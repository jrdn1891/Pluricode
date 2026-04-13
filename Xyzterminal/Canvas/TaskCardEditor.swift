import SwiftUI

struct TaskCardEditor: View {
    let document: CanvasDocument
    let nodeID: UUID
    @State private var title: String
    @State private var content: String
    @State private var status: TaskCardData.Status
    @Environment(\.dismiss) private var dismiss

    init(document: CanvasDocument, nodeID: UUID) {
        self.document = document
        self.nodeID = nodeID
        if let node = document.nodes[nodeID], case .taskCard(let data) = node.kind {
            _title = State(initialValue: data.title)
            _content = State(initialValue: data.body)
            _status = State(initialValue: data.status)
        } else {
            _title = State(initialValue: "")
            _content = State(initialValue: "")
            _status = State(initialValue: .draft)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(.title2.bold())

            Picker("Status", selection: $status) {
                ForEach(TaskCardData.Status.allCases, id: \.self) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)

            TextEditor(text: $content)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)

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
        .frame(width: 400, height: 300)
        .onDisappear { save() }
    }

    private func save() {
        let data = TaskCardData(title: title, body: content, status: status)
        document.nodes[nodeID]?.kind = .taskCard(data)
        document.scheduleSave()
    }
}
