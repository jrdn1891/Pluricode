import Foundation
import Observation
import CoreGraphics
import CoreTransferable

enum TileDirection: String, Codable {
    case horizontal
    case vertical
}

enum TileEdge: String, Codable {
    case top, bottom, left, right, center

    var direction: TileDirection {
        switch self {
        case .top, .bottom: .vertical
        case .left, .right: .horizontal
        case .center: .horizontal
        }
    }

    var insertsBefore: Bool {
        switch self {
        case .top, .left: true
        case .bottom, .right, .center: false
        }
    }

    static func zone(for point: CGPoint, in size: CGSize) -> TileEdge {
        guard size.width > 0, size.height > 0 else { return .center }
        let leftFrac = point.x / size.width
        let rightFrac = 1 - leftFrac
        let topFrac = point.y / size.height
        let bottomFrac = 1 - topFrac
        let threshold: CGFloat = 0.25
        let minVal = min(leftFrac, rightFrac, topFrac, bottomFrac)
        guard minVal < threshold else { return .center }
        if minVal == leftFrac { return .left }
        if minVal == rightFrac { return .right }
        if minVal == topFrac { return .top }
        return .bottom
    }
}

struct TilingDragPayload: Codable, Transferable, Hashable {
    enum Kind: Codable, Hashable {
        case newTerminal(repoID: UUID, worktreeID: String)
        case newShell(cwd: URL)
        case newTaskPane(listID: UUID)
        case newWidget(WidgetKind)
        case movePane(paneID: UUID)
    }
    let kind: Kind

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .plainText)
    }
}

enum WidgetKind: String, Hashable, Codable {
    case localHosts

    var label: String {
        switch self {
        case .localHosts: "Local Hosts"
        }
    }

    var systemImage: String {
        switch self {
        case .localHosts: "network"
        }
    }
}

enum TabContent: Hashable, Codable {
    case terminal(repoID: UUID, worktreeID: String)
    case shell(cwd: URL)
    case tasks(listID: UUID)
    case widget(WidgetKind)
    case browser(repoID: UUID, worktreeID: String, url: URL?)
    case simulator(repoID: UUID, worktreeID: String, udid: String?)
}

struct Tab: Identifiable, Hashable, Codable {
    let id: UUID
    var content: TabContent
    var name: String?

    init(id: UUID = UUID(), content: TabContent, name: String? = nil) {
        self.id = id
        self.content = content
        self.name = name
    }
}

struct Pane: Identifiable, Hashable, Codable {
    let id: UUID
    var tabs: [Tab]
    var activeTabID: UUID

    init(id: UUID = UUID(), tabs: [Tab], activeTabID: UUID? = nil) {
        precondition(!tabs.isEmpty, "Pane must have at least one tab")
        self.id = id
        self.tabs = tabs
        self.activeTabID = activeTabID ?? tabs[0].id
    }

    init(content: TabContent, name: String? = nil) {
        let tab = Tab(content: content, name: name)
        self.init(id: UUID(), tabs: [tab], activeTabID: tab.id)
    }

    var activeTab: Tab {
        tabs.first { $0.id == activeTabID } ?? tabs[0]
    }
}

struct RestoreHint: Hashable, Codable {
    let siblingPaneID: UUID?
    let edge: TileEdge
}

struct MinimizedPane: Identifiable, Hashable, Codable {
    let pane: Pane
    let hint: RestoreHint
    let minimizedAt: Date
    var id: UUID { pane.id }
}

struct Split: Identifiable, Hashable, Codable {
    let id: UUID
    var direction: TileDirection
    var children: [TileNode]
    var weights: [Float]
}

indirect enum TileNode: Identifiable, Hashable, Codable {
    case pane(Pane)
    case split(Split)

    var id: UUID {
        switch self {
        case .pane(let p): p.id
        case .split(let s): s.id
        }
    }
}

@Observable
final class Tiling {
    var root: TileNode?

    init(root: TileNode? = nil) {
        self.root = root
    }

    func addPane(_ content: TabContent) -> UUID {
        let pane = Pane(content: content)
        if let existingRoot = root, let firstPaneID = Self.allPanes(in: existingRoot).first?.id {
            root = Self.insertSibling(pane, at: .right, adjacentTo: firstPaneID, in: existingRoot)
        } else {
            root = .pane(pane)
        }
        return pane.id
    }

    func split(paneID: UUID, edge: TileEdge, newContent: TabContent) -> UUID {
        guard let current = root else {
            let pane = Pane(content: newContent)
            root = .pane(pane)
            return pane.id
        }
        if edge == .center {
            let tab = Tab(content: newContent)
            root = Self.update(paneID: paneID, in: current) { p in
                p.tabs.append(tab)
                p.activeTabID = tab.id
            }
            return paneID
        }
        let newPane = Pane(content: newContent)
        root = Self.insertSibling(newPane, at: edge, adjacentTo: paneID, in: current)
        return newPane.id
    }

