# Thrawn Console

Thrawn 2.1 is a native macOS command app led by Thrawn with a four-agent specialist stable.

## Runtime

- Primary route: the signed-in Codex CLI, launched as `codex app-server`.
- Models and supported reasoning levels come from the live `model/list` catalog. Thrawn does not pin the subscription route to a model slug.
- Command threads, specialist chats, and agent heartbeats each map to persisted Codex threads and receive structured streamed tool, file, usage, and approval events.
- Codex owns ChatGPT/API authentication and refreshes its own credentials. Thrawn persists only provider-neutral session metadata and Codex thread ids.
- xAI, OpenAI-compatible, OpenClaw, and Ollama clients remain explicit fallback adapters; they are not silent replacements for the primary route.
- Active owners: Andrew, Thrawn, Samwell Tarly, Sir Davos, Dwight, and Steven.
- Stable: Dwight routes; Samwell owns SandPro OMP; Sir Davos owns Hit Zero; Steven owns Spas 360; Thrawn reviews and leads.
- Future agents require explicit versioned specs, tools, cadence, and review standards.
- Normal operation has no silent Ollama or local fallback.
- Authenticated browser work uses the provider agent's supported Browser/Chrome integration and Andrew's existing signed-in session.

## Provider setup

```bash
codex login
codex login status
```

Thrawn discovers the executable from `THRAWN_CODEX_PATH`, the ChatGPT app bundle, or `PATH`. The native app is the persistent runtime machine and therefore uses the Developer ID/local distribution path rather than a browser-only or Mac App Store sandbox.

## Build

```bash
swift build
./build-app.sh
```

The installer writes `/Applications/Thrawn.app`.
