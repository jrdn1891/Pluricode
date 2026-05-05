import Foundation

@MainActor
struct MCPTools {
    let workspace: Workspace
    let callerWorktreeBranch: String?

    func handle(method: String, params: JSONValue?) async throws -> JSONValue {
        switch method {
        case "initialize":
            return Self.initializeResult
        case "notifications/initialized":
            return .null
        case "tools/list":
            return Self.toolsList
        case "tools/call":
            return try await callTool(params: params)
        case "ping":
            return .object([:])
        default:
            throw JSONRPCError.methodNotFound
        }
    }

    private func callTool(params: JSONValue?) async throws -> JSONValue {
        guard let name = params?["name"]?.stringValue else {
            throw JSONRPCError.invalid("missing tool name")
        }
        let arguments = params?["arguments"] ?? .object([:])
        do {
            let result = try await dispatch(name: name, args: arguments)
            return Self.toolResult(text: result, isError: false)
        } catch let err as JSONRPCError {
            return Self.toolResult(text: .string(err.message), isError: true)
        } catch {
            return Self.toolResult(text: .string("\(error)"), isError: true)
        }
    }

    private func dispatch(name: String, args: JSONValue) async throws -> JSONValue {
        switch name {
        case "spawn_terminal":   return try await spawnTerminal(args)
        case "list_worktrees":   return listWorktrees(args)
        case "list_panes":       return listPanes()
        case "list_profiles":    return listProfiles()
        case "list_repos":       return listRepos()
        case "send_prompt":      return try await sendPrompt(args)
        case "read_terminal":    return try readTerminal(args)
        case "close_pane":       return try closePane(args)
        case "list_task_lists":  return listTaskLists()
        case "list_tasks":       return try listTasks(args)
        case "add_task":         return try addTask(args)
        case "set_task_done":    return try setTaskDone(args)
        default:
            throw JSONRPCError.application("unknown tool: \(name)")
        }
    }

    private func spawnTerminal(_ args: JSONValue) async throws -> JSONValue {
        let repoID = try resolveRepo(args["repo_id"]?.stringValue)
        let baseBranch = args["base_branch"]?.stringValue
        let profileID = try resolveProfile(args["profile_id"]?.stringValue)
        let name = args["name"]?.stringValue
        let prompt = args["prompt"]?.stringValue
        let split = args["split"]?.stringValue

        let summary = spawnSummary(
            repoID: repoID,
            profileID: profileID,
            name: name,
            prompt: prompt,
            split: split
        )
        let approved = await workspace.evaluateSpawnPolicy(summary: summary)
        guard approved else { throw JSONRPCError.application("spawn denied by user") }

        let result = try await workspace.spawnTerminal(
            repoID: repoID,
            baseBranch: baseBranch,
            profileID: profileID,
            name: name,
            prompt: prompt,
            split: split.flatMap(SpawnSplit.init(rawValue:)) ?? .right
        )
        return .object([
            "pane_id": .string(result.paneID.uuidString),
            "tab_id": .string(result.tabID.uuidString),
            "worktree_branch": .string(result.worktreeBranch),
            "path": .string(result.path)
        ])
    }

