#!/usr/bin/env python3
from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas


ROOT = Path("/Users/andrewemmel/Documents/thrawn-console")
OUT_DIR = ROOT / "artifacts" / "thrawn-guide"
OUT = OUT_DIR / "thrawn-v2-guide.pdf"
APP = Path.home() / "Library/Application Support/Thrawn"
WORKSPACE = APP / "workspace"
LOGO = OUT_DIR / "logo-mark-20260520.png"

PAGE_W, PAGE_H = letter
M = 46

OBS = colors.HexColor("#050505")
CARBON = colors.HexColor("#0A0A0A")
GRAPHITE = colors.HexColor("#141414")
GRAPHITE2 = colors.HexColor("#1C1C1C")
GRAPHITE3 = colors.HexColor("#2A2A2A")
WHITE = colors.HexColor("#F0F0F0")
MUTED = colors.HexColor("#A4A7B1")
DIM = colors.HexColor("#6E7280")
GREEN = colors.HexColor("#44EE88")
GREEN_D = colors.HexColor("#0D7A3E")
WARN = colors.HexColor("#F6A23C")
CHROME = colors.HexColor("#CFD1D6")
CHROME_D = colors.HexColor("#6E7280")
BORDER = colors.Color(1, 1, 1, alpha=0.10)
BORDER2 = colors.Color(1, 1, 1, alpha=0.18)


def register_fonts() -> None:
    fonts = Path.home() / "Library/Fonts"
    candidates = {
        "Space": fonts / "SpaceGrotesk-Regular.ttf",
        "Space-Semi": fonts / "SpaceGrotesk-SemiBold.ttf",
        "Space-Bold": fonts / "SpaceGrotesk-Bold.ttf",
    }
    for name, path in candidates.items():
        if path.exists():
            pdfmetrics.registerFont(TTFont(name, str(path)))


def font(name: str) -> str:
    return name if name in pdfmetrics.getRegisteredFontNames() else "Helvetica"


def load_json(path: Path, fallback):
    try:
        return json.loads(path.read_text())
    except Exception:
        return fallback


def text_lines(c: canvas.Canvas, text: str, x: float, y: float, width: float, size=9.5, leading=13, color=MUTED, face="Helvetica", max_lines=None):
    c.setFont(face, size)
    c.setFillColor(color)
    words = text.replace("\n", " \n ").split()
    lines = []
    line = ""
    for word in words:
        if word == "\n":
            lines.append(line)
            line = ""
            continue
        test = f"{line} {word}".strip()
        if c.stringWidth(test, face, size) <= width:
            line = test
        else:
            if line:
                lines.append(line)
            line = word
    if line:
        lines.append(line)
    if max_lines:
        lines = lines[:max_lines]
    for line in lines:
        c.drawString(x, y, line)
        y -= leading
    return y


def page_bg(c: canvas.Canvas, title: str, kicker: str | None = None, page_num: int | None = None):
    c.setFillColor(CARBON)
    c.rect(0, 0, PAGE_W, PAGE_H, fill=1, stroke=0)
    c.setFillColor(colors.Color(0.27, 0.93, 0.53, alpha=0.045))
    c.circle(PAGE_W * 0.82, PAGE_H * 0.86, 190, fill=1, stroke=0)
    c.setFillColor(colors.Color(1, 1, 1, alpha=0.025))
    c.circle(PAGE_W * 0.20, PAGE_H * 0.18, 260, fill=1, stroke=0)
    c.setStrokeColor(colors.Color(1, 1, 1, alpha=0.06))
    for yy in range(72, int(PAGE_H), 72):
        c.line(M, yy, PAGE_W - M, yy)
    if kicker:
        c.setFont(font("Space-Semi"), 7.5)
        c.setFillColor(DIM)
        c.drawString(M, PAGE_H - 36, kicker.upper())
    if title:
        c.setFont(font("Space-Bold"), 16)
        c.setFillColor(CHROME)
        c.drawString(M, PAGE_H - 58, title)
        c.setStrokeColor(BORDER2)
        c.line(M, PAGE_H - 72, PAGE_W - M, PAGE_H - 72)
    if page_num is not None:
        c.setFont("Courier", 7)
        c.setFillColor(DIM)
        c.drawRightString(PAGE_W - M, 28, f"NDAI / THRAWN V2 / {page_num:02d}")


