import Foundation
import Observation

struct ChatMessage: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var parts: [MessagePart]
    var complete: Bool
}

enum MessagePart: Identifiable {
    case text(String)
    case toolUse(ToolUse)

    var id: String {
        switch self {
        case .text: "text"
        case .toolUse(let tu): tu.id.uuidString
        }
    }
}

struct ToolUse: Identifiable {
    let id = UUID()
    var name: String
    var input: String
    var result: String?
    var status: Status = .running
    enum Status { case running, ok, failed }
}

@Observable
final class ChatTranscript {
    private(set) var messages: [ChatMessage] = []
    private(set) var isStreaming: Bool = false
    var lastError: String?

    func appendUser(_ text: String) {
        messages.append(ChatMessage(role: .user, parts: [.text(text)], complete: true))
    }

    func startAssistant() {
        messages.append(ChatMessage(role: .assistant, parts: [], complete: false))
        isStreaming = true
    }

    func appendAssistantText(_ delta: String) {
        guard let idx = lastAssistantIndex() else { return }
        var msg = messages[idx]
        if let last = msg.parts.indices.last,
           case .text(let existing) = msg.parts[last] {
            msg.parts[last] = .text(existing + delta)
        } else {
            msg.parts.append(.text(delta))
        }
        messages[idx] = msg
    }

    func appendToolUse(_ tu: ToolUse) {
        guard let idx = lastAssistantIndex() else { return }
        var msg = messages[idx]
        msg.parts.append(.toolUse(tu))
        messages[idx] = msg
    }

    func updateToolResult(id: UUID, result: String, ok: Bool) {
        for mi in messages.indices {
            for pi in messages[mi].parts.indices {
                if case .toolUse(var tu) = messages[mi].parts[pi], tu.id == id {
                    tu.result = result
                    tu.status = ok ? .ok : .failed
                    messages[mi].parts[pi] = .toolUse(tu)
                    return
                }
            }
        }
    }

    func completeAssistant() {
        guard let idx = lastAssistantIndex() else {
            isStreaming = false
            return
        }
        var msg = messages[idx]
        msg.complete = true
        messages[idx] = msg
        isStreaming = false
    }

    func reset() {
        messages.removeAll()
        isStreaming = false
        lastError = nil
    }

    private func lastAssistantIndex() -> Int? {
        for i in messages.indices.reversed() where messages[i].role == .assistant && !messages[i].complete {
            return i
        }
        return nil
    }
}
