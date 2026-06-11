import SwiftUI

extension WorkerStatus {
    var color: Color {
        switch self {
        case .running: .blue
        case .waiting: .orange
        case .done: .green
        }
    }
}

struct PluriChatView: View {
    let session: PluriSession
    let bridge: PluriBridge
    let registry: PluriTaskRegistry
    @State private var draft = ""
    @State private var openTaskID: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        Group {
            if let id = openTaskID, let task = registry.tasks.first(where: { $0.id == id }) {
                TaskThreadView(task: task, bridge: bridge, onBack: { openTaskID = nil })
            } else {
                chat
            }
        }
        .frame(minWidth: 380, minHeight: 420)
    }

    private var chat: some View {
        VStack(spacing: 0) {
            if !registry.tasks.isEmpty {
                taskChips
                Divider()
            }
            if session.blocks.isEmpty {
                emptyState
            } else {
                transcript
            }
            if registry.proposal != nil {
                proposalCard
            }
            Divider()
            inputBar
        }
        .toolbar {
            ToolbarItem {
                Button {
                    session.clear()
                    inputFocused = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .help("New conversation")
                .disabled(session.blocks.isEmpty || session.isRunning)
            }
        }
        .onAppear { inputFocused = true }
    }

    private var taskChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(registry.tasks.sorted { $0.updatedAt > $1.updatedAt }) { task in
                    Button {
                        openTaskID = task.id
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(task.status.color)
                                .frame(width: 6, height: 6)
                            Text(task.branch)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("\(task.repoName) — \(task.status.rawValue)")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private var proposalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            let items = registry.proposal ?? []
            Label("Pluri proposes \(items.count) task\(items.count == 1 ? "" : "s")", systemImage: "tray.full")
                .font(.system(size: 12, weight: .semibold))
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(item.repo.name) · \(item.branch)")
                        .font(.system(size: 11, weight: .medium))
                    Text(item.prompt)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            HStack {
                Spacer()
                Button("Decline") {
                    registry.proposal = nil
                    session.postEvent("[approval] The user declined the proposed tasks.")
                }
                Button("Approve & Dispatch") {
                    let count = registry.proposal?.count ?? 0
                    bridge.approveProposal()
                    session.postEvent("[approval] The user approved the proposal — \(count) worker\(count == 1 ? "" : "s") dispatched.")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(10)
        .background(PluriMascotView.coral.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(PluriMascotView.coral.opacity(0.3)))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            PluriMascotView(size: 44)
            Text("Describe what you want to work on")
                .font(.title3)
            Text("Pluri sets up worktrees, drafts task briefs, and dispatches worker agents into your workspace.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(session.blocks) { block in
                        PluriBlockRow(block: block)
                    }
                    if session.isRunning {
                        HStack(spacing: 8) {
                            PluriMascotView(size: 16)
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(14)
            }
            .onChange(of: session.blocks) {
                proxy.scrollTo("bottom")
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask Pluri…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($inputFocused)
                .onSubmit(sendDraft)
            if session.isRunning {
                Button(action: session.interrupt) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Stop")
            } else {
                Button(action: sendDraft) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(draft.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(PluriMascotView.coral))
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Send")
            }
        }
        .padding(10)
    }

    private func sendDraft() {
        guard !session.isRunning else { return }
        session.send(draft)
        draft = ""
    }
}

private struct TaskThreadView: View {
    let task: PluriTask
    let bridge: PluriBridge
    let onBack: () -> Void
    @State private var reply = ""
    @FocusState private var replyFocused: Bool

    private var hasLiveWorker: Bool {
        bridge.workerSession(for: task) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        Text(task.brief)
                            .font(.system(size: 12))
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        ForEach(task.updates) { update in
                            UpdateRow(update: update)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(12)
                }
                .onChange(of: task.updates) {
                    proxy.scrollTo("bottom")
                }
            }
            Divider()
            replyBar
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            Circle()
                .fill(task.status.color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(task.branch)
                    .font(.system(size: 12, weight: .semibold))
                Text(task.repoName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if hasLiveWorker {
                Button("Open Pane") {
                    bridge.focusWorkerPane(for: task)
                }
            } else {
                Button("Re-dispatch") {
                    _ = bridge.redispatch(task)
                }
                .help("Start a fresh worker on this worktree with the original brief")
            }
        }
        .padding(10)
    }

    private var replyBar: some View {
        HStack(spacing: 8) {
            if hasLiveWorker {
                TextField("Reply to the worker…", text: $reply)
                    .textFieldStyle(.plain)
                    .focused($replyFocused)
                    .onSubmit(sendReply)
                Button(action: sendReply) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(reply.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(PluriMascotView.coral))
                }
                .buttonStyle(.plain)
                .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Send into the worker's terminal")
            } else {
                Text("No live worker session — re-dispatch to continue this task.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
    }

    private func sendReply() {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard bridge.reply(to: task, text: text) else { return }
        reply = ""
    }
}

private struct UpdateRow: View {
    let update: PluriTaskUpdate

    var body: some View {
        if update.kind == .reply {
            HStack {
                Spacer(minLength: 40)
                Text(update.message ?? "")
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(PluriMascotView.coral.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(update.date, format: .dateTime.hour().minute())
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var icon: String {
        switch update.kind {
        case .dispatched: "paperplane.fill"
        case .running: "play.fill"
        case .waiting: "hourglass"
        case .done: "checkmark.circle.fill"
        case .reply: "arrow.up"
        }
    }

    private var text: String {
        switch update.kind {
        case .dispatched: "Dispatched"
        case .running: "Working"
        case .waiting: update.message.map { "Waiting — \($0)" } ?? "Waiting for permission or input"
        case .done: "Finished its turn"
        case .reply: update.message ?? ""
        }
    }
}

private struct PluriBlockRow: View {
    let block: PluriBlock

    var body: some View {
        switch block.kind {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(block.content)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(PluriMascotView.coral.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            }
        case .event:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(block.content)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        case .text:
            Text(markdown(block.content))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .tool(let name):
            HStack(spacing: 6) {
                Image(systemName: "wrench.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                Text(block.content.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.08), in: Capsule())
        case .error:
            Text(block.content)
                .textSelection(.enabled)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
