from __future__ import annotations

from yaca.task import Task
from yaca.types import Context, Preset


def build_prompt(task: Task, preset: Preset, context: Context) -> str:
    parts: list[str] = []

    parts.append("=== SYSTEM ===")
    parts.append(preset.system_prompt.strip())

    parts.append("")
    parts.append("=== TASK ===")
    parts.append(task.user_input or "(empty)")

    parts.append("")
    parts.append("=== CONTEXT ===")
    parts.append(f"cwd: {context.cwd}")
    parts.append("entries:")
    for item in context.entries[:20]:
        parts.append(f"- {item}")

    return "\n".join(parts)
