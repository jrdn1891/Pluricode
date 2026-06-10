import Foundation
import Network
import Observation

struct LocalHostEntry: Identifiable, Hashable {
    let id: UUID
    let workspaceID: UUID
    let tabID: UUID
    let url: URL
    let repoID: UUID
    let branch: String
    let discoveredAt: Date

    init(workspaceID: UUID, tabID: UUID, url: URL, repoID: UUID, branch: String) {
        self.id = UUID()
        self.workspaceID = workspaceID
        self.tabID = tabID
        self.url = url
        self.repoID = repoID
        self.branch = branch
        self.discoveredAt = Date()
    }
}

@Observable
final class LocalHostRegistry {
    private(set) var entries: [LocalHostEntry] = []

    @ObservationIgnored private var failures: [UUID: Int] = [:]
    @ObservationIgnored private var probeTask: Task<Void, Never>?

    static let probeInterval: Duration = .seconds(3)
    static let probeTimeout: TimeInterval = 1
    static let failureBudget = 2

    deinit {
        probeTask?.cancel()
    }

    func record(workspaceID: UUID, tabID: UUID, url: URL, repoID: UUID, branch: String) {
        if entries.contains(where: { $0.tabID == tabID && $0.url == url }) { return }
        entries.append(LocalHostEntry(
            workspaceID: workspaceID,
            tabID: tabID,
            url: url,
            repoID: repoID,
            branch: branch
        ))
        ensureProbing()
    }

    func remove(tabID: UUID) {
        for entry in entries where entry.tabID == tabID {
            failures.removeValue(forKey: entry.id)
        }
        entries.removeAll { $0.tabID == tabID }
    }

    func remove(workspaceID: UUID) {
        for entry in entries where entry.workspaceID == workspaceID {
            failures.removeValue(forKey: entry.id)
        }
        entries.removeAll { $0.workspaceID == workspaceID }
    }

    private func ensureProbing() {
        guard probeTask == nil, !entries.isEmpty else { return }
        probeTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: LocalHostRegistry.probeInterval)
                guard let self else { return }
                if self.entries.isEmpty {
                    self.probeTask = nil
                    return
                }
                await self.probeOnce()
            }
        }
    }

    @MainActor
    private func probeOnce() async {
        let snapshot = entries
        guard !snapshot.isEmpty else { return }
        let results = await withTaskGroup(of: (UUID, Bool).self) { group in
            for entry in snapshot {
                group.addTask {
                    (entry.id, await Self.isReachable(entry.url))
                }
            }
            var collected: [(UUID, Bool)] = []
            for await result in group { collected.append(result) }
            return collected
        }
        var doomed: Set<UUID> = []
        for (id, reachable) in results {
            if reachable {
                failures[id] = 0
            } else {
                let next = (failures[id] ?? 0) + 1
                if next >= Self.failureBudget {
                    doomed.insert(id)
                    failures.removeValue(forKey: id)
                } else {
                    failures[id] = next
                }
            }
        }
        if !doomed.isEmpty {
            entries.removeAll { doomed.contains($0.id) }
        }
    }

    private static func isReachable(_ url: URL) async -> Bool {
        guard let host = url.host, let port = port(for: url) else { return true }
        return await withCheckedContinuation { continuation in
            let probe = Probe(host: host, port: port, timeout: probeTimeout, continuation: continuation)
            probe.start()
        }
    }

    private static func port(for url: URL) -> NWEndpoint.Port? {
        if let p = url.port, (0...65535).contains(p) {
            return NWEndpoint.Port(integerLiteral: UInt16(p))
        }
        switch url.scheme {
        case "https": return .https
        case "http": return .http
        default: return nil
        }
    }
}

private final class Probe: @unchecked Sendable {
    private let connection: NWConnection
    private let continuation: CheckedContinuation<Bool, Never>
    private let lock = NSLock()
    private var settled = false

    init(host: String, port: NWEndpoint.Port, timeout: TimeInterval, continuation: CheckedContinuation<Bool, Never>) {
        self.connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        self.continuation = continuation
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.finish(true)
            case .failed, .cancelled: self?.finish(false)
            default: break
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.finish(false)
        }
    }

    func start() {
        connection.start(queue: .global())
    }

    private func finish(_ ok: Bool) {
        lock.lock()
        if settled { lock.unlock(); return }
        settled = true
        lock.unlock()
        connection.cancel()
        continuation.resume(returning: ok)
    }
}

final class LocalHostDetector {
    private var buffer: String = ""
    private let onURL: (URL) -> Void

    private static let maxBuffer = 512
    private static let urlRegex: NSRegularExpression = {
        let pattern = #"https?://(?:localhost|127\.0\.0\.1|0\.0\.0\.0)(?::(\d{2,5}))?(?:/[^\s'"<>\x1B`)\]]*)?"#
        return try! NSRegularExpression(pattern: pattern)
    }()
    private static let ansiRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]")
    }()

    init(onURL: @escaping (URL) -> Void) {
        self.onURL = onURL
    }

    func feed(_ slice: ArraySlice<UInt8>) {
        let chunk = String(decoding: slice, as: UTF8.self)
        let cleaned = chunk.contains("\u{1B}") ? Self.stripAnsi(chunk) : chunk
        buffer.append(cleaned)
        guard buffer.contains("http") else {
            trimBuffer()
            return
        }
        let ns = buffer as NSString
        let matches = Self.urlRegex.matches(in: buffer, range: NSRange(location: 0, length: ns.length))
        for match in matches {
            let raw = ns.substring(with: match.range)
            let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
            guard let url = Self.normalize(trimmed) else { continue }
            onURL(url)
        }
        if let last = matches.last {
            let end = last.range.location + last.range.length
            buffer = ns.substring(from: end == ns.length ? last.range.location : end)
        }
        trimBuffer()
    }

    private func trimBuffer() {
        if buffer.count > Self.maxBuffer {
            buffer = String(buffer.suffix(Self.maxBuffer))
        }
    }

    private static func normalize(_ raw: String) -> URL? {
        guard var components = URLComponents(string: raw) else { return nil }
        if components.host == "127.0.0.1" || components.host == "0.0.0.0" {
            components.host = "localhost"
        }
        if components.path == "/" { components.path = "" }
        return components.url
    }

    private static func stripAnsi(_ s: String) -> String {
        let ns = s as NSString
        return ansiRegex.stringByReplacingMatches(
            in: s,
            range: NSRange(location: 0, length: ns.length),
            withTemplate: ""
        )
    }
}
