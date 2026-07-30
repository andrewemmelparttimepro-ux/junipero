#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path


def s(*parts: str) -> str:
    return "".join(parts)


BANNED_TERMS = [
    s("anth", "ropic"),
    s("clau", "de"),
    s("gem", "ini"),
    s("juni", "pero"),
    s("r2", "d2"),
    s("c3", "po"),
    s("qui", "gon"),
    s("lan", "do"),
    s("bo", "ba"),
    s("hunt", "er"),
    s("ba", "rt"),
    s("thrawn-", "dream"),
    s("thrawn-", "handoff"),
]

SOURCE_EXCLUDED_DIRS = {
    ".git",
    ".build",
    "dist",
    "artifacts",
    "__pycache__",
}

RUNTIME_EXCLUDED_PREFIXES = [
    Path("backups"),
    Path("workspace/logs"),
    Path("workspace/proofs"),
    Path("workspace/reports"),
    Path("workspace/deliverables"),
]

RUNTIME_EXCLUDED_FILES = {
    Path("threads.json"),
}

TEXT_EXTENSIONS = {
    "",
    ".c",
    ".cpp",
    ".css",
    ".h",
    ".html",
    ".js",
    ".json",
    ".md",
    ".plist",
    ".py",
    ".sh",
    ".swift",
    ".txt",
    ".xml",
    ".yml",
    ".yaml",
}


def is_text_candidate(path: Path) -> bool:
    if path.suffix.lower() in TEXT_EXTENSIONS:
        return True
    return path.name in {"README", "LICENSE"}


def source_allowed(path: Path, root: Path) -> bool:
    rel = path.relative_to(root)
    return not any(part in SOURCE_EXCLUDED_DIRS for part in rel.parts)


def runtime_allowed(path: Path, root: Path) -> bool:
    rel = path.relative_to(root)
    if rel in RUNTIME_EXCLUDED_FILES:
        return False
    return not any(rel == prefix or prefix in rel.parents for prefix in RUNTIME_EXCLUDED_PREFIXES)


def scan_tree(root: Path, allow_fn) -> list[tuple[Path, str]]:
    hits: list[tuple[Path, str]] = []
    if not root.exists():
        return hits
    for path in root.rglob("*"):
        if not allow_fn(path, root):
            continue
        rel_text = str(path.relative_to(root)).lower()
        for term in BANNED_TERMS:
            if term in rel_text:
                hits.append((path, term))
        if not path.is_file() or not is_text_candidate(path):
            continue
        try:
            text = path.read_text(errors="ignore").lower()
        except OSError:
            continue
        for term in BANNED_TERMS:
            if term in text:
                hits.append((path, term))
    return hits


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit Thrawn live source and runtime for removed legacy terms.")
    parser.add_argument("--source-root", default=str(Path.cwd()))
    parser.add_argument("--runtime-root", default=str(Path.home() / "Library/Application Support/Thrawn"))
    args = parser.parse_args()

    source_root = Path(args.source_root).resolve()
    runtime_root = Path(args.runtime_root).resolve()
    hits = []
    hits.extend(("source", path, term) for path, term in scan_tree(source_root, source_allowed))
    hits.extend(("runtime", path, term) for path, term in scan_tree(runtime_root, runtime_allowed))

    if hits:
        for scope, path, term in hits:
            print(f"{scope}: {path}: legacy term {term!r}")
        print(f"FAIL: {len(hits)} legacy residue hit(s) found.")
        return 1

    print("PASS: no removed legacy terms found in live source or live runtime.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
