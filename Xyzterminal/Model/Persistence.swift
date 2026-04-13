import Foundation

struct CanvasSnapshot: Codable {
    var nodes: [CanvasNode]
    var edges: [Edge]
    var cameraOffset: SIMD2<Float>
    var cameraZoom: Float
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
            cameraZoom: document.camera.zoom
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: saveURL(for: projectPath), options: .atomic)
    }

    static func load(into document: CanvasDocument) {
        guard let projectPath = document.projectPath else { return }
        let url = saveURL(for: projectPath)
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(CanvasSnapshot.self, from: data) else { return }

        document.nodes = Dictionary(uniqueKeysWithValues: snapshot.nodes.map { ($0.id, $0) })
        document.edges = Dictionary(uniqueKeysWithValues: snapshot.edges.map { ($0.id, $0) })
        document.camera.offset = snapshot.cameraOffset
        document.camera.zoom = snapshot.cameraZoom
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
