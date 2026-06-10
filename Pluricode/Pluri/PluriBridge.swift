import Foundation

@MainActor
final class PluriBridge {
    private let repoStore: RepoStore
    private let workspaceStore: WorkspaceStore
    private let sidebarState: SidebarState
    private let pinStore: PinStore
    private var source: DispatchSourceFileSystemObject?

    static var commandsDir: URL {
        PluriHome.dir.appendingPathComponent("commands", isDirectory: true)
    }

    init(repoStore: RepoStore, workspaceStore: WorkspaceStore, sidebarState: SidebarState, pinStore: PinStore) {
        self.repoStore = repoStore
        self.workspaceStore = workspaceStore
        self.sidebarState = sidebarState
        self.pinStore = pinStore
    }

    func start() {
        guard source == nil else { return }
        let dir = Self.commandsDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for url in contents() {
            try? FileManager.default.removeItem(at: url)
        }
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        src.setEventHandler { [weak self] in self?.drain() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    deinit {
        source?.cancel()
    }

    private func contents() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: Self.commandsDir, includingPropertiesForKeys: nil)) ?? []
    }

    private func drain() {
        for url in contents() {
            let name = url.lastPathComponent
            guard name.hasSuffix(".json"), !name.hasSuffix(".result.json") else { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            try? FileManager.default.removeItem(at: url)
            let result = handle(data)
            let resultName = url.deletingPathExtension().lastPathComponent + ".result.json"
            try? result.write(to: Self.commandsDir.appendingPathComponent(resultName), options: .atomic)
        }
    }

    private struct Command: Decodable {
        let action: String
        let repo: String?
        let branch: String?
        let startup: String?
        let workspace: String?
    }

    private func handle(_ data: Data) -> Data {
        let cmd: Command
        do {
            cmd = try JSONDecoder().decode(Command.self, from: data)
        } catch {
            return Self.failure("invalid request: \(error.localizedDescription)")
        }
        switch cmd.action {
        case "open_pane":
            return openPane(cmd)
        case "delete_worktree":
            return deleteWorktree(cmd)
        default:
            return Self.failure("unknown action '\(cmd.action)'; supported: open_pane, delete_worktree")
        }
    }

    private func repo(at path: String) -> RepoEntry? {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        return repoStore.repos.first { $0.path.standardizedFileURL.path == normalized }
    }

    private func unknownRepo(_ path: String) -> Data {
        let known = repoStore.repos.map { $0.path.path }.joined(separator: ", ")
        return Self.failure("unknown repo '\(path)'; registered: \(known)")
    }

    private func resolveWorkspace(_ name: String?) -> Workspace? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return workspaceStore.selectedWorkspace
        }
        if let existing = workspaceStore.workspaces.first(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) {
            workspaceStore.selectedWorkspaceID = existing.id
            workspaceStore.saveSelection()
            return existing
        }
        return workspaceStore.createWorkspace(name: name)
    }

    private func openPane(_ cmd: Command) -> Data {
        guard let repoPath = cmd.repo, let branch = cmd.branch else {
            return Self.failure("open_pane needs 'repo' (path) and 'branch'")
        }
        guard let repo = repo(at: repoPath) else {
            return unknownRepo(repoPath)
        }
        guard let workspace = resolveWorkspace(cmd.workspace) else {
            return Self.failure("no workspace selected in Pluricode; pass 'workspace' (name) to create one")
        }
        workspaceStore.worktreePaths.invalidate(repoID: repo.id)
        workspaceStore.worktreeStatusService.invalidate(repoID: repo.id)
        guard workspaceStore.worktreePaths.path(forRepoID: repo.id, repoPath: repo.path, branch: branch) != nil else {
            return Self.failure("no managed worktree on branch '\(branch)' in \(repo.name)")
        }
        sidebarState.refresh(repo)
        workspace.openWorktreePane(repoID: repo.id, branch: branch, startupScript: cmd.startup)
        return Self.success
    }

    private func deleteWorktree(_ cmd: Command) -> Data {
        guard let repoPath = cmd.repo, let branch = cmd.branch else {
            return Self.failure("delete_worktree needs 'repo' (path) and 'branch'")
        }
        guard let repo = repo(at: repoPath) else {
            return unknownRepo(repoPath)
        }
        workspaceStore.worktreePaths.invalidate(repoID: repo.id)
        guard let path = workspaceStore.worktreePaths.path(forRepoID: repo.id, repoPath: repo.path, branch: branch) else {
            return Self.failure("no managed worktree on branch '\(branch)' in \(repo.name)")
        }
        workspaceStore.deleteWorktree(
            repo: repo,
            worktree: Worktree(branch: branch, path: path, head: "", isPrimary: false),
            pinStore: pinStore
        )
        sidebarState.refresh(repo)
        return Self.success
    }

    private static let success = Data("{\"ok\": true}".utf8)

    private static func failure(_ message: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["ok": false, "error": message])) ?? success
    }
}
