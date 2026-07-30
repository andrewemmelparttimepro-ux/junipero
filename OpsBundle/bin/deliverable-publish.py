#!/usr/bin/env python3
"""Publish Thrawn deliverables as human-readable HTML.

The runtime contract is intentionally simple:

workspace/deliverables/<ticket>/<yyyy-mm-dd>/<slug>/index.html
workspace/deliverables/<ticket>/<yyyy-mm-dd>/<slug>/assets/

Markdown, JSON, screenshots, and raw proof files may still exist as source
material, but the manifest should point humans to index.html.
"""

from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import re
import shutil
from pathlib import Path
from typing import Any


HOME = Path.home()
THRAWN_ROOT = HOME / "Library" / "Application Support" / "Thrawn"
WORKSPACE = THRAWN_ROOT / "workspace"
DELIVERABLE_ROOT = WORKSPACE / "deliverables"
MANIFEST_PATH = DELIVERABLE_ROOT / "manifest.json"
TASK_BOARD_PATH = WORKSPACE / "ops" / "TASK_BOARD.md"


def now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def read_json(path: Path, default: Any) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def slugify(value: str, fallback: str = "deliverable") -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return slug[:80] or fallback


def first_string(item: dict[str, Any], *keys: str) -> str:
    for key in keys:
        value = item.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def manifest_items(raw: Any) -> list[dict[str, Any]]:
    if isinstance(raw, list):
        return [item for item in raw if isinstance(item, dict)]
    if isinstance(raw, dict):
        items = raw.get("deliverables", [])
        if isinstance(items, list):
            return [item for item in items if isinstance(item, dict)]
    return []


def resolve_path(value: str) -> Path:
    value = value.strip()
    if not value:
        return Path()
    if value.startswith("~/"):
        return HOME / value[2:]
    path = Path(value)
    if path.is_absolute():
        if not path.exists():
            try:
                rel = path.relative_to(THRAWN_ROOT)
                repaired = WORKSPACE / rel
                if rel.parts[:1] != ("workspace",):
                    return repaired
            except Exception:
                pass
        return path
    if value.startswith("workspace/"):
        return THRAWN_ROOT / value
    return WORKSPACE / value


def workspace_path(path: Path) -> str:
    try:
        return "workspace/" + path.resolve().relative_to(WORKSPACE.resolve()).as_posix()
    except Exception:
        return str(path)


def path_with_trailing_slash(path: Path) -> str:
    value = workspace_path(path)
    return value if value.endswith("/") else value + "/"


def date_from_item(item: dict[str, Any], source: Path) -> str:
    for raw in [
        source.as_posix(),
        first_string(item, "createdAt", "created_at", "timestamp", "updatedAt", "updated_at"),
    ]:
        match = re.search(r"\d{4}-\d{2}-\d{2}", raw or "")
        if match:
            return match.group(0)
    return dt.datetime.now().astimezone().date().isoformat()


def ticket_from_item(item: dict[str, Any], source: Path) -> str:
    explicit = first_string(item, "ticketId", "ticket_id", "taskId", "task_id")
    if explicit:
        return explicit.upper()
    match = re.search(r"task[-_ ]?(\d+)", source.as_posix(), flags=re.IGNORECASE)
    if match:
        return f"TASK-{int(match.group(1)):03d}"
    return "UNTICKETED"


def markdown_title(path: Path) -> str:
    try:
        for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
            if line.startswith("#"):
                return line.lstrip("#").strip()
    except Exception:
        pass
    return ""


def title_from_item(item: dict[str, Any], source: Path, ticket: str) -> str:
    phase = first_string(item, "phase")
    item_date = date_from_item(item, source)
    if ticket == "DAILY-CONTEXT":
        phase_title = phase.title() if phase else "Daily"
        return f"{phase_title} Desk Board - {item_date}"
    if first_string(item, "type", "legacyType") == "proof-synthesis" or "/proofs/" in source.as_posix():
        return f"Proof Synthesis - {item_date}"

    title = first_string(item, "title")
    if title:
        return title
    if source.is_file() and source.suffix.lower() in {".md", ".txt"}:
        title = markdown_title(source)
        if title:
            return title
    description = first_string(item, "description", "summary")
    if description:
        words = description.split()
        return " ".join(words[:14]) + ("..." if len(words) > 14 else "")
    kind = first_string(item, "type", "kind") or source.stem or "deliverable"
    if phase:
        kind = f"{phase} {kind}"
    return f"{ticket} {kind}".strip()


