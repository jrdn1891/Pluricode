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
    let profileStore: AgentProfileStore
    var terminalHosts: [UUID: TerminalHost] = [:]
    var focusedPaneID: UUID?

    private var saveTask: Task<Void, Never>?

    init(
        id: UUID = UUID(),
        name: String,
        root: TileNode? = nil,
        repoStore: RepoStore,
        taskListStore: TaskListStore,
        profileStore: AgentProfileStore
    ) {
        self.id = id
        self.name = name
        self.tiling = Tiling(root: root)
        self.repoStore = repoStore
        self.taskListStore = taskListStore
        self.profileStore = profileStore
    }

    deinit {
        saveTask?.cancel()
        save()
        for host in terminalHosts.values { host.teardown() }
    }

    static var rootDir: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Xyzterminal", isDirectory: true)
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
        let snapshot = WorkspaceSnapshot(id: id, name: name, root: tiling.root)
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

    func addPane(_ content: PaneContent) {
        let id = tiling.addPane(content)
        focusedPaneID = id
        scheduleSave()
    }

    func splitPane(paneID: UUID, edge: TileEdge, content: PaneContent) {
        let id = tiling.split(paneID: paneID, edge: edge, newContent: content)
        focusedPaneID = id
        scheduleSave()
    }

    func closePane(paneID: UUID) {
        if let host = terminalHosts.removeValue(forKey: paneID) {
            host.saveScrollback(to: Self.scrollbackDir)
            host.teardown()
        }
        tiling.remove(paneID: paneID)
        if focusedPaneID == paneID { focusedPaneID = tiling.panes.first?.id }
        scheduleSave()
    }

    func setWeights(splitID: UUID, weights: [Float]) {
        tiling.setWeights(splitID: splitID, weights: weights)
        scheduleSave()
    }

    func setFocus(paneID: UUID?) {
        focusedPaneID = paneID
    }

    func closeFocusedPane() {
        guard let id = focusedPaneID else { return }
        closePane(paneID: id)
    }

    func splitFocusedPane(direction: TileDirection) {
        guard let id = focusedPaneID, let pane = pane(id: id) else { return }
        let edge: TileEdge = direction == .horizontal ? .right : .bottom
        splitPane(paneID: id, edge: edge, content: pane.content)
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

    func performPaneCreation(_ action: PaneCreationAction, content: PaneContent) {
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
            let content: PaneContent = .terminal(repoID: repoID, worktreeID: worktreeID)
            if let targetID { splitPane(paneID: targetID, edge: edge, content: content) }
            else { addPane(content) }
        case .newTaskPane(let listID):
            let content: PaneContent = .tasks(listID: listID)
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
}

@Observable
final class WorkspaceStore {
    var workspaces: [Workspace] = []
    var selectedWorkspaceID: UUID?

    private let repoStore: RepoStore
    private let taskListStore: TaskListStore
    private let profileStore: AgentProfileStore

    private static let selectedKey = "selectedWorkspaceID"

    init(repoStore: RepoStore, taskListStore: TaskListStore, profileStore: AgentProfileStore) {
        self.repoStore = repoStore
        self.taskListStore = taskListStore
        self.profileStore = profileStore
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
            profileStore: profileStore
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
                repoStore: repoStore,
                taskListStore: taskListStore,
                profileStore: profileStore
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
