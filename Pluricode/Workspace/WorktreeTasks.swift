import Foundation
import Observation

struct TaskItem: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var done: Bool
}

@MainActor
@Observable
final class WorktreeTaskStore {
    private var items: [String: [TaskItem]] = [:]
    @ObservationIgnored private var watchers: [String: DirectoryWatcher] = [:]

    nonisolated static func fileURL(worktreePath: String) -> URL {
        URL(fileURLWithPath: worktreePath)
            .appendingPathComponent(".pluricode", isDirectory: true)
            .appendingPathComponent("TASKS.md")
    }

    func tasks(at path: String) -> [TaskItem] {
        items[path] ?? []
    }

    func openCount(at path: String) -> Int {
        tasks(at: path).filter { !$0.done }.count
    }

    func open(path: String) {
        guard watchers[path] == nil else { return }
        let watcher = DirectoryWatcher()
        watchers[path] = watcher
        reload(path: path)
        watcher.watch(Self.fileURL(worktreePath: path).deletingLastPathComponent()) { [weak self] in
            self?.reload(path: path)
        }
    }

    func add(path: String, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items[path, default: []].insert(TaskItem(title: trimmed, done: false), at: 0)
        write(path: path)
    }

    func toggle(path: String, taskID: UUID) {
        guard let idx = items[path]?.firstIndex(where: { $0.id == taskID }) else { return }
        items[path]?[idx].done.toggle()
        write(path: path)
    }

    func updateTitle(path: String, taskID: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = items[path]?.firstIndex(where: { $0.id == taskID }) else { return }
        items[path]?[idx].title = trimmed
        write(path: path)
    }

    func remove(path: String, taskID: UUID) {
        items[path]?.removeAll { $0.id == taskID }
        write(path: path)
    }

    func move(path: String, taskID: UUID, before targetID: UUID?) {
        guard taskID != targetID,
              let fromIdx = items[path]?.firstIndex(where: { $0.id == taskID }) else { return }
        let task = items[path]!.remove(at: fromIdx)
        if let targetID, let toIdx = items[path]!.firstIndex(where: { $0.id == targetID }) {
            items[path]!.insert(task, at: toIdx)
        } else {
            items[path]!.append(task)
        }
        write(path: path)
    }

    func clearCompleted(path: String) {
        items[path]?.removeAll { $0.done }
        write(path: path)
    }

    private func reload(path: String) {
        let text = (try? String(contentsOf: Self.fileURL(worktreePath: path), encoding: .utf8)) ?? ""
        let parsed = Self.parse(text)
        guard Self.render(parsed) != Self.render(tasks(at: path)) else { return }
        items[path] = parsed
    }

    private func write(path: String) {
        let url = Self.fileURL(worktreePath: path)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Self.render(tasks(at: path)).write(to: url, atomically: true, encoding: .utf8)
    }

    static func parse(_ text: String) -> [TaskItem] {
        text.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.count > 5, trimmed.hasPrefix("- [") else { return nil }
            let mark = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 3)]
            guard trimmed[trimmed.index(trimmed.startIndex, offsetBy: 4)] == "]" else { return nil }
            let title = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return nil }
            return TaskItem(title: title, done: mark == "x" || mark == "X")
        }
    }

    static func render(_ items: [TaskItem]) -> String {
        guard !items.isEmpty else { return "" }
        return items.map { "- [\($0.done ? "x" : " ")] \($0.title)\n" }.joined()
    }
}
