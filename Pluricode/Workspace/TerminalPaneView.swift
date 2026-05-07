import SwiftUI
import AppKit

struct TerminalPaneView: NSViewRepresentable {
    let tabID: UUID
    let worktreePath: String
    let repoPath: String
    let workspace: Workspace
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> NSView {
        let host = workspace.terminalHost(forTab: tabID, worktreePath: worktreePath, repoPath: repoPath)
        host.startIfNeeded(scrollbackDir: workspace.scrollbackDir)
        return host.containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        workspace
            .terminalHost(forTab: tabID, worktreePath: worktreePath, repoPath: repoPath)
            .applyTheme(Theme(from: NSApp.effectiveAppearance))
    }
}
