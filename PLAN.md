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
  displayName   = branch
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
- [x] Rename worktree: double-click row → inline edit; calls `git branch -m old new` and `git worktree move` if needed.
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

### M7 — Polish

**Goal**: make the day-to-day use feel sharp.

- [x] Pane header shows worktree/task info + profile swatch + close. Clicking the header activates the pane (sets workspace focus).
- [x] Workspace.focusedPaneID auto-updates on add/split/close. Focused pane has an accent-color border and tinted header.
- [x] Keyboard shortcuts via a Pane menu: ⌘W closes the focused pane, ⌘D splits right, ⌘⇧D splits down. Uses FocusedSceneValue so commands target the active workspace.
- [x] Empty workspace copy now mentions the Task List too.
- [x] Broken-worktree panes show an error state with "Remove Pane" (done earlier in M3).
- Divider hover widening + ⌘⌥ arrow focus navigation: deferred (nice-to-have, not blocking day-to-day use).

### M10 — Built-in Browser

**Goal**: render a worktree's locally-hosted preview inside Pluricode, and let the user mark up a region of that preview with a note that is sent straight to the worktree's agent terminal — closing the see-it → fix-it loop without leaving the app.

**How it fits**: the browser is a fourth pane content type, reusing three existing systems:
- **Pane/tab model** — a new `TabContent.browser` case (`Tiling/TileNode.swift`), rendered through `TabBody` like the others (`Workspace/WorkspaceView.swift`).
- **Localhost detection** — `LocalHostRegistry` already tracks each worktree's live dev-server URL; the browser resolves its initial URL from there instead of `NSWorkspace.shared.open` (`Workspace/LocalHostsWidgetView.swift`).
- **Agent injection** — `TerminalSession` already shell-escapes image paths into the PTY (`sendStartupScript`, `flushAttachmentInjection`, `shellEscape`); markup delivery is one more injection method on that class. No MCP/structured channel needed (deleted in M4) — auto-send writes directly to the agent's PTY.

**New types** (mirroring the terminal pattern):
- `BrowserHost` (parallel to `Workspace/TerminalHost.swift`): owns one `WKWebView`, keyed by `tabID` in a new `workspace.browserHosts: [UUID: BrowserHost]`, so page state survives SwiftUI re-layout, pane moves, and tab switches. Holds a runtime `originTabID` (the terminal that opened it) for markup routing.
- `BrowserPaneView: NSViewRepresentable` (parallel to `Workspace/TerminalPaneView.swift`): returns `host.webView`, wires nav state back to SwiftUI.
- `BrowserPaneBody` + header in the `WorkspaceView.swift` `TabBody` switch.

**Decisions**:
- Engine: `WKWebView` (only sensible native choice).
- Markup region basis: the *visible viewport* capture (`WKWebView.takeSnapshot`), so rectangle coords map 1:1 to what the user sees.
- Agent routing: resolved at send time, not stored — prefer the runtime `originTabID`'s session, else the first terminal session matching `(repoID, worktreeID)` skipping the `"dev"` tab; none → inline "No agent terminal open for this worktree." (Follows "don't store what you can compute.")
- Delivery: **auto-send** — note + image path injected into the agent terminal and submitted (trailing newline), via a new `TerminalSession.sendMarkup(note:imagePath:)` mirroring `sendStartupScript` and reusing `shellEscape`.
- Entry point: a **Preview button in the terminal pane header** (`PaneHeader`, next to the dev-script ▶), opening a browser pane bound to that pane's `(repoID, worktreeID)`.

**Config**: add `NSAppTransportSecurity` → `NSAllowsLocalNetworking = true` to `Info.plist` so `http://localhost` loads in `WKWebView`. Sandbox is already off; no entitlement changes.

**Switch sites to extend for the new `TabContent` case** (each already handles the other 3): `WorkspaceView.swift` `TabBody`/`GhostPane`/`ExpandedPaneCard`/`MinimizedPaneChip`; `Workspace.tabLabel`/`teardownTab` (release `browserHosts[tabID]`); `TilingDragPayload.Kind` + `acceptDrop` + `simulateDrop` (browser panes drag/tile like the rest).

#### Phase 1 — Preview pane

