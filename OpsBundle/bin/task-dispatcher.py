#!/usr/bin/env python3
"""
Task Dispatcher — the mechanical backbone of the NDAI agent board.

Runs every 5 minutes via crontab. Handles all TASK_BOARD.md mutations so
agents never have to edit a 100KB+ markdown file (which they fail at).

Responsibilities:
1. Move Ready → In Progress for agents whose cron window just fired
2. Ingest agent output files (small JSON) and apply status changes
3. Keep TASK_BOARD.md as the single source of truth

Agent output format (ops/agent-output/{agent}.json):
{
  "agent": "r2d2",
  "timestamp": "2026-03-17T20:10:00",
  "updates": [
    {"task_id": "TASK-031", "status": "Review", "notes": "Commit 9bd5627, build clean"},
    {"task_id": "TASK-005", "status": "Blocked", "blockers": "Need Andrew to decide billing model"}
  ]
}
"""

import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path

WORKSPACE = Path.home() / ".openclaw" / "workspace"
BOARD_PATH = WORKSPACE / "ops" / "TASK_BOARD.md"
OUTPUT_DIR = WORKSPACE / "ops" / "agent-output"
LOG_PATH = WORKSPACE / "ops" / "dispatcher.log"

# Agent cron schedule — minute of the hour each agent fires
AGENT_SCHEDULE = {
    "Thrawn": 0,
    "R2-D2": 10,
    "C-3PO": 20,
    "Qui-Gon": 30,
    "Lando": 40,
    "Boba": 50,
}

# How many minutes after an agent's cron to auto-move Ready → In Progress
PICKUP_WINDOW_MINUTES = 8


