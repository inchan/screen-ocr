#!/usr/bin/env python3
"""Validate local links in project documentation."""
from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
DOC_GLOBS = ("*.md", "docs/*.md", "docs/*.html")
REMOTE_SCHEMES = {"http", "https", "mailto", "data"}
MARKDOWN_LINK = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)")
HTML_LINK = re.compile(r"""(?:href|src)=["']([^"']+)["']""", re.IGNORECASE)


def slugify(heading: str) -> str:
    value = heading.strip().lower()
    value = re.sub(r"[^\w\s가-힣-]", "", value, flags=re.UNICODE)
    value = re.sub(r"\s+", "-", value)
    return value.strip("-")


def anchors_for(path: Path) -> set[str]:
    if path.suffix.lower() == ".html":
        text = path.read_text(encoding="utf-8")
        return set(re.findall(r"""id=["']([^"']+)["']""", text))

    anchors: set[str] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.match(r"^(#{1,6})\s+(.+?)\s*$", line)
        if match:
            anchors.add(slugify(match.group(2)))
    return anchors


def documentation_files() -> list[Path]:
    files: set[Path] = set()
    for pattern in DOC_GLOBS:
        files.update(ROOT.glob(pattern))
    return sorted(path for path in files if path.is_file())


def link_targets(text: str) -> list[str]:
    return [*MARKDOWN_LINK.findall(text), *HTML_LINK.findall(text)]


def normalize_target(raw: str) -> tuple[str, str]:
    target = raw.strip()
    if not target or target.startswith("<"):
        return "", ""
    target = target.split()[0]
    parsed = urlsplit(target)
    if parsed.scheme in REMOTE_SCHEMES:
        return "", ""
    return unquote(parsed.path), unquote(parsed.fragment)


def validate_link(source: Path, raw: str) -> str | None:
    target_path, fragment = normalize_target(raw)
    if not target_path and not fragment:
        return None

    resolved = source if not target_path else (source.parent / target_path).resolve()
    try:
        resolved.relative_to(ROOT)
    except ValueError:
        return f"{source.relative_to(ROOT)}: link escapes repository: {raw}"

    if not resolved.exists():
        return f"{source.relative_to(ROOT)}: missing link target: {raw}"

    if fragment and resolved.is_file() and resolved.suffix.lower() in {".md", ".html"}:
        if fragment not in anchors_for(resolved):
            return f"{source.relative_to(ROOT)}: missing anchor #{fragment} in {resolved.relative_to(ROOT)}"

    return None


def main() -> int:
    failures: list[str] = []
    checked = 0
    for source in documentation_files():
        text = source.read_text(encoding="utf-8")
        for raw in link_targets(text):
            checked += 1
            failure = validate_link(source, raw)
            if failure:
                failures.append(failure)

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        return 1
    print(f"PASS: documentation links valid ({checked} links checked)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
