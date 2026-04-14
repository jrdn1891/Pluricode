import Foundation
import Observation
import simd

@Observable
final class CanvasDocument {
    var nodes: [UUID: CanvasNode] = [:]
    var edges: [UUID: Edge] = [:]
    var agentProfiles: [UUID: AgentProfile] = Dictionary(uniqueKeysWithValues: AgentProfile.defaults.map { ($0.id, $0) })
    var camera = Camera()
    var selectedNodeIDs: Set<UUID> = []
    var selectedEdgeID: UUID?
    var snapToGrid = false
    var selectionRect: SelectionRect?
    var edgeDrag: EdgeDrag?
    var editingNodeID: UUID?
    var projectPath: URL?
    var showTerminalConfig = false
    var minimapCollapsed = false
    var showWorktreePanel = false
    var pendingTerminalDeletions: Set<UUID> = []
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
        let size = kind.defaultSize
        let jitter = SIMD2<Float>(Float.random(in: -30...30), Float.random(in: -30...30))
        let position = camera.offset - size * 0.5 + jitter
        let node = CanvasNode(id: UUID(), position: position, size: size, kind: kind)
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

    static func nodeBounds(_ nodes: some Collection<CanvasNode>) -> (min: SIMD2<Float>, max: SIMD2<Float>)? {
        guard !nodes.isEmpty else { return nil }
        var minP = SIMD2<Float>(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxP = SIMD2<Float>(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        for node in nodes {
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
        let terminalIDs = idsToDelete.filter { id in
            if case .terminal = nodes[id]?.kind { return true }
            return false
        }

        if !terminalIDs.isEmpty {
            pendingTerminalDeletions = idsToDelete
            return
        }

        removeNodes(idsToDelete)
    }

    func confirmTerminalDeletion(cleanup: Bool) {
        let ids = pendingTerminalDeletions
        pendingTerminalDeletions.removeAll()
        removeNodes(ids)
        if cleanup {
            mcpServer?.terminalManager?.cleanupWorktrees(
                ids.compactMap { id -> String? in
                    guard case .terminal(let d) = nodes[id]?.kind else { return nil }
                    return d.worktreePath
                }
            )
        }
    }

    private func removeNodes(_ ids: Set<UUID>) {
        for id in ids { nodes.removeValue(forKey: id) }
        if !ids.isEmpty {
            edges = edges.filter { !ids.contains($0.value.sourceID) && !ids.contains($0.value.targetID) }
        }
        selectedNodeIDs.removeAll()
        scheduleSave()
    }

    func unresolvedBlockers(for nodeID: UUID) -> [UUID] {
        edges.values.compactMap { edge in
            guard edge.targetID == nodeID, (edge.edgeType == .blocks || edge.edgeType == .flowsTo) else { return nil }
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
    var condition: String?
    var payloadLog: [EdgePayload] = []
}

struct EdgePayload: Codable, Identifiable {
    let id: UUID
    var timestamp: Date
    var summary: String
    var branchRef: String?
}

enum EdgeType: String, Codable {
    case handsOffTo, reviews, assignedTo, blocks, blockedBy, flowsTo
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