- [x] `TabContent.browser(repoID:worktreeID:url:)` case in `TileNode.swift` (Codable; stores last URL for relaunch restore).
- [x] `BrowserHost` + `workspace.browserHosts` map; teardown wired into `Workspace.teardownTab` and `deinit`.
- [x] `BrowserPaneView` (`NSViewRepresentable` over `WKWebView`) + `BrowserPaneBody` with header: address bar, back / forward / reload, loading indicator.
- [x] Preview button added to `PaneHeader`; `Workspace.openBrowser` opens a browser pane bound to the pane's `(repoID, worktreeID)`, dedup-focusing an existing one, recording `originTabID` via `pendingBrowserOrigins`.
- [x] Initial URL resolved from `LocalHostRegistry` for that worktree; empty state ("Waiting for a dev server on this worktree…") + usable address bar when none.
- [x] `LocalHostsWidgetView` "Open in Browser" switches from launching Safari to opening an internal browser pane.
- [x] Extend the tiling/drag switch sites so a browser pane labels, ghosts, minimizes, and tiles like the others (drag via a leading grip).
- [x] Expandable like terminal/shell panes — expand button in the header; the single `WKWebView` NSView moves to the `ExpandedPaneOverlay` (via shared `BrowserContent`, in-place shows `ExpandedPanePlaceholder`), no reload on expand/collapse.
- [x] Hot reload works for free — the dev server's own HMR/live-reload client runs inside the `WKWebView`, and `NSAllowsLocalNetworking` permits its `ws://localhost` connection. No app code needed; navigation churn is avoided since same-URL reloads no-op in `updateBrowserURL`.
- [x] `NSAllowsLocalNetworking` added to `Info.plist`.
- [ ] Verify (interactive): open a dev server in a worktree, click Preview, page renders; expand/collapse and resize/move keep the page live; edits hot-reload in place; URL persists across restart. *(Builds + launches clean; needs a live dev server to drive end-to-end.)*

#### Phase 2 — Capture + auto-send

- [x] "Mark up" (camera) button in the browser pane header → `BrowserHost.captureSnapshot` (`WKWebView.takeSnapshot`) of the visible viewport to an `NSImage`.
- [x] Note composition via `MarkupPopover` (screenshot thumbnail + multiline note field), with a disabled-send + warning when no agent terminal is resolved.
- [x] `TerminalSession.sendMarkup(note:imagePath:)` — writes `note + " " + shellEscape(path) + "\n"` to the PTY (reuses `shellEscape`).
- [x] Agent-terminal resolution via `Workspace.agentSession(repoID:worktreeID:preferredTabID:)` — prefers the browser's `originTabID`, else first matching `(repoID, worktreeID)` non-`"dev"` terminal; `MarkupPopover` shows the error state when none.
- [x] Temp PNG via `BrowserHost.writeTempPNG` under `NSTemporaryDirectory()`; screenshot + note auto-sent (trailing newline submits it).
- [ ] Verify (interactive): with an agent terminal open, capture sends a readable screenshot path + note into the bound worktree's agent terminal, submitted automatically. *(Builds clean; needs a live agent terminal to drive end-to-end.)*

#### Phase 3 — Region markup overlay (on the live preview)

Selection happens **directly on the running page**, not on a static capture: a markup-mode toggle (pencil) in the header turns the pane into a drawing surface; capture + composite happen at send time (which also sidesteps the snapshot warm-up). Supersedes Phase 2's capture-then-popover UI.

- [x] Markup-mode state on `BrowserHost` (`isMarkingUp`, `markupRects` normalized 0–1, `markupNote`) + `beginMarkup`/`cancelMarkup`/`clearRects`; pencil toggle in `BrowserHeader` (accent-tinted when active).
- [x] `MarkupSelectionOverlay` layered over the `WKWebView` (intercepts drags, dims the page) — drag to add red rectangles; `MarkupNoteBar` (bottom) with note field, clear-boxes, agent-availability warning, Cancel/Send.
- [x] On send: capture the viewport, `BrowserHost.annotate` composites the rectangles onto the full-res image (Core Graphics, y-flipped to image space), `writeTempPNG`, then the Phase 2 delivery path (`agentSession.sendMarkup`); exits markup mode.
- [x] Works in the expanded view too (markup state lives on the shared host).
- [ ] Verify (interactive): toggle markup, drag boxes over the page, add a note, Send → the agent receives the screenshot with red boxes drawn where you marked, plus the note. *(Builds + launches clean; needs a live dev server + agent to drive end-to-end.)*

