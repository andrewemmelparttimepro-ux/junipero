# Deployed Intelligence — @ARI in Thrawn

*Design doc, Aug 1 2026. Distilled from Andrew's brain dump: "Can I have the ACTUAL
agents from the boards of places I have intelligence (ARI with SPAS 360 first)…
the power here probably comes from the @ — it's more like you're calling a real
person, that exists elsewhere… maybe it's more like he lives in Thrawn."*

---

## 1. What this actually is

Three sentences, distilled:

**Every business NDAI runs has a deployed agent living inside its app, working
with that business's live data, under that business's guardrails. Thrawn is
Andrew's chair. @ARI in Thrawn summons the real deployed agent — the one the
coworkers use — into that chair, without making a copy of him.**

The test that keeps the design honest: if Andrew asks @ARI something in Thrawn
and a salesperson asks Ari the same thing in SPAS 360 thirty seconds later,
**they are talking to the same colleague** — same memory, same data, same
guardrails, same audit trail. The moment there are two Aris, this failed.

That is what "calling a real person that exists elsewhere" means mechanically:
**one brain, many rooms.** Ari's *home* is SPAS 360 (his memory, his org data,
his approval queues live there). Thrawn is a room he's always reachable in.

## 2. How ARI is actually wired today (read from source, 8/1)

Repo: `~/Desktop/antigravity/spas_360_solo`

| Piece | File | What it does |
|---|---|---|
| Model proxy | `api/chat.ts` | Stateless. Injects rails server-side (client system messages discarded). Provider-agnostic via `AI_PROVIDER` env: anthropic / gemini / openai / glm / meta — all translated to/from the OpenAI wire shape. `handleOpenAICompatible()` takes an arbitrary `baseUrl`. |
| Persona | `api/_lib/system-prompt.ts` + `business_profile` row | Persona is **data, not code** — org row (persona, guardrails, live facts) fetched with the caller's token, RLS-scoped. Same code, different org, different Ari. |
| Server agent runtime | `api/agent/run.ts` | The headless full ARI: owns threads (`agent_threads` / `agent_messages` in Supabase), runs the tool loop server-side (≤6 rounds, ≤16 calls), archives every output to Citadel (`agent_deliverables`), renders PDFs, queues SMS **for human approval** — never sends. Tools bound to the caller's RLS client. |
| Presence | `api/agent/status.ts` | Already an agent card in miniature: `{ok, provider, model, capabilities[], server_time}`. |
| The @ grammar | `src/lib/mentions.ts` | `@[Ari](ari)` summons him **in place** in team chat and deal/customer notes. The mechanic Andrew wants in Thrawn already exists one level down. |
| Second face | `FORWARD_FACE` mode in `api/chat.ts` | The Magic City Home Leisure website chat reaches the same brain with a shared secret, a restricted context envelope, and zero tools. **Precedent: ARI already has two faces and one brain.** |

The architecture is better prepared for this than expected. Two findings do most
of the work:

1. **`api/agent/run.ts` is the @ARI endpoint.** It already is "message in →
   real agent loop with tools, threads, Citadel, approvals → answer out." The
   only thing it lacks is a caller that isn't a human employee in a browser.
2. **Forward Face is the pattern.** A third face — the *operator* face, full
   trust, full tools — is an addition to an existing series, not a new idea.

## 3. The two questions from the brain dump, answered separately

These got asked as one thing but are two independent axes. Keeping them separate
is most of the design.

### Axis A — PRESENCE: where can you reach him? (@ARI in Thrawn)

Thrawn calls **into** SPAS 360. Ari's brain, memory, and data never move.

### Axis B — INTELLIGENCE: whose model account does his brain run on?

*"Can we just run the intelligence through Thrawn?"* — SPAS 360 calls **into**
Thrawn for inference only. Tools, data, rails stay in SPAS 360.

You can ship either without the other. They compose. And critically for the
latency worry — **most of what "control the intelligence inside Thrawn" means
does not require routing tokens through Thrawn at all** (see §5).

## 4. Axis A — @ARI in the stable

### The stable gets a second wing

Thrawn's roster today is **staff officers** — Thrawn, Dwight (router), Samwell
(SandPro), Davos (Hit Zero), Steven (Spas 360 Lead). They advise *about*
businesses from Andrew's side of the desk.

