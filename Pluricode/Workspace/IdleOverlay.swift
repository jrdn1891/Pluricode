import SwiftUI

struct IdleOverlay: View {
    @ObservedObject var session: TerminalSession
    @ObservedObject private var settings = TerminalSettings.shared

    private var emoji: String {
        settings.idleEmoji.trimmingCharacters(in: .whitespaces)
    }

    private var visible: Bool { session.isIdle && !emoji.isEmpty }

    var body: some View {
        ZStack {
            if visible {
                Text(emoji)
                    .font(.system(size: 56))
                    .opacity(0.6)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.3), value: visible)
    }
}
