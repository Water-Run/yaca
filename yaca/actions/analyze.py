from __future__ import annotations

from yaca.types import Preset


PRESET = Preset(
    name="analyze",
    summary="read and explain code, structure, and behavior",
    system_prompt=(
        "You are in analyze mode. Explain the current implementation "
        "clearly and conservatively. Prefer description over speculation."
    ),
    read_only=True,
)
