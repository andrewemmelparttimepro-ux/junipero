# HEARTBEAT_SCHEDULE.md

## Staggered cadence
- :00 — Thrawn
- :10 — R2-D2
- :20 — C-3PO
- :30 — Qui-Gon
- :40 — Lando
- :50 — Boba

## General heartbeat protocol
Each agent should:
1. Read its heartbeat file
2. Check the task board for owned or upcoming work
3. Advance work or record status
4. Move completed work to Review, not Done
5. Escalate only if blocked or if Andrew action is required

## Current limitation
Persistent dedicated agent scheduling cannot be fully activated from the current webchat surface. This schedule is the intended operating cadence once the dedicated sessions are instantiated on a compatible surface/runtime.
