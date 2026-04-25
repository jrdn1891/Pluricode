import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceView: View {
    let workspace: Workspace

    var body: some View {
        ZStack {
            WorkspaceBody(workspace: workspace)
            if let id = workspace.expandedPaneID {
                ExpandedPaneOverlay(paneID: id, workspace: workspace)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: workspace.expandedPaneID)
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
        .onDrop(of: [.plainText], delegate: EmptyWorkspaceDropDelegate(workspace: workspace, isTargeted: $isTargeted))
    }
}

private struct WorkspacePane: View {
    let pane: Pane
    let workspace: Workspace

    var body: some View {
        PaneFrame {
            switch pane.content {
            case .terminal(let repoID, let worktreeID):
                TerminalPaneBody(paneID: pane.id, repoID: repoID, worktreeID: worktreeID, workspace: workspace)
            case .tasks(let listID):
                TaskPaneBody(paneID: pane.id, listID: listID, workspace: workspace)
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
    let listID: UUID
    let workspace: Workspace
    @State private var hoverEdge: TileEdge?

    var body: some View {
        GeometryReader { geo in
            TaskPaneView(
                paneID: paneID,
                listID: listID,
                store: workspace.taskListStore,
                onActivate: { workspace.setFocus(paneID: paneID) },
                onClose: { workspace.closePane(paneID: paneID) }
            )
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay {
                if let edge = hoverEdge {
                    DropZoneOverlay(edge: edge, size: geo.size)
                }
            }
            .onDrop(
                of: [.plainText],
                delegate: PaneDropDelegate(
                    paneID: paneID,
                    workspace: workspace,
                    size: geo.size,
                    hoverEdge: $hoverEdge
                )
            )
        }
    }
}

private struct TerminalPaneBody: View {
    let paneID: UUID
    let repoID: UUID
    let worktreeID: String
    let workspace: Workspace
    @State private var hoverEdge: TileEdge?

    var body: some View {
        let isExpanded = workspace.expandedPaneID == paneID
        VStack(spacing: 0) {
            PaneHeader(
                paneID: paneID,
                workspace: workspace,
                title: workspace.paneDisplayName(worktreeID: worktreeID),
                branch: worktreeID,
                repoName: workspace.repo(id: repoID)?.name,
                repoColor: workspace.repo(id: repoID)?.resolvedColor.swiftUIColor,
                profile: workspace.paneProfile(paneID: paneID),
                isExpanded: isExpanded,
                onActivate: { workspace.setFocus(paneID: paneID) },
                onExpand: {
                    if isExpanded { workspace.collapseExpandedPane() }
                    else { workspace.expandPane(paneID: paneID) }
                },
                onClose: { workspace.closePane(paneID: paneID) }
            )
            if isExpanded {
                ExpandedPanePlaceholder()
            } else if let path = workspace.worktreePath(paneID: paneID), let repoPath = workspace.repo(id: repoID)?.path.path {
                GeometryReader { geo in
                    TerminalPaneView(paneID: paneID, worktreePath: path, repoPath: repoPath, workspace: workspace)
                        .overlay {
                            if let session = workspace.terminalHosts[paneID]?.session {
                                IdleOverlay(session: session)
                            }
                        }
                        .overlay {
                            if let edge = hoverEdge {
                                DropZoneOverlay(edge: edge, size: geo.size)
                            }
                        }
                        .onDrop(
                            of: [.plainText],
                            delegate: PaneDropDelegate(
                                paneID: paneID,
                                workspace: workspace,
                                size: geo.size,
                                hoverEdge: $hoverEdge
                            )
                        )
                }
            } else {
                MissingWorktreeBody(
                    worktreeID: worktreeID,
                    onRemove: { workspace.closePane(paneID: paneID) }
                )
            }
        }
    }

}

private struct ExpandedPanePlaceholder: View {
    var body: some View {
        ZStack {
            Color.secondary.opacity(0.08)
            Text("Expanded")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PaneHeader: View {
    let paneID: UUID
    let workspace: Workspace
    let title: String
    let branch: String
    let repoName: String?
    let repoColor: Color?
    let profile: AgentProfile?
    let isExpanded: Bool
    let onActivate: () -> Void
    let onExpand: () -> Void
    let onClose: () -> Void
    @State private var isMerged: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if let repoName {
                Circle()
                    .fill(repoColor ?? .accentColor)
                    .frame(width: 10, height: 10)
                Text(repoName)
                    .font(.system(size: 12, weight: .medium))
                Text("·")
                    .foregroundStyle(.secondary)
            }
            Image(systemName: isMerged ? "arrow.trianglehead.merge" : "arrow.triangle.branch")
                .foregroundStyle(isMerged ? Color.green : Color.secondary)
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
            Button(action: onExpand) {
                Image(systemName: isExpanded
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse" : "Expand")
            if !isExpanded {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(headerBackground)
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
        .task(id: paneID) {
            guard let pathString = workspace.worktreePath(paneID: paneID) else { return }
            let path = URL(fileURLWithPath: pathString)
            while !Task.isCancelled {
                let next = await Task.detached { WorktreeManager.isMerged(at: path) }.value
                if next != isMerged { isMerged = next }
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .draggable(TilingDragPayload(kind: .movePane(paneID: paneID))) {
            HStack(spacing: 6) {
                Image(systemName: isMerged ? "arrow.trianglehead.merge" : "arrow.triangle.branch")
                Text(title)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var headerBackground: Color {
        if let repoColor { return repoColor.opacity(0.12) }
        return Color.secondary.opacity(0.1)
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

private struct DropZoneOverlay: View {
    let edge: TileEdge
    let size: CGSize

    var body: some View {
        let rect = frame(for: edge, in: size)
        ZStack(alignment: .topLeading) {
            Color.clear
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor, lineWidth: 2)
                )
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    private func frame(for edge: TileEdge, in s: CGSize) -> CGRect {
        switch edge {
        case .left:   CGRect(x: 0, y: 0, width: s.width / 2, height: s.height)
        case .right:  CGRect(x: s.width / 2, y: 0, width: s.width / 2, height: s.height)
        case .top:    CGRect(x: 0, y: 0, width: s.width, height: s.height / 2)
        case .bottom: CGRect(x: 0, y: s.height / 2, width: s.width, height: s.height / 2)
        case .center: CGRect(x: 0, y: 0, width: s.width, height: s.height)
        }
    }
}

private struct EmptyWorkspaceDropDelegate: DropDelegate {
    let workspace: Workspace
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) { isTargeted = true }
    func dropExited(info: DropInfo) { isTargeted = false }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { obj, _ in
            guard let str = obj as? String,
                  let data = str.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(TilingDragPayload.self, from: data) else { return }
            DispatchQueue.main.async {
                _ = workspace.acceptDrop(payload: payload, on: nil, edge: .center)
            }
        }
        return true
    }
}

private struct PaneDropDelegate: DropDelegate {
    let paneID: UUID
    let workspace: Workspace
    let size: CGSize
    @Binding var hoverEdge: TileEdge?

    func dropEntered(info: DropInfo) {
        hoverEdge = TileEdge.zone(for: info.location, in: size)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        hoverEdge = TileEdge.zone(for: info.location, in: size)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        hoverEdge = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let edge = TileEdge.zone(for: info.location, in: size)
        hoverEdge = nil
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { obj, _ in
            guard let str = obj as? String,
                  let data = str.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(TilingDragPayload.self, from: data) else { return }
            DispatchQueue.main.async {
                _ = workspace.acceptDrop(payload: payload, on: paneID, edge: edge)
            }
        }
        return true
    }
}

private struct ExpandedPaneOverlay: View {
    let paneID: UUID
    let workspace: Workspace

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { workspace.collapseExpandedPane() }
            GeometryReader { geo in
                ExpandedPaneCard(paneID: paneID, workspace: workspace)
                    .frame(
                        width: min(geo.size.width * 0.9, 1400),
                        height: min(geo.size.height * 0.9, 900)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onExitCommand { workspace.collapseExpandedPane() }
    }
}

private struct ExpandedPaneCard: View {
    let paneID: UUID
    let workspace: Workspace

    var body: some View {
        if let pane = workspace.pane(id: paneID),
           case .terminal(let repoID, let worktreeID) = pane.content {
            TerminalExpandedContent(
                paneID: paneID,
                repoID: repoID,
                worktreeID: worktreeID,
                workspace: workspace
            )
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 30, y: 10)
        }
    }

    private var cardBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }
}

private struct TerminalExpandedContent: View {
    let paneID: UUID
    let repoID: UUID
    let worktreeID: String
    let workspace: Workspace

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                paneID: paneID,
                workspace: workspace,
                title: workspace.paneDisplayName(worktreeID: worktreeID),
                branch: worktreeID,
                repoName: workspace.repo(id: repoID)?.name,
                repoColor: workspace.repo(id: repoID)?.resolvedColor.swiftUIColor,
                profile: workspace.paneProfile(paneID: paneID),
                isExpanded: true,
                onActivate: { workspace.setFocus(paneID: paneID) },
                onExpand: { workspace.collapseExpandedPane() },
                onClose: { workspace.closePane(paneID: paneID) }
            )
            if let path = workspace.worktreePath(paneID: paneID),
               let repoPath = workspace.repo(id: repoID)?.path.path {
                TerminalPaneView(paneID: paneID, worktreePath: path, repoPath: repoPath, workspace: workspace)
            } else {
                MissingWorktreeBody(
                    worktreeID: worktreeID,
                    onRemove: { workspace.closePane(paneID: paneID) }
                )
            }
        }
    }
}
