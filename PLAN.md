# V2 Plan — Tiled Terminal Workspaces

## The pivot

V1 was a freeform infinite Metal canvas where terminals, task cards, and sections lived as nodes, wired together with bezier edges to form visual workflows. That model is out.

V2 is a **tiled terminal workspace**, one per repo. The detail view is a recursively splittable pane layout — tmux/i3 style, no floating windows, no z-order, no overlap. Worktrees are first-class entities listed under each repo in the sidebar. Users open a worktree in a pane; the tiling engine handles the rest.

Goal: observe and manage multiple terminals running in parallel, each scoped to its own worktree.

## End state

- **Sidebar**: two-level tree. Repos → Worktrees. Create/rename/delete worktrees here. Worktrees are drag sources.
- **Detail**: a `WorkspaceView` rendering a recursive `TileNode`. Dividers resize freely. Panes hold either a terminal bound to a worktree, or a task list scoped to the repo.
- **Drop zones**: dropping a worktree on a pane's edge splits that pane; dropping on the center replaces the pane.
- **Pure tiling**. No tabs. Same worktree may appear in multiple panes (two sessions in the same directory — that's fine).
- **Agent profile** is a property of the worktree, not the pane. Opening it anywhere respawns the right agent.
- **Startup script** auto-runs when a worktree opens in a pane.
- **Task panes**: repo-scoped task lists for the user's own follow-ups, bugs, notes. Not wired into agents.
- **No edges**, no task cards on a canvas, no sections, no workflow engine, no minimap, no Metal rendering.

## Data model

```
Worktree                                 // one per managed worktree under a repo
  id            = branch name            // stable identifier; derives path via git
  displayName   = branch with pluri- prefix stripped
  path          = from git worktree list
  branch        = from git
  head          = from git
  agentProfileID: UUID?                  // sidecar, M5
  startupScript: String?                 // sidecar, M5

TileNode
  .pane(PaneContent)
  .split(Split)

PaneContent
  .terminal(worktreeID: String)          // branch name
  .tasks                                 // repo-scoped task list, no state here

Split
  direction: .horizontal | .vertical
  children: [TileNode]
  weights:  [Float]                      // sum to 1.0

Workspace                                // one per repo, persisted to .pluricode/workspace.json
  root: TileNode?                        // nil = empty canvas

TaskItem                                 // repo-scoped, persisted to .pluricode/tasks.json
  id: UUID
  title: String
  done: Bool
  createdAt: Date
```

**What we do NOT store**: paths, branches, heads (all derived from `git worktree list`). Worktree records are not persisted separately — the list is the filesystem. Display names are the branch suffix. Per-worktree config (agent profile, startup script) lives in `{worktree}/.pluricode/worktree.json`.

---

## Milestones

Each milestone has a checklist. Tick items as completed across sessions.

### M1 — Worktrees as first-class in the sidebar

**Goal**: sidebar shows Repos → Worktrees. Users create, rename, delete worktrees explicitly. No canvas changes yet. Old canvas continues to work; this is purely additive.

- [x] Extend `WorktreeManager` with a `listManagedWorktrees()` that filters `git worktree list` to ones under `{repo}/.pluricode/worktrees/`, returning `[Worktree]` with display name derived from the branch.
- [x] Add `Worktree` struct (Identifiable by branch name) in `Worktree/Worktree.swift`.
- [x] `RepoSidebarView`: replace flat repo list with a `DisclosureGroup` per repo; expanded state shows the managed worktrees underneath.
- [x] "New Worktree" row under each repo opens an inline sheet: name input + base branch picker (defaults to repo's default branch).
- [x] Context menu on a worktree row: Show in Finder, Delete (confirm dialog, runs `git worktree remove --force`).
- [x] Rename worktree: double-click row → inline edit; calls `git branch -m pluri-old pluri-new` and `git worktree move` if needed.
- [x] Selecting a worktree row does not open anything yet — wire-up happens in M3.
- [x] Build and run: create/list/delete worktrees from the sidebar; old canvas still functions.

### M2 — Tiling layout engine (no terminals)

**Goal**: build the recursive split view with colored placeholder panes so we can iterate on geometry and interactions independently.

- [x] `Tiling/TileNode.swift`: enum + `Tiling` observable class with `addPane`, `split`, `remove`, `setWeights`. Collapse rule implemented: single-child splits collapse into their parent.
- [x] `Tiling/TileView.swift`: recursive SwiftUI view. GeometryReader-driven HStack/VStack, children sized by weights.
- [x] `Tiling/SplitDivider.swift`: draggable divider; uses cursor resize icons; enforces 0.08 minimum fraction per neighbor.
- [x] `Tiling/DropOverlay.swift`: per-pane hit regions (top/bottom/left/right/center) computed from drop location; `TilingDragPayload` Transferable for sources; visual zone indicator when targeted.
- [x] `Tiling/TileDemoView.swift` (throwaway): demo window with draggable placeholder templates in a sidebar; drag onto the empty canvas or onto any existing pane. Opened via `Window > Open Tiling Demo` (⌘⇧T).
- [ ] Keyboard: arrow keys move focus across panes. Deferred to M7.
- [ ] Verify visually: 1/2/3/4/5 panes lay out and resize cleanly; drag-to-split feels right.

### M3 — Terminal panes + Workspace persistence

**Goal**: wire the tiling engine to real terminals. Swap `CanvasHostView` for `WorkspaceView`. Old canvas still compiles but is no longer the detail view.

- [x] `Workspace/Workspace.swift`: observable model holding root TileNode, terminal hosts, debounced save to `.pluricode/workspace.json`.
- [x] `Workspace/TerminalHost.swift` + `TerminalPaneView.swift`: per-pane NSViewRepresentable wrapping a `TerminalSession`. Session survives view rebuilds via the Workspace-owned `terminalHosts` dict.
- [x] Same worktree may appear in multiple panes; distinct paneIDs = distinct sessions, distinct scrollback files.
- [x] `WorkspaceView` replaces `CanvasHostView` as the detail view.
- [x] Drag worktree from sidebar → empty drop zone or pane edge/center zone → add or split terminal.
- [x] Pane header: display name, branch, close button. Missing worktree state shows an error + remove pane button.
- [x] Layout persists across restarts via `workspace.json`.

### M4 — Delete the canvas

**Goal**: remove all dead code and legacy model concepts in one commit. App is now exclusively tiled.

- [x] Delete `Canvas/`, `Wiring/`, `MCP/`, `SectionLayout.swift`.
- [x] Delete `Model/CanvasDocument.swift`, `Model/CanvasNode.swift`, `Model/Persistence.swift`, `Terminal/TerminalManager.swift`, `Pluricode-Bridging-Header.h`.
- [x] Strip `main.swift` (no more MCP bridge branch); remove `CanvasHostView`, `migrateLastProjectPath`, old toolbar buttons.
- [x] Drop `SWIFT_OBJC_BRIDGING_HEADER` from `project.yml`.
- [x] Verify: project builds and launches; tiling works unchanged.

### M5 — Agent profiles on worktrees + startup script auto-run

**Goal**: profile and startup script move from terminal node → worktree. When a worktree opens in a pane, the agent auto-runs if a startup script is set.

- [x] `Worktree/WorktreeConfig.swift` holds agentProfileID + startupScript, loaded from `{worktree}/.pluricode/worktree.json`.
- [x] `Agent/AgentProfileStore.swift` is global, UserDefaults-backed, seeded from `AgentProfile.defaults`. Injected from `PluricodeApp` into the sidebar and workspace.
- [x] Sidebar "Configure..." context menu on worktree rows opens a sheet with profile picker + startup script.
- [x] New Worktree sheet now includes profile picker + startup script; saves the config alongside git worktree creation.
- [x] `TerminalHost.startIfNeeded` loads the config, writes CLAUDE.md via `ProfileInjector`, and schedules the startup script.
- [x] `WorktreeRow` and pane header show a color swatch + profile name when assigned.

### M6 — Task panes

**Goal**: a pane can be a task list instead of a terminal. Users jot down quick todos, bugs, follow-ups, and tick them off. Scoped per-repo. Not wired to agents.

- [x] `Workspace/TaskStore.swift`: `TaskItem` (id, title, done, createdAt) + observable `TaskStore` persisting `.pluricode/tasks.json` debounced.
- [x] `PaneContent.tasks` variant; `TilingDragPayload.Kind.newTaskPane` maps via `paneContent` helper.
- [x] `Workspace.addPane`/`splitPane` generalized over `PaneContent` so both kinds flow through one path.
- [x] `TaskPaneView`: header with open/total counts + clear-completed menu + close, list with checkbox, strikethrough, hover-delete, double-click to rename, bottom "Add task..." field.
- [x] Sidebar `Panes` section with a draggable "Task List" row (`.newTaskPane`).
- [x] Multiple task panes share the same repo-scoped list (expected for M6).

### M8 — Rearrange panes

**Goal**: drag existing panes to new positions within the canvas. Sessions survive the move.

- [x] `Tiling.movePane(sourceID:to:adjacentTo:)` and `Tiling.swapPanes(a:b:)`. Move preserves the Pane struct (id + content) so TerminalHost sessions keep running.
- [x] `TilingDragPayload.Kind.movePane(paneID:)` and a single `Workspace.acceptDrop(payload:on:edge:)` dispatcher that handles all kinds. Center drop on another pane swaps.
- [x] `PaneHeader` and `TaskPaneHeader` are draggable with `.movePane(...)` payloads; tap-to-activate and close button still work alongside the drag.
- [x] All drop handlers (empty workspace, terminal pane, task pane) route through the dispatcher.

### M9 — Named task lists per repo

**Goal**: users create multiple named task lists per repo (e.g. "Bugs", "Improvements") and open each in its own pane. Dragging a specific list from the sidebar creates a pane bound to that list.

- [ ] `TaskList` struct (id, name, items). `TaskStore` holds `[TaskList]` per repo. Persists to `.pluricode/tasks.json` as a list-of-lists (old flat-array format becomes unreadable — acceptable per no-backwards-compat rule).
- [ ] `TaskStoreRegistry` shared across sidebar and workspaces, keyed by repo path, so changes in the sidebar show up live in open panes.
- [ ] `PaneContent.tasks(listID:)` and `TilingDragPayload.Kind.newTaskPane(listID:)` carry the list identity.
- [ ] `TaskPaneView` renders and mutates a specific list by id; header shows the list's name + counts. Missing-list pane shows an error state with Remove Pane.
- [ ] Sidebar: under each expanded repo, below the worktrees, show a Task Lists section with draggable rows + "New Task List" action. Context menu offers Rename and Delete (confirm when list has tasks).
- [ ] Remove the old global "Task List" drag source from the sidebar top.
- [ ] Verify: create two lists, drag each into the canvas, add tasks in each, rename a list (panes reflect), delete a list (pane shows missing state).

### M10 — Agent orchestration via MCP

**Goal**: an "orchestrator" agent running in one pane can spawn additional worktree+terminal panes in the same workspace and delegate subtasks to them. Re-introduces an MCP server (deleted in M4), but at workspace scope, not per-terminal.

**Use case**: gabriel hands a long list of tasks to one agent. That agent breaks them up, spins up new worktrees/terminals in the active workspace, and assigns each subtask. The orchestrator stays the single conversational surface.

**Architecture**:
- One MCP server **per workspace** (not per pane). `MCPServer` owned by `Workspace`, `Network.framework` TCP listener on a random localhost port, port stored on the workspace.
- `main.swift --mcp-bridge <port> <workspaceID>` re-introduced: same binary, stdio JSON-RPC ⇄ localhost TCP. No second target.
- `.mcp.json` is written into a worktree by `TerminalHost.startIfNeeded` only when the worktree's profile has `mcpRole != .none`. Points at the bridge with the workspace's port.
- `AgentProfile.mcpRole: .orchestrator | .worker | .none` gates which tools are exposed. Defaults: Architect → orchestrator, others → none.
- All tool handlers run on `@MainActor`; they call existing `Workspace.spawnTerminal`, `WorktreeManager.createWorktree`, `addPane`/`splitPane` — no parallel code paths.
- Safety: `Workspace.spawnPolicy: .ask | .allowUpTo(N) | .allow`. `.ask` shows an in-app banner per request; `.allowUpTo(N)` caps MCP-spawned panes per workspace session. Default `.ask`.

**Tool surface** (exposed to orchestrator profiles):

```
spawn_terminal(repo_id?, base_branch?, profile_id?, name?, prompt?, split?: "right"|"down"|"tab")
  → { pane_id, tab_id, worktree_branch, path }
list_worktrees(repo_id?)             → [{ branch, path, head, profile, uncommitted }]
list_panes()                          → [{ pane_id, tab_id, kind, repo_id?, worktree_branch?, profile? }]
list_profiles()                       → [{ id, name, mcpRole }]
list_repos()                          → [{ id, name, path, default_branch }]
send_prompt(tab_id, text)             → types text into a target terminal (subject to spawnPolicy)
close_pane(pane_id, remove_worktree?) → closes pane; optionally removes the worktree
list_task_lists(repo_id) / list_tasks(list_id) / add_task(list_id, title) / set_task_done(task_id, done)
```

**Checklist**:
- [x] `Agent/AgentProfile.swift`: add `mcpRole: MCPRole` field; seed Architect → `.orchestrator`, Coder/Reviewer/Tester → `.none`.
- [x] `MCP/MCPServer.swift`: `Network.framework` TCP listener, one per `Workspace`, port held on `Workspace`. JSON-RPC 2.0 framing. Dispatch to `MCPTools` on `@MainActor`.
- [x] `MCP/MCPBridge.swift` + `main.swift --mcp-bridge <port> <workspaceID> <token>`: stdio ⇄ TCP forwarder, MCP protocol on stdio side.
- [x] `MCP/MCPTools.swift`: tool registry and handlers. Each handler is a thin call into `Workspace`/`WorktreeManager`/`TaskListStore`.
- [x] `Workspace.spawnTerminal(repo:baseBranch:profile:name:prompt:split:)`: single entry point used by both the MCP handler and any future UI affordance. Reuses `WorktreeManager.createWorktree` + `WorktreeConfig.save` + `addPane`/`splitPane`. Returns identifiers.
- [x] `TerminalHost.startIfNeeded`: when launching, if the resolved profile has `mcpRole != .none`, write `.mcp.json` into the worktree pointing at the workspace's bridge command.
- [x] `Workspace.spawnPolicy` + an in-app confirmation banner for `.ask`. `.allowUpTo(N)` enforced via a per-session counter on `Workspace`.
- [x] `send_prompt` is gated identically to `spawn_terminal` — never types into a terminal silently under `.ask`.
- [x] Persist `mcpRole` and `spawnPolicy` (the latter on the workspace snapshot).
- [x] Verify end-to-end: drop an Architect worktree onto a workspace, ask it to "split this into 3 worktrees and start each one"; confirm 3 panes appear, each with the correct profile and prompt typed; confirm `.ask` blocks an unapproved 4th spawn.

### M7 — Polish

**Goal**: make the day-to-day use feel sharp.

- [x] Pane header shows worktree/task info + profile swatch + close. Clicking the header activates the pane (sets workspace focus).
- [x] Workspace.focusedPaneID auto-updates on add/split/close. Focused pane has an accent-color border and tinted header.
- [x] Keyboard shortcuts via a Pane menu: ⌘W closes the focused pane, ⌘D splits right, ⌘⇧D splits down. Uses FocusedSceneValue so commands target the active workspace.
- [x] Empty workspace copy now mentions the Task List too.
- [x] Broken-worktree panes show an error state with "Remove Pane" (done earlier in M3).
- Divider hover widening + ⌘⌥ arrow focus navigation: deferred (nice-to-have, not blocking day-to-day use).

---

## Ordering

M1 → M2 → M3 → M4 are strictly sequential (each needs the previous). M5 and M6 are independent after M4 and can be done in either order. M10 depends on M5 (needs profiles on worktrees) and ideally M9 (task-list tools). M7 last.

## Open decisions

- Should task panes have multiple lists per repo (so separate "Now" / "Backlog" panes can show different slices), or a single shared list? Deferring — start with single shared list in M6; revisit if it feels cramped.
