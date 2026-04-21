import SwiftUI
import AppKit

struct XyzterminalApp: App {
    @State private var repoStore = RepoStore()
    @State private var profileStore = AgentProfileStore()
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppearanceMode.system.rawValue

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                RepoSidebarView(repoStore: repoStore, profileStore: profileStore)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
            } detail: {
                if let repo = repoStore.selectedRepo {
                    WorkspaceView(repo: repo, profileStore: profileStore)
                        .id(repo.id)
                } else {
                    EmptyWorkspaceView(repoStore: repoStore)
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
            }
            .onChange(of: appearanceModeRaw) { _, newValue in
                (AppearanceMode(rawValue: newValue) ?? .system).apply()
            }
        }
        .defaultSize(width: 1200, height: 800)
    }
}

struct EmptyWorkspaceView: View {
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
