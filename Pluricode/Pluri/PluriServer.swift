import Foundation
import Network
import Observation

@MainActor
@Observable
final class PluriServer {
    static let defaultPort = 8787
    private static let enabledKey = "pluriServerEnabled"
    private static let tokenKey = "pluriServerToken"

    private(set) var isRunning = false
    private(set) var lastError: String?

    var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            if enabled { start() } else { stop() }
        }
    }

    let port: Int
    let token: String

    private let backend: LocalPluriBackend
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: NWConnection] = [:]

    init(backend: LocalPluriBackend) {
        self.backend = backend
        self.port = Self.defaultPort
        self.enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        if let stored = KeychainStore.string(for: Self.tokenKey) {
            self.token = stored
        } else {
            let fresh = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
            KeychainStore.set(fresh, for: Self.tokenKey)
            self.token = fresh
        }
        if enabled { start() }
    }

    var pairing: PluriPairing {
        PluriPairing(host: Self.localAddresses().first ?? "127.0.0.1", port: port, token: token)
    }

    func start() {
        guard listener == nil else { return }
        lastError = nil
        let params = NWParameters(tls: nil)
        params.allowLocalEndpointReuse = true
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        do {
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: UInt16(port))!)
            listener.stateUpdateHandler = { state in
                MainActor.assumeIsolated { self.handleListenerState(state) }
            }
            listener.newConnectionHandler = { connection in
                MainActor.assumeIsolated { self.accept(connection) }
            }
            self.listener = listener
            listener.start(queue: .main)
            armTracking()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        for connection in clients.values { connection.cancel() }
        clients.removeAll()
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isRunning = true
        case .failed(let error):
            lastError = error.localizedDescription
            isRunning = false
            listener = nil
        case .cancelled:
            isRunning = false
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            MainActor.assumeIsolated {
                if case .cancelled = state { self.drop(connection) }
                if case .failed = state { self.drop(connection) }
            }
        }
        connection.start(queue: .main)
        receive(on: connection, authenticated: false)
    }

    private func drop(_ connection: NWConnection) {
        clients.removeValue(forKey: ObjectIdentifier(connection))
    }

    private func receive(on connection: NWConnection, authenticated: Bool) {
        connection.receiveMessage { [weak self] data, context, _, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
                let isClose = metadata?.opcode == .close
                var nextAuthenticated = authenticated
                if let data, !data.isEmpty {
                    nextAuthenticated = self.handle(data, on: connection, authenticated: authenticated)
                }
                if error == nil, !isClose {
                    self.receive(on: connection, authenticated: nextAuthenticated)
                } else {
                    connection.cancel()
                    self.drop(connection)
                }
            }
        }
    }

    private struct Auth: Decodable { let token: String }

    private func handle(_ data: Data, on connection: NWConnection, authenticated: Bool) -> Bool {
        if !authenticated {
            guard let auth = try? JSONDecoder().decode(Auth.self, from: data), auth.token == token else {
                connection.cancel()
                return false
            }
            clients[ObjectIdentifier(connection)] = connection
            sendState(to: connection)
            return true
        }
        guard let message = try? JSONDecoder().decode(PluriClientMessage.self, from: data) else { return true }
        apply(message)
        return true
    }

    private func apply(_ message: PluriClientMessage) {
        switch message {
        case .send(let text): backend.send(text)
        case .interrupt: backend.interrupt()
        case .clear: backend.clearConversation()
        case .approveProposal: backend.approveProposal()
        case .declineProposal: backend.declineProposal()
        case .reply(let taskID, let text):
            if let task = backend.tasks.first(where: { $0.id == taskID }) { backend.reply(to: task, text: text) }
        case .redispatch(let taskID):
            if let task = backend.tasks.first(where: { $0.id == taskID }) { backend.redispatch(task) }
        case .focusPane(let taskID):
            if let task = backend.tasks.first(where: { $0.id == taskID }) { backend.focusWorkerPane(task) }
        }
    }

    private func currentState() -> PluriChatState {
        let tasks = backend.tasks
        let live = Set(tasks.filter { backend.hasLiveWorker($0) }.map(\.id))
        return PluriChatState(
            blocks: backend.blocks,
            isRunning: backend.isRunning,
            tasks: tasks,
            proposal: backend.proposal,
            liveWorkers: live
        )
    }

    private func armTracking() {
        withObservationTracking {
            _ = currentState()
        } onChange: {
            Task { @MainActor in
                guard self.listener != nil else { return }
                self.broadcastState()
                self.armTracking()
            }
        }
    }

    private func broadcastState() {
        guard !clients.isEmpty else { return }
        guard let data = encode(currentState()) else { return }
        for connection in clients.values { send(data, to: connection) }
    }

    private func sendState(to connection: NWConnection) {
        guard let data = encode(currentState()) else { return }
        send(data, to: connection)
    }

    private func encode(_ state: PluriChatState) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(PluriServerMessage.state(state))
    }

    private func send(_ data: Data, to connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "state", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
    }

    static func localAddresses() -> [String] {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let sa = ptr.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(sa.pointee.sa_len)
            if getnameinfo(sa, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let address = String(cString: host)
                if !address.isEmpty { addresses.append(address) }
            }
        }
        return addresses.sorted { lhs, rhs in lhs.hasPrefix("100.") && !rhs.hasPrefix("100.") }
    }
}
