import Foundation

enum MCPToolHandlers {
    struct Request: Codable {
        var nodeID: String
        var tool: String
        var args: [String: String]
    }

    struct Response: Codable {
        var success: Bool
        var data: [String: String]?
        var error: String?
    }

    static func handle(_ line: String, document: CanvasDocument) -> String {
        guard let data = line.data(using: .utf8),
              let request = try? JSONDecoder().decode(Request.self, from: data) else {
            return encode(Response(success: false, error: "invalid request"))
        }

        let result: Response
        switch request.tool {
        case "update_task":
            result = updateTask(request.args, document: document)
        case "create_task":
            result = createTask(request.args, document: document, nearNodeID: request.nodeID)
        case "list_tasks":
            result = listTasks(document: document)
        default:
            result = Response(success: false, error: "unknown tool: \(request.tool)")
        }

        return encode(result)
    }

    private static func updateTask(_ args: [String: String], document: CanvasDocument) -> Response {
        guard let taskIDStr = args["task_id"],
              let taskID = UUID(uuidString: taskIDStr) else {
            return Response(success: false, error: "missing or invalid task_id")
        }

        guard var node = document.nodes[taskID],
              case .taskCard(var data) = node.kind else {
            return Response(success: false, error: "task not found")
        }

        if let statusStr = args["status"],
           let status = TaskCardData.Status(rawValue: statusStr) {
            data.transition(to: status)
        }
        if let summary = args["summary"] {
            data.result = summary
        }
        node.kind = .taskCard(data)
        document.nodes[taskID] = node
        document.scheduleSave()

        return Response(success: true)
    }

    private static func createTask(_ args: [String: String], document: CanvasDocument, nearNodeID: String) -> Response {
        let title = args["title"] ?? "Untitled"
        let body = args["body"] ?? ""

        var position = document.camera.offset
        if let sourceID = UUID(uuidString: nearNodeID),
           let sourceNode = document.nodes[sourceID] {
            position = sourceNode.position + SIMD2<Float>(Float.random(in: 50...150), Float.random(in: -100...100))
        }

        let taskData = TaskCardData(title: title, body: body, status: .ready)
        let node = CanvasNode(
            id: UUID(),
            position: position,
            size: SIMD2<Float>(250, 100),
            kind: .taskCard(taskData)
        )
        document.nodes[node.id] = node
        document.scheduleSave()

        return Response(success: true, data: ["task_id": node.id.uuidString])
    }

    private static func listTasks(document: CanvasDocument) -> Response {
        var tasks: [[String: String]] = []
        for (id, node) in document.nodes {
            if case .taskCard(let data) = node.kind {
                var entry: [String: String] = [
                    "id": id.uuidString,
                    "title": data.title,
                    "status": data.status.rawValue
                ]
                if !data.result.isEmpty {
                    entry["result"] = data.result
                }
                tasks.append(entry)
            }
        }
        guard let jsonData = try? JSONEncoder().encode(tasks),
              let jsonStr = String(data: jsonData, encoding: .utf8) else {
            return Response(success: true, data: ["tasks": "[]"])
        }
        return Response(success: true, data: ["tasks": jsonStr])
    }

    private static func encode(_ response: Response) -> String {
        guard let data = try? JSONEncoder().encode(response),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }
}