def log(msg: str):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line)
    try:
        with open(LOG_PATH, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass


def parse_tasks(content: str) -> list[dict]:
    """Parse TASK_BOARD.md into a list of task dicts with their raw text positions."""
    tasks = []
    # Match ### TASK-NNN blocks
    pattern = re.compile(r'^### (TASK-\d+)', re.MULTILINE)
    matches = list(pattern.finditer(content))

    for i, match in enumerate(matches):
        start = match.start()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(content)
        block = content[start:end]
        task_id = match.group(1)

        # Skip template
        if task_id == "TASK-000":
            continue

        # Extract fields
        def extract(field: str) -> str:
            m = re.search(rf'^- {field}:\s*(.*)', block, re.MULTILINE)
            return m.group(1).strip() if m else ""

        tasks.append({
            "id": task_id,
            "title": extract("Title"),
            "owner": extract("Owner"),
            "status": extract("Status"),
            "blockers": extract("Blockers"),
            "notes": extract("Notes"),
            "next_step": extract("Next step"),
            "start": start,
            "end": end,
            "block": block,
        })

    return tasks


def update_field(block: str, field: str, new_value: str) -> str:
    """Update a single field in a task block."""
    pattern = re.compile(rf'^(- {field}:)\s*.*', re.MULTILINE)
    if pattern.search(block):
        return pattern.sub(rf'\1 {new_value}', block)
    return block


def apply_status_change(content: str, task_id: str, new_status: str,
                        extra_fields: dict | None = None) -> str:
    """Change a task's status (and optionally other fields) in the raw markdown."""
    tasks = parse_tasks(content)
    for task in tasks:
        if task["id"] == task_id:
            block = task["block"]
            new_block = update_field(block, "Status", new_status)
            if extra_fields:
                for field, value in extra_fields.items():
                    new_block = update_field(new_block, field, value)
            content = content[:task["start"]] + new_block + content[task["end"]:]
            return content
    return content


def auto_pickup(content: str) -> str:
    """Move Ready → In Progress for agents in their pickup window."""
    now = datetime.now()
    current_minute = now.minute
    tasks = parse_tasks(content)
    changed = False

    for task in tasks:
        if task["status"] != "Ready":
            continue
        owner = task["owner"]
        if owner not in AGENT_SCHEDULE:
            continue

        agent_minute = AGENT_SCHEDULE[owner]
        # Check if we're within the pickup window after the agent's cron fired
        minutes_since = (current_minute - agent_minute) % 60
        if minutes_since <= PICKUP_WINDOW_MINUTES:
            log(f"PICKUP: {task['id']} ({task['title']}) — {owner} Ready → In Progress")
            content = apply_status_change(content, task["id"], "In Progress")
            changed = True

    if not changed:
        log("No Ready tasks to pick up this cycle.")
    return content


def next_task_id(content: str) -> str:
    """Find the highest TASK-NNN on the board and return TASK-(N+1)."""
    ids = [int(m.group(1)) for m in re.finditer(r'TASK-(\d+)', content)]
    next_num = max(ids) + 1 if ids else 1
    return f"TASK-{next_num:03d}"


def append_new_task(content: str, task_id: str, title: str, owner: str,
                    status: str, notes: str = "", blockers: str = "None",
                    priority: str = "Medium") -> str:
    """Append a brand new task block to TASK_BOARD.md."""
    now = datetime.now().strftime("%Y-%m-%d")
    block = f"""
### {task_id}
- Title: {title}
- Owner: {owner}
- Collaborators:
- Status: {status}
- Priority: {priority}
- Project:
- Requested by: Thrawn (initiative)
- Created: {now}
- Due:
- Inputs:
- Deliverable:
- Brain path:
- Notes: {notes}
- Review status:
- Blockers: {blockers}
- Next step:
"""
    content = content.rstrip() + "\n" + block
    return content


def ingest_agent_outputs(content: str) -> str:
    """Read agent output JSON files and apply their updates to the board."""
    if not OUTPUT_DIR.exists():
        return content

    for output_file in OUTPUT_DIR.glob("*.json"):
        try:
            with open(output_file) as f:
                data = json.load(f)

            agent = data.get("agent", output_file.stem)
            updates = data.get("updates", [])

            for update in updates:
                task_id = update.get("task_id", "")
                new_status = update.get("status", "")
                if not task_id or not new_status:
                    continue

                # Handle NEW task creation
                if task_id.upper() == "NEW":
                    title = update.get("title", "Untitled task")
                    owner = update.get("owner", "Thrawn")
                    notes = update.get("notes", "")
                    blockers = update.get("blockers", "None")
                    priority = update.get("priority", "Medium")
                    real_id = next_task_id(content)
                    log(f"CREATE: {agent} → {real_id} '{title}' ({owner}) → {new_status}")
                    content = append_new_task(content, real_id, title, owner,
                                             new_status, notes, blockers, priority)
                    continue

                extra = {}
                if "notes" in update:
                    extra["Notes"] = update["notes"]
                if "blockers" in update:
                    extra["Blockers"] = update["blockers"]
                if "next_step" in update:
                    extra["Next step"] = update["next_step"]

                log(f"INGEST: {agent} → {task_id} Status → {new_status}")
                content = apply_status_change(content, task_id, new_status, extra if extra else None)

            # Remove processed file
            output_file.unlink()
            log(f"Processed and removed {output_file.name}")

        except Exception as e:
            log(f"ERROR processing {output_file.name}: {e}")

    return content


def run():
    log("=== Dispatcher cycle starting ===")

    if not BOARD_PATH.exists():
        log(f"ERROR: {BOARD_PATH} not found")
        sys.exit(1)

    content = BOARD_PATH.read_text()
    original = content

    # Step 1: Auto-pickup Ready → In Progress
    content = auto_pickup(content)

    # Step 2: Ingest agent output files
    content = ingest_agent_outputs(content)

    # Write back if changed
    if content != original:
        # Atomic write
        tmp = BOARD_PATH.with_suffix(".tmp")
        tmp.write_text(content)
        tmp.rename(BOARD_PATH)
        log("TASK_BOARD.md updated successfully.")
    else:
        log("No changes to write.")

    log("=== Dispatcher cycle complete ===")


if __name__ == "__main__":
    run()
