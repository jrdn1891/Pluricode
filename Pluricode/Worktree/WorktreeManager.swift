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
        self.worktreeRoot = repoRoot.appendingPathComponent(".pluricode/worktrees", isDirectory: true)
        try? FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
    }

    func createWorktree(name: String, baseBranch: String) throws -> URL {
        let path = worktreeRoot.appendingPathComponent(name)
        let branchName = "pluri-\(name)"
        if baseBranch.hasPrefix("origin/") {
            _ = try? run("git", args: ["-C", repoRoot.path, "fetch", "origin", "--quiet"])
        }
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
        let newBranch = "pluri-\(newName)"
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

    static func isMerged(at path: URL) -> Bool {
        guard let branch = try? run("git", args: [
            "-C", path.path, "rev-parse", "--abbrev-ref", "HEAD"
        ]), branch.status == 0 else { return false }
        let name = branch.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "HEAD" else { return false }

        guard let result = try? run("gh", args: [
            "pr", "list", "--state", "merged", "--head", name, "--limit", "1", "--json", "number"
        ], cwd: path), result.status == 0 else { return false }

        let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return !out.isEmpty && out != "[]"
    }

    static func diffStats(at path: URL) -> DiffStats {
        guard let base = baseCommit(at: path) else { return .zero }
        var adds = 0
        var dels = 0
        if let result = try? run("git", args: [
            "-C", path.path, "diff", base, "--numstat"
        ]), result.status == 0 {
            for line in result.stdout.components(separatedBy: "\n") where !line.isEmpty {
                let parts = line.split(separator: "\t")
                guard parts.count >= 2 else { continue }
                adds += Int(parts[0]) ?? 0
                dels += Int(parts[1]) ?? 0
            }
        }
        if let result = try? run("git", args: [
            "-C", path.path, "ls-files", "--others", "--exclude-standard", "-z"
        ]), result.status == 0 {
            let entries = result.stdout.split(separator: "\0", omittingEmptySubsequences: true)
            for rel in entries.prefix(untrackedFileLimit) {
                adds += countLines(at: path.appendingPathComponent(String(rel)))
            }
        }
        return DiffStats(additions: adds, deletions: dels)
    }

    private static let untrackedFileLimit = 500
    private static let untrackedFileSizeLimit = 5_000_000

    private static func countLines(at url: URL) -> Int {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.intValue,
              size > 0, size <= untrackedFileSizeLimit else { return 0 }
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return 0 }
        if data.prefix(8192).contains(0) { return 0 }
        var count = 0
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for byte in raw where byte == 0x0A { count += 1 }
        }
        if let last = data.last, last != 0x0A { count += 1 }
        return count
    }

    private static func baseCommit(at path: URL) -> String? {
        var base = "main"
        if let result = try? run("git", args: [
            "-C", path.path, "symbolic-ref", "refs/remotes/origin/HEAD", "--short"
        ]), result.status == 0 {
            let name = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { base = name }
        }
        guard let result = try? run("git", args: [
            "-C", path.path, "merge-base", "HEAD", base
        ]), result.status == 0 else { return nil }
        let sha = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return sha.isEmpty ? nil : sha
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

    func defaultBaseRef() -> String {
        if let result = try? run("git", args: [
            "-C", repoRoot.path,
            "symbolic-ref", "refs/remotes/origin/HEAD", "--short"
        ]), result.status == 0 {
            let ref = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ref.isEmpty { return ref }
        }
        return defaultBranch()
    }

    static func findRepoRoot(from path: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) -> URL? {
        guard let result = try? run("git", args: ["-C", path.path, "rev-parse", "--show-toplevel"]),
              result.status == 0 else { return nil }
        let root = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return root.isEmpty ? nil : URL(fileURLWithPath: root)
    }

    private static func run(_ executable: String, args: [String], cwd: URL? = nil) throws -> ProcessResult {
        try ProcessRunner.run(executable, args: args, cwd: cwd)
    }

    private func run(_ executable: String, args: [String], cwd: URL? = nil) throws -> ProcessResult {
        try ProcessRunner.run(executable, args: args, cwd: cwd)
    }
}

struct DiffStats: Equatable, Sendable {
    var additions: Int
    var deletions: Int
    var isClean: Bool { additions == 0 && deletions == 0 }
    static let zero = DiffStats(additions: 0, deletions: 0)
}

enum WorktreeError: Error {
    case createFailed(String)
    case noRepo
}
