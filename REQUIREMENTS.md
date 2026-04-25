# Pluricode V1 Requirements

A native macOS app providing a freeform infinite canvas where terminal agents and task cards coexist. Agents work in isolated git worktrees. Users visually plan tasks, assign them to agents by dragging, and wire agents together for handover and review.

## Architecture

- **Native Swift/SwiftUI** with Metal-accelerated canvas rendering
- **Solo-only** — single user, no collaboration
- **Local-first** — all state persisted on disk, no cloud dependencies
- **Agent protocol** — Claude Code for V1; agent abstraction layer from day one so adding Codex, Gemini CLI, or custom scripts is a config change, not a rewrite

## Canvas

- Infinite pannable/zoomable surface (pinch, scroll, trackpad gestures)
- Two node types: **Terminal Nodes** and **Task Cards**
- Directed edges between any nodes, rendered as SVG-style bezier curves
- Edge types carry semantics:
  - `hands_off_to` — sequential delegation between terminals
  - `reviews` — code review relationship between terminals
  - `assigned_to` — task card assigned to a terminal
  - `blocks` / `blocked_by` — dependency between task cards
- Minimap for orientation on large canvases
- Canvas state auto-saved to disk
- Multi-select (box select, shift-click)
- Snap-to-grid toggle
- Named node groups (visual clustering, no nesting)

## Terminal Nodes

- Each node embeds a fully interactive terminal emulator (PTY)
- On creation, spawns a new git worktree from a user-selected base branch
- Launches the configured CLI agent inside the worktree
- Visual status indicator: `idle` | `working` | `waiting` | `done` | `error`
- Terminal output scrollback preserved per node
- Optional **role** label (architect, coder, reviewer, tester) — role injects a role-specific CLAUDE.md into the worktree before the agent starts
- Duplicate a terminal node: creates a new worktree forked from the same commit

## Task Cards

- Lightweight canvas nodes: title + body (Markdown)
- Visual states: `draft` | `ready` | `in_progress` | `done` | `failed`
- Drag a task card onto a terminal node to assign it — the task content becomes the agent's prompt
- Tasks can have `blocks` / `blocked_by` edges between them
- Bulk creation: paste or type multi-line text, split into one card per line

## Agent-to-App Communication (MCP Bridge)

Pluricode runs a local MCP server per terminal node. The agent inside the terminal connects to it and gains tools to update the canvas. This is how agents report back without the user polling terminal output.

### MCP tools exposed to agents

- `update_task(task_id, status, summary)` — mark assigned task as done/failed, attach a summary
- `create_task(title, body)` — agent discovers subtasks and puts them on the canvas
- `request_review(terminal_id, message)` — signal a connected reviewer terminal to begin
- `get_task(task_id)` — read task details
- `list_tasks(filter)` — list tasks visible on the canvas

### Flow example

1. User drags Task A onto Terminal 1
2. Terminal 1's agent receives the task as its prompt
3. Agent works, then calls `update_task(A, "done", "Implemented auth middleware")`
4. Task A's card on the canvas flips to `done` with the summary visible
5. If Terminal 1 is wired to Terminal 2 via `reviews`, user clicks the edge to trigger review
6. Terminal 2's agent receives the diff + task summary as context

## Agent Wiring (Terminal-to-Terminal Connections)

- Draw a directed edge from Terminal A to Terminal B with a type:
  - **hands_off_to**: A's output context (branch ref, summary, diff) is injected into B
  - **reviews**: B receives A's diff for code review, can post feedback via MCP
- Connections trigger manually in V1 — user clicks "send" on the edge
- Visual arrow shows data flow direction
- Edge carries a payload log: what was sent, when

## Worktree Management

- Each terminal node owns exactly one git worktree
- Worktrees created under a configurable root directory
- Deletion of a terminal node prompts: clean up worktree or keep it
- Side panel listing all active worktrees with branch name, status, and uncommitted changes count
- Quick action: open worktree in external editor (VS Code, Zed, Xcode)

## Agent Abstraction Layer

Agents are defined by a protocol, not hardcoded:

```
AgentDefinition:
  name: String           — "Claude Code", "Codex", "Gemini CLI"
  launch_command: String  — "claude", "codex", "gemini"
  launch_args: [String]   — ["--mcp", "{mcp_socket_path}"]
  supports_mcp: Bool      — whether the agent can connect to our MCP server
  role_injection: enum    — how role context is provided (claude_md | system_prompt | env_var)
```

V1 ships with Claude Code pre-configured. Adding a new agent is adding a new `AgentDefinition`.

## Persistence

- Canvas state (node positions, edges, groups) → JSON file per canvas
- Task card content → inline in canvas JSON
- Terminal scrollback → separate file per terminal node
- Worktree metadata → derived from git, not duplicated
- One canvas per project directory; a project is just a git repo

## Non-goals for V1

- Collaboration / multiplayer
- Cloud sync
- Auto-triggering connections (all manual)
- Proximity-based context injection
- Voice input
- Mobile or iPad support
