import Foundation

struct AgentDefinition: Identifiable, Codable {
    var id: String { name }
    var name: String
    var launchCommand: String
    var launchArgs: [String]
    var supportsMCP: Bool
    var roleInjection: RoleInjectionMethod

    static let claudeCode = AgentDefinition(
        name: "Claude Code",
        launchCommand: "claude",
        launchArgs: [],
        supportsMCP: true,
        roleInjection: .claudeMD
    )

    static let codex = AgentDefinition(
        name: "Codex",
        launchCommand: "codex",
        launchArgs: [],
        supportsMCP: false,
        roleInjection: .envVar
    )

    static let builtins: [AgentDefinition] = [.claudeCode, .codex]

    func buildCommand() -> String {
        ([launchCommand] + launchArgs).joined(separator: " ")
    }
}

enum RoleInjectionMethod: String, Codable {
    case claudeMD
    case systemPrompt
    case envVar
}