def pill(c, x, y, label, fill=GRAPHITE2, stroke=BORDER2, fg=WHITE):
    w = c.stringWidth(label, font("Space-Semi"), 8) + 18
    c.setFillColor(fill)
    c.setStrokeColor(stroke)
    c.roundRect(x, y - 10, w, 18, 9, fill=1, stroke=1)
    c.setFont(font("Space-Semi"), 8)
    c.setFillColor(fg)
    c.drawString(x + 9, y - 3, label)
    return x + w + 8


def card(c, x, y, w, h, title, body=None, accent=GREEN, label=None):
    c.setFillColor(GRAPHITE)
    c.setStrokeColor(BORDER)
    c.roundRect(x, y - h, w, h, 10, fill=1, stroke=1)
    c.setFillColor(colors.Color(accent.red, accent.green, accent.blue, alpha=0.12))
    c.rect(x, y - h, 4, h, fill=1, stroke=0)
    if label:
        c.setFont("Courier", 6.5)
        c.setFillColor(DIM)
        c.drawString(x + 16, y - 18, label.upper())
        ty = y - 36
    else:
        ty = y - 22
    c.setFont(font("Space-Bold"), 12)
    c.setFillColor(WHITE)
    c.drawString(x + 16, ty, title)
    if body:
        text_lines(c, body, x + 16, ty - 18, w - 32, size=8.7, leading=12, color=MUTED, face="Helvetica")


def section_title(c, num, title, lede, y):
    c.setFont(font("Space-Semi"), 8)
    c.setFillColor(DIM)
    c.drawString(M, y, num.upper())
    c.setStrokeColor(BORDER2)
    c.line(M + 72, y + 3, M + 140, y + 3)
    c.setFont(font("Space-Bold"), 23)
    c.setFillColor(WHITE)
    c.drawString(M + 170, y - 3, title)
    text_lines(c, lede, M + 170, y - 24, PAGE_W - M * 2 - 170, size=10, leading=14, color=MUTED, face="Helvetica")
    return y - 72


def table(c, x, y, cols, rows, widths, row_h=28):
    c.setFont("Courier", 6.8)
    c.setFillColor(DIM)
    yy = y
    xx = x
    for col, w in zip(cols, widths):
        c.drawString(xx + 6, yy - 10, col.upper())
        xx += w
    yy -= 18
    c.setStrokeColor(BORDER)
    c.line(x, yy, x + sum(widths), yy)
    for row in rows:
        yy -= row_h
        c.setFillColor(GRAPHITE if int((y - yy) / row_h) % 2 else GRAPHITE2)
        c.rect(x, yy, sum(widths), row_h, fill=1, stroke=0)
        xx = x
        for cell, w in zip(row, widths):
            c.setFillColor(WHITE if xx == x else MUTED)
            c.setFont("Courier", 6.6)
            val = str(cell)
            max_chars = max(6, int(w / 4.2))
            if len(val) > max_chars:
                val = val[: max_chars - 1] + "…"
            c.drawString(xx + 6, yy + 10, val)
            xx += w
        c.setStrokeColor(colors.Color(1, 1, 1, alpha=0.045))
        c.line(x, yy, x + sum(widths), yy)
    return yy


