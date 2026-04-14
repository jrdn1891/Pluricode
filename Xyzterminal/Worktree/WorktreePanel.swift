import SwiftUI

struct WorktreePanel: View {
    let document: CanvasDocument
    @State private var entries: [WorktreeEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Worktrees")
                    .font(.headline)
                Spacer()
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if entries.isEmpty {
                Text("No active worktrees")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries) { entry in
                    WorktreeRow(entry: entry)
                }
                .listStyle(.sidebar)
            }
        }
        .frame(width: 260)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        let nodes = document.nodes
        let wm = document.mcpServer?.terminalManager?.worktreeManager

        Task.detached {
            var result: [WorktreeEntry] = []
            for (id, node) in nodes {
                guard case .terminal(let data) = node.kind,
                      let path = data.worktreePath else { continue }
                let uncommitted = wm?.uncommittedCount(at: URL(fileURLWithPath: path)) ?? 0
                result.append(WorktreeEntry(
                    nodeID: id,
                    branch: data.branchName ?? "unknown",
                    path: path,
                    status: data.status,
                    uncommittedCount: uncommitted
                ))
            }
            let sorted = result.sorted { $0.branch < $1.branch }
            await MainActor.run { entries = sorted }
        }
    }
}

struct WorktreeEntry: Identifiable {
    var id: UUID { nodeID }
    let nodeID: UUID
    let branch: String
    let path: String
    let status: TerminalNodeData.Status
    let uncommittedCount: Int
}

struct WorktreeRow: View {
    let entry: WorktreeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(entry.status.color)
                    .frame(width: 8, height: 8)
                Text(entry.branch)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
            }
            HStack(spacing: 12) {
                Text(entry.status.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if entry.uncommittedCount > 0 {
                    Text("\(entry.uncommittedCount) uncommitted")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            HStack(spacing: 8) {
                Button("VS Code") { openIn(editor: "code", path: entry.path) }
                Button("Zed") { openIn(editor: "zed", path: entry.path) }
                Button("Xcode") { openIn(editor: "xed", path: entry.path) }
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private func openIn(editor: String, path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [editor, path]
        try? process.run()
    }
}
