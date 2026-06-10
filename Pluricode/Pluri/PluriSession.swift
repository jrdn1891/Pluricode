import Foundation

struct PluriBlock: Identifiable, Equatable {
    enum Kind: Equatable {
        case user
        case event
        case text
        case tool(name: String)
        case error
    }

    let id = UUID()
    let kind: Kind
    var content: String
}

@MainActor
@Observable
final class PluriSession {
    private(set) var blocks: [PluriBlock] = []
    private(set) var isRunning = false

    private let repoStore: RepoStore
    private var sessionID: String?
    private var process: Process?
    private var sawResult = false
    @ObservationIgnored private var pendingBlocks: [PluriBlock] = []
    @ObservationIgnored private var flushScheduled = false
    @ObservationIgnored private var queuedEvents: [String] = []

    init(repoStore: RepoStore) {
        self.repoStore = repoStore
    }

    func send(_ text: String) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isRunning else { return }
        PluriHome.prepare(repos: repoStore.repos)
        pendingBlocks.append(PluriBlock(kind: .user, content: prompt))
        blocks = pendingBlocks
        isRunning = true
        sawResult = false
        run(prompt: prompt)
    }

    func postEvent(_ text: String) {
        queuedEvents.append(text)
        flushQueuedEvents()
    }

    private func flushQueuedEvents() {
        guard !isRunning, !queuedEvents.isEmpty else { return }
        PluriHome.prepare(repos: repoStore.repos)
        for event in queuedEvents {
            pendingBlocks.append(PluriBlock(kind: .event, content: event))
        }
        let prompt = queuedEvents.joined(separator: "\n")
        queuedEvents.removeAll()
        blocks = pendingBlocks
        isRunning = true
        sawResult = false
        run(prompt: prompt)
    }

    func interrupt() {
        process?.interrupt()
    }

    func clear() {
        guard !isRunning else { return }
        pendingBlocks = []
        blocks = []
        sessionID = nil
        queuedEvents = []
    }

    private func run(prompt: String) {
        var command = "exec \(PluriSettings.shared.command) -p --output-format stream-json --include-partial-messages --verbose"
        if let sessionID {
            command += " --resume \(sessionID)"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = PluriHome.dir

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        var lineBuffer = Data()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            lineBuffer.append(data)
            while let newline = lineBuffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = lineBuffer[lineBuffer.startIndex..<newline]
                lineBuffer = lineBuffer[lineBuffer.index(after: newline)...]
                guard let event = try? JSONDecoder().decode(StreamLine.self, from: line) else { continue }
                DispatchQueue.main.async { self.handle(event) }
            }
        }

        var errorTail = Data()
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            errorTail.append(data)
        }

        process.terminationHandler = { proc in
            DispatchQueue.main.async {
                self.finish(status: proc.terminationStatus, errorOutput: String(data: errorTail, encoding: .utf8) ?? "")
            }
        }

        do {
            try process.run()
        } catch {
            pendingBlocks.append(PluriBlock(kind: .error, content: error.localizedDescription))
            blocks = pendingBlocks
            isRunning = false
            return
        }
        self.process = process
        stdin.fileHandleForWriting.write(Data(prompt.utf8))
        stdin.fileHandleForWriting.closeFile()
    }

    private func handle(_ line: StreamLine) {
        if let id = line.session_id {
            sessionID = id
        }
        switch line.type {
        case "stream_event":
            guard let event = line.event else { return }
            switch event.type {
            case "content_block_start":
                if event.content_block?.type == "tool_use", let name = event.content_block?.name {
                    pendingBlocks.append(PluriBlock(kind: .tool(name: name), content: ""))
                }
            case "content_block_delta":
                if let text = event.delta?.text {
                    appendText(text)
                } else if let json = event.delta?.partial_json {
                    appendToolInput(json)
                }
            default:
                break
            }
        case "result":
            sawResult = true
            if line.is_error == true, let result = line.result {
                pendingBlocks.append(PluriBlock(kind: .error, content: result))
            }
        default:
            break
        }
        scheduleFlush()
    }

    private func appendText(_ text: String) {
        if let last = pendingBlocks.indices.last, pendingBlocks[last].kind == .text {
            pendingBlocks[last].content += text
        } else {
            pendingBlocks.append(PluriBlock(kind: .text, content: text))
        }
    }

    private func appendToolInput(_ json: String) {
        guard let last = pendingBlocks.indices.last, case .tool = pendingBlocks[last].kind else { return }
        pendingBlocks[last].content += json
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            flushScheduled = false
            blocks = pendingBlocks
        }
    }

    private func finish(status: Int32, errorOutput: String) {
        process = nil
        isRunning = false
        if !sawResult, status != 0 {
            let detail = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            pendingBlocks.append(PluriBlock(kind: .error, content: detail.isEmpty ? "Pluri exited with status \(status)" : detail))
        }
        blocks = pendingBlocks
        flushQueuedEvents()
    }

    private struct StreamLine: Decodable {
        let type: String
        let session_id: String?
        let event: Event?
        let result: String?
        let is_error: Bool?

        struct Event: Decodable {
            let type: String
            let content_block: ContentBlock?
            let delta: Delta?
        }

        struct ContentBlock: Decodable {
            let type: String
            let name: String?
        }

        struct Delta: Decodable {
            let text: String?
            let partial_json: String?
        }
    }
}
