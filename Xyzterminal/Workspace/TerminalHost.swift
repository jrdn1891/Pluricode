import AppKit

final class TerminalHost {
    let paneID: UUID
    let session: TerminalSession
    let worktreePath: String
    private var hasStarted = false

    init(paneID: UUID, worktreePath: String) {
        self.paneID = paneID
        self.worktreePath = worktreePath
        self.session = TerminalSession(nodeID: paneID)
        session.worktreePath = worktreePath
        session.updateColors(theme: Theme(from: NSApp.effectiveAppearance))
    }

    func startIfNeeded(scrollbackDir: URL?) {
        guard !hasStarted else { return }
        hasStarted = true
        if let scrollbackDir {
            session.restoreScrollback(from: scrollbackDir)
        }
        session.start(in: worktreePath)
    }

    func applyTheme(_ theme: Theme) {
        session.updateColors(theme: theme)
    }

    func saveScrollback(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        session.saveScrollback(to: dir)
    }

    func teardown() {
        session.terminalView.removeFromSuperview()
    }
}
