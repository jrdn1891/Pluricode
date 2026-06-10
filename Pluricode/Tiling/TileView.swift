import SwiftUI

struct ResizeReporter {
    var change: ([UUID: [Float]], Set<UUID>) -> Void
    var end: () -> Void
}

private struct ResizeReporterKey: EnvironmentKey {
    static let defaultValue: ResizeReporter? = nil
}

struct PerpendicularResize {
    typealias Resize = (CGFloat) -> (weights: [Float], highlightedPaneIDs: Set<UUID>)?
    let splitID: UUID
    let leading: Resize?
    let trailing: Resize?
}

private struct PerpendicularResizeKey: EnvironmentKey {
    static let defaultValue: PerpendicularResize? = nil
}

extension EnvironmentValues {
    var resizeReporter: ResizeReporter? {
        get { self[ResizeReporterKey.self] }
        set { self[ResizeReporterKey.self] = newValue }
    }

    var perpendicularResize: PerpendicularResize? {
        get { self[PerpendicularResizeKey.self] }
        set { self[PerpendicularResizeKey.self] = newValue }
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
    @Environment(\.perpendicularResize) private var perpendicularResize
    @State private var dragWeights: [UUID: [Float]]?

    var body: some View {
        GeometryReader { geo in
            let total = split.direction == .horizontal ? geo.size.width : geo.size.height
            let available = max(0, total - CGFloat(split.children.count - 1) * dividerThickness)

            if split.direction == .horizontal {
                HStack(spacing: 0) { children(available: available, size: geo.size) }
            } else {
                VStack(spacing: 0) { children(available: available, size: geo.size) }
            }
        }
    }

    @ViewBuilder
    private func children(available: CGFloat, size: CGSize) -> some View {
        ForEach(Array(split.children.enumerated()), id: \.element.id) { index, child in
            TileView(node: child, tiling: tiling, content: content)
                .frame(
                    width: split.direction == .horizontal ? available * CGFloat(split.weights[index]) : size.width,
                    height: split.direction == .vertical ? available * CGFloat(split.weights[index]) : size.height,
                    alignment: .topLeading
                )
                .clipped()
                .environment(\.perpendicularResize, perpendicularHandler(childIndex: index, available: available))
            if index < split.children.count - 1 {
                SplitDivider(
                    direction: split.direction,
                    hasLeadingCorner: perpendicularResize?.leading != nil,
                    hasTrailingCorner: perpendicularResize?.trailing != nil,
                    onChanged: { region, translation in
                        updateDrag(leftIndex: index, region: region, translation: translation, available: available)
                    },
                    onEnded: commitDrag
                )
                .frame(
                    width: split.direction == .horizontal ? dividerThickness : nil,
                    height: split.direction == .vertical ? dividerThickness : nil
                )
            }
        }
    }

    private func perpendicularHandler(childIndex: Int, available: CGFloat) -> PerpendicularResize {
        PerpendicularResize(
            splitID: split.id,
            leading: childIndex > 0
                ? { delta in resizedWeights(leftIndex: childIndex - 1, delta: delta, available: available) }
                : nil,
            trailing: childIndex < split.children.count - 1
                ? { delta in resizedWeights(leftIndex: childIndex, delta: delta, available: available) }
                : nil
        )
    }

    private func resizedWeights(leftIndex: Int, delta: CGFloat, available: CGFloat) -> (weights: [Float], highlightedPaneIDs: Set<UUID>)? {
        guard available > 0,
              split.weights.indices.contains(leftIndex),
              split.weights.indices.contains(leftIndex + 1) else { return nil }
        let fraction = Float(delta / available)
        let combined = split.weights[leftIndex] + split.weights[leftIndex + 1]
        let newLeft = max(minFraction, min(combined - minFraction, split.weights[leftIndex] + fraction))
        var next = split.weights
        next[leftIndex] = newLeft
        next[leftIndex + 1] = combined - newLeft
        let highlighted = Set(
            Tiling.allPanes(in: split.children[leftIndex]).map(\.id)
            + Tiling.allPanes(in: split.children[leftIndex + 1]).map(\.id)
        )
        return (next, highlighted)
    }

    private func updateDrag(leftIndex: Int, region: DividerRegion, translation: CGSize, available: CGFloat) {
        let ownDelta = split.direction == .horizontal ? translation.width : translation.height
        let perpendicularDelta = split.direction == .horizontal ? translation.height : translation.width
        guard let own = resizedWeights(leftIndex: leftIndex, delta: ownDelta, available: available) else { return }
        var weightsBySplit = [split.id: own.weights]
        var highlighted = own.highlightedPaneIDs
        let resize: PerpendicularResize.Resize? = switch region {
        case .leading: perpendicularResize?.leading
        case .middle: nil
        case .trailing: perpendicularResize?.trailing
        }
        if let perpendicularResize, let perpendicular = resize?(perpendicularDelta) {
            weightsBySplit[perpendicularResize.splitID] = perpendicular.weights
            highlighted.formUnion(perpendicular.highlightedPaneIDs)
        }
        reporter?.change(weightsBySplit, highlighted)
        dragWeights = weightsBySplit
    }

    private func commitDrag() {
        for (splitID, weights) in dragWeights ?? [:] {
            tiling.setWeights(splitID: splitID, weights: weights)
        }
        dragWeights = nil
        reporter?.end()
    }
}
