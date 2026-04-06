from __future__ import annotations

from dataclasses import dataclass


@dataclass(slots=True)
class Task:
    preset: str
    user_input: str
    cwd: str = "."
    allow_apply: bool = False
    model: str | None = None
