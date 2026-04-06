from __future__ import annotations

from yaca.presets.analyze import PRESET as ANALYZE
from yaca.presets.build import PRESET as BUILD
from yaca.presets.debug import PRESET as DEBUG
from yaca.presets.design import PRESET as DESIGN
from yaca.presets.plan import PRESET as PLAN


PRESETS = {
    "debug": DEBUG,
    "build": BUILD,
    "plan": PLAN,
    "analyze": ANALYZE,
    "design": DESIGN,
}
