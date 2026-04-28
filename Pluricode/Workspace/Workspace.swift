import Foundation
import Observation
import SwiftUI

struct FocusedWorkspaceKey: FocusedValueKey {
    typealias Value = Workspace
}

extension FocusedValues {
    var workspace: Workspace? {
        get { self[FocusedWorkspaceKey.self] }
        set { self[FocusedWorkspaceKey.self] = newValue }
    }
}

enum SpawnPolicy: Codable, Equatable {
    case ask
    case allow
    case allowUpTo(Int)

    var label: String {
        switch self {
        case .ask: "Ask each time"
        case .allow: "Always allow"
        case .allowUpTo(let n): "Allow up to \(n)"
        }
    }
}

struct PendingSpawnRequest: Identifiable {
    let id: UUID
    let summary: String
    let createdAt: Date
    let continuation: CheckedContinuation<Bool, Never>
}

@Observable
final class Workspace {
    let id: UUID
    var name: String
    let tiling: Tiling
    let repoStore: RepoStore
    let taskListStore: TaskListStore
    let profileStore: AgentProfileStore
    let statsService: StatsService
    var terminalHosts: [UUID: TerminalHost] = [:]
    var pendingDevScripts: [UUID: String] = [:]
    var pendingMCPPrompts: [UUID: String] = [:]
    var focusedPaneID: UUID?
    var expandedPaneID: UUID?
    var commandKeyHeld: Bool = false
    var spawnPolicy: SpawnPolicy = .ask
    var spawnedThisSession: Int = 0
    var pendingSpawnRequests: [PendingSpawnRequest] = []

    private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var commandHoldTask: DispatchWorkItem?
    @ObservationIgnored private(set) var mcpServer: MCPServer?
    static let quickSwitchHoldDelay: TimeInterval = 0.35

    init(
        id: UUID = UUID(),
        name: String,
        root: TileNode? = nil,
        spawnPolicy: SpawnPolicy = .ask,
        repoStore: RepoStore,
        taskListStore: TaskListStore,
        profileStore: AgentProfileStore,
        statsService: StatsService
    ) {
        self.id = id
        self.name = name
        self.tiling = Tiling(root: root)
        self.spawnPolicy = spawnPolicy
        self.repoStore = repoStore
        self.taskListStore = taskListStore
        self.profileStore = profileStore
        self.statsService = statsService
        self.mcpServer = try? MCPServer(workspace: self)
    }

    deinit {
        saveTask?.cancel()
        save()
        for host in terminalHosts.values { host.teardown() }
        for req in pendingSpawnRequests { req.continuation.resume(returning: false) }
    }

