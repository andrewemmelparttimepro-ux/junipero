# Thrawn Initiative Heartbeat

This beat fires at :30 every hour. Its purpose is proactive work generation when the system is idle.

## Gate check

If Andrew has sent a message in the current thread within the last 30 minutes, reply `HEARTBEAT_OK` and stop. Do not generate initiative work while he is active — he is steering.

## Priority stack (work top to bottom, stop when you act)

### 1. Board hygiene
- Tasks stuck in `Review` with no movement for 2+ hours → investigate, approve if delivered, or spawn a fix task
- Tasks in `Blocked` where the blocker may have been resolved → move back to `Ready`
- Tasks in `In Progress` with no recent notes or agent output → flag as stale, ping the owner
- Tasks with no Owner → assign to the correct specialist
- Tasks in `Inbox` → triage, assign owner, move to `Ready`

### 2. Unblock other agents
- Is there a brief, spec, or decision that would give an idle agent work?
- Can a large task be broken into smaller pieces that can be parallelized?
- Does an agent need input from another agent? Write the bridge artifact.

### 3. Goal gap analysis
- Read `USER.md` for Andrew's stated goals and active projects
- Read the project directories in `projects/` for current state
- Compare what's on the board to what Andrew is trying to accomplish
- If a project goal has no tasks covering it, draft a new task in `Inbox` with a clear title, owner suggestion, and deliverable

### 4. Proactive research triggers
- If a project is mid-build, what's the next phase?
- Queue research tasks for Qui-Gon on upcoming needs
- Queue copy/positioning tasks for Lando if product truth has changed
- Flag what Boba should QA next based on recent completions

### 5. Net-new ideas (only if 1-4 produced nothing)
- Based on Andrew's goals and current project momentum, what are 1-3 high-value actions that would move things forward?
- Ground these in real context — no invented busywork
- Draft as `Inbox` tasks with clear rationale in Notes

## Output format

Read the current `ops/agent-updates.json` (it's always a JSON array — `[]` when empty). Append your entries and write the whole file back.

```json
[
  {
    "action": "move",
    "task_id": "TASK-039",
    "field": "Status",
    "value": "Done",
    "agent": "Thrawn",
    "timestamp": "2026-03-18T10:00:00"
  },
  {
    "action": "update",
    "task_id": "TASK-039",
    "field": "Notes",
    "value": "Validated — QA pass confirmed",
    "agent": "Thrawn",
    "timestamp": "2026-03-18T10:00:00"
  },
  {
    "action": "create",
    "task_id": "TASK-NEW",
    "title": "Research Vercel edge config for Open Mat",
    "owner": "Qui-Gon",
    "status": "Inbox",
    "priority": "Medium",
    "notes": "Next phase after TASK-026 deploy",
    "agent": "Thrawn",
    "timestamp": "2026-03-18T10:00:00"
  }
]
```

For new tasks, use `"task_id": "TASK-NEW"` — the dispatcher will auto-assign the next TASK-NNN ID.

**Do NOT edit TASK_BOARD.md directly.** Write to `ops/agent-updates.json`. The dispatcher handles all board mutations.

## Discipline

- Never generate more than 3 new tasks per initiative beat
- Every new task must have a clear deliverable and owner
- If the board is healthy and goals are covered, reply `HEARTBEAT_OK` — doing nothing is a valid outcome
- Quality over quantity. One well-scoped task beats five vague ones.
