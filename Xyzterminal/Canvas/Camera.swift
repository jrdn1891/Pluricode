import Foundation
import simd

struct Camera: Codable {
    var offset: SIMD2<Float> = .zero
    var zoom: Float = 1.0

    static let minZoom: Float = 0.05
    static let maxZoom: Float = 10.0

    enum CodingKeys: String, CodingKey { case offset, zoom }

    func viewProjectionMatrix(viewportSize: SIMD2<Float>) -> simd_float4x4 {
        let sx = zoom * 2.0 / viewportSize.x
        let sy = -zoom * 2.0 / viewportSize.y
        return simd_float4x4(
            SIMD4<Float>(sx, 0, 0, 0),
            SIMD4<Float>(0, sy, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(-offset.x * sx, -offset.y * sy, 0, 1)
        )
    }

    func screenToCanvas(_ point: CGPoint, viewportSize: CGSize) -> SIMD2<Float> {
        let screenX = Float(point.x)
        let screenY = Float(viewportSize.height) - Float(point.y)
        return SIMD2<Float>(
            (screenX - Float(viewportSize.width) * 0.5) / zoom + offset.x,
            (screenY - Float(viewportSize.height) * 0.5) / zoom + offset.y
        )
    }

    func canvasToScreen(_ point: SIMD2<Float>, viewportSize: CGSize) -> CGPoint {
        let screenX = (point.x - offset.x) * zoom + Float(viewportSize.width) * 0.5
        let screenY = Float(viewportSize.height) - ((point.y - offset.y) * zoom + Float(viewportSize.height) * 0.5)
        return CGPoint(x: CGFloat(screenX), y: CGFloat(screenY))
    }

    func canvasToSwiftUI(_ point: SIMD2<Float>, viewportSize: CGSize) -> CGPoint {
        CGPoint(
            x: CGFloat((point.x - offset.x) * zoom + Float(viewportSize.width) * 0.5),
            y: CGFloat((point.y - offset.y) * zoom + Float(viewportSize.height) * 0.5)
        )
    }

    mutating func clampZoom() {
        zoom = max(Self.minZoom, min(Self.maxZoom, zoom))
    }
}
