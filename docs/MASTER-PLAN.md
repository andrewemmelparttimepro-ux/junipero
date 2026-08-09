# Thrawn Master Plan — Full Audit & Rebuild (started 2026-08-08 night)

## Andrew's non-negotiables (verbatim intent, 2026-08-08)

1. **The chat's look is UNTOUCHABLE.** Early-2000s old-school aesthetic, kept in all the
   best ways. Interaction polish everywhere else must never restyle the chat surface.
2. **THE ANALOG CLOCK MUST REMAIN.**
3. The quirky CIC identity stays. Polish = best-practice interaction fundamentals
   (real buttons with hover/pressed states, feedback on every action, honest hit
   targets, nothing silent, nothing below an invisible fold) — never de-quirking.
4. Everything else is open, including layout.
5. **Purpose**: a tool Andrew lives in day-to-day that ALSO runs the business while he's
   away — with proper distinctions between surfaces so human brains keep things straight.
6. **ARI in Thrawn must be the SAME ARI built into Spas 360 in every way possible** —
   same identity, same memory/threads (product DB is ARI's home; Thrawn talks to that,
   never a parallel ARI).
7. Virtual-server fallback/redundancy agents: welcomed, explicitly not this build.
8. No corners. Nothing swept under the rug. Every finding surfaced.

## Status

- Burning fixes shipped 2026-08-08 ~22:30: chat resumes last thread on launch
  (ThreadStore.loadThreads), wizard SIGN IN rows wired to beginSignIn with progress +
  error surfacing, copy feedback, action bar out of the scroll fold. agents/README.md
  restored + whitelisted in launch cleanup.
- Full audit in flight: three parallel deep audits (app UI architecture + redundancy;
  agent wiring intention-vs-actual; runtime/ops/auth). Findings + plan sections land here.

## Plan sections (filled from audit results)

### A. Identity & sign-in (single coherent credential surface)
### B. Surface map & redundancy elimination (incl. duplicate chat entries)
### C. Agent intentions, wiring gaps, per-agent fixes
### D. ARI continuity contract (Thrawn ⇄ Spas 360 same-ARI guarantees)
### E. Interaction polish pass (buttons, feedback, affordances — chat + clock untouched)
### F. Away-mode: what runs while Andrew is gone, and how he can tell at a glance
### G. Kill list round 2 + code health

## C. AGENT WIRING AUDIT FINDINGS (2026-08-09, full report in audit transcript)

Top defects, ranked:
1. **Cloned codex credential**: AgentProviderProfileStore.swift:62-91 seeds thrawn/archivist/sentinel/dwight from ONE copied ~/.codex/auth.json (all byte-identical, Jul 26) — one expiry kills 4/5 agents. Claude seeding (:98) reads ~/.claude/.credentials.json which doesn't exist on Keychain installs → thrawn's claude NEVER authenticated, yet routed there 20×.
2. **.blocked erased every 30s**: AgentScheduler.swift:208-212 resets blocked→idle on every tick. Five hours of total failure showed "Standing by". No in-app failure visibility at all.
3. **Output truncated to 500 chars, read by nothing**: :1378/:529/:535; lastRunResults in zero views; only reader (HandoffStore:266) scans a nonexistent dir (workspace/ops/deliverables vs workspace/deliverables, 225 entries) so handoffs always say "no deliverables".
4. **Dwight has no inbox**: zero implementation/entitlements for Notes/Voice Memos/Mail/Messages (no NSAppleEventsUsageDescription, no automation entitlement); his ~73 no-op runs were structurally guaranteed. Sweep-result rule has no validator.
5. **Tool loop dead for all five agents**: AgentScheduler:544-561 skips executeToolCalls for subscription gateways → ToolRegistry/AutonomyPolicy/ShellCommandSafety gate NOTHING; real ceiling is codex sandbox danger-full-access (:1000). Prompts still teach the removed bash-fence harness.
6. **Two contradictory autonomy ladders**: AgentAutonomyStore (prompt) vs AutonomyPolicy (exec) disagree on 3/6 capabilities for dwight; AutonomyPolicy.overrides is lazy-static → UI changes don't apply until relaunch.
7. **Dispatcher create drops fields dict** (TaskDispatcher:298-373): Blocked/High cards land Ready/P2; shouldUpsertMissingField omits owner/status/priority/title.
8. **SystemPromptBuilder (chat) diverged from heartbeat prompts + contains false facts** (claims OpenClaw route, Steven "API" route; advertises archived openclaw browser tool).
9. **autoDelegateNamedSpecialistTasks reassigns cards on bare substring match** (:384-402) — "Dwight's sweep produced nothing" transfers the card to Dwight.
10. **Unbounded provider sessions + 80KB board injected every wake**; no compaction/rotation; single good run took 301s of the 900s watchdog.

Also: sentinel has phantom tool product_sentinel_run; objectives.json injected ONLY for thrawn while every lead's heartbeat requires it; charter v2 rules (no-silent-runs, forensics budget, sweep results) have NO enforcement code; Brain approvals/escalations tables have no Swift reader (agents told to file escalations with no client method); ARI/OTTO/SPOT invisible to scheduler/board (feed-only); deployed presence is courtesy-only; OpsBundle heartbeats stale (July) vs live (Aug); README.md quarantined per launch (fixed 8/8); voice peelVoiceLines can eat real content; readyWorkFire can wake agents every 2 min; auth failure = infinite no-backoff retry, only the external watchdog pages.

