import SwiftUI
import AppKit

struct PluriMascotView: View {
    var size: CGFloat = 20
    @State private var eyesOpen = true
    @State private var hovering = false
    @State private var gaze: CGSize = .zero

    static let coral = Color(red: 0.85, green: 0.47, blue: 0.34)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3)
                .fill(Self.coral)
            HStack(spacing: size * 0.2) {
                eye
                eye
            }
            .offset(gaze)
            .animation(.easeOut(duration: 0.12), value: gaze)
        }
        .frame(width: size, height: size * 0.82)
        .scaleEffect(hovering ? 1.15 : 1)
        .rotationEffect(.degrees(hovering ? -7 : 0))
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: hovering)
        .onHover { hovering = $0 }
        .background(GazeTracker(reach: size * 0.09) { gaze = $0 })
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
            try? await Task.sleep(for: .seconds(.random(in: 1.0...2.5)))
            withAnimation(.easeOut(duration: 0.07)) { eyesOpen = false }
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.easeIn(duration: 0.1)) { eyesOpen = true }
        }
    }
}

private struct GazeTracker: NSViewRepresentable {
    let reach: CGFloat
    let onGaze: (CGSize) -> Void

    func makeNSView(context: Context) -> TrackerView {
        TrackerView()
    }

    func updateNSView(_ nsView: TrackerView, context: Context) {
        nsView.reach = reach
        nsView.onGaze = onGaze
    }

    final class TrackerView: NSView {
        var reach: CGFloat = 0
        var onGaze: ((CGSize) -> Void)?
        private var timer: Timer?
        private var last: CGSize = .zero

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            timer?.invalidate()
            timer = nil
            guard window != nil else { return }
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
                self?.track()
            }
            timer?.tolerance = 0.02
        }

        deinit {
            timer?.invalidate()
        }

        private func track() {
            guard let window else { return }
            let center = window.convertPoint(
                toScreen: convert(CGPoint(x: bounds.midX, y: bounds.midY), to: nil)
            )
            let mouse = NSEvent.mouseLocation
            let dx = mouse.x - center.x
            let dy = mouse.y - center.y
            let distance = max(hypot(dx, dy), 0.001)
            let pull = reach * min(distance / 40, 1)
            let next = CGSize(width: dx / distance * pull, height: -dy / distance * pull)
            guard abs(next.width - last.width) > 0.05 || abs(next.height - last.height) > 0.05 else { return }
            last = next
            onGaze?(next)
        }
    }
}
