import Foundation
import Observation

@Observable
final class SidebarState {
    var expanded: Set<UUID> = []
    var worktrees: [UUID: [Worktree]] = [:]

    func toggle(_ repo: RepoEntry) {
        if expanded.contains(repo.id) {
            expanded.remove(repo.id)
        } else {
            expanded.insert(repo.id)
            refresh(repo)
        }
    }

    func toggleAll(_ repos: [RepoEntry]) {
        if expanded.isEmpty {
            for repo in repos {
                expanded.insert(repo.id)
                refresh(repo)
            }
        } else {
            expanded.removeAll()
        }
    }

    func refresh(_ repo: RepoEntry) {
        guard let wm = WorktreeManager(repoRoot: repo.path) else {
            worktrees[repo.id] = []
            return
        }
        worktrees[repo.id] = wm.listManagedWorktrees()
    }
}
