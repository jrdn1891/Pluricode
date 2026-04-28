import Foundation
import SwiftUI
import simd

enum MCPRole: String, Codable, CaseIterable {
    case orchestrator
    case worker
    case none

    var label: String {
        switch self {
        case .orchestrator: "Orchestrator"
        case .worker: "Worker"
        case .none: "None"
        }
    }

    var canSpawn: Bool { self == .orchestrator }
    var exposesMCP: Bool { self != .none }
}

struct AgentProfile: Identifiable, Codable {
    let id: UUID
    var name: String
    var instructions: String
    var agentDefinition: String
    var color: SIMD4<Float>
    var mcpRole: MCPRole

    var swiftUIColor: Color {
        Color(red: Double(color.x), green: Double(color.y), blue: Double(color.z), opacity: Double(color.w))
    }

    enum CodingKeys: String, CodingKey {
        case id, name, instructions, agentDefinition, color, mcpRole
    }

    init(
        id: UUID,
        name: String,
        instructions: String,
        agentDefinition: String,
        color: SIMD4<Float>,
        mcpRole: MCPRole = .none
    ) {
        self.id = id
        self.name = name
        self.instructions = instructions
        self.agentDefinition = agentDefinition
        self.color = color
        self.mcpRole = mcpRole
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        instructions = try c.decode(String.self, forKey: .instructions)
        agentDefinition = try c.decode(String.self, forKey: .agentDefinition)
        color = try c.decode(SIMD4<Float>.self, forKey: .color)
        mcpRole = try c.decodeIfPresent(MCPRole.self, forKey: .mcpRole) ?? .none
    }

    static let defaults: [AgentProfile] = [
        AgentProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Architect",
            instructions: """
            # Role: Architect
            You are the architect for this project. Focus on:
            - High-level design and system structure
            - Breaking down requirements into implementation tasks
            - Identifying dependencies and risks
            - Making technology and pattern decisions
            Do not write implementation code. Produce plans, diagrams, and task breakdowns.

            You have access to Pluricode workspace tools via MCP. Use them to:
            - `spawn_terminal` to delegate a subtask to a fresh worktree+terminal
            - `list_worktrees` / `list_panes` / `list_profiles` to inspect the workspace
            - `send_prompt` to nudge another running agent
            Pluri will gate spawn requests through the user unless they grant standing approval.
            """,
            agentDefinition: "Claude Code",
            color: SIMD4(0.6, 0.4, 1.0, 1.0),
            mcpRole: .orchestrator
        ),
        AgentProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Coder",
            instructions: """
            # Role: Coder
            You are the implementation engineer. Focus on:
            - Writing clean, production-quality code
            - Following existing patterns in the codebase
            - Keeping changes minimal and focused
            - Running tests after changes
            """,
            agentDefinition: "Claude Code",
            color: SIMD4(0.2, 0.8, 0.4, 1.0),
            mcpRole: .none
        ),
        AgentProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "Reviewer",
            instructions: """
            # Role: Reviewer
            You are the code reviewer. Focus on:
            - Reading diffs carefully and thoroughly
            - Identifying bugs, edge cases, and security issues
            - Checking for consistency with existing patterns
            - Providing specific, actionable feedback
            Do not make changes yourself. Only review and comment.
            """,
            agentDefinition: "Claude Code",
            color: SIMD4(1.0, 0.6, 0.2, 1.0),
            mcpRole: .none
        ),
        AgentProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            name: "Tester",
            instructions: """
            # Role: Tester
            You are the test engineer. Focus on:
            - Writing comprehensive test cases
            - Testing edge cases and error paths
            - Running the full test suite and reporting results
            - Identifying gaps in test coverage
            """,
            agentDefinition: "Claude Code",
            color: SIMD4(0.2, 0.6, 1.0, 1.0),
            mcpRole: .none
        ),
    ]
}
