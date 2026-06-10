import SwiftUI
import AppKit

struct PaneCreationToolbar: ToolbarContent {
    let workspace: Workspace?

    var body: some ToolbarContent {
        ToolbarItemGroup {
            PaneCreationButton(
                workspace: workspace,
                action: .addNew,
                systemImage: "plus",
                help: "New Pane"
            )
            PaneCreationButton(
                workspace: workspace,
                action: .splitRight,
                systemImage: "rectangle.split.2x1",
                help: "Split Vertically"
            )
            PaneCreationButton(
                workspace: workspace,
                action: .splitDown,
                systemImage: "rectangle.split.1x2",
                help: "Split Horizontally"
            )
        }
    }
}

private struct PaneCreationButton: View {
    let workspace: Workspace?
    let action: Workspace.PaneCreationAction
    let systemImage: String
    let help: String
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Image(systemName: systemImage)
        }
        .help(help)
        .disabled(workspace == nil)
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            if let workspace {
                PaneCreationPopover(
                    workspace: workspace,
                    action: action,
                    onComplete: { showing = false }
                )
            }
        }
    }
}

private struct PaneCreationPopover: View {
    let workspace: Workspace
    let action: Workspace.PaneCreationAction
    let onComplete: () -> Void
    @State private var worktreesByRepo: [UUID: [Worktree]] = [:]
    @State private var newWorktreeRepo: RepoEntry?
    @State private var highlight: Int = 0

    private enum Item: Identifiable {
        case widget(WidgetKind)
        case shell(cwd: URL, label: String)
        case chooseFolder
        case worktree(repo: RepoEntry, worktree: Worktree)
        case newWorktree(RepoEntry)

        var id: String {
            switch self {
            case .widget(let k): "w:\(k.rawValue)"
            case .shell(let cwd, _): "s:\(cwd.path)"
            case .chooseFolder: "cf"
            case .worktree(let r, let wt): "wt:\(r.id):\(wt.id)"
            case .newWorktree(let r): "nw:\(r.id)"
            }
        }
    }

    private struct Section: Identifiable {
        let id: String
        let header: Header
        let items: [Item]

        enum Header {
            case widgets
            case terminal
            case repo(RepoEntry)
        }
    }

    private var sections: [Section] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var result: [Section] = [
            Section(id: "widgets", header: .widgets, items: [.widget(.localHosts)]),
            Section(id: "terminal", header: .terminal, items: [
                .shell(cwd: home, label: "Home"),
                .chooseFolder
            ])
        ]
        for repo in workspace.repoStore.repos {
            var items: [Item] = (worktreesByRepo[repo.id] ?? []).map {
                .worktree(repo: repo, worktree: $0)
            }
            items.append(.newWorktree(repo))
            result.append(Section(id: "repo:\(repo.id)", header: .repo(repo), items: items))
        }
        return result
    }

    private var items: [Item] {
        sections.flatMap(\.items)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(sections) { section in
                            sectionView(section)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .onChange(of: highlight) { _, _ in
                    let all = items
                    guard all.indices.contains(highlight) else { return }
                    proxy.scrollTo(all[highlight].id, anchor: .center)
                }
            }
            KeyHintBar(hints: [
                ("↑↓", "Navigate"),
                ("⏎", "Open"),
                ("⎋", "Close")
            ])
        }
        .frame(width: 280, height: 360)
        .background(KeyboardCatcher(
            onMoveUp: { move(-1) },
            onMoveDown: { move(1) },
            onReturn: { commit() },
            onEscape: onComplete
        ))
        .task(loadAll)
        .sheet(item: $newWorktreeRepo) { repo in
            NewWorktreeSheet(repo: repo) { branch in
                workspace.performPaneCreation(
                    action,
                    content: .terminal(repoID: repo.id, worktreeID: branch)
                )
                onComplete()
            }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: Section) -> some View {
        sectionHeader(section.header)
        ForEach(section.items) { item in
            row(item)
                .id(item.id)
        }
    }

    @ViewBuilder
    private func sectionHeader(_ header: Section.Header) -> some View {
        HStack(spacing: 6) {
            switch header {
            case .widgets:
                Image(systemName: "square.grid.2x2")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("Widgets")
                    .font(.system(size: 12, weight: .semibold))
            case .terminal:
                Image(systemName: "terminal")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("Terminal")
                    .font(.system(size: 12, weight: .semibold))
            case .repo(let repo):
                Image(systemName: "folder.fill")
                    .foregroundStyle(repo.resolvedColor.swiftUIColor)
                    .font(.caption)
                Text(repo.name)
                    .font(.system(size: 12, weight: .semibold))
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func row(_ item: Item) -> some View {
        let highlighted = items.firstIndex(where: { $0.id == item.id }) == highlight
        switch item {
        case .widget(let kind):
            PaneCreationRow(
                icon: kind.systemImage,
                title: kind.label,
                subtitle: "Browser links from running dev servers",
                highlighted: highlighted
            ) { run(item) }
        case .shell(let cwd, let label):
            PaneCreationRow(
                icon: "folder",
                title: label,
                subtitle: cwd.path,
                highlighted: highlighted
            ) { run(item) }
        case .chooseFolder:
            PaneCreationRow(
                icon: "folder.badge.plus",
                title: "Choose Folder…",
                subtitle: nil,
                muted: true,
                highlighted: highlighted
            ) { run(item) }
        case .worktree(_, let wt):
            PaneCreationRow(
                icon: "arrow.triangle.branch",
                title: wt.displayName,
                subtitle: wt.branch,
                highlighted: highlighted
            ) { run(item) }
        case .newWorktree:
            PaneCreationRow(
                icon: "plus.circle",
                title: "New Worktree…",
                subtitle: nil,
                muted: true,
                highlighted: highlighted
            ) { run(item) }
        }
    }

    private func run(_ item: Item) {
        switch item {
        case .widget(let kind):
            workspace.performPaneCreation(action, content: .widget(kind))
            onComplete()
        case .shell(let cwd, _):
            workspace.performPaneCreation(action, content: .shell(cwd: cwd))
            onComplete()
        case .chooseFolder:
            chooseFolder()
        case .worktree(let repo, let wt):
            workspace.performPaneCreation(
                action,
                content: .terminal(repoID: repo.id, worktreeID: wt.branch)
            )
            onComplete()
        case .newWorktree(let repo):
            newWorktreeRepo = repo
        }
    }

    private func chooseFolder() {
        onComplete()
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workspace.performPaneCreation(action, content: .shell(cwd: url))
    }

    private func move(_ delta: Int) {
        let count = items.count
        guard count > 0 else { return }
        highlight = ((highlight + delta) % count + count) % count
    }

    private func commit() {
        let all = items
        guard all.indices.contains(highlight) else { return }
        run(all[highlight])
    }

    @Sendable private func loadAll() async {
        for repo in workspace.repoStore.repos {
            if let wm = WorktreeManager(repoRoot: repo.path) {
                worktreesByRepo[repo.id] = await wm.listManagedWorktrees()
            } else {
                worktreesByRepo[repo.id] = []
            }
        }
    }
}

private struct PaneCreationRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var muted: Bool = false
    let highlighted: Bool
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(muted ? .secondary : Color.accentColor)
                    .font(.caption)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12))
                        .foregroundStyle(muted ? .secondary : .primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(background)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    private var background: Color {
        if highlighted { return Color.accentColor.opacity(0.25) }
        if hovered { return Color.accentColor.opacity(0.15) }
        return Color.clear
    }
}
