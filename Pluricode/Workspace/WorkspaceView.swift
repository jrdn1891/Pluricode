import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct WorkspaceView: View {
    let workspace: Workspace
    @Namespace private var minimizeNS
    @State private var modifierMonitor: Any?
    @State private var dragMonitor: Any?
    @State private var resignObserver: NSObjectProtocol?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                WorkspaceBody(workspace: workspace, ns: minimizeNS)
                MinimizedPaneBar(workspace: workspace, ns: minimizeNS)
            }
            if let id = workspace.expandedPaneID {
                ExpandedPaneOverlay(paneID: id, workspace: workspace)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: workspace.expandedPaneID)
        .focusedSceneValue(\.workspace, workspace)
        .onAppear {
            modifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                workspace.setCommandKeyDown(event.modifierFlags.contains(.command))
                return event
            }
            dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseUp]) { event in
                guard workspace.dragSession != nil else { return event }
                if event.type == .keyDown, event.keyCode == 53 {
                    workspace.cancelDrag()
                    return nil
                }
                if event.type == .leftMouseUp {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        workspace.endDrag()
                    }
                }
                return event
            }
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                workspace.setCommandKeyDown(false)
                workspace.endDrag()
            }
        }
        .onDisappear {
            if let m = modifierMonitor { NSEvent.removeMonitor(m) }
            modifierMonitor = nil
            if let m = dragMonitor { NSEvent.removeMonitor(m) }
            dragMonitor = nil
            if let o = resignObserver { NotificationCenter.default.removeObserver(o) }
            resignObserver = nil
            workspace.setCommandKeyDown(false)
            workspace.endDrag()
        }
    }
}

private struct WorkspaceBody: View {
    let workspace: Workspace
    let ns: Namespace.ID

    private var dragPreview: (root: TileNode, highlightedIDs: Set<UUID>)? {
        workspace.previewLayout.map { ($0.root, [$0.highlightID]) }
    }

    private var resizePreview: (root: TileNode, highlightedIDs: Set<UUID>)? {
        workspace.resizePreview
    }

    private var isPreviewing: Bool {
        dragPreview != nil || resizePreview != nil
    }

    private var resizeReporter: ResizeReporter {
        ResizeReporter(
            change: { weightsBySplit, highlighted in
                workspace.updateResize(weightsBySplit: weightsBySplit, highlightedPaneIDs: highlighted)
            },
            end: { workspace.endResize() }
        )
    }

    var body: some View {
        ZStack {
            if let root = workspace.tiling.root {
                TileView(node: root, tiling: workspace.tiling) { pane in
                    WorkspacePane(pane: pane, workspace: workspace, ns: ns)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
                .padding(4)
                .opacity(isPreviewing ? 0.32 : 1)
                .animation(.easeOut(duration: 0.12), value: isPreviewing)
                .environment(\.resizeReporter, resizeReporter)
            } else {
                EmptyWorkspace(workspace: workspace)
            }

            if let preview = dragPreview {
                GhostLayoutOverlay(
                    root: preview.root,
                    highlightedIDs: preview.highlightedIDs,
                    tiling: workspace.tiling,
                    workspace: workspace
                )
                .padding(4)
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            if let preview = resizePreview {
                GhostLayoutOverlay(
                    root: preview.root,
                    highlightedIDs: preview.highlightedIDs,
                    tiling: workspace.tiling,
                    workspace: workspace
                )
                .padding(4)
                .allowsHitTesting(false)
            }
        }
    }
}

private struct GhostLayoutOverlay: View {
    let root: TileNode
    let highlightedIDs: Set<UUID>
    let tiling: Tiling
    let workspace: Workspace

    var body: some View {
        TileView(node: root, tiling: tiling) { pane in
            GhostPane(pane: pane, isHighlight: highlightedIDs.contains(pane.id), workspace: workspace)
        }
    }
}

private struct GhostPane: View {
    let pane: Pane
    let isHighlight: Bool
    let workspace: Workspace

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(isHighlight ? Color.accentColor.opacity(0.32) : Color.secondary.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            isHighlight ? Color.accentColor : Color.secondary.opacity(0.5),
                            style: StrokeStyle(
                                lineWidth: isHighlight ? 2 : 1,
                                dash: isHighlight ? [] : [5, 3]
                            )
                        )
                )
            HStack(spacing: 6) {
                if let icon = paneIcon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(paneTitle)
                    .font(.system(size: 13, weight: isHighlight ? .semibold : .medium))
            }
            .lineLimit(1)
            .foregroundStyle(isHighlight ? Color.accentColor : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(Color(nsColor: .windowBackgroundColor).opacity(0.8))
            )
        }
        .padding(2)
    }

    private var paneIcon: String? {
        switch pane.activeTab.content {
        case .terminal: return "arrow.triangle.branch"
        case .shell: return "folder"
        case .tasks: return "checklist"
        case .widget(let kind): return kind.systemImage
        case .browser: return "globe"
        case .simulator: return "iphone"
        }
    }

    private var paneTitle: String {
        switch pane.activeTab.content {
        case .terminal(_, let worktreeID):
            return worktreeID
        case .shell(let cwd):
            return cwd.lastPathComponent
        case .tasks(let listID):
            return workspace.taskListStore.lists.first { $0.id == listID }?.name ?? "Tasks"
        case .widget(let kind):
            return kind.label
        case .browser(_, let worktreeID, _):
            return worktreeID
        case .simulator(_, let worktreeID):
            return worktreeID
        }
    }
}

private struct EmptyWorkspace: View {
    let workspace: Workspace
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Drag a worktree here")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Or drag a Task List from the sidebar to jot down quick notes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .padding(32)
        }
        .onDrop(of: [.plainText], delegate: EmptyWorkspaceDropDelegate(workspace: workspace, isTargeted: $isTargeted))
    }
}

private struct WorkspacePane: View {
    let pane: Pane
    let workspace: Workspace
    let ns: Namespace.ID

