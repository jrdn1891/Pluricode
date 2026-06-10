import Foundation
import Observation

enum WorkerStatus: String, Codable {
    case running, waiting, done
}

struct PluriTaskUpdate: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        case dispatched, running, waiting, done, reply
    }

    let id: UUID
    let date: Date
    let kind: Kind
    let message: String?

    init(kind: Kind, message: String? = nil) {
        self.id = UUID()
        self.date = Date()
        self.kind = kind
        self.message = message
    }
}

struct PluriTask: Codable, Hashable, Identifiable {
    let repo: String
    let branch: String
    let brief: String
    var status: WorkerStatus
    let dispatchedAt: Date
    var updatedAt: Date
    var updates: [PluriTaskUpdate]

    var id: String { "\(repo)#\(branch)" }

    var repoName: String {
        URL(fileURLWithPath: repo).lastPathComponent
    }

    var worktreePath: String {
        URL(fileURLWithPath: repo)
            .appendingPathComponent(".pluricode/worktrees/\(branch)")
            .standardizedFileURL.path
    }
}

struct ProposalItem: Identifiable {
    let id = UUID()
    let repo: RepoEntry
    let branch: String
    let prompt: String
}

@MainActor
@Observable
final class PluriTaskRegistry {
    private(set) var tasks: [PluriTask]
    var proposal: [ProposalItem]?

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
            updatedAt: Date(),
            updates: [PluriTaskUpdate(kind: .dispatched)]
        ))
        save()
    }

    func remove(repo: String, branch: String) {
        tasks.removeAll { $0.repo == repo && $0.branch == branch }
        save()
    }

    func updateStatus(_ status: WorkerStatus, message: String? = nil, atWorktreePath path: String) -> PluriTask? {
        guard let idx = tasks.firstIndex(where: { $0.worktreePath == path }),
              tasks[idx].status != status else { return nil }
        tasks[idx].status = status
        tasks[idx].updatedAt = Date()
        tasks[idx].updates.append(PluriTaskUpdate(kind: PluriTaskUpdate.Kind(rawValue: status.rawValue)!, message: message))
        save()
        return tasks[idx]
    }

    func appendReply(_ text: String, taskID: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[idx].updatedAt = Date()
        tasks[idx].updates.append(PluriTaskUpdate(kind: .reply, message: text))
        save()
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
