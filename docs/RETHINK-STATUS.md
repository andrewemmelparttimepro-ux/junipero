# Thrawn Rethink — Implementation Status (2026-08-08)

Implements THRAWN-RETHINK-PLAN.md. Read this before touching the Brain, watchdog, or dispatcher.

## Live infrastructure

- **NDAI Brain**: Supabase project `ndai-brain` (ref `hgmaiotwhmegkzhlauyd`, us-east-1, $10/mo).
  Schema per plan §4.1: orgs, members, products, agents, agent_events, credential_status,
  tasks (+ done-requires-evidence trigger), task_events, deliverables, approvals, escalations.
  All RLS. History imported: board TASK-219…234 (incl. recovered 224/231), TASK-061,
  6 voided + 3 open approvals, proof verdicts Aug 3–8.
- **Ingest endpoint**: edge function `ingest` (verify_jwt off, token-gated via `x-brain-token`).
  Ops: table insert/upsert (whitelist), `task_update`, `task_comment`, `deliverable_add`,
  `task_done` (atomic evidence+move). Token + URL in `~/Library/Application Support/Thrawn/brain.json`
  (mode 600; also carries Resend key for watchdog email).
- **Watchdog**: `Watchdog/thrawn_watchdog.py` (repo) installed at App Support `bin/`,
  launchd `com.thrawn.watchdog` every 5 min. Checks fleet liveness + credential files +
  today's auth errors; writes heartbeat/credential_status to Brain; pages via macOS
  notification + Resend email (from notifications@objectivetracker.net) with 6h re-page damper.
  State: App Support `watchdog-state.json`.
- **Fleet → Brain**: `BrainClient.swift`. FlightRecorder heartbeat/error mirrors,
  AgentRuntime credential-status mirrors, TaskDispatcher board dual-write
  (Markdown stays authoritative until parity proven — then flip per task list).
- **AutonomyPolicy.swift**: single enforcement point. ExecutionService.run() blocks
  shell for prepare-tier agents (dwight); GrokCLIProvider permission-mode derives from it.
  Overrides in App Support `agent-autonomy.json`.

## Root causes found & fixed

- **Double proof batches** (TASK-233): launchd `com.thrawn.product-sentinel-proof` AND the
  OpenClaw gateway daemon (`ai.openclaw.gateway`, umask 077, cron `10 8,13,18 * * *`) both
  fired the runner. OpenClaw booted out + plist/cron archived in
  `Thrawn Archives/pre-rethink-20260808-174529/`. git-status(128) during collisions = index.lock races.
- **Solo launchd batch git failures**: launchd context lacks FDA → getcwd() EPERM inside
  Desktop/Documents → git exits 128. Runner now classifies that signature as
  SKIPPED/WARN; real check resumes when `/bin/bash` gets Full Disk Access (Andrew).
- **Launch-time data loss**: ThrawnV2ResetService now archives App Support before any
  version-bump migration and quarantines (never deletes) launch-time "unknown" files →
  `Thrawn Archives/launch-quarantine-<date>/`.
- **Dead cron jobs**: morning/evening handoff launchd jobs removed (scripts were deleted Aug 1).

## Charters (v2, both workspace/agents/ and OpsBundle/agents/)

No Silent Runs (verdict per wake), Business Output Is the Measure (>60% business-facing),
Thrawn forensics budget (1 in 4), Dwight structural sweep results, Steven re-aim.

## Phase 3 — Federation (live 2026-08-08 evening)

- Each product Supabase carries a `brain_sync` schema: `brain_sync.push()` (security definer)
  reads new `agent_messages` (+ `agent_deliverables` where present) past a watermark and
  POSTs them to the Brain ingest via pg_net; pg_cron `brain-sync-push` runs it every 10 min.
  No product-app code changed, no redeploys. Caveat: pg_net is fire-and-forget — watermark
  advances optimistically; product DB stays the source of truth.
- Backfilled: ARI 372 messages + 53 deliverables (spas-360), OTTO 3 messages (sandpro-omp),
  SPOT 4 messages (hit-zero). Sync installed in kxyqgkimcdxvfkceoixs, whgrkfhuzgwmbelocnhq,
  ldhzkdqznccfgpdvqyfk.
- **Unified Feed** section in the app (`ConsoleSection.feed` → `UnifiedFeedView`), reading the
  Brain's `feed` action (token-gated, newest 120 events, 30s auto-refresh): local fleet runs,
  deployed agents, proof verdicts, watchdog pages — one timeline.
- FDA for /bin/bash granted by Andrew 2026-08-08 evening — git checks in launchd proofs
  went PASS mid-batch (cyclops/sandpro-omp/spas-360 confirmed).

## Pending (task list)

- Phase 2 flip: Markdown board → read-only export after parity window.
- Kill list round 2 (after wizard-session merge): ProviderRouter, OpenClaw/Ollama Swift
  wiring, HandoffStore. TaskBoardView.swift is NOT orphaned (defines ParsedTask/TaskBoardStore).
- Hit Zero: real regression — test suite FAIL(1), dev server exit 1 (verdict
  hit-zero-20260808-182257). Plus TASK-224 four deploy decisions (Brain approval APPROVAL-HZ-DEPLOY).
- Re-auth: codex per profile (in-flight), `claude` login for thrawn profile, `grok login` for steven.
- Phase 3 federation (ARI → Brain), Phase 5 office-Mac headless split.
