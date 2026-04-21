import Foundation
import Observation

@Observable
final class Workspace {
    let repo: RepoEntry
    let profileStore: AgentProfileStore
    let tiling: Tiling
    var terminalHosts: [UUID: TerminalHost] = [:]

    private var saveTask: Task<Void, Never>?

    init(repo: RepoEntry, profileStore: AgentProfileStore) {
        self.repo = repo
        self.profileStore = profileStore
        self.tiling = Tiling()
    }

    deinit {
        saveTask?.cancel()
        save()
        for host in terminalHosts.values { host.teardown() }
    }

    var workspaceDir: URL {
        repo.path.appendingPathComponent(".xyzterminal", isDirectory: true)
    }

    var scrollbackDir: URL {
        workspaceDir.appendingPathComponent("scrollback", isDirectory: true)
    }

    private var snapshotURL: URL {
        workspaceDir.appendingPathComponent("workspace.json")
    }

    func load() {
        guard let data = try? Data(contentsOf: snapshotURL),
              let snapshot = try? JSONDecoder().decode(WorkspaceSnapshot.self, from: data) else { return }
        tiling.root = snapshot.root
    }

    func save() {
        try? FileManager.default.createDirectory(at: workspaceDir, withIntermediateDirectories: true)
        let snapshot = WorkspaceSnapshot(root: tiling.root)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: snapshotURL, options: .atomic)
        }
        try? FileManager.default.createDirectory(at: scrollbackDir, withIntermediateDirectories: true)
        for host in terminalHosts.values {
            host.saveScrollback(to: scrollbackDir)
        }
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            self.save()
        }
    }

    func addTerminal(worktreeID: String) {
        _ = tiling.addPane(.terminal(worktreeID: worktreeID))
        scheduleSave()
    }

    func splitTerminal(paneID: UUID, edge: TileEdge, worktreeID: String) {
        _ = tiling.split(paneID: paneID, edge: edge, newContent: .terminal(worktreeID: worktreeID))
        scheduleSave()
    }

    func closePane(paneID: UUID) {
        if let host = terminalHosts.removeValue(forKey: paneID) {
            host.saveScrollback(to: scrollbackDir)
            host.teardown()
        }
        tiling.remove(paneID: paneID)
        scheduleSave()
    }

    func setWeights(splitID: UUID, weights: [Float]) {
        tiling.setWeights(splitID: splitID, weights: weights)
        scheduleSave()
    }
}

struct WorkspaceSnapshot: Codable {
    var root: TileNode?
}
