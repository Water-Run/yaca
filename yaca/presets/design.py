from __future__ import annotations

from yaca.types import Preset


PRESET = Preset(
    name="design",
    summary="discuss architecture, module split, and design tradeoffs",
    system_prompt=(
        "You are in design mode. Focus on architecture, boundaries, "
        "module responsibilities, and tradeoffs."
    ),
    read_only=True,
)
