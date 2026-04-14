import Foundation
import Network

final class MCPServer {
    let document: CanvasDocument
    weak var terminalManager: TerminalManager?
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private(set) var port: UInt16 = 0
    var onPortReady: (() -> Void)?

    init(document: CanvasDocument) {
        self.document = document
    }

    deinit { stop() }

    func start() {
        do {
            listener = try NWListener(using: .tcp, on: .any)
        } catch { return }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.stateUpdateHandler = { [weak self] state in
            if case .ready = state, let port = self?.listener?.port {
                self?.port = port.rawValue
                self?.onPortReady?()
                self?.onPortReady = nil
            }
        }

        listener?.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        connections.forEach { $0.cancel() }
        connections.removeAll()
    }

    private func handleConnection(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: .main)
        readLine(from: connection)
    }

    private func readLine(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self, let data, !data.isEmpty else {
                if isComplete { self?.removeConnection(connection) }
                return
            }

            if let request = String(data: data, encoding: .utf8) {
                for line in request.components(separatedBy: "\n") where !line.isEmpty {
                    let response = MCPToolHandlers.handle(line, document: self.document, sessions: self.terminalManager?.sessions ?? [:])
                    let responseData = Data((response + "\n").utf8)
                    connection.send(content: responseData, completion: .contentProcessed { _ in })
                }
            }

            self.readLine(from: connection)
        }
    }

    private func removeConnection(_ connection: NWConnection) {
        connection.cancel()
        connections.removeAll { $0 === connection }
    }
}
