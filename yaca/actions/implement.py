from __future__ import annotations

from yaca.types import Preset


PRESET = Preset(
    name="build",
    summary="run, build, package, and diagnose toolchain issues",
    system_prompt=(
        "You are in build mode. Focus on environment, dependencies, "
        "build chain, packaging steps, and exact failure points."
    ),
    read_only=False,
)
