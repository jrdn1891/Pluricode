import SwiftUI

struct TranscriptView: View {
    let transcript: ChatTranscript

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if transcript.messages.isEmpty {
                        EmptyTranscriptView()
                            .padding(.top, 40)
                    }
                    ForEach(transcript.messages) { message in
                        MessageRow(message: message)
                            .id(message.id)
                    }
                    if let err = transcript.lastError {
                        ErrorRow(text: err)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchor)
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: transcript.messages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: lastMessageHash) { _, _ in scrollToBottom(proxy) }
            .onAppear { scrollToBottom(proxy) }
        }
    }

    private var lastMessageHash: Int {
        guard let last = transcript.messages.last else { return 0 }
        var hasher = Hasher()
        for part in last.parts {
            switch part {
            case .text(let s): hasher.combine(s.count)
            case .toolUse(let tu):
                hasher.combine(tu.name)
                hasher.combine(tu.input.count)
                hasher.combine(tu.result?.count ?? 0)
                hasher.combine(tu.status)
            }
        }
        hasher.combine(last.complete)
        return hasher.finalize()
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
        }
    }

    private static let bottomAnchor = "transcript-bottom"
}

private struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            UserBubble(text: text)
        case .assistant:
            AssistantMessage(parts: message.parts, streaming: !message.complete)
        }
    }

    private var text: String {
        message.parts.compactMap {
            if case .text(let t) = $0 { return t } else { return nil }
        }.joined()
    }
}

private struct UserBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 40)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.secondary.opacity(0.14))
                )
                .frame(maxWidth: 520, alignment: .trailing)
        }
    }
}

private struct AssistantMessage: View {
    let parts: [MessagePart]
    let streaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if parts.isEmpty && streaming {
                ThinkingDots()
            }
            ForEach(parts) { part in
                switch part {
                case .text(let t):
                    MarkdownText(text: t)
                case .toolUse(let tu):
                    ToolUseChip(toolUse: tu)
                }
            }
            if streaming && !parts.isEmpty {
                StreamingCursor()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ThinkingDots: View {
    @State private var phase: Int = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .opacity(phase == i ? 1 : 0.3)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { timer in
                phase = (phase + 1) % 3
                if Task.isCancelled { timer.invalidate() }
            }
        }
    }
}

private struct StreamingCursor: View {
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(Color.primary)
            .frame(width: 7, height: 14)
            .opacity(visible ? 0.7 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                    visible.toggle()
                }
            }
    }
}

private struct ToolUseChip: View {
    let toolUse: ToolUse
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { expanded.toggle() }) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(iconColor)
                    Text(toolUse.name)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                    if toolUse.status == .running {
                        SmallSpinner()
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded, let result = toolUse.result, !result.isEmpty {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(result)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .lineLimit(8)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var icon: String {
        switch toolUse.status {
        case .running: "wrench.and.screwdriver.fill"
        case .ok: "checkmark"
        case .failed: "xmark"
        }
    }

    private var iconColor: Color {
        switch toolUse.status {
        case .running: .orange
        case .ok: .green
        case .failed: .red
        }
    }
}

private struct SmallSpinner: View {
    @State private var angle: Double = 0
    var body: some View {
        Image(systemName: "circle.dotted")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
    }
}

private struct ErrorRow: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
        )
    }
}

private struct EmptyTranscriptView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How can I help?")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Ask anything. I have access to this worktree.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
