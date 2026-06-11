import SwiftUI

struct PluriSettingsView: View {
    @ObservedObject private var settings = PluriSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                commandRow
                workerSetupScriptRow
            }
            .padding(20)
        }
        .frame(width: 540, height: 520)
    }

    private var commandRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pluri command").font(.headline)
                Text("The Claude Code command behind Pluri's chat window, run headless with streaming output. Applies from the next message.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                TextField("claude --model opus", text: $settings.command)
                    .textFieldStyle(.roundedBorder)
                Button("Reset") { settings.command = PluriSettings.defaultCommand }
                    .disabled(settings.command == PluriSettings.defaultCommand)
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
                Text("The command Pluri uses to start worker agents in the worktrees it spawns; the task brief is passed as its argument. Leave empty to use the Pluri command.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextField("Same as Pluri command", text: $settings.workerSetupScript)
                .textFieldStyle(.roundedBorder)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
