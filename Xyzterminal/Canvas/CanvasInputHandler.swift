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
        case resizingNode(nodeID: UUID, corner: ResizeCorner, startSize: SIMD2<Float>, startPosition: SIMD2<Float>, startMouse: SIMD2<Float>)
    }

    private var dragState: DragState = .none
    private var editingTextField: NSTextField?
    private var editingDelegate: EditingDelegate?
    private var statusMenuHandler: StatusMenuHandler?

    init(document: CanvasDocument, view: NSView) {
        self.document = document
        self.view = view
        document.onStartInlineEdit = { [weak self] nodeID in
            self?.beginInlineEdit(nodeID: nodeID)
        }
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
        let layouts = document.allSectionLayouts()

        if editingTextField != nil {
            endInlineEdit(commit: true)
        }

        if event.clickCount == 2 {
            if let hitID = HitTesting.nodeAt(canvasPoint, in: document.nodes, layouts: layouts),
               let node = document.nodes[hitID] {
                switch node.kind {
                case .taskCard:
                    beginInlineEdit(nodeID: hitID)
                case .section:
                    beginSectionInlineEdit(nodeID: hitID)
                case .terminal:
                    break
                }
            }
            return
        }

        if let hitID = HitTesting.nodeAt(canvasPoint, in: document.nodes, layouts: layouts),
           let node = document.nodes[hitID] {
            let entry = layouts[hitID]
            let pos = entry?.position ?? node.position
            let sz = entry?.size ?? node.size

            if case .section = node.kind,
               isCollapseChevronHit(canvasPoint: canvasPoint, position: pos) {
                toggleCollapse(sectionID: hitID)
                return
            }

            switch node.kind {
            case .taskCard, .section:
                if isExpandHit(canvasPoint: canvasPoint, position: pos, size: sz) {
                    document.editingNodeID = hitID
                    return
                }
            case .terminal:
                break
            }
        }

        if let (hitID, corner) = HitTesting.resizeHandleAt(canvasPoint, in: document.nodes, selectedIDs: document.selectedNodeIDs),
           let node = document.nodes[hitID] {
            dragState = .resizingNode(nodeID: hitID, corner: corner, startSize: node.size, startPosition: node.position, startMouse: canvasPoint)
            return
        }

        if let hitID = HitTesting.nodeAt(canvasPoint, in: document.nodes, layouts: layouts),
           let node = document.nodes[hitID],
           case .taskCard = node.kind,
           isStatusPillHit(canvasPoint: canvasPoint, node: node) {
            showStatusMenu(nodeID: hitID, at: screenPoint)
            return
        }

        if let hitID = HitTesting.nodeAt(canvasPoint, in: document.nodes, layouts: layouts) {
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
                    let entry = layouts[id]
                    startPositions[id] = entry?.position ?? node.position
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
            document.highlightedSectionID = nil
            document.highlightedColumnIndex = nil
            document.highlightedTerminalID = nil

            if document.selectedNodeIDs.count == 1,
               let draggedID = document.selectedNodeIDs.first,
               let draggedNode = document.nodes[draggedID] {
                switch draggedNode.kind {
                case .taskCard:
                    let sectionID = findSectionUnder(canvasPoint, excluding: draggedID)
                    document.highlightedSectionID = sectionID
                    if let sectionID,
                       let section = document.nodes[sectionID],
                       case .section(let sData) = section.kind,
                       sData.viewType == .kanban {
                        document.highlightedColumnIndex = kanbanColumnIndex(at: canvasPoint, section: section)
                    }
                    document.highlightedTerminalID = findTerminalUnder(canvasPoint, excluding: draggedID)
                case .section:
                    document.highlightedTerminalID = findTerminalUnder(canvasPoint, excluding: draggedID)
                case .terminal:
                    break
                }
            } else if document.selectedNodeIDs.count > 1 {
                document.highlightedTerminalID = findTerminalUnder(canvasPoint, excludingSet: document.selectedNodeIDs)
            }
        case .resizingNode(let nodeID, let corner, let startSize, let startPosition, let startMouse):
            let delta = canvasPoint - startMouse
            var newSize = startSize
            var newPos = startPosition

            switch corner {
            case .bottomRight:
                newSize = startSize + delta
            case .bottomLeft:
                newSize.x = startSize.x - delta.x
                newSize.y = startSize.y + delta.y
                newPos.x = startPosition.x + delta.x
            case .topRight:
                newSize.x = startSize.x + delta.x
                newSize.y = startSize.y - delta.y
                newPos.y = startPosition.y + delta.y
            case .topLeft:
                newSize = startSize - delta
                newPos = startPosition + delta
            }

            let minSize = minSizeFor(document.nodes[nodeID]?.kind)
            if newSize.x < minSize.x {
                if corner == .bottomLeft || corner == .topLeft {
                    newPos.x = startPosition.x + startSize.x - minSize.x
                }
                newSize.x = minSize.x
            }
            if newSize.y < minSize.y {
                if corner == .topLeft || corner == .topRight {
                    newPos.y = startPosition.y + startSize.y - minSize.y
                }
                newSize.y = minSize.y
            }

            if document.snapToGrid {
                newSize.x = (newSize.x / 20).rounded() * 20
                newSize.y = (newSize.y / 20).rounded() * 20
            }

            document.nodes[nodeID]?.size = newSize
            document.nodes[nodeID]?.position = newPos
        case .boxSelecting(let startCanvas):
            document.selectionRect = SelectionRect(
                origin: startCanvas,
                size: canvasPoint - startCanvas
            )
            document.selectedNodeIDs = HitTesting.nodesInRect(
                origin: startCanvas,
                size: canvasPoint - startCanvas,
                in: document.nodes,
                layouts: document.allSectionLayouts()
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
               let draggedNode = document.nodes[draggedID] {

                switch draggedNode.kind {
                case .taskCard(var taskData):
                    if let targetID = findTerminalUnder(canvasPoint, excluding: draggedID) {
                        if case .movingNodes(let startPositions, _) = dragState,
                           let originalPos = startPositions[draggedID] {
                            document.nodes[draggedID]?.position = originalPos
                        }
                        assignTask(taskID: draggedID, to: targetID)
                    } else if let sectionID = findSectionUnder(canvasPoint, excluding: draggedID) {
                        if taskData.sectionID == sectionID {
                            if let section = document.nodes[sectionID],
                               case .section(let sData) = section.kind,
                               sData.viewType == .kanban,
                               let newStatus = kanbanColumnStatus(at: canvasPoint, section: section) {
                                taskData.transition(to: newStatus)
                            }
                        } else {
                            taskData.sectionID = sectionID
                            let existing = document.tasksInSection(sectionID)
                            taskData.orderIndex = (existing.map(\.data.orderIndex).max() ?? -1) + 1
                        }
                        document.nodes[draggedID]?.kind = .taskCard(taskData)
                    } else if taskData.sectionID != nil {
                        taskData.sectionID = nil
                        document.nodes[draggedID]?.kind = .taskCard(taskData)
                    }

                case .section:
                    if let targetID = findTerminalUnder(canvasPoint, excluding: draggedID) {
                        if case .movingNodes(let startPositions, _) = dragState,
                           let originalPos = startPositions[draggedID] {
                            document.nodes[draggedID]?.position = originalPos
                        }
                        assignSection(sectionID: draggedID, to: targetID)
                    }

                case .terminal:
                    break
                }
            }

            if moved, document.selectedNodeIDs.count > 1 {
                if let targetID = findTerminalUnder(canvasPoint, excludingSet: document.selectedNodeIDs) {
                    if case .movingNodes(let startPositions, _) = dragState {
                        for id in document.selectedNodeIDs {
                            if let originalPos = startPositions[id] {
                                document.nodes[id]?.position = originalPos
                            }
                        }
                    }
                    var taskIDs: [UUID] = []
                    for id in document.selectedNodeIDs {
                        guard let node = document.nodes[id] else { continue }
                        switch node.kind {
                        case .taskCard:
                            taskIDs.append(id)
                        case .section:
                            taskIDs.append(contentsOf: document.tasksInSection(id).map(\.id))
                        case .terminal:
                            break
                        }
                    }
                    if !taskIDs.isEmpty {
                        assignBatch(taskIDs: taskIDs, to: targetID)
                    }
                }
            }

            document.highlightedSectionID = nil
            document.highlightedColumnIndex = nil
            document.highlightedTerminalID = nil
            document.scheduleSave()
        }

        if case .resizingNode = dragState {
            document.scheduleSave()
        }

        if case .creatingEdge(let sourceID) = dragState {
            let screenPoint = view.convert(event.locationInWindow, from: nil)
            let canvasPoint = document.camera.screenToCanvas(screenPoint, viewportSize: viewportSize)
            let layouts = document.allSectionLayouts()

            if let targetID = HitTesting.nodeAt(canvasPoint, in: document.nodes, layouts: layouts), targetID != sourceID {
                let edgeType = inferEdgeType(sourceID: sourceID, targetID: targetID)
                document.addEdge(from: sourceID, to: targetID, type: edgeType)
            }
            document.edgeDrag = nil
        }

        document.selectionRect = nil
        dragState = .none
    }

    private func findTerminalUnder(_ point: SIMD2<Float>, excluding: UUID) -> UUID? {
        findTerminalUnder(point, excludingSet: [excluding])
    }

    private func findTerminalUnder(_ point: SIMD2<Float>, excludingSet: Set<UUID>) -> UUID? {
        for (id, node) in document.nodes {
            guard !excludingSet.contains(id), case .terminal = node.kind else { continue }
            if point.x >= node.position.x && point.x <= node.position.x + node.size.x
                && point.y >= node.position.y && point.y <= node.position.y + node.size.y {
                return id
            }
        }
        return nil
    }

    private func assignTask(taskID: UUID, to terminalID: UUID) {
        guard let sessions = terminalManager?.sessions else { return }
        WorkflowEngine.assign(taskID: taskID, terminalID: terminalID, document: document, sessions: sessions)
    }

    private func assignSection(sectionID: UUID, to terminalID: UUID) {
        guard let session = terminalManager?.sessions[terminalID],
              let process = session.terminalView.process else { return }
        guard case .section(let sectionData) = document.nodes[sectionID]?.kind else { return }

        let tasks = document.tasksInSection(sectionID)
        var eligible: [(id: UUID, data: TaskCardData)] = []
        var skipped: [(title: String, reason: String)] = []

        for task in tasks.sorted(by: { $0.data.orderIndex < $1.data.orderIndex }) {
            if task.data.status == .inProgress || task.data.status == .done || task.data.status == .failed {
                skipped.append((task.data.title, "already \(task.data.status.rawValue)"))
            } else if !document.unresolvedBlockers(for: task.id).isEmpty {
                skipped.append((task.data.title, "has unresolved blockers"))
            } else {
                eligible.append(task)
            }
        }

        guard !eligible.isEmpty else { return }

        let existingEdgeIDs = document.edges.values
            .filter { $0.sourceID == sectionID && $0.edgeType == .assignedTo }
            .map(\.id)
        for edgeID in existingEdgeIDs {
            document.edges.removeValue(forKey: edgeID)
        }
        document.addEdge(from: sectionID, to: terminalID, type: .assignedTo)

        for task in eligible {
            if case .taskCard(var data) = document.nodes[task.id]?.kind {
                data.transition(to: .inProgress)
                document.nodes[task.id]?.kind = .taskCard(data)
            }
        }

        let prompt = buildBatchPrompt(eligible: eligible, skipped: skipped, sectionTitle: sectionData.title, terminalID: terminalID)
        process.send(data: Array(prompt.utf8)[...])
        document.scheduleSave()
    }

    private func assignBatch(taskIDs: [UUID], to terminalID: UUID) {
        guard let session = terminalManager?.sessions[terminalID],
              let process = session.terminalView.process else { return }

        var eligible: [(id: UUID, data: TaskCardData)] = []
        var skipped: [(title: String, reason: String)] = []

        for taskID in taskIDs {
            guard let node = document.nodes[taskID],
                  case .taskCard(let data) = node.kind else { continue }
            if data.status == .inProgress || data.status == .done || data.status == .failed {
                skipped.append((data.title, "already \(data.status.rawValue)"))
            } else if !document.unresolvedBlockers(for: taskID).isEmpty {
                skipped.append((data.title, "has unresolved blockers"))
            } else {
                eligible.append((id: taskID, data: data))
            }
        }

        guard !eligible.isEmpty else { return }

        for task in eligible {
            let existingEdgeIDs = document.edges.values
                .filter { $0.sourceID == task.id && $0.edgeType == .assignedTo }
                .map(\.id)
            for edgeID in existingEdgeIDs {
                document.edges.removeValue(forKey: edgeID)
            }
            document.addEdge(from: task.id, to: terminalID, type: .assignedTo)

            if case .taskCard(var data) = document.nodes[task.id]?.kind {
                data.transition(to: .inProgress)
                document.nodes[task.id]?.kind = .taskCard(data)
            }
        }

        let prompt = buildBatchPrompt(eligible: eligible, skipped: skipped, sectionTitle: nil, terminalID: terminalID)
        process.send(data: Array(prompt.utf8)[...])
        document.scheduleSave()
    }

    private func buildBatchPrompt(
        eligible: [(id: UUID, data: TaskCardData)],
        skipped: [(title: String, reason: String)],
        sectionTitle: String?,
        terminalID: UUID
    ) -> String {
        let heading = sectionTitle ?? "Batch Assignment"
        var lines = ["# Assignment: \(heading) (\(eligible.count) tasks)", ""]
        lines.append("Work through the tasks below in order. After completing each, report via")
        lines.append("the `xyzterminal` MCP tool `update_task` with the task's ID, status, and")
        lines.append("a brief result summary.")
        lines.append("")

        lines.append("## Context")
        if let projectPath = document.projectPath?.path {
            lines.append("Project: \(projectPath)")
        }
        if let termNode = document.nodes[terminalID],
           case .terminal(let termData) = termNode.kind {
            if let pid = termData.profileID, let profile = document.agentProfiles[pid] {
                lines.append("Agent: \(profile.name)")
            }
            if let branch = termData.branchName { lines.append("Branch: `\(branch)`") }
            if let path = termData.worktreePath { lines.append("Worktree: \(path)") }
        }
        lines.append("")

        lines.append("## Tasks")
        lines.append("")
        for (i, task) in eligible.enumerated() {
            lines.append("### \(i + 1). \(task.data.title)")
            lines.append("task_id: \(task.id.uuidString)")
            if !task.data.body.isEmpty {
                lines.append(task.data.body)
            }

            let blockers = document.edges.values
                .filter { $0.targetID == task.id && $0.edgeType == .blocks }
                .compactMap { edge -> String? in
                    guard let node = document.nodes[edge.sourceID],
                          case .taskCard(let d) = node.kind else { return nil }
                    return "- \(d.title) (\(d.status.rawValue))"
                }
            if !blockers.isEmpty {
                lines.append("")
                lines.append("Dependencies:")
                lines.append(contentsOf: blockers)
            }
            lines.append("")
        }

        if !skipped.isEmpty {
            lines.append("## Skipped")
            for s in skipped {
                lines.append("- \(s.title): \(s.reason)")
            }
            lines.append("")
        }

        lines.append("## Completion Protocol")
        lines.append("For EACH task, call `update_task`:")
        lines.append("- task_id: UUID shown above")
        lines.append("- status: \"done\" or \"failed\"")
        lines.append("- result: brief summary")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    func handleKeyDown(_ event: NSEvent) {
        if editingTextField != nil { return }
        if event.keyCode == 51 || event.keyCode == 117 {
            document.deleteSelected()
            return
        }
        if event.keyCode == 36, let edgeID = document.selectedEdgeID {
            triggerEdgeSend(edgeID)
            return
        }
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "v" {
            handlePaste()
            return
        }
        guard let chars = event.charactersIgnoringModifiers else { return }
        switch chars {
        case "t":
            let id = document.addNode(kind: .taskCard(TaskCardData(title: "")))
            beginInlineEdit(nodeID: id)
        case "e":
            document.showTerminalConfig = true
        case "s":
            document.addNode(kind: .section(SectionData()))
        case "d":
            duplicateSelected()
        case "m":
            document.minimapCollapsed.toggle()
        default:
            break
        }
    }

    func triggerEdgeSend(_ edgeID: UUID) {
        guard let edge = document.edges[edgeID],
              let sessions = terminalManager?.sessions else { return }
        WiringAction.send(edge: edge, document: document, sessions: sessions)
    }

    // MARK: - Inline editing

    private func beginInlineEdit(nodeID: UUID) {
        guard let view,
              let node = document.nodes[nodeID],
              case .taskCard(let data) = node.kind else { return }

        endInlineEdit(commit: false)

        let layouts = document.allSectionLayouts()
        let pos = layouts[nodeID]?.position ?? node.position
        let sz = layouts[nodeID]?.size ?? node.size

        let zoom = CGFloat(document.camera.zoom)
        let screenTL = document.camera.canvasToScreen(pos, viewportSize: viewportSize)
        let cardW = CGFloat(sz.x) * zoom
        let fontSize = max(10, 13 * zoom)
        let tfHeight = ceil(fontSize * 1.6)

        let frame = NSRect(
            x: screenTL.x + 8,
            y: screenTL.y - 8 - tfHeight,
            width: cardW - 38,
            height: tfHeight
        )
        guard frame.width > 40 else { return }

        let delegate = EditingDelegate()
        delegate.onCommit = { [weak self] in self?.endInlineEdit(commit: true) }
        delegate.onCancel = { [weak self] in self?.endInlineEdit(commit: false) }

        let tf = NSTextField(frame: frame)
        tf.stringValue = data.title
        tf.font = .systemFont(ofSize: fontSize, weight: .semibold)
        tf.isBezeled = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.textColor = .labelColor
        tf.cell?.isScrollable = true
        tf.cell?.wraps = false
        tf.delegate = delegate

        view.addSubview(tf)
        view.window?.makeFirstResponder(tf)
        tf.selectText(nil)

        editingTextField = tf
        editingDelegate = delegate
        document.inlineEditingNodeID = nodeID
    }

    private func beginSectionInlineEdit(nodeID: UUID) {
        guard let view,
              let node = document.nodes[nodeID],
              case .section(let data) = node.kind else { return }

        endInlineEdit(commit: false)

        let zoom = CGFloat(document.camera.zoom)
        let titlePos = node.position + SIMD2<Float>(32, 8)
        let titleSize = SIMD2<Float>(node.size.x - 100, 24)
        let screenTL = document.camera.canvasToScreen(titlePos, viewportSize: viewportSize)
        let screenBR = document.camera.canvasToScreen(titlePos + titleSize, viewportSize: viewportSize)
        let frame = NSRect(
            x: screenTL.x,
            y: screenBR.y,
            width: screenBR.x - screenTL.x,
            height: screenTL.y - screenBR.y
        )
        guard frame.width > 40 else { return }

        let delegate = EditingDelegate()
        delegate.onCommit = { [weak self] in self?.endSectionInlineEdit(nodeID: nodeID, commit: true) }
        delegate.onCancel = { [weak self] in self?.endSectionInlineEdit(nodeID: nodeID, commit: false) }

        let fontSize = max(10, 13 * zoom)
        let tf = NSTextField(frame: frame)
        tf.stringValue = data.title
        tf.font = .systemFont(ofSize: fontSize, weight: .semibold)
        tf.isBezeled = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.textColor = .labelColor
        tf.cell?.isScrollable = true
        tf.cell?.wraps = false
        tf.delegate = delegate

        view.addSubview(tf)
        view.window?.makeFirstResponder(tf)
        tf.selectText(nil)

        editingTextField = tf
        editingDelegate = delegate
        document.inlineEditingNodeID = nodeID
    }

    private func endSectionInlineEdit(nodeID: UUID, commit: Bool) {
        document.inlineEditingNodeID = nil

        if commit, let text = editingTextField?.stringValue {
            if case .section(var d) = document.nodes[nodeID]?.kind {
                d.title = text
                document.nodes[nodeID]?.kind = .section(d)
                document.scheduleSave()
            }
        }

        editingTextField?.removeFromSuperview()
        editingTextField = nil
        editingDelegate = nil
    }

    private func endInlineEdit(commit: Bool) {
        guard let nodeID = document.inlineEditingNodeID else { return }
        document.inlineEditingNodeID = nil

        if commit, let text = editingTextField?.stringValue {
            if case .taskCard(var d) = document.nodes[nodeID]?.kind {
                d.title = text
                document.nodes[nodeID]?.kind = .taskCard(d)
                document.scheduleSave()
            }
        }

        editingTextField?.removeFromSuperview()
        editingTextField = nil
        editingDelegate = nil
    }

    func handleMouseMoved(_ event: NSEvent) {
        guard let view else { return }
        let screenPoint = view.convert(event.locationInWindow, from: nil)
        let canvasPoint = document.camera.screenToCanvas(screenPoint, viewportSize: viewportSize)

        if HitTesting.resizeHandleAt(canvasPoint, in: document.nodes, selectedIDs: document.selectedNodeIDs) != nil {
            NSCursor.crosshair.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func minSizeFor(_ kind: NodeKind?) -> SIMD2<Float> {
        guard let kind else { return SIMD2<Float>(80, 40) }
        return switch kind {
        case .terminal: SIMD2<Float>(200, 120)
        case .taskCard: SIMD2<Float>(120, 50)
        case .section: SIMD2<Float>(300, 200)
        }
    }

    private func isStatusPillHit(canvasPoint: SIMD2<Float>, node: CanvasNode) -> Bool {
        let zoom = document.camera.zoom
        let pillOrigin = node.position + SIMD2<Float>(8 / zoom, 26 / zoom)
        let pillSize = SIMD2<Float>(80 / zoom, 20 / zoom)
        return canvasPoint.x >= pillOrigin.x
            && canvasPoint.x <= pillOrigin.x + pillSize.x
            && canvasPoint.y >= pillOrigin.y
            && canvasPoint.y <= pillOrigin.y + pillSize.y
    }

    private func showStatusMenu(nodeID: UUID, at point: CGPoint) {
        guard let view else { return }

        let handler = StatusMenuHandler { [weak self] newStatus in
            guard let self, case .taskCard(var data) = self.document.nodes[nodeID]?.kind else { return }
            data.transition(to: newStatus)
            self.document.nodes[nodeID]?.kind = .taskCard(data)
            self.document.scheduleSave()
        }
        statusMenuHandler = handler

        let menu = NSMenu()
        for status in TaskCardData.Status.allCases {
            let item = NSMenuItem(title: status.label, action: #selector(StatusMenuHandler.select(_:)), keyEquivalent: "")
            item.target = handler
            item.representedObject = status.rawValue
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: point, in: view)
    }

    private func isExpandHit(canvasPoint: SIMD2<Float>, position: SIMD2<Float>, size: SIMD2<Float>) -> Bool {
        let expandOrigin = SIMD2<Float>(position.x + size.x - 28, position.y + 4)
        return canvasPoint.x >= expandOrigin.x
            && canvasPoint.x <= expandOrigin.x + 24
            && canvasPoint.y >= expandOrigin.y
            && canvasPoint.y <= expandOrigin.y + 24
    }

    private func duplicateSelected() {
        for id in document.selectedNodeIDs {
            guard let node = document.nodes[id] else { continue }
            let offset = SIMD2<Float>(30, 30)
            var kind = node.kind
            if case .terminal(var data) = kind {
                data.worktreePath = nil
                data.branchName = nil
                data.status = .idle
                kind = .terminal(data)
            }
            if case .section(var data) = kind {
                data.title += " (copy)"
                kind = .section(data)
            }
            let newNode = CanvasNode(id: UUID(), position: node.position + offset, size: node.size, kind: kind)
            document.nodes[newNode.id] = newNode
        }
        document.scheduleSave()
    }

    private func handlePaste() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.isEmpty else { return }
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return }

        let size = NodeKind.taskCard(TaskCardData()).defaultSize
        let basePosition = document.camera.offset - SIMD2<Float>(size.x * 0.5, Float(lines.count) * (size.y + 10) * 0.5)
        for (i, line) in lines.enumerated() {
            let position = basePosition + SIMD2<Float>(0, Float(i) * (size.y + 10))
            let node = CanvasNode(
                id: UUID(),
                position: position,
                size: size,
                kind: .taskCard(TaskCardData(title: line.trimmingCharacters(in: .whitespaces)))
            )
            document.nodes[node.id] = node
        }
        document.scheduleSave()
    }

    private func inferEdgeType(sourceID: UUID, targetID: UUID) -> EdgeType {
        guard let source = document.nodes[sourceID],
              let target = document.nodes[targetID] else { return .handsOffTo }

        switch (source.kind, target.kind) {
        case (.terminal, .terminal): return .handsOffTo
        case (.taskCard, .terminal): return .assignedTo
        case (.taskCard, .taskCard): return .flowsTo
        case (.terminal, .taskCard): return .blocks
        case (.section, .terminal), (.terminal, .section): return .handsOffTo
        case (.section, .taskCard), (.taskCard, .section): return .assignedTo
        case (.section, .section): return .handsOffTo
        }
    }

    private func findSectionUnder(_ point: SIMD2<Float>, excluding: UUID) -> UUID? {
        for (id, node) in document.nodes {
            guard id != excluding, case .section = node.kind else { continue }
            if point.x >= node.position.x && point.x <= node.position.x + node.size.x
                && point.y >= node.position.y && point.y <= node.position.y + node.size.y {
                return id
            }
        }
        return nil
    }

    private func kanbanColumnIndex(at point: SIMD2<Float>, section: CanvasNode) -> Int? {
        let statuses = TaskCardData.Status.allCases
        let numCols = Float(statuses.count)
        let colW = (section.size.x - SectionLayout.padding * 2 - SectionLayout.colGap * (numCols - 1)) / numCols
        let relX = point.x - section.position.x - SectionLayout.padding
        guard relX >= 0 else { return nil }
        let idx = Int(relX / (colW + SectionLayout.colGap))
        guard idx >= 0 && idx < statuses.count else { return nil }
        return idx
    }

    private func kanbanColumnStatus(at point: SIMD2<Float>, section: CanvasNode) -> TaskCardData.Status? {
        guard let idx = kanbanColumnIndex(at: point, section: section) else { return nil }
        return TaskCardData.Status.allCases[idx]
    }

    private func isCollapseChevronHit(canvasPoint: SIMD2<Float>, position: SIMD2<Float>) -> Bool {
        canvasPoint.x >= position.x + 4
            && canvasPoint.x <= position.x + 24
            && canvasPoint.y >= position.y + 4
            && canvasPoint.y <= position.y + 36
    }

    private func toggleCollapse(sectionID: UUID) {
        guard case .section(var data) = document.nodes[sectionID]?.kind else { return }
        data.isCollapsed.toggle()
        document.nodes[sectionID]?.kind = .section(data)
        document.scheduleSave()
    }
}

private final class EditingDelegate: NSObject, NSTextFieldDelegate {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    func controlTextDidEndEditing(_ obj: Notification) {
        onCommit?()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) {
            onCommit?()
            return true
        }
        if sel == #selector(NSResponder.cancelOperation(_:)) {
            onCancel?()
            return true
        }
        return false
    }
}

private final class StatusMenuHandler: NSObject {
    let onChange: (TaskCardData.Status) -> Void
    init(onChange: @escaping (TaskCardData.Status) -> Void) { self.onChange = onChange }
    @objc func select(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let status = TaskCardData.Status(rawValue: raw) else { return }
        onChange(status)
    }
}
