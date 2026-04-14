import Foundation
import SwiftUI
import simd

struct CanvasNode: Identifiable, Codable {
    let id: UUID
    var position: SIMD2<Float>
    var size: SIMD2<Float>
    var kind: NodeKind
}

enum NodeKind: Codable {
    case terminal(TerminalNodeData)
    case taskCard(TaskCardData)

    var defaultSize: SIMD2<Float> {
        switch self {
        case .terminal: SIMD2<Float>(400, 300)
        case .taskCard: SIMD2<Float>(250, 100)
        }
    }

    private enum CodingKeys: String, CodingKey { case type, data }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .terminal(let d):
            try c.encode("terminal", forKey: .type)
            try c.encode(d, forKey: .data)
        case .taskCard(let d):
            try c.encode("taskCard", forKey: .type)
            try c.encode(d, forKey: .data)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "terminal": self = .terminal(try c.decode(TerminalNodeData.self, forKey: .data))
        case "taskCard": self = .taskCard(try c.decode(TaskCardData.self, forKey: .data))
        default: self = .taskCard(TaskCardData())
        }
    }
}

struct TerminalNodeData: Codable {
    enum Status: String, Codable {
        case idle, working, waiting, done, error

        var color: Color {
            switch self {
            case .idle: .gray
            case .working: .orange
            case .waiting: .yellow
            case .done: .green
            case .error: .red
            }
        }
    }
    var status: Status = .idle
    var profileID: UUID?
    var worktreePath: String?
    var branchName: String?
    var agentName: String = "Claude Code"
    var startupScript: String?
}

struct TaskCardData: Codable {
    enum Status: String, Codable, CaseIterable {
        case draft, ready, inProgress, done, failed, flagged
    }
    var title: String = "New Task"
    var body: String = ""
    var result: String = ""
    var outcome: String = ""
    var status: Status = .draft
    var createdAt: Date = Date()
    var startedAt: Date?
    var completedAt: Date?

    mutating func transition(to newStatus: Status) {
        status = newStatus
        switch newStatus {
        case .inProgress:
            startedAt = Date()
            completedAt = nil
        case .done, .failed:
            completedAt = Date()
            if startedAt == nil { startedAt = Date() }
        case .flagged:
            break
        case .draft, .ready:
            startedAt = nil
            completedAt = nil
        }
    }
}

extension SIMD2: Encodable where Scalar: Encodable {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(x)
        try c.encode(y)
    }
}

extension SIMD2: Decodable where Scalar: Decodable {
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        self.init(try c.decode(Scalar.self), try c.decode(Scalar.self))
    }
}
