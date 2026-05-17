import SwiftUI
import AppKit

struct LocalHostsWidgetView: View {
    let paneID: UUID
    let tabID: UUID
    let workspace: Workspace
    let onActivate: () -> Void
    let onClose: () -> Void

    private var entries: [LocalHostEntry] {
        guard let store = workspace.store else { return [] }
        return store.localHostRegistry.entries
            .sorted { $0.discoveredAt > $1.discoveredAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            LocalHostsHeader(
                paneID: paneID,
                count: entries.count,
                onActivate: onActivate,
                onClose: onClose
            )
            if entries.isEmpty {
                EmptyLocalHostsBody()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(entries) { entry in
                            LocalHostRow(entry: entry, workspace: workspace)
                            Divider().opacity(0.3)
                        }
                    }
                }
            }
        }
    }
}

private struct LocalHostsHeader: View {
    let paneID: UUID
    let count: Int
    let onActivate: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: WidgetKind.localHosts.systemImage)
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(WidgetKind.localHosts.label)
                .font(.system(size: 12, weight: .medium))
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
        .draggable(TilingDragPayload(kind: .movePane(paneID: paneID))) {
            HStack(spacing: 6) {
                Image(systemName: WidgetKind.localHosts.systemImage)
                Text(WidgetKind.localHosts.label)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

private struct EmptyLocalHostsBody: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "network.slash")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No local hosts detected")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Start a dev server in any pane.\nURLs like http://localhost:3000 will appear here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
    }
}

private struct LocalHostRow: View {
    let entry: LocalHostEntry
    let workspace: Workspace
    @State private var hovering = false

    private var repo: RepoEntry? {
        workspace.store?.repos.first { $0.id == entry.repoID }
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Circle()
                    .fill(repo?.resolvedColor.swiftUIColor ?? .accentColor)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayURL)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        if let repo {
                            Text(repo.name)
                        }
                        Text("·").foregroundStyle(.secondary.opacity(0.6))
                        Text(entry.branch)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if hovering {
                    Button(action: focusPane) {
                        Image(systemName: "arrow.right.square")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Focus the originating pane")

                    Button(action: copyURL) {
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Copy URL")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(hovering ? Color.secondary.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open in Browser", action: open)
            Button("Copy URL", action: copyURL)
            Divider()
            Button("Focus Originating Pane", action: focusPane)
        }
    }

    private var displayURL: String {
        var s = entry.url.absoluteString
        if s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private func open() {
        NSWorkspace.shared.open(entry.url)
    }

    private func copyURL() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(entry.url.absoluteString, forType: .string)
    }

    private func focusPane() {
        guard let store = workspace.store else { return }
        if store.selectedWorkspaceID != entry.workspaceID {
            store.selectedWorkspaceID = entry.workspaceID
            store.saveSelection()
        }
        guard let target = store.workspaces.first(where: { $0.id == entry.workspaceID }) else { return }
        if let pane = target.tiling.panes.first(where: { p in p.tabs.contains { $0.id == entry.tabID } }) {
            target.setActiveTab(paneID: pane.id, tabID: entry.tabID)
            target.setFocus(paneID: pane.id)
            target.terminalHosts[entry.tabID]?.focusInput()
        }
    }
}
