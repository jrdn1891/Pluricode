import SwiftUI
import AppKit

struct TerminalPaneView: NSViewRepresentable {
    let tabID: UUID
    let worktreePath: String
    let repoPath: String
    let workspace: Workspace
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> NSView {
        let host = hostForTab()
        let scrollbackDir = workspace.scrollbackDir
        Task { @MainActor in
            await host.startIfNeeded(scrollbackDir: scrollbackDir)
        }
        return host.containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        hostForTab().applyTheme(Theme(from: NSApp.effectiveAppearance))
    }

    private func hostForTab() -> TerminalHost {
        if let existing = workspace.terminalHosts[tabID] { return existing }
        let host = TerminalHost(
            tabID: tabID,
            worktreePath: worktreePath,
            repoPath: repoPath,
            profileStore: workspace.profileStore,
            extraStartupScript: workspace.consumePendingDevScript(tabID: tabID),
            mcpPrompt: workspace.consumePendingMCPPrompt(tabID: tabID),
            workspace: workspace
        )
        workspace.terminalHosts[tabID] = host
        return host
    }
}
