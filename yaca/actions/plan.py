from __future__ import annotations

from yaca.types import Preset


PRESET = Preset(
    name="plan",
    summary="understand the task and produce a concrete execution plan",
    system_prompt=(
        "You are in plan mode. Do not rush into editing. "
        "Understand requirements, inspect structure, and produce a clear plan."
    ),
    read_only=True,
)
