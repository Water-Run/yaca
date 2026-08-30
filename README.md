# yaca: Yet Another Coding Agent

[中文](./README-zh.md)

yaca is the design for a simple, single-agent terminal Coding Agent, licensed under GPL v3.

> **Project status (2026-08-30): platform-independent core implemented through M9; controller closure and target qualification pending.** No target archive has qualified for release. Everything below describes the implemented v0.1 contract; target-specific behavior remains unqualified until it passes independently on Win32 x86, Win64 x86_64, and Linux x86_64. Gate A/B remain passed and Release Gate R remains closed.

## Supported release targets

v0.1 is planned as exactly three independently built and qualified portable archives:

- Win32 x86: Windows XP SP3 through Windows 11;
- Win64 x86_64: Windows 7 SP1 through Windows 11;
- Linux x86_64: CentOS 7 is the minimum hard baseline.

Each archive embeds Lua 5.5 and does not depend on a system Lua installation. Windows archives contain `yaca.exe`, `Install.cmd`, `README.txt`, `LICENSE`, and `docs/`; Linux uses `yaca` and `Install.sh` with the same outer shape. The thin install helper may add the extracted directory to `PATH`; it does not copy the program or create an install database.

The durable data root is always `__yaca__` next to the actual executable, regardless of the caller's current directory. v0.1 has no built-in updater or code-signing promise. There is no downloadable or verified archive yet.

## Product shape

- One terminal UI, one active Context, one active main turn, and serial tools.
- One workspace root per Context. It is derived from the Context XML's parent in the `__yaca__/CONTEXT/` mirror tree; XML cannot override it.
- Long-lived user facts are limited to `__yaca__/config.ini` and one complete XML per Context. There is no persistent WAL, index database, standalone log, backup history, trash, or general undo system.
- Two Model adapters are in scope: `openai-chat` and `anthropic-messages`. A Model is an explicit full connection record; yaca never silently switches to another Model after failure.
- A new chat remains an in-memory unsaved draft until its first main message. That message must create and durably publish the initial XML before any Model request or side effect.

The internal Context XML is versioned yaca storage, not a stable third-party API. Export is the human/tool interoperability path.

## Configuration and safety

The complete INI is validated as one typed generation. Every new top-level main or side turn observes the whole file; an invalid, unreadable, or half-written candidate blocks the new turn instead of falling back silently. A turn and all of its retries, tools, reviews, and compaction work keep the immutable generation admitted with that turn.

The distribution defines two Permission profiles:

| Profile | Read | Write | Delete | Shell | OutsideWorkspace |
| --- | --- | --- | --- | --- | --- |
| Std (default) | allow | confirm | confirm | confirm | confirm |
| Readonly | allow | deny | deny | deny | deny |

The fixed Agent tool set is `list`, `read`, `search`, `write`, `patch`, `rename`, `delete`, and `exec`. Raw `exec` is governed by the broad `Shell` capability; yaca does not claim to infer or sandbox its filesystem/network effects from command text. Permission names, descriptions, and prompts never grant capabilities.

`DoubleCheck` controls optional high-risk action review and mandatory finish review when enabled. `.cautious [status|on|off|toggle|reset]` changes only the current Context override; it is not a Permission profile. Before the first message it changes only the unsaved in-memory draft. In a saved Context the override and refreshed ModelView are published atomically, the Runtime adopts their exact receipt, and the new value applies at the next turn without changing the active turn's immutable configuration snapshot.

## Contexts

Context files live in a mirror tree such as `__yaca__/CONTEXT/C/Program Files/My Task.xml`. The current logical path, including the XML filename, produces a displayed 16-character uppercase hexadecimal hash. There is no permanent Context ID: rename or rebind changes the path and hash immediately.

Opening history is always explicit. A short name selects the first usable match by the specified scope/distance order; a hash is the precise selector and must be unique. Rename, rebind, permanent delete, import mapping, and metadata changes reverify the selected target. A live writer blocks another process from reading the XML body or mutating it; stale locks are never broken by age alone.

