import SwiftUI

struct RepoSidebarView: View {
    let repoStore: RepoStore
    let profileStore: AgentProfileStore
    let taskStoreRegistry: TaskStoreRegistry
    let workspaceStore: WorkspaceStore
    @State private var expanded: Set<UUID> = []
    @State private var worktrees: [UUID: [Worktree]] = [:]
    @State private var newWorktreeRepo: RepoEntry?
    @State private var deleteCandidate: DeleteCandidate?
    @State private var renameTarget: RenameTarget?
    @State private var configureTarget: RenameTarget?
    @State private var newListRepo: RepoEntry?
    @State private var renameListTarget: ListTarget?
    @State private var deleteListCandidate: ListTarget?
    @State private var creatingWorkspace = false
    @State private var renameWorkspaceTarget: Workspace?
    @State private var deleteWorkspaceCandidate: Workspace?

    var body: some View {
        List(selection: Binding(
            get: { workspaceStore.selectedWorkspaceID },
            set: { workspaceStore.selectedWorkspaceID = $0; workspaceStore.saveSelection() }
        )) {
            Section("Workspaces") {
                ForEach(workspaceStore.workspaces, id: \.id) { ws in
                    WorkspaceRow(workspace: ws)
                        .tag(ws.id)
                        .contextMenu {
                            Button("Rename...") { renameWorkspaceTarget = ws }
                            Divider()
                            Button("Delete", role: .destructive) { deleteWorkspaceCandidate = ws }
                        }
                }
                Button(action: { creatingWorkspace = true }) {
                    Label("New Workspace", systemImage: "plus.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
            }

            Section("Repositories") {
                ForEach(repoStore.repos) { repo in
                    RepoRow(repo: repo, isExpanded: expanded.contains(repo.id), toggle: { toggle(repo) })
                        .contextMenu {
                            Button("Show in Finder") {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: repo.path.path)
                            }
                            Divider()
                            Button("Remove", role: .destructive) {
                                repoStore.removeRepo(id: repo.id)
                            }
                        }

                    if expanded.contains(repo.id) {
                        ForEach(worktrees[repo.id] ?? []) { wt in
                            WorktreeRow(repoID: repo.id, worktree: wt, profileStore: profileStore)
                                .padding(.leading, 20)
                                .contextMenu {
                                    Button("Configure...") {
                                        configureTarget = RenameTarget(repo: repo, worktree: wt)
                                    }
                                    Button("Rename...") {
                                        renameTarget = RenameTarget(repo: repo, worktree: wt)
                                    }
                                    Button("Show in Finder") {
                                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: wt.path)
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        deleteCandidate = DeleteCandidate(repo: repo, worktree: wt)
                                    }
                                }
                        }

                        Button(action: { newWorktreeRepo = repo }) {
                            Label("New Worktree", systemImage: "plus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 20)
                        .padding(.vertical, 2)

                        ForEach(taskStoreRegistry.store(for: repo.path).lists) { list in
                            TaskListRow(repoID: repo.id, list: list)
                                .padding(.leading, 20)
                                .contextMenu {
                                    Button("Rename...") {
                                        renameListTarget = ListTarget(repo: repo, list: list)
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        deleteListCandidate = ListTarget(repo: repo, list: list)
                                    }
                                }
                        }

                        Button(action: { newListRepo = repo }) {
                            Label("New Task List", systemImage: "plus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 20)
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button(action: pickFolder) {
                Label("Add Repository", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .padding()
        }
        .sheet(isPresented: $creatingWorkspace) {
            NewWorkspaceSheet(workspaceStore: workspaceStore)
        }
        .sheet(item: $renameWorkspaceTarget) { ws in
            RenameWorkspaceSheet(workspace: ws, workspaceStore: workspaceStore)
        }
        .sheet(item: $newWorktreeRepo) { repo in
            NewWorktreeSheet(repo: repo, profileStore: profileStore) { refresh(repo) }
        }
        .sheet(item: $renameTarget) { target in
            RenameWorktreeSheet(target: target) { refresh(target.repo) }
        }
        .sheet(item: $configureTarget) { target in
            ConfigureWorktreeSheet(target: target, profileStore: profileStore)
        }
        .sheet(item: $newListRepo) { repo in
            NewTaskListSheet(store: taskStoreRegistry.store(for: repo.path))
        }
        .sheet(item: $renameListTarget) { target in
            RenameTaskListSheet(
                store: taskStoreRegistry.store(for: target.repo.path),
                list: target.list
            )
        }
        .alert(item: $deleteCandidate) { cand in
            Alert(
                title: Text("Delete \(cand.worktree.displayName)?"),
                message: Text("This runs `git worktree remove --force` and deletes the branch `\(cand.worktree.branch)`."),
                primaryButton: .destructive(Text("Delete")) {
                    delete(cand)
                },
                secondaryButton: .cancel()
            )
        }
        .alert(item: $deleteListCandidate) { cand in
            Alert(
                title: Text("Delete list \(cand.list.name)?"),
                message: Text(cand.list.items.isEmpty
                    ? "The list is empty. This cannot be undone."
                    : "This will delete \(cand.list.items.count) task\(cand.list.items.count == 1 ? "" : "s")."),
                primaryButton: .destructive(Text("Delete")) {
                    taskStoreRegistry.store(for: cand.repo.path).removeList(id: cand.list.id)
                },
                secondaryButton: .cancel()
            )
        }
        .alert(item: $deleteWorkspaceCandidate) { ws in
            Alert(
                title: Text("Delete workspace \(ws.name)?"),
                message: Text("Panes are removed from the canvas. Worktrees and task lists in your repos are untouched."),
                primaryButton: .destructive(Text("Delete")) {
                    workspaceStore.removeWorkspace(id: ws.id)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func toggle(_ repo: RepoEntry) {
        if expanded.contains(repo.id) {
            expanded.remove(repo.id)
        } else {
            expanded.insert(repo.id)
            refresh(repo)
        }
    }

    private func refresh(_ repo: RepoEntry) {
        guard let wm = WorktreeManager(repoRoot: repo.path) else {
            worktrees[repo.id] = []
            return
        }
        worktrees[repo.id] = wm.listManagedWorktrees()
    }

    private func delete(_ cand: DeleteCandidate) {
        guard let wm = WorktreeManager(repoRoot: cand.repo.path) else { return }
        let url = URL(fileURLWithPath: cand.worktree.path)
        try? wm.removeWorktree(at: url)
        _ = try? Process.run(
            URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["-C", cand.repo.path.path, "branch", "-D", cand.worktree.branch]
        )
        refresh(cand.repo)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a git repository"
        if panel.runModal() == .OK, let url = panel.url {
            repoStore.addRepo(url)
        }
    }
}

private struct DeleteCandidate: Identifiable {
    let repo: RepoEntry
    let worktree: Worktree
    var id: String { "\(repo.id.uuidString):\(worktree.id)" }
}

private struct RenameTarget: Identifiable {
    let repo: RepoEntry
    let worktree: Worktree
    var id: String { "\(repo.id.uuidString):\(worktree.id)" }
}

private struct ListTarget: Identifiable {
    let repo: RepoEntry
    let list: TaskList
    var id: String { "\(repo.id.uuidString):\(list.id.uuidString)" }
}

extension Workspace: Identifiable {}

struct WorkspaceRow: View {
    let workspace: Workspace

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.split.2x1")
                .foregroundStyle(.tint)
                .font(.caption)
            Text(workspace.name)
                .font(.body)
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

struct RepoRow: View {
    let repo: RepoEntry
    let isExpanded: Bool
    let toggle: () -> Void

    private var pathExists: Bool {
        FileManager.default.fileExists(atPath: repo.path.path)
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggle) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            }
            .buttonStyle(.plain)

            Image(systemName: "folder.fill")
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(repo.name)
                        .font(.body)
                    if !pathExists {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                    }
                }
                Text(repo.path.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .padding(.vertical, 2)
    }
}

struct WorktreeRow: View {
    let repoID: UUID
    let worktree: Worktree
    let profileStore: AgentProfileStore

    private var assignedProfile: AgentProfile? {
        let config = WorktreeConfig.load(at: worktree.path)
        guard let id = config.agentProfileID else { return nil }
        return profileStore.profile(id: id)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.secondary)
                .font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(worktree.displayName)
                        .font(.body)
                    if let profile = assignedProfile {
                        Circle()
                            .fill(profile.swiftUIColor)
                            .frame(width: 8, height: 8)
                        Text(profile.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(worktree.branch)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 1)
        .draggable(TilingDragPayload(kind: .newTerminal(repoID: repoID, worktreeID: worktree.branch))) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                Text(worktree.displayName)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

struct TaskListRow: View {
    let repoID: UUID
    let list: TaskList

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checklist")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(list.name)
                .font(.body)
            Spacer()
            if list.items.count > 0 {
                Text("\(list.items.filter { !$0.done }.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 1)
        .draggable(TilingDragPayload(kind: .newTaskPane(repoID: repoID, listID: list.id))) {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                Text(list.name)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

private struct NewWorkspaceSheet: View {
    let workspaceStore: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Workspace")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.caption).foregroundStyle(.secondary)
                TextField("Bug Fixes", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    _ = workspaceStore.createWorkspace(name: name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

private struct RenameWorkspaceSheet: View {
    let workspace: Workspace
    let workspaceStore: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Workspace")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.caption).foregroundStyle(.secondary)
                TextField("Bug Fixes", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") {
                    workspaceStore.renameWorkspace(id: workspace.id, name: name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear { name = workspace.name }
    }
}

private struct WorktreeConfigFields: View {
    @Binding var agentProfileID: UUID?
    @Binding var startupScript: String
    let profileStore: AgentProfileStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Agent Profile").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $agentProfileID) {
                    Text("None").tag(UUID?.none)
                    ForEach(profileStore.profiles) { profile in
                        Text(profile.name).tag(UUID?.some(profile.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Startup Script").font(.caption).foregroundStyle(.secondary)
                TextField("claude --dangerously-skip-permissions", text: $startupScript, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...5)
                Text("Runs in the pane's shell after it opens in this worktree.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct NewWorktreeSheet: View {
    let repo: RepoEntry
    let profileStore: AgentProfileStore
    let onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var baseBranch: String = ""
    @State private var agentProfileID: UUID?
    @State private var startupScript: String = ""
    @State private var error: String?
    @State private var isCreating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Worktree in \(repo.name)")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.caption).foregroundStyle(.secondary)
                TextField("frontend-fix", text: $name)
                    .textFieldStyle(.roundedBorder)
                Text("Branch will be `xyz-\(sanitized(name))`")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Base Branch").font(.caption).foregroundStyle(.secondary)
                TextField("main", text: $baseBranch)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            WorktreeConfigFields(
                agentProfileID: $agentProfileID,
                startupScript: $startupScript,
                profileStore: profileStore
            )

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(sanitized(name).isEmpty || isCreating)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            if let wm = WorktreeManager(repoRoot: repo.path) {
                baseBranch = wm.defaultBranch()
            }
        }
    }

    private func create() {
        let cleanName = sanitized(name)
        guard !cleanName.isEmpty else { return }
        guard let wm = WorktreeManager(repoRoot: repo.path) else {
            error = "Not a git repository"
            return
        }
        isCreating = true
        error = nil
        do {
            let path = try wm.createWorktree(
                name: cleanName,
                baseBranch: baseBranch.isEmpty ? wm.defaultBranch() : baseBranch
            )
            let config = WorktreeConfig(
                agentProfileID: agentProfileID,
                startupScript: startupScript.isEmpty ? nil : startupScript
            )
            config.save(at: path.path)
            onCreated()
            dismiss()
        } catch let WorktreeError.createFailed(message) {
            error = message
            isCreating = false
        } catch {
            self.error = error.localizedDescription
            isCreating = false
        }
    }

    private func sanitized(_ raw: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_/.")
        let lowered = raw.lowercased().replacingOccurrences(of: " ", with: "-")
        return String(lowered.unicodeScalars.filter { allowed.contains($0) })
    }
}

private struct ConfigureWorktreeSheet: View {
    let target: RenameTarget
    let profileStore: AgentProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var agentProfileID: UUID?
    @State private var startupScript: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configure \(target.worktree.displayName)")
                .font(.headline)

            WorktreeConfigFields(
                agentProfileID: $agentProfileID,
                startupScript: $startupScript,
                profileStore: profileStore
            )

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            let config = WorktreeConfig.load(at: target.worktree.path)
            agentProfileID = config.agentProfileID
            startupScript = config.startupScript ?? ""
        }
    }

    private func save() {
        let config = WorktreeConfig(
            agentProfileID: agentProfileID,
            startupScript: startupScript.isEmpty ? nil : startupScript
        )
        config.save(at: target.worktree.path)
        dismiss()
    }
}

private struct RenameWorktreeSheet: View {
    let target: RenameTarget
    let onRenamed: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename \(target.worktree.displayName)")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.caption).foregroundStyle(.secondary)
                TextField("name", text: $name)
                    .textFieldStyle(.roundedBorder)
                Text("Branch will be `xyz-\(sanitized(name))`")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") { rename() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(sanitized(name).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear { name = target.worktree.displayName }
    }

    private func rename() {
        let clean = sanitized(name)
        guard !clean.isEmpty else { return }
        guard let wm = WorktreeManager(repoRoot: target.repo.path) else {
            error = "Not a git repository"
            return
        }
        do {
            _ = try wm.renameWorktree(oldBranch: target.worktree.branch, newName: clean)
            onRenamed()
            dismiss()
        } catch let WorktreeError.createFailed(message) {
            error = message
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func sanitized(_ raw: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_/.")
        let lowered = raw.lowercased().replacingOccurrences(of: " ", with: "-")
        return String(lowered.unicodeScalars.filter { allowed.contains($0) })
    }
}

private struct NewTaskListSheet: View {
    let store: TaskStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Task List")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.caption).foregroundStyle(.secondary)
                TextField("Bugs", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    _ = store.addList(name: name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

private struct RenameTaskListSheet: View {
    let store: TaskStore
    let list: TaskList
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Task List")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.caption).foregroundStyle(.secondary)
                TextField("Bugs", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") {
                    store.renameList(id: list.id, name: name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear { name = list.name }
    }
}
