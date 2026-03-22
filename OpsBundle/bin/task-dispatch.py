#!/usr/bin/env python3
"""
Task Dispatcher — reads agent-updates.json, applies changes to TASK_BOARD.md.
Runs every 5 minutes via crontab. Agents write simple JSON updates instead of
editing markdown directly.

agent-updates.json format:
[
  {
    "action": "move",        // move, create, update, note
    "task_id": "TASK-001",
    "field": "Status",       // which field to change
    "value": "In Progress",  // new value
    "agent": "R2-D2",
    "timestamp": "2026-03-17T22:10:00"
  },
  {
    "action": "create",
    "task_id": "TASK-NEW",   // auto-assigned if "TASK-NEW"
    "title": "Fix the widget",
    "owner": "R2-D2",
    "status": "Ready",
    "priority": "High",
    "notes": "",
    "agent": "Thrawn",
    "timestamp": "2026-03-17T22:00:00"
  }
]
"""

import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path

OPS = Path.home() / ".openclaw" / "workspace" / "ops"
BOARD = OPS / "TASK_BOARD.md"
UPDATES = OPS / "agent-updates.json"
LOG = OPS / "dispatch-log.jsonl"

VALID_STATUSES = {"Inbox", "Ready", "In Progress", "Review", "Blocked", "Done"}

TASK_TEMPLATE = """### {task_id}
- Title: {title}
- Owner: {owner}
- Status: {status}
- Priority: {priority}
- Notes: {notes}
- Blockers: {blockers}
- Next step: {next_step}
"""


def log(msg, level="info"):
    entry = {"ts": datetime.now().isoformat(), "level": level, "msg": msg}
    with open(LOG, "a") as f:
        f.write(json.dumps(entry) + "\n")


def read_board():
    if not BOARD.exists():
        return ""
    return BOARD.read_text()


def write_board(content):
    # Atomic write
    tmp = BOARD.with_suffix(".tmp")
    tmp.write_text(content)
    tmp.rename(BOARD)


def next_task_id(board_text):
    ids = re.findall(r"### TASK-(\d+)", board_text)
    if not ids:
        return "TASK-001"
    max_id = max(int(x) for x in ids)
    return f"TASK-{max_id + 1:03d}"


def apply_move(board_text, update):
    """Change a field value on an existing task."""
    task_id = update["task_id"]
    field = update.get("field", "Status")
    value = update["value"]

    if field == "Status" and value not in VALID_STATUSES:
        log(f"Invalid status '{value}' for {task_id}, skipping", "warn")
        return board_text

    # Find the task block and update the field
    pattern = rf"(### {re.escape(task_id)}\n(?:- .+\n)*?)(- {re.escape(field)}: )(.+)"
    match = re.search(pattern, board_text)
    if match:
        old_val = match.group(3)
        board_text = board_text[:match.start(3)] + value + board_text[match.end(3):]
        log(f"Moved {task_id} {field}: '{old_val}' -> '{value}' (by {update.get('agent', '?')})")
    else:
        log(f"Could not find {task_id}/{field} in board", "warn")

    return board_text


def apply_create(board_text, update):
    """Append a new task to the board."""
    task_id = update.get("task_id", "TASK-NEW")
    if task_id == "TASK-NEW":
        task_id = next_task_id(board_text)

    block = TASK_TEMPLATE.format(
        task_id=task_id,
        title=update.get("title", "Untitled"),
        owner=update.get("owner", "Unassigned"),
        status=update.get("status", "Inbox"),
        priority=update.get("priority", "Medium"),
        notes=update.get("notes", ""),
        blockers=update.get("blockers", ""),
        next_step=update.get("next_step", ""),
    )

    board_text = board_text.rstrip() + "\n\n" + block
    log(f"Created {task_id}: '{update.get('title', '?')}' (by {update.get('agent', '?')})")
    return board_text


def apply_update(board_text, update):
    """Update a specific field (notes, blockers, next_step, etc.)."""
    return apply_move(board_text, update)  # Same logic


def run():
    if not UPDATES.exists():
        return  # Nothing to do

    try:
        raw = UPDATES.read_text().strip()
        if not raw:
            return
        updates = json.loads(raw)
    except (json.JSONDecodeError, Exception) as e:
        log(f"Failed to parse agent-updates.json: {e}", "error")
        return

    if not isinstance(updates, list) or len(updates) == 0:
        return

    board_text = read_board()
    applied = 0

    for update in updates:
        action = update.get("action", "")
        try:
            if action == "move":
                board_text = apply_move(board_text, update)
                applied += 1
            elif action == "create":
                board_text = apply_create(board_text, update)
                applied += 1
            elif action == "update":
                board_text = apply_update(board_text, update)
                applied += 1
            elif action == "note":
                board_text = apply_update(board_text, update)
                applied += 1
            else:
                log(f"Unknown action '{action}', skipping", "warn")
        except Exception as e:
            log(f"Error applying update {update}: {e}", "error")

    if applied > 0:
        write_board(board_text)
        log(f"Applied {applied} updates to TASK_BOARD.md")

    # Clear the updates file after processing
    UPDATES.write_text("[]")


if __name__ == "__main__":
    run()
