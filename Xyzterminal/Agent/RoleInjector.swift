import Foundation

enum ProfileInjector {
    static func inject(profile: AgentProfile, method: RoleInjectionMethod, worktreePath: String) {
        switch method {
        case .claudeMD:
            let path = URL(fileURLWithPath: worktreePath).appendingPathComponent("CLAUDE.md")
            try? profile.instructions.write(to: path, atomically: true, encoding: .utf8)
        case .systemPrompt, .envVar:
            break
        }
    }
}
