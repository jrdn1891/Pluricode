import SwiftUI

struct WorkspaceView: View {
    let workspace: Workspace

    var body: some View {
        WorkspaceBody(workspace: workspace)
            .focusedSceneValue(\.workspace, workspace)
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
            Text("Or drag a Task List from the sidebar to jot down quick notes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
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
            return workspace.acceptDrop(payload: payload, on: nil, edge: .center)
        } isTargeted: { isTargeted = $0 }
    }
}

private struct WorkspacePane: View {
    let pane: Pane
    let workspace: Workspace

    var body: some View {
        let focused = workspace.focusedPaneID == pane.id
        PaneFrame(focused: focused) {
            switch pane.content {
            case .terminal(let repoID, let worktreeID):
                TerminalPaneBody(paneID: pane.id, repoID: repoID, worktreeID: worktreeID, workspace: workspace)
            case .tasks(let repoID, let listID):
                TaskPaneBody(paneID: pane.id, repoID: repoID, listID: listID, workspace: workspace)
            }
        }
    }
}

private struct PaneFrame<Content: View>: View {
    let focused: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(
                        focused ? Color.accentColor : Color.secondary.opacity(0.2),
                        lineWidth: focused ? 2 : 1
                    )
                    .allowsHitTesting(false)
            }
    }
}

private struct TaskPaneBody: View {
    let paneID: UUID
    let repoID: UUID
    let listID: UUID
    let workspace: Workspace
    @State private var isTargeted = false

    var body: some View {
        GeometryReader { geo in
            if let store = workspace.taskStore(repoID: repoID) {
                TaskPaneView(
                    paneID: paneID,
                    listID: listID,
                    store: store,
                    focused: workspace.focusedPaneID == paneID,
                    onActivate: { workspace.setFocus(paneID: paneID) },
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
                    return workspace.acceptDrop(payload: payload, on: paneID, edge: edge)
                } isTargeted: { isTargeted = $0 }
            } else {
                MissingRepoBody(onRemove: { workspace.closePane(paneID: paneID) })
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}

private struct TerminalPaneBody: View {
    let paneID: UUID
    let repoID: UUID
    let worktreeID: String
    let workspace: Workspace
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                paneID: paneID,
                title: displayName,
                branch: worktreeID,
                repoName: workspace.repo(id: repoID)?.name,
                profile: resolveProfile(),
                focused: workspace.focusedPaneID == paneID,
                onActivate: { workspace.setFocus(paneID: paneID) },
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
                            return workspace.acceptDrop(payload: payload, on: paneID, edge: edge)
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
        guard let repo = workspace.repo(id: repoID),
              let wm = WorktreeManager(repoRoot: repo.path) else { return nil }
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
    let paneID: UUID
    let title: String
    let branch: String
    let repoName: String?
    let profile: AgentProfile?
    let focused: Bool
    let onActivate: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let repoName {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.tint)
                    .font(.caption)
                Text(repoName)
                    .font(.system(size: 12, weight: .medium))
                Text("·")
                    .foregroundStyle(.secondary)
            }
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
        .background(focused ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
        .draggable(TilingDragPayload(kind: .movePane(paneID: paneID))) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                Text(title)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
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

private struct MissingRepoBody: View {
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text("Repository unavailable")
                .font(.headline)
            Text("The repo this pane belongs to was removed from the library.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Remove Pane", role: .destructive, action: onRemove)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
