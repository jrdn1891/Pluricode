import Foundation
import Observation

enum Pin: Codable, Hashable {
    case repo(UUID)
    case worktree(repoID: UUID, branch: String)

    var id: String {
        switch self {
        case .repo(let id): return "r:\(id.uuidString)"
        case .worktree(let id, let branch): return "w:\(id.uuidString):\(branch)"
        }
    }
}

@Observable
final class PinStore {
    var pins: [Pin] = []
    private static let key = "pinnedItems"

    init() { load() }

    func isPinned(_ pin: Pin) -> Bool {
        pins.contains(pin)
    }

    func toggle(_ pin: Pin) {
        if let idx = pins.firstIndex(of: pin) {
            pins.remove(at: idx)
        } else {
            pins.append(pin)
        }
        save()
    }

    func removeAll(forRepo repoID: UUID) {
        let before = pins.count
        pins.removeAll {
            switch $0 {
            case .repo(let id): return id == repoID
            case .worktree(let id, _): return id == repoID
            }
        }
        if pins.count != before { save() }
    }

    func removeWorktree(repoID: UUID, branch: String) {
        let before = pins.count
        pins.removeAll {
            if case .worktree(let id, let b) = $0 { return id == repoID && b == branch }
            return false
        }
        if pins.count != before { save() }
    }

    func renameWorktree(repoID: UUID, oldBranch: String, newBranch: String) {
        var changed = false
        for i in pins.indices {
            if case .worktree(let id, let b) = pins[i], id == repoID, b == oldBranch {
                pins[i] = .worktree(repoID: id, branch: newBranch)
                changed = true
            }
        }
        if changed { save() }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(pins) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([Pin].self, from: data) {
            pins = decoded
        }
    }
}
