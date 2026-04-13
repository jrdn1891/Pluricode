import Foundation

enum RoleInjector {
    static func inject(role: TerminalNodeData.Role, method: RoleInjectionMethod, worktreePath: String) {
        switch method {
        case .claudeMD:
            let content = claudeMDContent(for: role)
            let path = URL(fileURLWithPath: worktreePath).appendingPathComponent("CLAUDE.md")
            try? content.write(to: path, atomically: true, encoding: .utf8)
        case .systemPrompt, .envVar:
            break
        }
    }

    private static func claudeMDContent(for role: TerminalNodeData.Role) -> String {
        switch role {
        case .architect:
            return """
            # Role: Architect
            You are the architect for this project. Focus on:
            - High-level design and system structure
            - Breaking down requirements into implementation tasks
            - Identifying dependencies and risks
            - Making technology and pattern decisions
            Do not write implementation code. Produce plans, diagrams, and task breakdowns.
            """
        case .coder:
            return """
            # Role: Coder
            You are the implementation engineer. Focus on:
            - Writing clean, production-quality code
            - Following existing patterns in the codebase
            - Keeping changes minimal and focused
            - Running tests after changes
            """
        case .reviewer:
            return """
            # Role: Reviewer
            You are the code reviewer. Focus on:
            - Reading diffs carefully and thoroughly
            - Identifying bugs, edge cases, and security issues
            - Checking for consistency with existing patterns
            - Providing specific, actionable feedback
            Do not make changes yourself. Only review and comment.
            """
        case .tester:
            return """
            # Role: Tester
            You are the test engineer. Focus on:
            - Writing comprehensive test cases
            - Testing edge cases and error paths
            - Running the full test suite and reporting results
            - Identifying gaps in test coverage
            """
        }
    }
}
