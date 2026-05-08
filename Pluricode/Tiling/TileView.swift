import SwiftUI

struct TileView<Content: View>: View {
    let node: TileNode
    let tiling: Tiling
    @ViewBuilder let content: (Pane) -> Content

    var body: some View {
        switch node {
        case .pane(let pane):
            content(pane)
        case .split(let split):
            SplitContainer(split: split, tiling: tiling, content: content)
        }
    }
}

private struct SplitContainer<Content: View>: View {
    let split: Split
    let tiling: Tiling
    @ViewBuilder let content: (Pane) -> Content

    private let dividerThickness: CGFloat = 6
    private let minFraction: Float = 0.08

    @State private var dragWeights: [Float]?

    var body: some View {
        GeometryReader { geo in
            let total = split.direction == .horizontal ? geo.size.width : geo.size.height
            let available = max(0, total - CGFloat(split.children.count - 1) * dividerThickness)

            ZStack {
                liveStack(available: available)
                if let dragWeights {
                    maskStack(weights: dragWeights, available: available)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    @ViewBuilder
    private func liveStack(available: CGFloat) -> some View {
        if split.direction == .horizontal {
            HStack(spacing: 0) { liveChildren(available: available) }
        } else {
            VStack(spacing: 0) { liveChildren(available: available) }
        }
    }

    @ViewBuilder
    private func liveChildren(available: CGFloat) -> some View {
        ForEach(Array(split.children.enumerated()), id: \.element.id) { index, child in
            TileView(node: child, tiling: tiling, content: content)
                .frame(
                    width: split.direction == .horizontal ? available * CGFloat(split.weights[index]) : nil,
                    height: split.direction == .vertical ? available * CGFloat(split.weights[index]) : nil
                )
            if index < split.children.count - 1 {
                SplitDivider(
                    direction: split.direction,
                    onChanged: { delta in updateDrag(leftIndex: index, delta: delta, available: available) },
                    onEnded: commitDrag
                )
                .frame(
                    width: split.direction == .horizontal ? dividerThickness : nil,
                    height: split.direction == .vertical ? dividerThickness : nil
                )
            }
        }
    }

    @ViewBuilder
    private func maskStack(weights: [Float], available: CGFloat) -> some View {
        Group {
            if split.direction == .horizontal {
                HStack(spacing: 0) { maskChildren(weights: weights, available: available) }
            } else {
                VStack(spacing: 0) { maskChildren(weights: weights, available: available) }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func maskChildren(weights: [Float], available: CGFloat) -> some View {
        ForEach(Array(split.children.enumerated()), id: \.element.id) { index, child in
            MaskTile()
                .frame(
                    width: split.direction == .horizontal ? available * CGFloat(weights[index]) : nil,
                    height: split.direction == .vertical ? available * CGFloat(weights[index]) : nil
                )
            if index < split.children.count - 1 {
                Color.clear.frame(
                    width: split.direction == .horizontal ? dividerThickness : nil,
                    height: split.direction == .vertical ? dividerThickness : nil
                )
            }
        }
    }

    private func updateDrag(leftIndex: Int, delta: CGFloat, available: CGFloat) {
        guard available > 0,
              split.weights.indices.contains(leftIndex),
              split.weights.indices.contains(leftIndex + 1) else { return }
        let fraction = Float(delta / available)
        let combined = split.weights[leftIndex] + split.weights[leftIndex + 1]
        let newLeft = max(minFraction, min(combined - minFraction, split.weights[leftIndex] + fraction))
        var next = split.weights
        next[leftIndex] = newLeft
        next[leftIndex + 1] = combined - newLeft
        dragWeights = next
    }

    private func commitDrag() {
        if let dragWeights {
            tiling.setWeights(splitID: split.id, weights: dragWeights)
        }
        dragWeights = nil
    }
}

private struct MaskTile: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(nsColor: .windowBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            }
    }
}
