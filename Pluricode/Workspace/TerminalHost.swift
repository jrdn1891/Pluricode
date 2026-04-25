import AppKit

final class TerminalHost {
    let paneID: UUID
    let session: TerminalSession
    let containerView: NSView
    let worktreePath: String
    let repoPath: String
    let profileStore: AgentProfileStore
    private var hasStarted = false

    init(paneID: UUID, worktreePath: String, repoPath: String, profileStore: AgentProfileStore) {
        self.paneID = paneID
        self.worktreePath = worktreePath
        self.repoPath = repoPath
        self.profileStore = profileStore
        self.session = TerminalSession(nodeID: paneID)
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

        let worktreeConfig = WorktreeConfig.load(at: worktreePath)
        if let profileID = worktreeConfig.agentProfileID,
           let profile = profileStore.profile(id: profileID) {
            let agent = AgentDefinition.builtins.first { $0.name == profile.agentDefinition } ?? .claudeCode
            ProfileInjector.inject(profile: profile, method: agent.roleInjection, worktreePath: worktreePath)
        }

        if let scrollbackDir {
            session.restoreScrollback(from: scrollbackDir)
        }
        session.start(in: worktreePath)

        let repoConfig = RepoConfig.load(at: repoPath)
        if let script = repoConfig.startupScript, !script.isEmpty {
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