    private func listWorktrees(_ args: JSONValue) -> JSONValue {
        let filterRepoID: UUID? = (args["repo_id"]?.stringValue).flatMap(UUID.init(uuidString:))
        let includeGit = args["include_git_state"]?.boolValue ?? false
        var out: [JSONValue] = []
        for repo in workspace.repoStore.repos {
            if let filter = filterRepoID, repo.id != filter { continue }
            guard let wm = WorktreeManager(repoRoot: repo.path) else { continue }
            let baseRef = includeGit ? wm.defaultBaseRef() : ""
            for w in wm.listManagedWorktrees() where !w.isPrimary {
                let url = URL(fileURLWithPath: w.path)
                let config = WorktreeConfig.load(at: w.path)
                let profileName = config.agentProfileID
                    .flatMap { workspace.profileStore.profile(id: $0) }?.name
                var entry: [String: JSONValue] = [
                    "repo_id": .string(repo.id.uuidString),
                    "branch": .string(w.branch),
                    "display_name": .string(w.displayName),
                    "path": .string(w.path),
                    "head": .string(w.head),
                    "profile": profileName.map { .string($0) } ?? .null,
                    "uncommitted": .int(Int64(wm.uncommittedCount(at: url)))
                ]
                if includeGit {
                    let stats = WorktreeManager.diffStats(at: url)
                    let ab = WorktreeManager.aheadBehind(at: url, base: baseRef)
                    entry["additions"] = .int(Int64(stats.additions))
                    entry["deletions"] = .int(Int64(stats.deletions))
                    entry["ahead"] = .int(Int64(ab.ahead))
                    entry["behind"] = .int(Int64(ab.behind))
                    entry["has_open_pr"] = .bool(WorktreeManager.hasOpenPR(at: url))
                    entry["is_merged"] = .bool(WorktreeManager.isMerged(at: url))
                }
                out.append(.object(entry))
            }
        }
        return .array(out)
    }

    private func listPanes() -> JSONValue {
        var out: [JSONValue] = []
        for pane in workspace.tiling.panes {
            for tab in pane.tabs {
                var entry: [String: JSONValue] = [
                    "pane_id": .string(pane.id.uuidString),
                    "tab_id": .string(tab.id.uuidString),
                    "active": .bool(tab.id == pane.activeTabID)
                ]
                switch tab.content {
                case .terminal(let repoID, let worktreeID):
                    entry["kind"] = .string("terminal")
                    entry["repo_id"] = .string(repoID.uuidString)
                    entry["worktree_branch"] = .string(worktreeID)
                    if let p = workspace.tabProfile(tabID: tab.id) {
                        entry["profile"] = .string(p.name)
                    }
                    if let host = workspace.terminalHosts[tab.id] {
                        entry["is_idle"] = .bool(host.session.isIdle)
                        entry["idle_since_ms"] = host.session.idleSince
                            .map { .int(Int64(Date().timeIntervalSince($0) * 1000)) } ?? .null
                    }
                case .tasks(let listID):
                    entry["kind"] = .string("tasks")
                    entry["list_id"] = .string(listID.uuidString)
                case .stats:
                    entry["kind"] = .string("stats")
                }
                out.append(.object(entry))
            }
        }
        return .array(out)
    }

    private func listProfiles() -> JSONValue {
        let entries: [JSONValue] = workspace.profileStore.profiles.map { p in
            .object([
                "id": .string(p.id.uuidString),
                "name": .string(p.name),
                "agent": .string(p.agentDefinition),
                "mcp_role": .string(p.mcpRole.rawValue)
            ])
        }
        return .array(entries)
    }

    private func listRepos() -> JSONValue {
        let entries: [JSONValue] = workspace.repoStore.repos.map { repo in
            .object([
                "id": .string(repo.id.uuidString),
                "name": .string(repo.name),
                "path": .string(repo.path.path),
                "default_branch": .string(WorktreeManager(repoRoot: repo.path)?.defaultBranch() ?? "main")
            ])
        }
        return .array(entries)
    }

    private func sendPrompt(_ args: JSONValue) async throws -> JSONValue {
        guard let tabIDStr = args["tab_id"]?.stringValue,
              let tabID = UUID(uuidString: tabIDStr) else {
            throw JSONRPCError.invalid("tab_id required")
        }
        guard let text = args["text"]?.stringValue, !text.isEmpty else {
            throw JSONRPCError.invalid("text required")
        }
        let summary = "send prompt to terminal: \(text.prefix(80))"
        let approved = await workspace.evaluateSpawnPolicy(summary: summary)
        guard approved else { throw JSONRPCError.application("send denied by user") }
        guard let host = workspace.terminalHosts[tabID] else {
            throw JSONRPCError.application("no live terminal for tab \(tabIDStr)")
        }
        host.session.sendStartupScript(text)
        return .object(["sent": .bool(true)])
    }

