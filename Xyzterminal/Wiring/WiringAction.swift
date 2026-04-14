import Foundation

enum WiringAction {
    static func send(edge: Edge, document: CanvasDocument, sessions: [UUID: TerminalSession]) {
        guard let sourceNode = document.nodes[edge.sourceID],
              let targetSession = sessions[edge.targetID],
              targetSession.terminalView.process != nil else { return }

        let (worktreePath, branchName): (String?, String?) = {
            if case .terminal(let data) = sourceNode.kind { return (data.worktreePath, data.branchName) }
            return (nil, nil)
        }()
        let edgeType = edge.edgeType
        let edgeID = edge.id

        Task.detached {
            let diff = await gatherDiff(worktreePath: worktreePath)
            let prompt = formatPrompt(edgeType: edgeType, branch: branchName, diff: diff, worktreePath: worktreePath)

            await MainActor.run {
                guard let process = targetSession.terminalView.process else { return }
                let bytes = Array("\(prompt)\n".utf8)
                process.send(data: bytes[...])

                let payload = EdgePayload(
                    id: UUID(),
                    timestamp: Date(),
                    summary: "\(edgeType.rawValue): \(branchName ?? "unknown branch")",
                    branchRef: branchName
                )
                document.edges[edgeID]?.payloadLog.append(payload)
                document.scheduleSave()
            }
        }
    }

    private static func gatherDiff(worktreePath: String?) async -> String? {
        guard let path = worktreePath else { return nil }

        if let diff = try? runGit(in: path, args: ["diff", "--stat", "HEAD~5..HEAD"]),
           !diff.isEmpty {
            return diff
        }
        return try? runGit(in: path, args: ["diff", "--stat"])
    }

    private static func formatPrompt(edgeType: EdgeType, branch: String?, diff: String?, worktreePath: String?) -> String {
        let branch = branch ?? "unknown"
        let diff = diff ?? "No changes detected"

        switch edgeType {
        case .handsOffTo:
            return """
            # Handoff from branch: \(branch)

            The previous terminal has completed work on branch `\(branch)`. Here is a summary of the changes:

            ```
            \(diff)
            ```

            Please continue the work. The worktree for the source branch is at: \(worktreePath ?? "unknown")
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