**Open edge cases**:
- Multiple agent terminals per worktree: the "skip `dev`, take first" heuristic is a guess; may want to target the *focused* terminal or prompt.
- Annotation richness: Phase 3 starts with rectangles only; arrows/freehand/text-on-image can follow.

---

## Pluri — central orchestrator (M11–M15)

A central agent ("Pluri") the user talks to in natural language; it sets up worktrees, prepares task briefs, dispatches worker sessions, and monitors them. Pluricode stays the dumb reliable hands: Pluri is the user's own Claude Code — no API keys, no LLM runtime in the app. The value is fan-out: one utterance containing N tasks across M repos becomes N parallel worker sessions. Workers are parallel by construction (separate PTYs in their own panes); Pluri only dispatches, so its own loop stays free.

### M11 — Pluri in the toolbar

**Goal**: the single entry point. An animated mascot lives in the toolbar; clicking it opens the workspace's Pluri pane — a terminal running `claude` in Pluri's home directory, primed with an orchestrator identity. Pluri can already investigate repos and create worktrees with plain git: the sidebar derives worktrees from `git worktree list`, so what Pluri sets up appears in the app with no IPC.

- [x] `Pluri/PluriHome.swift`: home at `~/Library/Application Support/Pluricode/pluri/`; on pane start writes `CLAUDE.md` (orchestrator identity, worktree conventions, brief-drafting rules) and `repos.json` (registered-repo export, regenerated each start).
- [x] `TabContent.pluri` case + all switch sites (TabBody, ghost pane, minimized chip, expanded card, `tabLabel`, `terminalPanes`).
- [x] `Pluri/PluriPaneView.swift`: `TerminalHost` at the Pluri home with startup script `claude`.
- [x] `Workspace.openPluri()`: dedup — focus an existing Pluri tab (restoring from minimized), else split right of the anchor pane.
- [x] `Pluri/PluriMascotView.swift`: coral mascot with blinking eyes and hover bounce; toolbar button → `openPluri()`.
- [ ] Verify (interactive): mascot animates; click opens Pluri running `claude`; second click focuses instead of duplicating; a worktree created by Pluri shows up in the sidebar. *(Builds clean; needs a live run to drive end-to-end.)*

### M12 — Control surface

**Goal**: give Pluri hands. A file-based command bridge under the Pluri home (`commands/` watched by the app, responses written back) plus a documented contract in `CLAUDE.md`, so Pluri can open a worktree pane and kick off a worker `claude "<brief>"` in it. Listing worktrees needs no bridge — it's `git worktree list`. Keep Pluri's turns short: anything slow (repo investigation) runs as Pluri's own background subagents.

