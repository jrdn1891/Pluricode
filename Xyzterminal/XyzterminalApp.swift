import SwiftUI
import AppKit

struct XyzterminalApp: App {
    @State private var document = CanvasDocument()
    @State private var hasProject = false
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppearanceMode.system.rawValue

    var body: some Scene {
        WindowGroup {
            Group {
                if hasProject {
                    CanvasContainerView(document: document)
                        .toolbar {
                            ToolbarItemGroup {
                                Button(action: { document.addNode(kind: .taskCard(TaskCardData())) }) {
                                    Label("Task Card", systemImage: "square.text.square")
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
                                Divider()
                                Picker("Appearance", selection: $appearanceModeRaw) {
                                    ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                                        Label(mode.rawValue.capitalized, systemImage: mode.icon)
                                            .tag(mode.rawValue)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                } else {
                    ProjectPickerView(onPick: { url in
                        openProject(url)
                    })
                }
            }
            .onAppear {
                (AppearanceMode(rawValue: appearanceModeRaw) ?? .system).apply()
                if let last = Persistence.lastProjectPath,
                   FileManager.default.fileExists(atPath: last.path) {
                    openProject(last)
                }
            }
            .onChange(of: appearanceModeRaw) { _, newValue in
                (AppearanceMode(rawValue: newValue) ?? .system).apply()
            }
        }
        .defaultSize(width: 1200, height: 800)
    }

    private func openProject(_ url: URL) {
        document.projectPath = url
        Persistence.lastProjectPath = url
        Persistence.load(into: document)

        let server = MCPServer(document: document)
        server.start()
        document.mcpServer = server

        hasProject = true
    }
}

struct ProjectPickerView: View {
    let onPick: (URL) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Open a project directory")
                .font(.title2)
            Text("Choose a git repository to use as your workspace")
                .foregroundStyle(.secondary)
            Button("Choose Folder...") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                panel.message = "Select a git repository"
                if panel.runModal() == .OK, let url = panel.url {
                    onPick(url)
                }
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