ARI is different in kind: a **field operator** — he's *in* the building, wired
to live org data, able to take real actions under that org's approval rails.
The stable renders him with a `DEPLOYED` badge, live presence from
`api/agent/status.ts` (green = his whole runtime is up, provider + model shown
— real presence, not decoration), and his actual SPAS 360 avatar.

Steven (strategy about Spas 360) and ARI (operator inside Spas 360) coexist,
same as a consultant and a store manager both existing. If that ever feels
redundant, the resolution is Steven's role shrinking — never ARI being
reimplemented Thrawn-side.

### The wire

```
Thrawn @ARI ──HTTPS──▶ spas360solo.vercel.app/api/agent/run
                        { message, thread_id? }        (existing endpoint)
           ◀────────── { thread_id, message, artifact, tool_rounds }
```

- **Identity:** Thrawn gets a real Supabase user in the org — `thrawn@ndai.pro`,
  its own `profiles` row, member of the Spas 360 org. Zero new auth code: RLS
  scopes it exactly like an employee, `requested_by` shows Thrawn honestly in
  Citadel and the SMS audit trail, and it can be revoked like any user. (A
  parallel `ARI_FORWARD_SECRET`-style header would also work but builds a
  second auth system for no gain and makes actions harder to attribute.)
- **Threads:** `agent_threads` in SPAS 360 stays the source of truth — that's
  his memory, at home. Thrawn stores only `(thrawn thread ↔ ari thread_id)` so
  a conversation resumes with full context. @ARI a second time in the same
  Thrawn thread = same `thread_id` = he remembers.
- **Deliverables:** stay in Citadel; the Thrawn reply carries the artifact
  card + link. Approvals (SMS) stay in SPAS 360 where the org's managers are —
  Thrawn is a place to *ask*, never a bypass.
- **Coworkers:** unchanged and already done — they have Ari in their app. The
  spec's "accessed by coworkers via the app I built for them" is satisfied by
  the axis-A direction being *into* the app.

### In-conversation mechanic

The `@[Ari](ari)` grammar from `mentions.ts` lifts straight into Thrawn's
composer: typing `@` offers the stable, deployed agents included. An @ARI
message routes that turn to the wire above; his reply lands in the thread under
his own name/avatar, model + latency footer like any Thrawn reply. It reads
exactly like Slack's version of an agent teammate — because that's the correct
comp (below).

## 5. Axis B — running the intelligence through Thrawn

### The latency answer (the go/no-go question)

Today: Vercel fn → Anthropic. Through Thrawn: Vercel fn → Cloudflare tunnel →
Thrawn gateway on the Mac mini → Anthropic.

- Added cost per model call ≈ tunnel RTT + gateway overhead ≈ **100–250 ms**.
- Model inference dominates at 2–20 s per call. On a multi-tool ARI task
  (3–6 model calls over 15–45 s), the through-Thrawn overhead is **~0.5–1.5 s
  on the whole task — 3–5%. Not meaningful.**
- Where it *would* be meaningful: nothing latency-critical runs here. Forward
  Face (customer-facing, snappy, must survive the Mac being off) **stays
  direct to the provider regardless** — see routing below.

**The real risk is availability, not latency.** The Mac asleep must never mean
Ari is down for the dealership. Reliability is the number 1 priority; the
mitigation is structural:

```
api/chat.ts provider order (per face):
  employee ARI:  thrawn-gateway (connect timeout ~1.5 s) → anthropic direct
  forward face:  anthropic direct, always
```

Fallback is a provider entry, not a code path bolted on — `chat.ts` already
routes by provider and `handleOpenAICompatible()` already accepts any
`baseUrl`. A Thrawn gateway that speaks OpenAI-compatible `/v1/chat/completions`
(Cloudflare tunnel, house pattern proven on Cyclops) plugs in as
`AI_PROVIDER=thrawn` + `THRAWN_BASE_URL` + key, with silent fall-through on
timeout. Config change on the SPAS side, one new branch; the gateway server is
the real (modest) build.

### What routing through Thrawn actually buys

- **One bill, Andrew's models** — deployed agents ride the Claude Max
  subscription / whatever Thrawn's gateway fronts (incl. local Ollama).
