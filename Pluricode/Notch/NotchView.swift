import SwiftUI

enum NotchMetrics {
    static let collapsedTopRadius: CGFloat = 9
    static let collapsedBottomRadius: CGFloat = 13
    static let expandedTopRadius: CGFloat = 13
    static let expandedBottomRadius: CGFloat = 22
    static let collapsedHang: CGFloat = 0
    static let expandedContentHeight: CGFloat = 420
    static let expandedBodyWidth: CGFloat = 360
    static let minCollapsedBodyWidth: CGFloat = 180
}

struct NotchGeometry: Equatable {
    var topInset: CGFloat = 0
    var hasNotch: Bool = false
}

@Observable
final class NotchModel {
    var isExpanded = false
    var geometry = NotchGeometry()
    var selectedAgentID: String?
    var isPinned = false
}

struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set { topCornerRadius = newValue.first; bottomCornerRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        return path
    }
}

struct NotchView: View {
    let store: WorkspaceStore
    let monitor: PluriMonitor
    let model: NotchModel

    @State private var draft = ""
    @State private var isHovering = false
    @FocusState private var inputFocused: Bool

    private var topRadius: CGFloat {
        model.isExpanded ? NotchMetrics.expandedTopRadius : NotchMetrics.collapsedTopRadius
    }
    private var bottomRadius: CGFloat {
        model.isExpanded ? NotchMetrics.expandedBottomRadius : NotchMetrics.collapsedBottomRadius
    }

    var body: some View {
        let overview = AgentOverview.build(workspaces: store.workspaces, statuses: monitor.statuses)
        Group {
            if model.isExpanded {
                expanded(overview)
            } else {
                Color.clear
            }
        }
        .padding(.top, model.geometry.topInset)
        .padding(.horizontal, topRadius)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { Color.black.padding(-50) }
        .mask { NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius) }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .onChange(of: model.selectedAgentID) { _, id in
            inputFocused = id != nil
        }
        .onChange(of: inputFocused) { _, focused in
            model.isPinned = focused
            updateExpansion()
        }
        .onHover { hovering in
            isHovering = hovering
            updateExpansion()
        }
    }

    private func updateExpansion() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            if isHovering || model.isPinned {
                model.isExpanded = true
            } else {
                model.isExpanded = false
                model.selectedAgentID = nil
            }
        }
    }

    private func expanded(_ overview: AgentOverview) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                counter(overview.working, color: .blue, symbol: "circle.fill")
                counter(overview.waiting, color: .orange, symbol: "exclamationmark.circle.fill", emphasize: true)
                counter(overview.idle, color: Color.secondary, symbol: "circle")
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            Divider().overlay(Color.white.opacity(0.12))
            if overview.groups.isEmpty {
                Text("No active agents")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(overview.groups) { group in
                            section(group)
                        }
                    }
                    .padding(.vertical, 10)
                }
            }
            if let selected = selectedRow(overview) {
                Divider().overlay(Color.white.opacity(0.12))
                inputBar(selected)
            }
        }
    }

    private func section(_ group: WorkspaceGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(group.rows) { row in
                agentRow(row)
            }
        }
    }

    private func agentRow(_ row: AgentRow) -> some View {
        let selected = model.selectedAgentID == row.id
        return HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(row.state?.status.color ?? Color(nsColor: .tertiaryLabelColor))
                .frame(width: 7, height: 7)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                    .font(.system(size: 12, weight: .medium))
                if let detail = row.detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            Button {
                store.focusWorkerPane(repoID: row.repoID, branch: row.branch)
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Jump to this agent's pane")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(selected ? Color.white.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectedAgentID = selected ? nil : row.id
        }
    }

    private func inputBar(_ row: AgentRow) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            TextField("message \(row.branch)…", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($inputFocused)
                .onSubmit { send(to: row) }
            Button {
                send(to: row)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(draft.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06))
    }

    private func send(to row: AgentRow) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        store.agentSession(repoID: row.repoID, branch: row.branch)?.submit(text)
        draft = ""
    }

    private func selectedRow(_ overview: AgentOverview) -> AgentRow? {
        guard let id = model.selectedAgentID else { return nil }
        for group in overview.groups {
            if let row = group.rows.first(where: { $0.id == id }) { return row }
        }
        return nil
    }

    private func counter(_ count: Int, color: Color, symbol: String, emphasize: Bool = false) -> some View {
        let active = emphasize && count > 0
        return HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9))
                .foregroundStyle(color)
            Text("\(count)")
                .font(.system(size: 12, weight: active ? .bold : .medium))
                .foregroundStyle(active ? color : Color.primary)
        }
    }
}
