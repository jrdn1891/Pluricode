import Foundation
import Observation

@Observable
final class StatsService {
    var commits: Int = 0
    var additions: Int = 0
    var deletions: Int = 0
    var prsMerged: Int = 0
    var lastUpdated: Date?
    var isLoading: Bool = false
    var ghAvailable: Bool = true

    private let repoStore: RepoStore

    init(repoStore: RepoStore) {
        self.repoStore = repoStore
        startPolling()
    }

    private func startPolling() {
        Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    @MainActor
    func refresh() async {
        if isLoading { return }
        isLoading = true
        let repos = repoStore.repos.map { $0.path }
        let dayStart = Calendar.current.startOfDay(for: Date())
        let snapshot = await Task.detached { Self.collect(repoPaths: repos, since: dayStart) }.value
        commits = snapshot.commits
        additions = snapshot.additions
        deletions = snapshot.deletions
        prsMerged = snapshot.prsMerged
        ghAvailable = snapshot.ghAvailable
        lastUpdated = Date()
        isLoading = false
    }

    struct Snapshot: Sendable {
        var commits: Int
        var additions: Int
        var deletions: Int
        var prsMerged: Int
        var ghAvailable: Bool
    }

    nonisolated private static func collect(repoPaths: [URL], since: Date) -> Snapshot {
        var commits = 0
        var additions = 0
        var deletions = 0

        let isoSince = ISO8601DateFormatter().string(from: since)

        for path in repoPaths {
            guard FileManager.default.fileExists(atPath: path.path) else { continue }
            guard let email = gitEmail(at: path), !email.isEmpty else { continue }

            guard let result = try? ProcessRunner.run("git", args: [
                "-C", path.path,
                "log",
                "--author=\(email)",
                "--since=\(isoSince)",
                "--all",
                "--no-merges",
                "--pretty=format:COMMIT",
                "--numstat"
            ]), result.status == 0 else { continue }

            for line in result.stdout.components(separatedBy: "\n") {
                if line == "COMMIT" {
                    commits += 1
                    continue
                }
                if line.isEmpty { continue }
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard parts.count >= 2 else { continue }
                additions += Int(parts[0]) ?? 0
                deletions += Int(parts[1]) ?? 0
            }
        }

        let pr = collectPRs(since: since)
        return Snapshot(
            commits: commits,
            additions: additions,
            deletions: deletions,
            prsMerged: pr.count,
            ghAvailable: pr.ghAvailable
        )
    }

    nonisolated private static func gitEmail(at repo: URL) -> String? {
        guard let result = try? ProcessRunner.run("git", args: [
            "-C", repo.path, "config", "user.email"
        ]), result.status == 0 else { return nil }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated private static func collectPRs(since: Date) -> (count: Int, ghAvailable: Bool) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        let day = formatter.string(from: since)

        guard let result = try? ProcessRunner.run("gh", args: [
            "search", "prs",
            "--author=@me",
            "--merged",
            "--merged-at=>=\(day)",
            "--limit", "100",
            "--json", "number"
        ]) else { return (0, true) }

        if result.executableMissing { return (0, false) }
        guard result.status == 0 else { return (0, true) }

        guard let data = result.stdout.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return (0, true)
        }
        return (array.count, true)
    }
}
