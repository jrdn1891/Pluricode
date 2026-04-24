import SwiftUI

struct IdleOverlay: View {
    @ObservedObject var session: TerminalSession
    let focused: Bool

    private var visible: Bool { session.isIdle && !focused }

    var body: some View {
        ZStack {
            if visible {
                Text("🥱")
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
