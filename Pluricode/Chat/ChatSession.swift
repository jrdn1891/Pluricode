import Foundation
import Observation

@Observable
final class ChatSession {
    let transcript = ChatTranscript()
    private let worktreePath: String
    private(set) var sessionID: UUID
    private var sessionEstablished: Bool
    private var process: Process?
    private var stdoutBuffer = Data()
    private var toolUseIDByClaudeID: [String: UUID] = [:]

    init(worktreePath: String) {
        self.worktreePath = worktreePath
        let config = WorktreeConfig.load(at: worktreePath)
        if let existing = config.chatSessionID {
            self.sessionID = existing
            self.sessionEstablished = true
        } else {
            let new = UUID()
            self.sessionID = new
            self.sessionEstablished = false
        }
    }

    var isRunning: Bool { process?.isRunning ?? false }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRunning else { return }
        guard let claude = Self.claudePath else {
            transcript.lastError = "claude CLI not found in PATH"
            return
        }
        transcript.appendUser(trimmed)
        transcript.startAssistant()
        spawn(prompt: trimmed, executable: claude)
    }

    func cancel() {
        process?.terminate()
    }

    private func spawn(prompt: String, executable: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.currentDirectoryURL = URL(fileURLWithPath: worktreePath)
        let sessionFlag = sessionEstablished
            ? ["--resume", sessionID.uuidString]
            : ["--session-id", sessionID.uuidString]
        task.arguments = [
            "--print",
            "--output-format", "stream-json",
            "--include-partial-messages",
            "--verbose",
            "--permission-mode", "bypassPermissions",
        ] + sessionFlag + [prompt]

        var env = ProcessInfo.processInfo.environment
        env["FORCE_COLOR"] = "0"
        env["NO_COLOR"] = "1"
        task.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr
        task.standardInput = Pipe()

        stdoutBuffer.removeAll(keepingCapacity: true)
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.consumeStdout(data) }
        }

        var stderrBuffer = Data()
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stderrBuffer.append(data)
        }

        task.terminationHandler = { [weak self] proc in
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            let stderrText = String(data: stderrBuffer, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                self?.finish(exitCode: proc.terminationStatus, stderr: stderrText)
            }
        }

        do {
            try task.run()
            self.process = task
        } catch {
            transcript.lastError = "Failed to launch claude: \(error.localizedDescription)"
            transcript.completeAssistant()
        }
    }

    private func consumeStdout(_ data: Data) {
        stdoutBuffer.append(data)
        while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = stdoutBuffer.subdata(in: stdoutBuffer.startIndex..<newline)
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...newline)
            if let str = String(data: line, encoding: .utf8), !str.isEmpty {
                handleEvent(str)
            }
        }
    }

    private func handleEvent(_ line: String) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        guard let type = obj["type"] as? String else { return }
        switch type {
        case "stream_event":
            handleStreamEvent(obj["event"] as? [String: Any])
        case "user":
            handleUserMessage(obj["message"] as? [String: Any])
        case "result":
            handleResult(obj)
        default:
            break
        }
    }

    private func handleStreamEvent(_ event: [String: Any]?) {
        guard let event, let type = event["type"] as? String else { return }
        switch type {
        case "content_block_start":
            if let block = event["content_block"] as? [String: Any],
               let blockType = block["type"] as? String {
                if blockType == "tool_use",
                   let claudeID = block["id"] as? String,
                   let name = block["name"] as? String {
                    let tu = ToolUse(name: name, input: "")
                    toolUseIDByClaudeID[claudeID] = tu.id
                    transcript.appendToolUse(tu)
                }
            }
        case "content_block_delta":
            if let delta = event["delta"] as? [String: Any],
               let dtype = delta["type"] as? String {
                if dtype == "text_delta", let text = delta["text"] as? String {
                    transcript.appendAssistantText(text)
                }
            }
        default:
            break
        }
    }

    private func handleResult(_ obj: [String: Any]) {
        if let isError = obj["is_error"] as? Bool, isError {
            if let result = obj["result"] as? String, !result.isEmpty {
                transcript.lastError = result
            } else if transcript.lastError == nil {
                transcript.lastError = "claude reported an error"
            }
        }
    }

    private func handleUserMessage(_ message: [String: Any]?) {
        guard let message, let content = message["content"] as? [[String: Any]] else { return }
        for block in content {
            guard let type = block["type"] as? String, type == "tool_result" else { continue }
            guard let claudeID = block["tool_use_id"] as? String,
                  let localID = toolUseIDByClaudeID[claudeID] else { continue }
            let isError = (block["is_error"] as? Bool) ?? false
            let resultText: String
            if let str = block["content"] as? String {
                resultText = str
            } else if let arr = block["content"] as? [[String: Any]] {
                resultText = arr.compactMap { $0["text"] as? String }.joined(separator: "\n")
            } else {
                resultText = ""
            }
            transcript.updateToolResult(id: localID, result: resultText, ok: !isError)
        }
    }

    private func finish(exitCode: Int32, stderr: String) {
        process = nil
        if exitCode != 0, transcript.lastError == nil {
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            transcript.lastError = trimmed.isEmpty ? "claude exited with code \(exitCode)" : trimmed
        }
        if exitCode == 0 && !sessionEstablished {
            sessionEstablished = true
            var config = WorktreeConfig.load(at: worktreePath)
            config.chatSessionID = sessionID
            config.save(at: worktreePath)
        }
        transcript.completeAssistant()
    }

    private static let claudePath: String? = {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-lc", "command -v claude"]
        let out = Pipe()
        task.standardOutput = out
        task.standardError = Pipe()
        do { try task.run() } catch { return nil }
        task.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (path?.isEmpty == false) ? path : nil
    }()
}
