import Foundation

struct ProcessResult {
    var status: Int32
    var stdout: String
    var stderr: String

    var executableMissing: Bool { status == 127 }
}

enum ProcessRunner {
    private static let searchPaths = [
        "/usr/bin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
        NSHomeDirectory() + "/.local/bin",
    ]

    static func run(_ executable: String, args: [String], cwd: URL? = nil) throws -> ProcessResult {
        guard let execURL = resolveExecutable(executable) else {
            return ProcessResult(status: 127, stdout: "", stderr: "executable not found: \(executable)")
        }
        let process = Process()
        process.executableURL = execURL
        process.arguments = args
        if let cwd { process.currentDirectoryURL = cwd }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (searchPaths + [env["PATH"]].compactMap { $0 }).joined(separator: ":")
        process.environment = env
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        DispatchQueue.global().async(group: group) {
            outData = stdout.fileHandleForReading.readDataToEndOfFile()
        }
        DispatchQueue.global().async(group: group) {
            errData = stderr.fileHandleForReading.readDataToEndOfFile()
        }
        process.waitUntilExit()
        group.wait()
        return ProcessResult(
            status: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    private static func resolveExecutable(_ name: String) -> URL? {
        if name.contains("/") {
            return URL(fileURLWithPath: name)
        }
        let fm = FileManager.default
        for dir in searchPaths {
            let path = "\(dir)/\(name)"
            if fm.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
}
