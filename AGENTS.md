# AGENTS

## Current reality (do not assume a working CLI yet)
- This repo is an early scaffold; several core files are placeholders: `yaca/cli.py`, `yaca/main.py`, `yaca/actions/operate.py`, `yaca/actions/study.py`.
- `pyproject.toml` is currently empty, so packaging metadata, scripts, and tool config are not defined.
- There are no test files or CI workflows in the repo at the moment.

## Verified architecture
- Main execution flow is `Task` -> `run_once()` -> `get_preset()` + `collect_context()` -> `build_prompt()` -> print result (`yaca/task.py`, `yaca/runner.py`, `yaca/preset.py`, `yaca/context.py`, `yaca/prompt.py`).
- Preset registry lives in `yaca/actions/__init__.py`; preset definitions are in `yaca/actions/*.py`.
- `DEFAULT_PRESET` is `"plan"` in `yaca/config.py`.

## Critical gotcha
- `yaca/actions/__init__.py` imports `yaca.actions.build`, but that module does not exist; the file present is `yaca/actions/implement.py` (with `name="build"`).
- As a result, importing presets fails now (`python -c "import yaca.actions"` raises `ModuleNotFoundError`). Fix this mismatch before relying on any preset-driven flow.

## Working style for future sessions
- Treat docs as aspirational unless backed by code/config; prefer executable truth from Python modules.
- When adding new behavior, wire entrypoints first (`cli.py`/`main.py`) and keep preset module names synchronized with imports.