`--continue` resolves and reverifies one exact target, acquires its writer, and currently requires invocation from the Context's recorded workspace. It restores the durable event/config/ModelView and identifier waterlines into an Idle Agent; it never replays unfinished work automatically. Unfinished turns, active queue items, unresolved operations or tools, unknown terminal outcomes, and pending compaction require explicit recovery instead. Cross-workspace continuation is refused with a typed confirmation requirement until an explicit confirmation/rebind controller is implemented.

Within chat, `.context` without a selector shows a bounded recent list. `.context <selector>` first freezes the verified path and precise hash, closes the current owner only when its queue, side lane, approval, and compaction state are safe, then recomposes and reopens by that hash alone. A post-close race is fatal for that invocation; it never falls back to a replacement short-name match. This switch is also limited to the recorded workspace until explicit cross-workspace confirmation exists.

Each interactive coordinator error receives a process-local `error-N` identity. `.details` shows the newest retained error and `.details error-N` selects one explicitly. The fixed ring retains at most 64 sanitized code/message/suggestion records; expired identities fail closed, and raw exception objects, Tool bodies, and transport payloads are not retained by this surface.

## Implemented command grammar

These spellings are implemented in the source tree; no downloadable target-qualified executable is available yet:

```text
yaca [directory]
yaca --help [topic]                 (-h, Windows /h)
yaca --version                      (-v, Windows /v)
yaca --self-test [options]          (-st, Windows /st)
yaca --model-repl                   (-mr, Windows /mr)
yaca --config-repl                  (-cfg, Windows /cfg)
yaca --context-repl recent|full     (-ctx, Windows /ctx)
yaca --continue <selector>          (-c, Windows /c)
yaca --export [selector]            (-ex, Windows /ex)
yaca --status                       (-stt, Windows /stt)
```

Bare `yaca` is exactly `yaca .`. `--` ends option parsing, so a directory beginning with `-` remains expressible. Linux never treats `/...` as an option. Non-TTY self-test Stage 2 or 3 requires the explicit current-invocation flag `--i-accept-online-self-test`; otherwise it performs zero Model requests and fails closed.

Chat text fallbacks are `.queue` (`list|delete|move|edit|clear`), `.immediate`, `.side`, `.multiline`, `.cancel`, `.cautious`, `.model`, `.context`, `.status`, `.help`, `.details`, `.prompt`, `.compact`, and `.quit`. They project the same semantic actions as terminal shortcuts and do not create a remote/headless controller.

## Explicitly out of scope for v0.1

There is no Web UI, image/audio input, transcription, TTS, public remote/headless API, MCP, plugin/hook/skills runtime, sub-agent, Context branching, multi-root Context, telemetry, diagnostic upload, built-in update, general undo, or direct HTTP Agent tool. These exclusions must have zero surface in configuration, help, schemas, runtime, dependencies, and release archives.

Future local Web product lines are design reservations only; they do not authorize a Web component in v0.1.

## Development documents

Start with the [current state](.develope-docs/CURRENT-STATE.md), [Gate A/B/R audit](.develope-docs/GATE-AUDIT-2026-08-29.md), [implementation plan](.develope-docs/IMPLEMENTATION-PLAN.md), [machine contracts](.develope-docs/contracts/README.md), and [technical proof backlog](.develope-docs/TECHNICAL-PROOF-BACKLOG.md). From the repository root, run the full coding-readiness check with:

```sh
bash .tools/run_coding_readiness.sh
```

The readiness and heavyweight proof entrypoints acquire one per-user yaca test
lock and fail with exit 75 before starting when effective host/cgroup memory,
load, or Linux memory pressure is unsafe. Run an isolated full Lua suite through
the same guard instead of invoking it unguarded:

```sh
bash .tools/run_with_resource_guard.sh bin/lua55 test/run.lua
```
