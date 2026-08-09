#!/usr/bin/env python3
"""Thrawn Watchdog — tiny, dumb, always-on.

Three jobs, nothing else:
  1. Verify fleet liveness + credential validity from local signals.
  2. Write a heartbeat (and findings) to the NDAI Brain.
  3. Page Andrew (macOS notification + email when configured) when:
       - the fleet has been dark past its expected cadence,
       - a credential is dead,
       - an open escalation sits unacknowledged past the nag interval.

No LLM. No board access. State in one JSON file so it never re-pages the
same incident every two minutes. Every network write is best-effort: the
local page fires even when the Brain is unreachable.

Config: ~/Library/Application Support/Thrawn/brain.json
  { "url": "https://<ref>.supabase.co", "ingest_token": "...",
    "email_to": "optional", "resend_api_key": "optional" }
"""

from __future__ import annotations

import json
import subprocess
import sys
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

HOME = Path.home()
APP = HOME / "Library/Application Support/Thrawn"
WORKSPACE = APP / "workspace"
CONFIG_PATH = APP / "brain.json"
STATE_PATH = APP / "watchdog-state.json"

# The fleet's own cadence: thrawn every 15 min, leads every 3 h. If nothing in
# agent-output has been written for this long while the console claims to be
# running, the fleet is dark. 35 min covers two missed thrawn slots.
FLEET_DARK_AFTER = timedelta(minutes=35)
# When the console is not running at all, that is a paged condition once,
# not every cycle.
ESCALATION_NAG_AFTER = timedelta(minutes=30)
REPAGE_AFTER = timedelta(hours=6)

PROFILES = {
    "thrawn": ["codex", "claude"],
    "archivist": ["codex"],
    "sentinel": ["codex"],
    "dwight": ["codex"],
    "steven": ["grok"],
}


def now() -> datetime:
    return datetime.now(timezone.utc)


def load_json(path: Path, fallback):
    try:
        return json.loads(path.read_text())
    except Exception:
        return fallback


def config() -> dict:
    cfg = load_json(CONFIG_PATH, {})
    if not cfg.get("url") or not cfg.get("ingest_token"):
        print("watchdog: no brain.json config; local-only mode", file=sys.stderr)
    return cfg


