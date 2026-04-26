import Foundation

struct RepoConfig: Codable, Equatable {
    var startupScript: String?
    var devScript: String?

    init(startupScript: String? = nil, devScript: String? = nil) {
        self.startupScript = startupScript
        self.devScript = devScript
    }

    static func configURL(for repoPath: String) -> URL {
        URL(fileURLWithPath: repoPath)
            .appendingPathComponent(".pluricode", isDirectory: true)
            .appendingPathComponent("repo.json")
    }

    static func load(at repoPath: String) -> RepoConfig {
        let url = configURL(for: repoPath)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(RepoConfig.self, from: data) else {
            return RepoConfig()
        }
        return decoded
    }

    func save(at repoPath: String) {
        let url = Self.configURL(for: repoPath)
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