Audit-recommended rebuild order: (1) real per-agent credentials + refresh + backoff, (2) stop erasing .blocked + persist full transcripts, (3) Dwight real ingest or retire mandate, (4) one autonomy ladder enforced, (5) unify prompt builders, (6) fix dispatcher create/upsert, (7) board filtering + session rotation.

## A/RUNTIME AUDIT FINDINGS (2026-08-09) — condensed; fixes ranked in §6 of audit
- ROOT CAUSE of sign-in outage: one-time seed marker (.seeded-current-account-v1, AgentProviderProfileStore:68) froze a Jul-26 refresh token cloned into 4 codex profiles; rotated away Aug 5 → revoked. steven/codex + 4 grok profiles never seeded. Claude never seeded (source file doesn't exist on keychain Macs); thrawn's claude keychain token dead since Aug 8 22:00Z.
- Exactly ONE sign-in button app-wide pre-tonight (AgentsConsoleView:298); wizard's was vestigial. (Wizard buttons added 8/8 night.)
- Claude/Grok login subprocess output DISCARDED (ClaudeCLIProvider:89, GrokCLIProvider:82 — pipe never read, can deadlock >64KB). Worst diagnosability hole.
- codex findExecutable omits ~/.local/bin — app secretly runs ChatGPT.app's bundled codex.
- Watchdog credential probes were wrong for claude (keychain) + grok (auth.json) → permanent false "credentials-dead" pages every 6h — FIXED 8/9.
- Gateway (pro.ndai.thrawn.gateway, port 8787): healthy, keychain-secured, used by NOTHING since Aug 1 commissioning (6 requests ever). Decide: ARI integration path or retire.
- Storage: 1.1GB total; state/product-sentinel-guard 257MB stale since Jul 12; proofs/ 301MB no retention; codex logs_2.sqlite ~29MB×5. bin/: 8 of 15 scripts dead (task-dispatcher.py vs task-dispatch.py near-name live/dead pair!). provider-state.json + devops-brain.json stale. config.json says model glm-5.2 (gateway-era residue).
- BrainClient: one retry then SILENT drop, no dead-letter; fetchFeed renders 401 as empty feed; brain.json secrets plaintext (gateway does keychain right — inconsistency); watchdog source duplicated (repo + bin copies).
- Terminal sign-in fallbacks (the immediate fix): CODEX_HOME="…/subscription-profiles/<agent>/codex" codex login (×4: thrawn/archivist/sentinel/dwight); CLAUDE_CONFIG_DIR="…/subscription-profiles/thrawn/claude" claude auth login --claudeai. Grok healthy — don't touch.
- Structural: seedCurrentAccountOnce must re-seed on newer source OR die entirely (per-agent real logins); stop discarding login output; nvm-pinned PATHs in 5 plists break on node bump.

## B/UI AUDIT FINDINGS (2026-08-09) — top items; full 20-defect table in audit transcript
- CHAT ROOT CAUSE: selectedProjectBoard defaulted .spas360, outranking .command in ConsoleSectionBody precedence → FIXED (nil default). ThreadStore resume + preservedNames(threads/drafts/brain.json) also fixed+committed.
- Redundancy map: FOUR surfaces render the same thread list (drifting); THREE chat engines (ThreadStore 1497 LOC / PrimarySessionStore ~700 LOC never-used-in-practice / DeployedAgentHub); AgentGatewayPicker ×4 on screen; provider status ×5; Threads-section tap DOES NOTHING; popup Command button always forks a new thread.
- Sign-in surfaces: only AgentsConsoleView fully worked; "THRAWN BRAIN OFFLINE/Retry" calls refresh not beginSignIn; cursor/opencode render FAKE inert SIGN IN (backend nil); ~250 lines orphaned auth UI asks "Z.ai API key" under ChatGPT case; picker switches to dead routes silently. → Build ONE AccountsView.
- Dead: MemoryGraph quartet (~1300 LOC unreachable), BitcoinWidget, ThrawnNeonWidget, ChatInputView, GatewayStatusPanel+GatewayClient (latent crash), TaskBoardView shim, XPCExecutionBackend (APPSTORE_BUILD undefined), HandoffStore (no view), Cognee polled every 25s uninstalled, Ollama bound in 5 places surfaced in 0.
- Layout: left panel needs 710pt gets 590-660 (CLOCK CLIPPED at every size — clock must remain, layout must give it room); expanded rail overlays 128pt; SpawnAgentSheet taller than min window; voice overlay ignores traffic-light inset; black-on-obsidian + white-on-white text; grain texture redraws 16.6k random ellipses per geometry change; 2 keyboard shortcuts app-wide.
- Rebuild recs: one Destination enum nav model; one chat engine (keep ThreadStore, thread participant field); one thread list component; one AccountsView; delete ~3500 dead lines; adaptive layout (clock gets guaranteed 340pt); one token set per surface (chat keeps its light early-2000s look BY DESIGN — three visual languages is the charm, make it deliberate not accidental); investigate source-tree mutation ("TaskBoardView 2.swift" appeared/vanished while app running).
