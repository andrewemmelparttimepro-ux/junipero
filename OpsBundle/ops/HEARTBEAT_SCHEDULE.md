# HEARTBEAT_SCHEDULE.md

## V2.1 cadence

Matches `agent-scheduler.json` (the live source of truth):

- Thrawn: every 15 minutes (offset :00).
- Sir Davos (Hit Zero): hourly, offset :10.
- Dwight (Router): hourly, offset :30.
- Steven (Spas 360): hourly, offset :40.
- Samwell Tarly (SandPro OMP): hourly, offset :55.
- Start-of-day briefing: 07:00 local. End-of-day briefing: 19:00 local.

## Known constraint

Heartbeats fire only while Thrawn.app is running. If the app is closed, no agent runs — a multi-day gap in `ops/agent-output/*.json` timestamps means the app was closed, not that agents failed.
