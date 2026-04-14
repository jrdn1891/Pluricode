import SwiftUI
import MetalKit

final class CanvasMTKView: MTKView {
    var inputHandler: CanvasInputHandler?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        window?.appearance = NSAppearance(named: .darkAqua)
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
        view.clearColor = MTLClearColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1.0)
        view.isPaused = false
        view.enableSetNeedsDisplay = false

        let terminalManager = TerminalManager(document: document)

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
        ZStack {
            CanvasMetalView(document: document)
            NodeLabelOverlay(document: document)
        }
        .ignoresSafeArea()
        .toolbar {
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
            TaskCardEditor(document: document, nodeID: item.id)
        }
        .sheet(isPresented: Binding(
            get: { document.showTerminalConfig },
            set: { document.showTerminalConfig = $0 }
        )) {
            TerminalConfigSheet { data in
                document.addNode(kind: .terminal(data))
            }
        }
    }
}