- [x] `Pluri/PluriBridge.swift`: DispatchSource watcher on `pluri/commands/`; handles `open_pane` `{repo, branch, startup}`; writes `{id}.result.json`; clears stale files at launch. Requests arrive via atomic `mv` (documented), so no partial reads.
- [x] `Workspace.openWorktreePane(repoID:branch:startupScript:)`: pane inserted right of the anchor via `reinsertPane`; startup delivered through the existing `pendingDevScripts` channel; keyboard focus stays where the user is (Pluri's pane).
- [x] Bridge invalidates `WorktreePaths` + worktree status caches and refreshes the sidebar, so worktrees Pluri just created with git resolve immediately.
- [x] `PluriHome` `CLAUDE.md` documents the protocol with a copy-paste dispatch recipe; limits section now only covers monitoring (M13).
- [x] Verify (interactive): asked Pluri to set up a worktree and dispatch a task — Pluri created the branch + worktree with git (appeared in the sidebar), the bridge opened a worker pane with the brief running, and the worker completed it. (Driven live during the M14 verify; "next to Pluri" predates M13 — Pluri is a window now, the pane opens at the workspace anchor.)

### M13 — Pluri chat window

**Goal**: Pluri leaves the tiling. Pulled ahead of status & events because the standalone surface is the user-facing priority; the bridge carries over unchanged. The mascot now opens a dedicated chat window driven by headless Claude Code: each user message spawns `claude -p --output-format stream-json --include-partial-messages` (resuming the session by id) in the Pluri home with the prompt on stdin — no shell escaping, no PTY, still the user's own auth. Headless mode cannot show terminal permission prompts (unmatched tools auto-deny), so the home gets a `.claude/settings.json` allow-list of what Pluri legitimately runs (git, gh, the bridge recipe, reads, subagents); approval lives where it belongs — in the conversation, before a fan-out dispatch.

- [x] `Pluri/PluriSession.swift`: per-turn `claude -p` subprocess via the login shell; parses the NDJSON stream (text deltas, tool_use starts, partial tool input, result) into `PluriBlock`s; captures `session_id` and resumes it on the next turn; SIGINT to interrupt; stderr surfaces as an error block when a turn dies without a result.
- [x] `Pluri/PluriChatView.swift`: transcript (user bubbles, streaming markdown text, compact tool-call capsules, errors), auto-scroll, multiline input with send/stop, new-conversation toolbar button, mascot empty state.
- [x] `PluricodeApp`: `Window("Pluri")` scene; the toolbar mascot opens it (no workspace required anymore).
- [x] `PluriHome.prepare` additionally writes `.claude/settings.json` (permission allow-list) and now runs per message, so `repos.json` is always fresh; identity updated for headless operation.
- [x] `PluriSettings.command` ("Pluri command") replaces the pane setup script; the worker setup script is unchanged.
- [x] Pane teardown: `TabContent.pluri`, `Workspace.openPluri()`, `PluriPaneView`, and all pane/header/expanded/minimized switch sites deleted.
- [x] Live-run fixes: dispatch recipe moved to the Write tool + atomic `mv` (the headless shell guard rejects JSON heredocs, and the redirect sandbox mismatches the home path's space — scoped Write rules fail on the same, so the allow-list carries bare `Write`); `PluriBridge.start()` moved from the main window's `onAppear` to app init (the chat window can exist without the main window, leaving the bridge unarmed); stream deltas coalesce into a 10 Hz flush so the transcript doesn't re-layout per token (beachballed on long turns).
- [ ] Verify (interactive): mascot opens the window; a message streams text and tool capsules live; a follow-up message continues the same session; a dispatch opens a worker pane in the workspace; stop interrupts; denied tools come back as a readable explanation.

### M14 — Status & events

**Goal**: the return channel. Worker sessions get Claude Code hooks that write status files under the Pluri home; the app watches them, badges panes (running / waiting / done), and posts worker events into Pluri's chat as resumed turns — the M13 transport makes PTY injection unnecessary. A persistent task registry file (task, repo, worktree, brief, status) makes orchestration state survive context compaction — the conversation is the UI, the registry is the truth.

- [x] `Pluri/WorkerHooks.swift`: writes `{worktree}/.claude/settings.local.json` with `SessionStart`/`UserPromptSubmit`/`Notification`/`Stop`/`SessionEnd` hooks that dump the hook's stdin JSON into `pluri/events/` (uuid tmp + atomic `mv`). Installed by `TerminalPaneView` before any worktree terminal starts, so every claude session in a managed worktree reports — not just dispatched workers. Rewritten while the file holds only our hooks (stale dev/prod paths self-heal); left untouched once Claude Code merges its own keys in. Argv-dispatched briefs don't fire `UserPromptSubmit` (claude-code #17284), so `SessionStart` carries the running signal.
- [x] `Pluri/PluriTaskRegistry.swift`: `pluri/tasks.json` — repo, branch, brief, status, timestamps; worktree path derived from the `{repo}/.pluricode/worktrees/{branch}` convention. Bridge `open_pane` with a `prompt` registers (re-dispatch on the same branch replaces); `delete_worktree` removes.
- [x] `Pluri/PluriMonitor.swift`: drains `pluri/events/` (creation-date order) via `DirectoryWatcher` — extracted from `PluriBridge`, now shared. Maintains observable `statuses` keyed by worktree path: SessionStart/UserPromptSubmit → running, Notification → waiting, Stop → done, SessionEnd clears the badge. Registry status transitions of `done`/`waiting` post to Pluri's chat; the registry's own transition guard prevents duplicate posts across app restarts.
- [x] `PluriSession.postEvent`: events queue while a turn is running and flush as one resumed turn when idle (and after `finish`); rendered as dim `bolt` system rows (`PluriBlock.Kind.event`) instead of user bubbles.
- [x] `PaneHeader` worker-status dot (blue running / orange waiting / green done) next to the branch name, looked up by worktree path from `PluriMonitor` via SwiftUI environment.
- [x] Identity: "Current limits" replaced by a Monitoring section — `tasks.json` is the app-maintained read-only truth, `[worker update]` turns arrive automatically, react briefly (`done` → inspect the worktree and summarize; `waiting` → relay; never self-dispatch follow-ups).
- [x] Verify (interactive): dispatched a test task through Pluri — `settings.local.json` appeared in the worktree, the pane dot went blue then green, `tasks.json` flipped running → done seven seconds after dispatch, and the `[worker update]` turn landed in the chat with Pluri's summary. Not yet driven: the orange waiting state (worker ran with `--dangerously-skip-permissions`, so no permission prompt occurs). Known behavior: a worker killed by an app restart leaves its registry entry `running` until re-engaged — M15 territory.

### M15 — Threads

**Goal**: Slack-style threads in the chat window: thread root = task (from the M14 registry), thread replies route into the worker's PTY, worker pane one click away. Confirm-gate briefs render as approvable cards.

- [x] `PluriTaskRegistry` is `@Observable` and each task carries an `updates` timeline (dispatched / running / waiting / done / reply, with messages); the monitor appends transitions, `register` seeds "dispatched". Old flat `tasks.json` becomes unreadable — registry resets (no-backwards-compat).
- [x] Chat window: task chip bar (live status dots, sorted by recency) above the transcript; tapping opens the task's thread — brief, update timeline, reply field, status header.
- [x] Thread replies route into the worker's PTY via `TerminalSession.submit` (extracted from `sendMarkup`) through `PluriBridge.reply`, and land in the timeline as `reply` updates. Workers resolved by `WorkspaceStore.workerPane` (tiled + minimized, stubs excluded).
- [x] Worker pane one click away: "Open Pane" selects the workspace, restores from minimized, activates the right tab, focuses the terminal, raises the main window. With no live session the button becomes "Re-dispatch" — re-registers and starts a fresh worker with the original brief (also the recovery path for workers killed by an app restart).
- [x] Confirm-gate: new bridge action `propose` `{tasks: [{repo, branch, prompt}]}` validates worktrees and stores a proposal; the chat renders it as a card with per-task briefs and Approve & Dispatch / Decline. Approve dispatches through the same core `open_pane` uses (extracted `PluriBridge.dispatch`); either way Pluri hears the outcome as an `[approval]` resumed turn.
- [x] `waiting` no longer burns a Pluri turn — it surfaces in the thread (with the notification message) and the orange dot; only `done` still posts a `[worker update]` for the summary.
- [x] Identity: fan-outs go through `propose` (worktrees first, end turn after proposing, never re-`open_pane` approved tasks); thread replies documented as user→worker, not through Pluri.
- [ ] Verify (interactive): ask Pluri for a multi-task fan-out — card appears, Approve dispatches all workers and Pluri acknowledges; a task chip opens the thread, a reply lands in the worker's terminal and echoes in the timeline; Open Pane jumps to the pane; Re-dispatch revives a dead task. *(Builds clean; needs a live run.)*

---

## Ordering

M1 → M2 → M3 → M4 are strictly sequential (each needs the previous). M5 and M6 are independent after M4 and can be done in either order. M7 last. M10 (browser) is independent of the task-list work; its three phases are sequential (each builds on the last). M11 → M12 → M13 → M14 → M15 are sequential: each Pluri milestone proves the previous before adding machinery.

## Open decisions

- Should task panes have multiple lists per repo (so separate "Now" / "Backlog" panes can show different slices), or a single shared list? Deferring — start with single shared list in M6; revisit if it feels cramped.
