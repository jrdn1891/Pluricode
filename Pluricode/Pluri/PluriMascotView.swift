import SwiftUI

struct PluriMascotView: View {
    var size: CGFloat = 20
    @State private var eyesOpen = true
    @State private var hovering = false

    static let coral = Color(red: 0.85, green: 0.47, blue: 0.34)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3)
                .fill(Self.coral)
            HStack(spacing: size * 0.2) {
                eye
                eye
            }
        }
        .frame(width: size, height: size * 0.82)
        .scaleEffect(hovering ? 1.15 : 1)
        .rotationEffect(.degrees(hovering ? -7 : 0))
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: hovering)
        .onHover { hovering = $0 }
        .task { await blink() }
    }

    private var eye: some View {
        Capsule()
            .fill(.white)
            .frame(width: size * 0.14, height: size * 0.36)
            .scaleEffect(y: eyesOpen ? 1 : 0.15, anchor: .center)
    }

    private func blink() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(.random(in: 2.0...4.5)))
            withAnimation(.easeOut(duration: 0.07)) { eyesOpen = false }
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.easeIn(duration: 0.1)) { eyesOpen = true }
        }
    }
}
