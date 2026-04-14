import Foundation
import Observation

struct RepoEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var path: URL
    var addedAt: Date

    init(path: URL) {
        self.id = UUID()
        self.name = path.lastPathComponent
        self.path = path
        self.addedAt = Date()
    }
}

@Observable
final class RepoStore {
    var repos: [RepoEntry] = []
    var selectedRepoID: UUID?

    private static let reposKey = "repoEntries"
    private static let selectedKey = "selectedRepoID"

    var selectedRepo: RepoEntry? {
        guard let id = selectedRepoID else { return nil }
        return repos.first { $0.id == id }
    }

    init() {
        load()
    }

    @discardableResult
    func addRepo(_ url: URL) -> RepoEntry {
        if let existing = repos.first(where: { $0.path.standardizedFileURL == url.standardizedFileURL }) {
            selectedRepoID = existing.id
            save()
            return existing
        }
        let entry = RepoEntry(path: url)
        repos.append(entry)
        selectedRepoID = entry.id
        save()
        return entry
    }

    func removeRepo(id: UUID) {
        repos.removeAll { $0.id == id }
        if selectedRepoID == id {
            selectedRepoID = repos.first?.id
        }
        save()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(repos) else { return }
        UserDefaults.standard.set(data, forKey: Self.reposKey)
        if let id = selectedRepoID {
            UserDefaults.standard.set(id.uuidString, forKey: Self.selectedKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.selectedKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.reposKey),
           let decoded = try? JSONDecoder().decode([RepoEntry].self, from: data) {
            repos = decoded
        }
        if let str = UserDefaults.standard.string(forKey: Self.selectedKey),
           let id = UUID(uuidString: str) {
            selectedRepoID = id
        }
    }
}
