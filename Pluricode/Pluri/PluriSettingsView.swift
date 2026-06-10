import SwiftUI

struct PluriSettingsView: View {
    @ObservedObject private var settings = PluriSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                setupScriptRow
                workerSetupScriptRow
            }
            .padding(20)
        }
        .frame(width: 540, height: 520)
    }

    private var setupScriptRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pluri setup script").font(.headline)
                Text("Typed into Pluri's terminal when its pane starts. Applies the next time the pane opens.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                TextField("claude --dangerously-skip-permissions", text: $settings.setupScript)
                    .textFieldStyle(.roundedBorder)
                Button("Reset") { settings.setupScript = PluriSettings.defaultSetupScript }
                    .disabled(settings.setupScript == PluriSettings.defaultSetupScript)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var workerSetupScriptRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Worker setup script").font(.headline)
                Text("The command Pluri uses to start worker agents in the worktrees it spawns; the task brief is passed as its argument. Leave empty to use the Pluri setup script.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextField("Same as Pluri setup script", text: $settings.workerSetupScript)
                .textFieldStyle(.roundedBorder)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
