import SwiftUI
import AppKit

struct TerminalPaneView: NSViewRepresentable {
    let paneID: UUID
    let worktreePath: String
    let repoPath: String
    let workspace: Workspace
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> NSView {
        let host = hostForPane()
        host.startIfNeeded(scrollbackDir: workspace.scrollbackDir)
        return host.containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        hostForPane().applyTheme(Theme(from: NSApp.effectiveAppearance))
    }

    private func hostForPane() -> TerminalHost {
        if let existing = workspace.terminalHosts[paneID] { return existing }
        let host = TerminalHost(
            paneID: paneID,
            worktreePath: worktreePath,
            repoPath: repoPath,
            profileStore: workspace.profileStore
        )
        workspace.terminalHosts[paneID] = host
        return host
    }
}
