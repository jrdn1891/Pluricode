import Foundation
import Network

enum MCPBridge {
    static func run(port: UInt16, workspaceID: String, token: String, worktree: String) -> Never {
        guard port > 0 else {
            FileHandle.standardError.write(Data("pluricode: invalid bridge port\n".utf8))
            exit(64)
        }

        let host = NWEndpoint.Host("127.0.0.1")
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let connection = NWConnection(host: host, port: nwPort, using: .tcp)
        let queue = DispatchQueue(label: "pluricode.mcp.bridge")
        let done = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var finished = false
        var exitCode: Int32 = 0

        let finish: (Int32) -> Void = { code in
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            exitCode = code
            connection.cancel()
            done.signal()
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let hello = "{\"type\":\"hello\",\"token\":\"\(token)\",\"workspace\":\"\(workspaceID)\",\"worktree\":\"\(worktree)\"}\n"
                connection.send(content: Data(hello.utf8), completion: .contentProcessed { _ in })
                startTCPReading(connection: connection, finish: finish)
                startStdinReading(connection: connection, finish: finish)
            case .failed(let err):
                FileHandle.standardError.write(Data("pluricode: connection failed: \(err)\n".utf8))
                finish(1)
            case .cancelled:
                finish(exitCode)
            default:
                break
            }
        }
        connection.start(queue: queue)
        done.wait()
        exit(exitCode)
    }

    private static func startTCPReading(connection: NWConnection, finish: @escaping (Int32) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
            if let data, !data.isEmpty {
                FileHandle.standardOutput.write(data)
            }
            if error != nil {
                finish(1)
                return
            }
            if isComplete {
                finish(0)
                return
            }
            startTCPReading(connection: connection, finish: finish)
        }
    }

    private static func startStdinReading(connection: NWConnection, finish: @escaping (Int32) -> Void) {
        let queue = DispatchQueue(label: "pluricode.mcp.bridge.stdin")
        queue.async {
            let stdin = FileHandle.standardInput
            while true {
                let chunk = stdin.availableData
                if chunk.isEmpty {
                    connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in })
                    finish(0)
                    return
                }
                connection.send(content: chunk, completion: .contentProcessed { _ in })
            }
        }
    }
}
