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

    func listManagedWorktrees() -> [Worktree] {
        let rootPath = worktreeRoot.standardizedFileURL.path
        let primaryPath = repoRoot.standardizedFileURL.path
        let all = (try? listWorktrees()) ?? []

        var result: [Worktree] = []
        if let primary = all.first(where: {
            URL(fileURLWithPath: $0.path).standardizedFileURL.path == primaryPath
        }) {
            result.append(Worktree(
                branch: primary.branch.isEmpty ? defaultBranch() : primary.branch,
                path: primary.path,
                head: primary.head,
                isPrimary: true
            ))
        }

        let managed = all
            .filter { URL(fileURLWithPath: $0.path).standardizedFileURL.path.hasPrefix(rootPath) }
            .map { Worktree(branch: $0.branch, path: $0.path, head: $0.head, isPrimary: false) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        result.append(contentsOf: managed)
        return result
    }

    func renameWorktree(oldBranch: String, newName: String) throws -> Worktree {
        let newBranch = "xyz-\(newName)"
        guard newBranch != oldBranch else {
            let info = try listWorktrees().first { $0.branch == oldBranch }
            guard let info else { throw WorktreeError.createFailed("worktree not found") }
            return Worktree(branch: info.branch, path: info.path, head: info.head, isPrimary: false)
        }

        guard let info = try listWorktrees().first(where: { $0.branch == oldBranch }) else {
            throw WorktreeError.createFailed("worktree not found")
        }
        let oldPath = URL(fileURLWithPath: info.path)
        let newPath = worktreeRoot.appendingPathComponent(newName)

        if oldPath.standardizedFileURL != newPath.standardizedFileURL {
            let move = try run("git", args: ["-C", repoRoot.path, "worktree", "move", oldPath.path, newPath.path])
            if move.status != 0 {
                throw WorktreeError.createFailed(move.stderr)
            }
        }

        let rename = try run("git", args: ["-C", repoRoot.path, "branch", "-m", oldBranch, newBranch])
        if rename.status != 0 {
            throw WorktreeError.createFailed(rename.stderr)
        }

        let updated = try listWorktrees().first { $0.branch == newBranch }
        guard let updated else { throw WorktreeError.createFailed("rename failed to resolve") }
        return Worktree(branch: updated.branch, path: updated.path, head: updated.head, isPrimary: false)
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
