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

@Observable
final class Workspace {
    let id: UUID
    var name: String
    let tiling: Tiling
    let repoStore: RepoStore
    let taskListStore: TaskListStore
    let worktreePaths: WorktreePaths
    let worktreeStatusService: WorktreeStatusService
    var terminalHosts: [UUID: TerminalHost] = [:]
    var browserHosts: [UUID: BrowserHost] = [:]
    var simulatorHosts: [UUID: SimulatorHost] = [:]
    var pendingDevScripts: [UUID: String] = [:]
    var pendingPreviewOrigins: [UUID: UUID] = [:]
    var stubTabs: [UUID: UUID] = [:]
    var minimizedPanes: [MinimizedPane] = []
    @ObservationIgnored weak var store: WorkspaceStore?
    var focusedPaneID: UUID?
    @ObservationIgnored var pendingFocusPaneID: UUID?
    var expandedPaneID: UUID?
    var commandKeyHeld: Bool = false
    var dragSession: DragSession?
    var resizeSession: ResizeSession?

    struct DragHover: Equatable {
        let paneID: UUID?
        let edge: TileEdge
    }

    struct DragSession {
        let payload: TilingDragPayload
        let previewPaneID: UUID
        var hover: DragHover?
        var isCancelled: Bool = false
    }

    struct ResizeSession {
        var weightsBySplit: [UUID: [Float]]
        var highlightedPaneIDs: Set<UUID>
    }

    private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var commandHoldTask: DispatchWorkItem?
    @ObservationIgnored var isDeleted: Bool = false
    static let quickSwitchHoldDelay: TimeInterval = 0.35

    init(
        id: UUID = UUID(),
        name: String,
        root: TileNode? = nil,
        minimizedPanes: [MinimizedPane] = [],
        repoStore: RepoStore,
        taskListStore: TaskListStore,
        worktreePaths: WorktreePaths,
        worktreeStatusService: WorktreeStatusService
    ) {
        self.id = id
        self.name = name
        self.tiling = Tiling(root: root)
        self.minimizedPanes = minimizedPanes
        self.repoStore = repoStore
        self.taskListStore = taskListStore
        self.worktreePaths = worktreePaths
        self.worktreeStatusService = worktreeStatusService
    }

    deinit {
        saveTask?.cancel()
        save()
        for host in terminalHosts.values { host.teardown() }
        for host in browserHosts.values { host.teardown() }
        for host in simulatorHosts.values { host.teardown() }
    }

    static var rootDir: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let name = Bundle.main.bundleIdentifier ?? "Pluricode"
        return support.appendingPathComponent(name, isDirectory: true)
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

    static let diskQueue = DispatchQueue(label: "com.pluricode.disk", qos: .utility)

    func save() {
        guard !isDeleted else { return }
        let snapshot = WorkspaceSnapshot(id: id, name: name, root: tiling.root, minimizedPanes: minimizedPanes)
        if let data = try? JSONEncoder().encode(snapshot) {
            let url = snapshotURL
            Self.diskQueue.async {
                try? FileManager.default.createDirectory(at: Self.workspacesDir, withIntermediateDirectories: true)
                try? data.write(to: url, options: .atomic)
            }
        }
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
        pendingFocusPaneID = id
        scheduleSave()
    }

    func splitPane(paneID: UUID, edge: TileEdge, content: TabContent) {
        let id = tiling.split(paneID: paneID, edge: edge, newContent: content)
        focusedPaneID = id
        pendingFocusPaneID = id
        scheduleSave()
    }

    func consumePendingFocus(paneID: UUID) -> Bool {
        guard pendingFocusPaneID == paneID else { return false }
        pendingFocusPaneID = nil
        return true
    }

    func canMinimize(paneID: UUID) -> Bool {
        pane(id: paneID) != nil && tiling.panes.count > 1
    }

