import Foundation

enum MCPBridge {
    static func run() {
        let args = CommandLine.arguments
        guard let portIdx = args.firstIndex(of: "--port"),
              args.count > portIdx + 1,
              let port = UInt16(args[portIdx + 1]),
              let nodeIdx = args.firstIndex(of: "--node-id"),
              args.count > nodeIdx + 1
        else {
            fputs("Usage: --mcp-bridge --port PORT --node-id ID\n", stderr)
            exit(1)
        }
        let nodeID = args[nodeIdx + 1]

        let fd = connectToApp(port: port)
        guard fd >= 0 else {
            fputs("Failed to connect to Xyzterminal app\n", stderr)
            exit(1)
        }

        setbuf(stdout, nil)

        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let id = json["id"]
            let method = json["method"] as? String

            if id == nil && method != nil {
                continue
            }

            guard let id else { continue }

            switch method {
            case "initialize":
                respond(id: id, result: initializeResult())
            case "tools/list":
                respond(id: id, result: toolsList())
            case "tools/call":
                let params = json["params"] as? [String: Any] ?? [:]
                let result = handleToolCall(params, nodeID: nodeID, socketFD: fd)
                respond(id: id, result: result)
            default:
                respondError(id: id, code: -32601, message: "Method not found: \(method ?? "nil")")
            }
        }

        close(fd)
    }

    private static func initializeResult() -> [String: Any] {
        [
            "protocolVersion": "2024-11-05",
            "capabilities": ["tools": [:]],
            "serverInfo": ["name": "xyzterminal", "version": "0.1.0"]
        ]
    }

    private static func toolsList() -> [String: Any] {
        [
            "tools": [
                toolDef(
                    name: "update_task",
                    description: "Update the status and summary of a task card on the Xyzterminal canvas",
                    properties: [
                        "task_id": ["type": "string", "description": "UUID of the task card"],
                        "status": ["type": "string", "enum": ["draft", "ready", "inProgress", "done", "failed"]],
                        "summary": ["type": "string", "description": "Summary text to set as the task body"]
                    ],
                    required: ["task_id"]
                ),
                toolDef(
                    name: "create_task",
                    description: "Create a new task card on the Xyzterminal canvas",
                    properties: [
                        "title": ["type": "string"],
                        "body": ["type": "string"]
                    ],
                    required: ["title"]
                ),
                toolDef(
                    name: "list_tasks",
                    description: "List all task cards on the Xyzterminal canvas",
                    properties: [:],
                    required: []
                )
            ]
        ]
    }

    private static func toolDef(name: String, description: String, properties: [String: Any], required: [String]) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": [
                "type": "object",
                "properties": properties,
                "required": required
            ]
        ]
    }

    private static func handleToolCall(_ params: [String: Any], nodeID: String, socketFD: Int32) -> [String: Any] {
        let toolName = params["name"] as? String ?? ""
        let arguments = params["arguments"] as? [String: Any] ?? [:]

        var args: [String: String] = [:]
        for (k, v) in arguments {
            args[k] = "\(v)"
        }

        let request: [String: Any] = [
            "nodeID": nodeID,
            "tool": toolName,
            "args": args
        ]

        guard let requestData = try? JSONSerialization.data(withJSONObject: request),
              var requestStr = String(data: requestData, encoding: .utf8) else {
            return errorContent("Failed to encode request")
        }

        requestStr += "\n"
        let bytes = Array(requestStr.utf8)
        let written = write(socketFD, bytes, bytes.count)
        guard written == bytes.count else {
            return errorContent("Failed to send request to app")
        }

        var buffer = [UInt8](repeating: 0, count: 65536)
        let n = read(socketFD, &buffer, buffer.count)
        guard n > 0, let responseStr = String(bytes: buffer[..<Int(n)], encoding: .utf8) else {
            return errorContent("No response from app")
        }

        return [
            "content": [
                ["type": "text", "text": responseStr.trimmingCharacters(in: .whitespacesAndNewlines)]
            ]
        ]
    }

    private static func errorContent(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": message]], "isError": true]
    }

    private static func respond(id: Any, result: [String: Any]) {
        let response: [String: Any] = ["jsonrpc": "2.0", "id": id, "result": result]
        writeLine(response)
    }

    private static func respondError(id: Any, code: Int, message: String) {
        let response: [String: Any] = [
            "jsonrpc": "2.0", "id": id,
            "error": ["code": code, "message": message]
        ]
        writeLine(response)
    }

    private static func writeLine(_ json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              var str = String(data: data, encoding: .utf8) else { return }
        str += "\n"
        fputs(str, stdout)
    }

    private static func connectToApp(port: UInt16) -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        return result == 0 ? fd : -1
    }
}
