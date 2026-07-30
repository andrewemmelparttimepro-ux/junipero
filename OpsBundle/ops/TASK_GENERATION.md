# TASK_GENERATION.md

## Why this exists
The flow board is Andrew's single pane of glass. At any moment it must answer: what is going on, who owns it, and where it came from. That only works if EVERY unit of work is a card, and if cards keep generating even when no obvious signal arrives.

## Rule 1 — Card-first
No agent works on anything that is not a card. If you are about to do work and no card exists, create the card first (via your JSON update file), then work it. Heartbeat summaries are receipts, not a substitute for cards.

## Rule 2 — Lane depth
Each business lead keeps at least 2 live (non-Done) cards in their lane at all times. If your lane is below depth at wake, run the generation pass (Rule 3) before anything else. If the pass genuinely produces nothing, update your stream's objective card with a dated "stream quiet" note citing the evidence you checked — that note is the proof you looked.

## Rule 3 — The generation pass (ranked sources)
Derive next-action cards from these sources, in order. Every generated card must name its source in Notes.

1. **Routed signals** — cards Dwight put in your lane. Obvious tasks; work them first.
2. **Objective decomposition** — `workspace/objectives.json` holds one Revenue Stream objective per business with real context in `notes`. Decompose the current phase into the next 1–3 concrete actions. Tag cards with `objective` and `phase` fields so the Objectives tab tracks them.
3. **Proof verdicts** — your latest Product Sentinel run. Any FAIL, missing screenshot, Clarity gap, or regression becomes a card.
4. **Clarity signals** — rage clicks, dead clicks, quick backs, broken funnels on your product become UX cards (cite the Clarity dashboard section).
5. **Commitment sweep** — your citadel page and past card notes. Anything promised but not delivered, unbilled, or awaiting a reply becomes a follow-up card.
6. **Weekly rubric** — max 3 evidence-cited improvement suggestions per week (see your role card).

## Rule 4 — Card anatomy for generated tasks
- Title: prefixed with the business name (`SandPro OMP: ...`, `Hit Zero: ...`, `Spas 360: ...`) so the board reads at a glance.
- Notes: source citation (signal id / objective+phase / proof path / Clarity section / commitment ref).
- `objective` + `phase` fields in the JSON create when the card belongs to a stream objective.
- Next step: the smallest concrete action.

## Rule 5 — No slop
Generation is not invention. A card with no citable source does not get created. If two sources produce the same task, one card, both citations. Thrawn rejects sourceless cards at review and deletes duplicates.

## Thrawn's enforcement duties
- Every active objective has ≥1 live card at all times; if a lane ignored Rule 2, Thrawn decomposes the objective himself and assigns the cards.
- Cards without a source citation bounce back to their creator.
- The board is the record: work discovered in heartbeat summaries that never had a card becomes a retroactive card plus a process note.
