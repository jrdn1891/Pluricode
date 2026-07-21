import AppKit
import SwiftUI
import UserNotifications
import Observation

final class NotchHostingView: NSHostingView<NotchView> {
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class NotchController: NSObject {
    private let store: WorkspaceStore
    private let monitor: PluriMonitor
    private let model = NotchModel()
    private var panel: NSPanel?

    init(store: WorkspaceStore, monitor: PluriMonitor) {
        self.store = store
        self.monitor = monitor
        super.init()
    }

    func install(enabled: Bool) {
        if panel == nil {
            buildPanel()
            monitor.onWaiting = { [weak self] path in self?.agentWentWaiting(path) }
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(screenChanged),
                name: NSApplication.didChangeScreenParametersNotification,
                object: nil
            )
            trackModel()
        }
        apply(enabled: enabled)
    }

    func apply(enabled: Bool) {
        guard let panel else { return }
        if enabled {
            layout()
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    private func buildPanel() {
        let hosting = NotchHostingView(rootView: NotchView(store: store, monitor: monitor, model: model))
        hosting.autoresizingMask = [.width, .height]
        let panel = NotchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.level = .screenSaver
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.contentView = hosting
        self.panel = panel
    }

    private func trackModel() {
        withObservationTracking {
            _ = model.selectedAgentID
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.model.selectedAgentID != nil {
                    self.panel?.makeKeyAndOrderFront(nil)
                }
                self.trackModel()
            }
        }
    }

    @objc private func screenChanged() {
        layout()
    }

    private func layout() {
        guard let panel, let screen = notchScreen() else { return }
        let hasNotch = screen.safeAreaInsets.top > 0
        let topInset = hasNotch
            ? screen.safeAreaInsets.top
            : screen.frame.maxY - screen.visibleFrame.maxY
        let left = screen.auxiliaryTopLeftArea?.width ?? 0
        let right = screen.auxiliaryTopRightArea?.width ?? 0
        let cameraWidth = hasNotch ? screen.frame.width - left - right : 0
        model.geometry = NotchGeometry(topInset: topInset, hasNotch: hasNotch, cameraWidth: cameraWidth)

        let width = NotchMetrics.expandedBodyWidth + NotchMetrics.expandedTopRadius * 2 + 40
        let height = topInset + NotchMetrics.focusedContentHeight + 40
        let frame = NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
        panel.setFrame(frame, display: true)
    }

    private func notchScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    private func agentWentWaiting(_ path: String) {
        guard let row = agentRow(forPath: path) else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(row.branch) needs your input"
        if let message = monitor.statuses[path]?.message, !message.isEmpty {
            content.body = message
        }
        content.sound = .default
        content.userInfo = ["repoID": row.repoID.uuidString, "branch": row.branch]
        let request = UNNotificationRequest(identifier: path, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func agentRow(forPath path: String) -> AgentRow? {
        let overview = AgentOverview.build(workspaces: store.workspaces, statuses: monitor.statuses)
        for group in overview.groups {
            if let row = group.rows.first(where: { $0.id == path }) { return row }
        }
        return nil
    }
}

extension NotchController: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        completionHandler()
        guard let idString = info["repoID"] as? String,
              let repoID = UUID(uuidString: idString),
              let branch = info["branch"] as? String else { return }
        Task { @MainActor [weak self] in
            self?.store.focusWorkerPane(repoID: repoID, branch: branch)
        }
    }
}
