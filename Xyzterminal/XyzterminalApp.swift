import SwiftUI
import AppKit

struct XyzterminalApp: App {
    @State private var repoStore = RepoStore()
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppearanceMode.system.rawValue

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                RepoSidebarView(repoStore: repoStore)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
            } detail: {
                if let repo = repoStore.selectedRepo {
                    CanvasHostView(repoEntry: repo)
                        .id(repo.id)
                } else {
                    EmptyCanvasView(repoStore: repoStore)
                }
            }
            .toolbar {
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
            .onAppear {
                (AppearanceMode(rawValue: appearanceModeRaw) ?? .system).apply()
                migrateLastProjectPath()
            }
            .onChange(of: appearanceModeRaw) { _, newValue in
                (AppearanceMode(rawValue: newValue) ?? .system).apply()
            }
        }
        .defaultSize(width: 1200, height: 800)
    }

    private func migrateLastProjectPath() {
        guard repoStore.repos.isEmpty,
              let last = Persistence.lastProjectPath,
              FileManager.default.fileExists(atPath: last.path) else { return }
        repoStore.addRepo(last)
        UserDefaults.standard.removeObject(forKey: "lastProjectPath")
    }
}

struct CanvasHostView: View {
    let repoEntry: RepoEntry
    @State private var document = CanvasDocument()

    var body: some View {
        CanvasContainerView(document: document)
            .toolbar {
                ToolbarItemGroup {
                    Button(action: {
                        let id = document.addNode(kind: .taskCard(TaskCardData(title: "")))
                        document.onStartInlineEdit?(id)
                    }) {
                        Label("Task Card", systemImage: "square.text.square")
                    }
                    Button(action: { document.addNode(kind: .section(SectionData())) }) {
                        Label("Section", systemImage: "rectangle.3.group")
                    }
                    Button(action: { document.showTerminalConfig = true }) {
                        Label("Terminal", systemImage: "terminal")
                    }
                    Divider()
                    Toggle(isOn: Binding(
                        get: { document.snapToGrid },
                        set: { document.snapToGrid = $0 }
                    )) {
                        Label("Snap", systemImage: "grid")
                    }
                }
            }
            .onAppear { openProject(repoEntry.path) }
    }

    private func openProject(_ url: URL) {
        document.projectPath = url
        Persistence.load(into: document)

        let server = MCPServer(document: document)
        server.start()
        document.mcpServer = server
    }
}

struct EmptyCanvasView: View {
    let repoStore: RepoStore

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No repository selected")
                .font(.title2)
            Text("Add a git repository from the sidebar")
                .foregroundStyle(.secondary)
            Button("Add Repository...") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                panel.message = "Select a git repository"
                if panel.runModal() == .OK, let url = panel.url {
                    repoStore.addRepo(url)
                }
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
