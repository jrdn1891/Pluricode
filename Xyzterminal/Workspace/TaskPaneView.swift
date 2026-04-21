import SwiftUI

struct TaskPaneView: View {
    let paneID: UUID
    let store: TaskStore
    let focused: Bool
    let onActivate: () -> Void
    let onClose: () -> Void
    @State private var draftText: String = ""
    @FocusState private var draftFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TaskPaneHeader(
                paneID: paneID,
                remainingCount: store.tasks.filter { !$0.done }.count,
                totalCount: store.tasks.count,
                focused: focused,
                onActivate: onActivate,
                onClearCompleted: { store.clearCompleted() },
                onClose: onClose
            )

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(store.tasks) { task in
                        TaskRow(task: task, store: store)
                        Divider().opacity(0.3)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .foregroundStyle(.secondary)
                TextField("Add task...", text: $draftText)
                    .textFieldStyle(.plain)
                    .focused($draftFocused)
                    .onSubmit(commitDraft)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.06))
            .overlay(alignment: .top) {
                Divider()
            }
        }
    }

    private func commitDraft() {
        store.add(title: draftText)
        draftText = ""
        draftFocused = true
    }
}

private struct TaskRow: View {
    let task: TaskItem
    let store: TaskStore
    @State private var hovering = false
    @State private var editingTitle: String?

    var body: some View {
        HStack(spacing: 10) {
            Button(action: { store.toggle(id: task.id) }) {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.done ? Color.accentColor : .secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)

            if let draft = editingTitle {
                TextField("", text: Binding(
                    get: { draft },
                    set: { editingTitle = $0 }
                ))
                .textFieldStyle(.plain)
                .onSubmit { commitEdit() }
                .onExitCommand { editingTitle = nil }
            } else {
                Text(task.title)
                    .strikethrough(task.done)
                    .foregroundStyle(task.done ? .secondary : .primary)
                    .onTapGesture(count: 2) { editingTitle = task.title }
            }

            Spacer()

            if hovering {
                Button(action: { store.remove(id: task.id) }) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(hovering ? Color.secondary.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private func commitEdit() {
        guard let draft = editingTitle else { return }
        store.updateTitle(id: task.id, title: draft)
        editingTitle = nil
    }
}

private struct TaskPaneHeader: View {
    let paneID: UUID
    let remainingCount: Int
    let totalCount: Int
    let focused: Bool
    let onActivate: () -> Void
    let onClearCompleted: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checklist")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text("Tasks")
                .font(.system(size: 12, weight: .medium))
            Text("\(remainingCount) open / \(totalCount)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button("Clear Completed", action: onClearCompleted)
                    .disabled(totalCount == remainingCount)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(focused ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
        .draggable(TilingDragPayload(kind: .movePane(paneID: paneID))) {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                Text("Tasks")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
