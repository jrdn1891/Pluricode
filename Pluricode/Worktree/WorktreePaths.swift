import Foundation

final class WorktreePaths {
    private var cache: [UUID: [Worktree]] = [:]

    func path(forRepoID repoID: UUID, repoPath: URL, branch: String) -> String? {
        worktrees(forRepoID: repoID, repoPath: repoPath)
            .first { $0.branch == branch }?.path
    }

    func invalidate(repoID: UUID) {
        cache.removeValue(forKey: repoID)
    }

    private func worktrees(forRepoID repoID: UUID, repoPath: URL) -> [Worktree] {
        if let list = cache[repoID] { return list }
        let list = WorktreeManager(repoRoot: repoPath)?.listManagedWorktrees() ?? []
        cache[repoID] = list
        return list
    }
}
