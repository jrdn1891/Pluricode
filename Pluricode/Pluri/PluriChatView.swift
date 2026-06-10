import SwiftUI

struct PluriChatView: View {
    let session: PluriSession
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if session.blocks.isEmpty {
                emptyState
            } else {
                transcript
            }
            Divider()
            inputBar
        }
        .frame(minWidth: 380, minHeight: 420)
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
