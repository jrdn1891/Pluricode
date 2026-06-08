import AppKit
import WebKit
import Observation

@Observable
final class BrowserHost {
    let tabID: UUID
    let repoID: UUID
    let worktreeID: String
    let originTabID: UUID?
    let webView: WKWebView

    var currentURL: URL?
    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    var pageTitle: String?

    var isMarkingUp = false
    var markupRects: [CGRect] = []
    var markupNote = ""

    @ObservationIgnored var onURLChange: ((URL) -> Void)?
    @ObservationIgnored private var observers: [NSKeyValueObservation] = []
    @ObservationIgnored private var hasLoaded = false

    init(tabID: UUID, repoID: UUID, worktreeID: String, originTabID: UUID?) {
        self.tabID = tabID
        self.repoID = repoID
        self.worktreeID = worktreeID
        self.originTabID = originTabID
        self.webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        observers = [
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] wv, _ in self?.canGoBack = wv.canGoBack },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] wv, _ in self?.canGoForward = wv.canGoForward },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] wv, _ in self?.isLoading = wv.isLoading },
            webView.observe(\.title, options: [.initial, .new]) { [weak self] wv, _ in self?.pageTitle = wv.title },
            webView.observe(\.url, options: [.initial, .new]) { [weak self] wv, _ in
                guard let self else { return }
                self.currentURL = wv.url
                if let url = wv.url { self.onURLChange?(url) }
            }
        ]
    }

    func loadIfNeeded(url: URL?) {
        guard !hasLoaded, let url else { return }
        load(url)
    }

    func load(_ url: URL) {
        hasLoaded = true
        webView.load(URLRequest(url: url))
    }

    func reload() {
        if webView.isLoading { webView.stopLoading() } else { webView.reload() }
    }

    func beginMarkup() { isMarkingUp = true }

    func cancelMarkup() {
        isMarkingUp = false
        markupRects = []
        markupNote = ""
    }

    func clearRects() { markupRects = [] }

    func captureSnapshot(_ completion: @escaping (NSImage?) -> Void) {
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        config.afterScreenUpdates = true
        webView.takeSnapshot(with: config) { image, _ in
            completion(image)
        }
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

    func teardown() {
        observers.forEach { $0.invalidate() }
        observers.removeAll()
        webView.stopLoading()
        webView.removeFromSuperview()
    }
}
