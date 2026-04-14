import SwiftUI

struct RepoSidebarView: View {
    let repoStore: RepoStore

    var body: some View {
        List(selection: Binding(
            get: { repoStore.selectedRepoID },
            set: { repoStore.selectedRepoID = $0; repoStore.save() }
        )) {
            Section("Repositories") {
                ForEach(repoStore.repos) { repo in
                    RepoRow(repo: repo)
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

struct RepoRow: View {
    let repo: RepoEntry

    private var pathExists: Bool {
        FileManager.default.fileExists(atPath: repo.path.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Label(repo.name, systemImage: "folder.fill")
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
        .padding(.vertical, 2)
    }
}
