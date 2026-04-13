import Foundation
import SwiftTerm

enum AgentLauncher {
    static func launch(
        agent: AgentDefinition,
        in session: TerminalSession,
        role: TerminalNodeData.Role?,
        worktreePath: String?
    ) {
        if let role, let path = worktreePath {
            RoleInjector.inject(role: role, method: agent.roleInjection, worktreePath: path)
        }

        let command = agent.buildCommand()
        let data = Array("\(command)\n".utf8)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            session.terminalView.process?.send(data: data[...])
        }
    }
}
