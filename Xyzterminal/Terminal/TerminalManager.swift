import AppKit

final class TerminalManager {
    let document: CanvasDocument
    var sessions: [UUID: TerminalSession] = [:]
    var worktreeManager: WorktreeManager?
    private static let titleBarHeight: Float = 30

    init(document: CanvasDocument) {
        self.document = document
        if let projectPath = document.projectPath,
           let root = WorktreeManager.findRepoRoot(from: projectPath) {
            self.worktreeManager = WorktreeManager(repoRoot: root)
        }
    }

    func sync(containerView: NSView) {
        let terminalNodeIDs = Set(document.nodes.values.compactMap { node -> UUID? in
            if case .terminal = node.kind { return node.id }
            return nil
        })

        for id in Array(sessions.keys) where !terminalNodeIDs.contains(id) {
            let session = sessions.removeValue(forKey: id)
            session?.terminalView.removeFromSuperview()
            if let path = session?.worktreePath, let wm = worktreeManager {
                Task.detached { try? wm.removeWorktree(at: URL(fileURLWithPath: path)) }
            }
        }

        for id in terminalNodeIDs where sessions[id] == nil {
            let session = TerminalSession(nodeID: id)
            containerView.addSubview(session.terminalView)

            if let wm = worktreeManager {
                let shortID = id.uuidString.prefix(8).lowercased()
                let baseBranch = wm.defaultBranch()
                if let path = try? wm.createWorktree(name: String(shortID), baseBranch: baseBranch) {
                    session.worktreePath = path.path
                    let branch = wm.currentBranch(at: path) ?? "xyz-\(shortID)"
                    session.start(in: path.path)

                    if var node = document.nodes[id], case .terminal(var data) = node.kind {
                        data.worktreePath = path.path
                        data.branchName = branch
                        node.kind = .terminal(data)
                        document.nodes[id] = node
                        document.scheduleSave()
                    }
                } else {
                    session.start()
                }
            } else {
                session.start()
            }

            if let node = document.nodes[id], case .terminal(let data) = node.kind {
                if let role = data.role, let path = session.worktreePath {
                    let agent = AgentDefinition.builtins.first { $0.name == data.agentName } ?? .claudeCode
                    RoleInjector.inject(role: role, method: agent.roleInjection, worktreePath: path)
                }
                if let script = data.startupScript, !script.isEmpty {
                    let bytes = Array("\(script)\n".utf8)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        session.terminalView.process?.send(data: bytes[...])
                    }
                }
            }

            session.onProcessTerminated = { [weak self] _ in
                guard var node = self?.document.nodes[id],
                      case .terminal(var data) = node.kind else { return }
                data.status = .done
                node.kind = .terminal(data)
                self?.document.nodes[id] = node
            }
            sessions[id] = session
        }

        let viewportSize = containerView.bounds.size
        guard viewportSize.width > 0 else { return }

        for (id, session) in sessions {
            guard let node = document.nodes[id] else { continue }

            let termTop = node.position + SIMD2<Float>(0, Self.titleBarHeight)
            let termBottomRight = node.position + node.size

            let screenTL = document.camera.canvasToScreen(termTop, viewportSize: viewportSize)
            let screenBR = document.camera.canvasToScreen(termBottomRight, viewportSize: viewportSize)

            let frame = NSRect(
                x: screenTL.x,
                y: screenBR.y,
                width: screenBR.x - screenTL.x,
                height: screenTL.y - screenBR.y
            )

            let visible = frame.height > 80
                && frame.width > 100
                && frame.intersects(containerView.bounds)

            session.terminalView.isHidden = !visible
            if visible && session.terminalView.frame != frame {
                session.terminalView.frame = frame
            }
        }
    }
}
