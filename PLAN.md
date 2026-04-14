# Reactive Workflow Engine — Implementation Plan

## Context

Xyzterminal's core value proposition is combining task tracking with visual workflow building — chaining agents together so a task flows from agent to agent automatically. Today the canvas is manual: the user drags tasks onto terminals one at a time, and nothing reacts when a task completes. The system needs to become a live execution graph where edges are triggers, task completion drives dispatch, agents are configurable entities, and conditional routing enables review loops.

---

## Milestone 1: Extract WorkflowEngine from UI

**Goal**: Move task assignment logic out of the input handler (UI layer) into a shared `WorkflowEngine` that both UI gestures and MCP callbacks can invoke. Pure refactor, no behavior change.

**Why first**: Every subsequent milestone needs a central place to assign tasks and send prompts. Right now that logic is buried in `CanvasInputHandler` which MCP handlers can't reach.

### Changes

**New file**: `Xyzterminal/Wiring/WorkflowEngine.swift`
- `static func assign(taskID:terminalID:document:sessions:)` — moved from `CanvasInputHandler.assignTask` (line 265)
- `static func buildPrompt(taskData:taskID:terminalID:document:)` — moved from `CanvasInputHandler.buildAssignmentPrompt` (line 290)
- Keep the existing logic intact: blocker check, edge cleanup, edge creation, status transition, prompt generation, stdin send

**Modified**: `Xyzterminal/Canvas/CanvasInputHandler.swift`
- `assignTask` becomes a thin delegate: calls `WorkflowEngine.assign(...)` passing `terminalManager?.sessions`
- Remove `buildAssignmentPrompt` (now lives in WorkflowEngine)

**Modified**: `Xyzterminal/Wiring/WiringAction.swift`
- No functional change, but `WiringAction` and `WorkflowEngine` now live side-by-side in `Wiring/`

