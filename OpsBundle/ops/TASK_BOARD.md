# TASK_BOARD.md

## Status lanes

- Inbox
- Ready
- In Progress
- Review
- Blocked
- Done

## Rules

1. Every task must have an owner.
2. Every task must have a deliverable.
3. Every task must have a current status.
4. Nothing moves to `Done` until reviewed and confirmed delivered.
5. If work exists without a deliverable link or output path, it is not done.
6. If a task is waiting on Andrew, mark it `Blocked` and state exactly what decision or approval is needed.
7. Thrawn owns review discipline and status integrity.

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

### TASK-048
- Title: Dashboard UI Research — latest trends, standout examples, top 10 dos & don'ts
- Owner: Qui-Gon
- Status: Done
- Priority: High
- Requested by: Andrew
- Created: 2026-03-18
- Deliverable: `/Volumes/brain/NDAI/Assets/Reports/DASHBOARD-UI-RESEARCH.md`
- Notes: Boba QA PASS (2026-03-20 1:50 AM CT). Deliverable: /Volumes/brain/NDAI/Assets/Reports/DASHBOARD-UI-RESEARCH.md. All 6 checklist items validated: cookie-cutter problem section (5 root causes, 7 functional problems) ✅, standout examples (7 products: Linear, Vercel, Stripe, Raycast, Retool, Amplitude, Pitch — specific and current) ✅, emerging trends (7 trends, appropriately framed) ✅, Top 10 Dos ✅, Top 10 Don'ts ✅, sources table (19 primary sources with URLs) ✅. Quality rating: stronger than typical competitor research — goes beyond surface aesthetics to architectural and philosophical design decisions. OBS-DASH-001 (non-blocking): consider adding a 3-5 point executive summary of immediate actions at the top. No revisions required. Report is ready for Andrew. Thrawn to surface to Andrew during morning hours.
- Blockers: None
- Next step: Qui-Gon delivers report → Thrawn reviews → surfaces to Andrew

### TASK-049
- Title: Fix dispatcher error on agent-output/*.json files
- Owner: Andrew
- Status: Inbox
- Priority: Low
- Notes: Dispatcher logs show repeated errors every cycle: "ERROR processing r2d2.json: 'list' object has no attribute 'get'" (and same for quigon.json, lando.json, boba.json, c3po.json). Root cause: agent-output/*.json files use heartbeat/status array format [{...}] but the dispatcher expects dict format {key: value}. The dispatcher appears to be scanning the agent-output/ directory and trying to process all JSON files as task-update dicts — but those files are agent heartbeat logs meant for Thrawn review only, not dispatcher mutations. Fix: either (a) update dispatcher to skip agent-output/ files that aren't in update-dict format, or (b) separate agent heartbeat logs into a different directory (e.g. agent-heartbeats/) so the dispatcher only scans agent-updates.json. Current impact: log noise every 5 minutes; no task updates are being lost since agents correctly write task mutations to agent-updates.json, not to their individual output files. Non-blocking for now.
- Blockers: 
- Next step: 
