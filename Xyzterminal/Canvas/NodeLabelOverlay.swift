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
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor(data.status))
                        .frame(width: 8, height: 8)
                    if blocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: max(8, 10 * CGFloat(document.camera.zoom))))
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    Text(data.title)
                        .font(.system(size: max(10, 13 * CGFloat(document.camera.zoom)), weight: .semibold))
                        .foregroundStyle(.primary.opacity(blocked ? 0.5 : 1))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: max(8, 10 * CGFloat(document.camera.zoom))))
                        .foregroundStyle(.secondary)
                }
                if height > 50 {
                    let subtitle = (data.status == .done || data.status == .failed) && !data.result.isEmpty
                        ? data.result
                        : data.body
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: max(9, 11 * CGFloat(document.camera.zoom))))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            }
            .padding(8)
            .frame(width: width, height: height, alignment: .topLeading)

        case .terminal(let data):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .font(.system(size: max(9, 11 * CGFloat(document.camera.zoom))))
                        .foregroundStyle(.green.opacity(0.7))
                    Text(data.role?.rawValue.capitalized ?? "Terminal")
                        .font(.system(size: max(10, 13 * CGFloat(document.camera.zoom)), weight: .semibold))
                        .foregroundStyle(.primary)
                    if let branch = data.branchName {
                        Text(branch)
                            .font(.system(size: max(8, 10 * CGFloat(document.camera.zoom)), design: .monospaced))
                            .foregroundStyle(.cyan.opacity(0.7))
                    }
                    Spacer()
                    Text(data.status.rawValue)
                        .font(.system(size: max(8, 10 * CGFloat(document.camera.zoom))))
                        .foregroundStyle(terminalStatusColor(data.status))
                }
            }
            .padding(8)
            .frame(width: width, height: height, alignment: .topLeading)
        }
    }

    private func statusColor(_ status: TaskCardData.Status) -> Color {
        switch status {
        case .draft: .gray
        case .ready: .blue
        case .inProgress: .orange
        case .done: .green
        case .failed: .red
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
