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
    var onLocalHostDiscovered: ((URL) -> Void)?
    @Published private(set) var isIdle: Bool = false
    @Published private(set) var pendingAttachments: [PendingImageAttachment] = []
    private var lastAppliedZoom: Float = 1.0
    private var lastSavedBufferSize: Int = 0
    private var idleWorkItem: DispatchWorkItem?
    private var isHovering: Bool = false
    private lazy var hostDetector: LocalHostDetector = LocalHostDetector { [weak self] url in
        self?.onLocalHostDiscovered?(url)
    }

    static let baseFontSize: CGFloat = 13
    static let idleThreshold: TimeInterval = 4.0
    static let scrollbackLines: Int = 20_000
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "webp", "heic", "tiff", "tif"]

    var onFocus: (() -> Void)?

    init(nodeID: UUID) {
        self.nodeID = nodeID
        let view = ActivityAwareTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 270))
        self.terminalView = view
        super.init()
        view.onActivity = { [weak self] in self?.noteActivity() }
        view.onRawData = { [weak self] slice in self?.hostDetector.feed(slice) }
        view.onAttachImage = { [weak self] attachment in self?.attach(attachment) }
        view.flushAttachments = { [weak self] in self?.flushAttachmentInjection() }
        view.onMouseDown = { [weak self] in self?.onFocus?() }
        view.onHoverChange = { [weak self] hovering in self?.setHovering(hovering) }
        terminalView.processDelegate = self
        terminalView.font = NSFont.monospacedSystemFont(ofSize: Self.baseFontSize, weight: .regular)
        terminalView.changeScrollback(Self.scrollbackLines)
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
        idleWorkItem = nil
        guard !isHovering else { return }
        let item = DispatchWorkItem { [weak self] in self?.isIdle = true }
        idleWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleThreshold, execute: item)
    }

    private func setHovering(_ hovering: Bool) {
        guard isHovering != hovering else { return }
        isHovering = hovering
        if hovering {
            if isIdle { isIdle = false }
            idleWorkItem?.cancel()
            idleWorkItem = nil
        } else {
            noteActivity()
        }
    }

    func sendStartupScript(_ script: String) {
        let bytes = Array("\(script)\n".utf8)
        terminalView.process?.send(data: bytes[...])
    }

    func sendMarkup(note: String, imagePath: String) {
        let escaped = Self.shellEscape(imagePath)
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let line = (trimmed.isEmpty ? escaped : "\(trimmed) \(escaped)") + "\n"
        terminalView.process?.send(data: Array(line.utf8)[...])
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
        terminalView.installColors(theme.terminalPalette)
    }

    func start(in directory: String? = nil) {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        if let dir = directory { env["PWD"] = dir }
        terminalView.startProcess(
            executable: shell,
            args: ["-l"],
            environment: env.map { "\($0.key)=\($0.value)" },
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
    var onRawData: ((ArraySlice<UInt8>) -> Void)?
    var onAttachImage: ((PendingImageAttachment) -> Void)?
    var flushAttachments: (() -> String?)?
    var onMouseDown: (() -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var hoverTrackingArea: NSTrackingArea?
    private lazy var hoverObserver = HoverObserver { [weak self] hovering in self?.onHoverChange?(hovering) }
    private var metalCancellable: AnyCancellable?

    private let promiseQueue = OperationQueue()

    override init(frame: CGRect) {
        super.init(frame: frame)
        let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        registerForDraggedTypes(registeredDraggedTypes + [.fileURL, .tiff, .png] + promiseTypes)
        metalCancellable = TerminalSettings.shared.$useMetalRenderer
            .sink { [weak self] _ in self?.applyMetalRenderer() }
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    deinit {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = mouseMonitor { NSEvent.removeMonitor(monitor) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            if keyMonitor == nil {
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    self?.interceptReturn(event)
                    return event
                }
            }
            if mouseMonitor == nil {
                mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                    self?.captureFocusIfHit(event)
                    return event
                }
            }
            if hoverTrackingArea == nil {
                let area = NSTrackingArea(
                    rect: .zero,
                    options: [.mouseEnteredAndExited, .inVisibleRect, .activeInActiveApp],
                    owner: hoverObserver,
                    userInfo: nil
                )
                addTrackingArea(area)
                hoverTrackingArea = area
            }
        } else {
            if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
            keyMonitor = nil
            if let monitor = mouseMonitor { NSEvent.removeMonitor(monitor) }
            mouseMonitor = nil
            if let area = hoverTrackingArea { removeTrackingArea(area) }
            hoverTrackingArea = nil
            onHoverChange?(false)
        }
        applyMetalRenderer()
    }

    private func captureFocusIfHit(_ event: NSEvent) {
        guard let window, event.window === window else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        if window.firstResponder !== self {
            window.makeFirstResponder(self)
        }
        onActivity?()
        onMouseDown?()
    }

    private func applyMetalRenderer() {
        guard window != nil else { return }
        try? setUseMetal(TerminalSettings.shared.useMetalRenderer)
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
        onRawData?(slice)
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
            handle(urls: urls)
            return true
        }

        if receivePromisedFiles(from: sender) {
            return true
        }

        if let image = NSImage(pasteboard: pb), let path = Self.writeTempPNG(image) {
            handle(urls: [URL(fileURLWithPath: path)])
            return true
        }
        return false
    }

    private func handle(urls: [URL]) {
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
    }

    private func receivePromisedFiles(from sender: NSDraggingInfo) -> Bool {
        var receivers: [NSFilePromiseReceiver] = []
        sender.enumerateDraggingItems(
            options: [],
            for: self,
            classes: [NSFilePromiseReceiver.self],
            searchOptions: [:]
        ) { item, _, _ in
            if let receiver = item.item as? NSFilePromiseReceiver {
                receivers.append(receiver)
            }
        }
        guard !receivers.isEmpty else { return false }
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
        for receiver in receivers {
            receiver.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: promiseQueue) { [weak self] url, error in
                guard error == nil else { return }
                DispatchQueue.main.async { self?.handle(urls: [url]) }
            }
        }
        return true
    }

    private func hasAcceptableDrop(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           urls.contains(where: \.isFileURL) {
            return true
        }
        if pb.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil) {
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

private final class HoverObserver: NSResponder {
    private let callback: (Bool) -> Void

    init(callback: @escaping (Bool) -> Void) {
        self.callback = callback
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func mouseEntered(with event: NSEvent) { callback(true) }
    override func mouseExited(with event: NSEvent) { callback(false) }
}