def cover(c):
    c.setFillColor(OBS)
    c.rect(0, 0, PAGE_W, PAGE_H, fill=1, stroke=0)
    c.setFillColor(colors.Color(0.27, 0.93, 0.53, alpha=0.12))
    c.circle(PAGE_W * 0.68, PAGE_H * 0.66, 210, fill=1, stroke=0)
    c.setFillColor(colors.Color(1, 1, 1, alpha=0.04))
    c.circle(PAGE_W * 0.23, PAGE_H * 0.32, 260, fill=1, stroke=0)
    if LOGO.exists():
        c.drawImage(ImageReader(str(LOGO)), M, PAGE_H - 156, width=116, height=70, mask="auto")
    c.setFont(font("Space-Semi"), 8)
    c.setFillColor(DIM)
    c.drawString(M, PAGE_H - 186, "NDAI OPERATING SYSTEM / PRODUCT SENTINEL")
    c.setFont(font("Space-Bold"), 54)
    c.setFillColor(CHROME)
    c.drawString(M, PAGE_H - 248, "THRAWN")
    c.setFillColor(WHITE)
    c.drawString(M, PAGE_H - 304, "V2 GUIDE")
    c.setFont(font("Space-Semi"), 17)
    c.setFillColor(MUTED)
    c.drawString(M, PAGE_H - 340, "Command harness, board mechanics,")
    c.drawString(M, PAGE_H - 362, "heartbeats, proofs, and outputs.")
    y = PAGE_H - 396
    x = M
    x = pill(c, x, y, "SWIFTUI MAC APP", fg=GREEN)
    x = pill(c, x, y, "CODEX 5.5 EXTRA HIGH")
    x = pill(c, x, y, "PRODUCT SENTINEL")
    x = M
    pill(c, x, y - 28, "THRAWN + ARCHIVIST")
    pill(c, x + 146, y - 28, "MICROSOFT CLARITY SIGNALS")
    c.setStrokeColor(BORDER2)
    c.line(M, 126, PAGE_W - M, 126)
    c.setFont("Courier", 8)
    c.setFillColor(DIM)
    c.drawString(M, 103, f"Generated {datetime.now().strftime('%Y-%m-%d %H:%M')} CT from live Thrawn workspace state.")
    c.drawString(M, 88, "Design language follows NDAI dark-first tokens: obsidian, carbon, chrome, automation green.")


