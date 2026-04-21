import Foundation
import Observation

struct TaskItem: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var done: Bool
    var createdAt: Date

    init(id: UUID = UUID(), title: String, done: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.done = done
        self.createdAt = createdAt
    }
}

@Observable
final class TaskStore {
    var tasks: [TaskItem] = []
    let repoPath: URL
    private var saveTask: Task<Void, Never>?

    init(repoPath: URL) {
        self.repoPath = repoPath
        load()
    }

    deinit {
        saveTask?.cancel()
        save()
    }

    private var tasksURL: URL {
        repoPath.appendingPathComponent(".xyzterminal/tasks.json")
    }

    func load() {
        guard let data = try? Data(contentsOf: tasksURL),
              let decoded = try? JSONDecoder().decode([TaskItem].self, from: data) else { return }
        tasks = decoded
    }

    func save() {
        let url = tasksURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(tasks) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            self.save()
        }
    }

    func add(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tasks.insert(TaskItem(title: trimmed), at: 0)
        scheduleSave()
    }

    func toggle(id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].done.toggle()
        scheduleSave()
    }

    func updateTitle(id: UUID, title: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        tasks[idx].title = trimmed
        scheduleSave()
    }

    func remove(id: UUID) {
        tasks.removeAll { $0.id == id }
        scheduleSave()
    }

    func clearCompleted() {
        tasks.removeAll { $0.done }
        scheduleSave()
    }
}