    func remove(paneID: UUID) {
        guard let current = root else { return }
        root = Self.remove(paneID: paneID, from: current)
    }

    func setWeights(splitID: UUID, weights: [Float]) {
        guard let current = root else { return }
        root = Self.setWeights(splitID: splitID, weights: weights, in: current)
    }

    func movePane(sourceID: UUID, to edge: TileEdge, adjacentTo targetID: UUID) {
        guard sourceID != targetID, edge != .center, let current = root else { return }
        guard let source = Self.findPaneStruct(id: sourceID, in: current) else { return }
        guard let afterRemoval = Self.remove(paneID: sourceID, from: current) else {
            root = .pane(source)
            return
        }
        root = Self.insertSibling(source, at: edge, adjacentTo: targetID, in: afterRemoval)
    }

    func mergePaneTabs(sourceID: UUID, targetID: UUID) {
        guard sourceID != targetID, let current = root else { return }
        guard let source = Self.findPaneStruct(id: sourceID, in: current) else { return }
        guard let afterRemoval = Self.remove(paneID: sourceID, from: current) else { return }
        root = Self.update(paneID: targetID, in: afterRemoval) { p in
            p.tabs.append(contentsOf: source.tabs)
            p.activeTabID = source.activeTabID
        }
    }

    func reinsertPane(_ pane: Pane, near siblingID: UUID?, edge: TileEdge) {
        guard let existingRoot = root else {
            root = .pane(pane)
            return
        }
        if let siblingID, Self.findPaneStruct(id: siblingID, in: existingRoot) != nil {
            root = Self.insertSibling(pane, at: edge, adjacentTo: siblingID, in: existingRoot)
            return
        }
        if let firstID = Self.allPanes(in: existingRoot).first?.id {
            root = Self.insertSibling(pane, at: .right, adjacentTo: firstID, in: existingRoot)
        } else {
            root = .pane(pane)
        }
    }

    func updatePane(_ paneID: UUID, _ transform: (inout Pane) -> Void) {
        guard let current = root else { return }
        root = Self.update(paneID: paneID, in: current, transform: transform)
    }

    var panes: [Pane] {
        guard let root else { return [] }
        return Self.allPanes(in: root)
    }
}

extension Tiling {
    static func allPanes(in node: TileNode) -> [Pane] {
        switch node {
        case .pane(let p): [p]
        case .split(let s): s.children.flatMap { allPanes(in: $0) }
        }
    }

    static func insertSibling(_ newPane: Pane, at edge: TileEdge, adjacentTo targetID: UUID, in node: TileNode) -> TileNode {
        switch node {
        case .pane(let p):
            guard p.id == targetID else { return node }
            let old = TileNode.pane(p)
            let new = TileNode.pane(newPane)
            let children = edge.insertsBefore ? [new, old] : [old, new]
            return .split(Split(id: UUID(), direction: edge.direction, children: children, weights: [0.5, 0.5]))

        case .split(var split):
            if split.direction == edge.direction,
               let idx = split.children.firstIndex(where: { isPane($0, id: targetID) }) {
                let insertIdx = edge.insertsBefore ? idx : idx + 1
                split.children.insert(.pane(newPane), at: insertIdx)
                split.weights = Array(repeating: 1.0 / Float(split.children.count), count: split.children.count)
                return .split(split)
            }
            split.children = split.children.map { insertSibling(newPane, at: edge, adjacentTo: targetID, in: $0) }
            return .split(split)
        }
    }

    static func remove(paneID: UUID, from node: TileNode) -> TileNode? {
        switch node {
        case .pane(let p):
            return p.id == paneID ? nil : node
        case .split(var split):
            var kept: [TileNode] = []
            var didRemove = false
            for child in split.children {
                if let next = remove(paneID: paneID, from: child) {
                    kept.append(next)
                } else {
                    didRemove = true
                }
            }
            if !didRemove {
                split.children = kept
                return .split(split)
            }
            if kept.count == 1 { return kept[0] }
            if kept.isEmpty { return nil }
            split.children = kept
            split.weights = Array(repeating: 1.0 / Float(kept.count), count: kept.count)
            return .split(split)
        }
    }

    static func setWeights(splitID: UUID, weights: [Float], in node: TileNode) -> TileNode {
        switch node {
        case .pane: return node
        case .split(var split):
            if split.id == splitID {
                split.weights = weights
                return .split(split)
            }
            split.children = split.children.map { setWeights(splitID: splitID, weights: weights, in: $0) }
            return .split(split)
        }
    }

