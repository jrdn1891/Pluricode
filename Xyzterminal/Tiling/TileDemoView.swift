import SwiftUI

struct TileDemoView: View {
    @State private var tiling = Tiling()

    var body: some View {
        HStack(spacing: 0) {
            templatesSidebar
                .frame(width: 180)
                .background(Color.secondary.opacity(0.08))

            Divider()

            ZStack {
                Color.black.opacity(0.03)

                if let root = tiling.root {
                    TileView(node: root, tiling: tiling) { pane in
                        PlaceholderPane(pane: pane, tiling: tiling)
                    }
                    .padding(4)
                } else {
                    EmptyWorkspaceDrop(tiling: tiling)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    @ViewBuilder
    private var templatesSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Drag onto canvas")
                .font(.headline)
            ForEach(["A", "B", "C", "D", "E"], id: \.self) { label in
                PaneTemplateRow(label: "Pane \(label)")
            }
            Spacer()
            Button("Reset") { tiling.root = nil }
                .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct PaneTemplateRow: View {
    let label: String

    var body: some View {
        HStack {
            Image(systemName: "square.split.2x1")
                .foregroundStyle(.secondary)
            Text(label)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.12)))
        .draggable(TilingDragPayload(kind: .newPlaceholder(label: label)))
    }
}

private struct EmptyWorkspaceDrop: View {
    let tiling: Tiling
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Drop a pane here to begin")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .padding(32)
        }
        .dropDestination(for: TilingDragPayload.self) { items, _ in
            guard let payload = items.first else { return false }
            switch payload.kind {
            case .newPlaceholder(let label):
                _ = tiling.addPane(.placeholder(label: label))
            }
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

private struct PlaceholderPane: View {
    let pane: Pane
    let tiling: Tiling

    var body: some View {
        let label = labelText(for: pane.content)
        let hue = Double(abs(label.hashValue) % 360) / 360

        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hue: hue, saturation: 0.3, brightness: 0.95))

            VStack(spacing: 2) {
                Text(label).font(.title2).bold()
                Text(pane.id.uuidString.prefix(8))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(action: { tiling.remove(paneID: pane.id) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(8)

            DropOverlay(paneID: pane.id) { payload, edge in
                switch payload.kind {
                case .newPlaceholder(let label):
                    _ = tiling.split(paneID: pane.id, edge: edge, newContent: .placeholder(label: label))
                }
            }
        }
        .padding(2)
    }

    private func labelText(for content: PaneContent) -> String {
        switch content {
        case .placeholder(let l): l
        }
    }
}
