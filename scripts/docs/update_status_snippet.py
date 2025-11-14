#!/usr/bin/env python3
"""
Sync ERNI-KI status snippet across README and MkDocs sources.

Source of truth: docs/reference/status.yml
Generated snippet: docs/reference/status-snippet.md
README.md is updated between <!-- STATUS_SNIPPET_START/END --> markers.
Docs consume the snippet via mkdocs-include-markdown.
"""

from __future__ import annotations

from pathlib import Path
from typing import Dict

REPO_ROOT = Path(__file__).resolve().parents[2]
STATUS_YAML = REPO_ROOT / "docs/reference/status.yml"
SNIPPET_MD = REPO_ROOT / "docs/reference/status-snippet.md"
SNIPPET_DE_MD = REPO_ROOT / "docs/locales/de/status-snippet.md"
README_FILE = REPO_ROOT / "README.md"
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


def render_snippet(data: Dict[str, str]) -> str:
    """Build the Markdown snippet in Russian (default)."""
    lines = [
        f"> **Статус системы ({data.get('date', 'n/a')}) — {data.get('release', '')}**",
        ">",
        f"> - Контейнеры: {data.get('containers', '')}",
        f"> - Графана: {data.get('grafana_dashboards', '')}",
        f"> - Алерты: {data.get('prometheus_alerts', '')}",
        f"> - AI/GPU: {data.get('gpu_stack', '')}",
        f"> - Context & RAG: {data.get('ai_stack', '')}",
        f"> - Мониторинг: {data.get('monitoring_stack', '')}",
        f"> - Автоматизация: {data.get('automation', '')}",
    ]
    note = data.get("notes")
    if note:
        lines.append(f"> - Примечание: {note}")
    return "\n".join(lines) + "\n"


def write_snippet(content: str) -> None:
    SNIPPET_MD.write_text(content, encoding="utf-8")


def render_snippet_de(data: Dict[str, str]) -> str:
    """Build the German Markdown snippet using the same YAML data."""
    lines = [
        f"> **Systemstatus ({data.get('date', 'n/a')}) — {data.get('release', '')}**",
        ">",
        f"> - Container: {data.get('containers', '')}",
        f"> - Grafana: {data.get('grafana_dashboards', '')}",
        f"> - Alerts: {data.get('prometheus_alerts', '')}",
        f"> - AI/GPU: {data.get('gpu_stack', '')}",
        f"> - Context & RAG: {data.get('ai_stack', '')}",
        f"> - Monitoring: {data.get('monitoring_stack', '')}",
        f"> - Automatisierung: {data.get('automation', '')}",
    ]
    note = data.get("notes")
    if note:
        lines.append(f"> - Hinweis: {note}")
    return "\n".join(lines) + "\n"


def write_snippet_de(content: str) -> None:
    SNIPPET_DE_MD.write_text(content, encoding="utf-8")


def update_readme(content: str) -> None:
    text = README_FILE.read_text(encoding="utf-8")
    start = text.find(MARKER_START)
    end = text.find(MARKER_END)
    if start == -1 or end == -1:
        raise RuntimeError(
            "README.md markers not found. Add STATUS_SNIPPET_START/END comments."
        )
    if start > end:
        raise RuntimeError("README.md markers are misordered.")
    new_text = (
        text[: start + len(MARKER_START)].rstrip()
        + "\n\n"
        + content
        + "\n"
        + text[end:]
    )
    README_FILE.write_text(new_text, encoding="utf-8")


def update_de_index(content: str) -> None:
    text = DE_INDEX_FILE.read_text(encoding="utf-8")
    start = text.find(DE_MARKER_START)
    end = text.find(DE_MARKER_END)
    if start == -1 or end == -1:
        raise RuntimeError(
            "docs/locales/de/index.md markers not found. "
            "Add STATUS_SNIPPET_DE_START/END comments."
        )
    if start > end:
        raise RuntimeError("German status markers are misordered.")
    new_text = (
        text[: start + len(DE_MARKER_START)].rstrip()
        + "\n\n"
        + content
        + "\n"
        + text[end:]
    )
    DE_INDEX_FILE.write_text(new_text, encoding="utf-8")


def main() -> None:
    data = parse_simple_yaml(STATUS_YAML)
    snippet_ru = render_snippet(data)
    write_snippet(snippet_ru)
    update_readme(snippet_ru)

    snippet_de = render_snippet_de(data)
    write_snippet_de(snippet_de)
    update_de_index(snippet_de)

    print("Status snippets updated from docs/reference/status.yml")


if __name__ == "__main__":
    main()
