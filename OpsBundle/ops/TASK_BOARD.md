# TASK_BOARD.md

> Thrawn command board. Active stable: Thrawn, Samwell Tarly, Sir Davos, Dwight, Steven.

## Status values

- Inbox
- Ready
- In Progress
- Review
- Blocked
- Done

## Rules

1. Active owners are Andrew, Thrawn, Samwell Tarly, Sir Davos, Dwight, and Steven.
2. Thrawn-owned cards are live pressure: execute, unblock, clarify, review, or close them.
3. Mark a task Blocked for Andrew only when his taste, credential, preference, business judgment, or outside-world authority is the missing input.
4. Review and Blocked share the Review column in Flow. Review cards are purple; when review exposes a real blocker, change Status to Blocked and record the exact blocker plus smallest next action so the card turns red.
5. Nothing moves to Done until review is present and any produced artifact has a human-readable deliverable path.
6. Do not edit this board directly from prompts. Write JSON updates to `workspace/ops/pending-updates/updates-thrawn-chat.json` or the heartbeat update file.

## Task template

```md
### TASK-000
- Title:
- Owner:
- Collaborators:
- Status:
- Priority:
- Project:
- Requested by:
- Created:
- Due:
- Inputs:
- Deliverable:
- Brain path:
- Notes:
- Review status:
- Blockers:
- Next step:
```

## Active tasks

<!-- New work appears below. Thrawn routes specialist work to the active stable. -->
