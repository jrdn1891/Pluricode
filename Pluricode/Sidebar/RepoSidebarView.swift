import SwiftUI

struct RepoSidebarView: View {
    let repoStore: RepoStore
    let profileStore: AgentProfileStore
    let taskListStore: TaskListStore
    let workspaceStore: WorkspaceStore
    @State private var expanded: Set<UUID> = []
    @State private var worktrees: [UUID: [Worktree]] = [:]
    @State private var newWorktreeRepo: RepoEntry?
    @State private var renameTarget: RenameTarget?
    @State private var configureTarget: RenameTarget?
    @State private var configureRepo: RepoEntry?
    @State private var creatingList = false
    @State private var renameListTarget: TaskList?
    @State private var creatingWorkspace = false
    @State private var renameWorkspaceTarget: Workspace?
    @State private var pendingDelete: PendingDelete?
    @State private var selectedWorktrees: Set<WorktreeKey> = []
    @State private var worktreeAnchor: WorktreeKey?

    var body: some View {
        List(selection: Binding(
            get: { workspaceStore.selectedWorkspaceID },
            set: { newValue in
                guard let newValue else { return }
                workspaceStore.selectedWorkspaceID = newValue
                workspaceStore.saveSelection()
            }
        )) {
            Section {
                ForEach(workspaceStore.workspaces, id: \.id) { ws in
                    WorkspaceRow(workspace: ws)
                        .tag(ws.id)
                        .contextMenu {
                            Button("Rename...") { renameWorkspaceTarget = ws }
                            Divider()
                            Button("Delete", role: .destructive) { pendingDelete = .workspace(ws) }
                        }
                }
            } header: {
                SidebarSectionHeader(title: "Workspaces") { creatingWorkspace = true }
            }

            Section {
                ForEach(taskListStore.lists) { list in
                    TaskListRow(list: list)
                        .contextMenu {
                            Button("Rename...") { renameListTarget = list }
                            Divider()
                            Button("Delete", role: .destructive) { pendingDelete = .taskList(list) }
                        }
                }
            } header: {
                SidebarSectionHeader(title: "Task Lists") { creatingList = true }
            }
            .selectionDisabled()

            Section("Widgets") {
                StatsWidgetRow()
            }
            .selectionDisabled()

            Section("Repositories") {
                ForEach(repoStore.repos) { repo in
                    RepoRow(
                        repo: repo,
                        isExpanded: expanded.contains(repo.id),
                        toggle: { toggle(repo) },
                        onSetColor: { repoStore.setColor(id: repo.id, color: $0) },
                        onNewWorktree: { newWorktreeRepo = repo },
                        onConfigure: { configureRepo = repo },
                        onShowInFinder: {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: repo.path.path)
                        },
                        onRemove: { repoStore.removeRepo(id: repo.id) }
                    )

                    if expanded.contains(repo.id) {
                        ForEach(worktrees[repo.id] ?? []) { wt in
                            WorktreeRow(
                                repoID: repo.id,
                                worktree: wt,
                                profileStore: profileStore,
                                workspaceStore: workspaceStore,
                                isSelected: selectedWorktrees.contains(WorktreeKey(repoID: repo.id, branch: wt.branch)),
                                onSelect: { flags in
                                    selectWorktree(WorktreeKey(repoID: repo.id, branch: wt.branch), flags: flags)
                                }
                            )
                                .padding(.leading, 20)
                                .contextMenu {
                                    if wt.isPrimary {
                                        Button("Show in Finder") {
                                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: wt.path)
                                        }
                                    } else {
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
                                            pendingDelete = .worktree(repo: repo, worktree: wt)
                                        }
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
            }
            .selectionDisabled()
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
            NewWorktreeSheet(repo: repo, profileStore: profileStore) { _ in refresh(repo) }
        }
        .sheet(item: $renameTarget) { target in
            RenameWorktreeSheet(target: target) { refresh(target.repo) }
        }
        .sheet(item: $configureTarget) { target in
            ConfigureWorktreeSheet(target: target, profileStore: profileStore)
        }
        .sheet(item: $configureRepo) { repo in
            ConfigureRepoSheet(repo: repo)
        }
        .sheet(isPresented: $creatingList) {
            NewTaskListSheet(store: taskListStore)
        }
        .sheet(item: $renameListTarget) { list in
            RenameTaskListSheet(store: taskListStore, list: list)
        }
        .alert(item: $pendingDelete) { item in
            switch item {
            case .worktree(let repo, let wt):
                return Alert(
                    title: Text("Delete \(wt.displayName)?"),
                    message: Text("This runs `git worktree remove --force` and deletes the branch `\(wt.branch)`."),
                    primaryButton: .destructive(Text("Delete")) {
                        deleteWorktree(repo: repo, worktree: wt)
                    },
                    secondaryButton: .cancel()
                )
            case .taskList(let list):
                return Alert(
                    title: Text("Delete list \(list.name)?"),
                    message: Text(list.items.isEmpty
                        ? "The list is empty. This cannot be undone."
                        : "This will delete \(list.items.count) task\(list.items.count == 1 ? "" : "s")."),
                    primaryButton: .destructive(Text("Delete")) {
                        taskListStore.removeList(id: list.id)
                    },
                    secondaryButton: .cancel()
                )
            case .workspace(let ws):
                return Alert(
                    title: Text("Delete workspace \(ws.name)?"),
                    message: Text("Panes are removed from the canvas. Worktrees and task lists are untouched."),
                    primaryButton: .destructive(Text("Delete")) {
                        workspaceStore.removeWorkspace(id: ws.id)
                    },
                    secondaryButton: .cancel()
                )
            }
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

    private func selectWorktree(_ key: WorktreeKey, flags: NSEvent.ModifierFlags) {
        if flags.contains(.shift), let anchor = worktreeAnchor {
            let order = flattenedWorktreeKeys()
            if let a = order.firstIndex(of: anchor), let b = order.firstIndex(of: key) {
                let range = a <= b ? order[a...b] : order[b...a]
                selectedWorktrees = Set(range)
                return
            }
        }
        if flags.contains(.command) {
            if selectedWorktrees.contains(key) {
                selectedWorktrees.remove(key)
            } else {
                selectedWorktrees.insert(key)
            }
        } else {
            selectedWorktrees = [key]
        }
        worktreeAnchor = key
    }

    private func flattenedWorktreeKeys() -> [WorktreeKey] {
        var result: [WorktreeKey] = []
        for repo in repoStore.repos where expanded.contains(repo.id) {
            for wt in worktrees[repo.id] ?? [] {
                result.append(WorktreeKey(repoID: repo.id, branch: wt.branch))
            }
        }
        return result
    }

    private func refresh(_ repo: RepoEntry) {
        guard let wm = WorktreeManager(repoRoot: repo.path) else {
            worktrees[repo.id] = []
            return
        }
        worktrees[repo.id] = wm.listManagedWorktrees()
    }

    private func deleteWorktree(repo: RepoEntry, worktree: Worktree) {
        guard let wm = WorktreeManager(repoRoot: repo.path) else { return }
        let url = URL(fileURLWithPath: worktree.path)
        workspaceStore.removePanes(repoID: repo.id, worktreeID: worktree.branch)
        try? wm.removeWorktree(at: url)
        _ = try? Process.run(
            URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["-C", repo.path.path, "branch", "-D", worktree.branch]
        )
        refresh(repo)
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

private struct ColorMenuLabel: View {
    let title: String
    let swatch: Color
    let dashed: Bool
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: Self.swatchImage(color: swatch, dashed: dashed))
            Text(title)
            if selected {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }

    private static func swatchImage(color: Color, dashed: Bool) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let img = NSImage(size: size)
        img.lockFocus()
        let rect = NSRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(ovalIn: rect)
        if dashed {
            NSColor(color).setStroke()
            path.lineWidth = 1.2
            path.setLineDash([2.0, 1.5], count: 2, phase: 0)
            path.stroke()
        } else {
            NSColor(color).setFill()
            path.fill()
        }
        img.unlockFocus()
        img.isTemplate = false
        return img
    }
}

private struct SidebarSectionHeader: View {
    let title: String
    let onAdd: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Spacer()
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(hovered ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}

private struct ColorPickerPopover: View {
    let current: RepoColor?
    let resolved: RepoColor
    let onSelect: (RepoColor?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ColorPickerRow(
                title: "Automatic",
                swatch: resolved.swiftUIColor,
                dashed: true,
                selected: current == nil
            ) { onSelect(nil) }
            Divider().padding(.vertical, 4)
            ForEach(RepoColor.allCases, id: \.self) { c in
                ColorPickerRow(
                    title: c.label,
                    swatch: c.swiftUIColor,
                    dashed: false,
                    selected: current == c
                ) { onSelect(c) }
            }
        }
        .padding(6)
        .frame(width: 160)
    }
}

private struct ColorPickerRow: View {
    let title: String
    let swatch: Color
    let dashed: Bool
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Group {
                    if dashed {
                        Circle()
                            .strokeBorder(swatch, style: StrokeStyle(lineWidth: 1.2, dash: [2, 1.5]))
                    } else {
                        Circle().fill(swatch)
                    }
                }
                .frame(width: 10, height: 10)
                Text(title)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(hovered ? Color.accentColor.opacity(0.25) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private enum PendingDelete: Identifiable {
    case worktree(repo: RepoEntry, worktree: Worktree)
    case taskList(TaskList)
    case workspace(Workspace)

    var id: String {
        switch self {
        case .worktree(let repo, let wt): return "wt:\(repo.id.uuidString):\(wt.id)"
        case .taskList(let list): return "tl:\(list.id)"
        case .workspace(let ws): return "ws:\(ws.id)"
        }
    }
}

private struct RenameTarget: Identifiable {
    let repo: RepoEntry
    let worktree: Worktree
    var id: String { "\(repo.id.uuidString):\(worktree.id)" }
}

struct WorktreeKey: Hashable {
    let repoID: UUID
    let branch: String
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
    let onSetColor: (RepoColor?) -> Void
    let onNewWorktree: () -> Void
    let onConfigure: () -> Void
    let onShowInFinder: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false
    @State private var showColorPicker = false

    private var pathExists: Bool {
        FileManager.default.fileExists(atPath: repo.path.path)
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                showColorPicker = true
            } label: {
                Circle()
                    .fill(repo.resolvedColor.swiftUIColor)
                    .frame(width: 10, height: 10)
                    .padding(2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Change color")
            .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
                ColorPickerPopover(
                    current: repo.color,
                    resolved: repo.resolvedColor
                ) { color in
                    onSetColor(color)
                    showColorPicker = false
                }
            }

            Text(repo.name)
                .font(.body)

            if !pathExists {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.yellow)
                    .font(.caption)
            }

            Spacer(minLength: 4)

            if isHovered {
                Menu {
                    Button("Configure...", action: onConfigure)
                    Button("Show in Finder", action: onShowInFinder)
                    Divider()
                    Button("Remove", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                        .frame(width: 14)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .tint(.secondary)

                Button(action: onNewWorktree) {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
                .help("New Worktree")
            }

            Button(action: toggle) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

struct WorktreeRow: View {
    let repoID: UUID
    let worktree: Worktree
    let profileStore: AgentProfileStore
    let workspaceStore: WorkspaceStore
    let isSelected: Bool
    let onSelect: (NSEvent.ModifierFlags) -> Void
    @State private var stats: DiffStats = .zero
    @State private var isMerged: Bool = false
    @State private var isHovered = false

    private var assignedProfile: AgentProfile? {
        let config = WorktreeConfig.load(at: worktree.path)
        guard let id = config.agentProfileID else { return nil }
        return profileStore.profile(id: id)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isMerged ? "arrow.trianglehead.merge" : "arrow.triangle.branch")
                .foregroundStyle(isMerged ? Color.green : Color.secondary)
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
            if !isMerged && !stats.isClean {
                HStack(spacing: 4) {
                    if stats.additions > 0 {
                        Text("+\(stats.additions)")
                            .foregroundStyle(.green)
                    }
                    if stats.deletions > 0 {
                        Text("-\(stats.deletions)")
                            .foregroundStyle(.red)
                    }
                }
                .font(.caption.monospacedDigit())
            }
            if isHovered, let ws = workspaceStore.selectedWorkspace {
                Button {
                    ws.addPane(.terminal(repoID: repoID, worktreeID: worktree.branch))
                } label: {
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Add to \(ws.name)")
            }
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            onSelect(NSEvent.modifierFlags)
        }
        .task(id: worktree.path) {
            let path = URL(fileURLWithPath: worktree.path)
            while !Task.isCancelled {
                let next = await Task.detached { WorktreeManager.diffStats(at: path) }.value
                if next != stats { stats = next }
                try? await Task.sleep(for: .seconds(3))
            }
        }
        .task(id: worktree.path) {
            guard !worktree.isPrimary else { return }
            let path = URL(fileURLWithPath: worktree.path)
            while !Task.isCancelled {
                let next = await Task.detached { WorktreeManager.isMerged(at: path) }.value
                if next != isMerged { isMerged = next }
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .onDrag({
            let payload = TilingDragPayload(kind: .newTerminal(repoID: repoID, worktreeID: worktree.branch))
            let data = (try? JSONEncoder().encode(payload)) ?? Data()
            let string = String(data: data, encoding: .utf8) ?? ""
            return NSItemProvider(object: string as NSString)
        }, preview: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                Text(worktree.displayName)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        })
    }
}

struct StatsWidgetRow: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text("Today's Stats")
                .font(.body)
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 1)
        .onDrag({
            let payload = TilingDragPayload(kind: .newStats)
            let data = (try? JSONEncoder().encode(payload)) ?? Data()
            let string = String(data: data, encoding: .utf8) ?? ""
            return NSItemProvider(object: string as NSString)
        }, preview: {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar")
                Text("Today's Stats")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        })
    }
}

struct TaskListRow: View {
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
        .onDrag({
            let payload = TilingDragPayload(kind: .newTaskPane(listID: list.id))
            let data = (try? JSONEncoder().encode(payload)) ?? Data()
            let string = String(data: data, encoding: .utf8) ?? ""
            return NSItemProvider(object: string as NSString)
        }, preview: {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                Text(list.name)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        })
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
    let profileStore: AgentProfileStore

    var body: some View {
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
    }
}

struct NewWorktreeSheet: View {
    let repo: RepoEntry
    let profileStore: AgentProfileStore
    let onCreated: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var baseBranch: String = ""
    @State private var agentProfileID: UUID?
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
                Text("Branch will be `pluri-\(sanitized(name))`")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Base Branch").font(.caption).foregroundStyle(.secondary)
                TextField("origin/main", text: $baseBranch)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            WorktreeConfigFields(
                agentProfileID: $agentProfileID,
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
                baseBranch = wm.defaultBaseRef()
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
                baseBranch: baseBranch.isEmpty ? wm.defaultBaseRef() : baseBranch
            )
            let config = WorktreeConfig(agentProfileID: agentProfileID)
            config.save(at: path.path)
            onCreated("pluri-\(cleanName)")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configure \(target.worktree.displayName)")
                .font(.headline)

            WorktreeConfigFields(
                agentProfileID: $agentProfileID,
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
            agentProfileID = WorktreeConfig.load(at: target.worktree.path).agentProfileID
        }
    }

    private func save() {
        WorktreeConfig(agentProfileID: agentProfileID).save(at: target.worktree.path)
        dismiss()
    }
}

private struct ConfigureRepoSheet: View {
    let repo: RepoEntry
    @Environment(\.dismiss) private var dismiss
    @State private var startupScript: String = ""
    @State private var devScript: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configure \(repo.name)")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Startup Script").font(.caption).foregroundStyle(.secondary)
                TextField("claude --dangerously-skip-permissions", text: $startupScript, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...5)
                Text("Runs in every worktree's shell after it opens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Dev Script").font(.caption).foregroundStyle(.secondary)
                TextField("npm run dev", text: $devScript, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...5)
                Text("Runs in the focused pane on ⌘R or via the ▶ button.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
            let config = RepoConfig.load(at: repo.path.path)
            startupScript = config.startupScript ?? ""
            devScript = config.devScript ?? ""
        }
    }

    private func save() {
        RepoConfig(
            startupScript: startupScript.isEmpty ? nil : startupScript,
            devScript: devScript.isEmpty ? nil : devScript
        )
        .save(at: repo.path.path)
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
                Text("Branch will be `pluri-\(sanitized(name))`")
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
    let store: TaskListStore
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
    let store: TaskListStore
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
