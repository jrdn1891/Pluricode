import SwiftUI

struct TaskCardEditor: View {
    let document: CanvasDocument
    let nodeID: UUID
    @State private var title: String
    @State private var content: String
    @State private var result: String
    @State private var status: TaskCardData.Status
    @Environment(\.dismiss) private var dismiss

    init(document: CanvasDocument, nodeID: UUID) {
        self.document = document
        self.nodeID = nodeID
        if let node = document.nodes[nodeID], case .taskCard(let data) = node.kind {
            _title = State(initialValue: data.title)
            _content = State(initialValue: data.body)
            _result = State(initialValue: data.result)
            _status = State(initialValue: data.status)
        } else {
            _title = State(initialValue: "")
            _content = State(initialValue: "")
            _result = State(initialValue: "")
            _status = State(initialValue: .draft)
        }
    }

    private var showResult: Bool {
        !result.isEmpty || status == .done || status == .failed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            editorBody
            Divider()
            footer
        }
        .frame(width: 500, height: showResult ? 540 : 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDisappear { save() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Task title", text: $title)
                .textFieldStyle(.plain)
                .font(.title2.bold())

            HStack(spacing: 12) {
                statusPicker

                if let elapsed = taskDuration {
                    Label(elapsed, systemImage: "clock")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .padding(24)
    }

    private var editorBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section("Description") {
                    TextEditor(text: $content)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 120)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                if showResult {
                    section("Result") {
                        TextEditor(text: $result)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(minHeight: 80)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding(24)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") {
                save()
                dismiss()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private var statusPicker: some View {
        Menu {
            ForEach(TaskCardData.Status.allCases, id: \.self) { s in
                Button(s.label) { status = s }
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)
                Text(status.label)
                    .font(.subheadline.weight(.medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var taskDuration: String? {
        guard let node = document.nodes[nodeID],
              case .taskCard(let data) = node.kind,
              let started = data.startedAt else { return nil }
        let end = data.completedAt ?? Date()
        let seconds = Int(end.timeIntervalSince(started))
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func save() {
        guard let node = document.nodes[nodeID],
              case .taskCard(var data) = node.kind else { return }
        let oldStatus = data.status
        data.title = title
        data.body = content
        data.result = result
        if status != oldStatus {
            data.transition(to: status)
        }
        document.nodes[nodeID]?.kind = .taskCard(data)
        document.scheduleSave()
    }
}
