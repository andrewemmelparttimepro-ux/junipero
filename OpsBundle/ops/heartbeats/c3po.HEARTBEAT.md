# C-3PO Heartbeat

On each wake:
1. Read `ops/TASK_BOARD.md` — find every task where Owner is `C-3PO`.
2. Tasks with `Status: In Progress` are yours to work on NOW. Do the work.
3. When you complete or change a task, **DO NOT edit TASK_BOARD.md directly**.
4. Instead, append your updates to `~/.openclaw/workspace/ops/agent-updates.json`.

## How to write an update

Read the current `ops/agent-updates.json` (it's always a JSON array — `[]` when empty). Append your entries and write the whole file back.

```json
[
  {
    "action": "move",
    "task_id": "TASK-015",
    "field": "Status",
    "value": "Review",
    "agent": "C-3PO",
    "timestamp": "2026-03-18T10:00:00"
  },
  {
    "action": "update",
    "task_id": "TASK-015",
    "field": "Notes",
    "value": "Schema validated, migration tested against staging",
    "agent": "C-3PO",
    "timestamp": "2026-03-18T10:00:00"
  },
  {
    "action": "move",
    "task_id": "TASK-016",
    "field": "Status",
    "value": "Blocked",
    "agent": "C-3PO",
    "timestamp": "2026-03-18T10:00:00"
  },
  {
    "action": "update",
    "task_id": "TASK-016",
    "field": "Blockers",
    "value": "Need Andrew to confirm API key rotation",
    "agent": "C-3PO",
    "timestamp": "2026-03-18T10:00:00"
  }
]
```

## Action types

| action | required fields | use when |
|--------|----------------|----------|
| `move` | task_id, field, value | changing Status, Owner, Priority |
| `update` | task_id, field, value | updating Notes, Blockers, Next step |

Valid Status values: `Inbox` `Ready` `In Progress` `Review` `Blocked` `Done`

## Rules

5. Move completed work to `Review` — never `Done`.
6. If a task requires Andrew's decision, set Status to `Blocked` and write the decision needed in Blockers.
7. Validate data assumptions, schema risks, and API contracts before marking anything Review.
8. The dispatcher (runs every 5 min) reads this file, applies changes to TASK_BOARD.md, then resets the file to `[]`.

**CRITICAL**: Do NOT try to edit TASK_BOARD.md directly. Write to `ops/agent-updates.json`. The dispatcher handles the board.