def inline_markup(value: str) -> str:
    escaped = html.escape(value)
    escaped = re.sub(r"`([^`]+)`", r"<code>\1</code>", escaped)
    escaped = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", escaped)
    escaped = re.sub(
        r"(https?://[^\s<]+)",
        lambda m: f'<a href="{m.group(1)}">{m.group(1)}</a>',
        escaped,
    )
    return escaped


def markdown_to_html(text: str) -> str:
    parts: list[str] = []
    list_mode = ""

    def close_list() -> None:
        nonlocal list_mode
        if list_mode:
            parts.append(f"</{list_mode}>")
            list_mode = ""

    for raw_line in text.splitlines():
        line = raw_line.rstrip()
        stripped = line.strip()
        if not stripped:
            close_list()
            continue
        if stripped.startswith("### "):
            close_list()
            parts.append(f"<h3>{inline_markup(stripped[4:])}</h3>")
        elif stripped.startswith("## "):
            close_list()
            parts.append(f"<h2>{inline_markup(stripped[3:])}</h2>")
        elif stripped.startswith("# "):
            close_list()
            parts.append(f"<h1>{inline_markup(stripped[2:])}</h1>")
        elif stripped.startswith("- "):
            if list_mode != "ul":
                close_list()
                list_mode = "ul"
                parts.append("<ul>")
            parts.append(f"<li>{inline_markup(stripped[2:])}</li>")
        elif re.match(r"\d+\.\s+", stripped):
            if list_mode != "ol":
                close_list()
                list_mode = "ol"
                parts.append("<ol>")
            numbered_text = re.sub(r"^\d+\.\s+", "", stripped)
            parts.append(f"<li>{inline_markup(numbered_text)}</li>")
        else:
            close_list()
            parts.append(f"<p>{inline_markup(stripped)}</p>")

    close_list()
    return "\n".join(parts)


