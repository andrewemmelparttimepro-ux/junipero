# Thrawn Contributor Handoff

## Product Shape

Thrawn V2 is a native SwiftUI command center for board-driven agent work. The app should feel operational and proof-oriented, not like a generic chat wrapper.

## Active Surface

- Flow Board: source of truth for work state.
- Agents rail: five V2 agents only.
- Briefings: daily context and review artifacts.
- Deliverables: human-readable HTML-first packages.
- Command: direct Thrawn interaction.

## Provider Contract

The canonical interactive route is the authenticated Codex CLI app-server. Always discover the current model catalog with `model/list`; never replace this with a fixed model slug or copied ChatGPT credential. Persist Thrawn session metadata and provider thread ids only. Command/file approvals must remain visible and actionable in Thrawn.

The provider boundary lives in `AgentRuntime.swift`. Codex protocol translation lives in `CodexAppServerProvider.swift`. Keep API, OpenClaw, xAI, and Ollama clients as explicit fallback adapters for unattended or provider-specific work; normal routes must surface a Codex setup/runtime failure instead of silently changing harnesses.

## Reliability Contracts

- Preserve stale-run cleanup, watchdogs, wrapped-update dispatcher recovery, and Done-with-deliverable enforcement.
- Preserve provider-native thread continuity, turn cancellation, streamed event translation, and fail-closed approval handling.
- Treat Flow Board status as behavior, not decoration.
- Do not add old provider or retired-agent names back into UI, scheduler, specs, docs, or runtime defaults.

## Build And Verification

```bash
python3 -m py_compile OpsBundle/bin/*.py
swift build
./build-app.sh
python3 scripts/thrawn-live-purge-audit.py
```

Before release, also verify `codex login status`, live model discovery, one ephemeral app-server turn, and an approval request/decision round trip.

## Deliverable Rule

Any externally useful report or proof package should include an `index.html` at the package root and register that HTML in the deliverables manifest. Use PDFs as premium companion assets, not the only path.
