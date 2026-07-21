import SwiftUI

enum NotchMetrics {
    static let collapsedTopRadius: CGFloat = 9
    static let collapsedBottomRadius: CGFloat = 13
    static let expandedTopRadius: CGFloat = 13
    static let expandedBottomRadius: CGFloat = 22
    static let collapsedHang: CGFloat = 0
    static let expandedContentHeight: CGFloat = 210
    static let focusedContentHeight: CGFloat = 340
    static let expandedBodyWidth: CGFloat = 360
    static let collapsedFallbackWidth: CGFloat = 120
    static let mascotEar: CGFloat = 34
    static let mascotSize: CGFloat = 16
}

struct NotchGeometry: Equatable {
    var topInset: CGFloat = 0
    var hasNotch: Bool = false
    var cameraWidth: CGFloat = 0
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
    private var bodyWidth: CGFloat {
        model.isExpanded
            ? NotchMetrics.expandedBodyWidth
            : max(model.geometry.cameraWidth, NotchMetrics.collapsedFallbackWidth)
    }
    private var contentHeight: CGFloat {
        guard model.isExpanded else { return 0 }
        return model.selectedAgentID == nil ? NotchMetrics.expandedContentHeight : NotchMetrics.focusedContentHeight
    }
    private var shapeHeight: CGFloat {
        model.geometry.topInset + contentHeight
    }

    var body: some View {
        Group {
            if model.isExpanded {
                expanded(AgentOverview.build(workspaces: store.workspaces, statuses: monitor.statuses))
            } else {
                Color.clear
            }
        }
        .padding(.horizontal, topRadius)
        .frame(width: bodyWidth + topRadius * 2, height: shapeHeight, alignment: .top)
        .background { Color.black.padding(-50) }
        .mask { NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius) }
        .contentShape(NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius))
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
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

    private func mascotBand() -> some View {
        PluriMascotView(size: NotchMetrics.mascotSize)
            .offset(x: model.geometry.cameraWidth / 2 + NotchMetrics.mascotEar / 2)
            .frame(maxWidth: .infinity)
            .frame(height: model.geometry.topInset)
    }

    private func expanded(_ overview: AgentOverview) -> some View {
        Group {
            if let row = selectedRow(overview) {
                focused(row)
            } else {
                list(overview)
            }
        }
    }

    private func list(_ overview: AgentOverview) -> some View {
        VStack(spacing: 0) {
            mascotBand()
            HStack(spacing: 16) {
                counter(overview.working, color: .blue, symbol: "circle.fill")
                counter(overview.waiting, color: .orange, symbol: "exclamationmark.circle.fill", emphasize: true)
                counter(overview.idle, color: Color.secondary, symbol: "circle")
                Spacer()
            }
            .padding(.horizontal, 10)
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
        }
    }

    private func focused(_ row: AgentRow) -> some View {
        VStack(spacing: 0) {
            mascotBand()
            focusedHeader(row)
            Divider().overlay(Color.white.opacity(0.12))
            responseBody(row)
            if row.state?.status == .waiting {
                HStack(spacing: 6) {
                    quickButton("Allow", color: .green) { sendKeys(to: row, "\r") }
                    quickButton("Deny", color: Color(nsColor: .systemRed)) { sendKeys(to: row, "\u{1b}") }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            Divider().overlay(Color.white.opacity(0.12))
            inputBar(row)
        }
    }

    private func focusedHeader(_ row: AgentRow) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    model.selectedAgentID = nil
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Circle()
                .fill(row.state?.status.color ?? Color(nsColor: .tertiaryLabelColor))
                .frame(width: 7, height: 7)
            Text(row.branch)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer()
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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func responseBody(_ row: AgentRow) -> some View {
        if let text = row.state?.lastResponse {
            ScrollView {
                Text(text)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
        } else {
            Text(responsePlaceholder(row))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func responsePlaceholder(_ row: AgentRow) -> String {
        switch row.state?.status {
        case .running: return "Working…"
        case .waiting: return row.state?.message ?? "Waiting for your input"
        default: return "No response yet"
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
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(row.state?.status.color ?? Color(nsColor: .tertiaryLabelColor))
                .frame(width: 7, height: 7)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.branch)
                    .font(.system(size: 12, weight: .medium))
                if let detail = row.detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if row.state?.status == .waiting {
                    HStack(spacing: 6) {
                        quickButton("Allow", color: .green) { sendKeys(to: row, "\r") }
                        quickButton("Deny", color: Color(nsColor: .systemRed)) { sendKeys(to: row, "\u{1b}") }
                    }
                    .padding(.top, 1)
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
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                model.selectedAgentID = row.id
            }
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

    private func sendKeys(to row: AgentRow, _ keys: String) {
        store.agentSession(repoID: row.repoID, branch: row.branch)?.sendKeys(keys)
    }

    private func quickButton(_ title: String, color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color.opacity(0.18), in: Capsule())
        }
        .buttonStyle(.plain)
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
