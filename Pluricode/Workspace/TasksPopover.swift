import SwiftUI
import CoreTransferable

struct TaskDragPayload: Codable, Transferable, Hashable {
    let taskID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

struct TasksPopover: View {
    let worktreePath: String
    let store: WorktreeTaskStore
    @State private var draftText: String = ""
    @FocusState private var draftFocused: Bool

    private var tasks: [TaskItem] { store.tasks(at: worktreePath) }

    var body: some View {
        VStack(spacing: 0) {
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
            .overlay(alignment: .bottom) { Divider() }

            if tasks.isEmpty {
                Text("Jot down anything you notice while the agent works.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(tasks) { task in
                            TaskRow(worktreePath: worktreePath, task: task, store: store)
                            Divider().opacity(0.3)
                        }
                        TaskTrailingDropZone(worktreePath: worktreePath, store: store)
                    }
                }
                .frame(maxHeight: 280)

                if tasks.contains(where: { $0.done }) {
                    Button("Clear Completed") { store.clearCompleted(path: worktreePath) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .top) { Divider() }
                }
            }
        }
        .frame(width: 320)
        .onAppear { draftFocused = true }
    }

    private func commitDraft() {
        store.add(path: worktreePath, title: draftText)
        draftText = ""
        draftFocused = true
    }
}

private struct TaskRow: View {
    let worktreePath: String
    let task: TaskItem
    let store: WorktreeTaskStore
    @State private var hovering = false
    @State private var editingTitle: String?
    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: { store.toggle(path: worktreePath, taskID: task.id) }) {
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
                Button(action: { store.remove(path: worktreePath, taskID: task.id) }) {
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
        .draggable(TaskDragPayload(taskID: task.id))
        .dropDestination(for: TaskDragPayload.self) { payloads, _ in
            guard let payload = payloads.first else { return false }
            store.move(path: worktreePath, taskID: payload.taskID, before: task.id)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private func commitEdit() {
        guard let draft = editingTitle else { return }
        store.updateTitle(path: worktreePath, taskID: task.id, title: draft)
        editingTitle = nil
    }
}

private struct TaskTrailingDropZone: View {
    let worktreePath: String
    let store: WorktreeTaskStore
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
                guard let payload = payloads.first else { return false }
                store.move(path: worktreePath, taskID: payload.taskID, before: nil)
                return true
            } isTargeted: { isTargeted = $0 }
    }
}
