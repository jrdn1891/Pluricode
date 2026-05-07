import SwiftUI

struct ChatHeader: View {
    let status: TerminalStatus
    let title: String
    let branch: String
    let repoName: String?
    let repoColor: Color?
    let profile: AgentProfile?
    let isExpanded: Bool
    let onActivate: () -> Void
    let onToggleRaw: () -> Void
    let onExpand: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            agentBadge
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(profile?.name ?? "Agent")
                        .font(.system(size: 13, weight: .semibold))
                    StatusPill(status: status)
                }
                HStack(spacing: 4) {
                    if let repoName {
                        Circle().fill(repoColor ?? .accentColor).frame(width: 6, height: 6)
                        Text(repoName)
                        Text("·").foregroundStyle(.tertiary)
                    }
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10))
                    Text(branch)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            HeaderIcon(symbol: "terminal", help: "Show raw terminal (⌃⇧T)", action: onToggleRaw)
            HeaderIcon(
                symbol: isExpanded
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right",
                help: isExpanded ? "Collapse" : "Expand",
                action: onExpand
            )
            if !isExpanded {
                HeaderIcon(symbol: "xmark", help: "Close", action: onClose)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider().opacity(0.6) }
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
    }

    private var agentBadge: some View {
        Circle()
            .fill(profile?.swiftUIColor ?? Color.accentColor)
            .frame(width: 26, height: 26)
            .overlay(
                Text(initial)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            )
    }

    private var initial: String {
        let name = profile?.name ?? "Agent"
        return String(name.prefix(1)).uppercased()
    }
}

private struct StatusPill: View {
    let status: TerminalStatus

    var body: some View {
        HStack(spacing: 4) {
            StatusDot(color: dotColor, pulsing: status != .idle)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(Color.secondary.opacity(0.12))
        )
    }

    private var label: String {
        switch status {
        case .idle: "Idle"
        case .thinking: "Thinking…"
        case .working: "Working…"
        }
    }

    private var dotColor: Color {
        switch status {
        case .idle: .secondary
        case .thinking: .orange
        case .working: .green
        }
    }
}

private struct StatusDot: View {
    let color: Color
    let pulsing: Bool
    @State private var phase: Bool = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .opacity(pulsing && phase ? 0.4 : 1)
            .animation(
                pulsing ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                value: phase
            )
            .onAppear { phase = pulsing }
            .onChange(of: pulsing) { _, newValue in phase = newValue }
    }
}

private struct HeaderIcon: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? .primary : .secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
