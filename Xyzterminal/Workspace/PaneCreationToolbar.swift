import SwiftUI

struct PaneCreationToolbar: ToolbarContent {
    let workspace: Workspace?
    let profileStore: AgentProfileStore

    var body: some ToolbarContent {
        ToolbarItemGroup {
            PaneCreationButton(
                workspace: workspace,
                profileStore: profileStore,
                action: .addNew,
                systemImage: "plus",
                help: "New Pane"
            )
            PaneCreationButton(
                workspace: workspace,
                profileStore: profileStore,
                action: .splitRight,
                systemImage: "rectangle.split.2x1",
                help: "Split Vertically"
            )
            PaneCreationButton(
                workspace: workspace,
                profileStore: profileStore,
                action: .splitDown,
                systemImage: "rectangle.split.1x2",
                help: "Split Horizontally"
            )
        }
    }
}

private struct PaneCreationButton: View {
    let workspace: Workspace?
    let profileStore: AgentProfileStore
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
                    profileStore: profileStore,
                    action: action,
                    onComplete: { showing = false }
                )
            }
        }
    }
}

private struct PaneCreationPopover: View {
    let workspace: Workspace
    let profileStore: AgentProfileStore
    let action: Workspace.PaneCreationAction
    let onComplete: () -> Void
    @State private var worktreesByRepo: [UUID: [Worktree]] = [:]
    @State private var newWorktreeRepo: RepoEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if workspace.repoStore.repos.isEmpty {
                Text("Add a repository from the sidebar first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(workspace.repoStore.repos) { repo in
                            repoSection(repo)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(width: 280, height: 360)
        .onAppear(perform: loadAll)
        .sheet(item: $newWorktreeRepo) { repo in
            NewWorktreeSheet(repo: repo, profileStore: profileStore) { branch in
                workspace.performPaneCreation(
                    action,
                    content: .terminal(repoID: repo.id, worktreeID: branch)
                )
                onComplete()
            }
        }
    }

    @ViewBuilder
    private func repoSection(_ repo: RepoEntry) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .foregroundStyle(repo.resolvedColor.swiftUIColor)
                .font(.caption)
            Text(repo.name)
                .font(.system(size: 12, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 2)

        ForEach(worktreesByRepo[repo.id] ?? []) { wt in
            PaneCreationRow(
                icon: "arrow.triangle.branch",
                title: wt.displayName,
                subtitle: wt.branch
            ) {
                workspace.performPaneCreation(
                    action,
                    content: .terminal(repoID: repo.id, worktreeID: wt.branch)
                )
                onComplete()
            }
        }

        PaneCreationRow(
            icon: "plus.circle",
            title: "New Worktree…",
            subtitle: nil,
            muted: true
        ) {
            newWorktreeRepo = repo
        }
    }

    private func loadAll() {
        for repo in workspace.repoStore.repos {
            if let wm = WorktreeManager(repoRoot: repo.path) {
                worktreesByRepo[repo.id] = wm.listManagedWorktrees()
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
            .background(hovered ? Color.accentColor.opacity(0.15) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
