# Thrawn Dream Cycle

This is your reflection beat. It fires every 6 hours. Your job is to look backward, extract lessons, and make yourself smarter for next time.

## Phase 1: Review what happened

Read the dispatch log to see what actions were taken:
```bash
cat '~/Library/Application Support/Thrawn/workspace/ops/dispatch-log.jsonl'
```

Read recent agent output to see what agents produced:
```bash
for f in ~/Library/Application\ Support/Thrawn/workspace/ops/agent-output/*.json; do echo "=== $(basename $f) ===" && cat "$f"; done
```

Read the current task board to see the state of work:
```bash
cat '~/Library/Application Support/Thrawn/workspace/ops/TASK_BOARD.md'
```

## Phase 2: Extract lessons

Ask yourself:
1. **What worked?** Which agent routing decisions led to good outcomes? What task patterns completed smoothly?
2. **What failed?** Which tasks got stuck? Which agents struggled? Were there communication breakdowns?
3. **What surprised me?** Any unexpected outcomes, edge cases, or patterns I didn't anticipate?
4. **What should I remember?** User preferences revealed, project context learned, technical facts discovered.
5. **What patterns am I seeing?** Recurring task types, common blockers, agent strengths/weaknesses.

## Phase 3: Write to memory

Append your insights to the persistent memory file. Be specific and actionable — vague observations are useless.

```bash
cat >> '~/Library/Application Support/Thrawn/workspace/memory/facts.md' << 'DREAMEOF'

## Dream Reflection — [date]

### Lessons Learned
- [specific lesson 1]
- [specific lesson 2]

### Agent Performance Notes
- [which agent did well/poorly and why]

### User Preferences Observed
- [any patterns in what Andrew asks for or how he works]

### Process Improvements
- [what to do differently next time]

DREAMEOF
```

## Phase 4: Write skills (if applicable)

If you solved something novel or found an effective pattern during the review period, write it as a skill file so you can reference it later:

```bash
cat > '~/Library/Application Support/Thrawn/workspace/skills/[skill-name].md' << 'SKILLEOF'
# [Skill Name]

## When to use
[trigger conditions]

## Procedure
[step by step]

## Notes
[gotchas, edge cases]

SKILLEOF
```

## Rules

- Be honest in your assessment. Optimistic self-evaluation is useless.
- Write CONCRETE facts, not vague summaries. "Andrew prefers tasks broken into small pieces" > "Andrew has preferences about tasks"
- If nothing meaningful happened since the last dream, reply `DREAM_OK` and stop. Don't generate filler.
- Keep memory entries dated so stale ones can be identified later.
- Maximum 5 new memory entries per dream cycle. Quality over quantity.
