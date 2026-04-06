from __future__ import annotations

from pathlib import Path

from yaca.types import Context


def collect_context(cwd: str) -> Context:
    root = Path(cwd).resolve()
    entries: list[str] = []

    try:
        for path in sorted(root.iterdir(), key=lambda p: (p.is_file(), p.name.lower())):
            suffix = "/" if path.is_dir() else ""
            entries.append(path.name + suffix)
    except FileNotFoundError:
        entries.append("[cwd not found]")

    return Context(
        cwd=str(root),
        entries=entries,
    )