    private func readTerminal(_ args: JSONValue) throws -> JSONValue {
        guard let tabIDStr = args["tab_id"]?.stringValue,
              let tabID = UUID(uuidString: tabIDStr) else {
            throw JSONRPCError.invalid("tab_id required")
        }
        guard let host = workspace.terminalHosts[tabID] else {
            throw JSONRPCError.application("no live terminal for tab \(tabIDStr)")
        }
        let requested = args["tail_lines"]?.intValue ?? 200
        let tail = max(1, min(requested, 5000))

        let data = host.session.terminalView.getTerminal().getBufferAsData()
        let allLines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let trimmed = Array(allLines.reversed()
            .drop { $0.trimmingCharacters(in: .whitespaces).isEmpty }
            .reversed())
        let suffix = Array(trimmed.suffix(tail))
        let text = suffix.joined(separator: "\n")

        var entry: [String: JSONValue] = [
            "text": .string(text),
            "lines": .int(Int64(suffix.count)),
            "is_idle": .bool(host.session.isIdle)
        ]
        entry["idle_since_ms"] = host.session.idleSince
            .map { .int(Int64(Date().timeIntervalSince($0) * 1000)) } ?? .null
        return .object(entry)
    }

    private func closePane(_ args: JSONValue) throws -> JSONValue {
        guard let paneIDStr = args["pane_id"]?.stringValue,
              let paneID = UUID(uuidString: paneIDStr) else {
            throw JSONRPCError.invalid("pane_id required")
        }
        let removeWorktree = args["remove_worktree"]?.boolValue ?? false
        var worktreePathToRemove: (URL, URL)?
        if removeWorktree, let pane = workspace.pane(id: paneID),
           case .terminal(let repoID, let worktreeID) = pane.activeTab.content,
           let repo = workspace.repo(id: repoID),
           let wm = WorktreeManager(repoRoot: repo.path),
           let info = wm.listManagedWorktrees().first(where: { $0.branch == worktreeID }),
           !info.isPrimary {
            worktreePathToRemove = (repo.path, URL(fileURLWithPath: info.path))
        }
        workspace.closePane(paneID: paneID)
        if let (repoPath, worktreePath) = worktreePathToRemove,
           let wm = WorktreeManager(repoRoot: repoPath) {
            try? wm.removeWorktree(at: worktreePath)
        }
        return .object(["closed": .bool(true)])
    }

    private func listTaskLists() -> JSONValue {
        let entries: [JSONValue] = workspace.taskListStore.lists.map { list in
            .object([
                "id": .string(list.id.uuidString),
                "name": .string(list.name),
                "open": .int(Int64(list.items.filter { !$0.done }.count)),
                "total": .int(Int64(list.items.count))
            ])
        }
        return .array(entries)
    }

    private func listTasks(_ args: JSONValue) throws -> JSONValue {
        guard let listIDStr = args["list_id"]?.stringValue,
              let listID = UUID(uuidString: listIDStr),
              let list = workspace.taskListStore.list(id: listID) else {
            throw JSONRPCError.invalid("list_id not found")
        }
        let entries: [JSONValue] = list.items.map { item in
            .object([
                "id": .string(item.id.uuidString),
                "title": .string(item.title),
                "done": .bool(item.done)
            ])
        }
        return .array(entries)
    }

    private func addTask(_ args: JSONValue) throws -> JSONValue {
        guard let listIDStr = args["list_id"]?.stringValue,
              let listID = UUID(uuidString: listIDStr),
              workspace.taskListStore.list(id: listID) != nil else {
            throw JSONRPCError.invalid("list_id not found")
        }
        guard let title = args["title"]?.stringValue, !title.isEmpty else {
            throw JSONRPCError.invalid("title required")
        }
        workspace.taskListStore.addTask(listID: listID, title: title)
        return .object(["added": .bool(true)])
    }

