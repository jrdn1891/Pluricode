import SwiftUI

struct TerminalDefaults: Codable {
    var agentName: String = "Claude Code"
    var startupScript: String = "claude"
    var profileID: UUID?

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
    let document: CanvasDocument
    let onCreate: (TerminalNodeData) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var startupScript: String
    @State private var profileID: UUID?
    @State private var saveAsDefault: Bool = false
    @State private var editingProfile: AgentProfile?

    init(document: CanvasDocument, onCreate: @escaping (TerminalNodeData) -> Void) {
        self.document = document
        self.onCreate = onCreate
        let defaults = TerminalDefaults.saved
        _startupScript = State(initialValue: defaults.startupScript)
        _profileID = State(initialValue: defaults.profileID)
    }

    private var sortedProfiles: [AgentProfile] {
        document.agentProfiles.values.sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Terminal")
                .font(.title2.bold())

            profilePicker
            startupScriptField
            Divider()
            Toggle("Save as default for new terminals", isOn: $saveAsDefault)
            actionButtons
        }
        .padding(24)
        .frame(width: 480)
        .sheet(item: $editingProfile) { profile in
            ProfileEditorSheet(profile: profile) { updated in
                document.agentProfiles[updated.id] = updated
                profileID = updated.id
                document.scheduleSave()
            }
        }
    }

    private var profilePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agent Profile")
                .font(.subheadline.bold())
            HStack(spacing: 8) {
                Picker("", selection: $profileID) {
                    Text("None").tag(UUID?.none)
                    ForEach(sortedProfiles) { profile in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(simd: profile.color))
                                .frame(width: 8, height: 8)
                            Text(profile.name)
                        }
                        .tag(Optional(profile.id))
                    }
                }
                .labelsHidden()

                Button("Edit") {
                    if let id = profileID, let profile = document.agentProfiles[id] {
                        editingProfile = profile
                    }
                }
                .disabled(profileID == nil)

                Button("New") {
                    editingProfile = AgentProfile(
                        id: UUID(),
                        name: "",
                        instructions: "",
                        agentDefinition: "Claude Code",
                        color: SIMD4(
                            Float.random(in: 0.3...0.9),
                            Float.random(in: 0.3...0.9),
                            Float.random(in: 0.3...0.9),
                            1.0
                        )
                    )
                }
            }
        }
    }

    private var startupScriptField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Startup script")
                .font(.subheadline.bold())
            TextField("e.g. claude --dangerously-skip-permissions", text: $startupScript)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
        }
    }

    private var actionButtons: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Create") {
                if saveAsDefault {
                    TerminalDefaults.saved = TerminalDefaults(
                        agentName: document.agentProfiles[profileID ?? UUID()]?.agentDefinition ?? "Claude Code",
                        startupScript: startupScript,
                        profileID: profileID
                    )
                }
                var data = TerminalNodeData()
                data.agentName = document.agentProfiles[profileID ?? UUID()]?.agentDefinition ?? "Claude Code"
                data.startupScript = startupScript.isEmpty ? nil : startupScript
                data.profileID = profileID
                onCreate(data)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}

struct ProfileEditorSheet: View {
    @State var profile: AgentProfile
    let onSave: (AgentProfile) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(profile.name.isEmpty ? "New Profile" : "Edit Profile")
                .font(.title2.bold())

            TextField("Profile name", text: $profile.name)
                .textFieldStyle(.roundedBorder)

            Picker("Agent", selection: $profile.agentDefinition) {
                ForEach(AgentDefinition.builtins) { agent in
                    Text(agent.name).tag(agent.name)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Instructions")
                    .font(.subheadline.bold())
                TextEditor(text: $profile.instructions)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 200)
                    .border(Color.secondary.opacity(0.3))
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(profile)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(profile.name.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520, height: 480)
    }
}

extension Color {
    init(simd c: SIMD4<Float>) {
        self.init(red: Double(c.x), green: Double(c.y), blue: Double(c.z), opacity: Double(c.w))
    }
}
