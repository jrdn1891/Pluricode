import Foundation
import Observation
import simd

@Observable
final class CanvasDocument {
    var nodes: [UUID: CanvasNode] = [:]
    var edges: [UUID: Edge] = [:]
    var camera = Camera()
    var selectedNodeIDs: Set<UUID> = []
    var selectedEdgeID: UUID?
    var snapToGrid = false
    var selectionRect: SelectionRect?
    var edgeDrag: EdgeDrag?
    var editingNodeID: UUID?
    var projectPath: URL?
    var showTerminalConfig = false
    var mcpServer: MCPServer?

    private var saveTask: Task<Void, Never>?

    func addNode(kind: NodeKind) {
        let defaultSize: SIMD2<Float> = switch kind {
        case .terminal: SIMD2<Float>(400, 300)
        case .taskCard: SIMD2<Float>(250, 100)
        }
        let jitter = SIMD2<Float>(Float.random(in: -30...30), Float.random(in: -30...30))
        let position = camera.offset - defaultSize * 0.5 + jitter
        let node = CanvasNode(id: UUID(), position: position, size: defaultSize, kind: kind)
        nodes[node.id] = node
        scheduleSave()
    }

    func addEdge(from sourceID: UUID, to targetID: UUID, type: EdgeType) {
        let alreadyExists = edges.values.contains { $0.sourceID == sourceID && $0.targetID == targetID }
        guard !alreadyExists, sourceID != targetID else { return }
        let edge = Edge(id: UUID(), sourceID: sourceID, targetID: targetID, edgeType: type)
        edges[edge.id] = edge
        scheduleSave()
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
        }
        selectedNodeIDs.removeAll()
        scheduleSave()
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
