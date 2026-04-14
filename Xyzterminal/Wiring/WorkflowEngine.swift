import Foundation

enum WorkflowEngine {
    static func assign(taskID: UUID, terminalID: UUID, document: CanvasDocument, sessions: [UUID: TerminalSession]) {
        guard document.unresolvedBlockers(for: taskID).isEmpty else { return }
        guard let node = document.nodes[taskID],
              case .taskCard(let taskData) = node.kind else { return }
        guard let session = sessions[terminalID],
              let process = session.terminalView.process else { return }

        let existingEdgeIDs = document.edges.values
            .filter { $0.sourceID == taskID && $0.edgeType == .assignedTo }
            .map(\.id)
        for edgeID in existingEdgeIDs {
            document.edges.removeValue(forKey: edgeID)
        }

        document.addEdge(from: taskID, to: terminalID, type: .assignedTo)

        var updatedTask = taskData
        updatedTask.transition(to: .inProgress)
        document.nodes[taskID]?.kind = .taskCard(updatedTask)

        let prompt = buildPrompt(taskData: taskData, taskID: taskID, terminalID: terminalID, document: document)
        let bytes = Array(prompt.utf8)
        process.send(data: bytes[...])

        document.scheduleSave()
    }

    static func buildPrompt(taskData: TaskCardData, taskID: UUID, terminalID: UUID, document: CanvasDocument) -> String {
        var lines = ["# Task: \(taskData.title)", ""]

        if !taskData.body.isEmpty {
            lines.append(taskData.body)
            lines.append("")
        }

        lines.append("## Context")
        if let projectPath = document.projectPath?.path {
            lines.append("Project: \(projectPath)")
        }
        if let termNode = document.nodes[terminalID],
           case .terminal(let termData) = termNode.kind {
            if let role = termData.role {
                lines.append("Role: \(role.rawValue)")
            }
            if let branch = termData.branchName {
                lines.append("Branch: `\(branch)`")
            }
            if let path = termData.worktreePath {
                lines.append("Worktree: \(path)")
            }
        }

        let predecessors = document.edges.values
            .filter { $0.targetID == taskID && $0.edgeType == .blocks }
            .compactMap { edge -> (String, TaskCardData)? in
                guard let node = document.nodes[edge.sourceID],
                      case .taskCard(let d) = node.kind else { return nil }
                return (edge.sourceID.uuidString, d)
            }

        let incomplete = predecessors.filter { $0.1.status != .done }
        if !incomplete.isEmpty {
            lines.append("")
            lines.append("Dependencies:")
            lines.append(contentsOf: incomplete.map { "- \($0.1.title) (\($0.1.status.rawValue))" })
        }

        let completed = predecessors.filter { $0.1.status == .done && !$0.1.result.isEmpty }
        if !completed.isEmpty {
            lines.append("")
            lines.append("## Predecessor Results")
            for (_, pred) in completed {
                lines.append("### \(pred.title)")
                lines.append(pred.result)
                lines.append("")
            }
        }

        lines.append("")
        lines.append("When finished, report completion via the `xyzterminal` MCP tool `update_task`:")
        lines.append("- task_id: \(taskID.uuidString)")
        lines.append("- status: \"done\" or \"failed\"")
        lines.append("- summary: a brief summary of what you did")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    static func dispatchDownstream(completedTaskID: UUID, document: CanvasDocument, sessions: [UUID: TerminalSession]) {
        let downstreamEdges = document.edges.values.filter {
            $0.sourceID == completedTaskID && $0.edgeType == .blocks
        }

        for edge in downstreamEdges {
            let targetID = edge.targetID
            guard let targetNode = document.nodes[targetID],
                  case .taskCard(let data) = targetNode.kind,
                  data.status != .done, data.status != .inProgress else { continue }

            guard document.unresolvedBlockers(for: targetID).isEmpty else { continue }

            let assignmentEdge = document.edges.values.first {
                $0.sourceID == targetID && $0.edgeType == .assignedTo
            }

            if let terminalID = assignmentEdge?.targetID {
                assign(taskID: targetID, terminalID: terminalID, document: document, sessions: sessions)
            } else {
                var updated = data
                updated.transition(to: .ready)
                document.nodes[targetID]?.kind = .taskCard(updated)
                document.scheduleSave()
            }
        }
    }
}
