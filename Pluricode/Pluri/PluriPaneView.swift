import SwiftUI
import AppKit

struct PluriPaneView: NSViewRepresentable {
    let paneID: UUID
    let tabID: UUID
    let workspace: Workspace

    func makeNSView(context: Context) -> NSView {
        let host = hostForTab()
        host.startIfNeeded(scrollbackDir: workspace.scrollbackDir)
        if workspace.consumePendingFocus(paneID: paneID) {
            DispatchQueue.main.async { host.focusInput() }
        }
        return host.containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let host = hostForTab()
        host.applyTheme(Theme(from: NSApp.effectiveAppearance))
        host.session.onFocus = { [weak workspace, paneID] in
            workspace?.setFocus(paneID: paneID)
        }
    }

    private func hostForTab() -> TerminalHost {
        if let existing = workspace.terminalHosts[tabID] { return existing }
        PluriHome.prepare(repos: workspace.repoStore.repos)
        let host = TerminalHost(tabID: tabID, cwd: PluriHome.dir.path, startupScript: "claude")
        workspace.terminalHosts[tabID] = host
        return host
    }
}
