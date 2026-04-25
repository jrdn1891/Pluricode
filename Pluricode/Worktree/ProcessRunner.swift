import Foundation

struct ProcessResult {
    var status: Int32
    var stdout: String
    var stderr: String

    var executableMissing: Bool { status == 127 }
}

enum ProcessRunner {
    static func run(_ executable: String, args: [String], cwd: URL? = nil) throws -> ProcessResult {
        guard let execURL = resolveExecutable(executable) else {
            return ProcessResult(status: 127, stdout: "", stderr: "executable not found: \(executable)")
        }
        let process = Process()
        process.executableURL = execURL
        process.arguments = args
        if let cwd { process.currentDirectoryURL = cwd }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return ProcessResult(
            status: process.terminationStatus,
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }

    private static func resolveExecutable(_ name: String) -> URL? {
        if name.contains("/") {
            return URL(fileURLWithPath: name)
        }
        let candidates = [
            "/usr/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            NSHomeDirectory() + "/.local/bin/\(name)",
        ]
        let fm = FileManager.default
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}
