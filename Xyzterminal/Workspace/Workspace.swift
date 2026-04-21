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
    let repo: RepoEntry
    let profileStore: AgentProfileStore
    let tiling: Tiling
    let taskStore: TaskStore
    var terminalHosts: [UUID: TerminalHost] = [:]
    var focusedPaneID: UUID?

    private var saveTask: Task<Void, Never>?

    init(repo: RepoEntry, profileStore: AgentProfileStore, taskStore: TaskStore) {
        self.repo = repo
        self.profileStore = profileStore
        self.tiling = Tiling()
        self.taskStore = taskStore
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
            host.saveScrollback(to: scrollbackDir)
            host.teardown()
        }
        tiling.remove(paneID: paneID)
        if focusedPaneID == paneID { focusedPaneID = nil }
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

    func pane(id: UUID) -> Pane? {
        Self.findPane(id: id, in: tiling.root)
    }

    @discardableResult
    func acceptDrop(payload: TilingDragPayload, on targetID: UUID?, edge: TileEdge) -> Bool {
        switch payload.kind {
        case .newTerminal(let wid):
            let content: PaneContent = .terminal(worktreeID: wid)
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
    var root: TileNode?
}
