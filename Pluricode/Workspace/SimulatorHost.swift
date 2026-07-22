import AppKit
import Observation

@Observable
final class SimulatorHost {
    let tabID: UUID
    let repoID: UUID
    let worktreeID: String
    let originTabID: UUID?
    let markup = Markup()

    var frame: NSImage?
    var deviceName: String?
    var isLive = false

    /// The device this pane is pinned to, or nil to follow the first booted device.
    @ObservationIgnored private var pinnedUDID: String?

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var liveProcess: Process?
    @ObservationIgnored private var liveStdin: FileHandle?
    @ObservationIgnored private let framePath =
        NSTemporaryDirectory() + "pluricode-simframe-\(UUID().uuidString.prefix(8)).png"

    static let simulatorInstalled =
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iphonesimulator") != nil

    // CoreSimulator-backed live streaming via the bundled plurisim helper, gated on a feature flag.
    // `defaults write com.pluricode.app useSimulatorLiveStream -bool YES`
    private static let liveStreamKey = "useSimulatorLiveStream"
    static let helperURL: URL? = {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/plurisim")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }()
    private static var liveStreamEnabled: Bool {
        UserDefaults.standard.bool(forKey: liveStreamKey) && helperURL != nil
    }

    init(tabID: UUID, repoID: UUID, worktreeID: String, originTabID: UUID?, pinnedUDID: String?) {
        self.tabID = tabID
        self.repoID = repoID
        self.worktreeID = worktreeID
        self.originTabID = originTabID
        self.pinnedUDID = pinnedUDID
        start()
    }

    func teardown() {
        pollTask?.cancel()
        pollTask = nil
        liveProcess?.terminate()
        liveProcess = nil
        try? FileManager.default.removeItem(atPath: framePath)
    }

    /// Injects a tap at normalized (0...1) coordinates from the top-left, via the live helper.
    func sendTap(x: Double, y: Double) {
        guard let stdin = liveStdin else { return }
        let fx = min(max(x, 0), 1), fy = min(max(y, 0), 1)
        try? stdin.write(contentsOf: Data("tap \(fx) \(fy)\n".utf8))
    }

    /// Drags from one normalized point to another (scroll / swipe), via the live helper.
    func sendSwipe(x0: Double, y0: Double, x1: Double, y1: Double) {
        guard let stdin = liveStdin else { return }
        func c(_ v: Double) -> Double { min(max(v, 0), 1) }
        try? stdin.write(contentsOf: Data("swipe \(c(x0)) \(c(y0)) \(c(x1)) \(c(y1))\n".utf8))
    }

    /// Types the characters of a string one Unicode scalar at a time, via the live helper.
    func sendText(_ text: String) {
        guard let stdin = liveStdin else { return }
        for scalar in text.unicodeScalars {
            try? stdin.write(contentsOf: Data("char \(scalar.value)\n".utf8))
        }
    }

    /// Presses the Home button, via the live helper.
    func sendHome() {
        try? liveStdin?.write(contentsOf: Data("home\n".utf8))
    }

    private func start() {
        let live = Self.liveStreamEnabled
        pollTask = Task.detached(priority: .utility) { [weak self] in
            if live { await self?.runLiveLoop() } else { await self?.runScreenshotLoop() }
        }
    }

    // MARK: - idb live stream

    private func runLiveLoop() async {
        while !Task.isCancelled {
            let device = resolveDevice()
            await MainActor.run {
                self.deviceName = device?.name
                if device == nil { self.frame = nil }
            }
            guard let udid = device?.udid else {
                try? await Task.sleep(for: .seconds(2))
                continue
            }
            await streamHelper(udid: udid)   // returns when the helper exits (device gone/switched)
            await MainActor.run { self.frame = nil; self.isLive = false }
            if !Task.isCancelled { try? await Task.sleep(for: .seconds(1)) }
        }
    }

    /// The device to show: the pinned one (booting it if needed), else the first booted device.
    private func resolveDevice() -> BootedDevice? {
        guard let pinnedUDID else { return Self.firstBootedDevice() }
        guard let info = Self.deviceInfo(udid: pinnedUDID) else { return Self.firstBootedDevice() }
        if info.state == "Booted" { return BootedDevice(udid: pinnedUDID, name: info.name) }
        Self.boot(udid: pinnedUDID)   // kick off boot; the loop retries until it is ready
        return nil
    }

    /// Pins the pane to a device (nil follows the first booted) and restarts streaming.
    func selectDevice(_ udid: String?) {
        pinnedUDID = udid
        if let udid { Self.boot(udid: udid) }
        liveProcess?.terminate()   // interrupt the current stream so the loop re-resolves
    }

    private func streamHelper(udid: String) async {
        guard let helper = Self.helperURL else { return }
        let process = Process()
        process.executableURL = helper
        process.arguments = [udid]
        var env = ProcessInfo.processInfo.environment
        env["DEVELOPER_DIR"] = Self.developerDir
        env["DYLD_FRAMEWORK_PATH"] = Self.tapFrameworkPath   // idb's Indigo touch-message builder
        process.environment = env
        let output = Pipe()
        let input = Pipe()
        process.standardOutput = output
        process.standardInput = input
        process.standardError = FileHandle.nullDevice
        liveProcess = process
        liveStdin = input.fileHandleForWriting

        var buffer = Data()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            buffer.append(data)
            while buffer.count >= 4 {
                let len = (Int(buffer[0]) << 24) | (Int(buffer[1]) << 16) | (Int(buffer[2]) << 8) | Int(buffer[3])
                let total = 4 + len
                guard buffer.count >= total else { break }
                let jpeg = buffer.subdata(in: 4..<total)
                buffer.removeSubrange(0..<total)
                guard let self, let image = NSImage(data: jpeg) else { continue }
                DispatchQueue.main.async {
                    if !self.markup.isMarkingUp { self.frame = image }
                }
            }
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
            do { try process.run(); Task { @MainActor in self.isLive = true } } catch { cont.resume() }
        }
        output.fileHandleForReading.readabilityHandler = nil
        try? liveStdin?.close()
        liveStdin = nil
        liveProcess = nil
    }

