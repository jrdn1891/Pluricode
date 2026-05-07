import Foundation

struct WorktreeConfig: Codable, Equatable {
    var agentProfileID: UUID?
    var chatSessionID: UUID?

    init(agentProfileID: UUID? = nil, chatSessionID: UUID? = nil) {
        self.agentProfileID = agentProfileID
        self.chatSessionID = chatSessionID
    }

    static func configURL(for worktreePath: String) -> URL {
        URL(fileURLWithPath: worktreePath)
            .appendingPathComponent(".pluricode", isDirectory: true)
            .appendingPathComponent("worktree.json")
    }

    static func load(at worktreePath: String) -> WorktreeConfig {
        let url = configURL(for: worktreePath)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(WorktreeConfig.self, from: data) else {
            return WorktreeConfig()
        }
        return decoded
    }

    func save(at worktreePath: String) {
        let url = Self.configURL(for: worktreePath)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
