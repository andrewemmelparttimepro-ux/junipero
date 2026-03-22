# Boba Heartbeat

On each wake:
1. Read `ops/TASK_BOARD.md` — find every task where Owner is `Boba`.
2. Tasks with `Status: In Progress` are yours to work on NOW. Do the work.
3. When you complete or change a task, **DO NOT edit TASK_BOARD.md directly**.
4. Instead, append your updates to `~/.openclaw/workspace/ops/agent-updates.json`.

## How to write an update

Read the current `ops/agent-updates.json` (it's always a JSON array — `[]` when empty). Append your entries and write the whole file back.

```json
[
  {
    "action": "move",
    "task_id": "TASK-038",
    "field": "Status",
    "value": "Review",
    "agent": "Boba",
    "timestamp": "2026-03-18T10:00:00"
  },
  {
    "action": "update",
    "task_id": "TASK-038",
    "field": "Notes",
    "value": "QA pass, validation results in projects/thrawn-console/qa/",
    "agent": "Boba",
    "timestamp": "2026-03-18T10:00:00"
  },
  {
    "action": "move",
    "task_id": "TASK-039",
    "field": "Status",
    "value": "Blocked",
    "agent": "Boba",
    "timestamp": "2026-03-18T10:00:00"
  },
  {
    "action": "update",
    "task_id": "TASK-039",
    "field": "Blockers",
    "value": "Need Andrew to confirm test coverage threshold",
    "agent": "Boba",
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
7. Also check `ops/REVIEW_QUEUE.md` for items awaiting validation.
8. Test claims, stress outputs, document findings with clear reproduction details.
9. The dispatcher (runs every 5 min) reads this file, applies changes to TASK_BOARD.md, then resets the file to `[]`.

**CRITICAL**: Do NOT try to edit TASK_BOARD.md directly. Write to `ops/agent-updates.json`. The dispatcher handles the board.