    static var rootDir: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Pluricode", isDirectory: true)
    }

    static var workspacesDir: URL {
        rootDir.appendingPathComponent("workspaces", isDirectory: true)
    }

    static var scrollbackDir: URL {
        rootDir.appendingPathComponent("scrollback", isDirectory: true)
    }

    var scrollbackDir: URL { Self.scrollbackDir }

    var snapshotURL: URL {
        Self.workspacesDir.appendingPathComponent("\(id.uuidString).json")
    }

    func repo(id: UUID) -> RepoEntry? {
        repoStore.repos.first { $0.id == id }
    }

    func save() {
        try? FileManager.default.createDirectory(at: Self.workspacesDir, withIntermediateDirectories: true)
        let snapshot = WorkspaceSnapshot(id: id, name: name, root: tiling.root, spawnPolicy: spawnPolicy)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: snapshotURL, options: .atomic)
        }
        try? FileManager.default.createDirectory(at: Self.scrollbackDir, withIntermediateDirectories: true)
        for host in terminalHosts.values {
            host.saveScrollback(to: Self.scrollbackDir)
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

    func rename(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        name = trimmed
        scheduleSave()
    }

    func addPane(_ content: TabContent) {
        let id = tiling.addPane(content)
        focusedPaneID = id
        scheduleSave()
    }

    func splitPane(paneID: UUID, edge: TileEdge, content: TabContent) {
        let id = tiling.split(paneID: paneID, edge: edge, newContent: content)
        focusedPaneID = id
        scheduleSave()
    }

    func closePane(paneID: UUID) {
        guard let pane = pane(id: paneID) else { return }
        for tab in pane.tabs { teardownTab(tab.id) }
        tiling.remove(paneID: paneID)
        if focusedPaneID == paneID { focusedPaneID = tiling.panes.first?.id }
        if expandedPaneID == paneID { expandedPaneID = nil }
        scheduleSave()
    }

    func closeTab(paneID: UUID, tabID: UUID) {
        guard let pane = pane(id: paneID) else { return }
        if pane.tabs.count <= 1 {
            closePane(paneID: paneID)
            return
        }
        teardownTab(tabID)
        tiling.updatePane(paneID) { p in
            p.tabs.removeAll { $0.id == tabID }
            if p.activeTabID == tabID, let next = p.tabs.first {
                p.activeTabID = next.id
            }
        }
        scheduleSave()
    }

    func setActiveTab(paneID: UUID, tabID: UUID) {
        tiling.updatePane(paneID) { $0.activeTabID = tabID }
        scheduleSave()
    }

    func cycleTab(paneID: UUID, by delta: Int) {
        guard let pane = pane(id: paneID), pane.tabs.count > 1 else { return }
        let idx = pane.tabs.firstIndex { $0.id == pane.activeTabID } ?? 0
        let count = pane.tabs.count
        let next = ((idx + delta) % count + count) % count
        setActiveTab(paneID: paneID, tabID: pane.tabs[next].id)
    }

    private func teardownTab(_ tabID: UUID) {
        if let host = terminalHosts.removeValue(forKey: tabID) {
            host.saveScrollback(to: Self.scrollbackDir)
            host.teardown()
        }
        pendingDevScripts.removeValue(forKey: tabID)
    }

    func consumePendingDevScript(tabID: UUID) -> String? {
        pendingDevScripts.removeValue(forKey: tabID)
    }

    func consumePendingMCPPrompt(tabID: UUID) -> String? {
        pendingMCPPrompts.removeValue(forKey: tabID)
    }

    func setSpawnPolicy(_ policy: SpawnPolicy) {
        spawnPolicy = policy
        scheduleSave()
    }

    func evaluateSpawnPolicy(summary: String) async -> Bool {
        switch spawnPolicy {
        case .allow:
            return true
        case .allowUpTo(let limit):
            if spawnedThisSession < limit { return true }
            return await askUserToApprove(summary: summary)
        case .ask:
            return await askUserToApprove(summary: summary)
        }
    }

    private func askUserToApprove(summary: String) async -> Bool {
        await withCheckedContinuation { cont in
            let req = PendingSpawnRequest(
                id: UUID(),
                summary: summary,
                createdAt: Date(),
                continuation: cont
            )
            pendingSpawnRequests.append(req)
        }
    }

    func resolveSpawnRequest(id: UUID, approve: Bool) {
        guard let idx = pendingSpawnRequests.firstIndex(where: { $0.id == id }) else { return }
        let req = pendingSpawnRequests.remove(at: idx)
        req.continuation.resume(returning: approve)
    }

    struct SpawnResult {
        let paneID: UUID
        let tabID: UUID
        let worktreeBranch: String
        let path: String
    }

    func spawnTerminal(
        repoID: UUID,
        baseBranch: String?,
        profileID: UUID?,
        name: String?,
        prompt: String?,
        split: SpawnSplit
    ) async throws -> SpawnResult {
        guard let repo = repo(id: repoID) else {
            throw JSONRPCError.invalid("repo not found")
        }
        guard let wm = WorktreeManager(repoRoot: repo.path) else {
            throw JSONRPCError.invalid("not a git repo")
        }
        let resolvedBase = baseBranch.map(Self.normalizeBaseRef) ?? wm.defaultBaseRef()
        let candidate = name.flatMap { s -> String? in
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        let baseName = candidate ?? Self.autoWorktreeName(profileID: profileID, profileStore: profileStore)
        let safeName = Self.uniqueWorktreeName(base: Self.sanitize(baseName), wm: wm)

        let path: URL
        do {
            path = try wm.createWorktree(name: safeName, baseBranch: resolvedBase)
        } catch {
            throw JSONRPCError.application("createWorktree failed: \(error)")
        }

        var config = WorktreeConfig.load(at: path.path)
        config.agentProfileID = profileID
        config.save(at: path.path)

        let branch = "pluri-\(safeName)"
        let content: TabContent = .terminal(repoID: repoID, worktreeID: branch)

        let paneIDResolved: UUID
        let tabIDResolved: UUID

        switch split {
        case .right, .down:
            let edge: TileEdge = (split == .right) ? .right : .bottom
            if let anchor = anchorPaneID {
                paneIDResolved = tiling.split(paneID: anchor, edge: edge, newContent: content)
            } else {
                paneIDResolved = tiling.addPane(content)
            }
            guard let firstTab = pane(id: paneIDResolved)?.tabs.first else {
                throw JSONRPCError.application("pane lookup failed after split")
            }
            tabIDResolved = firstTab.id
        case .tab:
            if let anchor = anchorPaneID {
                let newTab = Tab(content: content)
                tiling.updatePane(anchor) { p in
                    p.tabs.append(newTab)
                    p.activeTabID = newTab.id
                }
                paneIDResolved = anchor
                tabIDResolved = newTab.id
            } else {
                paneIDResolved = tiling.addPane(content)
                guard let firstTab = pane(id: paneIDResolved)?.tabs.first else {
                    throw JSONRPCError.application("pane lookup failed")
                }
                tabIDResolved = firstTab.id
            }
        }

        if let prompt, !prompt.isEmpty {
            pendingMCPPrompts[tabIDResolved] = prompt
        }
        focusedPaneID = paneIDResolved
        spawnedThisSession += 1
        scheduleSave()

        return SpawnResult(
            paneID: paneIDResolved,
            tabID: tabIDResolved,
            worktreeBranch: branch,
            path: path.path
        )
    }

    private static func normalizeBaseRef(_ s: String) -> String { s }

    private static func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(scalars).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return String(collapsed.prefix(40)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func autoWorktreeName(profileID: UUID?, profileStore: AgentProfileStore) -> String {
        let suffix = String(UUID().uuidString.prefix(6)).lowercased()
        if let id = profileID, let p = profileStore.profile(id: id) {
            return "\(p.name.lowercased())-\(suffix)"
        }
        return "agent-\(suffix)"
    }

    private static func uniqueWorktreeName(base: String, wm: WorktreeManager) -> String {
        let existing = Set(wm.listManagedWorktrees().map { $0.branch })
        var candidate = base.isEmpty ? "agent" : base
        var n = 2
        while existing.contains("pluri-\(candidate)") {
            candidate = "\(base)-\(n)"
            n += 1
        }
        return candidate
    }

    func expandPane(paneID: UUID) {
        expandedPaneID = paneID
    }

    func collapseExpandedPane() {
        expandedPaneID = nil
    }

    func worktreePath(tabID: UUID) -> String? {
        guard let (_, tab) = locateTab(id: tabID),
              case .terminal(let repoID, let worktreeID) = tab.content,
              let repo = repo(id: repoID),
              let wm = WorktreeManager(repoRoot: repo.path) else { return nil }
        return wm.listManagedWorktrees().first { $0.branch == worktreeID }?.path
    }

    func paneDisplayName(worktreeID: String) -> String {
        worktreeID.hasPrefix("pluri-") ? String(worktreeID.dropFirst("pluri-".count)) : worktreeID
    }

    func tabProfile(tabID: UUID) -> AgentProfile? {
        guard let path = worktreePath(tabID: tabID) else { return nil }
        let config = WorktreeConfig.load(at: path)
        guard let id = config.agentProfileID else { return nil }
        return profileStore.profile(id: id)
    }

    func devScript(paneID: UUID) -> String? {
        guard let pane = pane(id: paneID),
              case .terminal(let repoID, _) = pane.activeTab.content,
              let repo = repo(id: repoID) else { return nil }
        let script = RepoConfig.load(at: repo.path.path).devScript
        return (script?.isEmpty == false) ? script : nil
    }

    func runDevScript(paneID: UUID) {
        guard let pane = pane(id: paneID),
              case .terminal(let repoID, let worktreeID) = pane.activeTab.content,
              let repo = repo(id: repoID),
              let script = RepoConfig.load(at: repo.path.path).devScript,
              !script.isEmpty else { return }
        let newTab = Tab(content: .terminal(repoID: repoID, worktreeID: worktreeID), name: "dev")
        pendingDevScripts[newTab.id] = script
        tiling.updatePane(paneID) { p in
            p.tabs.append(newTab)
            p.activeTabID = newTab.id
        }
        focusedPaneID = paneID
        scheduleSave()
    }

    func runDevScriptOnFocusedPane() {
        guard let id = focusedPaneID else { return }
        runDevScript(paneID: id)
    }

    var focusedDevScript: String? {
        guard let id = focusedPaneID else { return nil }
        return devScript(paneID: id)
    }

    func tabLabel(_ tab: Tab, fallback: String) -> String {
        if let name = tab.name, !name.isEmpty { return name }
        if case .terminal(_, let worktreeID) = tab.content {
            return paneDisplayName(worktreeID: worktreeID)
        }
        return fallback
    }

    private func locateTab(id tabID: UUID) -> (Pane, Tab)? {
        for pane in tiling.panes {
            if let tab = pane.tabs.first(where: { $0.id == tabID }) {
                return (pane, tab)
            }
        }
        return nil
    }

    func setWeights(splitID: UUID, weights: [Float]) {
        tiling.setWeights(splitID: splitID, weights: weights)
        scheduleSave()
    }

    func setFocus(paneID: UUID?) {
        focusedPaneID = paneID
    }

    func setCommandKeyDown(_ down: Bool) {
        commandHoldTask?.cancel()
        commandHoldTask = nil
        if down {
            let task = DispatchWorkItem { [weak self] in
                self?.commandKeyHeld = true
            }
            commandHoldTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.quickSwitchHoldDelay, execute: task)
        } else {
            commandKeyHeld = false
        }
    }

    var terminalPanes: [Pane] {
        tiling.panes.filter {
            if case .terminal = $0.activeTab.content { return true }
            return false
        }
    }

    func focusPane(atIndex index: Int) {
        let panes = terminalPanes
        guard panes.indices.contains(index) else { return }
        let pane = panes[index]
        setFocus(paneID: pane.id)
        terminalHosts[pane.activeTabID]?.focusInput()
    }

    func closeFocusedTab() {
        guard let paneID = focusedPaneID, let pane = pane(id: paneID) else { return }
        closeTab(paneID: paneID, tabID: pane.activeTabID)
    }

    func cycleFocusedTab(by delta: Int) {
        guard let id = focusedPaneID else { return }
        cycleTab(paneID: id, by: delta)
    }

    var focusedPaneTabCount: Int {
        guard let id = focusedPaneID, let pane = pane(id: id) else { return 0 }
        return pane.tabs.count
    }

    func splitFocusedPane(direction: TileDirection) {
        guard let id = focusedPaneID, let pane = pane(id: id) else { return }
        let edge: TileEdge = direction == .horizontal ? .right : .bottom
        splitPane(paneID: id, edge: edge, content: pane.activeTab.content)
    }

    var anchorPaneID: UUID? {
        if let id = focusedPaneID, pane(id: id) != nil { return id }
        return tiling.panes.first?.id
    }

    enum PaneCreationAction {
        case addNew
        case splitRight
        case splitDown

        var edge: TileEdge? {
            switch self {
            case .addNew: nil
            case .splitRight: .right
            case .splitDown: .bottom
            }
        }
    }

    func performPaneCreation(_ action: PaneCreationAction, content: TabContent) {
        if let edge = action.edge, let anchor = anchorPaneID {
            splitPane(paneID: anchor, edge: edge, content: content)
        } else {
            addPane(content)
        }
    }

    func pane(id: UUID) -> Pane? {
        Self.findPane(id: id, in: tiling.root)
    }

    @discardableResult
    func acceptDrop(payload: TilingDragPayload, on targetID: UUID?, edge: TileEdge) -> Bool {
        switch payload.kind {
        case .newTerminal(let repoID, let worktreeID):
            let content: TabContent = .terminal(repoID: repoID, worktreeID: worktreeID)
            if let targetID { splitPane(paneID: targetID, edge: edge, content: content) }
            else { addPane(content) }
        case .newTaskPane(let listID):
            let content: TabContent = .tasks(listID: listID)
            if let targetID { splitPane(paneID: targetID, edge: edge, content: content) }
            else { addPane(content) }
        case .newStats:
            let content: TabContent = .stats
            if let targetID { splitPane(paneID: targetID, edge: edge, content: content) }
            else { addPane(content) }
        case .movePane(let sourceID):
            guard let targetID, sourceID != targetID else { return false }
            if edge == .center {
                tiling.swapPanes(a: sourceID, b: targetID)
            } else {
                tiling.movePane(sourceID: sourceID, to: edge, adjacentTo: targetID)
            }
            focusedPaneID = sourceID
            scheduleSave()
        }
        return true
    }

    private static func findPane(id: UUID, in node: TileNode?) -> Pane? {
        guard let node else { return nil }
        switch node {
        case .pane(let p):
            return p.id == id ? p : nil
        case .split(let s):
            for child in s.children {
                if let found = findPane(id: id, in: child) { return found }
            }
            return nil
        }
    }
}

struct WorkspaceSnapshot: Codable {
    var id: UUID
    var name: String
    var root: TileNode?
    var spawnPolicy: SpawnPolicy?
}

@Observable
final class WorkspaceStore {
    var workspaces: [Workspace] = []
    var selectedWorkspaceID: UUID?

    private let repoStore: RepoStore
    private let taskListStore: TaskListStore
    private let profileStore: AgentProfileStore
    let statsService: StatsService

    private static let selectedKey = "selectedWorkspaceID"

    init(repoStore: RepoStore, taskListStore: TaskListStore, profileStore: AgentProfileStore) {
        self.repoStore = repoStore
        self.taskListStore = taskListStore
        self.profileStore = profileStore
        self.statsService = StatsService(repoStore: repoStore)
        load()
    }

    var selectedWorkspace: Workspace? {
        guard let id = selectedWorkspaceID else { return nil }
        return workspaces.first { $0.id == id }
    }

    @discardableResult
    func createWorkspace(name: String) -> Workspace {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Untitled" : trimmed
        let ws = Workspace(
            name: finalName,
            repoStore: repoStore,
            taskListStore: taskListStore,
            profileStore: profileStore,
            statsService: statsService
        )
        workspaces.append(ws)
        sort()
        ws.save()
        selectedWorkspaceID = ws.id
        saveSelection()
        return ws
    }

    func renameWorkspace(id: UUID, name: String) {
        guard let ws = workspaces.first(where: { $0.id == id }) else { return }
        ws.rename(name)
        sort()
    }

    func removeWorkspace(id: UUID) {
        workspaces.removeAll { $0.id == id }
        let url = Workspace.workspacesDir.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
        if selectedWorkspaceID == id {
            selectedWorkspaceID = workspaces.first?.id
            saveSelection()
        }
    }

    func removePanes(repoID: UUID, worktreeID: String) {
        for ws in workspaces {
            let targets: [(UUID, UUID)] = ws.tiling.panes.flatMap { pane in
                pane.tabs.compactMap { tab -> (UUID, UUID)? in
                    guard case .terminal(let r, let w) = tab.content,
                          r == repoID, w == worktreeID else { return nil }
                    return (pane.id, tab.id)
                }
            }
            for (paneID, tabID) in targets {
                ws.closeTab(paneID: paneID, tabID: tabID)
            }
        }
    }

    func saveAll() {
        for ws in workspaces { ws.save() }
        saveSelection()
    }

    func saveSelection() {
        if let id = selectedWorkspaceID {
            UserDefaults.standard.set(id.uuidString, forKey: Self.selectedKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.selectedKey)
        }
    }

    private func sort() {
        workspaces.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func load() {
        let dir = Workspace.workspacesDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let snapshots: [WorkspaceSnapshot] = urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(WorkspaceSnapshot.self, from: data)
            }

        workspaces = snapshots.map { snap in
            Workspace(
                id: snap.id,
                name: snap.name,
                root: snap.root,
                spawnPolicy: snap.spawnPolicy ?? .ask,
                repoStore: repoStore,
                taskListStore: taskListStore,
                profileStore: profileStore,
                statsService: statsService
            )
        }
        sort()

        if let str = UserDefaults.standard.string(forKey: Self.selectedKey),
           let id = UUID(uuidString: str),
           workspaces.contains(where: { $0.id == id }) {
            selectedWorkspaceID = id
        } else {
            selectedWorkspaceID = workspaces.first?.id
        }
    }
}
