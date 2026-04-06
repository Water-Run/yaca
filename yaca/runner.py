from __future__ import annotations

from yaca.context import collect_context
from yaca.preset import get_preset
from yaca.prompt import build_prompt
from yaca.task import Task
from yaca.types import RunResult


def run_once(task: Task) -> int:
    preset = get_preset(task.preset)
    context = collect_context(task.cwd)
    prompt = build_prompt(task, preset, context)

    # 当前仅做本地骨架演示，不实际调用模型。
    result = RunResult(
        ok=True,
        message=(
            f"[preset] {preset.name}\n"
            f"[mode] {'apply' if task.allow_apply else 'read-only'}\n"
            f"[cwd] {task.cwd}\n\n"
            f"{prompt}"
        ),
    )

    print(result.message)
    return 0 if result.ok else 1
