import Foundation
import simd

enum ResizeCorner {
    case topLeft, topRight, bottomLeft, bottomRight
}

enum HitTesting {
    static func resizeHandleAt(
        _ canvasPoint: SIMD2<Float>,
        in nodes: [UUID: CanvasNode],
        selectedIDs: Set<UUID>,
        handleSize: Float = 14
    ) -> (UUID, ResizeCorner)? {
        for id in selectedIDs {
            guard let node = nodes[id] else { continue }
            let minX = node.position.x
            let minY = node.position.y
            let maxX = minX + node.size.x
            let maxY = minY + node.size.y

            if canvasPoint.x >= maxX - handleSize && canvasPoint.x <= maxX
                && canvasPoint.y >= maxY - handleSize && canvasPoint.y <= maxY {
                return (id, .bottomRight)
            }
            if canvasPoint.x >= minX && canvasPoint.x <= minX + handleSize
                && canvasPoint.y >= maxY - handleSize && canvasPoint.y <= maxY {
                return (id, .bottomLeft)
            }
            if canvasPoint.x >= maxX - handleSize && canvasPoint.x <= maxX
                && canvasPoint.y >= minY && canvasPoint.y <= minY + handleSize {
                return (id, .topRight)
            }
            if canvasPoint.x >= minX && canvasPoint.x <= minX + handleSize
                && canvasPoint.y >= minY && canvasPoint.y <= minY + handleSize {
                return (id, .topLeft)
            }
        }
        return nil
    }

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

    static func edgeAt(
        _ canvasPoint: SIMD2<Float>,
        in edges: [UUID: Edge],
        nodes: [UUID: CanvasNode],
        threshold: Float = 8.0
    ) -> UUID? {
        for (id, edge) in edges {
            guard let source = nodes[edge.sourceID],
                  let target = nodes[edge.targetID] else { continue }

            let sourceCenter = source.position + source.size * 0.5
            let targetCenter = target.position + target.size * 0.5
            let p0 = portPoint(from: sourceCenter, toward: targetCenter, halfSize: source.size * 0.5)
            let p3 = portPoint(from: targetCenter, toward: sourceCenter, halfSize: target.size * 0.5)

            let dist = abs(p3.x - p0.x)
            let offset = max(50.0, dist * 0.4)
            let sign: Float = p3.x > p0.x ? 1 : -1
            let p1 = SIMD2<Float>(p0.x + offset * sign, p0.y)
            let p2 = SIMD2<Float>(p3.x - offset * sign, p3.y)

            for i in 0..<32 {
                let t = Float(i) / 32.0
                let pt = cubicBezier(p0, p1, p2, p3, t)
                let d = simd_length(canvasPoint - pt)
                if d < threshold {
                    return id
                }
            }
        }
        return nil
    }

    private static func portPoint(from center: SIMD2<Float>, toward target: SIMD2<Float>, halfSize: SIMD2<Float>) -> SIMD2<Float> {
        if target.x > center.x {
            return SIMD2<Float>(center.x + halfSize.x, center.y)
        } else {
            return SIMD2<Float>(center.x - halfSize.x, center.y)
        }
    }

    private static func cubicBezier(_ p0: SIMD2<Float>, _ p1: SIMD2<Float>, _ p2: SIMD2<Float>, _ p3: SIMD2<Float>, _ t: Float) -> SIMD2<Float> {
        let u = 1.0 - t
        return u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3
    }
}
