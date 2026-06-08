import SwiftUI
import WebKit

struct BrowserPaneView: NSViewRepresentable {
    let tabID: UUID
    let repoID: UUID
    let worktreeID: String
    let initialURL: URL?
    let workspace: Workspace

    func makeNSView(context: Context) -> NSView {
        let host = hostForTab()
        host.loadIfNeeded(url: initialURL)
        return host.webView
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func hostForTab() -> BrowserHost {
        if let existing = workspace.browserHosts[tabID] { return existing }
        let host = BrowserHost(
            tabID: tabID,
            repoID: repoID,
            worktreeID: worktreeID,
            originTabID: workspace.consumePendingBrowserOrigin(tabID: tabID)
        )
        host.onURLChange = { [weak workspace, tabID] url in
            workspace?.updateBrowserURL(tabID: tabID, url: url)
        }
        workspace.browserHosts[tabID] = host
        return host
    }
}
