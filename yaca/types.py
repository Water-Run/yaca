from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(slots=True)
class Preset:
    name: str
    summary: str
    system_prompt: str
    read_only: bool = True


@dataclass(slots=True)
class Context:
    cwd: str
    entries: list[str] = field(default_factory=list)


@dataclass(slots=True)
class RunResult:
    ok: bool
    message: str
