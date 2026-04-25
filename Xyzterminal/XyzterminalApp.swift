import SwiftUI
import AppKit

struct XyzterminalApp: App {
    @State private var repoStore = RepoStore()
    @State private var profileStore = AgentProfileStore()
    @State private var taskListStore = TaskListStore()
    @State private var workspaceStore: WorkspaceStore
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppearanceMode.system.rawValue

    init() {
        let repos = RepoStore()
        let lists = TaskListStore()
        let profiles = AgentProfileStore()
        _repoStore = State(initialValue: repos)
        _taskListStore = State(initialValue: lists)
        _profileStore = State(initialValue: profiles)
        _workspaceStore = State(initialValue: WorkspaceStore(
            repoStore: repos,
            taskListStore: lists,
            profileStore: profiles
        ))
    }

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                RepoSidebarView(
                    repoStore: repoStore,
                    profileStore: profileStore,
                    taskListStore: taskListStore,
                    workspaceStore: workspaceStore
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
                PaneCreationToolbar(
                    workspace: workspaceStore.selectedWorkspace,
                    profileStore: profileStore
                )
                ToolbarItemGroup {
                    Picker("Appearance", selection: $appearanceModeRaw) {
                        ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                            Label(mode.rawValue.capitalized, systemImage: mode.icon)
                                .tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .navigationTitle(workspaceStore.selectedWorkspace?.name ?? "Xyzterminal")
            .onAppear {
                (AppearanceMode(rawValue: appearanceModeRaw) ?? .system).apply()
            }
            .onChange(of: appearanceModeRaw) { _, newValue in
                (AppearanceMode(rawValue: newValue) ?? .system).apply()
            }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandMenu("Pane") {
                PaneCommands()
            }
        }
    }
}

struct PaneCommands: View {
    @FocusedValue(\.workspace) var workspace

    var body: some View {
        Button("Close Pane") {
            workspace?.closeFocusedPane()
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
