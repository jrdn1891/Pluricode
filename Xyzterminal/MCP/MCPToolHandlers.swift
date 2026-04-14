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

    static func handle(_ line: String, document: CanvasDocument, sessions: [UUID: TerminalSession]) -> String {
        guard let data = line.data(using: .utf8),
              let request = try? JSONDecoder().decode(Request.self, from: data) else {
            return encode(Response(success: false, error: "invalid request"))
        }

        let result: Response
        switch request.tool {
        case "update_task":
            result = updateTask(request.args, document: document, sessions: sessions)
        case "create_task":
            result = createTask(request.args, document: document, nearNodeID: request.nodeID)
        case "get_task":
            result = getTask(request.args, document: document)
        case "list_tasks":
            result = listTasks(document: document)
        case "request_review":
            result = requestReview(request.args, callerNodeID: request.nodeID, document: document, sessions: sessions)
        case "update_terminal_status":
            result = updateTerminalStatus(request.args, callerNodeID: request.nodeID, document: document, sessions: sessions)
        default:
            result = Response(success: false, error: "unknown tool: \(request.tool)")
        }

        return encode(result)
    }

    private static func updateTask(_ args: [String: String], document: CanvasDocument, sessions: [UUID: TerminalSession]) -> Response {
        guard let taskIDStr = args["task_id"],
              let taskID = UUID(uuidString: taskIDStr) else {
            return Response(success: false, error: "missing or invalid task_id")
        }

        guard var node = document.nodes[taskID],
              case .taskCard(var data) = node.kind else {
            return Response(success: false, error: "task not found")
        }

        let wasNotDone = data.status != .done
        if let statusStr = args["status"],
           let status = TaskCardData.Status(rawValue: statusStr) {
            data.transition(to: status)
        }
        if let summary = args["summary"] {
            data.result = summary
        }
        if let outcome = args["outcome"] {
            data.outcome = outcome
        }
        node.kind = .taskCard(data)
        document.nodes[taskID] = node
        document.scheduleSave()

        if wasNotDone && data.status == .done {
            WorkflowEngine.dispatchDownstream(completedTaskID: taskID, document: document, sessions: sessions)
        }

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
            size: NodeKind.taskCard(taskData).defaultSize,
            kind: .taskCard(taskData)
        )
        document.nodes[node.id] = node
        document.scheduleSave()

        return Response(success: true, data: ["task_id": node.id.uuidString])
    }

    private static func getTask(_ args: [String: String], document: CanvasDocument) -> Response {
        guard let taskIDStr = args["task_id"],
              let taskID = UUID(uuidString: taskIDStr) else {
            return Response(success: false, error: "missing or invalid task_id")
        }

        guard let node = document.nodes[taskID],
              case .taskCard(let data) = node.kind else {
            return Response(success: false, error: "task not found")
        }

        var entry: [String: String] = [
            "id": taskID.uuidString,
            "title": data.title,
            "status": data.status.rawValue,
            "body": data.body
        ]
        if !data.result.isEmpty { entry["result"] = data.result }
        if let started = data.startedAt { entry["started_at"] = started.ISO8601Format() }
        if let completed = data.completedAt { entry["completed_at"] = completed.ISO8601Format() }

        return Response(success: true, data: entry)
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

    private static func requestReview(_ args: [String: String], callerNodeID: String, document: CanvasDocument, sessions: [UUID: TerminalSession]) -> Response {
        guard let sourceID = UUID(uuidString: callerNodeID) else {
            return Response(success: false, error: "invalid caller node ID")
        }

        let reviewEdge = document.edges.values.first {
            $0.sourceID == sourceID && $0.edgeType == .reviews
        }

        guard let edge = reviewEdge else {
            return Response(success: false, error: "no reviews edge from this terminal")
        }

        guard sessions[edge.targetID] != nil else {
            return Response(success: false, error: "target terminal not active")
        }

        WiringAction.send(edge: edge, document: document, sessions: sessions)

        return Response(success: true, data: ["target_id": edge.targetID.uuidString])
    }

    private static func updateTerminalStatus(_ args: [String: String], callerNodeID: String, document: CanvasDocument, sessions: [UUID: TerminalSession]) -> Response {
        guard let nodeID = UUID(uuidString: callerNodeID),
              var node = document.nodes[nodeID],
              case .terminal(var data) = node.kind else {
            return Response(success: false, error: "terminal not found")
        }

        guard let statusStr = args["status"],
              let status = TerminalNodeData.Status(rawValue: statusStr) else {
            return Response(success: false, error: "invalid status")
        }

        data.status = status
        node.kind = .terminal(data)
        document.nodes[nodeID] = node
        document.scheduleSave()

        if status == .idle {
            WorkflowEngine.dispatchReady(document: document, sessions: sessions)
        }

        return Response(success: true)
    }

    private static func encode(_ response: Response) -> String {
        guard let data = try? JSONEncoder().encode(response),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }
}
