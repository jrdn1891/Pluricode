import AppKit
import simd

final class CanvasInputHandler {
    let document: CanvasDocument
    weak var view: NSView?

    var terminalManager: TerminalManager?

    private enum DragState {
        case none
        case movingNodes(startPositions: [UUID: SIMD2<Float>], startMouse: SIMD2<Float>)
        case boxSelecting(startCanvas: SIMD2<Float>)
        case creatingEdge(sourceID: UUID)
    }

    private var dragState: DragState = .none

    init(document: CanvasDocument, view: NSView) {
        self.document = document
        self.view = view
    }

    private var viewportSize: CGSize {
        view?.bounds.size ?? CGSize(width: 800, height: 600)
    }

    func handleScroll(_ event: NSEvent) {
        var dx = Float(event.scrollingDeltaX)
        var dy = Float(event.scrollingDeltaY)
        if !event.hasPreciseScrollingDeltas {
            dx *= 10
            dy *= 10
        }
        document.camera.offset.x -= dx / document.camera.zoom
        document.camera.offset.y -= dy / document.camera.zoom
    }

    func handleMagnify(_ event: NSEvent) {
        guard let view else { return }
        let screenPoint = view.convert(event.locationInWindow, from: nil)
        let canvasPoint = document.camera.screenToCanvas(screenPoint, viewportSize: viewportSize)

        document.camera.zoom *= (1.0 + Float(event.magnification))
        document.camera.clampZoom()

        let halfW = Float(viewportSize.width) * 0.5
        let halfH = Float(viewportSize.height) * 0.5
        let flippedY = Float(viewportSize.height) - Float(screenPoint.y)

        document.camera.offset.x = canvasPoint.x - (Float(screenPoint.x) - halfW) / document.camera.zoom
        document.camera.offset.y = canvasPoint.y - (flippedY - halfH) / document.camera.zoom
    }

    func handleMouseDown(_ event: NSEvent) {
        guard let view else { return }
        let screenPoint = view.convert(event.locationInWindow, from: nil)
        let canvasPoint = document.camera.screenToCanvas(screenPoint, viewportSize: viewportSize)
        let optionHeld = NSEvent.modifierFlags.contains(.option)

        if event.clickCount == 2 {
            if let hitID = HitTesting.nodeAt(canvasPoint, in: document.nodes),
               case .taskCard = document.nodes[hitID]?.kind {
                document.editingNodeID = hitID
            }
            return
        }

        if let hitID = HitTesting.nodeAt(canvasPoint, in: document.nodes) {
            document.selectedEdgeID = nil
            if optionHeld {
                dragState = .creatingEdge(sourceID: hitID)
                document.edgeDrag = EdgeDrag(sourceNodeID: hitID, currentPoint: canvasPoint)
                return
            }

            let shiftHeld = NSEvent.modifierFlags.contains(.shift)
            if shiftHeld {
                if document.selectedNodeIDs.contains(hitID) {
                    document.selectedNodeIDs.remove(hitID)
                } else {
                    document.selectedNodeIDs.insert(hitID)
                }
            } else if !document.selectedNodeIDs.contains(hitID) {
                document.selectedNodeIDs = [hitID]
            }

            var startPositions: [UUID: SIMD2<Float>] = [:]
            for id in document.selectedNodeIDs {
                if let node = document.nodes[id] {
                    startPositions[id] = node.position
                }
            }
            dragState = .movingNodes(startPositions: startPositions, startMouse: canvasPoint)
        } else if let edgeID = HitTesting.edgeAt(canvasPoint, in: document.edges, nodes: document.nodes, threshold: 12 / document.camera.zoom) {
            document.selectedNodeIDs.removeAll()
            document.selectedEdgeID = edgeID
            dragState = .none
        } else {
            document.selectedEdgeID = nil
            if !NSEvent.modifierFlags.contains(.shift) {
                document.selectedNodeIDs.removeAll()
            }
            dragState = .boxSelecting(startCanvas: canvasPoint)
        }
    }

    func handleMouseDragged(_ event: NSEvent) {
        guard let view else { return }
        let screenPoint = view.convert(event.locationInWindow, from: nil)
        let canvasPoint = document.camera.screenToCanvas(screenPoint, viewportSize: viewportSize)

        switch dragState {
        case .creatingEdge:
            document.edgeDrag?.currentPoint = canvasPoint
        case .movingNodes(let startPositions, let startMouse):
            let delta = canvasPoint - startMouse
            for (id, startPos) in startPositions {
                var pos = startPos + delta
                if document.snapToGrid {
                    pos.x = (pos.x / 20).rounded() * 20
                    pos.y = (pos.y / 20).rounded() * 20
                }
                document.nodes[id]?.position = pos
            }
        case .boxSelecting(let startCanvas):
            document.selectionRect = SelectionRect(
                origin: startCanvas,
                size: canvasPoint - startCanvas
            )
            document.selectedNodeIDs = HitTesting.nodesInRect(
                origin: startCanvas,
                size: canvasPoint - startCanvas,
                in: document.nodes
            )
        case .none:
            break
        }
    }

