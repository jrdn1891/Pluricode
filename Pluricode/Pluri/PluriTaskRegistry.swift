import Foundation

enum WorkerStatus: String, Codable {
    case running, waiting, done
}

struct PluriTask: Codable {
    let repo: String
    let branch: String
    let brief: String
    var status: WorkerStatus
    let dispatchedAt: Date
    var updatedAt: Date

    var worktreePath: String {
        URL(fileURLWithPath: repo)
            .appendingPathComponent(".pluricode/worktrees/\(branch)")
            .standardizedFileURL.path
    }
}

@MainActor
final class PluriTaskRegistry {
    private(set) var tasks: [PluriTask]

    private static var fileURL: URL {
        PluriHome.dir.appendingPathComponent("tasks.json")
    }

    init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: Self.fileURL),
           let loaded = try? decoder.decode([PluriTask].self, from: data) {
            tasks = loaded
        } else {
            tasks = []
        }
    }

    func register(repo: String, branch: String, brief: String) {
        tasks.removeAll { $0.repo == repo && $0.branch == branch }
        tasks.append(PluriTask(
            repo: repo,
            branch: branch,
            brief: brief,
            status: .running,
            dispatchedAt: Date(),
            updatedAt: Date()
        ))
        save()
    }

    func remove(repo: String, branch: String) {
        tasks.removeAll { $0.repo == repo && $0.branch == branch }
        save()
    }

    func updateStatus(_ status: WorkerStatus, atWorktreePath path: String) -> PluriTask? {
        guard let idx = tasks.firstIndex(where: { $0.worktreePath == path }),
              tasks[idx].status != status else { return nil }
        tasks[idx].status = status
        tasks[idx].updatedAt = Date()
        save()
        return tasks[idx]
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(tasks) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}
