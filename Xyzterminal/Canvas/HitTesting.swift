import Foundation
import simd

enum HitTesting {
    static func nodeAt(_ canvasPoint: SIMD2<Float>, in nodes: [UUID: CanvasNode]) -> UUID? {
        for (id, node) in nodes {
            if canvasPoint.x >= node.position.x
                && canvasPoint.x <= node.position.x + node.size.x
                && canvasPoint.y >= node.position.y
                && canvasPoint.y <= node.position.y + node.size.y
            {
                return id
            }
        }
        return nil
    }

    static func nodesInRect(
        origin: SIMD2<Float>,
        size: SIMD2<Float>,
        in nodes: [UUID: CanvasNode]
    ) -> Set<UUID> {
        let minX = min(origin.x, origin.x + size.x)
        let maxX = max(origin.x, origin.x + size.x)
        let minY = min(origin.y, origin.y + size.y)
        let maxY = max(origin.y, origin.y + size.y)

        var result = Set<UUID>()
        for (id, node) in nodes {
            let nodeMaxX = node.position.x + node.size.x
            let nodeMaxY = node.position.y + node.size.y
            if nodeMaxX > minX && node.position.x < maxX
                && nodeMaxY > minY && node.position.y < maxY
            {
                result.insert(id)
            }
        }
        return result
    }
}
