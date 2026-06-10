import SwiftUI
import AppKit

enum DividerRegion {
    case leading, middle, trailing
}

struct SplitDivider: View {
    let direction: TileDirection
    let hasLeadingCorner: Bool
    let hasTrailingCorner: Bool
    let onChanged: (DividerRegion, CGSize) -> Void
    let onEnded: () -> Void

    @State private var hovering = false

    private let cornerLength: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .overlay {
                    Rectangle()
                        .fill(Color.secondary.opacity(hovering ? 0.5 : 0.2))
                        .frame(
                            width: direction == .horizontal ? 1 : nil,
                            height: direction == .vertical ? 1 : nil
                        )
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let next = cursor(at: location, size: geo.size)
                        if hovering {
                            next.set()
                        } else {
                            hovering = true
                            next.push()
                        }
                    case .ended:
                        hovering = false
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            onChanged(region(at: value.startLocation, size: geo.size), value.translation)
                        }
                        .onEnded { _ in onEnded() }
                )
        }
    }

    private func region(at location: CGPoint, size: CGSize) -> DividerRegion {
        let along = direction == .horizontal ? location.y : location.x
        let length = direction == .horizontal ? size.height : size.width
        if hasLeadingCorner, along < cornerLength { return .leading }
        if hasTrailingCorner, along > length - cornerLength { return .trailing }
        return .middle
    }

    private func cursor(at location: CGPoint, size: CGSize) -> NSCursor {
        switch region(at: location, size: size) {
        case .middle:
            direction == .horizontal ? .resizeLeftRight : .resizeUpDown
        case .leading, .trailing:
            .frameResize(position: .topLeft, directions: .all)
        }
    }
}
