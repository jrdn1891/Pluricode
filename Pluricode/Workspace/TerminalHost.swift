import AppKit

final class TerminalHost {
    let tabID: UUID
    let session: TerminalSession
    let containerView: NSView
    let cwd: String
    let startupScript: String?
    private var hasStarted = false

    init(
        tabID: UUID,
        cwd: String,
        startupScript: String? = nil,
        onLocalHostDiscovered: ((URL) -> Void)? = nil
    ) {
        self.tabID = tabID
        self.cwd = cwd
        self.startupScript = startupScript
        self.session = TerminalSession(nodeID: tabID)
        session.worktreePath = cwd
        session.onLocalHostDiscovered = onLocalHostDiscovered
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
        session.start(in: cwd)

        if let script = startupScript, !script.isEmpty {
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
        session.saveScrollback(to: dir)
    }

    func teardown() {
        containerView.removeFromSuperview()
    }
}
