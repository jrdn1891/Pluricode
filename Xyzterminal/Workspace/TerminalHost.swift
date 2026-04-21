import AppKit

final class TerminalHost {
    let paneID: UUID
    let session: TerminalSession
    let worktreePath: String
    let profileStore: AgentProfileStore
    private var hasStarted = false

    init(paneID: UUID, worktreePath: String, profileStore: AgentProfileStore) {
        self.paneID = paneID
        self.worktreePath = worktreePath
        self.profileStore = profileStore
        self.session = TerminalSession(nodeID: paneID)
        session.worktreePath = worktreePath
        session.updateColors(theme: Theme(from: NSApp.effectiveAppearance))
    }

    func startIfNeeded(scrollbackDir: URL?) {
        guard !hasStarted else { return }
        hasStarted = true

        let config = WorktreeConfig.load(at: worktreePath)
        if let profileID = config.agentProfileID,
           let profile = profileStore.profile(id: profileID) {
            let agent = AgentDefinition.builtins.first { $0.name == profile.agentDefinition } ?? .claudeCode
            ProfileInjector.inject(profile: profile, method: agent.roleInjection, worktreePath: worktreePath)
        }

        if let scrollbackDir {
            session.restoreScrollback(from: scrollbackDir)
        }
        session.start(in: worktreePath)

        if let script = config.startupScript, !script.isEmpty {
            session.scheduleStartupScript(script)
        }
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
