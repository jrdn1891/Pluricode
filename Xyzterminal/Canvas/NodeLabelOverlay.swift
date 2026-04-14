import SwiftUI

struct NodeLabelOverlay: View {
    let document: CanvasDocument

    var body: some View {
        GeometryReader { geo in
            let vp = geo.size
            let zoom = CGFloat(document.camera.zoom)
            let layouts = document.allSectionLayouts()
            if zoom > 0.25 {
                ForEach(Array(document.nodes.values), id: \.id) { node in
                    let entry = layouts[node.id]
                    let effectivePos = entry?.position ?? node.position
                    let effectiveSize = entry?.size ?? node.size
                    let pos = document.camera.canvasToSwiftUI(effectivePos, viewportSize: vp)
                    let w = CGFloat(effectiveSize.x) * zoom
                    let h = CGFloat(effectiveSize.y) * zoom

                    nodeLabelView(node: node, width: w, height: h)
                        .position(x: pos.x + w * 0.5, y: pos.y + h * 0.5)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func profileName(for data: TerminalNodeData) -> String {
        guard let id = data.profileID, let profile = document.agentProfiles[id] else { return "Terminal" }
        return profile.name
    }

    @ViewBuilder
    private func nodeLabelView(node: CanvasNode, width: CGFloat, height: CGFloat) -> some View {
        switch node.kind {
        case .taskCard(let data):
            let blocked = !document.unresolvedBlockers(for: node.id).isEmpty
            let isEditing = node.id == document.inlineEditingNodeID
            let zoom = CGFloat(document.camera.zoom)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if blocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: max(8, 10 * zoom)))
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    Text(data.title.isEmpty ? "Untitled" : data.title)
                        .font(.system(size: max(10, 13 * zoom), weight: .semibold))
                        .foregroundStyle(.primary.opacity(isEditing ? 0 : (data.title.isEmpty ? 0.4 : (blocked ? 0.5 : 1))))
                        .lineLimit(2)
                    Spacer()
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: max(8, 10 * zoom)))
                        .foregroundStyle(.secondary)
                }
                Text(data.status.label)
                    .font(.system(size: max(8, 10 * zoom), weight: .medium))
                    .foregroundStyle(data.status.color)
                    .padding(.horizontal, max(4, 6 * zoom))
                    .padding(.vertical, max(1, 2 * zoom))
                    .background(data.status.color.opacity(0.12))
                    .clipShape(Capsule())
                if height > 60 {
                    let subtitle = (data.status == .done || data.status == .failed) && !data.result.isEmpty
                        ? data.result
                        : data.body
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: max(9, 11 * zoom)))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            }
            .padding(8)
            .frame(width: width, height: height, alignment: .topLeading)

        case .terminal(let data):
            let zoom = CGFloat(document.camera.zoom)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .font(.system(size: max(9, 11 * zoom)))
                        .foregroundStyle(.green.opacity(0.7))
                    Text(profileName(for: data))
                        .font(.system(size: max(10, 13 * zoom), weight: .semibold))
                        .foregroundStyle(.primary)
                    if let branch = data.branchName {
                        Text(branch)
                            .font(.system(size: max(8, 10 * zoom), design: .monospaced))
                            .foregroundStyle(.cyan.opacity(0.7))
                    }
                    Spacer()
                    Text(data.status.rawValue)
                        .font(.system(size: max(8, 10 * zoom)))
                        .foregroundStyle(data.status.color)
                }
            }
            .padding(8)
            .frame(width: width, height: height, alignment: .topLeading)

        case .section(let data):
            let zoom = CGFloat(document.camera.zoom)
            let tasks = document.tasksInSection(node.id)
            let taskCount = tasks.count
            let isAssigned = document.edges.values.contains { $0.sourceID == node.id && $0.edgeType == .assignedTo }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: data.isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: max(8, 10 * zoom)))
                        .foregroundStyle(.secondary)
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: max(9, 11 * zoom)))
                        .foregroundStyle(.purple.opacity(0.7))
                    Text(data.title)
                        .font(.system(size: max(10, 13 * zoom), weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if isAssigned && taskCount > 0 {
                        let done = tasks.filter { $0.data.status == .done }.count
                        Text("\(done)/\(taskCount)")
                            .font(.system(size: max(8, 10 * zoom), weight: .medium))
                            .foregroundStyle(done == taskCount ? .green : .orange)
                    } else if data.isCollapsed && taskCount > 0 {
                        Text("\(taskCount)")
                            .font(.system(size: max(8, 10 * zoom)))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !data.isCollapsed {
                        Text(data.viewType.rawValue.capitalized)
                            .font(.system(size: max(8, 10 * zoom)))
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: max(8, 10 * zoom)))
                        .foregroundStyle(.secondary)
                }
                .frame(height: 40 * zoom)

                if !data.isCollapsed {
                    if data.viewType == .kanban, width > 200 {
                        HStack(spacing: 0) {
                            ForEach(TaskCardData.Status.allCases, id: \.self) { status in
                                let count = tasks.filter { $0.data.status == status }.count
                                Text(count > 0 ? "\(columnLabel(status)) \(count)" : columnLabel(status))
                                    .font(.system(size: max(7, 9 * zoom)))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 28 * zoom)
                    }

                    if taskCount == 0 {
                        Spacer()
                        Text("Drag tasks here")
                            .font(.system(size: max(10, 13 * zoom)))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                        Spacer()
                    } else {
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 8)
            .frame(width: width, height: data.isCollapsed ? 40 * zoom : height, alignment: .topLeading)
        }
    }

    private func columnLabel(_ status: TaskCardData.Status) -> String {
        switch status {
        case .draft: "Draft"
        case .ready: "Ready"
        case .inProgress: "Active"
        case .done: "Done"
        case .failed: "Failed"
        case .flagged: "Flagged"
        }
    }
}

extension TaskCardData.Status {
    var label: String {
        switch self {
        case .draft: "Draft"
        case .ready: "Ready"
        case .inProgress: "In Progress"
        case .done: "Done"
        case .failed: "Failed"
        case .flagged: "Flagged"
        }
    }

    var color: Color {
        switch self {
        case .draft: .gray
        case .ready: .blue
        case .inProgress: .orange
        case .done: .green
        case .failed: .red
        case .flagged: .yellow
        }
    }
}
