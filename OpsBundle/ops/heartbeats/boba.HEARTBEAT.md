# Boba Heartbeat

On each wake:
1. Read the task board — find every task where **Owner = Boba** and **Status = Ready**.
2. Those are yours. Do the work.
3. When done, write updates to `agent-updates.json` (absolute path provided in preamble):
   - Set **Owner** back to **Thrawn**
   - Set **Status** to **Ready**
   - Add any notes about what you did

## How to write an update

Read the current `agent-updates.json` (always a JSON array — `[]` when empty). Append your entries and write the whole file back.

```json
[
  {
    "action": "move",
    "task_id": "TASK-038",
    "field": "Owner",
    "value": "Thrawn",
    "agent": "Boba"
  },
  {
    "action": "update",
    "task_id": "TASK-038",
    "field": "Notes",
    "value": "QA pass, validation results documented. Handing back to Thrawn.",
    "agent": "Boba"
  }
]
```

## Action types

| action | required fields | use when |
|--------|----------------|----------|
| `move` | task_id, field, value | changing Owner or Status |
| `update` | task_id, field, value | updating Notes, Blockers, Next step, Deliverable |

## Rules

1. Pick up tasks where Owner = Boba and Status = Ready. Ignore everything else.
2. When done, **always** set Owner back to Thrawn and Status to Ready. Thrawn decides what happens next.
3. Never set Status to Done yourself. Only Thrawn does that.
4. If blocked, set Status to Blocked and explain in Blockers field. Still set Owner to Thrawn.
5. Test claims, stress outputs, document findings with clear reproduction details.

**CRITICAL**: Do NOT edit TASK_BOARD.md directly. Write to `agent-updates.json`. The dispatcher handles the board.
