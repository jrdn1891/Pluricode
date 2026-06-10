import Foundation
import Observation

@Observable
final class WorktreePaths {
    private var cache: [UUID: [Worktree]] = [:]
    @ObservationIgnored private var loading: Set<UUID> = []

    func path(forRepoID repoID: UUID, repoPath: URL, branch: String) -> String? {
        guard let list = cache[repoID] else {
            load(repoID: repoID, repoPath: repoPath)
            return nil
        }
        return list.first { $0.branch == branch }?.path
    }

    func isLoaded(repoID: UUID) -> Bool {
        cache[repoID] != nil
    }

    @MainActor
    func resolve(forRepoID repoID: UUID, repoPath: URL, branch: String) async -> String? {
        if cache[repoID] == nil {
            cache[repoID] = await WorktreeManager(repoRoot: repoPath)?.listManagedWorktrees() ?? []
        }
        return cache[repoID]?.first { $0.branch == branch }?.path
    }

    func invalidate(repoID: UUID) {
        cache.removeValue(forKey: repoID)
        loading.remove(repoID)
    }

    private func load(repoID: UUID, repoPath: URL) {
        guard !loading.contains(repoID) else { return }
        loading.insert(repoID)
        Task { @MainActor in
            let list = await WorktreeManager(repoRoot: repoPath)?.listManagedWorktrees() ?? []
            guard loading.remove(repoID) != nil else { return }
            cache[repoID] = list
        }
    }
}
