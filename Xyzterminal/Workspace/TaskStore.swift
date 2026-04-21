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

struct TaskList: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var items: [TaskItem]

    init(id: UUID = UUID(), name: String, items: [TaskItem] = []) {
        self.id = id
        self.name = name
        self.items = items
    }
}

@Observable
final class TaskStore {
    var lists: [TaskList] = []
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
              let decoded = try? JSONDecoder().decode([TaskList].self, from: data) else { return }
        lists = decoded
    }

    func save() {
        let url = tasksURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(lists) else { return }
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

    func list(id: UUID) -> TaskList? {
        lists.first { $0.id == id }
    }

    @discardableResult
    func addList(name: String) -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Untitled" : trimmed
        let list = TaskList(name: finalName)
        lists.append(list)
        scheduleSave()
        return list.id
    }

    func renameList(id: UUID, name: String) {
        guard let idx = lists.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lists[idx].name = trimmed
        scheduleSave()
    }

    func removeList(id: UUID) {
        lists.removeAll { $0.id == id }
        scheduleSave()
    }

    func addTask(listID: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = lists.firstIndex(where: { $0.id == listID }) else { return }
        lists[idx].items.insert(TaskItem(title: trimmed), at: 0)
        scheduleSave()
    }

    func toggleTask(listID: UUID, taskID: UUID) {
        guard let listIdx = lists.firstIndex(where: { $0.id == listID }),
              let taskIdx = lists[listIdx].items.firstIndex(where: { $0.id == taskID }) else { return }
        lists[listIdx].items[taskIdx].done.toggle()
        scheduleSave()
    }

    func updateTaskTitle(listID: UUID, taskID: UUID, title: String) {
        guard let listIdx = lists.firstIndex(where: { $0.id == listID }),
              let taskIdx = lists[listIdx].items.firstIndex(where: { $0.id == taskID }) else { return }
        lists[listIdx].items[taskIdx].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        scheduleSave()
    }

    func removeTask(listID: UUID, taskID: UUID) {
        guard let listIdx = lists.firstIndex(where: { $0.id == listID }) else { return }
        lists[listIdx].items.removeAll { $0.id == taskID }
        scheduleSave()
    }

    func clearCompleted(listID: UUID) {
        guard let listIdx = lists.firstIndex(where: { $0.id == listID }) else { return }
        lists[listIdx].items.removeAll { $0.done }
        scheduleSave()
    }
}

@Observable
final class TaskStoreRegistry {
    private var stores: [String: TaskStore] = [:]

    func store(for repoPath: URL) -> TaskStore {
        let key = repoPath.standardizedFileURL.path
        if let existing = stores[key] { return existing }
        let store = TaskStore(repoPath: repoPath)
        stores[key] = store
        return store
    }
}
