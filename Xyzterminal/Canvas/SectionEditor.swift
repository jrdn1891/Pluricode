import SwiftUI

struct SectionEditor: View {
    let document: CanvasDocument
    let nodeID: UUID
    @State private var title: String
    @State private var viewType: SectionData.ViewType
    @Environment(\.dismiss) private var dismiss

    init(document: CanvasDocument, nodeID: UUID) {
        self.document = document
        self.nodeID = nodeID
        if let node = document.nodes[nodeID], case .section(let data) = node.kind {
            _title = State(initialValue: data.title)
            _viewType = State(initialValue: data.viewType)
        } else {
            _title = State(initialValue: "")
            _viewType = State(initialValue: .list)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(.title2.bold())
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 8) {
                Text("View")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                Picker("View", selection: $viewType) {
                    ForEach(SectionData.ViewType.allCases, id: \.self) { type in
                        Label(type.rawValue.capitalized, systemImage: iconFor(type))
                            .tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }

            Spacer()

            HStack {
                Text("\(taskCount) tasks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(20)
        .frame(width: 340, height: 200)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDisappear { save() }
    }

    private var taskCount: Int {
        document.tasksInSection(nodeID).count
    }

    private func iconFor(_ type: SectionData.ViewType) -> String {
        switch type {
        case .list: "list.bullet"
        case .kanban: "rectangle.split.3x1"
        }
    }

    private func save() {
        guard case .section(var data) = document.nodes[nodeID]?.kind else { return }
        data.title = title
        data.viewType = viewType
        document.nodes[nodeID]?.kind = .section(data)
        document.scheduleSave()
    }
}
