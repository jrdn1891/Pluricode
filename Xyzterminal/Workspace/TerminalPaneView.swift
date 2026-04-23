import SwiftUI
import AppKit

struct TerminalPaneView: NSViewRepresentable {
    let paneID: UUID
    let worktreePath: String
    let repoPath: String
    let workspace: Workspace
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true

        let host = hostForPane()
        host.startIfNeeded(scrollbackDir: workspace.scrollbackDir)

        let term = host.session.terminalView
        term.translatesAutoresizingMaskIntoConstraints = false
        if term.superview !== container {
            term.removeFromSuperview()
            container.addSubview(term)
        }
        NSLayoutConstraint.activate([
            term.topAnchor.constraint(equalTo: container.topAnchor),
            term.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            term.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            term.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let host = hostForPane()
        host.applyTheme(Theme(from: NSApp.effectiveAppearance))
        let term = host.session.terminalView
        if term.superview !== nsView {
            term.removeFromSuperview()
            term.translatesAutoresizingMaskIntoConstraints = false
            nsView.addSubview(term)
            NSLayoutConstraint.activate([
                term.topAnchor.constraint(equalTo: nsView.topAnchor),
                term.bottomAnchor.constraint(equalTo: nsView.bottomAnchor),
                term.leadingAnchor.constraint(equalTo: nsView.leadingAnchor),
                term.trailingAnchor.constraint(equalTo: nsView.trailingAnchor)
            ])
        }
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
