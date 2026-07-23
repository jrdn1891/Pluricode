import AppKit
import Observation

@Observable
final class Markup {
    var isMarkingUp = false
    var rects: [CGRect] = []
    var note = ""

    func begin() { isMarkingUp = true }

    func cancel() {
        isMarkingUp = false
        rects = []
        note = ""
    }

    static func annotate(_ image: NSImage, rects: [CGRect]) -> NSImage {
        guard !rects.isEmpty,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cg = rep.cgImage else { return image }
        let pw = rep.pixelsWide
        let ph = rep.pixelsHigh
        guard let ctx = CGContext(
            data: nil, width: pw, height: ph,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: pw, height: ph))
        ctx.setStrokeColor(NSColor.systemRed.cgColor)
        ctx.setLineWidth(max(2, CGFloat(pw) / 320))
        for r in rects {
            ctx.stroke(CGRect(
                x: r.minX * CGFloat(pw),
                y: (1 - r.minY - r.height) * CGFloat(ph),
                width: r.width * CGFloat(pw),
                height: r.height * CGFloat(ph)
            ))
        }
        guard let out = ctx.makeImage() else { return image }
        return NSImage(cgImage: out, size: NSSize(width: pw, height: ph))
    }

    static func writeTempPNG(_ image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let path = NSTemporaryDirectory() + "pluricode-markup-\(UUID().uuidString.prefix(8)).png"
        do {
            try png.write(to: URL(fileURLWithPath: path))
            return path
        } catch {
            return nil
        }
    }
}
