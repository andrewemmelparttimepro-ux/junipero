# Thrawn User Guide

## What Thrawn Does

Thrawn is a macOS work command center. It keeps a visible Flow Board, routes work to a small team of durable agents, requires proof for completion, and publishes human-readable deliverables.

## Install

1. Build or obtain `Thrawn.app`.
2. Move it to `/Applications`.
3. Open `Thrawn.app`.
4. Grant file access only for folders that Thrawn needs to inspect for assigned work.

## Providers

The active Thrawn 2.1 provider stack is:

- Codex CLI/app-server for Command, specialist chats, and normal scheduled agent work.
- The model and reasoning selector is populated from the models currently available to the signed-in Codex account.
- Existing API providers remain explicit fallback routes for unattended or provider-specific work.
- No silent Ollama or local fallback in normal work.

Thrawn does not store a ChatGPT password, access token, or copied subscription credential. Sign in through the provider:

```bash
codex login
```

Return to Thrawn Setup and select refresh. The setup screen will show the authentication mode, plan, executable, live model count, selected model, and supported reasoning levels.

## Browser Sessions

- Login-gated work should use the Browser or Chrome integration exposed to the provider agent and Andrew's signed-in session.
- If authenticated access fails, verify the signed-in browser integration is connected before signing in again or blaming the product route.

## Sessions and Approvals

- Each Thrawn conversation or durable agent has a stable local session key mapped to a provider thread id.
- Codex retains the actual conversation/thread state; Thrawn retains only the mapping needed to resume it.
- Command, file-change, and permission requests appear in Thrawn's Approvals screen.
- Approve once, allow for the current provider session, or deny. Unknown approval methods fail closed.

## Flow Board

The Flow Board is the operating core:

- Inbox: raw work that needs shaping.
- Ready: work with a clear next action.
- In Progress: work currently owned by an agent or human.
- Review: work waiting for proof or judgment.
- Blocked: work needing a decision, missing access, or unavailable input.
- Done: work with a human-readable deliverable or evidence pointer.

## Deliverables

Prefer `index.html` as the primary human-facing deliverable. PDFs and supporting assets can sit beside it, but the app should always give the user something easy to open and read.

## Troubleshooting

- If an agent appears stuck, relaunch Thrawn; startup recovery resets stale working states.
- If Codex is unavailable, run `codex login status`, then refresh the Provider Agent Runtime card.
- If a task is Done without a deliverable, move it back for review.
- If a route label looks wrong, refresh the live model catalog and inspect the agent spec before running proof.
