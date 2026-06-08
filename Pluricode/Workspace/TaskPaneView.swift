import SwiftUI
import CoreTransferable

struct TaskDragPayload: Codable, Transferable, Hashable {
    let listID: UUID
    let taskID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

struct TaskPaneView: View {
    let paneID: UUID
    let listID: UUID
    let store: TaskListStore
    let workspace: Workspace
    let onActivate: () -> Void
    let onMinimize: (() -> Void)?
    let onClose: () -> Void
    @State private var draftText: String = ""
    @FocusState private var draftFocused: Bool

    private var list: TaskList? {
        store.list(id: listID)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let list {
                TaskPaneHeader(
                    paneID: paneID,
                    listName: list.name,
                    remainingCount: list.items.filter { !$0.done }.count,
                    totalCount: list.items.count,
                    onActivate: onActivate,
                    onClearCompleted: { store.clearCompleted(listID: listID) },
                    onMinimize: onMinimize,
                    onClose: onClose
                )

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(list.items) { task in
                            TaskRow(listID: listID, task: task, store: store)
                            Divider().opacity(0.3)
                        }
                        TaskTrailingDropZone(listID: listID, store: store)
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
            } else {
                MissingTaskListBody(listID: listID, onRemove: onClose)
            }
        }
        .onAppear {
            if workspace.consumePendingFocus(paneID: paneID) { draftFocused = true }
        }
    }

    private func commitDraft() {
        store.addTask(listID: listID, title: draftText)
        draftText = ""
        draftFocused = true
    }
}

private struct TaskRow: View {
    let listID: UUID
    let task: TaskItem
    let store: TaskListStore
    @State private var hovering = false
    @State private var editingTitle: String?
    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: { store.toggleTask(listID: listID, taskID: task.id) }) {
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
                Button(action: { store.removeTask(listID: listID, taskID: task.id) }) {
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
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
                .opacity(isTargeted ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .draggable(TaskDragPayload(listID: listID, taskID: task.id))
        .dropDestination(for: TaskDragPayload.self) { payloads, _ in
            guard let payload = payloads.first, payload.listID == listID else { return false }
            store.moveTask(listID: listID, taskID: payload.taskID, before: task.id)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private func commitEdit() {
        guard let draft = editingTitle else { return }
        store.updateTaskTitle(listID: listID, taskID: task.id, title: draft)
        editingTitle = nil
    }
}

private struct TaskTrailingDropZone: View {
    let listID: UUID
    let store: TaskListStore
    @State private var isTargeted = false

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 24)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .opacity(isTargeted ? 1 : 0)
            }
            .dropDestination(for: TaskDragPayload.self) { payloads, _ in
                guard let payload = payloads.first, payload.listID == listID else { return false }
                store.moveTask(listID: listID, taskID: payload.taskID, before: nil)
                return true
            } isTargeted: { isTargeted = $0 }
    }
}

private struct TaskPaneHeader: View {
    let paneID: UUID
    let listName: String
    let remainingCount: Int
    let totalCount: Int
    let onActivate: () -> Void
    let onClearCompleted: () -> Void
    let onMinimize: (() -> Void)?
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checklist")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(listName)
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
            .menuIndicator(.hidden)
            .frame(width: 20)

            if let onMinimize {
                Button(action: onMinimize) {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Minimize pane")
            }

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
                Image(systemName: "checklist")
                Text(listName)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

private struct MissingTaskListBody: View {
    let listID: UUID
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text("Task list not found")
                .font(.headline)
            Text("The list this pane points to has been deleted.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Remove Pane", role: .destructive, action: onRemove)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
