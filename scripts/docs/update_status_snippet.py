#!/usr/bin/env python3
"""
Sync or validate ERNI-KI status snippets across README, docs and locales.

Source of truth: docs/reference/status.yml
Run without arguments to update snippets, or with --check to validate.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Dict

REPO_ROOT = Path(__file__).resolve().parents[2]
STATUS_YAML = REPO_ROOT / "docs/reference/status.yml"
SNIPPET_MD = REPO_ROOT / "docs/reference/status-snippet.md"
SNIPPET_DE_MD = REPO_ROOT / "docs/locales/de/status-snippet.md"
README_FILE = REPO_ROOT / "README.md"
DOC_INDEX_FILE = REPO_ROOT / "docs/index.md"
DOC_OVERVIEW_FILE = REPO_ROOT / "docs/overview.md"
DE_INDEX_FILE = REPO_ROOT / "docs/locales/de/index.md"
MARKER_START = "<!-- STATUS_SNIPPET_START -->"
MARKER_END = "<!-- STATUS_SNIPPET_END -->"
DE_MARKER_START = "<!-- STATUS_SNIPPET_DE_START -->"
DE_MARKER_END = "<!-- STATUS_SNIPPET_DE_END -->"


def parse_simple_yaml(path: Path) -> Dict[str, str]:
    """Minimal YAML parser for flat key-value files."""
    data: Dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        data[key.strip()] = value.strip().strip('"').strip("'")
    return data


def render_snippet(data: Dict[str, str], locale: str = "ru") -> str:
    """Build the Markdown snippet in Russian or German."""
    header = (
        f"> **Статус системы ({data.get('date', 'n/a')}) — {data.get('release', '')}**"
        if locale == "ru"
        else f"> **Systemstatus ({data.get('date', 'n/a')}) — {data.get('release', '')}**"
    )
    lines = [
        header,
        ">",
        (
            f"> - Контейнеры: {data.get('containers', '')}"
            if locale == "ru"
            else f"> - Container: {data.get('containers', '')}"
        ),
        f"> - {'Графана' if locale == 'ru' else 'Grafana'}: {data.get('grafana_dashboards', '')}",
        f"> - {'Алерты' if locale == 'ru' else 'Alerts'}: {data.get('prometheus_alerts', '')}",
        f"> - AI/GPU: {data.get('gpu_stack', '')}",
        f"> - Context & RAG: {data.get('ai_stack', '')}",
        f"> - {'Мониторинг' if locale == 'ru' else 'Monitoring'}: {data.get('monitoring_stack', '')}",
        f"> - {'Автоматизация' if locale == 'ru' else 'Automatisierung'}: {data.get('automation', '')}",
    ]
    note = data.get("notes")
    if note:
        label = "Примечание" if locale == "ru" else "Hinweis"
        lines.append(f"> - {label}: {note}")
    return "\n".join(lines) + "\n"


def write_snippet(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")


def inject_snippet(target: Path, start_marker: str, end_marker: str, content: str) -> None:
    text = target.read_text(encoding="utf-8")
    start = text.find(start_marker)
    end = text.find(end_marker)
    if start == -1 or end == -1:
        raise RuntimeError(f"{target} markers not found.")
    if start > end:
        raise RuntimeError(f"{target} markers are misordered.")
    new_text = (
        text[: start + len(start_marker)].rstrip()
        + "\n\n"
        + content
        + "\n"
        + text[end:]
    )
    target.write_text(new_text, encoding="utf-8")


def snippet_present(target: Path, marker_start: str, marker_end: str, content: str) -> bool:
    text = target.read_text(encoding="utf-8")
    start = text.find(marker_start)
    end = text.find(marker_end)
    if start == -1 or end == -1 or start > end:
        return False
    current = text[start + len(marker_start) : end].strip()
    return current == content.strip()


def run_update() -> None:
    data = parse_simple_yaml(STATUS_YAML)
    snippet_ru = render_snippet(data, "ru")
    snippet_de = render_snippet(data, "de")

    write_snippet(SNIPPET_MD, snippet_ru)
    write_snippet(SNIPPET_DE_MD, snippet_de)

    inject_snippet(README_FILE, MARKER_START, MARKER_END, snippet_ru)
    inject_snippet(DOC_INDEX_FILE, MARKER_START, MARKER_END, snippet_ru)
    inject_snippet(DOC_OVERVIEW_FILE, MARKER_START, MARKER_END, snippet_ru)
    inject_snippet(DE_INDEX_FILE, DE_MARKER_START, DE_MARKER_END, snippet_de)
    print("Status snippets updated from docs/reference/status.yml")


def run_check() -> None:
    data = parse_simple_yaml(STATUS_YAML)
    snippet_ru = render_snippet(data, "ru").strip()
    snippet_de = render_snippet(data, "de").strip()

    errors = []
    if SNIPPET_MD.read_text(encoding="utf-8").strip() != snippet_ru:
        errors.append("docs/reference/status-snippet.md is out of date.")
    if SNIPPET_DE_MD.read_text(encoding="utf-8").strip() != snippet_de:
        errors.append("docs/locales/de/status-snippet.md is out of date.")

    if errors:
        print("Status snippet validation failed:", file=sys.stderr)
        for err in errors:
            print(f"- {err}", file=sys.stderr)
        sys.exit(1)
    print("Status snippets are up to date.")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Update or validate ERNI-KI status snippets."
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Validate snippets instead of updating them.",
    )
    args = parser.parse_args()

    if args.check:
        run_check()
    else:
        run_update()


if __name__ == "__main__":
    main()
