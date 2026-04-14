import Foundation

struct CanvasSnapshot: Codable {
    var nodes: [CanvasNode]
    var edges: [Edge]
    var cameraOffset: SIMD2<Float>
    var cameraZoom: Float
    var agentProfiles: [AgentProfile]?
}

enum Persistence {
    private static func saveURL(for projectPath: URL) -> URL {
        let dir = projectPath.appendingPathComponent(".xyzterminal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("canvas.json")
    }

    static func save(_ document: CanvasDocument) {
        guard let projectPath = document.projectPath else { return }
        let snapshot = CanvasSnapshot(
            nodes: Array(document.nodes.values),
            edges: Array(document.edges.values),
            cameraOffset: document.camera.offset,
            cameraZoom: document.camera.zoom,
            agentProfiles: Array(document.agentProfiles.values)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: saveURL(for: projectPath), options: .atomic)
        } catch {
            NSLog("Xyzterminal: failed to save canvas: %@", error.localizedDescription)
        }

        document.mcpServer?.terminalManager?.saveAllScrollback()
    }

    static func load(into document: CanvasDocument) {
        guard let projectPath = document.projectPath else { return }
        let url = saveURL(for: projectPath)
        do {
            let data = try Data(contentsOf: url)
            let snapshot = try JSONDecoder().decode(CanvasSnapshot.self, from: data)
            document.nodes = Dictionary(uniqueKeysWithValues: snapshot.nodes.map { ($0.id, $0) })
            document.edges = Dictionary(uniqueKeysWithValues: snapshot.edges.map { ($0.id, $0) })
            document.camera.offset = snapshot.cameraOffset
            document.camera.zoom = snapshot.cameraZoom
            if let profiles = snapshot.agentProfiles, !profiles.isEmpty {
                document.agentProfiles = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
            }
        } catch {
            NSLog("Xyzterminal: failed to load canvas: %@", error.localizedDescription)
        }
    }

    static var lastProjectPath: URL? {
        get {
            guard let path = UserDefaults.standard.string(forKey: "lastProjectPath") else { return nil }
            return URL(fileURLWithPath: path)
        }
        set {
            UserDefaults.standard.set(newValue?.path, forKey: "lastProjectPath")
        }
    }
}
