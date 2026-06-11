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

    static func run(
        _ executable: String,
        args: [String],
        cwd: URL? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> ProcessResult {
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
        let outData = drain(stdout)
        let errData = drain(stderr)
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
                if let timeout {
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        if process.isRunning { process.terminate() }
                    }
                }
            } catch {
                process.terminationHandler = nil
                try? stdout.fileHandleForWriting.close()
                try? stderr.fileHandleForWriting.close()
                continuation.resume(throwing: error)
            }
        }
        return ProcessResult(
            status: status,
            stdout: String(data: await outData.value, encoding: .utf8) ?? "",
            stderr: String(data: await errData.value, encoding: .utf8) ?? ""
        )
    }

    private static func drain(_ pipe: Pipe) -> Task<Data, Never> {
        Task {
            await withCheckedContinuation { (continuation: CheckedContinuation<Data, Never>) in
                DispatchQueue.global().async {
                    continuation.resume(returning: pipe.fileHandleForReading.readDataToEndOfFile())
                }
            }
        }
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
