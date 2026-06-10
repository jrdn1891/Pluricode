import Foundation

@MainActor
final class PluriBridge {
    private let repoStore: RepoStore
    private let workspaceStore: WorkspaceStore
    private let sidebarState: SidebarState
    private var source: DispatchSourceFileSystemObject?

    static var commandsDir: URL {
        PluriHome.dir.appendingPathComponent("commands", isDirectory: true)
    }

    init(repoStore: RepoStore, workspaceStore: WorkspaceStore, sidebarState: SidebarState) {
        self.repoStore = repoStore
        self.workspaceStore = workspaceStore
        self.sidebarState = sidebarState
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
        default:
            return Self.failure("unknown action '\(cmd.action)'; supported: open_pane")
        }
    }

    private func openPane(_ cmd: Command) -> Data {
        guard let repoPath = cmd.repo, let branch = cmd.branch else {
            return Self.failure("open_pane needs 'repo' (path) and 'branch'")
        }
        let normalized = URL(fileURLWithPath: repoPath).standardizedFileURL.path
        guard let repo = repoStore.repos.first(where: { $0.path.standardizedFileURL.path == normalized }) else {
            let known = repoStore.repos.map { $0.path.path }.joined(separator: ", ")
            return Self.failure("unknown repo '\(repoPath)'; registered: \(known)")
        }
        guard let workspace = workspaceStore.selectedWorkspace else {
            return Self.failure("no workspace selected in Pluricode")
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

    private static let success = Data("{\"ok\": true}".utf8)

    private static func failure(_ message: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["ok": false, "error": message])) ?? success
    }
}
