import SwiftUI
import AppKit

struct PluricodeApp: App {
    @State private var repoStore = RepoStore()
    @State private var taskListStore = TaskListStore()
    @State private var workspaceStore: WorkspaceStore
    @State private var pinStore: PinStore
    @State private var sidebarState: SidebarState
    @State private var pluriMonitor: PluriMonitor
    @State private var pluriBackend: LocalPluriBackend
    @State private var pluriServer: PluriServer
    @State private var notch: NotchController
    @AppStorage("notchEnabled") private var notchEnabled = true
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showPalette = false
    @State private var creatingWorkspace = false
    @State private var pendingConfirmation: ConfirmationPrompt?
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppearanceMode.system.rawValue

    init() {
        let repos = RepoStore()
        let lists = TaskListStore()
        let sidebar = SidebarState()
        let store = WorkspaceStore(repoStore: repos, taskListStore: lists)
        let pins = PinStore()
        _repoStore = State(initialValue: repos)
        _taskListStore = State(initialValue: lists)
        _sidebarState = State(initialValue: sidebar)
        _workspaceStore = State(initialValue: store)
        _pinStore = State(initialValue: pins)
        let registry = PluriTaskRegistry()
        let session = PluriSession(repoStore: repos)
        let bridge = PluriBridge(
            repoStore: repos,
            workspaceStore: store,
            sidebarState: sidebar,
            pinStore: pins,
            registry: registry
        )
        let backend = LocalPluriBackend(session: session, bridge: bridge, registry: registry)
        let monitor = PluriMonitor(registry: registry, session: session)
        _pluriMonitor = State(initialValue: monitor)
        _pluriBackend = State(initialValue: backend)
        _pluriServer = State(initialValue: PluriServer(backend: backend))
        _notch = State(initialValue: NotchController(store: store, monitor: monitor))
        bridge.start()
        monitor.start()
    }

    var body: some Scene {
        WindowGroup {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                RepoSidebarView(
                    repoStore: repoStore,
                    taskListStore: taskListStore,
                    workspaceStore: workspaceStore,
                    pinStore: pinStore,
                    sidebarState: sidebarState
                )
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
            } detail: {
                if let workspace = workspaceStore.selectedWorkspace {
                    WorkspaceView(workspace: workspace)
                        .id(workspace.id)
                } else {
                    EmptyDetailView(workspaceStore: workspaceStore, hasRepos: !repoStore.repos.isEmpty)
                }
            }
            .toolbar {
                ToolbarItem {
                    PluriToolbarButton()
                }
                ToolbarItemGroup {
                    Picker("Appearance", selection: $appearanceModeRaw) {
                        ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                            Label(mode.rawValue.capitalized, systemImage: mode.icon)
                                .tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.menu)

                    Button {
                        showPalette = true
                    } label: {
                        Image(systemName: "command")
                    }
                    .help("Command Palette (⌘K)")
                }
            }
            .navigationTitle(workspaceStore.selectedWorkspace?.name ?? "Pluricode")
            .onAppear {
                (AppearanceMode(rawValue: appearanceModeRaw) ?? .system).apply()
                notch.install(enabled: notchEnabled)
            }
            .onChange(of: appearanceModeRaw) { _, newValue in
                (AppearanceMode(rawValue: newValue) ?? .system).apply()
            }
            .onChange(of: notchEnabled) { _, enabled in
                notch.apply(enabled: enabled)
            }
            .sheet(isPresented: $showPalette) {
                CommandPaletteView(
                    isPresented: $showPalette,
                    columnVisibility: $columnVisibility,
                    workspaceStore: workspaceStore,
                    repoStore: repoStore,
                    sidebarState: sidebarState,
                    onCreateWorkspace: { creatingWorkspace = true },
                    onMergedDeletionFound: { matches in
                        pendingConfirmation = mergedDeletionPrompt(matches)
                    }
                )
            }
            .sheet(isPresented: $creatingWorkspace) {
                NewWorkspaceSheet(workspaceStore: workspaceStore)
            }
            .confirmation($pendingConfirmation)
            .environment(pluriMonitor)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton()
            }
            CommandMenu("Pane") {
                PaneCommands()
            }
            CommandGroup(after: .toolbar) {
                Button("Command Palette") { showPalette = true }
                    .keyboardShortcut("k", modifiers: .command)
            }
        }

        Window("Pluri", id: "pluri") {
            PluriChatView(backend: pluriBackend)
        }
        .defaultSize(width: 460, height: 640)

        Settings {
            TabView {
                PermissionsView()
                    .tabItem { Label("Permissions", systemImage: "lock.shield") }
                TerminalSettingsView()
                    .tabItem { Label("Terminal", systemImage: "terminal") }
                PluriSettingsView()
                    .tabItem { Label("Pluri", systemImage: "sparkles") }
                PluriServerSettingsView(server: pluriServer)
                    .tabItem { Label("Mobile", systemImage: "iphone") }
                UpdatesSettingsView()
                    .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
            }
        }
    }

    private func mergedDeletionPrompt(_ matches: [MergedWorktreeMatch]) -> ConfirmationPrompt {
        if matches.isEmpty {
            return .info(
                title: "No Merged Worktrees",
                message: "All worktrees still have open or unmerged PRs."
            )
        }
        let names = matches.map(\.branch).joined(separator: ", ")
        let count = matches.count
        return .destructive(
            title: "Delete \(count) merged worktree\(count == 1 ? "" : "s")?",
            message: "Removes worktrees and deletes their branches:\n\(names)"
        ) {
            runMergedDeletion(matches)
        }
    }

    private func runMergedDeletion(_ matches: [MergedWorktreeMatch]) {
        Task {
            var affectedRepos: Set<UUID> = []
            for match in matches {
                guard let repo = repoStore.repos.first(where: { $0.id == match.repoID }) else { continue }
                let worktree = Worktree(branch: match.branch, path: match.path, head: "", isPrimary: false)
                await workspaceStore.deleteWorktree(repo: repo, worktree: worktree, pinStore: pinStore)
                affectedRepos.insert(repo.id)
            }
            for id in affectedRepos {
                if let repo = repoStore.repos.first(where: { $0.id == id }) {
                    sidebarState.refresh(repo)
                }
            }
        }
    }
}

