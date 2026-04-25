import SwiftUI
import AppKit

struct SplitDivider: View {
    let splitID: UUID
    let leftIndex: Int
    let direction: TileDirection
    let available: CGFloat
    let weights: [Float]
    let tiling: Tiling

    private let minFraction: Float = 0.08

    @State private var baseWeights: [Float]?
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
                        let base = baseWeights ?? weights
                        if baseWeights == nil { baseWeights = base }
                        let delta = direction == .horizontal ? value.translation.width : value.translation.height
                        applyDelta(delta, base: base)
                    }
                    .onEnded { _ in
                        baseWeights = nil
                    }
            )
    }

    private func applyDelta(_ delta: CGFloat, base: [Float]) {
        guard available > 0, base.indices.contains(leftIndex), base.indices.contains(leftIndex + 1) else { return }
        let fraction = Float(delta / available)
        let i = leftIndex
        let combined = base[i] + base[i + 1]
        let newLeft = max(minFraction, min(combined - minFraction, base[i] + fraction))
        var next = base
        next[i] = newLeft
        next[i + 1] = combined - newLeft
        tiling.setWeights(splitID: splitID, weights: next)
    }
}
