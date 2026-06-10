import Foundation

@MainActor
final class PluriBridge {
    private let repoStore: RepoStore
    private let workspaceStore: WorkspaceStore
    private let sidebarState: SidebarState
    private let pinStore: PinStore
    private let registry: PluriTaskRegistry
    private let watcher = DirectoryWatcher()

    static var commandsDir: URL {
        PluriHome.dir.appendingPathComponent("commands", isDirectory: true)
    }

    init(repoStore: RepoStore, workspaceStore: WorkspaceStore, sidebarState: SidebarState, pinStore: PinStore, registry: PluriTaskRegistry) {
        self.repoStore = repoStore
        self.workspaceStore = workspaceStore
        self.sidebarState = sidebarState
        self.pinStore = pinStore
        self.registry = registry
    }

    func start() {
        watcher.watch(Self.commandsDir) { [weak self] in self?.drain() }
        for url in contents() {
            try? FileManager.default.removeItem(at: url)
        }
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
        let prompt: String?
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
        case "propose":
            return propose(data)
        case "delete_worktree":
            return deleteWorktree(cmd)
        default:
            return Self.failure("unknown action '\(cmd.action)'; supported: open_pane, propose, delete_worktree")
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
        if let error = dispatch(repo: repo, branch: branch, prompt: cmd.prompt, startup: cmd.startup, workspaceName: cmd.workspace) {
            return Self.failure(error)
        }
        return Self.success
    }

    private func dispatch(repo: RepoEntry, branch: String, prompt: String?, startup: String?, workspaceName: String? = nil) -> String? {
        guard let workspace = resolveWorkspace(workspaceName) else {
            return "no workspace selected in Pluricode; pass 'workspace' (name) to create one"
        }
        workspaceStore.worktreePaths.invalidate(repoID: repo.id)
        workspaceStore.worktreeStatusService.invalidate(repoID: repo.id)
        guard workspaceStore.worktreePaths.path(forRepoID: repo.id, repoPath: repo.path, branch: branch) != nil else {
            return "no managed worktree on branch '\(branch)' in \(repo.name)"
        }
        sidebarState.refresh(repo)
        let script: String?
        if let prompt, !prompt.isEmpty {
            script = "\(startup ?? PluriSettings.shared.effectiveWorkerScript) \(shellEscape(prompt))"
            registry.register(repo: repo.path.standardizedFileURL.path, branch: branch, brief: prompt)
        } else {
            script = startup
        }
        workspace.openWorktreePane(repoID: repo.id, branch: branch, startupScript: script)
        return nil
    }

    private struct ProposeCommand: Decodable {
        struct Item: Decodable {
            let repo: String
            let branch: String
            let prompt: String
        }
        let tasks: [Item]
    }

    private func propose(_ data: Data) -> Data {
        let cmd: ProposeCommand
        do {
            cmd = try JSONDecoder().decode(ProposeCommand.self, from: data)
        } catch {
            return Self.failure("propose needs 'tasks': [{repo, branch, prompt}]: \(error.localizedDescription)")
        }
        guard !cmd.tasks.isEmpty else {
            return Self.failure("propose needs at least one task")
        }
        var items: [ProposalItem] = []
        for task in cmd.tasks {
            guard let repo = repo(at: task.repo) else {
                return unknownRepo(task.repo)
            }
            workspaceStore.worktreePaths.invalidate(repoID: repo.id)
            guard workspaceStore.worktreePaths.path(forRepoID: repo.id, repoPath: repo.path, branch: task.branch) != nil else {
                return Self.failure("no managed worktree on branch '\(task.branch)' in \(repo.name); create worktrees before proposing")
            }
            guard !task.prompt.isEmpty else {
                return Self.failure("task on '\(task.branch)' has an empty prompt")
            }
            items.append(ProposalItem(repo: repo, branch: task.branch, prompt: task.prompt))
        }
        registry.proposal = items
        return Self.success
    }

    func approveProposal() {
        guard let items = registry.proposal else { return }
        registry.proposal = nil
        for item in items {
            _ = dispatch(repo: item.repo, branch: item.branch, prompt: item.prompt, startup: nil)
        }
    }

    func redispatch(_ task: PluriTask) -> String? {
        guard let repo = repo(at: task.repo) else {
            return "repo '\(task.repo)' is no longer registered"
        }
        return dispatch(repo: repo, branch: task.branch, prompt: task.brief, startup: nil)
    }

    func workerSession(for task: PluriTask) -> TerminalSession? {
        guard let repo = repo(at: task.repo),
              let (ws, _, tabID) = workspaceStore.workerPane(repoID: repo.id, branch: task.branch) else { return nil }
        return ws.terminalHosts[tabID]?.session
    }

    @discardableResult
    func reply(to task: PluriTask, text: String) -> Bool {
        guard let session = workerSession(for: task) else { return false }
        session.submit(text)
        registry.appendReply(text, taskID: task.id)
        return true
    }

    @discardableResult
    func focusWorkerPane(for task: PluriTask) -> Bool {
        guard let repo = repo(at: task.repo) else { return false }
        return workspaceStore.focusWorkerPane(repoID: repo.id, branch: task.branch)
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
        registry.remove(repo: repo.path.standardizedFileURL.path, branch: branch)
        sidebarState.refresh(repo)
        return Self.success
    }

    private static let success = Data("{\"ok\": true}".utf8)

    private static func failure(_ message: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["ok": false, "error": message])) ?? success
    }
}
