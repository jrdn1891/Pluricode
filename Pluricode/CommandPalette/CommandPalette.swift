import SwiftUI
import AppKit

enum PaletteAction: Identifiable, Hashable {
    case toggleSidebar
    case toggleExpandAllRepos
    case deleteMergedWorktrees
    case createWorkspace
    case switchWorkspace(id: UUID, name: String)

    var id: String {
        switch self {
        case .toggleSidebar: "toggleSidebar"
        case .toggleExpandAllRepos: "toggleExpandAllRepos"
        case .deleteMergedWorktrees: "deleteMergedWorktrees"
        case .createWorkspace: "createWorkspace"
        case .switchWorkspace(let id, _): "switchWorkspace:\(id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .toggleSidebar: "Toggle Sidebar"
        case .toggleExpandAllRepos: "Expand / Collapse All Repos"
        case .deleteMergedWorktrees: "Delete All Merged Worktrees"
        case .createWorkspace: "Create New Workspace"
        case .switchWorkspace(_, let name): "Switch to: \(name)"
        }
    }

    var systemImage: String {
        switch self {
        case .toggleSidebar: "sidebar.left"
        case .toggleExpandAllRepos: "chevron.down.square"
        case .deleteMergedWorktrees: "trash"
        case .createWorkspace: "plus.rectangle.on.rectangle"
        case .switchWorkspace: "arrow.right.circle"
        }
    }
}

struct MergedWorktreeMatch: Identifiable, Hashable {
    let repoID: UUID
    let branch: String
    let path: String
    var id: String { "\(repoID.uuidString):\(branch)" }
}

struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    @Binding var columnVisibility: NavigationSplitViewVisibility
    let workspaceStore: WorkspaceStore
    let repoStore: RepoStore
    let sidebarState: SidebarState
    let onCreateWorkspace: () -> Void
    let onMergedDeletionFound: ([MergedWorktreeMatch]) -> Void

    @State private var query: String = ""
    @State private var selection: Int = 0
    @State private var scanningMerged = false
    @FocusState private var queryFocused: Bool

    private var actions: [PaletteAction] {
        var list: [PaletteAction] = [
            .toggleSidebar,
            .toggleExpandAllRepos,
            .deleteMergedWorktrees,
            .createWorkspace
        ]
        list += workspaceStore.workspaces
            .filter { $0.id != workspaceStore.selectedWorkspaceID }
            .map { .switchWorkspace(id: $0.id, name: $0.name) }
        return list
    }

    private var filtered: [PaletteAction] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return actions }
        return actions.filter { $0.title.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Type a command…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($queryFocused)
                    .onSubmit(runSelection)
                if scanningMerged {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let items = filtered
                        if items.isEmpty {
                            Text("No matching actions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 16)
                                .frame(maxWidth: .infinity)
                        } else {
                            ForEach(Array(items.enumerated()), id: \.element.id) { idx, action in
                                PaletteRow(
                                    action: action,
                                    isSelected: idx == selection
                                ) {
                                    selection = idx
                                    runSelection()
                                }
                                .id(action.id)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 320)
                .onChange(of: selection) { _, _ in
                    let items = filtered
                    guard items.indices.contains(selection) else { return }
                    proxy.scrollTo(items[selection].id, anchor: .center)
                }
            }
        }
        .frame(width: 480)
        .background(KeyEventCatcher(
            onMoveUp: { move(-1) },
            onMoveDown: { move(1) },
            onCancel: { isPresented = false }
        ))
        .onChange(of: query) { _, _ in selection = 0 }
        .onAppear { queryFocused = true }
    }

    private func move(_ delta: Int) {
        let count = filtered.count
        guard count > 0 else { return }
        selection = ((selection + delta) % count + count) % count
    }

    private func runSelection() {
        let items = filtered
        guard items.indices.contains(selection) else { return }
        execute(items[selection])
    }

    private func execute(_ action: PaletteAction) {
        switch action {
        case .toggleSidebar:
            columnVisibility = (columnVisibility == .detailOnly) ? .all : .detailOnly
            isPresented = false
        case .toggleExpandAllRepos:
            sidebarState.toggleAll(repoStore.repos)
            isPresented = false
        case .deleteMergedWorktrees:
            scanMergedWorktrees()
        case .createWorkspace:
            isPresented = false
            onCreateWorkspace()
        case .switchWorkspace(let id, _):
            workspaceStore.selectedWorkspaceID = id
            workspaceStore.saveSelection()
            isPresented = false
        }
    }

    private func scanMergedWorktrees() {
        guard !scanningMerged else { return }
        scanningMerged = true
        let snapshot = repoStore.repos
        Task.detached {
            var matches: [MergedWorktreeMatch] = []
            for repo in snapshot {
                guard let wm = WorktreeManager(repoRoot: repo.path) else { continue }
                for wt in wm.listManagedWorktrees() where !wt.isPrimary {
                    let url = URL(fileURLWithPath: wt.path)
                    if WorktreeManager.isMerged(at: url) {
                        matches.append(MergedWorktreeMatch(
                            repoID: repo.id,
                            branch: wt.branch,
                            path: wt.path
                        ))
                    }
                }
            }
            await MainActor.run {
                scanningMerged = false
                isPresented = false
                onMergedDeletionFound(matches)
            }
        }
    }
}

private struct PaletteRow: View {
    let action: PaletteAction
    let isSelected: Bool
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: action.systemImage)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                Text(action.title)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : (hovered ? Color.gray.opacity(0.15) : Color.clear))
                    .padding(.horizontal, 6)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct KeyEventCatcher: NSViewRepresentable {
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = CatcherView()
        view.onMoveUp = onMoveUp
        view.onMoveDown = onMoveDown
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let v = nsView as? CatcherView else { return }
        v.onMoveUp = onMoveUp
        v.onMoveDown = onMoveDown
        v.onCancel = onCancel
    }

    final class CatcherView: NSView {
        var onMoveUp: (() -> Void)?
        var onMoveDown: (() -> Void)?
        var onCancel: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self, self.window != nil else { return event }
                    switch event.keyCode {
                    case 126: self.onMoveUp?(); return nil    // up
                    case 125: self.onMoveDown?(); return nil  // down
                    case 53:  self.onCancel?(); return nil    // esc
                    default: return event
                    }
                }
            } else if window == nil, let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }

        deinit {
            if let m = monitor { NSEvent.removeMonitor(m) }
        }
    }
}
