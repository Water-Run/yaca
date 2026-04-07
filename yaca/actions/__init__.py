from __future__ import annotations

from yaca.actions.analyze import PRESET as ANALYZE
from yaca.actions.build import PRESET as BUILD
from yaca.actions.debug import PRESET as DEBUG
from yaca.actions.design import PRESET as DESIGN
from yaca.actions.plan import PRESET as PLAN


PRESETS = {
    "debug": DEBUG,
    "build": BUILD,
    "plan": PLAN,
    "analyze": ANALYZE,
    "design": DESIGN,
}
