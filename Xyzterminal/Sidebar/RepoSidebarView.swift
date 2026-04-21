import SwiftUI

struct RepoSidebarView: View {
    let repoStore: RepoStore
    let profileStore: AgentProfileStore
    @State private var expanded: Set<UUID> = []
    @State private var worktrees: [UUID: [Worktree]] = [:]
    @State private var newWorktreeRepo: RepoEntry?
    @State private var deleteCandidate: DeleteCandidate?
    @State private var renameTarget: RenameTarget?
    @State private var configureTarget: RenameTarget?

    var body: some View {
        List(selection: Binding(
            get: { repoStore.selectedRepoID },
            set: { repoStore.selectedRepoID = $0; repoStore.save() }
        )) {
            Section("Repositories") {
                ForEach(repoStore.repos) { repo in
                    repoSection(repo)
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
        .sheet(item: $newWorktreeRepo) { repo in
            NewWorktreeSheet(repo: repo, profileStore: profileStore) { refresh(repo) }
        }
        .sheet(item: $renameTarget) { target in
            RenameWorktreeSheet(target: target) { refresh(target.repo) }
        }
        .sheet(item: $configureTarget) { target in
            ConfigureWorktreeSheet(target: target, profileStore: profileStore)
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
    }

    @ViewBuilder
    private func repoSection(_ repo: RepoEntry) -> some View {
        RepoRow(repo: repo, isExpanded: expanded.contains(repo.id), toggle: { toggle(repo) })
            .tag(repo.id)
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
            let list = worktrees[repo.id] ?? []
            ForEach(list) { wt in
                WorktreeRow(worktree: wt, profileStore: profileStore)
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
        .draggable(TilingDragPayload(kind: .newTerminal(worktreeID: worktree.branch))) {
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
