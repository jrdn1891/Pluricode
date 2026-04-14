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
            if let profileID = termData.profileID,
               let profile = document.agentProfiles[profileID] {
                lines.append("Role: \(profile.name)")
            }
            if let branch = termData.branchName {
                lines.append("Branch: `\(branch)`")
            }
            if let path = termData.worktreePath {
                lines.append("Worktree: \(path)")
            }
        }

        let predecessors = document.edges.values
            .filter { $0.targetID == taskID && ($0.edgeType == .blocks || $0.edgeType == .flowsTo) }
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

        let pipeline = walkPipeline(taskID: taskID, document: document)
        if pipeline.count > 1 {
            lines.append("")
            lines.append("## Workflow Context")
            let currentIndex = pipeline.firstIndex(of: taskID)
            lines.append("You are step \(currentIndex.map { $0 + 1 } ?? 0) of \(pipeline.count) in this pipeline:")
            for (i, stepID) in pipeline.enumerated() {
                guard let stepNode = document.nodes[stepID],
                      case .taskCard(let stepData) = stepNode.kind else { continue }
                let marker = stepID == taskID ? " <- you are here" : ""
                let outcomeStr = stepData.outcome.isEmpty ? "" : " -> \(stepData.outcome)"
                lines.append("\(i + 1). [\(stepData.status.rawValue)] \"\(stepData.title)\"\(outcomeStr)\(marker)")
            }

            let downstream = document.edges.values.filter {
                $0.sourceID == taskID && ($0.edgeType == .flowsTo || $0.edgeType == .blocks)
            }
            for edge in downstream {
                guard let targetNode = document.nodes[edge.targetID],
                      case .taskCard(let targetData) = targetNode.kind else { continue }
                let assignedProfile = document.edges.values
                    .first { $0.sourceID == edge.targetID && $0.edgeType == .assignedTo }
                    .flatMap { document.nodes[$0.targetID] }
                    .flatMap { node -> String? in
                        if case .terminal(let d) = node.kind, let pid = d.profileID {
                            return document.agentProfiles[pid]?.name
                        }
                        return nil
                    }
                let agent = assignedProfile.map { " by a \($0) agent" } ?? ""
                let cond = edge.condition.map { " (when outcome = \"\($0)\")" } ?? ""
                lines.append("After you complete this, \"\(targetData.title)\" will be handled\(agent)\(cond)")
            }
        }

        lines.append("")
        lines.append("When finished, report completion via the `xyzterminal` MCP tool `update_task`:")
        lines.append("- task_id: \(taskID.uuidString)")
        lines.append("- status: \"done\" or \"failed\"")
        lines.append("- outcome: a routing keyword (e.g. \"approved\", \"needs_changes\", \"needs_human_review\")")
        lines.append("- summary: a brief summary of what you did")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    private static func walkPipeline(taskID: UUID, document: CanvasDocument) -> [UUID] {
        var root = taskID
        var visited: Set<UUID> = [root]
        while let edge = document.edges.values.first(where: {
            $0.targetID == root && ($0.edgeType == .flowsTo || $0.edgeType == .blocks)
        }), !visited.contains(edge.sourceID) {
            if case .taskCard = document.nodes[edge.sourceID]?.kind {
                visited.insert(edge.sourceID)
                root = edge.sourceID
            } else {
                break
            }
        }

        var ordered: [UUID] = []
        var queue = [root]
        var seen: Set<UUID> = []
        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard seen.insert(current).inserted else { continue }
            guard case .taskCard = document.nodes[current]?.kind else { continue }
            ordered.append(current)
            let downstream = document.edges.values.filter {
                $0.sourceID == current && ($0.edgeType == .flowsTo || $0.edgeType == .blocks)
            }
            for edge in downstream {
                if !seen.contains(edge.targetID) { queue.append(edge.targetID) }
            }
        }
        return ordered
    }

    static func dispatchDownstream(completedTaskID: UUID, document: CanvasDocument, sessions: [UUID: TerminalSession]) {
        guard let completedNode = document.nodes[completedTaskID],
              case .taskCard(let completedData) = completedNode.kind else { return }

        let downstreamEdges = document.edges.values.filter {
            $0.sourceID == completedTaskID && ($0.edgeType == .blocks || $0.edgeType == .flowsTo)
        }

        for edge in downstreamEdges {
            if let condition = edge.condition, !condition.isEmpty {
                guard completedData.outcome == condition else { continue }
            }

            let targetID = edge.targetID

            if completedData.outcome == "needs_human_review" {
                if var targetNode = document.nodes[targetID],
                   case .taskCard(var data) = targetNode.kind {
                    data.transition(to: .flagged)
                    targetNode.kind = .taskCard(data)
                    document.nodes[targetID] = targetNode
                    document.scheduleSave()
                }
                continue
            }

            guard let targetNode = document.nodes[targetID],
                  case .taskCard(let data) = targetNode.kind,
                  data.status != .done, data.status != .inProgress else { continue }

            guard document.unresolvedBlockers(for: targetID).isEmpty else { continue }

            let assignmentEdge = document.edges.values.first {
                $0.sourceID == targetID && $0.edgeType == .assignedTo
            }

            if let terminalID = assignmentEdge?.targetID {
                if let termNode = document.nodes[terminalID],
                   case .terminal(let termData) = termNode.kind,
                   termData.status == .working {
                    var updated = data
                    updated.transition(to: .ready)
                    document.nodes[targetID]?.kind = .taskCard(updated)
                    document.scheduleSave()
                } else {
                    assign(taskID: targetID, terminalID: terminalID, document: document, sessions: sessions)
                }
            } else {
                var updated = data
                updated.transition(to: .ready)
                document.nodes[targetID]?.kind = .taskCard(updated)
                document.scheduleSave()
            }
        }
    }

    static func dispatchReady(document: CanvasDocument, sessions: [UUID: TerminalSession]) {
        for (taskID, node) in document.nodes {
            guard case .taskCard(let data) = node.kind, data.status == .ready else { continue }
            guard document.unresolvedBlockers(for: taskID).isEmpty else { continue }

            let assignmentEdge = document.edges.values.first {
                $0.sourceID == taskID && $0.edgeType == .assignedTo
            }
            guard let terminalID = assignmentEdge?.targetID else { continue }

            if let termNode = document.nodes[terminalID],
               case .terminal(let termData) = termNode.kind,
               termData.status != .working {
                assign(taskID: taskID, terminalID: terminalID, document: document, sessions: sessions)
            }
        }
    }
}
