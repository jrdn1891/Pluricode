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

    let markup = Markup()

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

    func captureSnapshot(_ completion: @escaping (NSImage?) -> Void) {
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        config.afterScreenUpdates = true
        webView.takeSnapshot(with: config) { image, _ in
            completion(image)
        }
    }

    func teardown() {
        observers.forEach { $0.invalidate() }
        observers.removeAll()
        webView.stopLoading()
        webView.removeFromSuperview()
    }
}
