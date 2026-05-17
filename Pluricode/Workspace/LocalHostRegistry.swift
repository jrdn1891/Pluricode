import Foundation
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

    func record(workspaceID: UUID, tabID: UUID, url: URL, repoID: UUID, branch: String) {
        if entries.contains(where: { $0.tabID == tabID && $0.url == url }) { return }
        entries.append(LocalHostEntry(
            workspaceID: workspaceID,
            tabID: tabID,
            url: url,
            repoID: repoID,
            branch: branch
        ))
    }

    func remove(tabID: UUID) {
        entries.removeAll { $0.tabID == tabID }
    }

    func remove(workspaceID: UUID) {
        entries.removeAll { $0.workspaceID == workspaceID }
    }
}

final class LocalHostDetector {
    private var buffer: String = ""
    private let onURL: (URL) -> Void
    private var seen: Set<URL> = []

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
        let cleaned = Self.stripAnsi(chunk)
        buffer.append(cleaned)
        let ns = buffer as NSString
        let matches = Self.urlRegex.matches(in: buffer, range: NSRange(location: 0, length: ns.length))
        for match in matches {
            let raw = ns.substring(with: match.range)
            let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
            guard let url = Self.normalize(trimmed) else { continue }
            if seen.insert(url).inserted {
                onURL(url)
            }
        }
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
