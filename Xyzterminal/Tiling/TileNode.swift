import Foundation
import Observation

enum TileDirection: String, Codable {
    case horizontal
    case vertical
}

enum TileEdge {
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
}

struct Pane: Identifiable, Hashable {
    let id: UUID
    var content: PaneContent
}

enum PaneContent: Hashable {
    case placeholder(label: String)
}

struct Split: Identifiable, Hashable {
    let id: UUID
    var direction: TileDirection
    var children: [TileNode]
    var weights: [Float]
}

indirect enum TileNode: Identifiable, Hashable {
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

    func addPane(_ content: PaneContent) -> UUID {
        let pane = Pane(id: UUID(), content: content)
        if let existingRoot = root, let firstPaneID = Self.allPanes(in: existingRoot).first?.id {
            root = Self.insertSibling(pane, at: .right, adjacentTo: firstPaneID, in: existingRoot)
        } else {
            root = .pane(pane)
        }
        return pane.id
    }

    func split(paneID: UUID, edge: TileEdge, newContent: PaneContent) -> UUID {
        guard let current = root else {
            let pane = Pane(id: UUID(), content: newContent)
            root = .pane(pane)
            return pane.id
        }
        let newPane = Pane(id: UUID(), content: newContent)
        if edge == .center {
            root = Self.replace(paneID: paneID, with: newPane, in: current)
        } else {
            root = Self.insertSibling(newPane, at: edge, adjacentTo: paneID, in: current)
        }
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

    static func replace(paneID: UUID, with newPane: Pane, in node: TileNode) -> TileNode {
        switch node {
        case .pane(let p):
            return p.id == paneID ? .pane(newPane) : node
        case .split(var split):
            split.children = split.children.map { replace(paneID: paneID, with: newPane, in: $0) }
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

    static func isPane(_ node: TileNode, id: UUID) -> Bool {
        if case .pane(let p) = node, p.id == id { return true }
        return false
    }
}
