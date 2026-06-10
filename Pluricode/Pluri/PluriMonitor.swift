import Foundation
import Observation

@MainActor
@Observable
final class PluriMonitor {
    private(set) var statuses: [String: WorkerStatus] = [:]

    private let registry: PluriTaskRegistry
    private let session: PluriSession
    @ObservationIgnored private let watcher = DirectoryWatcher()

    init(registry: PluriTaskRegistry, session: PluriSession) {
        self.registry = registry
        self.session = session
    }

    func start() {
        watcher.watch(WorkerHooks.eventsDir) { [weak self] in self?.drain() }
        drain()
    }

    private func drain() {
        let urls = ((try? FileManager.default.contentsOfDirectory(
            at: WorkerHooks.eventsDir,
            includingPropertiesForKeys: [.creationDateKey]
        )) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { creationDate($0) < creationDate($1) }
        for url in urls {
            let data = try? Data(contentsOf: url)
            try? FileManager.default.removeItem(at: url)
            guard let data, let event = try? JSONDecoder().decode(HookEvent.self, from: data) else { continue }
            handle(event)
        }
    }

    private func creationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
    }

    private struct HookEvent: Decodable {
        let hook_event_name: String
        let cwd: String
        let message: String?
    }

    private func handle(_ event: HookEvent) {
        let path = URL(fileURLWithPath: event.cwd).standardizedFileURL.path
        let status: WorkerStatus
        switch event.hook_event_name {
        case "SessionStart", "UserPromptSubmit": status = .running
        case "Notification": status = .waiting
        case "Stop": status = .done
        case "SessionEnd":
            statuses.removeValue(forKey: path)
            return
        default:
            return
        }
        guard statuses[path] != status else { return }
        statuses[path] = status
        guard let task = registry.updateStatus(status, message: event.message, atWorktreePath: path) else { return }
        if status == .done {
            session.postEvent("[worker update] \(task.repoName) / \(task.branch): done — the worker finished its turn.")
        }
    }
}
