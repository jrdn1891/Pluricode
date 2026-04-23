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

    var body: some View {
        GeometryReader { geo in
            let total = split.direction == .horizontal ? geo.size.width : geo.size.height
            let available = max(0, total - CGFloat(split.children.count - 1) * dividerThickness)

            if split.direction == .horizontal {
                HStack(spacing: 0) { laidOutChildren(available: available) }
            } else {
                VStack(spacing: 0) { laidOutChildren(available: available) }
            }
        }
    }

    @ViewBuilder
    private func laidOutChildren(available: CGFloat) -> some View {
        ForEach(Array(split.children.enumerated()), id: \.element.id) { index, child in
            TileView(node: child, tiling: tiling, content: content)
                .frame(
                    width: split.direction == .horizontal ? available * CGFloat(split.weights[index]) : nil,
                    height: split.direction == .vertical ? available * CGFloat(split.weights[index]) : nil
                )
            if index < split.children.count - 1 {
                SplitDivider(
                    splitID: split.id,
                    leftIndex: index,
                    direction: split.direction,
                    available: available,
                    weights: split.weights,
                    tiling: tiling
                )
                .frame(
                    width: split.direction == .horizontal ? dividerThickness : nil,
                    height: split.direction == .vertical ? dividerThickness : nil
                )
            }
        }
    }
}
