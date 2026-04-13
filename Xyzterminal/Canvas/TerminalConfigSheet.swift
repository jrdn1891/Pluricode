import SwiftUI

struct TerminalDefaults: Codable {
    var agentName: String = "Claude Code"
    var startupScript: String = "claude"
    var role: TerminalNodeData.Role?

    static var saved: TerminalDefaults {
        get {
            guard let data = UserDefaults.standard.data(forKey: "terminalDefaults"),
                  let defaults = try? JSONDecoder().decode(TerminalDefaults.self, from: data)
            else { return TerminalDefaults() }
            return defaults
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "terminalDefaults")
            }
        }
    }
}

struct TerminalConfigSheet: View {
    let onCreate: (TerminalNodeData) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var agentName: String
    @State private var startupScript: String
    @State private var role: TerminalNodeData.Role?
    @State private var saveAsDefault: Bool = false

    init(onCreate: @escaping (TerminalNodeData) -> Void) {
        self.onCreate = onCreate
        let defaults = TerminalDefaults.saved
        _agentName = State(initialValue: defaults.agentName)
        _startupScript = State(initialValue: defaults.startupScript)
        _role = State(initialValue: defaults.role)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Terminal")
                .font(.title2.bold())

            Picker("Agent", selection: $agentName) {
                ForEach(AgentDefinition.builtins) { agent in
                    Text(agent.name).tag(agent.name)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Startup script")
                    .font(.subheadline.bold())
                TextField("e.g. claude --dangerously-skip-permissions", text: $startupScript)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            Picker("Role (optional)", selection: Binding(
                get: { role ?? .coder },
                set: { role = $0 }
            )) {
                ForEach(TerminalNodeData.Role.allCases, id: \.self) { r in
                    Text(r.rawValue.capitalized).tag(r)
                }
            }

            Toggle("No role", isOn: Binding(
                get: { role == nil },
                set: { if $0 { role = nil } else { role = .coder } }
            ))

            Divider()

            Toggle("Save as default for new terminals", isOn: $saveAsDefault)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    if saveAsDefault {
                        TerminalDefaults.saved = TerminalDefaults(
                            agentName: agentName,
                            startupScript: startupScript,
                            role: role
                        )
                    }
                    var data = TerminalNodeData()
                    data.agentName = agentName
                    data.startupScript = startupScript.isEmpty ? nil : startupScript
                    data.role = role
                    onCreate(data)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
