import Foundation
import Observation
import simd

@Observable
final class CanvasDocument {
    var nodes: [UUID: CanvasNode] = [:]
    var edges: [UUID: Edge] = [:]
    var groups: [UUID: NodeGroup] = [:]
    var camera = Camera()
    var selectedNodeIDs: Set<UUID> = []
    var selectedEdgeID: UUID?
    var snapToGrid = false
    var selectionRect: SelectionRect?
    var edgeDrag: EdgeDrag?
    var editingNodeID: UUID?
    var editingGroupID: UUID?
    var projectPath: URL?
    var showTerminalConfig = false
    var minimapCollapsed = false
    var showWorktreePanel = false
    var pendingWorktreeDeletions: [String] = []
    var mcpServer: MCPServer?
    var inlineEditingNodeID: UUID?
    var onStartInlineEdit: ((UUID) -> Void)?

    private var saveTask: Task<Void, Never>?

    deinit {
        saveTask?.cancel()
        Persistence.save(self)
        mcpServer?.stop()
    }

    @discardableResult
    func addNode(kind: NodeKind) -> UUID {
        let defaultSize: SIMD2<Float> = switch kind {
        case .terminal: SIMD2<Float>(400, 300)
        case .taskCard: SIMD2<Float>(250, 100)
        }
        let jitter = SIMD2<Float>(Float.random(in: -30...30), Float.random(in: -30...30))
        let position = camera.offset - defaultSize * 0.5 + jitter
        let node = CanvasNode(id: UUID(), position: position, size: defaultSize, kind: kind)
        nodes[node.id] = node
        scheduleSave()
        return node.id
    }

    func addEdge(from sourceID: UUID, to targetID: UUID, type: EdgeType) {
        let alreadyExists = edges.values.contains { $0.sourceID == sourceID && $0.targetID == targetID }
        guard !alreadyExists, sourceID != targetID else { return }
        let edge = Edge(id: UUID(), sourceID: sourceID, targetID: targetID, edgeType: type)
        edges[edge.id] = edge
        scheduleSave()
    }

    func groupSelected(name: String = "Group") {
        guard selectedNodeIDs.count >= 2 else { return }
        for (id, group) in groups {
            var updated = group
            updated.nodeIDs.subtract(selectedNodeIDs)
            if updated.nodeIDs.isEmpty {
                groups.removeValue(forKey: id)
            } else {
                groups[id] = updated
            }
        }
        let group = NodeGroup(id: UUID(), name: name, nodeIDs: selectedNodeIDs)
        groups[group.id] = group
        scheduleSave()
    }

    func ungroupSelected() {
        let selected = selectedNodeIDs
        for (id, group) in groups {
            if !group.nodeIDs.isDisjoint(with: selected) {
                groups.removeValue(forKey: id)
            }
        }
        scheduleSave()
    }

    func groupBounds(for group: NodeGroup) -> (min: SIMD2<Float>, max: SIMD2<Float>)? {
        let memberNodes = group.nodeIDs.compactMap { nodes[$0] }
        guard !memberNodes.isEmpty else { return nil }
        var minP = SIMD2<Float>(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxP = SIMD2<Float>(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        for node in memberNodes {
            minP = simd_min(minP, node.position)
            maxP = simd_max(maxP, node.position + node.size)
        }
        return (minP, maxP)
    }

    func deleteSelected() {
        if let edgeID = selectedEdgeID {
            edges.removeValue(forKey: edgeID)
            selectedEdgeID = nil
        }
        let idsToDelete = selectedNodeIDs
        for id in idsToDelete {
            nodes.removeValue(forKey: id)
        }
        if !idsToDelete.isEmpty {
            edges = edges.filter { !idsToDelete.contains($0.value.sourceID) && !idsToDelete.contains($0.value.targetID) }
            for (gid, group) in groups {
                var updated = group
                updated.nodeIDs.subtract(idsToDelete)
                if updated.nodeIDs.count < 2 {
                    groups.removeValue(forKey: gid)
                } else {
                    groups[gid] = updated
                }
            }
        }
        selectedNodeIDs.removeAll()
        scheduleSave()
    }

    func unresolvedBlockers(for nodeID: UUID) -> [UUID] {
        edges.values.compactMap { edge in
            guard edge.targetID == nodeID, edge.edgeType == .blocks else { return nil }
            guard let source = nodes[edge.sourceID],
                  case .taskCard(let data) = source.kind,
                  data.status != .done else { return nil }
            return edge.sourceID
        }
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            Persistence.save(self)
        }
    }
}

struct Edge: Identifiable, Codable {
    let id: UUID
    var sourceID: UUID
    var targetID: UUID
    var edgeType: EdgeType
    var payloadLog: [EdgePayload] = []
}

struct EdgePayload: Codable, Identifiable {
    let id: UUID
    var timestamp: Date
    var summary: String
    var branchRef: String?
}

enum EdgeType: String, Codable {
    case handsOffTo, reviews, assignedTo, blocks, blockedBy
}

struct SelectionRect {
    var origin: SIMD2<Float>
    var size: SIMD2<Float>
}

struct EdgeDrag {
    var sourceNodeID: UUID
    var currentPoint: SIMD2<Float>
}

struct EditingNode: Identifiable {
    let id: UUID
}

struct NodeGroup: Identifiable, Codable {
    let id: UUID
    var name: String
    var nodeIDs: Set<UUID>
    var color: SIMD4<Float> = SIMD4<Float>(0.4, 0.5, 0.7, 0.15)
}
