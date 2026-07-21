import Foundation

enum WorkerHooks {
    static var eventsDir: URL {
        PluriHome.dir.appendingPathComponent("events", isDirectory: true)
    }

    static func install(atWorktree path: String) {
        let claudeDir = URL(fileURLWithPath: path).appendingPathComponent(".claude", isDirectory: true)
        let file = claudeDir.appendingPathComponent("settings.local.json")
        if let data = try? Data(contentsOf: file) {
            guard let existing = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  Set(existing.keys) == ["hooks"] else { return }
        }
        let events = eventsDir.path
        let command = "f=\"$(/usr/bin/uuidgen)\" && cat > \"\(events)/$f.tmp\" && mv \"\(events)/$f.tmp\" \"\(events)/$f.json\""
        let hook: [String: Any] = ["hooks": [["type": "command", "command": command]]]
        let names = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop", "SessionEnd"]
        let settings: [String: Any] = ["hooks": names.reduce(into: [String: Any]()) { $0[$1] = [hook] }]
        try? FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: file, options: .atomic)
        }
    }
}
