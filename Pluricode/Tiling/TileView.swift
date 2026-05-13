import SwiftUI

struct ResizeReporter {
    var begin: (UUID, TileDirection, [Float], Set<UUID>) -> Void
    var change: ([Float]) -> Void
    var end: () -> Void
}

private struct ResizeReporterKey: EnvironmentKey {
    static let defaultValue: ResizeReporter? = nil
}

extension EnvironmentValues {
    var resizeReporter: ResizeReporter? {
        get { self[ResizeReporterKey.self] }
        set { self[ResizeReporterKey.self] = newValue }
    }
}

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

    @Environment(\.resizeReporter) private var reporter
    @State private var dragWeights: [Float]?

    var body: some View {
        GeometryReader { geo in
            let total = split.direction == .horizontal ? geo.size.width : geo.size.height
            let available = max(0, total - CGFloat(split.children.count - 1) * dividerThickness)

            if split.direction == .horizontal {
                HStack(spacing: 0) { children(available: available) }
            } else {
                VStack(spacing: 0) { children(available: available) }
            }
        }
    }

    @ViewBuilder
    private func children(available: CGFloat) -> some View {
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
        if dragWeights == nil {
            let highlighted = Set(
                Tiling.allPanes(in: split.children[leftIndex]).map(\.id)
                + Tiling.allPanes(in: split.children[leftIndex + 1]).map(\.id)
            )
            reporter?.begin(split.id, split.direction, next, highlighted)
        } else {
            reporter?.change(next)
        }
        dragWeights = next
    }

    private func commitDrag() {
        if let dragWeights {
            tiling.setWeights(splitID: split.id, weights: dragWeights)
        }
        dragWeights = nil
        reporter?.end()
    }
}