    var body: some View {
        PaneFrame {
            VStack(alignment: .leading, spacing: 0) {
                if pane.tabs.count >= 2 {
                    TabStrip(pane: pane, workspace: workspace)
                }
                TabBody(pane: pane, workspace: workspace)
            }
        }
        .matchedGeometryEffect(id: pane.id, in: ns, isSource: true)
        .overlay {
            QuickSwitchOverlay(paneID: pane.id, workspace: workspace)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

private struct TabBody: View {
    let pane: Pane
    let workspace: Workspace

    var body: some View {
        let tab = pane.activeTab
        switch tab.content {
        case .terminal(let repoID, let worktreeID):
            TerminalPaneBody(
                pane: pane,
                tabID: tab.id,
                repoID: repoID,
                worktreeID: worktreeID,
                workspace: workspace
            )
        case .shell(let cwd):
            ShellPaneBody(pane: pane, tabID: tab.id, cwd: cwd, workspace: workspace)
        case .tasks(let listID):
            TaskPaneBody(pane: pane, tabID: tab.id, listID: listID, workspace: workspace)
        case .widget(.localHosts):
            WidgetPaneBody(pane: pane, tabID: tab.id, workspace: workspace)
        case .browser(let repoID, let worktreeID, let url):
            BrowserPaneBody(
                pane: pane,
                tabID: tab.id,
                repoID: repoID,
                worktreeID: worktreeID,
                url: url,
                workspace: workspace
            )
        case .simulator(let repoID, let worktreeID):
            SimulatorPaneBody(
                pane: pane,
                tabID: tab.id,
                repoID: repoID,
                worktreeID: worktreeID,
                workspace: workspace
            )
        }
    }
}

private struct WidgetPaneBody: View {
    let pane: Pane
    let tabID: UUID
    let workspace: Workspace

    var body: some View {
        GeometryReader { geo in
            LocalHostsWidgetView(
                paneID: pane.id,
                tabID: tabID,
                workspace: workspace,
                onActivate: { workspace.setFocus(paneID: pane.id) },
                onMinimize: workspace.canMinimize(paneID: pane.id)
                    ? { workspace.minimizePane(paneID: pane.id) }
                    : nil,
                onClose: { workspace.closeTab(paneID: pane.id, tabID: tabID) }
            )
            .frame(width: geo.size.width, height: geo.size.height)
            .onDrop(
                of: [.plainText],
                delegate: PaneDropDelegate(paneID: pane.id, workspace: workspace, size: geo.size)
            )
        }
    }
}

private struct BrowserPaneBody: View {
    let pane: Pane
    let tabID: UUID
    let repoID: UUID
    let worktreeID: String
    let url: URL?
    let workspace: Workspace

    var body: some View {
        let isExpanded = workspace.expandedPaneID == pane.id
        VStack(alignment: .leading, spacing: 0) {
            BrowserHeader(
                pane: pane,
                tabID: tabID,
                worktreeID: worktreeID,
                repoName: workspace.repo(id: repoID)?.name,
                repoColor: workspace.repo(id: repoID)?.resolvedColor.swiftUIColor,
                workspace: workspace,
                isExpanded: isExpanded,
                onExpand: {
                    if isExpanded { workspace.collapseExpandedPane() }
                    else { workspace.expandPane(paneID: pane.id) }
                }
            )
            if isExpanded {
                ExpandedPanePlaceholder()
            } else {
                GeometryReader { geo in
                    BrowserContent(tabID: tabID, repoID: repoID, worktreeID: worktreeID, url: url, workspace: workspace)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .overlay {
                            if workspace.dragSession != nil {
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onDrop(
                                        of: [.plainText],
                                        delegate: PaneDropDelegate(paneID: pane.id, workspace: workspace, size: geo.size)
                                    )
                            }
                        }
                }
            }
        }
    }
}

private struct BrowserContent: View {
    let tabID: UUID
    let repoID: UUID
    let worktreeID: String
    let url: URL?
    let workspace: Workspace

    private var host: BrowserHost? { workspace.browserHosts[tabID] }

    private var agentAvailable: Bool {
        guard let host else { return false }
        return workspace.agentSession(repoID: repoID, worktreeID: worktreeID, preferredTabID: host.originTabID) != nil
    }

    var body: some View {
        ZStack {
            BrowserPaneView(
                tabID: tabID,
                repoID: repoID,
                worktreeID: worktreeID,
                initialURL: url,
                workspace: workspace
            )
            .id(tabID)
            if url == nil, host?.currentURL == nil {
                BrowserEmptyState()
            }
            if let host, host.markup.isMarkingUp {
                MarkupSelectionOverlay(
                    markup: host.markup,
                    agentAvailable: agentAvailable,
                    onSend: sendMarkup,
                    onCancel: host.markup.cancel
                )
            }
        }
    }

    private func sendMarkup() {
        guard let host,
              let session = workspace.agentSession(repoID: repoID, worktreeID: worktreeID, preferredTabID: host.originTabID) else { return }
        let rects = host.markup.rects
        let note = host.markup.note
        host.captureSnapshot { image in
            guard let image,
                  let path = Markup.writeTempPNG(Markup.annotate(image, rects: rects)) else { return }
            session.sendMarkup(note: note, imagePath: path)
            host.markup.cancel()
        }
    }
}

private struct BrowserExpandedContent: View {
    let pane: Pane
    let tabID: UUID
    let repoID: UUID
    let worktreeID: String
    let url: URL?
    let workspace: Workspace

    var body: some View {
        VStack(spacing: 0) {
            BrowserHeader(
                pane: pane,
                tabID: tabID,
                worktreeID: worktreeID,
                repoName: workspace.repo(id: repoID)?.name,
                repoColor: workspace.repo(id: repoID)?.resolvedColor.swiftUIColor,
                workspace: workspace,
                isExpanded: true,
                onExpand: { workspace.collapseExpandedPane() }
            )
            BrowserContent(tabID: tabID, repoID: repoID, worktreeID: worktreeID, url: url, workspace: workspace)
        }
    }
}

private struct BrowserHeader: View {
    let pane: Pane
    let tabID: UUID
    let worktreeID: String
    let repoName: String?
    let repoColor: Color?
    let workspace: Workspace
    let isExpanded: Bool
    let onExpand: () -> Void
    @State private var address: String = ""
    @FocusState private var addressFocused: Bool

    private var host: BrowserHost? { workspace.browserHosts[tabID] }

    var body: some View {
        HStack(spacing: 8) {
            dragHandle
            navButton("chevron.left", enabled: host?.canGoBack ?? false) { host?.webView.goBack() }
            navButton("chevron.right", enabled: host?.canGoForward ?? false) { host?.webView.goForward() }
            navButton(host?.isLoading == true ? "xmark" : "arrow.clockwise", enabled: host != nil) { host?.reload() }
            addressField
            Button(action: toggleMarkup) {
                Image(systemName: "pencil.tip.crop.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle((host?.markup.isMarkingUp == true) ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(host == nil)
            .help("Mark up the preview for this worktree's agent")
            Button(action: onExpand) {
                Image(systemName: isExpanded
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse" : "Expand")
            if !isExpanded, workspace.canMinimize(paneID: pane.id) {
                Button(action: { workspace.minimizePane(paneID: pane.id) }) {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Minimize pane")
            }
            if !isExpanded {
                Button(action: { workspace.closeTab(paneID: pane.id, tabID: tabID) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(headerBackground)
        .contentShape(Rectangle())
        .onTapGesture { workspace.setFocus(paneID: pane.id) }
        .draggable(beginMoveDrag()) {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                Text(worktreeID)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .onAppear { syncAddress() }
        .onChange(of: host?.currentURL) { _, _ in syncAddress() }
    }

    private var dragHandle: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(repoColor ?? .accentColor)
                .frame(width: 10, height: 10)
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .help(worktreeID)
    }

    private var addressField: some View {
        TextField("localhost:3000", text: $address)
            .textFieldStyle(.plain)
            .font(.system(size: 11, design: .monospaced))
            .focused($addressFocused)
            .onSubmit(submit)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
            .frame(maxWidth: .infinity)
    }

    private func navButton(_ systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? Color.secondary : Color.secondary.opacity(0.35))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var headerBackground: Color {
        if let repoColor { return repoColor.opacity(0.12) }
        return Color.secondary.opacity(0.1)
    }

    private func submit() {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let str = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let url = URL(string: str) else { return }
        host?.load(url)
        workspace.updateBrowserURL(tabID: tabID, url: url)
        addressFocused = false
    }

    private func toggleMarkup() {
        guard let host else { return }
        if host.markup.isMarkingUp { host.markup.cancel() } else { host.markup.begin() }
    }

    private func syncAddress() {
        guard !addressFocused else { return }
        guard let url = host?.currentURL else { address = ""; return }
        var s = url.absoluteString
        if s.hasSuffix("/") { s.removeLast() }
        address = s
    }

    private func beginMoveDrag() -> TilingDragPayload {
        let payload = TilingDragPayload(kind: .movePane(paneID: pane.id))
        workspace.beginDrag(payload)
        return payload
    }
}

private struct BrowserEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Waiting for a dev server on this worktree…")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Start your dev server, then click Preview again — or type a URL above.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SimulatorPaneBody: View {
    let pane: Pane
    let tabID: UUID
    let repoID: UUID
    let worktreeID: String
    let workspace: Workspace

    var body: some View {
        let isExpanded = workspace.expandedPaneID == pane.id
        VStack(alignment: .leading, spacing: 0) {
            SimulatorHeader(
                pane: pane,
                tabID: tabID,
                worktreeID: worktreeID,
                repoName: workspace.repo(id: repoID)?.name,
                repoColor: workspace.repo(id: repoID)?.resolvedColor.swiftUIColor,
                workspace: workspace,
                isExpanded: isExpanded,
                onExpand: {
                    if isExpanded { workspace.collapseExpandedPane() }
                    else { workspace.expandPane(paneID: pane.id) }
                }
            )
            if isExpanded {
                ExpandedPanePlaceholder()
            } else {
                GeometryReader { geo in
                    SimulatorContent(tabID: tabID, repoID: repoID, worktreeID: worktreeID, workspace: workspace)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .overlay {
                            if workspace.dragSession != nil {
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onDrop(
                                        of: [.plainText],
                                        delegate: PaneDropDelegate(paneID: pane.id, workspace: workspace, size: geo.size)
                                    )
                            }
                        }
                }
            }
        }
        .onAppear {
            if workspace.simulatorHosts[tabID] == nil {
                workspace.simulatorHosts[tabID] = SimulatorHost(
                    tabID: tabID,
                    repoID: repoID,
                    worktreeID: worktreeID,
                    originTabID: workspace.consumePendingPreviewOrigin(tabID: tabID)
                )
            }
        }
    }
}

private struct SimulatorContent: View {
    let tabID: UUID
    let repoID: UUID
    let worktreeID: String
    let workspace: Workspace

    private var host: SimulatorHost? { workspace.simulatorHosts[tabID] }

    private var agentAvailable: Bool {
        guard let host else { return false }
        return workspace.agentSession(repoID: repoID, worktreeID: worktreeID, preferredTabID: host.originTabID) != nil
    }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if let host, let frame = host.frame {
                ZStack {
                    Image(nsImage: frame)
                        .resizable()
                    if host.isLive, !host.markup.isMarkingUp {
                        SimulatorInputView(host: host)
                    }
                    if host.markup.isMarkingUp {
                        MarkupSelectionOverlay(
                            markup: host.markup,
                            agentAvailable: agentAvailable,
                            onSend: sendMarkup,
                            onCancel: host.markup.cancel
                        )
                    }
                }
                .aspectRatio(frame.size.width / frame.size.height, contentMode: .fit)
                .padding(8)
            } else {
                SimulatorEmptyState()
            }
        }
    }

    private func sendMarkup() {
        guard let host, let frame = host.frame,
              let session = workspace.agentSession(repoID: repoID, worktreeID: worktreeID, preferredTabID: host.originTabID),
              let path = Markup.writeTempPNG(Markup.annotate(frame, rects: host.markup.rects)) else { return }
        session.sendMarkup(note: host.markup.note, imagePath: path)
        host.markup.cancel()
    }
}

private struct SimulatorExpandedContent: View {
    let pane: Pane
    let tabID: UUID
    let repoID: UUID
    let worktreeID: String
    let workspace: Workspace

    var body: some View {
        VStack(spacing: 0) {
            SimulatorHeader(
                pane: pane,
                tabID: tabID,
                worktreeID: worktreeID,
                repoName: workspace.repo(id: repoID)?.name,
                repoColor: workspace.repo(id: repoID)?.resolvedColor.swiftUIColor,
                workspace: workspace,
                isExpanded: true,
                onExpand: { workspace.collapseExpandedPane() }
            )
            SimulatorContent(tabID: tabID, repoID: repoID, worktreeID: worktreeID, workspace: workspace)
        }
    }
}

private struct SimulatorHeader: View {
    let pane: Pane
    let tabID: UUID
    let worktreeID: String
    let repoName: String?
    let repoColor: Color?
    let workspace: Workspace
    let isExpanded: Bool
    let onExpand: () -> Void

    private var host: SimulatorHost? { workspace.simulatorHosts[tabID] }

    var body: some View {
        HStack(spacing: 8) {
            dragHandle
            Text(host?.deviceName ?? "No simulator")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(host?.deviceName == nil ? Color.secondary : Color.primary)
            Spacer()
            if host?.isLive == true {
                Button(action: { host?.sendHome() }) {
                    Image(systemName: "house")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Press the Home button")
            }
            Button(action: toggleMarkup) {
                Image(systemName: "pencil.tip.crop.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle((host?.markup.isMarkingUp == true) ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(host?.frame == nil)
            .help("Mark up the simulator for this worktree's agent")
            Button(action: onExpand) {
                Image(systemName: isExpanded
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse" : "Expand")
            if !isExpanded, workspace.canMinimize(paneID: pane.id) {
                Button(action: { workspace.minimizePane(paneID: pane.id) }) {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Minimize pane")
            }
            if !isExpanded {
                Button(action: { workspace.closeTab(paneID: pane.id, tabID: tabID) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(headerBackground)
        .contentShape(Rectangle())
        .onTapGesture { workspace.setFocus(paneID: pane.id) }
        .draggable(beginMoveDrag()) {
            HStack(spacing: 6) {
                Image(systemName: "iphone")
                Text(worktreeID)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var dragHandle: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(repoColor ?? .accentColor)
                .frame(width: 10, height: 10)
            Image(systemName: "iphone")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .help(worktreeID)
    }

    private var headerBackground: Color {
        if let repoColor { return repoColor.opacity(0.12) }
        return Color.secondary.opacity(0.1)
    }

    private func toggleMarkup() {
        guard let host else { return }
        if host.markup.isMarkingUp { host.markup.cancel() } else { host.markup.begin() }
    }

    private func beginMoveDrag() -> TilingDragPayload {
        let payload = TilingDragPayload(kind: .movePane(paneID: pane.id))
        workspace.beginDrag(payload)
        return payload
    }
}

private struct SimulatorEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Waiting for a booted simulator…")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Boot a device in Simulator.app or ask the agent to run one, and it will appear here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }
}

// Forwards mouse and keyboard input over the live device frame: a click taps, a drag swipes
// (scroll / page switch), and typing goes to the device once the view has key focus.
private struct SimulatorInputView: NSViewRepresentable {
    let host: SimulatorHost

    func makeNSView(context: Context) -> InputNSView {
        let view = InputNSView()
        view.host = host
        return view
    }

    func updateNSView(_ nsView: InputNSView, context: Context) { nsView.host = host }

    final class InputNSView: NSView {
        weak var host: SimulatorHost?
        private var downPoint: NSPoint?

        override var isFlipped: Bool { true }          // top-left origin, matching device coordinates
        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        private func normalized(_ p: NSPoint) -> (Double, Double) {
            (Double(p.x / max(bounds.width, 1)), Double(p.y / max(bounds.height, 1)))
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            downPoint = convert(event.locationInWindow, from: nil)
        }

        override func mouseUp(with event: NSEvent) {
            guard let start = downPoint else { return }
            downPoint = nil
            let end = convert(event.locationInWindow, from: nil)
            let (sx, sy) = normalized(start)
            let (ex, ey) = normalized(end)
            if hypot(end.x - start.x, end.y - start.y) < bounds.width * 0.02 {
                host?.sendTap(x: ex, y: ey)
            } else {
                host?.sendSwipe(x0: sx, y0: sy, x1: ex, y1: ey)
            }
        }

        override func keyDown(with event: NSEvent) {
            guard let text = event.characters, !text.isEmpty else { return super.keyDown(with: event) }
            host?.sendText(text)
        }
    }
}

private struct MarkupSelectionOverlay: View {
    let markup: Markup
    let agentAvailable: Bool
    let onSend: () -> Void
    let onCancel: () -> Void
    @State private var current: CGRect?

    private let fieldWidth: CGFloat = 280
    private let fieldHeight: CGFloat = 34

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.06)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in
                                current = normalizedRect(value.startLocation, value.location, geo.size)
                            }
                            .onEnded { value in
                                let rect = normalizedRect(value.startLocation, value.location, geo.size)
                                if rect.width > 0.004, rect.height > 0.004 { markup.rects.append(rect) }
                                current = nil
                            }
                    )
                if markup.rects.isEmpty, current == nil {
                    Text("Drag to mark up an area")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .allowsHitTesting(false)
                }
                ForEach(Array(markup.rects.enumerated()), id: \.offset) { _, rect in
                    box(rect, in: geo.size)
                }
                if let current {
                    box(current, in: geo.size)
                }
                if let anchor = markup.rects.last {
                    MarkupCommentField(markup: markup, agentAvailable: agentAvailable, onSend: onSend, onCancel: onCancel)
                        .frame(width: fieldWidth)
                        .offset(commentOffset(anchor, in: geo.size))
                }
            }
        }
    }

    private func box(_ rect: CGRect, in size: CGSize) -> some View {
        Rectangle()
            .fill(Color.red.opacity(0.12))
            .overlay(Rectangle().strokeBorder(Color.red, lineWidth: 2))
            .frame(width: rect.width * size.width, height: rect.height * size.height)
            .position(x: (rect.minX + rect.width / 2) * size.width, y: (rect.minY + rect.height / 2) * size.height)
            .allowsHitTesting(false)
    }

    private func commentOffset(_ rect: CGRect, in size: CGSize) -> CGSize {
        let gap: CGFloat = 8
        let x = min(max(8, rect.minX * size.width), max(8, size.width - fieldWidth - 8))
        let below = (rect.minY + rect.height) * size.height + gap
        let above = rect.minY * size.height - fieldHeight - gap
        let y = below + fieldHeight <= size.height ? below : max(8, above)
        return CGSize(width: x, height: y)
    }

    private func normalizedRect(_ a: CGPoint, _ b: CGPoint, _ size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let x = min(a.x, b.x) / size.width
        let y = min(a.y, b.y) / size.height
        let w = abs(a.x - b.x) / size.width
        let h = abs(a.y - b.y) / size.height
        return CGRect(x: x, y: y, width: w, height: h)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}

private struct MarkupCommentField: View {
    @Bindable var markup: Markup
    let agentAvailable: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            MarkupNoteField(
                text: $markup.note,
                focusToken: markup.rects.count,
                onSubmit: { if agentAvailable { onSend() } },
                onCancel: onCancel
            )
            if agentAvailable {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .help("No agent terminal open for this worktree")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
    }
}

private struct MarkupNoteField: NSViewRepresentable {
    @Binding var text: String
    let focusToken: Int
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = FocusGrabbingTextField()
        field.delegate = context.coordinator
        field.placeholderString = "Describe the issue…"
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async { [weak field] in
                field?.window?.makeFirstResponder(field)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: MarkupNoteField
        var focusToken: Int?

        init(_ parent: MarkupNoteField) { self.parent = parent }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit(); return true
            case #selector(NSResponder.cancelOperation(_:)): parent.onCancel(); return true
            default: return false
            }
        }
    }
}

private final class FocusGrabbingTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            window?.makeFirstResponder(self)
        }
    }
}

private struct TabStrip: View {
    let pane: Pane
    let workspace: Workspace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(pane.tabs) { tab in
                TabCell(
                    label: workspace.tabLabel(tab, fallback: "tab"),
                    isActive: tab.id == pane.activeTabID,
                    onSelect: { workspace.setActiveTab(paneID: pane.id, tabID: tab.id) },
                    onClose: { workspace.closeTab(paneID: pane.id, tabID: tab.id) }
                )
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .background(Color.secondary.opacity(0.06))
    }
}

private struct TabCell: View {
    let label: String
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .primary : .secondary)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .opacity(hovering || isActive ? 1 : 0)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isActive ? Color.secondary.opacity(0.18) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
    }
}

private struct QuickSwitchOverlay: View {
    let paneID: UUID
    let workspace: Workspace

    var body: some View {
        let visible = workspace.commandKeyHeld
            && workspace.terminalPanes.count >= 2
            && (paneIndex.map { $0 < 9 } ?? false)
        ZStack {
            if visible, let index = paneIndex {
                Color.black.opacity(0.18)
                Text("⌘\(index + 1)")
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 22)
                            .fill(.regularMaterial)
                    )
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.12), value: visible)
    }

    private var paneIndex: Int? {
        workspace.terminalPanes.firstIndex { $0.id == paneID }
    }
}

private struct PaneFrame<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

private struct TaskPaneBody: View {
    let pane: Pane
    let tabID: UUID
    let listID: UUID
    let workspace: Workspace

    var body: some View {
        GeometryReader { geo in
            TaskPaneView(
                paneID: pane.id,
                listID: listID,
                store: workspace.taskListStore,
                workspace: workspace,
                onActivate: { workspace.setFocus(paneID: pane.id) },
                onMinimize: workspace.canMinimize(paneID: pane.id)
                    ? { workspace.minimizePane(paneID: pane.id) }
                    : nil,
                onClose: { workspace.closeTab(paneID: pane.id, tabID: tabID) }
            )
            .frame(width: geo.size.width, height: geo.size.height)
            .onDrop(
                of: [.plainText],
                delegate: PaneDropDelegate(paneID: pane.id, workspace: workspace, size: geo.size)
            )
        }
    }
}

private struct TerminalPaneBody: View {
    let pane: Pane
    let tabID: UUID
    let repoID: UUID
    let worktreeID: String
    let workspace: Workspace

    var body: some View {
        let isExpanded = workspace.expandedPaneID == pane.id
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(
                pane: pane,
                tabID: tabID,
                workspace: workspace,
                title: worktreeID,
                repoName: workspace.repo(id: repoID)?.name,
                repoColor: workspace.repo(id: repoID)?.resolvedColor.swiftUIColor,
                isExpanded: isExpanded,
                onActivate: { workspace.setFocus(paneID: pane.id) },
                onExpand: {
                    if isExpanded { workspace.collapseExpandedPane() }
                    else { workspace.expandPane(paneID: pane.id) }
                },
                onClose: { workspace.closeTab(paneID: pane.id, tabID: tabID) },
                onPreview: {
                    workspace.openBrowser(
                        repoID: repoID,
                        worktreeID: worktreeID,
                        originTabID: tabID,
                        nearPaneID: pane.id
                    )
                },
                onSimulator: SimulatorHost.simulatorInstalled ? {
                    workspace.openSimulator(
                        repoID: repoID,
                        worktreeID: worktreeID,
                        originTabID: tabID,
                        nearPaneID: pane.id
                    )
                } : nil
            )
            if isExpanded {
                ExpandedPanePlaceholder()
            } else if let targetID = workspace.stubTabs[tabID] {
                SessionMovedBody(
                    worktreeID: worktreeID,
                    targetWorkspaceName: workspace.store?.workspaces.first { $0.id == targetID }?.name,
                    onRemove: { workspace.closeTab(paneID: pane.id, tabID: tabID) }
                )
            } else if let path = workspace.worktreePath(tabID: tabID), let repoPath = workspace.repo(id: repoID)?.path.path {
                GeometryReader { geo in
                    TerminalPaneView(paneID: pane.id, tabID: tabID, repoID: repoID, worktreeID: worktreeID, worktreePath: path, repoPath: repoPath, workspace: workspace)
                        .id(tabID)
                        .overlay {
                            if let session = workspace.terminalHosts[tabID]?.session {
                                IdleOverlay(session: session)
                            }
                        }
                        .overlay {
                            if let session = workspace.terminalHosts[tabID]?.session {
                                AttachmentChipsOverlay(session: session)
                            }
                        }
                        .onDrop(
                            of: [.plainText],
                            delegate: PaneDropDelegate(paneID: pane.id, workspace: workspace, size: geo.size)
                        )
                }
            } else if workspace.repo(id: repoID) == nil || workspace.worktreePaths.isLoaded(repoID: repoID) {
                MissingWorktreeBody(
                    worktreeID: worktreeID,
                    onRemove: { workspace.closeTab(paneID: pane.id, tabID: tabID) }
                )
            } else {
                Color.clear
            }
        }
    }
}

private struct ShellPaneBody: View {
    let pane: Pane
    let tabID: UUID
    let cwd: URL
    let workspace: Workspace

    var body: some View {
        let isExpanded = workspace.expandedPaneID == pane.id
        VStack(alignment: .leading, spacing: 0) {
            ShellPaneHeader(
                pane: pane,
                workspace: workspace,
                cwd: cwd,
                isExpanded: isExpanded,
                onActivate: { workspace.setFocus(paneID: pane.id) },
                onExpand: {
                    if isExpanded { workspace.collapseExpandedPane() }
                    else { workspace.expandPane(paneID: pane.id) }
                },
                onClose: { workspace.closeTab(paneID: pane.id, tabID: tabID) }
            )
            if isExpanded {
                ExpandedPanePlaceholder()
            } else if FileManager.default.fileExists(atPath: cwd.path) {
                GeometryReader { geo in
                    ShellPaneView(paneID: pane.id, tabID: tabID, cwd: cwd, workspace: workspace)
                        .id(tabID)
                        .overlay {
                            if let session = workspace.terminalHosts[tabID]?.session {
                                IdleOverlay(session: session)
                            }
                        }
                        .overlay {
                            if let session = workspace.terminalHosts[tabID]?.session {
                                AttachmentChipsOverlay(session: session)
                            }
                        }
                        .onDrop(
                            of: [.plainText],
                            delegate: PaneDropDelegate(paneID: pane.id, workspace: workspace, size: geo.size)
                        )
                }
            } else {
                MissingFolderBody(
                    cwd: cwd,
                    onRemove: { workspace.closeTab(paneID: pane.id, tabID: tabID) }
                )
            }
        }
    }
}

private struct ShellPaneHeader: View {
    let pane: Pane
    let workspace: Workspace
    let cwd: URL
    let isExpanded: Bool
    let onActivate: () -> Void
    let onExpand: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(cwd.lastPathComponent)
                .font(.system(size: 12, weight: .medium))
            Text(parentPath)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
            Button(action: onExpand) {
                Image(systemName: isExpanded
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse" : "Expand")
            if !isExpanded, workspace.canMinimize(paneID: pane.id) {
                Button(action: { workspace.minimizePane(paneID: pane.id) }) {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Minimize pane")
            }
            if !isExpanded {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
        .draggable(beginMoveDrag()) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                Text(cwd.lastPathComponent)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var parentPath: String {
        let parent = cwd.deletingLastPathComponent().path
        let home = NSHomeDirectory()
        if parent == home { return "~" }
        if parent.hasPrefix(home + "/") { return "~" + parent.dropFirst(home.count) }
        return parent
    }

    private func beginMoveDrag() -> TilingDragPayload {
        let payload = TilingDragPayload(kind: .movePane(paneID: pane.id))
        workspace.beginDrag(payload)
        return payload
    }
}

private struct MissingFolderBody: View {
    let cwd: URL
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text("Folder `\(cwd.path)` not found")
                .font(.headline)
            Text("It may have been deleted or renamed.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Remove Pane", role: .destructive, action: onRemove)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct ExpandedPanePlaceholder: View {
    var body: some View {
        ZStack {
            Color.secondary.opacity(0.08)
            Text("Expanded")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PaneHeader: View {
    let pane: Pane
    let tabID: UUID
    let workspace: Workspace
    let title: String
    let repoName: String?
    let repoColor: Color?
    let isExpanded: Bool
    let onActivate: () -> Void
    let onExpand: () -> Void
    let onClose: () -> Void
    let onPreview: (() -> Void)?
    let onSimulator: (() -> Void)?
    @State private var devScript: String?
    @Environment(PluriMonitor.self) private var monitor: PluriMonitor?

    private var isMerged: Bool {
        guard let tab = pane.tabs.first(where: { $0.id == tabID }),
              case .terminal(let repoID, let worktreeID) = tab.content else { return false }
        return workspace.worktreeStatusService.status(repoID: repoID, branch: worktreeID).isMerged
    }

    private var workerStatus: WorkerStatus? {
        guard let monitor, let path = workspace.worktreePath(tabID: tabID) else { return nil }
        return monitor.statuses[URL(fileURLWithPath: path).standardizedFileURL.path]?.status
    }

    var body: some View {
        HStack(spacing: 8) {
            if let repoName {
                Circle()
                    .fill(repoColor ?? .accentColor)
                    .frame(width: 10, height: 10)
                Text(repoName)
                    .font(.system(size: 12, weight: .medium))
                Text("·")
                    .foregroundStyle(.secondary)
            }
            Image(systemName: isMerged ? "arrow.trianglehead.merge" : "arrow.triangle.branch")
                .foregroundStyle(isMerged ? Color.green : Color.secondary)
                .font(.caption)
            Text(title)
                .font(.system(size: 12, weight: .medium))
            if let status = workerStatus {
                Circle()
                    .fill(status.color)
                    .frame(width: 7, height: 7)
                    .help(status.help)
            }
            Spacer()
            if devScript != nil {
                Button(action: { workspace.runDevScript(paneID: pane.id) }) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Run dev script in a new tab (⌘R)")
            }
            if let onPreview {
                Button(action: onPreview) {
                    Image(systemName: "globe")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Preview this worktree's local server in a built-in browser")
            }
            if let onSimulator {
                Button(action: onSimulator) {
                    Image(systemName: "iphone")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Preview the iOS Simulator for this worktree's agent")
            }
            Button(action: onExpand) {
                Image(systemName: isExpanded
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse" : "Expand")
            if !isExpanded, workspace.canMinimize(paneID: pane.id) {
                Button(action: { workspace.minimizePane(paneID: pane.id) }) {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Minimize pane")
            }
            if !isExpanded {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(headerBackground)
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
        .task(id: tabID) {
            devScript = workspace.devScript(paneID: pane.id)
        }
        .draggable(beginMoveDrag()) {
            HStack(spacing: 6) {
                Image(systemName: isMerged ? "arrow.trianglehead.merge" : "arrow.triangle.branch")
                Text(title)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var headerBackground: Color {
        if let repoColor { return repoColor.opacity(0.12) }
        return Color.secondary.opacity(0.1)
    }

    private func beginMoveDrag() -> TilingDragPayload {
        let payload = TilingDragPayload(kind: .movePane(paneID: pane.id))
        workspace.beginDrag(payload)
        return payload
    }
}

private extension WorkerStatus {
    var help: String {
        switch self {
        case .running: "Agent is working"
        case .waiting: "Agent is waiting for permission or input"
        case .done: "Agent finished its turn"
        }
    }
}

private struct MissingWorktreeBody: View {
    let worktreeID: String
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text("Worktree `\(worktreeID)` not found")
                .font(.headline)
            Text("It may have been deleted or renamed.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Remove Pane", role: .destructive, action: onRemove)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct EmptyWorkspaceDropDelegate: DropDelegate {
    let workspace: Workspace
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) {
        isTargeted = true
        workspace.updateHover(.init(paneID: nil, edge: .center))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if workspace.dragSession?.isCancelled == true {
            return DropProposal(operation: .forbidden)
        }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
        if workspace.dragSession?.hover?.paneID == nil {
            workspace.updateHover(nil)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        workspace.updateHover(nil)
        guard let provider = info.itemProviders(for: [.plainText]).first else {
            workspace.endDrag()
            return false
        }
        provider.loadObject(ofClass: NSString.self) { obj, _ in
            guard let str = obj as? String,
                  let data = str.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(TilingDragPayload.self, from: data) else {
                DispatchQueue.main.async { workspace.endDrag() }
                return
            }
            DispatchQueue.main.async {
                _ = workspace.acceptDrop(payload: payload, on: nil, edge: .center)
            }
        }
        return true
    }
}

private struct PaneDropDelegate: DropDelegate {
    let paneID: UUID
    let workspace: Workspace
    let size: CGSize

    func dropEntered(info: DropInfo) {
        workspace.updateHover(.init(paneID: paneID, edge: TileEdge.zone(for: info.location, in: size)))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        workspace.updateHover(.init(paneID: paneID, edge: TileEdge.zone(for: info.location, in: size)))
        if workspace.dragSession?.isCancelled == true {
            return DropProposal(operation: .forbidden)
        }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if workspace.dragSession?.hover?.paneID == paneID {
            workspace.updateHover(nil)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let edge = TileEdge.zone(for: info.location, in: size)
        workspace.updateHover(nil)
        guard let provider = info.itemProviders(for: [.plainText]).first else {
            workspace.endDrag()
            return false
        }
        provider.loadObject(ofClass: NSString.self) { obj, _ in
            guard let str = obj as? String,
                  let data = str.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(TilingDragPayload.self, from: data) else {
                DispatchQueue.main.async { workspace.endDrag() }
                return
            }
            DispatchQueue.main.async {
                _ = workspace.acceptDrop(payload: payload, on: paneID, edge: edge)
            }
        }
        return true
    }
}

private struct MinimizedPaneBar: View {
    let workspace: Workspace
    let ns: Namespace.ID

    var body: some View {
        if !workspace.minimizedPanes.isEmpty {
            HStack(spacing: 6) {
                ForEach(workspace.minimizedPanes) { item in
                    MinimizedPaneChip(item: item, workspace: workspace, ns: ns)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.08))
            .overlay(alignment: .top) {
                Divider()
            }
        }
    }
}

private struct MinimizedPaneChip: View {
    let item: MinimizedPane
    let workspace: Workspace
    let ns: Namespace.ID
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            Button(action: { workspace.closeMinimizedPane(paneID: item.id) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .opacity(hovering ? 1 : 0)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(hovering ? 0.22 : 0.16))
        )
        .matchedGeometryEffect(id: item.id, in: ns, isSource: false)
        .contentShape(Rectangle())
        .onTapGesture { workspace.restoreMinimizedPane(paneID: item.id) }
        .onHover { hovering = $0 }
        .help("Click to restore · × to close")
    }

    private var icon: String {
        switch item.pane.activeTab.content {
        case .terminal: "arrow.triangle.branch"
        case .shell: "folder"
        case .tasks: "checklist"
        case .widget(let kind): kind.systemImage
        case .browser: "globe"
        case .simulator: "iphone"
        }
    }

    private var label: String {
        let tab = item.pane.activeTab
        if let name = tab.name, !name.isEmpty { return name }
        switch tab.content {
        case .terminal(_, let worktreeID): return worktreeID
        case .shell(let cwd): return cwd.lastPathComponent
        case .tasks(let listID): return workspace.taskListStore.list(id: listID)?.name ?? "Tasks"
        case .widget(let kind): return kind.label
        case .browser(_, let worktreeID, _): return worktreeID
        case .simulator(_, let worktreeID): return worktreeID
        }
    }
}

private struct ExpandedPaneOverlay: View {
    let paneID: UUID
    let workspace: Workspace

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { workspace.collapseExpandedPane() }
            GeometryReader { geo in
                ExpandedPaneCard(paneID: paneID, workspace: workspace)
                    .frame(
                        width: min(geo.size.width * 0.9, 1400),
                        height: min(geo.size.height * 0.9, 900)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onExitCommand { workspace.collapseExpandedPane() }
    }
}

private struct ExpandedPaneCard: View {
    let paneID: UUID
    let workspace: Workspace

    var body: some View {
        if let pane = workspace.pane(id: paneID) {
            content(for: pane)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 30, y: 10)
        }
    }

    @ViewBuilder
    private func content(for pane: Pane) -> some View {
        switch pane.activeTab.content {
        case .terminal(let repoID, let worktreeID):
            TerminalExpandedContent(
                pane: pane,
                tabID: pane.activeTabID,
                repoID: repoID,
                worktreeID: worktreeID,
                workspace: workspace
            )
        case .shell(let cwd):
            ShellExpandedContent(
                pane: pane,
                tabID: pane.activeTabID,
                cwd: cwd,
                workspace: workspace
            )
        case .browser(let repoID, let worktreeID, let url):
            BrowserExpandedContent(
                pane: pane,
                tabID: pane.activeTabID,
                repoID: repoID,
                worktreeID: worktreeID,
                url: url,
                workspace: workspace
            )
        case .simulator(let repoID, let worktreeID):
            SimulatorExpandedContent(
                pane: pane,
                tabID: pane.activeTabID,
                repoID: repoID,
                worktreeID: worktreeID,
                workspace: workspace
            )
        case .tasks, .widget:
            EmptyView()
        }
    }
}

private struct TerminalExpandedContent: View {
    let pane: Pane
    let tabID: UUID
    let repoID: UUID
    let worktreeID: String
    let workspace: Workspace

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                pane: pane,
                tabID: tabID,
                workspace: workspace,
                title: worktreeID,
                repoName: workspace.repo(id: repoID)?.name,
                repoColor: workspace.repo(id: repoID)?.resolvedColor.swiftUIColor,
                isExpanded: true,
                onActivate: { workspace.setFocus(paneID: pane.id) },
                onExpand: { workspace.collapseExpandedPane() },
                onClose: { workspace.closeTab(paneID: pane.id, tabID: tabID) },
                onPreview: nil,
                onSimulator: nil
            )
            if let targetID = workspace.stubTabs[tabID] {
                SessionMovedBody(
                    worktreeID: worktreeID,
                    targetWorkspaceName: workspace.store?.workspaces.first { $0.id == targetID }?.name,
                    onRemove: { workspace.closeTab(paneID: pane.id, tabID: tabID) }
                )
            } else if let path = workspace.worktreePath(tabID: tabID),
               let repoPath = workspace.repo(id: repoID)?.path.path {
                TerminalPaneView(paneID: pane.id, tabID: tabID, repoID: repoID, worktreeID: worktreeID, worktreePath: path, repoPath: repoPath, workspace: workspace)
                    .id(tabID)
                    .overlay {
                        if let session = workspace.terminalHosts[tabID]?.session {
                            AttachmentChipsOverlay(session: session)
                        }
                    }
            } else if workspace.repo(id: repoID) == nil || workspace.worktreePaths.isLoaded(repoID: repoID) {
                MissingWorktreeBody(
                    worktreeID: worktreeID,
                    onRemove: { workspace.closeTab(paneID: pane.id, tabID: tabID) }
                )
            } else {
                Color.clear
            }
        }
    }
}

private struct ShellExpandedContent: View {
    let pane: Pane
    let tabID: UUID
    let cwd: URL
    let workspace: Workspace

    var body: some View {
        VStack(spacing: 0) {
            ShellPaneHeader(
                pane: pane,
                workspace: workspace,
                cwd: cwd,
                isExpanded: true,
                onActivate: { workspace.setFocus(paneID: pane.id) },
                onExpand: { workspace.collapseExpandedPane() },
                onClose: { workspace.closeTab(paneID: pane.id, tabID: tabID) }
            )
            if FileManager.default.fileExists(atPath: cwd.path) {
                ShellPaneView(paneID: pane.id, tabID: tabID, cwd: cwd, workspace: workspace)
                    .id(tabID)
                    .overlay {
                        if let session = workspace.terminalHosts[tabID]?.session {
                            AttachmentChipsOverlay(session: session)
                        }
                    }
            } else {
                MissingFolderBody(
                    cwd: cwd,
                    onRemove: { workspace.closeTab(paneID: pane.id, tabID: tabID) }
                )
            }
        }
    }
}

private struct SessionMovedBody: View {
    let worktreeID: String
    let targetWorkspaceName: String?
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
            Text("Session moved")
                .font(.headline)
            Text(detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Remove Pane", role: .destructive, action: onRemove)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var detailText: String {
        if let name = targetWorkspaceName {
            return "`\(worktreeID)` is now running in \(name)."
        }
        return "`\(worktreeID)` is now running in another workspace."
    }
}
