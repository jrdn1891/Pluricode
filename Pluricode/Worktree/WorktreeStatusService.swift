import Foundation
import Observation

struct WorktreeStatusKey: Hashable, Sendable {
    let repoID: UUID
    let branch: String
}

struct WorktreeStatus: Equatable, Sendable {
    var diff: DiffStats
    var isMerged: Bool

    static let empty = WorktreeStatus(diff: .zero, isMerged: false)
}

@Observable
final class WorktreeStatusService {
    private(set) var statuses: [WorktreeStatusKey: WorktreeStatus] = [:]

    @ObservationIgnored private let repoStore: RepoStore
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    static let diffInterval: Duration = .seconds(15)
    static let mergedEveryNTicks: Int = 4
    static let maxConcurrentJobs: Int = 4

    init(repoStore: RepoStore) {
        self.repoStore = repoStore
        startPolling()
    }

    deinit {
        pollTask?.cancel()
    }

    func status(repoID: UUID, branch: String) -> WorktreeStatus {
        statuses[WorktreeStatusKey(repoID: repoID, branch: branch)] ?? .empty
    }

    func mergedKeys() -> [WorktreeStatusKey] {
        statuses.compactMap { $0.value.isMerged ? $0.key : nil }
    }

    func invalidate(repoID: UUID) {
        for key in statuses.keys where key.repoID == repoID {
            statuses.removeValue(forKey: key)
        }
        Task { @MainActor in await self.refresh(includeMerged: true) }
    }

    @MainActor
    func refreshNow() async {
        await refresh(includeMerged: true)
    }

    private func startPolling() {
        pollTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                guard let self else { return }
                let includeMerged = tick % Self.mergedEveryNTicks == 0
                await self.refresh(includeMerged: includeMerged)
                tick += 1
                try? await Task.sleep(for: Self.diffInterval)
            }
        }
    }

    @MainActor
    private func refresh(includeMerged: Bool) async {
        let repos = repoStore.repos
        let previous = statuses
        let updates = await Task.detached {
            await Self.collect(repos: repos, previous: previous, includeMerged: includeMerged)
        }.value

        let valid = Set(updates.keys)
        for key in statuses.keys where !valid.contains(key) {
            statuses.removeValue(forKey: key)
        }
        for (key, status) in updates where statuses[key] != status {
            statuses[key] = status
        }
    }

    nonisolated private static func collect(
        repos: [RepoEntry],
        previous: [WorktreeStatusKey: WorktreeStatus],
        includeMerged: Bool
    ) async -> [WorktreeStatusKey: WorktreeStatus] {
        struct Job {
            let key: WorktreeStatusKey
            let path: URL
            let isPrimary: Bool
            let prevMerged: Bool
        }
        var jobs: [Job] = []
        for repo in repos {
            guard let wm = WorktreeManager(repoRoot: repo.path) else { continue }
            for wt in await wm.listManagedWorktrees() {
                let key = WorktreeStatusKey(repoID: repo.id, branch: wt.branch)
                jobs.append(Job(
                    key: key,
                    path: URL(fileURLWithPath: wt.path),
                    isPrimary: wt.isPrimary,
                    prevMerged: previous[key]?.isMerged ?? false
                ))
            }
        }
        return await withTaskGroup(of: (WorktreeStatusKey, WorktreeStatus).self) { group in
            func add(_ job: Job) {
                group.addTask {
                    let diff = await WorktreeManager.diffStats(at: job.path)
                    let merged: Bool
                    if job.isPrimary {
                        merged = false
                    } else if includeMerged {
                        merged = await WorktreeManager.isMerged(at: job.path)
                    } else {
                        merged = job.prevMerged
                    }
                    return (job.key, WorktreeStatus(diff: diff, isMerged: merged))
                }
            }
            var iterator = jobs.makeIterator()
            for _ in 0..<maxConcurrentJobs {
                guard let job = iterator.next() else { break }
                add(job)
            }
            var result: [WorktreeStatusKey: WorktreeStatus] = [:]
            for await item in group {
                result[item.0] = item.1
                if let job = iterator.next() { add(job) }
            }
            return result
        }
    }
}
