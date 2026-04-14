import Foundation
import simd

enum SectionLayout {
    struct Entry {
        var position: SIMD2<Float>
        var size: SIMD2<Float>
    }

    static let headerHeight: Float = 40
    static let colHeaderHeight: Float = 28
    static let padding: Float = 12
    static let gap: Float = 4
    static let colGap: Float = 8

    struct Result {
        var entries: [UUID: Entry]
        var contentHeight: Float
    }

    static func layout(
        section: CanvasNode,
        tasks: [(id: UUID, data: TaskCardData)],
        viewType: SectionData.ViewType,
        isCollapsed: Bool = false
    ) -> Result {
        if isCollapsed {
            return Result(entries: [:], contentHeight: headerHeight)
        }
        return switch viewType {
        case .list: layoutList(section: section, tasks: tasks)
        case .kanban: layoutKanban(section: section, tasks: tasks)
        }
    }

    private static func layoutList(
        section: CanvasNode,
        tasks: [(id: UUID, data: TaskCardData)]
    ) -> Result {
        let cardH: Float = 40
        let cardW = section.size.x - padding * 2
        let startX = section.position.x + padding
        var y = section.position.y + headerHeight

        var entries: [UUID: Entry] = [:]
        for item in tasks.sorted(by: { $0.data.orderIndex < $1.data.orderIndex }) {
            entries[item.id] = Entry(
                position: SIMD2<Float>(startX, y),
                size: SIMD2<Float>(cardW, cardH)
            )
            y += cardH + gap
        }
        let contentHeight = headerHeight + Float(tasks.count) * (cardH + gap) + padding
        return Result(entries: entries, contentHeight: contentHeight)
    }

    private static func layoutKanban(
        section: CanvasNode,
        tasks: [(id: UUID, data: TaskCardData)]
    ) -> Result {
        let cardH: Float = 60
        let statuses = TaskCardData.Status.allCases
        let numCols = Float(statuses.count)
        let colW = (section.size.x - padding * 2 - colGap * (numCols - 1)) / numCols
        let cardW = colW - 8

        var entries: [UUID: Entry] = [:]
        var maxColCount: Int = 0
        for (colIndex, status) in statuses.enumerated() {
            let cardX = section.position.x + padding + (colW + colGap) * Float(colIndex) + 4
            var y = section.position.y + headerHeight + colHeaderHeight
            let matching = tasks
                .filter { $0.data.status == status }
                .sorted { $0.data.orderIndex < $1.data.orderIndex }
            maxColCount = max(maxColCount, matching.count)
            for item in matching {
                entries[item.id] = Entry(
                    position: SIMD2<Float>(cardX, y),
                    size: SIMD2<Float>(cardW, cardH)
                )
                y += cardH + gap
            }
        }
        let contentHeight = headerHeight + colHeaderHeight + Float(maxColCount) * (cardH + gap) + padding
        return Result(entries: entries, contentHeight: contentHeight)
    }
}
