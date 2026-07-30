# TOOLS.md

## Active Runtime

- Model route: OpenClaw subscription GPT-5.4 xhigh for Thrawn, Samwell Tarly, Sir Davos, and Dwight; xAI Grok 4.5 for Steven.
- Board updates: write JSON arrays to `workspace/ops/pending-updates/`.
- Deliverables: publish user-facing HTML under `workspace/deliverables/<ticket>/<date>/<slug>/index.html`.
- Logs: inspect `workspace/logs/`.

## Browser Routing

The stable has its OWN browser. Use it. Syntax is
`openclaw browser --browser-profile <name> <command>`.

**`openclaw` — the agent's own browser. This is the default and the first choice.**
- Persistent profile at `~/.openclaw/browser/openclaw/user-data`, CDP on port 18800.
- Start it with `openclaw browser start` if `openclaw browser status` shows `running: false`.
- Its logins persist across restarts. Where a service is already signed in here, authenticated work needs no human at all.
- It is a separate identity from Andrew's personal Chrome by design. Never assume its account is his.

**`user` — attaching to Andrew's own signed-in Chrome. Conditional.**
- Requires the Chrome MCP bridge to be connected. When it is not, `browser.status` and
  `browser.start` fail with a missing `DevToolsActivePort`, because normal Chrome runs
  without a remote-debugging port. That is a configuration state, not something a retry fixes.
- Do not relaunch, quit, or add debugging flags to Andrew's personal Chrome.

**When a site needs a login the `openclaw` profile does not have:**
1. Try the `openclaw` profile first and capture the exact page it lands on.
2. If it hits a login wall, that is a one-time human step, not a recurring blocker.
   Raise a single approval asking Andrew to sign that service into the agent browser
   (`openclaw browser start`, then he signs in once — the session persists).
3. Record the blocker once with the service name and stop. **Do not re-attempt the same
   browser attach on every heartbeat.** Re-check at most once per day, or when Andrew says
   the sign-in is done. Repeatedly retrying an unchanged configuration blocker is waste,
   not diligence.

**Never** ask for, store, type, or transmit Andrew's passwords, MFA codes, or session
cookies. Signing a service into the agent browser is always his action, performed by him.

## Local Work

Thrawn may run local build, verification, repair, and file operations through the app's full-operation command loop when the work is internal and authorized by the task.
