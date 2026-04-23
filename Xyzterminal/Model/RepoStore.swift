import Foundation
import Observation
import SwiftUI

enum RepoColor: String, CaseIterable, Codable {
    case blue, indigo, purple, pink, red, orange, yellow, green, teal, gray

    var swiftUIColor: Color {
        switch self {
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .gray: .gray
        }
    }

    var label: String {
        rawValue.capitalized
    }

    static func auto(for id: UUID) -> RepoColor {
        let all = Self.allCases
        var hasher = Hasher()
        hasher.combine(id)
        return all[abs(hasher.finalize()) % all.count]
    }
}

struct RepoEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var path: URL
    var addedAt: Date
    var color: RepoColor?

    var resolvedColor: RepoColor { color ?? .auto(for: id) }

    init(path: URL) {
        self.id = UUID()
        self.name = path.lastPathComponent
        self.path = path
        self.addedAt = Date()
        self.color = nil
    }

    enum CodingKeys: String, CodingKey { case id, name, path, addedAt, color }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        path = try c.decode(URL.self, forKey: .path)
        addedAt = try c.decode(Date.self, forKey: .addedAt)
        color = try c.decodeIfPresent(RepoColor.self, forKey: .color)
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

    func setColor(id: UUID, color: RepoColor?) {
        guard let idx = repos.firstIndex(where: { $0.id == id }) else { return }
        repos[idx].color = color
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
