import SwiftUI

struct NodeLabelOverlay: View {
    let document: CanvasDocument

    var body: some View {
        GeometryReader { geo in
            let vp = geo.size
            let zoom = CGFloat(document.camera.zoom)
            if zoom > 0.25 {
                ForEach(Array(document.nodes.values), id: \.id) { node in
                    let pos = document.camera.canvasToSwiftUI(node.position, viewportSize: vp)
                    let w = CGFloat(node.size.x) * zoom
                    let h = CGFloat(node.size.y) * zoom

                    nodeLabelView(node: node, width: w, height: h)
                        .position(x: pos.x + w * 0.5, y: pos.y + h * 0.5)
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func nodeLabelView(node: CanvasNode, width: CGFloat, height: CGFloat) -> some View {
        switch node.kind {
        case .taskCard(let data):
            let blocked = !document.unresolvedBlockers(for: node.id).isEmpty
            let isEditing = node.id == document.inlineEditingNodeID
            let zoom = CGFloat(document.camera.zoom)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if blocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: max(8, 10 * zoom)))
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    Text(data.title.isEmpty ? "Untitled" : data.title)
                        .font(.system(size: max(10, 13 * zoom), weight: .semibold))
                        .foregroundStyle(.primary.opacity(isEditing ? 0 : (data.title.isEmpty ? 0.4 : (blocked ? 0.5 : 1))))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: max(8, 10 * zoom)))
                        .foregroundStyle(.secondary)
                }
                Text(data.status.label)
                    .font(.system(size: max(8, 10 * zoom), weight: .medium))
                    .foregroundStyle(data.status.color)
                    .padding(.horizontal, max(4, 6 * zoom))
                    .padding(.vertical, max(1, 2 * zoom))
                    .background(data.status.color.opacity(0.12))
                    .clipShape(Capsule())
                if height > 60 {
                    let subtitle = (data.status == .done || data.status == .failed) && !data.result.isEmpty
                        ? data.result
                        : data.body
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: max(9, 11 * zoom)))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            }
            .padding(8)
            .frame(width: width, height: height, alignment: .topLeading)

        case .terminal(let data):
            let zoom = CGFloat(document.camera.zoom)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .font(.system(size: max(9, 11 * zoom)))
                        .foregroundStyle(.green.opacity(0.7))
                    Text(data.role?.rawValue.capitalized ?? "Terminal")
                        .font(.system(size: max(10, 13 * zoom), weight: .semibold))
                        .foregroundStyle(.primary)
                    if let branch = data.branchName {
                        Text(branch)
                            .font(.system(size: max(8, 10 * zoom), design: .monospaced))
                            .foregroundStyle(.cyan.opacity(0.7))
                    }
                    Spacer()
                    Text(data.status.rawValue)
                        .font(.system(size: max(8, 10 * zoom)))
                        .foregroundStyle(terminalStatusColor(data.status))
                }
            }
            .padding(8)
            .frame(width: width, height: height, alignment: .topLeading)
        }
    }

    private func terminalStatusColor(_ status: TerminalNodeData.Status) -> Color {
        switch status {
        case .idle: .gray
        case .working: .orange
        case .waiting: .yellow
        case .done: .green
        case .error: .red
        }
    }
}

extension TaskCardData.Status {
    var label: String {
        switch self {
        case .draft: "Draft"
        case .ready: "Ready"
        case .inProgress: "In Progress"
        case .done: "Done"
        case .failed: "Failed"
        }
    }

    var color: Color {
        switch self {
        case .draft: .gray
        case .ready: .blue
        case .inProgress: .orange
        case .done: .green
        case .failed: .red
        }
    }
}
