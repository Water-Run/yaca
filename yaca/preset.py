from __future__ import annotations

from yaca.presets import PRESETS
from yaca.types import Preset


def get_preset(name: str) -> Preset:
    key = name.strip().lower()
    if key in PRESETS:
        return PRESETS[key]

    available = ", ".join(sorted(PRESETS))
    raise SystemExit(f"unknown preset: {name!r}. available: {available}")
