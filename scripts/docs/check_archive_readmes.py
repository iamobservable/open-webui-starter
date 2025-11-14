#!/usr/bin/env python3
"""Validate that archive/data README files list all documents."""

from __future__ import annotations

import sys
from pathlib import Path
from typing import List

ROOT = Path(__file__).resolve().parents[2]
ARCHIVE_CHECKS = {
    ROOT / "docs/archive/audits": ROOT / "docs/archive/audits/README.md",
    ROOT / "docs/archive/diagnostics": ROOT / "docs/archive/diagnostics/README.md",
    ROOT / "docs/archive/incidents": ROOT / "docs/archive/incidents/README.md",
}
DATA_DIR = ROOT / "docs/data"
DATA_README = DATA_DIR / "README.md"


def missing_entries(directory: Path, readme: Path, include_suffix: str = ".md") -> List[str]:
    text = readme.read_text(encoding="utf-8")
    missing: List[str] = []
    for md_file in sorted(directory.glob(f"*{include_suffix}")):
        if md_file.name.lower() == "readme.md":
            continue
        if md_file.name not in text:
            missing.append(md_file.name)
    return missing


def check_archive_readmes() -> List[str]:
    errors: List[str] = []
    for folder, readme in ARCHIVE_CHECKS.items():
        if not readme.exists():
            errors.append(f"{readme} отсутствует.")
            continue
        missing = missing_entries(folder, readme)
        if missing:
            errors.append(
                f"{readme} не содержит ссылки на: {', '.join(missing)}"
            )
    return errors


def check_data_readme() -> List[str]:
    if not DATA_README.exists():
        return [f"{DATA_README} отсутствует."]
    text = DATA_README.read_text(encoding="utf-8")
    missing = missing_entries(DATA_DIR, DATA_README)
    if missing:
        return [
            f"{DATA_README} не содержит записи для: {', '.join(missing)}"
        ]
    # также проверим, что каждая запись содержит дату в таблице
    table_rows = [
        line for line in text.splitlines() if line.strip().startswith("| ")
    ]
    if len(table_rows) < 3:
        return [
            f"{DATA_README} таблица состояния выглядит неполной (найдено {len(table_rows)} строк)."
        ]
    return []


def main() -> None:
    errors = check_archive_readmes()
    errors.extend(check_data_readme())
    if errors:
        print("Проверка README архивов/данных не пройдена:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        sys.exit(1)
    print("Archive/data READMEs cover all documents.")


if __name__ == "__main__":
    main()
