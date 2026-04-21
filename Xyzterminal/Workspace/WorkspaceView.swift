import SwiftUI

struct WorkspaceView: View {
    let repo: RepoEntry
    let profileStore: AgentProfileStore
    @State private var workspace: Workspace?

    var body: some View {
        Group {
            if let workspace {
                WorkspaceBody(workspace: workspace)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if workspace == nil {
                let ws = Workspace(repo: repo, profileStore: profileStore)
                ws.load()
                workspace = ws
            }
        }
        .onDisappear {
            workspace?.save()
        }
    }
}

private struct WorkspaceBody: View {
    let workspace: Workspace

    var body: some View {
        if let root = workspace.tiling.root {
            TileView(node: root, tiling: workspace.tiling) { pane in
                WorkspacePane(pane: pane, workspace: workspace)
            }
            .padding(4)
        } else {
            EmptyWorkspace(workspace: workspace)
        }
    }
}

private struct EmptyWorkspace: View {
    let workspace: Workspace
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Drag a worktree here")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Expand a repository in the sidebar to find its worktrees.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .padding(32)
        }
        .dropDestination(for: TilingDragPayload.self) { items, _ in
            guard let payload = items.first else { return false }
            workspace.addPane(payload.paneContent)
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

private struct WorkspacePane: View {
    let pane: Pane
    let workspace: Workspace

    var body: some View {
        PaneFrame {
            switch pane.content {
            case .terminal(let worktreeID):
                TerminalPaneBody(paneID: pane.id, worktreeID: worktreeID, workspace: workspace)
            case .tasks:
                TaskPaneBody(paneID: pane.id, workspace: workspace)
            }
        }
    }
}

private struct PaneFrame<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

private struct TaskPaneBody: View {
    let paneID: UUID
    let workspace: Workspace
    @State private var isTargeted = false

    var body: some View {
        GeometryReader { geo in
            TaskPaneView(
                store: workspace.taskStore,
                onClose: { workspace.closePane(paneID: paneID) }
            )
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor, lineWidth: 3)
                        .allowsHitTesting(false)
                }
            }
            .dropDestination(for: TilingDragPayload.self) { items, location in
                guard let payload = items.first else { return false }
                let edge = TileEdge.zone(for: location, in: geo.size)
                workspace.splitPane(paneID: paneID, edge: edge, content: payload.paneContent)
                return true
            } isTargeted: { isTargeted = $0 }
        }
    }
}

private struct TerminalPaneBody: View {
    let paneID: UUID
    let worktreeID: String
    let workspace: Workspace
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                title: displayName,
                branch: worktreeID,
                profile: resolveProfile(),
                onClose: { workspace.closePane(paneID: paneID) }
            )
            if let path = resolveWorktreePath() {
                GeometryReader { geo in
                    TerminalPaneView(paneID: paneID, worktreePath: path, workspace: workspace)
                        .overlay {
                            if isTargeted {
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.accentColor, lineWidth: 3)
                                    .allowsHitTesting(false)
                            }
                        }
                        .dropDestination(for: TilingDragPayload.self) { items, location in
                            guard let payload = items.first else { return false }
                            let edge = TileEdge.zone(for: location, in: geo.size)
                            workspace.splitPane(paneID: paneID, edge: edge, content: payload.paneContent)
                            return true
                        } isTargeted: { isTargeted = $0 }
                }
            } else {
                MissingWorktreeBody(
                    worktreeID: worktreeID,
                    onRemove: { workspace.closePane(paneID: paneID) }
                )
            }
        }
    }

    private var displayName: String {
        worktreeID.hasPrefix("xyz-") ? String(worktreeID.dropFirst("xyz-".count)) : worktreeID
    }

    private func resolveWorktreePath() -> String? {
        guard let wm = WorktreeManager(repoRoot: workspace.repo.path) else { return nil }
        return wm.listManagedWorktrees().first { $0.branch == worktreeID }?.path
    }

    private func resolveProfile() -> AgentProfile? {
        guard let path = resolveWorktreePath() else { return nil }
        let config = WorktreeConfig.load(at: path)
        guard let id = config.agentProfileID else { return nil }
        return workspace.profileStore.profile(id: id)
    }
}

private struct PaneHeader: View {
    let title: String
    let branch: String
    let profile: AgentProfile?
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Text(branch)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let profile {
                Circle()
                    .fill(profile.swiftUIColor)
                    .frame(width: 8, height: 8)
                Text(profile.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.1))
    }
}

private struct MissingWorktreeBody: View {
    let worktreeID: String
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text("Worktree `\(worktreeID)` not found")
                .font(.headline)
            Text("It may have been deleted or renamed.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Remove Pane", role: .destructive, action: onRemove)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