def build_pdf():
    register_fonts()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    c = canvas.Canvas(str(OUT), pagesize=letter)
    c.setTitle("Thrawn V2 Guide")
    c.setAuthor("NDAI / Thrawn")
    c.setSubject("Current Thrawn V2 architecture, delegation, heartbeats, Product Sentinel, and outputs")
    c.setKeywords("NDAI, Thrawn, Product Sentinel, Microsoft Clarity, SwiftUI, agents")

    products = load_json(WORKSPACE / "product-sentinel/products.json", [])
    schedule = load_json(WORKSPACE / "product-sentinel/schedule.json", {})
    scheduler = load_json(APP / "agent-scheduler.json", [])
    specs = load_json(APP / "agent-specs.json", [])
    objectives = load_json(WORKSPACE / "objectives.json", [])

    cover(c)
    c.showPage()

    page_bg(c, "Operating Picture", "01 / current state", 2)
    y = section_title(
        c,
        "01",
        "System As It Stands",
        "Thrawn V2 is a Swift-native command harness with a clean two-agent roster, a Product Sentinel objective, proof storage, Citadel synthesis, and a board-driven delegation contract.",
        PAGE_H - 106,
    )
    card(c, M, y, 160, 104, "Thrawn", "Command layer. Core identity is Codex 5.5 Extra High; fallback state is visible but does not replace the identity.", label="agent")
    card(c, M + 178, y, 160, 104, "Samwell Tarly", "Arch Maester. Maintains product pages and the rolling 72-hour brief from immutable evidence.", label="agent", accent=CHROME)
    card(c, M + 356, y, 164, 104, "Product Sentinel", "Active objective watches Vaultage, Hit Zero, Cyclops, and Sandpro OMP.", label="mission", accent=WARN)
    y -= 134
    active = [o for o in objectives if o.get("status") == "active"]
    rows = [[o.get("id"), o.get("playbookId"), o.get("input"), f"phase {o.get('currentPhaseIndex', 0)}", f"{o.get('tasksCompleted', 0)}/{o.get('tasksCreated', 0)}"] for o in active] or [["none", "-", "-", "-", "-"]]
    c.setFont(font("Space-Bold"), 15)
    c.setFillColor(WHITE)
    c.drawString(M, y, "Active Objectives")
    table(c, M, y - 16, ["id", "playbook", "input", "phase", "tasks"], rows, [118, 122, 160, 70, 50])
    y -= 120
    c.setFont(font("Space-Bold"), 15)
    c.setFillColor(WHITE)
    c.drawString(M, y, "Important Truth")
    text_lines(
        c,
        "The architecture is board-driven. Agents receive the board first on every heartbeat, but the board itself is only mutated by the dispatcher. Thrawn and Samwell Tarly now have narrow task_write permission so they can submit JSON updates without directly editing the board.",
        M,
        y - 20,
        PAGE_W - 2 * M,
        size=10,
        leading=14,
        color=MUTED,
    )
    c.showPage()

    page_bg(c, "Delegation & Board Mechanics", "02 / how work moves", 3)
    y = section_title(
        c,
        "02",
        "Delegation Flow",
        "Objectives create intent. Thrawn decomposes intent into board tasks. Agents execute tasks. The dispatcher applies updates and the scanner advances objective phases.",
        PAGE_H - 106,
    )
    steps = [
        ("Objective", "Andrew launches a playbook such as Product Sentinel: all products."),
        ("Thrawn heartbeat", "Reads TASK_BOARD.md first, then objective context and operating contract."),
        ("Task creation", "Writes JSON to pending-updates/updates-thrawn.json using task_write."),
        ("Dispatcher", "Runs every 30 seconds, locks the board, backs it up, applies create/move/update/note."),
        ("Agent work", "Assigned agent wakes, reads board first, works Ready tasks, writes update JSON."),
        ("Phase advance", "Objective scanner counts linked Done tasks and advances phases automatically."),
    ]
    x, yy = M, y
    for i, (title, body) in enumerate(steps, 1):
        card(c, x, yy, 238, 76, f"{i}. {title}", body, accent=GREEN if i in (2, 4) else CHROME)
        if i % 2:
            x = M + 282
        else:
            x = M
            yy -= 96
    yy -= 108
    c.setFont(font("Space-Bold"), 15)
    c.setFillColor(WHITE)
    c.drawString(M, yy, "Board Files")
    rows = [
        ["TASK_BOARD.md", "Human-readable Kanban source of truth"],
        ["pending-updates/updates-*.json", "Agent-submitted board mutations"],
        ["TASK_BOARD.md.lock", "Cross-process lock during dispatcher write"],
        ["board-backups/", "Pre-mutation board snapshots"],
    ]
    table(c, M, yy - 16, ["path", "purpose"], rows, [220, 300], row_h=30)
    c.showPage()

    page_bg(c, "Heartbeat Settings", "03 / native swift timers", 4)
    y = section_title(c, "03", "Heartbeats", "The scheduler is native Swift, not external cron. It checks every 30 seconds and persists last-run timestamps across app restarts.", PAGE_H - 106)
    rows = []
    for agent in scheduler:
        if agent.get("id") == "thrawn":
            cadence = "every 15 min (:00/:15/:30/:45)"
        elif agent.get("id") == "archivist":
            cadence = ":55 at 8 AM, 1 PM, 6 PM"
        else:
            cadence = f":{agent.get('minuteOffset', 0):02d} hourly"
        rows.append([agent.get("name"), agent.get("id"), cadence, agent.get("heartbeatFile"), "enabled" if agent.get("enabled") else "off"])
    table(c, M, y, ["agent", "id", "cadence", "heartbeat", "state"], rows, [82, 70, 170, 154, 54], row_h=34)
    y -= 166
    card(c, M, y, 250, 118, "Briefings", "SOD briefing fires at 7:00 AM. EOD briefing fires at 7:00 PM. BriefingService routes one-shot prompts through scheduler plumbing and logs generation in runtime events.", accent=WARN)
    card(c, M + 278, y, 250, 118, "Reliability", "Running agents are skipped until complete. Last-run timestamps prevent immediate duplicates after sleep, crash, or reopen. Watchdogs prevent hung heartbeat and dispatcher loops.", accent=GREEN)
    y -= 150
    c.setFont(font("Space-Bold"), 15)
    c.setFillColor(WHITE)
    c.drawString(M, y, "Product Sentinel Check Windows")
    rows = [[w.get("id"), f"{w.get('hour'):02d}:{w.get('minute'):02d}", schedule.get("timezone", "local"), schedule.get("dedupe_key", "")] for w in schedule.get("windows", [])]
    table(c, M, y - 16, ["window", "time", "timezone", "dedupe"], rows, [100, 90, 142, 188], row_h=30)
    c.showPage()

    page_bg(c, "Agents, Tools, Routing", "04 / team contract", 5)
    y = section_title(c, "04", "Agents Know The Board", "Every heartbeat prompt includes TASK_BOARD.md first. The preamble tells the agent to find tasks where Owner equals its name and Status equals Ready.", PAGE_H - 106)
    rows = []
    for s in specs:
        tools = ",".join((s.get("tools") or {}).get("tools", []))
        tier = (s.get("tier") or {}).get("tier", "")
        rows.append([s.get("name"), s.get("role"), tier, tools])
    table(c, M, y, ["agent", "role", "tier", "tools"], rows, [90, 126, 70, 234], row_h=42)
    y -= 132
    card(c, M, y, 250, 144, "Thrawn Core", "Identity: Codex 5.5 Extra High. Routing tries OpenAI gpt-5.5 xhigh first. If unavailable, fallback is visible as degraded status without changing the core identity label.", accent=GREEN)
    card(c, M + 278, y, 250, 144, "Product Sentinel Route", "The left selector controls background/Product Sentinel model route. It is not Thrawn's core brain. V2 experimental agents use explicit AgentSpec routing.", accent=CHROME)
    y -= 176
    c.setFont(font("Space-Bold"), 15)
    c.setFillColor(WHITE)
    c.drawString(M, y, "Permission Principle")
    text_lines(c, "Agents get the tools they need, not blanket shell access. task_write lets them submit board updates, while the dispatcher remains the only process that edits TASK_BOARD.md.", M, y - 20, PAGE_W - 2 * M, size=10, leading=14)
    c.showPage()

    page_bg(c, "Product Sentinel Registry", "05 / products and clarity", 6)
    y = section_title(c, "05", "Products In Scope", "The registry is the operating source for roots, commands, user flows, and Microsoft Clarity expectations.", PAGE_H - 106)
    rows = []
    for p in products:
        clarity = p.get("clarity", {})
        cstat = "expected"
        if clarity.get("dashboardUrl"):
            cstat = "dashboard known"
        rows.append([p.get("name"), p.get("id"), p.get("rootPath"), p.get("buildCommand") or "-", p.get("testCommand") or "-", cstat])
    table(c, M, y, ["product", "id", "root", "build", "test", "clarity"], rows, [82, 76, 170, 70, 74, 68], row_h=38)
    y -= 190
    card(c, M, y, 528, 144, "Microsoft Clarity Is A Major Signal", "For products with clarity.expected = true, proof runs scan the repo for tracking code and write logs/microsoft-clarity.log. Recommendations should consult rage clicks, dead clicks, quick backs, excessive scrolling, recordings, heatmaps, funnels, smart events, and top affected pages.", accent=GREEN)
    c.showPage()

    page_bg(c, "Proofs, Citadel, Outputs", "06 / evidence map", 7)
    y = section_title(c, "06", "Output System", "Thrawn separates immutable proof from readable context. Raw evidence stays in proof directories; Samwell Tarly keeps synthesis in Citadel pages.", PAGE_H - 106)
    rows = [
        ["Proof root", "workspace/proofs/<product>/<yyyy-mm-dd>/<run-id>/"],
        ["Metadata", "proof-run.json"],
        ["Verdict", "verdict.md"],
        ["Screenshots", "screenshots/desktop-proof.png"],
        ["Logs", "logs/git-status.log, build.log, test.log, microsoft-clarity.log"],
        ["Citadel product page", "workspace/citadel/products/<product>.md"],
        ["Rolling brief", "workspace/citadel/rolling-72h.md"],
        ["Runtime logs", "workspace/logs/*.jsonl"],
    ]
    table(c, M, y, ["artifact", "location"], rows, [128, 392], row_h=34)
    y -= 310
    card(c, M, y, 250, 120, "Immutable Evidence", "Raw proof directories should not be rewritten. New observations append to Citadel/context, preserving the original run.", accent=CHROME)
    card(c, M + 278, y, 250, 120, "Readable Context", "The rolling 72-hour brief is intentionally short enough for Thrawn to read every cycle and use as context.", accent=GREEN)
    c.showPage()

    page_bg(c, "File System Map", "07 / where everything lives", 8)
    y = section_title(c, "07", "Live Paths", "The app copies versioned OpsBundle files into Application Support, then runtime state evolves there.", PAGE_H - 106)
    rows = [
        ["Active config", "~/Library/Application Support/Thrawn/"],
        ["Archive root", "~/Library/Application Support/Thrawn Archives/"],
        ["Workspace docs", "workspace/*.md"],
        ["Agents", "workspace/agents/"],
        ["Heartbeats", "workspace/ops/heartbeats/"],
        ["Board", "workspace/ops/TASK_BOARD.md"],
        ["Pending updates", "workspace/ops/pending-updates/"],
        ["Product registry", "workspace/product-sentinel/products.json"],
        ["Proofs", "workspace/proofs/"],
        ["Citadel", "workspace/citadel/"],
        ["Guide", "workspace/THRAWN_GUIDE.md"],
    ]
    table(c, M, y, ["thing", "path"], rows, [140, 380], row_h=31)
    y -= 386
    card(c, M, y, 528, 94, "Current Limitation / Next Build", "Product Sentinel has registry, schedule, proof hook, Clarity scanning, and Samwell Tarly synthesis. The next natural step is a dedicated Sentinel runner/agent that autonomously starts products, drives browser flows, captures screenshots, and runs each scheduled window.", accent=WARN)
    c.showPage()

    page_bg(c, "Runbook", "08 / operator notes", 9)
    y = section_title(c, "08", "How To Operate It", "Short, durable actions for the next build cycle.", PAGE_H - 106)
    items = [
        ("Launch objective", "Use Objectives > Product Sentinel with a product or all products."),
        ("Watch board", "The board should fill after Thrawn heartbeat creates phase tasks."),
        ("Manual proof", "Run product-sentinel-proof.py --product <id> for immediate evidence."),
        ("Review Clarity", "Before UX changes, inspect Clarity dashboard signals and record project IDs."),
        ("Add agents slowly", "Each new agent needs mandate, cadence, tool list, output paths, and review standard."),
        ("Promote Sentinel", "Next durable role should own scheduled product checks and browser proof capture."),
    ]
    for title, body in items:
        card(c, M, y, 528, 64, title, body, accent=GREEN if "Sentinel" in title or "Clarity" in title else CHROME)
        y -= 78
    c.setFont("Courier", 7)
    c.setFillColor(DIM)
    c.drawString(M, 44, "Source: live Thrawn workspace + NDAI design system tokens from https://ndai-design-web.vercel.app/")
    c.save()


if __name__ == "__main__":
    build_pdf()
    print(OUT)
