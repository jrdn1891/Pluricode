import SwiftUI
import AppKit

struct ChatComposer: View {
    let isBusy: Bool
    let onSend: (String) -> Void
    let onStop: (() -> Void)?
    @State private var text: String = ""
    @FocusState private var focused: Bool

    init(isBusy: Bool = false, onStop: (() -> Void)? = nil, onSend: @escaping (String) -> Void) {
        self.isBusy = isBusy
        self.onStop = onStop
        self.onSend = onSend
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            AttachButton { paths in injectPaths(paths) }
            ComposerField(text: $text, onSubmit: submit, focused: $focused)
            if isBusy, let onStop {
                StopButton(action: onStop)
            } else {
                SendButton(enabled: !trimmed.isEmpty, action: submit)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider().opacity(0.6)
        }
        .onAppear { focused = true }
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        let payload = trimmed
        guard !payload.isEmpty, !isBusy else { return }
        onSend(payload)
        text = ""
        focused = true
    }

    private func injectPaths(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        let escaped = paths.map(Self.shellEscape).joined(separator: " ")
        let separator = text.isEmpty || text.hasSuffix(" ") ? "" : " "
        text += separator + escaped + " "
        focused = true
    }

    private static func shellEscape(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private struct ComposerField: View {
    @Binding var text: String
    let onSubmit: () -> Void
    var focused: FocusState<Bool>.Binding

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Message agent…")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)
            }
            ComposerTextView(text: $text, onSubmit: onSubmit)
                .focused(focused)
                .frame(minHeight: 28, maxHeight: 140)
        }
    }
}

private struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.verticalScroller?.controlSize = .mini
        scroll.borderType = .noBorder
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView

        init(_ parent: ComposerTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                let event = NSApp.currentEvent
                if event?.modifierFlags.contains(.shift) == true {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    parent.onSubmit()
                }
                return true
            }
            return false
        }
    }
}

private struct AttachButton: View {
    let onPick: ([String]) -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: pick) {
            Image(systemName: "paperclip")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(hovering ? .primary : .secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Attach files")
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            onPick(panel.urls.map(\.path))
        }
    }
}

private struct SendButton: View {
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(enabled ? Color.white : Color.secondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(enabled ? Color.accentColor : Color.secondary.opacity(0.18))
                )
                .opacity(hovering && enabled ? 0.85 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .keyboardShortcut(.return, modifiers: [.command])
        .disabled(!enabled)
        .help("Send (Return)")
    }
}

private struct StopButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "stop.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary))
                .opacity(hovering ? 0.8 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Stop")
    }
}
