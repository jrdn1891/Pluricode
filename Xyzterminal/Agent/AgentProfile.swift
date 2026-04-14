import Foundation
import simd

struct AgentProfile: Identifiable, Codable {
    let id: UUID
    var name: String
    var instructions: String
    var agentDefinition: String
    var color: SIMD4<Float>

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
            """,
            agentDefinition: "Claude Code",
            color: SIMD4(0.6, 0.4, 1.0, 1.0)
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
            color: SIMD4(0.2, 0.8, 0.4, 1.0)
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
            color: SIMD4(1.0, 0.6, 0.2, 1.0)
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
            color: SIMD4(0.2, 0.6, 1.0, 1.0)
        ),
    ]
}
