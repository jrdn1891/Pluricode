import Foundation

struct PluriBlock: Identifiable, Equatable, Codable {
    enum Kind: Equatable, Codable {
        case user
        case event
        case text
        case tool(name: String)
        case error
    }

    var id = UUID()
    var kind: Kind
    var content: String
}

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

struct PluriProposalItem: Identifiable, Equatable, Codable {
    var id = UUID()
    let repoName: String
    let branch: String
    let prompt: String
}

struct PluriChatState: Equatable, Codable {
    var blocks: [PluriBlock] = []
    var isRunning = false
    var tasks: [PluriTask] = []
    var proposal: [PluriProposalItem]?
    var liveWorkers: Set<String> = []
}

enum PluriClientMessage: Codable {
    case send(String)
    case interrupt
    case clear
    case approveProposal
    case declineProposal
    case reply(taskID: String, text: String)
    case redispatch(taskID: String)
    case focusPane(taskID: String)
}

enum PluriServerMessage: Codable {
    case state(PluriChatState)
}
