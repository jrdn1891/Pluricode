import SwiftUI

struct TaskNudgeOverlay: View {
    let worktreePath: String
    @ObservedObject var session: TerminalSession
    @Environment(WorktreeTaskStore.self) private var taskStore
    @Environment(PluriMonitor.self) private var monitor: PluriMonitor?
    @State private var armed = false
    @State private var dismissed = false

    static let dwell: Duration = .seconds(30)

    private var state: WorkerState? {
        monitor?.state(atWorktree: worktreePath)
    }

    private var nextTask: TaskItem? {
        taskStore.tasks(at: worktreePath).first { !$0.done }
    }

    private var visible: Bool {
        armed && !dismissed && session.pendingAttachments.isEmpty && nextTask != nil
    }

    var body: some View {
        VStack {
            Spacer()
            if let task = nextTask, visible {
                HStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("\(taskStore.openCount(at: worktreePath)) open")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Button { start(task) } label: {
                        HStack(spacing: 4) {
                            Text("Start")
                            Text(task.title)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 260, alignment: .leading)
                            Image(systemName: "return")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button { dismissed = true } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss until the agent runs again")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .allowsHitTesting(visible)
        .animation(.easeInOut(duration: 0.2), value: visible)
        .task(id: state?.changedAt) {
            armed = false
            dismissed = false
            guard state?.status == .done else { return }
            try? await Task.sleep(for: Self.dwell)
            guard !Task.isCancelled else { return }
            armed = true
        }
    }

    private func start(_ task: TaskItem) {
        session.submit(task.title)
        dismissed = true
    }
}
