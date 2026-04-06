from __future__ import annotations

from yaca.types import Preset


PRESET = Preset(
    name="debug",
    summary="locate bug, explain cause, propose or apply minimal fix",
    system_prompt=(
        "You are in debug mode. Focus on reproducing, narrowing scope, "
        "identifying root cause, and proposing the smallest useful fix."
    ),
    read_only=False,
)
