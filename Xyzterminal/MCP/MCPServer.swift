import Foundation
import Network

final class MCPServer {
    let document: CanvasDocument
    weak var terminalManager: TerminalManager?
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var buffers: [ObjectIdentifier: Data] = [:]
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
        buffers.removeAll()
    }

    private func handleConnection(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: .main)
        receiveData(from: connection)
    }

    private func receiveData(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, _ in
            guard let self else { return }

            if let data, !data.isEmpty {
                let key = ObjectIdentifier(connection)
                var buffer = self.buffers[key] ?? Data()
                buffer.append(data)

                while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let lineData = buffer[buffer.startIndex..<newlineIndex]
                    buffer = Data(buffer[buffer.index(after: newlineIndex)...])

                    if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                        let response = MCPToolHandlers.handle(line, document: self.document, sessions: self.terminalManager?.sessions ?? [:])
                        let responseData = Data((response + "\n").utf8)
                        connection.send(content: responseData, completion: .contentProcessed { _ in })
                    }
                }

                self.buffers[key] = buffer
            }

            if isComplete {
                self.removeConnection(connection)
            } else {
                self.receiveData(from: connection)
            }
        }
    }

    private func removeConnection(_ connection: NWConnection) {
        connection.cancel()
        buffers.removeValue(forKey: ObjectIdentifier(connection))
        connections.removeAll { $0 === connection }
    }
}
