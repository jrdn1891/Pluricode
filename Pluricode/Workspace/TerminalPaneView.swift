import SwiftUI
import AppKit

struct TerminalPaneView: NSViewRepresentable {
    let paneID: UUID
    let tabID: UUID
    let worktreePath: String
    let repoPath: String
    let workspace: Workspace
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> NSView {
        let host = hostForTab()
        host.startIfNeeded(scrollbackDir: workspace.scrollbackDir)
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
        let host = TerminalHost(
            tabID: tabID,
            worktreePath: worktreePath,
            repoPath: repoPath,
            extraStartupScript: workspace.consumePendingDevScript(tabID: tabID)
        )
        workspace.terminalHosts[tabID] = host
        return host
    }
}