- **Total observability** — every deployed-agent conversation across every
  NDAI business streams through one place Andrew already lives in.
- **Instant model control** — swap every deployed agent to a new model from
  Thrawn in one action, no Vercel redeploys.

### What "control the intelligence INSIDE THRAWN" needs even without routing

Split control plane from data plane. Most of the control Andrew wants is
config, not token flow:

- Each app already holds persona/guardrails as **data** (`business_profile`).
  Add the model choice to that pattern — an `agent_config` row (provider,
  model, temperature, budgets) read by `api/chat.ts` per request.
- Thrawn edits those rows. That is a **control room with zero latency added,
  zero dependency on the Mac being awake**: change ARI's model, tighten his
  guardrails, read his status — from Thrawn, while his tokens still flow
  Vercel→Anthropic directly.
- Kill switch, budgets, prompt versions: same row, same console.

**Recommendation: control plane first (immediately, it's nearly free), token
routing second (real but optional win — do it when the gateway exists), keep
Forward Face direct forever.**

## 6. Comps

| Comp | What it validates |
|---|---|
| **Devin in Slack** (Cognition) | The exact feel Andrew described: @Devin in a channel calls a real agent living in its own cloud; it works, reports back with artifacts. Slack = surface, brain = elsewhere. This is @ARI in Thrawn, one-to-one. |
| **Slack Agentforce / agent teammates** | Agents as first-class coworkers: presence dot, profile, DM-able, @-able in threads. Direct UI blueprint for the stable's DEPLOYED wing. |
| **Google A2A protocol** (2025) | The industry name for axis A: **Agent Cards** (discovery/capability manifest — `api/agent/status.ts` is already 80% of one), task lifecycle, agents on different infra collaborating. Adopting the *shape* (card + task endpoint) keeps NDAI aligned with where this is going without buying the whole protocol today. |
| **Microsoft Copilot Studio** | "Build an agent once, publish to many channels (Teams, web, apps)." Validates one-brain-many-rooms as the mainstream architecture; their channels ≈ our faces. |
| **LiteLLM / OpenRouter** | The gateway comp for axis B: one OpenAI-compatible proxy in front of many models with keys, budgets, spend, logging. Thrawn Gateway is a self-hosted LiteLLM with a face — and per-face fallback routing is standard practice there, which is reassuring for the availability design. |
| **MCP** | Considered and set aside for this: MCP models *tools*, not *colleagues*. @ARI is an identity with memory and duties, not a function catalogue. (MCP may still be how ARI's tools are exposed internally someday.) |
| **Forward Face** (in-house) | The strongest comp is already shipped: same brain, second surface, different trust envelope. Thrawn is the third face — the operator face. |

## 7. The generalization — every NDAI deployment

The unlock Andrew named ("this would be what I would do with all of the NDAI
deployed intelligence") is a **contract**, not a pile of integrations. Any NDAI
app that ships intelligence ships three things:

1. **Agent card** — `GET /api/agent/status`: name, org, provider, model,
   capabilities, health. (Spas 360: exists.)
2. **Agent endpoint** — `POST /api/agent/run`: message + thread in, answer +
   artifacts out, tools server-side under org rails. (Spas 360: exists.)
3. **Config row** — provider/model/guardrails as org data, editable by the
   Thrawn service identity. (Spas 360: half exists as `business_profile`.)

Thrawn's stable reads a registry of deployments (OpsBundle — the canonical
config source) and auto-populates the DEPLOYED wing. Hit Zero, UNISS, OMP
agents appear the day their apps implement the trio. Hub-and-spoke doctrine is
preserved: deployed agents never talk to each other; anything cross-business
routes through Thrawn — the hub is always Thrawn.

## 8. Build order

| Phase | What ships | Size |
|---|---|---|
| **1. Presence** | `thrawn@ndai.pro` Supabase identity in the Spas 360 org · DEPLOYED wing in the stable with live status card · @ARI in composer → `api/agent/run` → reply-with-artifacts in thread · thread-id mapping for continuity | The core unlock. Mostly Thrawn-side UI + one HTTP client; SPAS side is a user invite. |
| **2. Control plane** | `agent_config` row read by `api/chat.ts` per request · Thrawn console card on ARI: model/provider picker, guardrail editor, kill switch, spend-so-far | Small. No latency, no Mac dependency. |
| **3. Intelligence through Thrawn** | Thrawn Gateway: OpenAI-compatible endpoint over Cloudflare tunnel fronting Claude Max / Ollama · `AI_PROVIDER=thrawn` with 1.5 s-timeout fallback to direct Anthropic · per-face routing (Forward Face never routes through) | The real build. Do it once for ARI, every future deployment inherits it. |
| **4. Fleet** | The three-piece contract stamped into Hit Zero / UNISS / OMP as their agents come online · registry-driven stable | Repetition of 1–3 per app. |

## 9. Decisions taken (flag if wrong)

- **One brain per business, in the business.** Thrawn visits; it never clones.
- **Thrawn authenticates as a real org user**, not a bypass secret — RLS and
  audit trails do the security work they already do.
- **Approvals never move.** SMS and future writes get approved inside the org
  app by that org's humans, whoever asked.
- **Forward Face never routes through the Mac.** Customer-facing must survive
  Andrew's hardware.
- **Latency verdict:** routing internal ARI through Thrawn costs ~3–5% on real
  tasks — under the "meaningful" bar. The availability risk is handled by
  provider fallback, and the customer face is exempt entirely.


---

## 10. The product ladder (added 8/1 — Agent OS integration)

What exists in reality now, bottom to top:

| Tier | What it is | Who pays | Status |
|---|---|---|---|
| **The deployed agent** (Ari) | Lives inside the SaaS, staff use it daily | Included in the SPAS 360 subscription — it's why the subscription is sticky | Shipped |
| **Agent OS** | The owner's native cockpit: Pulse, Citadel, approvals, Team Activity ledger, and now the **intelligence steering wheel** | The upsell. Owner-seat pricing | Shipped (`~/Desktop/spas360-agent-os`) |
| **Thrawn** | NDAI's meta-console: every deployed agent across every business in one stable | Never sold. NDAI's operating advantage | Phase 1+2 shipped |

**The instance model costs nothing to scale.** "Brandon's instance" is not a
fork — it is the same signed app, and his login makes it his: RLS scopes every
row to his org, `owner_manager` unlocks the steering wheel, the audit ledger
names him. Andrew's parallel copy is the same binary signed in as Andrew.
One build, N owners. The only real blocker to handing Brandon the app is
distribution: it is signed with the local NDAI identity today, and a clean
install on an unrelated Mac needs Developer ID + notarization (~$99/yr Apple
program, one afternoon of setup — worth doing once, it covers every future
Agent OS).

**Cohesion is one row.** Thrawn's INTELLIGENCE popover, Agent OS's card, and
the server all read/write `agent_config`. Realtime pushes changes to every
open surface in ~1s (verified: SQL flip → Brandon-view updated in <10s).
Agent OS changes additionally land in the Team Activity ledger under the
owner's own name; changes from anywhere record `updated_by`.

**Pricing suggestions** (opinions, not decisions):
- **Agent OS owner seat: $99–149/mo** (or ~$1,200/yr). Anchor it against one
  saved deal — a single $8–12k hot tub sale a year pays for it several times
  over. The audit ledger alone justifies it for a two-owner store.
- **Intelligence tiers as merchandising.** The picker is a natural upsell
  surface: a *standard mind* included (GLM / Gemini), *premium minds*
  (Grok, Claude) as +$29–49/mo line items. The greyed-out "Claude Sonnet 5 —
  coming soon" entry is literally an in-app teaser today.
- **At fleet scale, move inference billing per-tenant.** Today Ari runs on
  NDAI's xAI key — fine for one org, a margin leak and a blast-radius risk at
  ten. The `agent_config` row is where a per-org key reference (or a metered
  allowance) slots in later without touching any UI.

**What "completely comprehensive" has turned out to mean, concretely:** every
surface reads the same row (no state forks) · every control is role-gated by
RLS, not by UI promises · every change is attributed and auditable · every
failure path says something calm instead of erroring (paused message, env
fallback) · and the owner can see, steer, and stop their agent without asking
NDAI. That list is the checklist for stamping the next deployment.
