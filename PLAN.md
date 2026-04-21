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
  displayName   = branch with xyz- prefix stripped
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

Workspace                                // one per repo, persisted to .xyzterminal/workspace.json
  root: TileNode?                        // nil = empty canvas

TaskItem                                 // repo-scoped, persisted to .xyzterminal/tasks.json
  id: UUID
  title: String
  done: Bool
  createdAt: Date
```

**What we do NOT store**: paths, branches, heads (all derived from `git worktree list`). Worktree records are not persisted separately — the list is the filesystem. Display names are the branch suffix. Per-worktree config (agent profile, startup script) lives in `{worktree}/.xyzterminal/worktree.json`.

---

## Milestones

Each milestone has a checklist. Tick items as completed across sessions.

### M1 — Worktrees as first-class in the sidebar

**Goal**: sidebar shows Repos → Worktrees. Users create, rename, delete worktrees explicitly. No canvas changes yet. Old canvas continues to work; this is purely additive.

- [x] Extend `WorktreeManager` with a `listManagedWorktrees()` that filters `git worktree list` to ones under `{repo}/.xyzterminal/worktrees/`, returning `[Worktree]` with display name derived from the branch.
- [x] Add `Worktree` struct (Identifiable by branch name) in `Worktree/Worktree.swift`.
- [x] `RepoSidebarView`: replace flat repo list with a `DisclosureGroup` per repo; expanded state shows the managed worktrees underneath.
- [x] "New Worktree" row under each repo opens an inline sheet: name input + base branch picker (defaults to repo's default branch).
- [x] Context menu on a worktree row: Show in Finder, Delete (confirm dialog, runs `git worktree remove --force`).
- [x] Rename worktree: double-click row → inline edit; calls `git branch -m xyz-old xyz-new` and `git worktree move` if needed.
- [x] Selecting a worktree row does not open anything yet — wire-up happens in M3.
- [x] Build and run: create/list/delete worktrees from the sidebar; old canvas still functions.

### M2 — Tiling layout engine (no terminals)

**Goal**: build the recursive split view with colored placeholder panes so we can iterate on geometry and interactions independently.

- [ ] `Tiling/TileNode.swift`: the enum + helpers (`insert`, `remove`, `resize`, `findPane`).
- [ ] `Tiling/TileView.swift`: SwiftUI recursive view. Uses `GeometryReader` + `HStack`/`VStack` driven by weights.
- [ ] `Tiling/SplitDivider.swift`: draggable divider that adjusts neighbor weights; min pane size enforced.
- [ ] `Tiling/DropOverlay.swift`: per-pane hit regions — top/bottom/left/right quadrants split, center replaces.
- [ ] `Tiling/TileDemoView.swift` (throwaway): standalone window showing the tiling engine with placeholder panes (colored rectangles with labels), a toolbar to add/remove panes, and drag-to-split between them. Deleted in M3.
- [ ] Collapse rule: when a split has one remaining child, it replaces the split in its parent. When the root is empty, workspace is empty.
- [ ] Keyboard: arrow keys move focus across panes. Deferred if tricky.
- [ ] Verify visually: 1/2/3/4/5 panes lay out and resize cleanly; drag-to-split feels right.

### M3 — Terminal panes + Workspace persistence

**Goal**: wire the tiling engine to real terminals. Swap `CanvasHostView` for `WorkspaceView`. Old canvas still compiles but is no longer the detail view.

- [ ] `Workspace/Workspace.swift`: the model holding the root `TileNode`, with observable mutations.
- [ ] `Workspace/WorkspaceStore.swift`: load/save `.xyzterminal/workspace.json` per repo, debounced.
- [ ] Swap `TileNode.pane(.terminal(worktreeID:))` content for a `TerminalPaneView` backed by a `TerminalSession`. Reuse `TerminalManager` — rekey sessions by `paneID` (not `nodeID`).
- [ ] Same worktree may appear in multiple panes; each pane gets its own session, its own PTY.
- [ ] `WorkspaceView`: replaces `CanvasHostView` as the detail view in `XyzterminalApp`. Renders the root tile + a drop target for the empty state.
- [ ] Dragging a worktree from the sidebar into a pane's drop zone adds a new terminal pane.
- [ ] Pane header: worktree display name, branch, a close button. Closing removes the pane and collapses its parent split.
- [ ] Verify: open a repo, drag worktree A, drag worktree B alongside, resize divider, close one, app restart restores layout.

### M4 — Delete the canvas

**Goal**: remove all dead code and legacy model concepts in one commit. App is now exclusively tiled.

- [ ] Delete `Canvas/` entirely (Metal view, input handler, renderer, camera, hit testing, edge tessellator, overlays, section editor, task card editor, terminal config sheet, shaders).
- [ ] Delete `Wiring/` (WorkflowEngine, WiringAction).
- [ ] Delete `SectionLayout.swift`.
- [ ] Strip `CanvasDocument` down to what `Workspace` needs — or just rename `CanvasDocument` → `Workspace` and absorb remaining state. Remove nodes, edges, selection, camera, section helpers, inline editing, pending terminal deletions.
- [ ] Remove from `CanvasNode.swift`: `TaskCardData`, `SectionData`, `NodeKind.taskCard`, `NodeKind.section`. If nothing remains, delete the file and fold `TerminalNodeData` into `Workspace/Pane.swift` (or its replacement).
- [ ] Persistence: replace `canvas.json` with `workspace.json`. Delete legacy snapshot struct.
- [ ] Remove toolbar buttons for Task Card, Section, Snap.
- [ ] Verify: project builds, launches, tiling works, no warnings.

### M5 — Agent profiles on worktrees + startup script auto-run

**Goal**: profile and startup script move from terminal node → worktree. When a worktree opens in a pane, the agent auto-runs if a startup script is set.

- [ ] Per-worktree config at `{worktree}/.xyzterminal/worktree.json` with `agentProfileID` and `startupScript`.
- [ ] `WorktreeManager` load/save of the config.
- [ ] Sidebar: right-click a worktree → Configure (sheet): pick an agent profile, edit startup script.
- [ ] New Worktree sheet: include profile picker + startup script from the start.
- [ ] When `TerminalSession` starts in a pane: if a profile exists, `ProfileInjector` writes CLAUDE.md. If a startup script exists, `scheduleStartupScript` runs it.
- [ ] Pane header shows the profile swatch + name if assigned.
- [ ] Verify: configure a worktree with Claude Code + startup script; open it in a pane; Claude Code auto-launches.

### M6 — Task panes

**Goal**: a pane can be a task list instead of a terminal. Users jot down quick todos, bugs, follow-ups, and tick them off. Scoped per-repo. Not wired to agents.

- [ ] `TaskItem` model + persistence at `.xyzterminal/tasks.json`.
- [ ] `PaneContent.tasks` variant.
- [ ] `TaskPaneView`: list of items with inline add (Enter to commit), tick to complete, swipe or delete key to remove. Strikethrough for done. Optional "clear completed" menu item.
- [ ] Sidebar / pane header: "+" menu → "New Terminal Pane" / "New Task Pane". Dropping a task pane anywhere lands it via the same drop zone system.
- [ ] Multiple task panes allowed (so two can sit side-by-side, e.g. "Now" vs "Backlog"). For now they share the same underlying list. Filtering per-pane: deferred.
- [ ] Verify: add tasks, tick them, restart, state persists.

### M7 — Polish

**Goal**: make the day-to-day use feel sharp.

- [ ] Pane header: worktree display name + branch + profile swatch + close. Click header → focus the pane's terminal.
- [ ] Keyboard shortcuts:
  - ⌘W closes the focused pane
  - ⌘D splits the focused pane horizontally
  - ⌘⇧D splits vertically
  - ⌘⌥ arrow keys move focus
- [ ] Divider hit targets widen on hover; minimum pane size prevents collapsing to zero.
- [ ] Empty workspace shows a helpful drop target with "Drag a worktree here or click +".
- [ ] Broken-worktree pane (path gone): show an error state with a "Remove pane" button instead of a crashed terminal.
- [ ] Theme: terminal backgrounds match pane backgrounds, focused pane has a subtle outline.

---

## Ordering

M1 → M2 → M3 → M4 are strictly sequential (each needs the previous). M5 and M6 are independent after M4 and can be done in either order. M7 last.

## Open decisions

- Should task panes have multiple lists per repo (so separate "Now" / "Backlog" panes can show different slices), or a single shared list? Deferring — start with single shared list in M6; revisit if it feels cramped.
