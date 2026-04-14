import Foundation

struct WorktreeInfo {
    var path: String
    var branch: String
    var head: String
}

final class WorktreeManager {
    let repoRoot: URL
    let worktreeRoot: URL

    init?(repoRoot: URL) {
        self.repoRoot = repoRoot
        self.worktreeRoot = repoRoot.appendingPathComponent(".xyzterminal/worktrees", isDirectory: true)
        try? FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
    }

    func createWorktree(name: String, baseBranch: String) throws -> URL {
        let path = worktreeRoot.appendingPathComponent(name)
        let branchName = "xyz-\(name)"
        let result = try run("git", args: [
            "-C", repoRoot.path,
            "worktree", "add",
            path.path,
            "-b", branchName,
            baseBranch
        ])
        if result.status != 0 {
            let fallback = try run("git", args: [
                "-C", repoRoot.path,
                "worktree", "add",
                path.path,
                baseBranch
            ])
            if fallback.status != 0 {
                throw WorktreeError.createFailed(fallback.stderr)
            }
        }
        return path
    }

    func removeWorktree(at path: URL) throws {
        let result = try run("git", args: [
            "-C", repoRoot.path,
            "worktree", "remove",
            path.path,
            "--force"
        ])
        if result.status != 0 {
            try? FileManager.default.removeItem(at: path)
            _ = try run("git", args: ["-C", repoRoot.path, "worktree", "prune"])
        }
    }

    func listWorktrees() throws -> [WorktreeInfo] {
        let result = try run("git", args: ["-C", repoRoot.path, "worktree", "list", "--porcelain"])
        guard result.status == 0 else { return [] }

        var worktrees: [WorktreeInfo] = []
        var path = "", branch = "", head = ""

        for line in result.stdout.components(separatedBy: "\n") {
            if line.hasPrefix("worktree ") {
                if !path.isEmpty {
                    worktrees.append(WorktreeInfo(path: path, branch: branch, head: head))
                }
                path = String(line.dropFirst(9))
                branch = ""
                head = ""
            } else if line.hasPrefix("HEAD ") {
                head = String(line.dropFirst(5).prefix(8))
            } else if line.hasPrefix("branch ") {
                branch = String(line.dropFirst(7))
                if let last = branch.split(separator: "/").last {
                    branch = String(last)
                }
            }
        }
        if !path.isEmpty {
            worktrees.append(WorktreeInfo(path: path, branch: branch, head: head))
        }
        return worktrees
    }

    func uncommittedCount(at path: URL) -> Int {
        guard let result = try? run("git", args: ["-C", path.path, "status", "--porcelain"]),
              result.status == 0 else { return 0 }
        return result.stdout.components(separatedBy: "\n").filter { !$0.isEmpty }.count
    }

    func currentBranch(at path: URL) -> String? {
        guard let result = try? run("git", args: ["-C", path.path, "rev-parse", "--abbrev-ref", "HEAD"]),
              result.status == 0 else { return nil }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func defaultBranch() -> String {
        if let result = try? run("git", args: [
            "-C", repoRoot.path,
            "symbolic-ref", "refs/remotes/origin/HEAD", "--short"
        ]), result.status == 0 {
            let branch = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if let last = branch.split(separator: "/").last { return String(last) }
            return branch
        }
        return "main"
    }

    static func findRepoRoot(from path: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) -> URL? {
        guard let result = try? run("git", args: ["-C", path.path, "rev-parse", "--show-toplevel"]),
              result.status == 0 else { return nil }
        let root = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return root.isEmpty ? nil : URL(fileURLWithPath: root)
    }

    private static func run(_ executable: String, args: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/\(executable)")
        process.arguments = args
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

    private func run(_ executable: String, args: [String]) throws -> ProcessResult {
        try Self.run(executable, args: args)
    }
}

struct ProcessResult {
    var status: Int32
    var stdout: String
    var stderr: String
}

enum WorktreeError: Error {
    case createFailed(String)
    case noRepo
}
