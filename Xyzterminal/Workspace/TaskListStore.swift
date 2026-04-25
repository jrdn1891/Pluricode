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
final class TaskListStore {
    var lists: [TaskList] = []
    private var dirty: Set<UUID> = []
    private var saveTask: Task<Void, Never>?

    init() {
        load()
    }

    deinit {
        saveTask?.cancel()
        flush()
    }

    static var dir: URL {
        Workspace.rootDir.appendingPathComponent("tasklists", isDirectory: true)
    }

    private func url(for id: UUID) -> URL {
        Self.dir.appendingPathComponent("\(id.uuidString).json")
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
        sort()
        mark(list.id)
        return list.id
    }

    func renameList(id: UUID, name: String) {
        guard let idx = lists.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lists[idx].name = trimmed
        sort()
        mark(id)
    }

    func removeList(id: UUID) {
        lists.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: url(for: id))
        dirty.remove(id)
    }

    func addTask(listID: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = lists.firstIndex(where: { $0.id == listID }) else { return }
        lists[idx].items.insert(TaskItem(title: trimmed), at: 0)
        mark(listID)
    }

    func toggleTask(listID: UUID, taskID: UUID) {
        guard let listIdx = lists.firstIndex(where: { $0.id == listID }),
              let taskIdx = lists[listIdx].items.firstIndex(where: { $0.id == taskID }) else { return }
        lists[listIdx].items[taskIdx].done.toggle()
        mark(listID)
    }

    func updateTaskTitle(listID: UUID, taskID: UUID, title: String) {
        guard let listIdx = lists.firstIndex(where: { $0.id == listID }),
              let taskIdx = lists[listIdx].items.firstIndex(where: { $0.id == taskID }) else { return }
        lists[listIdx].items[taskIdx].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        mark(listID)
    }

    func removeTask(listID: UUID, taskID: UUID) {
        guard let listIdx = lists.firstIndex(where: { $0.id == listID }) else { return }
        lists[listIdx].items.removeAll { $0.id == taskID }
        mark(listID)
    }

    func moveTask(listID: UUID, taskID: UUID, before targetID: UUID?) {
        guard taskID != targetID,
              let listIdx = lists.firstIndex(where: { $0.id == listID }),
              let fromIdx = lists[listIdx].items.firstIndex(where: { $0.id == taskID }) else { return }
        let task = lists[listIdx].items.remove(at: fromIdx)
        let insertIdx: Int
        if let targetID, let toIdx = lists[listIdx].items.firstIndex(where: { $0.id == targetID }) {
            insertIdx = toIdx
        } else {
            insertIdx = lists[listIdx].items.count
        }
        lists[listIdx].items.insert(task, at: insertIdx)
        mark(listID)
    }

    func clearCompleted(listID: UUID) {
        guard let listIdx = lists.firstIndex(where: { $0.id == listID }) else { return }
        lists[listIdx].items.removeAll { $0.done }
        mark(listID)
    }

    private func mark(_ id: UUID) {
        dirty.insert(id)
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            self.flush()
        }
    }

    private func flush() {
        guard !dirty.isEmpty else { return }
        try? FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        for id in dirty {
            guard let list = lists.first(where: { $0.id == id }),
                  let data = try? encoder.encode(list) else { continue }
            try? data.write(to: url(for: id), options: .atomic)
        }
        dirty.removeAll()
    }

    private func sort() {
        lists.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func load() {
        let dir = Self.dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        lists = urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(TaskList.self, from: data)
            }
        sort()
    }
}
