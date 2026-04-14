import SwiftUI

struct EdgeActionToolbar: View {
    let document: CanvasDocument

    var body: some View {
        if let edgeID = document.selectedEdgeID,
           let edge = document.edges[edgeID] {
            HStack(spacing: 8) {
                Text(edge.edgeType.label)
                    .font(.caption.bold())

                if edge.edgeType == .flowsTo || edge.edgeType == .blocks {
                    TextField(
                        "condition",
                        text: Binding(
                            get: { document.edges[edgeID]?.condition ?? "" },
                            set: {
                                document.edges[edgeID]?.condition = $0.isEmpty ? nil : $0
                                document.scheduleSave()
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 120)
                }

                Button(action: { triggerSend(edgeID) }) {
                    Label("Send", systemImage: "paperplane.fill")
                        .font(.caption)
                }
                if !edge.payloadLog.isEmpty {
                    Text("\(edge.payloadLog.count) sent")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func triggerSend(_ edgeID: UUID) {
        guard let containerView = NSApp.mainWindow?.contentView else { return }
        if let mtkView = findCanvasMTKView(in: containerView) {
            mtkView.inputHandler?.triggerEdgeSend(edgeID)
        }
    }

    private func findCanvasMTKView(in view: NSView) -> CanvasMTKView? {
        if let v = view as? CanvasMTKView { return v }
        for sub in view.subviews {
            if let found = findCanvasMTKView(in: sub) { return found }
        }
        return nil
    }
}

extension EdgeType {
    var label: String {
        switch self {
        case .handsOffTo: "Hands Off"
        case .reviews: "Reviews"
        case .assignedTo: "Assigned"
        case .blocks: "Blocks"
        case .blockedBy: "Blocked By"
        case .flowsTo: "Flows To"
        }
    }
}