    static func update(paneID: UUID, in node: TileNode, transform: (inout Pane) -> Void) -> TileNode {
        switch node {
        case .pane(var p):
            if p.id == paneID {
                transform(&p)
                return .pane(p)
            }
            return node
        case .split(var split):
            split.children = split.children.map { update(paneID: paneID, in: $0, transform: transform) }
            return .split(split)
        }
    }

    static func isPane(_ node: TileNode, id: UUID) -> Bool {
        if case .pane(let p) = node, p.id == id { return true }
        return false
    }

    static func simulateDrop(
        payload: TilingDragPayload,
        targetID: UUID?,
        edge: TileEdge,
        previewPaneID: UUID,
        root: TileNode?
    ) -> (root: TileNode, highlightID: UUID)? {
        switch payload.kind {
        case .newTerminal(let repoID, let worktreeID):
            return simulateAdd(content: .terminal(repoID: repoID, worktreeID: worktreeID),
                               targetID: targetID, edge: edge, previewPaneID: previewPaneID, root: root)
        case .newShell(let cwd):
            return simulateAdd(content: .shell(cwd: cwd),
                               targetID: targetID, edge: edge, previewPaneID: previewPaneID, root: root)
        case .newTaskPane(let listID):
            return simulateAdd(content: .tasks(listID: listID),
                               targetID: targetID, edge: edge, previewPaneID: previewPaneID, root: root)
        case .newWidget(let kind):
            return simulateAdd(content: .widget(kind),
                               targetID: targetID, edge: edge, previewPaneID: previewPaneID, root: root)
        case .movePane(let sourceID):
            return simulateMove(sourceID: sourceID, targetID: targetID, edge: edge, root: root)
        }
    }

    private static func simulateAdd(content: TabContent, targetID: UUID?, edge: TileEdge, previewPaneID: UUID, root: TileNode?) -> (TileNode, UUID) {
        let newPane = Pane(id: previewPaneID, tabs: [Tab(content: content)])
        guard let root else { return (.pane(newPane), previewPaneID) }
        guard let targetID else {
            guard let firstID = allPanes(in: root).first?.id else {
                return (.pane(newPane), previewPaneID)
            }
            return (insertSibling(newPane, at: .right, adjacentTo: firstID, in: root), previewPaneID)
        }
        if edge == .center {
            let next = update(paneID: targetID, in: root) { p in
                p.tabs.append(Tab(content: content))
            }
            return (next, targetID)
        }
        return (insertSibling(newPane, at: edge, adjacentTo: targetID, in: root), previewPaneID)
    }

    private static func simulateMove(sourceID: UUID, targetID: UUID?, edge: TileEdge, root: TileNode?) -> (TileNode, UUID)? {
        guard let root, let targetID, sourceID != targetID else { return nil }
        guard let source = findPaneStruct(id: sourceID, in: root) else { return nil }
        guard let afterRemoval = remove(paneID: sourceID, from: root) else { return nil }
        if edge == .center {
            let next = update(paneID: targetID, in: afterRemoval) { p in
                p.tabs.append(contentsOf: source.tabs)
            }
            return (next, targetID)
        }
        return (insertSibling(source, at: edge, adjacentTo: targetID, in: afterRemoval), sourceID)
    }

    static func captureRestoreHint(for paneID: UUID, in node: TileNode?) -> RestoreHint {
        guard let node, let hint = findHint(paneID: paneID, in: node) else {
            return RestoreHint(siblingPaneID: nil, edge: .right)
        }
        return hint
    }

    private static func findHint(paneID: UUID, in node: TileNode) -> RestoreHint? {
        guard case .split(let split) = node else { return nil }
        if let idx = split.children.firstIndex(where: { isPane($0, id: paneID) }) {
            let preferLeft = idx > 0
            let siblingNode = preferLeft ? split.children[idx - 1] : split.children[idx + 1]
            let siblingID = allPanes(in: siblingNode).first?.id
            let edge: TileEdge
            switch split.direction {
            case .horizontal: edge = preferLeft ? .right : .left
            case .vertical: edge = preferLeft ? .bottom : .top
            }
            return RestoreHint(siblingPaneID: siblingID, edge: edge)
        }
        for child in split.children {
            if let hint = findHint(paneID: paneID, in: child) { return hint }
        }
        return nil
    }

    static func findPaneStruct(id: UUID, in node: TileNode) -> Pane? {
        switch node {
        case .pane(let p):
            return p.id == id ? p : nil
        case .split(let s):
            for child in s.children {
                if let found = findPaneStruct(id: id, in: child) { return found }
            }
            return nil
        }
    }
}
