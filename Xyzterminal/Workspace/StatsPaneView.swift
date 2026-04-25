import SwiftUI

struct StatsPaneView: View {
    let paneID: UUID
    let service: StatsService
    let onActivate: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            StatsPaneHeader(
                paneID: paneID,
                lastUpdated: service.lastUpdated,
                isLoading: service.isLoading,
                onRefresh: { Task { await service.refresh() } },
                onActivate: onActivate,
                onClose: onClose
            )

            VStack(spacing: 0) {
                StatsRow(
                    icon: "arrow.triangle.merge",
                    label: "Commits",
                    value: "\(service.commits)"
                )
                Divider().opacity(0.3)
                StatsLinesRow(additions: service.additions, deletions: service.deletions)
                Divider().opacity(0.3)
                StatsRow(
                    icon: "checkmark.seal",
                    label: "PRs merged",
                    value: "\(service.prsMerged)",
                    caption: service.ghAvailable ? nil : "Install `gh` for PR counts"
                )
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
        }
        .task {
            await service.refresh()
        }
    }
}

private struct StatsRow: View {
    let icon: String
    let label: String
    let value: String
    var caption: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let caption {
                    Text(caption)
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Text(value)
                .font(.system(size: 22, weight: .semibold).monospacedDigit())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct StatsLinesRow: View {
    let additions: Int
    let deletions: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "plusminus")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text("Lines")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 6) {
                Text("+\(additions)")
                    .foregroundStyle(.green)
                Text("-\(deletions)")
                    .foregroundStyle(.red)
            }
            .font(.system(size: 18, weight: .semibold).monospacedDigit())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct StatsPaneHeader: View {
    let paneID: UUID
    let lastUpdated: Date?
    let isLoading: Bool
    let onRefresh: () -> Void
    let onActivate: () -> Void
    let onClose: () -> Void

    @State private var now: Date = Date()

    private var statusText: String {
        if isLoading { return "Updating…" }
        guard let lastUpdated else { return "—" }
        let elapsed = Int(now.timeIntervalSince(lastUpdated))
        if elapsed < 5 { return "just now" }
        if elapsed < 60 { return "\(elapsed)s ago" }
        let mins = elapsed / 60
        if mins < 60 { return "\(mins)m ago" }
        return "\(mins / 60)h ago"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text("Today")
                .font(.system(size: 12, weight: .medium))
            Text(statusText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
        .draggable(TilingDragPayload(kind: .movePane(paneID: paneID))) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar")
                Text("Today")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .task {
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }
}
