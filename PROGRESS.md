# Xyzterminal — Progress

## Phase 1: Metal Canvas Foundation ✅
- Infinite pannable/zoomable Metal-rendered canvas (pinch, scroll, trackpad)
- Two node types rendered as SDF rounded rectangles with instanced drawing
- Click to select, shift-click for multi-select, box-select by dragging empty space
- Drag nodes to move them, delete with Backspace
- Toolbar buttons and keyboard shortcuts (T = task card, E = terminal)
- Dark theme with blue selection outlines

## Phase 2: Bezier Edges ✅
- CPU-tessellated cubic bezier curves between nodes, rendered as triangle lists
- Option+drag from any node to another to create an edge
- Preview edge follows cursor during drag
- Edge types auto-inferred from node kinds:
  - Terminal → Terminal: handsOffTo (green)
  - Task Card → Terminal: assignedTo (blue)
  - Task Card → Task Card: blocks (red)
- Arrowheads showing direction
- Edges update live as nodes are moved

## Phase 3: Persistence and Task Cards ✅
- All model types Codable (SIMD2 extension, custom NodeKind coding)
- Auto-save to `{project}/.xyzterminal/canvas.json` (debounced 1s)
- Load on app startup, persists nodes/edges/camera across restarts
- SwiftUI text label overlay on nodes (title, status dot, body preview)
- Labels scale with zoom, hidden below 0.25x
- Double-click task card → editor sheet (title, markdown body, status picker)
- Task card statuses: draft, ready, inProgress, done, failed

## Phase 4: Terminal Nodes (PTY + SwiftTerm) ✅
- SwiftTerm `LocalProcessTerminalView` embedded as NSView subview of MTKView
- Each terminal spawns a real shell ($SHELL, login mode)
- Terminal views positioned on top of Metal canvas, synced every frame at 60fps
- Auto-hide when zoomed out too far or off-screen
- Click terminal content → terminal gets keyboard focus
- Click canvas → canvas gets keyboard focus
- Process termination updates node status to "done"

## Phase 5: Git Worktree Management ✅
- `WorktreeManager` wraps `git worktree add/remove/list` via Process
- Each terminal node creates its own worktree under `{repo}/.xyzterminal/worktrees/`
- Branches from the repo's default branch (auto-detected from origin/HEAD)
- Shell starts in the worktree directory
- Branch name shown in terminal title bar
- Worktree cleaned up when terminal node is deleted
- Project directory picker on first launch (persisted in UserDefaults)

## Phase 6: Agent Abstraction and Launching ✅
- `AgentDefinition` struct: name, launchCommand, launchArgs, supportsMCP, roleInjection
- Claude Code and Codex pre-configured as builtins
- Terminal config sheet on creation: agent picker, startup script, optional role
- Startup script auto-typed into terminal after 1s delay (e.g. `claude --dangerously-skip-permissions`)
- "Save as default" persists config to UserDefaults for future terminals
- `RoleInjector` writes role-specific CLAUDE.md into worktree (architect/coder/reviewer/tester)

## Remaining Phases

### Phase 7: MCP Bridge Server
- Per-terminal MCP server (separate executable)
- Agents can call update_task, create_task, request_review, get_task, list_tasks
- Bidirectional agent-to-app communication via Unix domain socket

### Phase 8: Terminal-to-Terminal Wiring
- hands_off_to: source output context injected into target
- reviews: target receives source diff for code review
- Manual trigger via "send" button on edge
- Edge payload log

### Phase 9: Minimap, Drag-to-Assign, Polish
- Minimap overlay
- Drag task card onto terminal → agent receives task as prompt
- Duplicate terminal node
- Settings panel