    func handleMouseUp(_ event: NSEvent) {
        guard let view else { return }

        if case .movingNodes(_, let startMouse) = dragState {
            let screenPoint = view.convert(event.locationInWindow, from: nil)
            let canvasPoint = document.camera.screenToCanvas(screenPoint, viewportSize: viewportSize)
            let moved = simd_length(canvasPoint - startMouse) > 5

            if moved, document.selectedNodeIDs.count == 1,
               let draggedID = document.selectedNodeIDs.first,
               let draggedNode = document.nodes[draggedID],
               case .taskCard(let taskData) = draggedNode.kind {
                if let targetID = findTerminalUnder(canvasPoint, excluding: draggedID) {
                    assignTask(taskData: taskData, taskID: draggedID, to: targetID)
                }
            }
            document.scheduleSave()
        }

        if case .creatingEdge(let sourceID) = dragState {
            let screenPoint = view.convert(event.locationInWindow, from: nil)
            let canvasPoint = document.camera.screenToCanvas(screenPoint, viewportSize: viewportSize)

            if let targetID = HitTesting.nodeAt(canvasPoint, in: document.nodes), targetID != sourceID {
                let edgeType = inferEdgeType(sourceID: sourceID, targetID: targetID)
                document.addEdge(from: sourceID, to: targetID, type: edgeType)
            }
            document.edgeDrag = nil
        }

        document.selectionRect = nil
        dragState = .none
    }

    private func findTerminalUnder(_ point: SIMD2<Float>, excluding: UUID) -> UUID? {
        for (id, node) in document.nodes {
            guard id != excluding, case .terminal = node.kind else { continue }
            if point.x >= node.position.x && point.x <= node.position.x + node.size.x
                && point.y >= node.position.y && point.y <= node.position.y + node.size.y {
                return id
            }
        }
        return nil
    }

    private func assignTask(taskData: TaskCardData, taskID: UUID, to terminalID: UUID) {
        guard let session = terminalManager?.sessions[terminalID],
              let process = session.terminalView.process else { return }

        document.addEdge(from: taskID, to: terminalID, type: .assignedTo)

        var updatedTask = taskData
        updatedTask.status = .inProgress
        document.nodes[taskID]?.kind = .taskCard(updatedTask)

        let prompt = "# Task: \(taskData.title)\n\n\(taskData.body)\n\n"
        let bytes = Array(prompt.utf8)
        process.send(data: bytes[...])

        document.scheduleSave()
    }

    func handleKeyDown(_ event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            document.deleteSelected()
            return
        }
        if event.keyCode == 36, let edgeID = document.selectedEdgeID {
            triggerEdgeSend(edgeID)
            return
        }
        guard let chars = event.charactersIgnoringModifiers else { return }
        switch chars {
        case "t":
            document.addNode(kind: .taskCard(TaskCardData()))
        case "e":
            document.showTerminalConfig = true
        case "d":
            duplicateSelected()
        default:
            break
        }
    }

    func triggerEdgeSend(_ edgeID: UUID) {
        guard let edge = document.edges[edgeID],
              let sessions = terminalManager?.sessions else { return }
        WiringAction.send(edge: edge, document: document, sessions: sessions)
    }

    private func duplicateSelected() {
        for id in document.selectedNodeIDs {
            guard let node = document.nodes[id] else { continue }
            let offset = SIMD2<Float>(30, 30)
            let newNode = CanvasNode(
                id: UUID(),
                position: node.position + offset,
                size: node.size,
                kind: node.kind
            )
            document.nodes[newNode.id] = newNode
        }
        document.scheduleSave()
    }

    private func inferEdgeType(sourceID: UUID, targetID: UUID) -> EdgeType {
        guard let source = document.nodes[sourceID],
              let target = document.nodes[targetID] else { return .handsOffTo }

        switch (source.kind, target.kind) {
        case (.terminal, .terminal): return .handsOffTo
        case (.taskCard, .terminal): return .assignedTo
        case (.taskCard, .taskCard): return .blocks
        case (.terminal, .taskCard): return .assignedTo
        }
    }
}