    private func setTaskDone(_ args: JSONValue) throws -> JSONValue {
        guard let listIDStr = args["list_id"]?.stringValue,
              let listID = UUID(uuidString: listIDStr),
              let list = workspace.taskListStore.list(id: listID) else {
            throw JSONRPCError.invalid("list_id not found")
        }
        guard let taskIDStr = args["task_id"]?.stringValue,
              let taskID = UUID(uuidString: taskIDStr),
              let item = list.items.first(where: { $0.id == taskID }) else {
            throw JSONRPCError.invalid("task_id not found in list")
        }
        let target = args["done"]?.boolValue ?? true
        if item.done != target {
            workspace.taskListStore.toggleTask(listID: listID, taskID: taskID)
        }
        return .object(["done": .bool(target)])
    }

    private func resolveRepo(_ idStr: String?) throws -> UUID {
        if let idStr, let id = UUID(uuidString: idStr) {
            guard workspace.repo(id: id) != nil else {
                throw JSONRPCError.invalid("repo_id not found")
            }
            return id
        }
        if let branch = callerWorktreeBranch,
           let id = repoIDForWorktreeBranch(branch) {
            return id
        }
        if let first = workspace.repoStore.repos.first { return first.id }
        throw JSONRPCError.invalid("no repos available")
    }

    private func repoIDForWorktreeBranch(_ branch: String) -> UUID? {
        for repo in workspace.repoStore.repos {
            guard let wm = WorktreeManager(repoRoot: repo.path) else { continue }
            if wm.listManagedWorktrees().contains(where: { $0.branch == branch }) {
                return repo.id
            }
        }
        return nil
    }

    private func resolveProfile(_ idStr: String?) throws -> UUID? {
        guard let idStr else { return nil }
        guard let id = UUID(uuidString: idStr),
              workspace.profileStore.profile(id: id) != nil else {
            throw JSONRPCError.invalid("profile_id not found")
        }
        return id
    }

    private func spawnSummary(
        repoID: UUID,
        profileID: UUID?,
        name: String?,
        prompt: String?,
        split: String?
    ) -> String {
        var bits: [String] = []
        bits.append("spawn terminal")
        if let p = profileID, let prof = workspace.profileStore.profile(id: p) {
            bits.append("[\(prof.name)]")
        }
        if let n = name, !n.isEmpty { bits.append("name=\(n)") }
        if let s = split { bits.append("split=\(s)") }
        if let pr = prompt, !pr.isEmpty {
            bits.append("prompt=\(pr.prefix(60))\(pr.count > 60 ? "..." : "")")
        }
        if let repoName = workspace.repo(id: repoID)?.name { bits.append("repo=\(repoName)") }
        return bits.joined(separator: " ")
    }

    private static let initializeResult: JSONValue = .object([
        "protocolVersion": .string("2024-11-05"),
        "capabilities": .object([
            "tools": .object([:])
        ]),
        "serverInfo": .object([
            "name": .string("pluricode"),
            "version": .string("0.1.0")
        ])
    ])

