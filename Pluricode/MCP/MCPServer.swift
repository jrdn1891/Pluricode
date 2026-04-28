import Foundation
import Network

struct MCPEndpoint: Sendable {
    let port: UInt16
    let token: String
    let workspaceID: UUID
    let executablePath: String
}

final class MCPServer: @unchecked Sendable {
    let token: String
    let workspaceID: UUID
    weak var workspace: Workspace?

    private let listener: NWListener
    private let queue = DispatchQueue(label: "pluricode.mcp.server", qos: .userInitiated)
    private var connections: [ObjectIdentifier: ConnectionState] = [:]
    private var boundPort: UInt16 = 0
    private var readyContinuations: [CheckedContinuation<UInt16, Error>] = []

    init(workspace: Workspace) throws {
        self.workspace = workspace
        self.workspaceID = workspace.id
        self.token = UUID().uuidString
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        self.listener = try NWListener(using: params, on: .any)
        self.listener.stateUpdateHandler = { [weak self] state in
            self?.handleListenerState(state)
        }
        self.listener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        self.listener.start(queue: queue)
    }

    deinit {
        listener.cancel()
        for c in connections.values { c.connection.cancel() }
    }

    func awaitReady() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { cont in
            queue.async { [weak self] in
                guard let self else {
                    cont.resume(throwing: CancellationError())
                    return
                }
                if self.boundPort != 0 {
                    cont.resume(returning: self.boundPort)
                } else {
                    self.readyContinuations.append(cont)
                }
            }
        }
    }

    func endpoint() async throws -> MCPEndpoint {
        let port = try await awaitReady()
        return MCPEndpoint(
            port: port,
            token: token,
            workspaceID: workspaceID,
            executablePath: Bundle.main.executablePath ?? CommandLine.arguments[0]
        )
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener.port?.rawValue else { return }
            boundPort = port
            let conts = readyContinuations
            readyContinuations.removeAll()
            for c in conts { c.resume(returning: port) }
        case .failed(let err):
            let conts = readyContinuations
            readyContinuations.removeAll()
            for c in conts { c.resume(throwing: err) }
        default: break
        }
    }

    private func accept(_ conn: NWConnection) {
        let state = ConnectionState(connection: conn, server: self)
        let key = ObjectIdentifier(conn)
        connections[key] = state
        conn.stateUpdateHandler = { [weak self, weak state] s in
            guard let self, let state else { return }
            switch s {
            case .ready:
                state.beginReceive()
            case .failed, .cancelled:
                self.queue.async { self.connections.removeValue(forKey: key) }
            default: break
            }
        }
        conn.start(queue: queue)
    }
}

private final class ConnectionState {
    let connection: NWConnection
    weak var server: MCPServer?
    var buffer = Data()
    var authenticated = false
    var callerWorktreeBranch: String?

    init(connection: NWConnection, server: MCPServer) {
        self.connection = connection
        self.server = server
    }

    func beginReceive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.processBuffer()
            }
            if let _ = error {
                self.connection.cancel()
                return
            }
            if isComplete {
                self.connection.cancel()
                return
            }
            self.beginReceive()
        }
    }

    private func processBuffer() {
        let lines = MCPFraming.splitLines(buffer: &buffer)
        for line in lines {
            handle(line: line)
        }
    }

    private func handle(line: Data) {
        if !authenticated {
            guard let obj = try? MCPFraming.decoder.decode(JSONValue.self, from: line),
                  obj["type"]?.stringValue == "hello",
                  let token = obj["token"]?.stringValue,
                  let server,
                  token == server.token else {
                connection.cancel()
                return
            }
            authenticated = true
            if let branch = obj["worktree"]?.stringValue, !branch.isEmpty {
                callerWorktreeBranch = branch
            }
            return
        }
        guard let request = try? MCPFraming.decoder.decode(JSONRPCRequest.self, from: line) else {
            send(JSONRPCResponse(id: nil, error: .parseError))
            return
        }
        let caller = callerWorktreeBranch
        Task { @MainActor [weak self] in
            await self?.dispatch(request, callerWorktreeBranch: caller)
        }
    }

    @MainActor
    private func dispatch(_ request: JSONRPCRequest, callerWorktreeBranch: String?) async {
        guard let server, let workspace = server.workspace else {
            send(JSONRPCResponse(id: request.id, error: .application("Workspace gone")))
            return
        }
        let tools = MCPTools(workspace: workspace, callerWorktreeBranch: callerWorktreeBranch)
        do {
            let result = try await tools.handle(method: request.method, params: request.params)
            if let id = request.id {
                send(JSONRPCResponse(id: id, result: result))
            }
        } catch let err as JSONRPCError {
            send(JSONRPCResponse(id: request.id, error: err))
        } catch {
            send(JSONRPCResponse(id: request.id, error: .application("\(error)")))
        }
    }

    private func send<T: Encodable>(_ value: T) {
        guard let data = try? MCPFraming.encode(value) else { return }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }
}