def brain_post(cfg: dict, payload: dict) -> bool:
    if not cfg.get("url") or not cfg.get("ingest_token"):
        return False
    req = urllib.request.Request(
        cfg["url"].rstrip("/") + "/functions/v1/ingest",
        data=json.dumps(payload).encode(),
        headers={
            "Content-Type": "application/json",
            "x-brain-token": cfg["ingest_token"],
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return 200 <= resp.status < 300
    except Exception as exc:
        print(f"watchdog: brain write failed: {exc}", file=sys.stderr)
        return False


def notify(title: str, body: str) -> None:
    try:
        subprocess.run(
            ["osascript", "-e",
             f'display notification "{body[:180]}" with title "{title[:60]}" sound name "Sosumi"'],
            timeout=10, capture_output=True,
        )
    except Exception:
        pass


def send_email(cfg: dict, subject: str, body: str) -> bool:
    key, to = cfg.get("resend_api_key"), cfg.get("email_to")
    if not key or not to:
        return False
    req = urllib.request.Request(
        "https://api.resend.com/emails",
        data=json.dumps({
            "from": "Thrawn Watchdog <notifications@objectivetracker.net>",
            "to": [to],
            "subject": subject,
            "text": body,
        }).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}",
                 "User-Agent": "thrawn-watchdog/1.0"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return 200 <= resp.status < 300
    except Exception as exc:
        print(f"watchdog: email failed: {exc}", file=sys.stderr)
        return False


# ── Checks ───────────────────────────────────────────────────────────────────

def fleet_last_activity() -> tuple[datetime | None, str]:
    """Newest write across agent-output files = last completed agent run."""
    newest, which = None, "none"
    out_dir = WORKSPACE / "ops" / "agent-output"
    if out_dir.is_dir():
        for f in out_dir.glob("*.json"):
            ts = datetime.fromtimestamp(f.stat().st_mtime, timezone.utc)
            if newest is None or ts > newest:
                newest, which = ts, f.stem
    return newest, which


def console_running() -> bool:
    try:
        out = subprocess.run(["pgrep", "-f", "Thrawn.app/Contents/MacOS"],
                             capture_output=True, text=True, timeout=10)
        return out.returncode == 0
    except Exception:
        return False


def credential_check() -> dict[str, dict[str, str]]:
    """Cheap, local, no-network credential reads per agent profile."""
    results: dict[str, dict[str, str]] = {}
    for agent, providers in PROFILES.items():
        results[agent] = {}
        base = APP / "subscription-profiles" / agent
        for provider in providers:
            home = base / provider
            state = "unknown"
            if provider == "codex":
                auth = home / "auth.json"
                if not auth.is_file():
                    state = "auth_required"
                else:
                    tokens = load_json(auth, {}).get("tokens") or {}
                    state = "ready" if tokens.get("refresh_token") else "auth_required"
            elif provider == "claude":
                # Claude Code stores credentials in the login keychain, namespaced
                # by CLAUDE_CONFIG_DIR. `claude auth status` is the only honest
                # local probe; a missing/failed CLI reads as unknown, not dead.
                try:
                    out = subprocess.run(
                        ["claude", "auth", "status"],
                        env={**__import__("os").environ, "CLAUDE_CONFIG_DIR": str(home)},
                        capture_output=True, text=True, timeout=20,
                    )
                    state = "ready" if '"loggedIn":true' in out.stdout.replace(" ", "") else "auth_required"
                except Exception:
                    state = "unknown"
            elif provider == "grok":
                auth = home / "auth.json"
                state = "ready" if auth.is_file() and auth.stat().st_size > 2 else "auth_required"
            results[agent][provider] = state
    return results


def today_error_lines() -> list[dict]:
    f = WORKSPACE / "logs" / f"errors-{datetime.now().strftime('%Y-%m-%d')}.jsonl"
    out = []
    if f.is_file():
        for line in f.read_text().splitlines()[-50:]:
            try:
                out.append(json.loads(line))
            except Exception:
                continue
    return out


def auth_errors_today(errors: list[dict]) -> list[str]:
    needles = ("not authenticated", "OAuth", "signed out", "Not logged in", "Not signed in")
    return sorted({e.get("message", "")[:160] for e in errors
                   if any(n.lower() in e.get("message", "").lower() for n in needles)})


# ── Incident memory ─────────────────────────────────────────────────────────

def should_page(state: dict, incident_key: str) -> bool:
    last = state.get("paged", {}).get(incident_key)
    if last is None:
        return True
    try:
        return now() - datetime.fromisoformat(last) > REPAGE_AFTER
    except Exception:
        return True


def mark_paged(state: dict, incident_key: str) -> None:
    state.setdefault("paged", {})[incident_key] = now().isoformat()


def clear_incident(state: dict, incident_key: str) -> None:
    state.get("paged", {}).pop(incident_key, None)


# ── Main ────────────────────────────────────────────────────────────────────

def main() -> int:
    cfg = config()
    state = load_json(STATE_PATH, {})
    findings: list[tuple[str, str, str]] = []  # (severity, key, message)

    last_run, last_agent = fleet_last_activity()
    running = console_running()
    creds = credential_check()
    raw_errors = today_error_lines()
    errors = auth_errors_today(raw_errors)

    # A file-on-disk check cannot see server-side token death (the Aug 2026
    # outage hid exactly there). Overlay today's observed auth failures: an
    # agent that errored on auth today is auth_required regardless of what
    # its local auth file claims.
    for e in raw_errors:
        msg = e.get("message", "").lower()
        if not any(n in msg for n in ("not authenticated", "oauth", "signed out", "not logged in", "not signed in")):
            continue
        source = e.get("source", "")
        agent = source.split(":")[-1] if ":" in source else source
        if agent in creds:
            provider = source.split(":")[0] if source.split(":")[0] in ("codex", "claude", "grok") else None
            for p in ([provider] if provider else list(creds[agent].keys())):
                if p in creds[agent]:
                    creds[agent][p] = "auth_required"

    if last_run is None:
        findings.append(("page", "fleet-no-history", "No agent-output history found at all."))
    else:
        dark_for = now() - last_run
        if running and dark_for > FLEET_DARK_AFTER:
            findings.append(("page", "fleet-dark",
                             f"Console is running but no agent has completed in {int(dark_for.total_seconds()/60)} min "
                             f"(last: {last_agent} at {last_run.isoformat(timespec='minutes')})."))
        elif not running and dark_for > timedelta(hours=6):
            findings.append(("warn", "console-closed",
                             f"Console not running; fleet dark {int(dark_for.total_seconds()/3600)}h."))
        else:
            clear_incident(state, "fleet-dark")

    dead = [f"{agent}/{provider}" for agent, provs in creds.items()
            for provider, s in provs.items() if s == "auth_required"]
    if dead:
        findings.append(("page", "credentials-dead", "Credentials need sign-in: " + ", ".join(dead)))
    else:
        clear_incident(state, "credentials-dead")

    if errors:
        findings.append(("warn", "auth-errors-today", " | ".join(errors)[:400]))

    # Report everything to the Brain (best effort).
    hb = {
        "kind": "watchdog_heartbeat",
        "at": now().isoformat(),
        "console_running": running,
        "last_agent_run": last_run.isoformat() if last_run else None,
        "credential_states": creds,
        "findings": [{"severity": s, "key": k, "message": m} for s, k, m in findings],
    }
    brain_post(cfg, {"table": "agent_events", "rows": [{
        "agent_slug": "watchdog", "actor": "watchdog", "kind": "watchdog",
        "status": "ok" if not findings else findings[0][0], "summary": hb["findings"][0]["message"] if findings else "fleet nominal",
        "detail": hb,
    }]})
    cred_rows = [{"agent_slug": a, "provider": p, "state": s,
                  "detail": "watchdog local check"}
                 for a, provs in creds.items() for p, s in provs.items()]
    brain_post(cfg, {"table": "credential_status", "rows": cred_rows, "upsert": True})

    # Page on pageable findings.
    for severity, key, message in findings:
        if severity != "page" or not should_page(state, key):
            continue
        notify("Thrawn Watchdog", message)
        send_email(cfg, f"[Thrawn Watchdog] {key}", message)
        brain_post(cfg, {"table": "escalations", "rows": [{
            "severity": "page", "source": "watchdog", "title": key, "body": message,
            "delivered_via": ["notification"] + (["email"] if cfg.get("resend_api_key") else []),
            "delivered_at": now().isoformat(),
        }]})
        mark_paged(state, key)

    STATE_PATH.write_text(json.dumps(state, indent=2))
    print(json.dumps({"ok": True, "findings": len(findings), "at": now().isoformat()}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
