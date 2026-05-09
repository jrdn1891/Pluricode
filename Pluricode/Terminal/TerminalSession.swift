import AppKit
import Combine
import SwiftTerm

struct PendingImageAttachment: Identifiable, Equatable {
    let id = UUID()
    let path: String
    let displayName: String
    let thumbnail: NSImage?
}

final class TerminalSession: NSObject, LocalProcessTerminalViewDelegate, ObservableObject {
    let nodeID: UUID
    let terminalView: LocalProcessTerminalView
    var worktreePath: String?
    var onProcessTerminated: ((Int32?) -> Void)?
    @Published private(set) var isIdle: Bool = false
    @Published private(set) var pendingAttachments: [PendingImageAttachment] = []
    private var lastAppliedZoom: Float = 1.0
    private var lastSavedBufferSize: Int = 0
    private var idleWorkItem: DispatchWorkItem?

    static let baseFontSize: CGFloat = 13
    static let idleThreshold: TimeInterval = 4.0
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "webp", "heic", "tiff", "tif"]

    init(nodeID: UUID) {
        self.nodeID = nodeID
        let view = ActivityAwareTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 270))
        self.terminalView = view
        super.init()
        view.onActivity = { [weak self] in self?.noteActivity() }
        view.onAttachImage = { [weak self] attachment in self?.attach(attachment) }
        view.flushAttachments = { [weak self] in self?.flushAttachmentInjection() }
        terminalView.processDelegate = self
        terminalView.font = NSFont.monospacedSystemFont(ofSize: Self.baseFontSize, weight: .regular)
    }

    static func isImagePath(_ path: String) -> Bool {
        imageExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    func removeAttachment(id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    private func attach(_ attachment: PendingImageAttachment) {
        pendingAttachments.append(attachment)
    }

    private func flushAttachmentInjection() -> String? {
        guard !pendingAttachments.isEmpty else { return nil }
        let joined = pendingAttachments.map { Self.shellEscape($0.path) }.joined(separator: " ")
        pendingAttachments.removeAll()
        return " " + joined
    }

    private static func shellEscape(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
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
        if let palette = theme.terminalPalette {
            terminalView.installColors(palette)
        }
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

    func scrolled(source: TerminalView, position: Double) {
        noteActivity()
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        idleWorkItem?.cancel()
        idleWorkItem = nil
        onProcessTerminated?(exitCode)
    }
}

private final class ActivityAwareTerminalView: LocalProcessTerminalView {
    var onActivity: (() -> Void)?
    var onAttachImage: ((PendingImageAttachment) -> Void)?
    var flushAttachments: (() -> String?)?
    private var keyMonitor: Any?

    override init(frame: CGRect) {
        super.init(frame: frame)
        registerForDraggedTypes(registeredDraggedTypes + [.fileURL, .tiff, .png])
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    deinit {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.interceptReturn(event)
                return event
            }
        } else if window == nil, let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func interceptReturn(_ event: NSEvent) {
        guard event.keyCode == 36,
              !event.modifierFlags.contains(.shift),
              window?.firstResponder === self,
              let injection = flushAttachments?() else { return }
        process?.send(data: Array(injection.utf8)[...])
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        onActivity?()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        hasAcceptableDrop(sender) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        hasAcceptableDrop(sender) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        let urls = (pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.filter(\.isFileURL) ?? []

        if !urls.isEmpty {
            let imageURLs = urls.filter { TerminalSession.isImagePath($0.path) }
            let nonImageURLs = urls.filter { !TerminalSession.isImagePath($0.path) }
            for url in imageURLs {
                let thumb = NSImage(contentsOfFile: url.path)
                onAttachImage?(PendingImageAttachment(path: url.path, displayName: url.lastPathComponent, thumbnail: thumb))
            }
            if !nonImageURLs.isEmpty {
                let bytes = Array(nonImageURLs.map { Self.shellEscape($0.path) }.joined(separator: " ").utf8)
                process?.send(data: bytes[...])
            }
            return true
        }

        if let image = NSImage(pasteboard: pb), let path = Self.writeTempPNG(image) {
            let thumb = NSImage(contentsOfFile: path)
            onAttachImage?(PendingImageAttachment(path: path, displayName: (path as NSString).lastPathComponent, thumbnail: thumb))
            return true
        }
        return false
    }

    private func hasAcceptableDrop(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           urls.contains(where: \.isFileURL) {
            return true
        }
        return NSImage(pasteboard: pb) != nil
    }

    private static func writeTempPNG(_ image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return nil }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pluricode-\(UUID().uuidString.prefix(8)).png")
        do { try data.write(to: url); return url.path } catch { return nil }
    }

    private static func shellEscape(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
