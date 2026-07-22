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

    init(tabID: UUID, repoID: UUID, worktreeID: String, originTabID: UUID?) {
        self.tabID = tabID
        self.repoID = repoID
        self.worktreeID = worktreeID
        self.originTabID = originTabID
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
            let device = Self.firstBootedDevice()
            await MainActor.run {
                self.deviceName = device?.name
                if device == nil { self.frame = nil }
            }
            guard let udid = device?.udid else {
                try? await Task.sleep(for: .seconds(2))
                continue
            }
            await streamHelper(udid: udid)   // returns when the helper exits (device gone/error)
            await MainActor.run { self.frame = nil; self.isLive = false }
            if !Task.isCancelled { try? await Task.sleep(for: .seconds(1)) }
        }
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
        var udid: String?
        while !Task.isCancelled {
            if udid == nil {
                let device = Self.firstBootedDevice()
                udid = device?.udid
                await MainActor.run {
                    self.deviceName = device?.name
                    if device == nil { self.frame = nil }
                }
                if udid == nil {
                    try? await Task.sleep(for: .seconds(2))
                    continue
                }
            }
            let paused = await MainActor.run { self.markup.isMarkingUp }
            if !paused, let current = udid {
                if Self.xcrun(["simctl", "io", current, "screenshot", self.framePath]) != nil,
                   let data = try? Data(contentsOf: URL(fileURLWithPath: self.framePath)),
                   let image = NSImage(data: data) {
                    await MainActor.run { self.frame = image }
                } else {
                    udid = nil
                    continue
                }
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
