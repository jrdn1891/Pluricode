import SwiftUI
import AppKit

struct KeyboardCatcher: NSViewRepresentable {
    var onMoveUp: (() -> Void)? = nil
    var onMoveDown: (() -> Void)? = nil
    var onReturn: (() -> Void)? = nil
    var onEscape: (() -> Void)? = nil
    var onCommandDigit: ((Int) -> Void)? = nil

    func makeNSView(context: Context) -> NSView {
        let view = CatcherView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? CatcherView else { return }
        apply(to: view)
    }

    private func apply(to view: CatcherView) {
        view.onMoveUp = onMoveUp
        view.onMoveDown = onMoveDown
        view.onReturn = onReturn
        view.onEscape = onEscape
        view.onCommandDigit = onCommandDigit
    }

    final class CatcherView: NSView {
        var onMoveUp: (() -> Void)?
        var onMoveDown: (() -> Void)?
        var onReturn: (() -> Void)?
        var onEscape: (() -> Void)?
        var onCommandDigit: ((Int) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self, self.window != nil else { return event }
                    if let handler = self.onCommandDigit,
                       event.modifierFlags.contains(.command),
                       let chars = event.charactersIgnoringModifiers,
                       chars.count == 1,
                       let digit = Int(chars),
                       (1...9).contains(digit) {
                        handler(digit - 1)
                        return nil
                    }
                    switch event.keyCode {
                    case 126:
                        guard let handler = self.onMoveUp else { return event }
                        handler(); return nil
                    case 125:
                        guard let handler = self.onMoveDown else { return event }
                        handler(); return nil
                    case 36, 76:
                        guard let handler = self.onReturn else { return event }
                        handler(); return nil
                    case 53:
                        guard let handler = self.onEscape else { return event }
                        handler(); return nil
                    default:
                        return event
                    }
                }
            } else if window == nil, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}

struct KeyHint: View {
    let glyph: String

    var body: some View {
        Text(glyph)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.12))
            )
            .opacity(0.85)
    }
}

struct KeyHintBar: View {
    let hints: [(glyph: String, label: String)]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(hints, id: \.glyph) { hint in
                HStack(spacing: 5) {
                    KeyHint(glyph: hint.glyph)
                    Text(hint.label)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

struct ConfirmationPrompt: Identifiable {
    let id = UUID()
    let title: String
    let message: String?
    let confirm: Confirm?

    struct Confirm {
        let label: String
        let isDestructive: Bool
        let action: () -> Void
    }

    static func info(title: String, message: String? = nil) -> ConfirmationPrompt {
        ConfirmationPrompt(title: title, message: message, confirm: nil)
    }

    static func destructive(
        title: String,
        message: String? = nil,
        label: String = "Delete",
        action: @escaping () -> Void
    ) -> ConfirmationPrompt {
        ConfirmationPrompt(
            title: title,
            message: message,
            confirm: Confirm(label: label, isDestructive: true, action: action)
        )
    }
}

private struct ConfirmationSheet: View {
    let prompt: ConfirmationPrompt
    let dismiss: () -> Void
    @FocusState private var defaultFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(prompt.title).font(.headline)
            if let message = prompt.message {
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                if let confirm = prompt.confirm {
                    Button(action: dismiss) {
                        buttonLabel("Cancel", glyph: "⎋")
                    }
                    .keyboardShortcut(.cancelAction)
                    Button(role: confirm.isDestructive ? .destructive : nil) {
                        confirm.action()
                        dismiss()
                    } label: {
                        buttonLabel(confirm.label, glyph: "⏎")
                    }
                    .keyboardShortcut(.defaultAction)
                    .focused($defaultFocused)
                } else {
                    Button(action: dismiss) {
                        buttonLabel("OK", glyph: "⏎")
                    }
                    .keyboardShortcut(.defaultAction)
                    .focused($defaultFocused)
                }
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { defaultFocused = true }
    }

    private func buttonLabel(_ title: String, glyph: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Text(glyph)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .opacity(0.65)
        }
    }
}

extension View {
    func confirmation(_ binding: Binding<ConfirmationPrompt?>) -> some View {
        sheet(item: binding) { prompt in
            ConfirmationSheet(prompt: prompt) { binding.wrappedValue = nil }
        }
    }
}
