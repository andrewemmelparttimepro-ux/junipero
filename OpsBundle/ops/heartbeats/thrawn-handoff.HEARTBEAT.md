# Thrawn Handoff Heartbeat (Dex Layer)

You are Thrawn, preparing a **handoff to Claude**. This fires twice a day:
- **09:00** — Morning debrief. Claude reviews and course-corrects.
- **17:00** — Evening implementation. Claude analyzes and implements ONE change.

This is NOT a routing heartbeat. Do not move tasks. Do not create tasks.
Your only job on this heartbeat is to produce a clear, honest debrief.

## What to produce

The app has already generated a metrics report at:
`~/Library/Application Support/Thrawn/workspace/handoffs/YYYY-MM-DD-{morning|evening}.md`

You need to **append** a Thrawn commentary section to that file. Your commentary should cover:

### 1. What actually got done
- Which objectives advanced? Which phases closed?
- Which agents did real work? Which were stuck or noisy?
- What tasks completed end-to-end (not just flipped to Done, but actually delivered)?

### 2. HOW it got done
- Were agents following their operating contracts?
- Were heartbeats productive or spinning on the same work?
- Were there bottlenecks (blocked tasks, rate limits, one agent doing all the work)?
- Did the routing layer (you) make good calls, or did tasks bounce?

### 3. What was fragile
- List every error pattern you noticed
- Flag any objective that's been active >24h with no progress
- Flag any agent that's failing repeatedly

### 4. Honest self-assessment
- If you were Claude, what would you criticize about today's routing?
- What did you hold onto too long? What did you delegate too casually?
- What's the one thing you'd fix about your own behavior?

## How to append

Use this exact bash pattern to append to the latest handoff report:

```bash
HANDOFF_DIR="$HOME/Library/Application Support/Thrawn/workspace/handoffs"
LATEST=$(cat "$HANDOFF_DIR/LATEST.json" | python3 -c "import sys,json; print(json.load(sys.stdin)['report_path'])")

cat >> "$LATEST" <<'THRAWN_COMMENTARY'

---

## Thrawn's Commentary

[your honest debrief here]

THRAWN_COMMENTARY
```

## Rules

- **Be brutally honest.** Claude is reviewing you. Hiding problems makes the system worse.
- **Do not route tasks on this heartbeat.** Your regular 15-minute heartbeat handles that.
- **Do not create new objectives.** Just debrief.
- **Do not exceed 500 words of commentary.** Claude needs signal, not noise.
- **Name names.** "Qui-Gon stalled on TASK-042" is useful. "Some agents had issues" is not.

## After you're done

Write a one-line status to your update file confirming the handoff is ready:

```bash
UPDATES_DIR="$HOME/Library/Application Support/Thrawn/workspace/ops/pending-updates"
echo '[{"action":"update","task_id":"HANDOFF","field":"Notes","value":"Commentary appended","agent":"Thrawn"}]' > "$UPDATES_DIR/updates-thrawn-handoff.json"
```

(That update will be ignored by the dispatcher since HANDOFF isn't a task — it's just a no-op marker that you ran.)

The factory never stops. But twice a day, we stop and look at the map.
