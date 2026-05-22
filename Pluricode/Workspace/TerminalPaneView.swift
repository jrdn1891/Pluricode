import SwiftUI
import AppKit

struct TerminalPaneView: NSViewRepresentable {
    let paneID: UUID
    let tabID: UUID
    let repoID: UUID
    let worktreeID: String
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
        let startup = workspace.consumePendingDevScript(tabID: tabID)
            ?? RepoConfig.load(at: repoPath).startupScript
        let host = TerminalHost(
            tabID: tabID,
            cwd: worktreePath,
            startupScript: startup,
            onLocalHostDiscovered: { [weak workspace, tabID, repoID, worktreeID] url in
                guard let workspace, let store = workspace.store else { return }
                store.localHostRegistry.record(
                    workspaceID: workspace.id,
                    tabID: tabID,
                    url: url,
                    repoID: repoID,
                    branch: worktreeID
                )
            }
        )
        workspace.terminalHosts[tabID] = host
        return host
    }
}

struct ShellPaneView: NSViewRepresentable {
    let paneID: UUID
    let tabID: UUID
    let cwd: URL
    let workspace: Workspace

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
        let host = TerminalHost(tabID: tabID, cwd: cwd.path, startupScript: nil)
        workspace.terminalHosts[tabID] = host
        return host
    }
}
