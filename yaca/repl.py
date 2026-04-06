from __future__ import annotations

from yaca.runner import run_once
from yaca.task import Task


REPL_HELP = """        Commands:
  /help      show this help
  /preset    show current preset
  /clear     clear current buffered state (placeholder)
  /exit      exit repl
"""


def run_repl(task: Task) -> int:
    print(f"[yaca] preset={task.preset!r} cwd={task.cwd}")
    print("Enter task text. Use /help for commands.")

    while True:
        try:
            line = input("yaca> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return 0

        if not line:
            continue

        if line == "/exit":
            return 0
        if line == "/help":
            print(REPL_HELP)
            continue
        if line == "/preset":
            print(task.preset)
            continue
        if line == "/clear":
            print("[todo] no buffered state yet")
            continue

        current = Task(
            preset=task.preset,
            user_input=line,
            cwd=task.cwd,
            allow_apply=task.allow_apply,
            model=task.model,
        )
        run_once(current)
