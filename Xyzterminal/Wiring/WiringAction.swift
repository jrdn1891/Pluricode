import Foundation

enum WiringAction {
    static func send(edge: Edge, document: CanvasDocument, sessions: [UUID: TerminalSession]) {
        guard let sourceNode = document.nodes[edge.sourceID],
              let targetNode = document.nodes[edge.targetID],
              let targetSession = sessions[edge.targetID] else { return }

        let context = gatherContext(from: sourceNode, sessions: sessions)
        let prompt = formatPrompt(edgeType: edge.edgeType, context: context, sourceNode: sourceNode)

        let bytes = Array("\(prompt)\n".utf8)
        targetSession.terminalView.process?.send(data: bytes[...])

        let payload = EdgePayload(
            id: UUID(),
            timestamp: Date(),
            summary: "\(edge.edgeType.rawValue): \(context.branch ?? "unknown branch")",
            branchRef: context.branch
        )
        document.edges[edge.id]?.payloadLog.append(payload)
        document.scheduleSave()
    }

    private struct Context {
        var branch: String?
        var diff: String?
        var worktreePath: String?
    }

    private static func gatherContext(from node: CanvasNode, sessions: [UUID: TerminalSession]) -> Context {
        guard case .terminal(let data) = node.kind else {
            return Context()
        }

        var ctx = Context(branch: data.branchName, worktreePath: data.worktreePath)

        if let path = data.worktreePath {
            let diffResult = try? runGit(in: path, args: ["diff", "--stat", "HEAD~5..HEAD"])
            ctx.diff = diffResult?.isEmpty == false ? diffResult : nil

            if ctx.diff == nil {
                let statusResult = try? runGit(in: path, args: ["diff", "--stat"])
                ctx.diff = statusResult
            }
        }

        return ctx
    }

    private static func formatPrompt(edgeType: EdgeType, context: Context, sourceNode: CanvasNode) -> String {
        let branch = context.branch ?? "unknown"
        let diff = context.diff ?? "No changes detected"

        switch edgeType {
        case .handsOffTo:
            return """
            # Handoff from branch: \(branch)

            The previous terminal has completed work on branch `\(branch)`. Here is a summary of the changes:

            ```
            \(diff)
            ```

            Please continue the work. The worktree for the source branch is at: \(context.worktreePath ?? "unknown")
            You can cherry-pick or merge changes from `\(branch)` into your branch.
            """

        case .reviews:
            return """
            # Code Review Request — branch: \(branch)

            Please review the following changes from branch `\(branch)`:

            ```
            \(diff)
            ```

            Provide specific, actionable feedback on code quality, bugs, and potential issues.
            """

        default:
            return "Context from \(branch):\n\(diff)"
        }
    }

    private static func runGit(in path: String, args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", path] + args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
