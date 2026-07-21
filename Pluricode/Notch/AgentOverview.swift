import Foundation

struct AgentRow: Identifiable {
    let id: String
    let repoID: UUID
    let branch: String
    let label: String
    let state: WorkerState?

    var detail: String? {
        let text: String?
        switch state?.status {
        case .waiting: text = state?.message
        case .running: text = state?.activity
        default: text = nil
        }
        guard let text, !text.isEmpty else { return nil }
        return text
    }
}

struct WorkspaceGroup: Identifiable {
    let id: UUID
    let name: String
    let rows: [AgentRow]
}

struct AgentOverview {
    let groups: [WorkspaceGroup]
    let working: Int
    let waiting: Int
    let idle: Int
}

extension AgentOverview {
    @MainActor
    static func build(workspaces: [Workspace], statuses: [String: WorkerState]) -> AgentOverview {
        var groups: [WorkspaceGroup] = []
        var working = 0
        var waiting = 0
        var idle = 0
        for workspace in workspaces {
            var rows: [AgentRow] = []
            var seen: Set<String> = []
            for pane in workspace.tiling.panes + workspace.minimizedPanes.map(\.pane) {
                for tab in pane.tabs {
                    guard case .terminal(let repoID, let branch) = tab.content,
                          tab.name != "dev",
                          let repo = workspace.repo(id: repoID) else { continue }
                    let path = repo.path
                        .appendingPathComponent(".pluricode/worktrees/\(branch)")
                        .standardizedFileURL.path
                    guard seen.insert(path).inserted else { continue }
                    let state = statuses[path]
                    rows.append(AgentRow(id: path, repoID: repoID, branch: branch, label: branch, state: state))
                    switch state?.status {
                    case .running: working += 1
                    case .waiting: waiting += 1
                    default: idle += 1
                    }
                }
            }
            if !rows.isEmpty {
                groups.append(WorkspaceGroup(id: workspace.id, name: workspace.name, rows: rows))
            }
        }
        return AgentOverview(groups: groups, working: working, waiting: waiting, idle: idle)
    }
}
