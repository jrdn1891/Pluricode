import Foundation
import Observation

struct WorkerState: Equatable {
    var status: WorkerStatus
    var message: String?
    var activity: String?
    var changedAt: Date
    var lastResponse: String?
}

@MainActor
@Observable
final class PluriMonitor {
    private(set) var statuses: [String: WorkerState] = [:]
    var onWaiting: ((String) -> Void)?

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
        let transcript_path: String?
        let message: String?
        let tool_name: String?
        let tool_input: ToolInput?

        struct ToolInput: Decodable {
            let file_path: String?
            let command: String?
        }
    }

    private func handle(_ event: HookEvent) {
        let path = URL(fileURLWithPath: event.cwd).standardizedFileURL.path
        if event.hook_event_name == "SessionEnd" {
            statuses.removeValue(forKey: path)
            return
        }
        let previousStatus = statuses[path]?.status
        let status: WorkerStatus
        switch event.hook_event_name {
        case "UserPromptSubmit", "PreToolUse", "PostToolUse": status = .running
        case "Notification": status = previousStatus == .done ? .done : .waiting
        case "Stop": status = .done
        default: return
        }
        let statusChanged = previousStatus != status
        var state = statuses[path] ?? WorkerState(status: status, message: nil, activity: nil, changedAt: Date(), lastResponse: nil)
        state.status = status
        switch event.hook_event_name {
        case "PreToolUse": state.activity = Self.activity(for: event)
        case "PostToolUse": state.activity = nil
        case "UserPromptSubmit": state.activity = nil; state.message = nil
        case "Notification": state.message = status == .waiting ? event.message : nil
        case "Stop": state.activity = nil
        default: break
        }
        if statusChanged { state.changedAt = Date() }
        if event.hook_event_name == "Stop" || event.hook_event_name == "Notification",
           let transcript = event.transcript_path {
            loadResponse(transcriptPath: transcript, worktreePath: path)
        }
        guard statuses[path] != state else { return }
        statuses[path] = state
        if statusChanged, status == .waiting { onWaiting?(path) }
        if statusChanged, let task = registry.updateStatus(status, message: event.message, atWorktreePath: path), status == .done {
            session.postEvent("[worker update] \(task.repoName) / \(task.branch): done — the worker finished its turn.")
        }
    }

    private func loadResponse(transcriptPath: String, worktreePath: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let url = URL(fileURLWithPath: transcriptPath)
            let delays: [TimeInterval] = [0, 0.2, 0.4, 0.6, 0.8, 1, 1, 1.5, 1.5, 2]
            for delay in delays {
                if delay > 0 { Thread.sleep(forTimeInterval: delay) }
                guard let text = TranscriptReader.lastAssistantText(at: url) else { continue }
                Task { @MainActor [weak self] in
                    guard let self, var state = self.statuses[worktreePath] else { return }
                    state.lastResponse = text
                    self.statuses[worktreePath] = state
                }
                return
            }
        }
    }

    private static func activity(for event: HookEvent) -> String? {
        guard let tool = event.tool_name else { return nil }
        let file = event.tool_input?.file_path.map { ($0 as NSString).lastPathComponent }
        switch tool {
        case "Edit", "MultiEdit", "Write", "NotebookEdit":
            return file.map { "Editing \($0)" } ?? "Editing"
        case "Read", "NotebookRead":
            return file.map { "Reading \($0)" } ?? "Reading"
        case "Bash":
            guard let command = event.tool_input?.command else { return "Running command" }
            let firstLine = command.split(separator: "\n").first.map(String.init) ?? command
            return "Running " + (firstLine.count > 36 ? firstLine.prefix(36) + "…" : firstLine)
        case "Grep", "Glob":
            return "Searching"
        case "Task":
            return "Delegating"
        case "WebFetch", "WebSearch":
            return "Browsing"
        default:
            return tool
        }
    }
}