struct PluriToolbarButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openWindow(id: "pluri")
        } label: {
            PluriMascotView()
        }
        .help("Pluri — describe what you want to work on")
    }
}

struct PaneCommands: View {
    @FocusedValue(\.workspace) var workspace

    var body: some View {
        Button("Close Tab") {
            workspace?.closeFocusedTab()
        }
        .keyboardShortcut("w", modifiers: .command)
        .disabled(workspace?.focusedPaneID == nil)

        Button("Split Right") {
            workspace?.splitFocusedPane(direction: .horizontal)
        }
        .keyboardShortcut("d", modifiers: .command)
        .disabled(workspace?.focusedPaneID == nil)

        Button("Split Down") {
            workspace?.splitFocusedPane(direction: .vertical)
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])
        .disabled(workspace?.focusedPaneID == nil)

        Divider()

        Button("Run Dev") {
            workspace?.runDevScriptOnFocusedPane()
        }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(workspace?.focusedDevScript == nil)

        Button("Next Tab") {
            workspace?.cycleFocusedTab(by: 1)
        }
        .keyboardShortcut("]", modifiers: .command)
        .disabled((workspace?.focusedPaneTabCount ?? 0) < 2)

        Button("Previous Tab") {
            workspace?.cycleFocusedTab(by: -1)
        }
        .keyboardShortcut("[", modifiers: .command)
        .disabled((workspace?.focusedPaneTabCount ?? 0) < 2)

        Divider()

        ForEach(1...9, id: \.self) { n in
            Button("Focus Pane \(n)") {
                workspace?.focusPane(atIndex: n - 1)
            }
            .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
            .disabled((workspace?.terminalPanes.count ?? 0) < n)
        }
    }
}

struct EmptyDetailView: View {
    let workspaceStore: WorkspaceStore
    let hasRepos: Bool
    @State private var creating = false
    @State private var draftName = ""

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No workspace selected")
                .font(.title2)
            Text(hasRepos
                ? "Create a workspace to start arranging panes."
                : "Add a repository in the sidebar, then create a workspace.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("New Workspace...") { creating = true }
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $creating) {
            VStack(alignment: .leading, spacing: 16) {
                Text("New Workspace").font(.headline)
                TextField("Bug Fixes", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { creating = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Create") {
                        _ = workspaceStore.createWorkspace(name: draftName)
                        draftName = ""
                        creating = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(24)
            .frame(width: 360)
        }
    }
}