def html_shell(title: str, body: str, summary: str = "", source_links: list[str] | None = None) -> str:
    source_links = source_links or []
    links = "".join(f"<li>{inline_markup(link)}</li>" for link in source_links)
    sources = f"<section><h2>Source Material</h2><ul>{links}</ul></section>" if links else ""
    summary_block = f"<p class=\"summary\">{inline_markup(summary)}</p>" if summary else ""
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<style>
:root {{
  color-scheme: light dark;
  --paper: #f7f4ed;
  --ink: #191d24;
  --muted: #5c6470;
  --line: #d9dee7;
  --accent: #3c79d8;
  --panel: #ffffff;
}}
@media (prefers-color-scheme: dark) {{
  :root {{ --paper: #071016; --ink: #f2f6fb; --muted: #a5afbd; --line: #253445; --panel: #101922; }}
}}
* {{ box-sizing: border-box; }}
body {{ margin: 0; background: var(--paper); color: var(--ink); font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; line-height: 1.55; }}
main {{ max-width: 980px; margin: 0 auto; padding: 40px 22px 64px; }}
header {{ border-bottom: 1px solid var(--line); margin-bottom: 28px; padding-bottom: 18px; }}
h1 {{ margin: 0 0 10px; font-size: clamp(30px, 5vw, 56px); line-height: 1.02; letter-spacing: 0; }}
h2 {{ margin-top: 30px; border-top: 1px solid var(--line); padding-top: 22px; font-size: 22px; }}
h3 {{ margin-top: 20px; font-size: 17px; color: var(--accent); }}
p, li {{ font-size: 16px; }}
.summary {{ color: var(--muted); font-size: 18px; max-width: 820px; }}
section {{ background: color-mix(in srgb, var(--panel) 82%, transparent); border: 1px solid var(--line); border-radius: 8px; padding: 18px 22px; margin-top: 22px; }}
img {{ display: block; max-width: 100%; height: auto; border-radius: 8px; border: 1px solid var(--line); }}
a {{ color: var(--accent); }}
code {{ background: color-mix(in srgb, var(--line) 45%, transparent); padding: 1px 5px; border-radius: 5px; }}
pre {{ overflow: auto; background: color-mix(in srgb, var(--line) 35%, transparent); padding: 16px; border-radius: 8px; font-size: 13px; line-height: 1.45; }}
</style>
</head>
<body>
<main>
<header>
<h1>{html.escape(title)}</h1>
{summary_block}
</header>
{body}
{sources}
</main>
</body>
</html>
"""


def copy_if_exists(source: Path, dest: Path) -> bool:
    if not source.exists():
        return False
    dest.parent.mkdir(parents=True, exist_ok=True)
    if source.resolve() == dest.resolve():
        return True
    shutil.copy2(source, dest)
    return True


def render_from_file(source: Path, title: str, summary: str, out_dir: Path) -> tuple[str, str]:
    suffix = source.suffix.lower()
    if suffix in {".html", ".htm"}:
        text = source.read_text(encoding="utf-8", errors="ignore")
        return text, ""
    if suffix in {".md", ".txt"}:
        text = source.read_text(encoding="utf-8", errors="ignore")
        return html_shell(title, markdown_to_html(text), summary, [workspace_path(source)]), ""
    if suffix == ".json":
        raw = source.read_text(encoding="utf-8", errors="ignore")
        try:
            pretty = json.dumps(json.loads(raw), indent=2, sort_keys=True)
        except Exception:
            pretty = raw
        body = f"<section><h2>JSON Source</h2><pre>{html.escape(pretty)}</pre></section>"
        return html_shell(title, body, summary, [workspace_path(source)]), ""
    if suffix in {".png", ".jpg", ".jpeg", ".gif", ".webp", ".heic"}:
        asset = out_dir / "assets" / source.name
        copy_if_exists(source, asset)
        body = f'<section><img src="assets/{html.escape(source.name)}" alt="{html.escape(title)}"></section>'
        return html_shell(title, body, summary, [workspace_path(source)]), workspace_path(asset)
    body = f"<section><p>{inline_markup(source.name)} is available in the source material.</p></section>"
    return html_shell(title, body, summary, [workspace_path(source)]), ""


def render_from_directory(source: Path, title: str, summary: str, out_dir: Path) -> tuple[str, str]:
    pieces: list[str] = []
    source_links: list[str] = []
    thumbnail = ""

    image = source / "visual-board.png"
    if image.exists():
        asset = out_dir / "assets" / image.name
        copy_if_exists(image, asset)
        thumbnail = workspace_path(asset)
        pieces.append(f'<section><img src="assets/{html.escape(image.name)}" alt="{html.escape(title)} visual board"></section>')
        source_links.append(workspace_path(image))

    for name in ["report.md", "board.md", "review-request.md"]:
        candidate = source / name
        if candidate.exists():
            text = candidate.read_text(encoding="utf-8", errors="ignore")
            pieces.append(f"<section>{markdown_to_html(text)}</section>")
            source_links.append(workspace_path(candidate))

    visual_html = source / "visual-board.html"
    if visual_html.exists():
        asset = out_dir / "assets" / visual_html.name
        copy_if_exists(visual_html, asset)
        pieces.append(f'<section><p><a href="assets/{html.escape(visual_html.name)}">Open original visual board HTML</a></p></section>')
        source_links.append(workspace_path(visual_html))

    if not pieces:
        files = sorted([p.name for p in source.iterdir() if p.is_file()]) if source.exists() else []
        file_list = "".join(f"<li>{html.escape(name)}</li>" for name in files) or "<li>Source folder is missing or empty.</li>"
        pieces.append(f"<section><h2>Available Files</h2><ul>{file_list}</ul></section>")
        if source.exists():
            source_links.append(workspace_path(source))

    return html_shell(title, "\n".join(pieces), summary, source_links), thumbnail


def proof_run_alternates(source: Path) -> list[Path]:
    match = re.search(r"/proofs/(\d{4}-\d{2}-\d{2})/([^/]+)", source.as_posix())
    if not match:
        return []
    proof_date, run_id = match.groups()
    proof_root = WORKSPACE / "proofs"
    if not proof_root.exists():
        return []
    return sorted(path for path in proof_root.glob(f"*/{proof_date}/{run_id}") if path.is_dir())


def render_from_proof_run(sources: list[Path], title: str, summary: str) -> str:
    cards: list[str] = []
    links: list[str] = []
    for source in sources:
        proof_json = source / "proof.json"
        product = source.parts[-3] if len(source.parts) >= 3 else source.parent.name
        status = "available"
        note = ""
        if proof_json.exists():
            data = read_json(proof_json, {})
            if isinstance(data, dict):
                status = str(data.get("status") or data.get("result") or status)
                note = str(data.get("summary") or data.get("verdict") or data.get("notes") or "")
        links.append(workspace_path(proof_json if proof_json.exists() else source))
        cards.append(
            "<section>"
            f"<h2>{html.escape(product.replace('-', ' ').title())}</h2>"
            f"<p>Status: <strong>{inline_markup(status)}</strong></p>"
            f"{'<p>' + inline_markup(note) + '</p>' if note else ''}"
            f"<p><a href=\"{html.escape(workspace_path(proof_json if proof_json.exists() else source))}\">Open proof source</a></p>"
            "</section>"
        )
    body = "\n".join(cards) or "<section><p>No proof sources were found for this run.</p></section>"
    return html_shell(title, body, summary, links)


def canonical_entry(item: dict[str, Any], source: Path) -> dict[str, Any]:
    ticket = ticket_from_item(item, source)
    date = date_from_item(item, source)
    title = title_from_item(item, source, ticket)
    phase = first_string(item, "phase")
    slug_base = f"{phase}-desk-board" if ticket == "DWIGHT-DAILY-CONTEXT" and phase else title
    out_dir = DELIVERABLE_ROOT / ticket / date / slugify(slug_base)
    out_dir.mkdir(parents=True, exist_ok=True)

    summary = first_string(item, "summary", "description")
    if source.exists() and source.is_dir():
        rendered, thumbnail = render_from_directory(source, title, summary, out_dir)
    elif source.exists() and source.is_file():
        rendered, thumbnail = render_from_file(source, title, summary, out_dir)
    else:
        alternates = proof_run_alternates(source)
        if alternates:
            rendered = render_from_proof_run(alternates, title, summary)
        else:
            body = f"<section><p>Original source path could not be found: <code>{html.escape(str(source))}</code></p></section>"
            rendered = html_shell(title, body, summary)
        thumbnail = ""

    index_path = out_dir / "index.html"
    index_path.write_text(rendered, encoding="utf-8")

    timestamp = first_string(item, "createdAt", "created_at", "timestamp") or now_iso()
    entry = {
        "agent": first_string(item, "agent"),
        "createdAt": timestamp,
        "filePath": workspace_path(index_path),
        "folderPath": path_with_trailing_slash(out_dir),
        "id": first_string(item, "id") or f"DEL-{date.replace('-', '')}-{slugify(ticket)}-{slugify(title)[:40]}",
        "kind": "html",
        "project": first_string(item, "project") or first_string(item, "agent") or "General",
        "sourcePath": workspace_path(source),
        "status": first_string(item, "status") or "ready",
        "summary": summary,
        "ticketId": ticket,
        "title": title,
        "updatedAt": now_iso(),
    }
    if thumbnail:
        entry["thumbnailPath"] = thumbnail
    if phase:
        entry["phase"] = phase
    legacy_type = first_string(item, "type")
    if legacy_type:
        entry["legacyType"] = legacy_type
    alternates = proof_run_alternates(source) if not source.exists() else []
    if alternates:
        entry["sourcePaths"] = [workspace_path(path) for path in alternates]

    write_json(out_dir / "metadata.json", entry)
    return {key: value for key, value in entry.items() if value != ""}


def loose_file_items(existing_sources: set[str]) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    if not DELIVERABLE_ROOT.exists():
        return items
    for path in sorted(DELIVERABLE_ROOT.iterdir()):
        if path.name == "manifest.json" or path.is_dir() or path.name.startswith("."):
            continue
        if path.suffix.lower() not in {".md", ".txt", ".html", ".htm", ".png", ".jpg", ".jpeg", ".pdf"}:
            continue
        source = workspace_path(path)
        if source in existing_sources or str(path) in existing_sources:
            continue
        ticket = ticket_from_item({}, path)
        title = markdown_title(path) if path.suffix.lower() in {".md", ".txt"} else ""
        items.append({
            "agent": "Thrawn",
            "filePath": source,
            "status": "ready",
            "summary": "Migrated loose deliverable into the human-readable HTML deliverable library.",
            "ticketId": ticket,
            "title": title or path.stem.replace("-", " ").replace("_", " ").title(),
        })
    return items


def task_board_items(existing_sources: set[str], manifest_tickets: set[str]) -> list[dict[str, Any]]:
    if not TASK_BOARD_PATH.exists():
        return []
    items: list[dict[str, Any]] = []
    current: dict[str, str] | None = None
    for line in TASK_BOARD_PATH.read_text(encoding="utf-8", errors="ignore").splitlines():
        task_match = re.match(r"###\s+(TASK-\d+)", line)
        if task_match:
            current = {"ticketId": task_match.group(1)}
            continue
        if current is None or not line.startswith("- "):
            continue
        key, _, value = line[2:].partition(":")
        key = key.strip()
        value = value.strip()
        if key in {"Title", "Owner", "Status", "Deliverable", "Notes"}:
            current[key] = value
        if key == "Deliverable" and value:
            resolved = resolve_path(value)
            if value in existing_sources or workspace_path(resolved) in existing_sources:
                continue
            if not resolved.exists() and current["ticketId"] in manifest_tickets:
                continue
            items.append({
                "agent": current.get("Owner", "Thrawn"),
                "filePath": value,
                "project": current.get("Owner", "General") or "General",
                "status": current.get("Status", "ready") or "ready",
                "summary": current.get("Notes", ""),
                "ticketId": current["ticketId"],
                "title": current.get("Title", current["ticketId"]) or current["ticketId"],
            })
    return items


def migrate() -> dict[str, Any]:
    DELIVERABLE_ROOT.mkdir(parents=True, exist_ok=True)
    raw = read_json(MANIFEST_PATH, {"deliverables": []})
    items = manifest_items(raw)
    manifest_tickets = {ticket_from_item(item, resolve_path(first_string(item, "sourcePath", "source_path", "filePath", "file_path", "path", "evidence_path", "evidencePath"))) for item in items}

    existing_sources: set[str] = set()
    for item in items:
        for key in ["filePath", "file_path", "path", "evidence_path", "evidencePath", "sourcePath", "source_path"]:
            value = first_string(item, key)
            if value:
                existing_sources.add(value)
    existing_sources.discard("")
    items.extend(task_board_items(existing_sources, manifest_tickets))
    items.extend(loose_file_items(existing_sources))

    canonical: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in items:
        raw_file = first_string(item, "filePath", "file_path", "path", "evidence_path", "evidencePath")
        already_html = raw_file.startswith("workspace/deliverables/") and raw_file.endswith("/index.html")
        raw_source = first_string(item, "sourcePath", "source_path") if already_html else ""
        raw_source = raw_source or raw_file
        if not raw_source:
            continue
        source = resolve_path(raw_source)
        if already_html and not first_string(item, "sourcePath", "source_path"):
            entry = dict(item)
            entry.setdefault("kind", "html")
            entry.setdefault("updatedAt", now_iso())
        else:
            entry = canonical_entry(item, source)
        key = entry["filePath"]
        if key in seen:
            continue
        seen.add(key)
        canonical.append(entry)

    canonical.sort(key=lambda entry: (entry.get("updatedAt", ""), entry.get("createdAt", "")), reverse=True)
    manifest = {
        "deliverableRoot": "workspace/deliverables",
        "primaryFormat": "html",
        "schemaVersion": 2,
        "updatedAt": now_iso(),
        "deliverables": canonical,
    }
    write_json(MANIFEST_PATH, manifest)
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description="Publish or migrate Thrawn deliverables to HTML.")
    parser.add_argument("--migrate", action="store_true", help="Migrate the current manifest and loose deliverables.")
    parser.add_argument("--print-summary", action="store_true", help="Print a compact JSON summary.")
    args = parser.parse_args()

    manifest = migrate()
    if args.print_summary or args.migrate:
        print(json.dumps({
            "manifest": str(MANIFEST_PATH),
            "count": len(manifest["deliverables"]),
            "primaryFormat": manifest["primaryFormat"],
        }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
