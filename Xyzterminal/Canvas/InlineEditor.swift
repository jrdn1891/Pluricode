import AppKit

final class InlineEditor: NSObject, NSTextFieldDelegate {
    private var textField: NSTextField?
    private var editingNodeID: UUID?
    private var onCommit: ((String) -> Void)?

    func startEditing(
        nodeID: UUID,
        text: String,
        frame: NSRect,
        in containerView: NSView,
        onCommit: @escaping (String) -> Void
    ) {
        cancel()

        self.editingNodeID = nodeID
        self.onCommit = onCommit

        let tf = NSTextField(frame: frame)
        tf.stringValue = text
        tf.font = .systemFont(ofSize: 14, weight: .semibold)
        tf.isBezeled = false
        tf.drawsBackground = true
        tf.backgroundColor = NSColor(red: 0.18, green: 0.18, blue: 0.22, alpha: 1)
        tf.textColor = .white
        tf.focusRingType = .exterior
        tf.alignment = .left
        tf.cell?.isScrollable = true
        tf.cell?.wraps = false
        tf.delegate = self

        containerView.addSubview(tf)
        tf.window?.makeFirstResponder(tf)
        tf.selectText(nil)

        self.textField = tf
    }

    func cancel() {
        textField?.removeFromSuperview()
        textField = nil
        editingNodeID = nil
        onCommit = nil
    }

    var isEditing: Bool { textField != nil }
    var currentNodeID: UUID? { editingNodeID }

    func controlTextDidEndEditing(_ obj: Notification) {
        commit()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commit()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancel()
            return true
        }
        return false
    }

    private func commit() {
        guard let tf = textField else { return }
        let value = tf.stringValue
        onCommit?(value)
        tf.removeFromSuperview()
        textField = nil
        editingNodeID = nil
        onCommit = nil
    }
}