    private static let tapFrameworkPath = [
        "/opt/homebrew/opt/idb-companion/Frameworks",
        "/Library/Developer/PrivateFrameworks",
        developerDir + "/Library/PrivateFrameworks",
    ].joined(separator: ":")

    private static let developerDir: String = {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "/Applications/Xcode.app/Contents/Developer" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (path?.isEmpty == false) ? path! : "/Applications/Xcode.app/Contents/Developer"
    }()

    // MARK: - simctl screenshot fallback

    private func runScreenshotLoop() async {
        while !Task.isCancelled {
            let device = resolveDevice()
            await MainActor.run {
                self.deviceName = device?.name
                if device == nil { self.frame = nil }
            }
            guard let udid = device?.udid else {
                try? await Task.sleep(for: .seconds(2))
                continue
            }
            let paused = await MainActor.run { self.markup.isMarkingUp }
            if !paused,
               Self.xcrun(["simctl", "io", udid, "screenshot", self.framePath]) != nil,
               let data = try? Data(contentsOf: URL(fileURLWithPath: self.framePath)),
               let image = NSImage(data: data) {
                await MainActor.run { self.frame = image }
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    // MARK: - Device discovery

    private struct BootedDevice: Decodable {
        let udid: String
        let name: String
    }

    private struct DeviceList: Decodable {
        let devices: [String: [BootedDevice]]
    }

    private static func firstBootedDevice() -> BootedDevice? {
        guard let data = xcrun(["simctl", "list", "devices", "booted", "-j"]),
              let list = try? JSONDecoder().decode(DeviceList.self, from: data) else { return nil }
        return list.devices.values.flatMap { $0 }.first
    }

    struct DeviceOption: Identifiable, Hashable {
        let udid: String
        let name: String
        let runtime: String
        let isBooted: Bool
        var id: String { udid }
    }

    private struct FullEntry: Decodable {
        let udid: String
        let name: String
        let state: String
        let isAvailable: Bool?
    }

    private struct FullList: Decodable {
        let devices: [String: [FullEntry]]
    }

    private static func fullList() -> FullList? {
        guard let data = xcrun(["simctl", "list", "devices", "-j"]) else { return nil }
        return try? JSONDecoder().decode(FullList.self, from: data)
    }

    /// Available simulators for the picker, booted ones first, then grouped by runtime and name.
    static func availableDevices() -> [DeviceOption] {
        guard let list = fullList() else { return [] }
        var options: [DeviceOption] = []
        for (runtimeKey, devices) in list.devices {
            let runtime = prettyRuntime(runtimeKey)
            for d in devices where d.isAvailable != false {
                options.append(DeviceOption(udid: d.udid, name: d.name, runtime: runtime, isBooted: d.state == "Booted"))
            }
        }
        return options.sorted {
            ($0.isBooted ? 0 : 1, $0.runtime, $0.name) < ($1.isBooted ? 0 : 1, $1.runtime, $1.name)
        }
    }

    private static func deviceInfo(udid: String) -> (name: String, state: String)? {
        guard let list = fullList() else { return nil }
        for devices in list.devices.values {
            if let d = devices.first(where: { $0.udid == udid }) { return (d.name, d.state) }
        }
        return nil
    }

    private static func boot(udid: String) {
        _ = xcrun(["simctl", "boot", udid])   // harmless no-op if already booted
    }

    // com.apple.CoreSimulator.SimRuntime.iOS-26-2 -> "iOS 26.2"
    private static func prettyRuntime(_ key: String) -> String {
        guard let tail = key.components(separatedBy: ".SimRuntime.").last else { return key }
        let parts = tail.components(separatedBy: "-")
        guard parts.count >= 2 else { return tail }
        return parts[0] + " " + parts[1...].joined(separator: ".")
    }

    private static func xcrun(_ args: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = args
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}
