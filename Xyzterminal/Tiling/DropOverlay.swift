import SwiftUI
import UniformTypeIdentifiers

struct TilingDragPayload: Codable, Transferable, Hashable {
    enum Kind: Codable, Hashable {
        case newPlaceholder(label: String)
    }
    let kind: Kind

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .plainText)
    }
}

struct DropOverlay: View {
    let paneID: UUID
    let onDrop: (TilingDragPayload, TileEdge) -> Void

    @State private var isTargeted = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .dropDestination(for: TilingDragPayload.self) { items, location in
                        guard let payload = items.first else { return false }
                        let edge = Self.zone(for: location, in: geo.size)
                        onDrop(payload, edge)
                        return true
                    } isTargeted: { self.isTargeted = $0 }

                if isTargeted {
                    ZoneIndicatorOverlay(size: geo.size)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    static func zone(for point: CGPoint, in size: CGSize) -> TileEdge {
        guard size.width > 0, size.height > 0 else { return .center }
        let leftFrac = point.x / size.width
        let rightFrac = 1 - leftFrac
        let topFrac = point.y / size.height
        let bottomFrac = 1 - topFrac
        let threshold: CGFloat = 0.25
        let minVal = min(leftFrac, rightFrac, topFrac, bottomFrac)
        guard minVal < threshold else { return .center }
        if minVal == leftFrac { return .left }
        if minVal == rightFrac { return .right }
        if minVal == topFrac { return .top }
        return .bottom
    }
}

private struct ZoneIndicatorOverlay: View {
    let size: CGSize

    var body: some View {
        let inset: CGFloat = min(size.width, size.height) * 0.25
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.accentColor, lineWidth: 2)
                .padding(4)

            Path { path in
                path.move(to: CGPoint(x: inset, y: 0))
                path.addLine(to: CGPoint(x: inset, y: size.height))
                path.move(to: CGPoint(x: size.width - inset, y: 0))
                path.addLine(to: CGPoint(x: size.width - inset, y: size.height))
                path.move(to: CGPoint(x: 0, y: inset))
                path.addLine(to: CGPoint(x: size.width, y: inset))
                path.move(to: CGPoint(x: 0, y: size.height - inset))
                path.addLine(to: CGPoint(x: size.width, y: size.height - inset))
            }
            .stroke(Color.accentColor.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
    }
}
