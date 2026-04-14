import simd

struct EdgeVertex {
    var position: SIMD2<Float>
    var color: SIMD4<Float>
}

enum EdgeTessellator {
    static let segmentCount = 32
    static let lineThickness: Float = 2.5
    static let arrowSize: Float = 10.0

    static func tessellate(
        from sourceNode: CanvasNode,
        to targetNode: CanvasNode,
        color: SIMD4<Float>
    ) -> [EdgeVertex] {
        let sourceCenter = sourceNode.position + sourceNode.size * 0.5
        let targetCenter = targetNode.position + targetNode.size * 0.5

        let sourcePort = portPoint(from: sourceCenter, toward: targetCenter, nodeSize: sourceNode.size)
        let targetPort = portPoint(from: targetCenter, toward: sourceCenter, nodeSize: targetNode.size)

        let dist = abs(targetPort.x - sourcePort.x)
        let handleOffset = max(50.0, dist * 0.4)
        let sign: Float = targetPort.x > sourcePort.x ? 1 : -1

        let p0 = sourcePort
        let p1 = SIMD2<Float>(sourcePort.x + handleOffset * sign, sourcePort.y)
        let p2 = SIMD2<Float>(targetPort.x - handleOffset * sign, targetPort.y)
        let p3 = targetPort

        var points: [SIMD2<Float>] = []
        for i in 0...segmentCount {
            let t = Float(i) / Float(segmentCount)
            points.append(cubicBezier(p0, p1, p2, p3, t))
        }
        guard points.count >= 2 else { return [] }

        var strip: [(SIMD2<Float>, SIMD2<Float>)] = []
        for i in 0..<points.count {
            let tangent: SIMD2<Float>
            if i == 0 {
                tangent = normalize(points[1] - points[0])
            } else if i == points.count - 1 {
                tangent = normalize(points[i] - points[i - 1])
            } else {
                tangent = normalize(points[i + 1] - points[i - 1])
            }
            let normal = SIMD2<Float>(-tangent.y, tangent.x)
            let half = lineThickness * 0.5
            strip.append((points[i] + normal * half, points[i] - normal * half))
        }

        var triangles: [EdgeVertex] = []
        for i in 0..<(strip.count - 1) {
            let (a0, b0) = strip[i]
            let (a1, b1) = strip[i + 1]
            triangles.append(EdgeVertex(position: a0, color: color))
            triangles.append(EdgeVertex(position: b0, color: color))
            triangles.append(EdgeVertex(position: a1, color: color))
            triangles.append(EdgeVertex(position: b0, color: color))
            triangles.append(EdgeVertex(position: b1, color: color))
            triangles.append(EdgeVertex(position: a1, color: color))
        }

        let tip = targetPort
        let dir = normalize(targetPort - points[points.count - 2])
        let perp = SIMD2<Float>(-dir.y, dir.x)
        let base = tip - dir * arrowSize
        triangles.append(EdgeVertex(position: base + perp * arrowSize * 0.5, color: color))
        triangles.append(EdgeVertex(position: base - perp * arrowSize * 0.5, color: color))
        triangles.append(EdgeVertex(position: tip, color: color))

        return triangles
    }

    private static func portPoint(
        from center: SIMD2<Float>,
        toward target: SIMD2<Float>,
        nodeSize: SIMD2<Float>
    ) -> SIMD2<Float> {
        let half = nodeSize * 0.5
        if target.x > center.x {
            return SIMD2<Float>(center.x + half.x, center.y)
        } else {
            return SIMD2<Float>(center.x - half.x, center.y)
        }
    }

    private static func cubicBezier(
        _ p0: SIMD2<Float>, _ p1: SIMD2<Float>,
        _ p2: SIMD2<Float>, _ p3: SIMD2<Float>,
        _ t: Float
    ) -> SIMD2<Float> {
        let u = 1.0 - t
        let tt = t * t
        let uu = u * u
        return uu * u * p0 + 3.0 * uu * t * p1 + 3.0 * u * tt * p2 + tt * t * p3
    }
}
