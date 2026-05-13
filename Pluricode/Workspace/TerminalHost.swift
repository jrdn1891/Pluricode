import AppKit

final class TerminalHost {
    let tabID: UUID
    let session: TerminalSession
    let containerView: NSView
    let worktreePath: String
    let repoPath: String
    let extraStartupScript: String?
    private var hasStarted = false

    init(
        tabID: UUID,
        worktreePath: String,
        repoPath: String,
        extraStartupScript: String? = nil
    ) {
        self.tabID = tabID
        self.worktreePath = worktreePath
        self.repoPath = repoPath
        self.extraStartupScript = extraStartupScript
        self.session = TerminalSession(nodeID: tabID)
        session.worktreePath = worktreePath
        session.updateColors(theme: Theme(from: NSApp.effectiveAppearance))

        let container = NSView()
        container.wantsLayer = true
        let term = session.terminalView
        term.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(term)
        NSLayoutConstraint.activate([
            term.topAnchor.constraint(equalTo: container.topAnchor),
            term.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            term.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            term.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        self.containerView = container
    }

    func startIfNeeded(scrollbackDir: URL?) {
        guard !hasStarted else { return }
        hasStarted = true

        if let scrollbackDir {
            session.restoreScrollback(from: scrollbackDir)
        }
        session.start(in: worktreePath)

        if let extra = extraStartupScript, !extra.isEmpty {
            session.sendStartupScript(extra)
        } else if let script = RepoConfig.load(at: repoPath).startupScript, !script.isEmpty {
            session.sendStartupScript(script)
        }
    }

    func applyTheme(_ theme: Theme) {
        session.updateColors(theme: theme)
    }

    func focusInput() {
        let term = session.terminalView
        term.window?.makeFirstResponder(term)
    }

    func saveScrollback(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        session.saveScrollback(to: dir)
    }

    func teardown() {
        containerView.removeFromSuperview()
    }
}
