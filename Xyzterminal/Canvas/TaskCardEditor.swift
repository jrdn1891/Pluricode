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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(.title2.bold())
                .foregroundStyle(.white)

            HStack {
                Picker("Status", selection: $status) {
                    ForEach(TaskCardData.Status.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)

                if let elapsed = taskDuration {
                    Text(elapsed)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text("Description")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            TextEditor(text: $content)
                .font(.body)
                .scrollContentBackground(.hidden)
                .background(Color.white.opacity(0.05))
                .cornerRadius(6)
                .frame(minHeight: 100)

            if !result.isEmpty || status == .done || status == .failed {
                Text("Result")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                TextEditor(text: $result)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(6)
                    .frame(minHeight: 60)
            }

            HStack {
                Spacer()
                Button("Done") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(20)
        .frame(width: 450, height: result.isEmpty && status != .done && status != .failed ? 360 : 480)
        .background(Color(nsColor: NSColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1)))
        .preferredColorScheme(.dark)
        .onDisappear { save() }
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
