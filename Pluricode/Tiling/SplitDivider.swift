import SwiftUI
import AppKit

struct SplitDivider: View {
    let direction: TileDirection
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    @State private var hovering = false

    var body: some View {
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
            .onHover { inside in
                hovering = inside
                if inside {
                    (direction == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let delta = direction == .horizontal ? value.translation.width : value.translation.height
                        onChanged(delta)
                    }
                    .onEnded { _ in onEnded() }
            )
    }
}
