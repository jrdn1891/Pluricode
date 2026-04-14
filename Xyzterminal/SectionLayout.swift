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

    static func layout(
        section: CanvasNode,
        tasks: [(id: UUID, data: TaskCardData)],
        viewType: SectionData.ViewType
    ) -> [UUID: Entry] {
        switch viewType {
        case .list: layoutList(section: section, tasks: tasks)
        case .kanban: layoutKanban(section: section, tasks: tasks)
        }
    }

    private static func layoutList(
        section: CanvasNode,
        tasks: [(id: UUID, data: TaskCardData)]
    ) -> [UUID: Entry] {
        let cardH: Float = 40
        let cardW = section.size.x - padding * 2
        let startX = section.position.x + padding
        var y = section.position.y + headerHeight

        var result: [UUID: Entry] = [:]
        for item in tasks.sorted(by: { $0.data.orderIndex < $1.data.orderIndex }) {
            result[item.id] = Entry(
                position: SIMD2<Float>(startX, y),
                size: SIMD2<Float>(cardW, cardH)
            )
            y += cardH + gap
        }
        return result
    }

    private static func layoutKanban(
        section: CanvasNode,
        tasks: [(id: UUID, data: TaskCardData)]
    ) -> [UUID: Entry] {
        let cardH: Float = 60
        let statuses = TaskCardData.Status.allCases
        let numCols = Float(statuses.count)
        let colW = (section.size.x - padding * 2 - colGap * (numCols - 1)) / numCols
        let cardW = colW - 8

        var result: [UUID: Entry] = [:]
        for (colIndex, status) in statuses.enumerated() {
            let cardX = section.position.x + padding + (colW + colGap) * Float(colIndex) + 4
            var y = section.position.y + headerHeight + colHeaderHeight
            let matching = tasks
                .filter { $0.data.status == status }
                .sorted { $0.data.orderIndex < $1.data.orderIndex }
            for item in matching {
                result[item.id] = Entry(
                    position: SIMD2<Float>(cardX, y),
                    size: SIMD2<Float>(cardW, cardH)
                )
                y += cardH + gap
            }
        }
        return result
    }
}
