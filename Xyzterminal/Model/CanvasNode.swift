import Foundation
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
    enum Status: String, Codable { case idle, working, waiting, done, error }
    enum Role: String, Codable, CaseIterable { case architect, coder, reviewer, tester }
    var status: Status = .idle
    var role: Role?
    var worktreePath: String?
    var branchName: String?
    var agentName: String = "Claude Code"
    var startupScript: String?
}

struct TaskCardData: Codable {
    enum Status: String, Codable, CaseIterable { case draft, ready, inProgress, done, failed }
    var title: String = "New Task"
    var body: String = ""
    var status: Status = .draft
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