    func minimizePane(paneID: UUID) {
        guard let pane = pane(id: paneID), canMinimize(paneID: paneID) else { return }
        let hint = Tiling.captureRestoreHint(for: paneID, in: tiling.root)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            tiling.remove(paneID: paneID)
            minimizedPanes.append(MinimizedPane(pane: pane, hint: hint, minimizedAt: Date()))
        }
        if focusedPaneID == paneID { focusedPaneID = tiling.panes.first?.id }
        if expandedPaneID == paneID { expandedPaneID = nil }
        scheduleSave()
    }

    func restoreMinimizedPane(paneID: UUID) {
        guard let idx = minimizedPanes.firstIndex(where: { $0.pane.id == paneID }) else { return }
        let item = minimizedPanes[idx]
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            minimizedPanes.remove(at: idx)
            tiling.reinsertPane(item.pane, near: item.hint.siblingPaneID, edge: item.hint.edge)
        }
        focusedPaneID = paneID
        scheduleSave()
    }

    func closeMinimizedPane(paneID: UUID) {
        guard let idx = minimizedPanes.firstIndex(where: { $0.pane.id == paneID }) else { return }
        let item = minimizedPanes.remove(at: idx)
        for tab in item.pane.tabs { teardownTab(tab.id) }
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
        browserHosts.removeValue(forKey: tabID)?.teardown()
        simulatorHosts.removeValue(forKey: tabID)?.teardown()
        pendingDevScripts.removeValue(forKey: tabID)
        pendingPreviewOrigins.removeValue(forKey: tabID)
        stubTabs.removeValue(forKey: tabID)
        store?.localHostRegistry.remove(tabID: tabID)
    }

    func markStub(tabID: UUID, targetWorkspaceID: UUID) {
        stubTabs[tabID] = targetWorkspaceID
    }

    func detachHost(tabID: UUID) -> TerminalHost? {
        terminalHosts.removeValue(forKey: tabID)
    }

    func adoptHost(_ host: TerminalHost, tabID: UUID) {
        terminalHosts[tabID] = host
    }

    func consumePendingDevScript(tabID: UUID) -> String? {
        pendingDevScripts.removeValue(forKey: tabID)
    }

    func consumePendingPreviewOrigin(tabID: UUID) -> UUID? {
        pendingPreviewOrigins.removeValue(forKey: tabID)
    }

    /// The most recently discovered local dev-server URL for a worktree, if any.
    func discoveredURL(repoID: UUID, worktreeID: String) -> URL? {
        store?.localHostRegistry.entries
            .filter { $0.repoID == repoID && $0.branch == worktreeID }
            .sorted { $0.discoveredAt > $1.discoveredAt }
            .first?.url
    }

    /// Whether this worktree already has a running "dev" tab (dev script launched).
    func hasDevTab(repoID: UUID, worktreeID: String) -> Bool {
        tiling.panes.contains { pane in
            pane.tabs.contains {
                if case .terminal(let r, let w) = $0.content { return r == repoID && w == worktreeID && $0.name == "dev" }
                return false
            }
        }
    }

    func openBrowser(repoID: UUID, worktreeID: String, url: URL? = nil, originTabID: UUID?, nearPaneID: UUID?) {
        let resolved = url ?? discoveredURL(repoID: repoID, worktreeID: worktreeID)

        // For less-technical users: if nothing is serving yet and the repo has a dev script,
        // start it so the preview fills in on its own once the server is up.
        if resolved == nil, let nearPaneID,
           !hasDevTab(repoID: repoID, worktreeID: worktreeID),
           devScript(paneID: nearPaneID) != nil {
            runDevScript(paneID: nearPaneID)
        }

        if let (paneID, tab) = findBrowserTab(repoID: repoID, worktreeID: worktreeID) {
            setActiveTab(paneID: paneID, tabID: tab.id)
            setFocus(paneID: paneID)
            if let resolved, browserHosts[tab.id]?.currentURL == nil {
                browserHosts[tab.id]?.load(resolved)
                updateBrowserURL(tabID: tab.id, url: resolved)
            }
            return
        }

        let content: TabContent = .browser(repoID: repoID, worktreeID: worktreeID, url: resolved)
        if let nearPaneID {
            splitPane(paneID: nearPaneID, edge: .right, content: content)
        } else {
            addPane(content)
        }
        if let originTabID, let pid = focusedPaneID, let tabID = pane(id: pid)?.activeTabID {
            pendingPreviewOrigins[tabID] = originTabID
        }
    }

    func openSimulator(repoID: UUID, worktreeID: String, originTabID: UUID?, nearPaneID: UUID?) {
        if let (paneID, tab) = findSimulatorTab(repoID: repoID, worktreeID: worktreeID) {
            setActiveTab(paneID: paneID, tabID: tab.id)
            setFocus(paneID: paneID)
            return
        }
        let content: TabContent = .simulator(repoID: repoID, worktreeID: worktreeID, udid: nil)
        if let nearPaneID {
            splitPane(paneID: nearPaneID, edge: .right, content: content)
        } else {
            addPane(content)
        }
        if let originTabID, let pid = focusedPaneID, let tabID = pane(id: pid)?.activeTabID {
            pendingPreviewOrigins[tabID] = originTabID
        }
    }

    func openWorktreePane(repoID: UUID, branch: String, startupScript: String?) {
        let tab = Tab(content: .terminal(repoID: repoID, worktreeID: branch))
        if let startupScript, !startupScript.isEmpty {
            pendingDevScripts[tab.id] = startupScript
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            tiling.reinsertPane(Pane(tabs: [tab]), near: anchorPaneID, edge: .right)
        }
        scheduleSave()
    }

    func renameWorktreeReferences(repoID: UUID, oldBranch: String, newBranch: String) {
        func renamed(_ content: TabContent) -> TabContent? {
            switch content {
            case .terminal(let r, let w) where r == repoID && w == oldBranch:
                return .terminal(repoID: r, worktreeID: newBranch)
            case .browser(let r, let w, let url) where r == repoID && w == oldBranch:
                return .browser(repoID: r, worktreeID: newBranch, url: url)
            case .simulator(let r, let w, let udid) where r == repoID && w == oldBranch:
                return .simulator(repoID: r, worktreeID: newBranch, udid: udid)
            default:
                return nil
            }
        }
        var changed = false
        for pane in tiling.panes where pane.tabs.contains(where: { renamed($0.content) != nil }) {
            tiling.updatePane(pane.id) { p in
                for i in p.tabs.indices where renamed(p.tabs[i].content) != nil {
                    p.tabs[i].content = renamed(p.tabs[i].content)!
                }
            }
            changed = true
        }
        for i in minimizedPanes.indices where minimizedPanes[i].pane.tabs.contains(where: { renamed($0.content) != nil }) {
            let old = minimizedPanes[i]
            var tabs = old.pane.tabs
            for j in tabs.indices where renamed(tabs[j].content) != nil {
                tabs[j].content = renamed(tabs[j].content)!
            }
            minimizedPanes[i] = MinimizedPane(
                pane: Pane(id: old.pane.id, tabs: tabs, activeTabID: old.pane.activeTabID),
                hint: old.hint,
                minimizedAt: old.minimizedAt
            )
            changed = true
        }
        if changed { scheduleSave() }
    }

    func agentSession(repoID: UUID, worktreeID: String, preferredTabID: UUID?) -> TerminalSession? {
        if let preferredTabID, let host = terminalHosts[preferredTabID] {
            return host.session
        }
        for pane in tiling.panes {
            for tab in pane.tabs {
                guard case .terminal(let r, let w) = tab.content, r == repoID, w == worktreeID else { continue }
                if tab.name == "dev" { continue }
                if let host = terminalHosts[tab.id] { return host.session }
            }
        }
        return nil
    }

    private func findBrowserTab(repoID: UUID, worktreeID: String) -> (paneID: UUID, tab: Tab)? {
        for pane in tiling.panes {
            for tab in pane.tabs {
                if case .browser(let r, let w, _) = tab.content, r == repoID, w == worktreeID {
                    return (pane.id, tab)
                }
            }
        }
        return nil
    }

    private func findSimulatorTab(repoID: UUID, worktreeID: String) -> (paneID: UUID, tab: Tab)? {
        for pane in tiling.panes {
            for tab in pane.tabs {
                if case .simulator(let r, let w, _) = tab.content, r == repoID, w == worktreeID {
                    return (pane.id, tab)
                }
            }
        }
        return nil
    }

    /// Pins a simulator pane to a specific device: persists the choice and restreams to it.
    func selectSimulatorDevice(tabID: UUID, udid: String?) {
        for pane in tiling.panes {
            guard let tab = pane.tabs.first(where: { $0.id == tabID }),
                  case .simulator(let repoID, let worktreeID, _) = tab.content else { continue }
            tiling.updatePane(pane.id) { p in
                guard let idx = p.tabs.firstIndex(where: { $0.id == tabID }) else { return }
                p.tabs[idx].content = .simulator(repoID: repoID, worktreeID: worktreeID, udid: udid)
            }
            scheduleSave()
            break
        }
        simulatorHosts[tabID]?.selectDevice(udid)
    }

    func updateBrowserURL(tabID: UUID, url: URL) {
        for pane in tiling.panes {
            guard let tab = pane.tabs.first(where: { $0.id == tabID }),
                  case .browser(let repoID, let worktreeID, let existing) = tab.content,
                  existing != url else { continue }
            tiling.updatePane(pane.id) { p in
                guard let idx = p.tabs.firstIndex(where: { $0.id == tabID }) else { return }
                p.tabs[idx].content = .browser(repoID: repoID, worktreeID: worktreeID, url: url)
            }
            scheduleSave()
            return
        }
    }

    func expandPane(paneID: UUID) {
        expandedPaneID = paneID
        focusedPaneID = paneID
        pendingFocusPaneID = paneID
    }

    func collapseExpandedPane() {
        pendingFocusPaneID = expandedPaneID
        expandedPaneID = nil
    }

    func worktreePath(tabID: UUID) -> String? {
        guard let (_, tab) = locateTab(id: tabID),
              case .terminal(let repoID, let worktreeID) = tab.content,
              let repo = repo(id: repoID) else { return nil }
        return worktreePaths.path(forRepoID: repoID, repoPath: repo.path, branch: worktreeID)
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
        switch tab.content {
        case .terminal(_, let worktreeID): return worktreeID
        case .shell(let cwd): return cwd.lastPathComponent
        case .widget(let kind): return kind.label
        case .tasks: return fallback
        case .browser(_, let worktreeID, _): return worktreeID
        case .simulator(_, let worktreeID, _): return worktreeID
        }
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
            switch $0.activeTab.content {
            case .terminal, .shell: return true
            case .tasks, .widget, .browser, .simulator: return false
            }
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

    func pane(id: UUID) -> Pane? {
        Self.findPane(id: id, in: tiling.root)
    }

    func beginDrag(_ payload: TilingDragPayload) {
        dragSession = DragSession(payload: payload, previewPaneID: UUID())
    }

    func endDrag() {
        dragSession = nil
    }

    func cancelDrag() {
        guard dragSession != nil else { return }
        dragSession?.isCancelled = true
        dragSession?.hover = nil
    }

    func updateHover(_ hover: DragHover?) {
        guard var session = dragSession, !session.isCancelled else { return }
        if session.hover != hover {
            session.hover = hover
            dragSession = session
        }
    }

    var previewLayout: (root: TileNode, highlightID: UUID)? {
        guard let session = dragSession, !session.isCancelled, let hover = session.hover else { return nil }
        return Tiling.simulateDrop(
            payload: session.payload,
            targetID: hover.paneID,
            edge: hover.edge,
            previewPaneID: session.previewPaneID,
            root: tiling.root
        )
    }

    func updateResize(weightsBySplit: [UUID: [Float]], highlightedPaneIDs: Set<UUID>) {
        resizeSession = ResizeSession(weightsBySplit: weightsBySplit, highlightedPaneIDs: highlightedPaneIDs)
    }

    func endResize() {
        resizeSession = nil
    }

    var resizePreview: (root: TileNode, highlightedIDs: Set<UUID>)? {
        guard let session = resizeSession, var root = tiling.root else { return nil }
        for (splitID, weights) in session.weightsBySplit {
            root = Tiling.setWeights(splitID: splitID, weights: weights, in: root)
        }
        return (root, session.highlightedPaneIDs)
    }

    @discardableResult
    func acceptDrop(payload: TilingDragPayload, on targetID: UUID?, edge: TileEdge) -> Bool {
        let cancelled = dragSession?.isCancelled ?? false
        endDrag()
        if cancelled { return false }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            switch payload.kind {
            case .newTerminal(let repoID, let worktreeID):
                let transferred = store?.transferLiveHost(
                    repoID: repoID,
                    branch: worktreeID,
                    target: self,
                    targetPaneID: targetID,
                    edge: edge
                ) ?? false
                if !transferred {
                    let content: TabContent = .terminal(repoID: repoID, worktreeID: worktreeID)
                    if let targetID { splitPane(paneID: targetID, edge: edge, content: content) }
                    else { addPane(content) }
                }
            case .newShell(let cwd):
                let content: TabContent = .shell(cwd: cwd)
                if let targetID { splitPane(paneID: targetID, edge: edge, content: content) }
                else { addPane(content) }
            case .newTaskPane(let listID):
                let content: TabContent = .tasks(listID: listID)
                if let targetID { splitPane(paneID: targetID, edge: edge, content: content) }
                else { addPane(content) }
            case .newWidget(let kind):
                let content: TabContent = .widget(kind)
                if let targetID { splitPane(paneID: targetID, edge: edge, content: content) }
                else { addPane(content) }
            case .movePane(let sourceID):
                if let targetID, sourceID != targetID {
                    if edge == .center {
                        tiling.mergePaneTabs(sourceID: sourceID, targetID: targetID)
                        focusedPaneID = targetID
                    } else {
                        tiling.movePane(sourceID: sourceID, to: edge, adjacentTo: targetID)
                        focusedPaneID = sourceID
                    }
                    scheduleSave()
                }
            }
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
    var minimizedPanes: [MinimizedPane]

    init(id: UUID, name: String, root: TileNode?, minimizedPanes: [MinimizedPane] = []) {
        self.id = id
        self.name = name
        self.root = root
        self.minimizedPanes = minimizedPanes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.root = try c.decodeIfPresent(TileNode.self, forKey: .root)
        self.minimizedPanes = try c.decodeIfPresent([MinimizedPane].self, forKey: .minimizedPanes) ?? []
    }
}

@Observable
final class WorkspaceStore {
    var workspaces: [Workspace] = []
    var selectedWorkspaceID: UUID?

    private let repoStore: RepoStore
    private let taskListStore: TaskListStore
    let worktreePaths: WorktreePaths
    let worktreeStatusService: WorktreeStatusService
    let localHostRegistry: LocalHostRegistry

    var repos: [RepoEntry] { repoStore.repos }

    private static let selectedKey = "selectedWorkspaceID"

    init(repoStore: RepoStore, taskListStore: TaskListStore) {
        self.repoStore = repoStore
        self.taskListStore = taskListStore
        self.worktreePaths = WorktreePaths()
        self.worktreeStatusService = WorktreeStatusService(repoStore: repoStore)
        self.localHostRegistry = LocalHostRegistry()
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
            worktreePaths: worktreePaths,
            worktreeStatusService: worktreeStatusService
        )
        ws.store = self
        workspaces.append(ws)
        sort()
        ws.save()
        selectedWorkspaceID = ws.id
        saveSelection()
        return ws
    }

    func transferLiveHost(
        repoID: UUID,
        branch: String,
        target: Workspace,
        targetPaneID: UUID?,
        edge: TileEdge
    ) -> Bool {
        guard let match = findLiveHost(repoID: repoID, branch: branch),
              match.workspace !== target else { return false }
        let source = match.workspace
        guard let host = source.detachHost(tabID: match.tabID) else { return false }
        source.markStub(tabID: match.tabID, targetWorkspaceID: target.id)

        let content: TabContent = .terminal(repoID: repoID, worktreeID: branch)
        if let targetPaneID {
            target.splitPane(paneID: targetPaneID, edge: edge, content: content)
        } else {
            target.addPane(content)
        }
        guard let newPaneID = target.focusedPaneID,
              let newPane = target.pane(id: newPaneID) else {
            source.adoptHost(host, tabID: match.tabID)
            source.stubTabs.removeValue(forKey: match.tabID)
            return false
        }
        target.adoptHost(host, tabID: newPane.activeTabID)
        return true
    }

    func workerPane(repoID: UUID, branch: String) -> (workspace: Workspace, paneID: UUID, tabID: UUID)? {
        for ws in workspaces {
            for pane in ws.tiling.panes + ws.minimizedPanes.map(\.pane) {
                for tab in pane.tabs {
                    guard case .terminal(let r, let b) = tab.content,
                          r == repoID, b == branch,
                          ws.terminalHosts[tab.id] != nil,
                          ws.stubTabs[tab.id] == nil else { continue }
                    return (ws, pane.id, tab.id)
                }
            }
        }
        return nil
    }

    func agentSession(repoID: UUID, branch: String) -> TerminalSession? {
        guard let (ws, _, tabID) = workerPane(repoID: repoID, branch: branch) else { return nil }
        return ws.terminalHosts[tabID]?.session
    }

    @discardableResult
    func focusWorkerPane(repoID: UUID, branch: String) -> Bool {
        guard let (ws, paneID, tabID) = workerPane(repoID: repoID, branch: branch) else { return false }
        selectedWorkspaceID = ws.id
        saveSelection()
        if ws.minimizedPanes.contains(where: { $0.pane.id == paneID }) {
            ws.restoreMinimizedPane(paneID: paneID)
        }
        ws.setActiveTab(paneID: paneID, tabID: tabID)
        ws.setFocus(paneID: paneID)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows
            .first { $0.canBecomeKey && $0.identifier?.rawValue.contains("pluri") != true && !($0 is NSPanel) }?
            .makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { ws.terminalHosts[tabID]?.focusInput() }
        return true
    }

    private func findLiveHost(repoID: UUID, branch: String) -> (workspace: Workspace, tabID: UUID)? {
        for ws in workspaces {
            for pane in ws.tiling.panes {
                for tab in pane.tabs {
                    guard case .terminal(let r, let b) = tab.content,
                          r == repoID, b == branch,
                          ws.terminalHosts[tab.id] != nil,
                          ws.stubTabs[tab.id] == nil else { continue }
                    return (ws, tab.id)
                }
            }
        }
        return nil
    }

    func renameWorkspace(id: UUID, name: String) {
        guard let ws = workspaces.first(where: { $0.id == id }) else { return }
        ws.rename(name)
        sort()
    }

    func removeWorkspace(id: UUID) {
        if let ws = workspaces.first(where: { $0.id == id }) {
            ws.isDeleted = true
        }
        workspaces.removeAll { $0.id == id }
        localHostRegistry.remove(workspaceID: id)
        let url = Workspace.workspacesDir.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
        if selectedWorkspaceID == id {
            selectedWorkspaceID = workspaces.first?.id
            saveSelection()
        }
    }

    @MainActor
    func deleteWorktree(repo: RepoEntry, worktree: Worktree, pinStore: PinStore) async {
        guard let wm = WorktreeManager(repoRoot: repo.path) else { return }
        pinStore.removeWorktree(repoID: repo.id, branch: worktree.branch)
        removePanes(repoID: repo.id, worktreeID: worktree.branch)
        try? await wm.removeWorktree(at: URL(fileURLWithPath: worktree.path))
        _ = try? await ProcessRunner.run("git", args: ["-C", repo.path.path, "branch", "-D", worktree.branch])
        worktreePaths.invalidate(repoID: repo.id)
        worktreeStatusService.invalidate(repoID: repo.id)
    }

    func renameWorktreeReferences(repoID: UUID, oldBranch: String, newBranch: String) {
        guard oldBranch != newBranch else { return }
        for ws in workspaces {
            ws.renameWorktreeReferences(repoID: repoID, oldBranch: oldBranch, newBranch: newBranch)
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
            let minimizedTargets = ws.minimizedPanes.filter { item in
                item.pane.tabs.contains { tab in
                    if case .terminal(let r, let w) = tab.content { return r == repoID && w == worktreeID }
                    return false
                }
            }
            for item in minimizedTargets {
                ws.closeMinimizedPane(paneID: item.pane.id)
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
            let ws = Workspace(
                id: snap.id,
                name: snap.name,
                root: snap.root,
                minimizedPanes: snap.minimizedPanes,
                repoStore: repoStore,
                taskListStore: taskListStore,
                worktreePaths: worktreePaths,
                worktreeStatusService: worktreeStatusService
            )
            ws.store = self
            return ws
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
