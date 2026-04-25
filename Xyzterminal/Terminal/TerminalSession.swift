import AppKit
import Combine
import SwiftTerm

final class TerminalSession: NSObject, LocalProcessTerminalViewDelegate, ObservableObject {
    let nodeID: UUID
    let terminalView: LocalProcessTerminalView
    var worktreePath: String?
    var onProcessTerminated: ((Int32?) -> Void)?
    @Published private(set) var isIdle: Bool = false
    private var lastAppliedZoom: Float = 1.0
    private var lastSavedBufferSize: Int = 0
    private var idleWorkItem: DispatchWorkItem?

    static let baseFontSize: CGFloat = 13
    static let idleThreshold: TimeInterval = 4.0

    init(nodeID: UUID) {
        self.nodeID = nodeID
        let view = ActivityAwareTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 270))
        self.terminalView = view
        super.init()
        view.onDataReceived = { [weak self] in self?.noteActivity() }
        terminalView.processDelegate = self
        terminalView.font = NSFont.monospacedSystemFont(ofSize: Self.baseFontSize, weight: .regular)
    }

    private func noteActivity() {
        if isIdle { isIdle = false }
        idleWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.isIdle = true }
        idleWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleThreshold, execute: item)
    }

    func sendStartupScript(_ script: String) {
        let bytes = Array("\(script)\n".utf8)
        terminalView.process?.send(data: bytes[...])
    }

    func saveScrollback(to dir: URL) {
        let data = terminalView.getTerminal().getBufferAsData()
        guard data.count != lastSavedBufferSize else { return }
        lastSavedBufferSize = data.count
        let file = dir.appendingPathComponent("\(nodeID.uuidString).txt")
        try? data.write(to: file, options: .atomic)
    }

    func restoreScrollback(from dir: URL) {
        let file = dir.appendingPathComponent("\(nodeID.uuidString).txt")
        guard let data = try? Data(contentsOf: file), !data.isEmpty else { return }
        terminalView.getTerminal().feed(byteArray: Array(data))
        terminalView.getTerminal().feed(text: "\r\n--- session restored ---\r\n\r\n")
    }

    func applyZoom(_ zoom: Float) {
        guard zoom != lastAppliedZoom else { return }
        lastAppliedZoom = zoom
        terminalView.font = NSFont.monospacedSystemFont(ofSize: Self.baseFontSize * CGFloat(zoom), weight: .regular)
    }

    func updateColors(theme: Theme) {
        terminalView.nativeBackgroundColor = theme.terminalBackground
        terminalView.nativeForegroundColor = theme.terminalForeground
    }

    func start(in directory: String? = nil) {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var env = Array(ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" })
        if let dir = directory {
            env.removeAll { $0.hasPrefix("PWD=") }
            env.append("PWD=\(dir)")
        }
        terminalView.startProcess(
            executable: shell,
            args: ["-l"],
            environment: env,
            execName: (shell as NSString).lastPathComponent,
            currentDirectory: directory
        )
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        idleWorkItem?.cancel()
        idleWorkItem = nil
        onProcessTerminated?(exitCode)
    }
}

private final class ActivityAwareTerminalView: LocalProcessTerminalView {
    var onDataReceived: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        registerForDraggedTypes(registeredDraggedTypes + [.fileURL, .tiff, .png])
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        onDataReceived?()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedPaths(sender).isEmpty ? super.draggingEntered(sender) : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedPaths(sender).isEmpty ? super.draggingUpdated(sender) : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let paths = droppedPaths(sender)
        guard !paths.isEmpty else { return super.performDragOperation(sender) }
        let bytes = Array(paths.map(Self.shellEscape).joined(separator: " ").utf8)
        process?.send(data: bytes[...])
        return true
    }

    private func droppedPaths(_ sender: NSDraggingInfo) -> [String] {
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !urls.isEmpty {
            return urls.filter(\.isFileURL).map(\.path)
        }
        if let image = NSImage(pasteboard: pb), let path = Self.writeTempPNG(image) {
            return [path]
        }
        return []
    }

    private static func writeTempPNG(_ image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return nil }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xyzterminal-\(UUID().uuidString.prefix(8)).png")
        do { try data.write(to: url); return url.path } catch { return nil }
    }

    private static func shellEscape(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
