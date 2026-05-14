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
            }
            .padding(20)
        }
        .frame(width: 540, height: 520)
    }
}