    private static func toolResult(text: JSONValue, isError: Bool) -> JSONValue {
        let payload: String
        if case .string(let s) = text { payload = s }
        else if let data = try? MCPFraming.encoder.encode(text), let s = String(data: data, encoding: .utf8) {
            payload = s
        } else {
            payload = ""
        }
        return .object([
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(payload)
                ])
            ]),
            "isError": .bool(isError)
        ])
    }

    private static let toolsList: JSONValue = .object([
        "tools": .array([
            tool(
                name: "spawn_terminal",
                description: "Create a new git worktree, attach a terminal pane to it in the current workspace, and optionally type a prompt. Subject to the workspace's spawn policy (defaults to user approval).",
                properties: [
                    "repo_id": ("string", "UUID of the repo to branch from. Defaults to the first registered repo."),
                    "base_branch": ("string", "Branch to fork from. Defaults to the repo's default branch."),
                    "profile_id": ("string", "Agent profile UUID to assign. Use list_profiles to discover."),
                    "name": ("string", "Short name for the new worktree (used for the branch suffix)."),
                    "prompt": ("string", "Initial text to send to the terminal once the agent is up."),
                    "split": ("string", "Where to place the new pane: right | down | tab. Default: right.")
                ],
                required: []
            ),
            tool(
                name: "list_worktrees",
                description: "List managed worktrees across all repos, or scoped to one. Pass include_git_state to enrich each entry with diff stats, ahead/behind, and PR status (slower; runs gh).",
                properties: [
                    "repo_id": ("string", "Optional repo UUID filter."),
                    "include_git_state": ("boolean", "If true, include additions, deletions, ahead, behind, has_open_pr, is_merged. Default false.")
                ],
                required: []
            ),
            tool(
                name: "list_panes",
                description: "List every pane and tab in the active workspace with their kinds and bindings.",
                properties: [:],
                required: []
            ),
            tool(
                name: "list_profiles",
                description: "List all agent profiles configured in Pluricode, including their MCP role.",
                properties: [:],
                required: []
            ),
            tool(
                name: "list_repos",
                description: "List repositories registered in Pluricode.",
                properties: [:],
                required: []
            ),
            tool(
                name: "send_prompt",
                description: "Type text into the terminal of an existing tab as if the user pressed enter at the prompt. Subject to spawn policy.",
                properties: [
                    "tab_id": ("string", "UUID of the target tab."),
                    "text": ("string", "Text to send. A newline is appended automatically.")
                ],
                required: ["tab_id", "text"]
            ),
            tool(
                name: "read_terminal",
                description: "Read the recent visible output of a child terminal as plain text (ANSI already stripped by the renderer). Returns is_idle and idle_since_ms so the orchestrator can tell whether the child is still working.",
                properties: [
                    "tab_id": ("string", "UUID of the target tab."),
                    "tail_lines": ("integer", "How many trailing non-empty lines to return. Default 200, max 5000.")
                ],
                required: ["tab_id"]
            ),
            tool(
                name: "close_pane",
                description: "Close a pane in the workspace. Optionally remove the underlying worktree.",
                properties: [
                    "pane_id": ("string", "UUID of the pane to close."),
                    "remove_worktree": ("boolean", "If true, also git-worktree-remove the worktree. Default false.")
                ],
                required: ["pane_id"]
            ),
            tool(
                name: "list_task_lists",
                description: "List all task lists with open and total counts.",
                properties: [:],
                required: []
            ),
            tool(
                name: "list_tasks",
                description: "List items inside a single task list.",
                properties: [
                    "list_id": ("string", "UUID of the task list.")
                ],
                required: ["list_id"]
            ),
            tool(
                name: "add_task",
                description: "Append a task to a task list.",
                properties: [
                    "list_id": ("string", "UUID of the task list."),
                    "title": ("string", "Task title.")
                ],
                required: ["list_id", "title"]
            ),
            tool(
                name: "set_task_done",
                description: "Mark a task done or not done.",
                properties: [
                    "list_id": ("string", "UUID of the task list."),
                    "task_id": ("string", "UUID of the task."),
                    "done": ("boolean", "Target state. Defaults to true.")
                ],
                required: ["list_id", "task_id"]
            )
        ])
    ])

    private static func tool(
        name: String,
        description: String,
        properties: [String: (String, String)],
        required: [String]
    ) -> JSONValue {
        var props: [String: JSONValue] = [:]
        for (key, def) in properties {
            props[key] = .object([
                "type": .string(def.0),
                "description": .string(def.1)
            ])
        }
        return .object([
            "name": .string(name),
            "description": .string(description),
            "inputSchema": .object([
                "type": .string("object"),
                "properties": .object(props),
                "required": .array(required.map { .string($0) })
            ])
        ])
    }
}

enum SpawnSplit: String {
    case right
    case down
    case tab

    var edge: TileEdge? {
        switch self {
        case .right: .right
        case .down: .bottom
        case .tab: nil
        }
    }
}