**Fix**: `inferEdgeType` at `CanvasInputHandler.swift:552` — the `(.terminal, .taskCard)` case currently returns `.assignedTo` which is semantically backwards (the terminal isn't "assigned to" the task). Change to `.blocks` or introduce a guard that prevents drawing edges from terminals to tasks (they have no meaning in the workflow model).

### Verification
- Drag a task onto a terminal — same behavior as before (prompt sent, status transitions)
- Select edge + Enter — handoff still works via WiringAction
- MCP `update_task` — still works (no change yet to MCPToolHandlers)

---

## Milestone 2: Reactive Dispatch on Task Completion

**Goal**: When an agent marks a task `done` via MCP, the system walks downstream edges and auto-assigns the next unblocked task to its wired terminal. This is the core of chaining.

### Changes

**Modified**: `Xyzterminal/Wiring/WorkflowEngine.swift`
- Add `static func dispatchDownstream(completedTaskID:document:sessions:)`
  1. Find all outgoing `blocks` edges where `sourceID == completedTaskID`
  2. For each target task: call `document.unresolvedBlockers(for: targetID)`
  3. If empty (all blockers resolved): find an `assignedTo` edge from that target task to a terminal
  4. If found: call `WorkflowEngine.assign(taskID:terminalID:document:sessions:)`
  5. If no pre-wired terminal: transition task to `.ready` (signals it's available for manual assignment)

**Modified**: `Xyzterminal/MCP/MCPToolHandlers.swift`
- In `updateTask` (line 41): after setting status to `done`, call `WorkflowEngine.dispatchDownstream`
- Pass `sessions` through (already available via the `handle` signature)

**Modified**: `Xyzterminal/Wiring/WorkflowEngine.swift` — `buildPrompt`
- Gather `result` field from all completed predecessor tasks (walk incoming `blocks` edges where source task is `done`)
- Add a "## Predecessor Results" section to the prompt with each predecessor's title and result
- This is how Agent B sees what Agent A produced

### User-facing behavior
- User draws: Task A `blocks` Task B, Task B `assignedTo` Terminal 2
- User assigns Task A to Terminal 1 (drag)
- Agent in Terminal 1 finishes, calls `update_task(status: "done", summary: "...")`
- System auto-assigns Task B to Terminal 2 with Agent 1's result in the prompt
- Chain continues

### Verification
- Set up a two-task chain: A blocks B, B assigned to a terminal
- Assign A manually, let the agent complete it via MCP
- Verify B auto-starts with A's result in the prompt
- Verify a task with multiple blockers only dispatches when ALL are done

---

## Milestone 3: Configurable Agent Profiles

**Goal**: Replace the rigid `Role` enum with user-configurable agent profiles. Users create profiles (e.g., "Task Reviewer", "Implementation Engineer", "Code Reviewer") and assign them to terminals. Profiles define the agent's instructions, which get injected into the worktree.

**Why**: The current 4 hardcoded roles (architect/coder/reviewer/tester) can't express workflow-specific behaviors like "check if this task description is complete before passing it to implementation." Configurable profiles let users design agent behaviors that match their workflow.

### Data model changes

**New file**: `Xyzterminal/Agent/AgentProfile.swift`
```
struct AgentProfile: Identifiable, Codable {
    let id: UUID
    var name: String              // "Task Reviewer", "Backend Coder", etc.
    var instructions: String      // Injected as CLAUDE.md content
    var agentDefinition: String   // "Claude Code" or "Codex" — which binary to run
    var color: SIMD4<Float>       // Visual identifier on canvas
}
```

**Modified**: `Xyzterminal/Model/CanvasDocument.swift`
- Add `var agentProfiles: [UUID: AgentProfile]` — document-level storage
- Seed with default profiles matching the old roles on first load (architect, coder, reviewer, tester)

**Modified**: `Xyzterminal/Model/CanvasNode.swift`
- `TerminalNodeData`: replace `role: Role?` with `profileID: UUID?`
- Remove the `Role` enum entirely
- Keep `agentName` as a computed property derived from the profile's `agentDefinition`

**Modified**: `Xyzterminal/Model/Persistence.swift`
- `CanvasSnapshot`: add `agentProfiles: [AgentProfile]`
- Migration: on load, if old `role` field exists and no profiles, create default profiles and map

**Modified**: `Xyzterminal/Agent/RoleInjector.swift`
- Rename to `ProfileInjector`
- `inject(profile:method:worktreePath:)` — writes `profile.instructions` to CLAUDE.md
- No more hardcoded role content

**Modified**: `Xyzterminal/Terminal/TerminalManager.swift`
- `sync`: look up profile from `document.agentProfiles[data.profileID]` instead of `data.role`
- Pass profile to `ProfileInjector.inject`

### UI changes

**Modified**: `Xyzterminal/Canvas/TerminalConfigSheet.swift`
- Profile picker: dropdown of existing profiles
- "New Profile" button: opens inline editor for name + instructions
- Shows the profile color as a swatch
- Agent definition picker (Claude Code / Codex)

**Modified**: `Xyzterminal/Canvas/CanvasRenderer.swift`
- Terminal node title bar tinted with profile color
- Profile name displayed in the node label overlay

### Verification
- Create a custom profile "Task Quality Checker" with instructions
- Assign it to a terminal
- Verify CLAUDE.md in the worktree contains the custom instructions
- Verify the terminal renders with the profile name and color
- Verify old canvases load correctly (migration from Role to profileID)

---

## Milestone 4: Terminal Status via MCP + Availability

**Goal**: Agents can report their own status (idle/working) via MCP. The dispatch system uses this to prefer idle terminals when auto-assigning.

### Changes

**Modified**: `Xyzterminal/MCP/MCPToolHandlers.swift`
- Add `update_terminal_status` tool
- Accepts `status: "idle" | "working" | "waiting" | "error"`
- Updates `TerminalNodeData.status` on the calling node
- Validates the nodeID matches a terminal node

**Modified**: `Xyzterminal/Wiring/WorkflowEngine.swift`
- `dispatchDownstream`: when looking for a terminal to assign to, check `TerminalNodeData.status`
- If the wired terminal is busy (working), queue the task as `.ready` instead of force-assigning
- Add `static func dispatchReady(document:sessions:)` — scans for `.ready` tasks with idle wired terminals and assigns them
- Call `dispatchReady` when a terminal transitions to `.idle`

**Modified**: `Xyzterminal/MCP/MCPToolHandlers.swift`
- After `update_terminal_status` sets idle, call `WorkflowEngine.dispatchReady`

### Verification
- Agent calls `update_terminal_status(status: "idle")` after completing work
- A queued `.ready` task auto-assigns to the now-idle terminal
- A task whose wired terminal is busy stays `.ready` until the terminal is free

---

## Milestone 5: Conditional Routing and Review Loops

**Goal**: Agents produce structured outcomes. Edges carry conditions. The system routes tasks to different downstream paths based on outcomes. This enables the review loop pattern: review agent → [approved: implementation] or [needs_info: flag for human].

### Data model changes

**Modified**: `Xyzterminal/Model/CanvasNode.swift`
- `TaskCardData`: add `var outcome: String = ""` — free-form string set by the agent (e.g., "approved", "needs_changes", "needs_human_review")

**Modified**: `Xyzterminal/Model/CanvasDocument.swift`
- `Edge`: add `var condition: String?` — if set, this edge only fires when the source task's outcome matches
- `EdgeType`: add `.flowsTo` case — explicit sequential flow (distinct from `.blocks` which is a dependency gate)

**Modified**: `Xyzterminal/MCP/MCPToolHandlers.swift`
- `update_task`: accept optional `outcome` parameter
- Agent calls: `update_task(status: "done", outcome: "approved", summary: "...")`

**Modified**: `Xyzterminal/Wiring/WorkflowEngine.swift`
- `dispatchDownstream`: walk both `blocks` and `flowsTo` edges
- For edges with a `condition`: only follow if `completedTask.outcome == edge.condition`
- For edges without a condition: always follow (backwards compatible)
- Special outcome `"needs_human_review"`: transition target task to a new `.flagged` status instead of auto-assigning; don't dispatch further

**Modified**: `Xyzterminal/Model/CanvasNode.swift`
- `TaskCardData.Status`: add `.flagged` case — task needs human attention before proceeding

### UI changes

**Modified**: `Xyzterminal/Canvas/EdgeActionOverlay.swift` (or equivalent)
- When an edge is selected, show a condition field where the user can type the matching outcome
- Display the condition as a label on the edge

**Modified**: `Xyzterminal/Canvas/CanvasRenderer.swift`
- Render condition labels on edges (small text near the midpoint of the bezier)
- Render `.flagged` tasks with a distinct visual (amber/warning color)

### The review loop pattern
```
[Task A: "Implement login"] 
    → (flowsTo) [Task B: "Review implementation"] assigned to Review Agent
        → (flowsTo, condition: "approved") [Task C: "Write tests"] assigned to Test Agent
        → (flowsTo, condition: "needs_changes") [Task A] ← cycle back to implementation
        → (flowsTo, condition: "needs_human_review") [Task A] ← flagged, workflow pauses
```

- The review agent finishes with `outcome: "approved"` → Task C auto-assigns
- The review agent finishes with `outcome: "needs_changes"` → Task A re-enters inProgress on its terminal
- The review agent finishes with `outcome: "needs_human_review"` → Task A gets flagged, user intervenes

### Verification
- Build a review loop on the canvas with conditional edges
- Assign the first task, let it chain through
- Verify "approved" follows the right path
- Verify "needs_changes" cycles back
- Verify "needs_human_review" flags and pauses
- Verify unconditional edges still work (backwards compatible)

---

## Milestone 6: Workflow-Level Prompt Context

**Goal**: When a task is assigned, the agent receives not just the task details but its full position in the workflow DAG — what came before, what comes after, and what the overall pipeline looks like.

### Changes

**Modified**: `Xyzterminal/Wiring/WorkflowEngine.swift` — `buildPrompt`
- Add a "## Workflow Context" section to the generated prompt
- Walk the DAG to build a textual representation:
  ```
  ## Workflow Context
  You are step 3 of 5 in this pipeline:
  1. [done] "Design API schema" → approved
  2. [done] "Review API design" → approved  
  3. [in progress] "Implement API endpoints" ← you are here
  4. [ready] "Review implementation"
  5. [draft] "Write integration tests"
  ```
- Include the overall goal if derivable (title of the first task in the chain)
- Include what downstream tasks expect: "After you complete this, your work will be reviewed by a Code Reviewer agent"

**Modified**: `Xyzterminal/Wiring/WorkflowEngine.swift` — `buildPrompt`
- Add MCP tool documentation to the prompt so the agent knows about `outcome`:
  ```
  When finished, call update_task with:
  - task_id: <id>
  - status: "done" or "failed"  
  - outcome: one of "approved", "needs_changes", "needs_human_review" (if this is a review task)
  - summary: brief description of what you did
  ```

### Verification
- Assign a task in the middle of a 4-task chain
- Check the terminal stdin for the workflow context section
- Verify it shows predecessor results and downstream expectations

---

## File Change Summary

| File | M1 | M2 | M3 | M4 | M5 | M6 |
|---|---|---|---|---|---|---|
| **new** `Wiring/WorkflowEngine.swift` | create | modify | | modify | modify | modify |
| **new** `Agent/AgentProfile.swift` | | | create | | | |
| `Canvas/CanvasInputHandler.swift` | modify | | | | | |
| `MCP/MCPToolHandlers.swift` | | modify | | modify | modify | |
| `Model/CanvasNode.swift` | | | modify | | modify | |
| `Model/CanvasDocument.swift` | | | modify | | modify | |
| `Model/Persistence.swift` | | | modify | | | |
| `Agent/RoleInjector.swift` | | | rename+modify | | | |
| `Terminal/TerminalManager.swift` | | | modify | | | |
| `Canvas/TerminalConfigSheet.swift` | | | modify | | | |
| `Canvas/CanvasRenderer.swift` | | | modify | | modify | |
| `Canvas/EdgeActionOverlay.swift` | | | | | modify | |
| `Wiring/WiringAction.swift` | — | — | — | — | — | — |

---

## Dependency Graph

```
M1 (extract) ──→ M2 (reactive dispatch) ──→ M4 (terminal status)
                       │                          │
                       ├──→ M6 (workflow context)  │
                       │                          │
M3 (agent profiles) ───┴──→ M5 (conditional routing) ←─┘
```

M1 and M3 are independent and could be done in parallel. M2 requires M1. M5 requires M2 and benefits from M3. M4 and M6 require M2.

Recommended order: **M1 → M2 → M3 → M4 → M5 → M6**

Each milestone is self-contained and delivers incremental value:
- After M1: cleaner architecture, same behavior
- After M2: basic chaining works end-to-end
- After M3: users can define custom agent behaviors
- After M4: smarter dispatch, agents self-report availability
- After M5: review loops, conditional branching, human-in-the-loop
- After M6: agents understand their role in the bigger picture
