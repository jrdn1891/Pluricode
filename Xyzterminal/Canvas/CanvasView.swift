import SwiftUI
import MetalKit

final class CanvasMTKView: MTKView {
    var inputHandler: CanvasInputHandler?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        inputHandler?.handleMouseMoved(event)
    }

    override func scrollWheel(with event: NSEvent) {
        inputHandler?.handleScroll(event)
    }

    override func magnify(with event: NSEvent) {
        inputHandler?.handleMagnify(event)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        inputHandler?.handleMouseDown(event)
    }

    override func mouseDragged(with event: NSEvent) {
        inputHandler?.handleMouseDragged(event)
    }

    override func mouseUp(with event: NSEvent) {
        inputHandler?.handleMouseUp(event)
    }

    override func keyDown(with event: NSEvent) {
        inputHandler?.handleKeyDown(event)
    }
}

struct CanvasMetalView: NSViewRepresentable {
    let document: CanvasDocument

    final class Coordinator {
        var renderer: CanvasRenderer?
        var inputHandler: CanvasInputHandler?
        var terminalManager: TerminalManager?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> CanvasMTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        let view = CanvasMTKView()
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = Theme(from: NSApp.effectiveAppearance).canvasClearColor
        view.isPaused = false
        view.enableSetNeedsDisplay = false

        let terminalManager = TerminalManager(document: document)
        document.mcpServer?.terminalManager = terminalManager

        let renderer = CanvasRenderer(device: device, document: document)
        renderer.terminalManager = terminalManager
        view.delegate = renderer
        context.coordinator.renderer = renderer
        context.coordinator.terminalManager = terminalManager

        let inputHandler = CanvasInputHandler(document: document, view: view)
        inputHandler.terminalManager = terminalManager
        view.inputHandler = inputHandler
        context.coordinator.inputHandler = inputHandler

        return view
    }

    func updateNSView(_ nsView: CanvasMTKView, context: Context) {}
}

struct CanvasContainerView: View {
    let document: CanvasDocument

    var body: some View {
        HStack(spacing: 0) {
            if document.showWorktreePanel {
                WorktreePanel(document: document)
                Divider()
            }
            ZStack {
                CanvasMetalView(document: document)
                NodeLabelOverlay(document: document)
                MinimapToggleButton(document: document)
            }
        }
        .ignoresSafeArea()
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { document.showWorktreePanel.toggle() }) {
                    Label("Worktrees", systemImage: "sidebar.left")
                }
            }
            ToolbarItem(placement: .automatic) {
                if document.selectedEdgeID != nil {
                    EdgeActionToolbar(document: document)
                }
            }
        }
        .sheet(item: Binding(
            get: { document.editingNodeID.map { EditingNode(id: $0) } },
            set: { document.editingNodeID = $0?.id }
        )) { item in
            if let node = document.nodes[item.id] {
                switch node.kind {
                case .taskCard:
                    TaskCardEditor(document: document, nodeID: item.id)
                case .section:
                    SectionEditor(document: document, nodeID: item.id)
                case .terminal:
                    EmptyView()
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { document.showTerminalConfig },
            set: { document.showTerminalConfig = $0 }
        )) {
            TerminalConfigSheet(document: document) { data in
                document.addNode(kind: .terminal(data))
            }
        }
        .alert(
            "Delete terminals?",
            isPresented: Binding(
                get: { !document.pendingTerminalDeletions.isEmpty },
                set: { if !$0 { document.pendingTerminalDeletions.removeAll() } }
            )
        ) {
            Button("Delete & clean up worktrees", role: .destructive) {
                document.confirmTerminalDeletion(cleanup: true)
            }
            Button("Delete & keep worktrees") {
                document.confirmTerminalDeletion(cleanup: false)
            }
            Button("Cancel", role: .cancel) {
                document.pendingTerminalDeletions.removeAll()
            }
        } message: {
            let count = document.pendingTerminalDeletions.count
            Text("This will remove \(count) terminal\(count == 1 ? "" : "s"). Delete the associated worktree branch\(count == 1 ? "" : "es") too, or keep them?")
        }
    }
}
