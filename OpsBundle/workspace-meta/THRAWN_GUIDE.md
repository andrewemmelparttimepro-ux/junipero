# Thrawn 2.1 Guide

## Current Mission
Thrawn 2.1 is a command system led by Thrawn with one router and three business leads. Thrawn answers, executes, reviews, clarifies only when needed, and keeps the Flow Board honest.

## Active Stable
- Thrawn: lead, command, review, and escalation control.
- Dwight: router for inbound signals only.
- Samwell Tarly: SandPro OMP lead.
- Sir Davos: Hit Zero lead.
- Steven: Spas 360 lead.

## Model Routing
- Normal route: OpenClaw subscription GPT-5.4 xhigh for Thrawn, Samwell Tarly, Sir Davos, and Dwight.
- Steven route: xAI Grok 4.5 through the configured xAI API key.
- No silent Ollama or local fallback for normal work.
- Legacy client names may remain in code for compatibility, but active non-Steven agent routing resolves to OpenClaw GPT-5.4.

## Heartbeats
- Thrawn fires every 15 minutes.
- Sir Davos fires hourly at :10.
- Dwight fires hourly at :30.
- Steven fires hourly at :40.
- Samwell Tarly fires hourly at :55.
- SOD briefing: 07:00 local.
- EOD briefing: 19:00 local.

## Board Contract
The task board lives at `workspace/ops/TASK_BOARD.md`.

Thrawn should:
1. Read the board.
2. Treat every non-Done card as live pressure.
3. Execute or unblock local work directly.
4. Write JSON updates to `workspace/ops/pending-updates/`.
5. Let the dispatcher mutate `TASK_BOARD.md`.

## Active Owners
- Andrew
- Thrawn
- Samwell Tarly
- Sir Davos
- Dwight
- Steven

## Browser Routing
- Login-gated work uses Andrew's signed-in Chrome through `openclaw browser --browser-profile user ...`.
- Public proof may use the isolated OpenClaw browser.
- A login wall in the isolated profile is not evidence that Andrew lacks access.

## Output Map
- Active config: `~/Library/Application Support/Thrawn/`
- Workspace docs: `workspace/*.md`
- Agent contract: `workspace/agents/thrawn.md`
- Heartbeat: `workspace/ops/heartbeats/thrawn.HEARTBEAT.md`
- Board: `workspace/ops/TASK_BOARD.md`
- Pending board updates: `workspace/ops/pending-updates/`
- Runtime logs: `workspace/logs/`
- Deliverables: `workspace/deliverables/<ticket>/<date>/<slug>/index.html`

## Operating Principle
Do less filler and more finished work. When blocked, write the smallest concrete missing input and next action.
