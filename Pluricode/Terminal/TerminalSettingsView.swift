import SwiftUI

struct TerminalSettingsView: View {
    @ObservedObject private var settings = TerminalSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $settings.useMetalRenderer) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GPU rendering (Metal)").font(.headline)
                        Text("Renders terminal cells through a Metal texture atlas instead of CoreGraphics. Lowers CPU with many active panes. Experimental in SwiftTerm.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .padding(14)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                idleEmojiRow
            }
            .padding(20)
        }
        .frame(width: 540, height: 520)
    }

    private var idleEmojiRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Idle indicator").font(.headline)
                Text("Shown over a terminal pane that has been quiet for a while. Leave empty to hide it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                TextField("Empty to disable", text: $settings.idleEmoji)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                Button("Reset") { settings.idleEmoji = TerminalSettings.defaultIdleEmoji }
                    .disabled(settings.idleEmoji == TerminalSettings.defaultIdleEmoji)
                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
