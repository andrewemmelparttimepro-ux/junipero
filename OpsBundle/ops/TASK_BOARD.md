# TASK_BOARD.md

> **Korbis-Spawn — V1 starter board.** Clean slate for the Korbis × Cyclops × Thrawn Phase 1 deployment.
> Master Thrawn keeps its own board; this one is exclusive to the spawn.

## Status lanes

- Inbox
- Ready
- In Progress
- Review
- Blocked
- Done

## Rules

1. Every task has an owner. Thrawn is the only hub — every specialist task flows `Owner=Thrawn → Owner=<Specialist> → Owner=Thrawn`.
2. Every task has a deliverable.
3. Every task has a current status.
4. Nothing moves to `Done` until Thrawn reviews and confirms the deliverable.
5. If work exists without a deliverable link or output path, it is not done.
6. If a task is waiting on Andrew, mark it `Blocked` and state exactly what decision or approval is needed.
7. Thrawn owns review discipline and status integrity.

## Phase 1 reminders for the spawn

- **Thrawn agents are dormant in V1.** Heartbeats fire to prove the spawn is alive; no analysis is being performed yet. Phase 2 activates Foreman / Inspector / Pulse and begins frame analysis on the Korbis camera feeds.
- **The supervisor flow runs through Cyclops, not the board.** Operator instructions to the jobsite display are pushed via the Cyclops composer and written to Firestore `instructions/`. The board here is for Korbis-spawn engineering tasks, not real-time operations.
- **Footage is being recorded** to `/korbis-footage/` continuously and indexed by camera + timestamp. Do not delete; Phase 2 needs this corpus.

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

<!--
  Empty by design. Phase 1 work is tracked via the four-week build plan
  document on Andrew's Desktop, not on this board. Tasks land here as the
  spawn graduates from infrastructure-only to active operations.
-->
