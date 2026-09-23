# yaca — Yet Another Coding Agent

[中文](README-zh.md)

yaca is a general-purpose terminal agent. One chat, one agent, one Context at a time, and tools run one after another. Coding is a common job for it, and so are other tasks. Licensed under GPL v3.

> **Release:** v0.1 publishes a portable archive for each of the three targets. Start with the [Windows quickstart](release/WINDOWS-QUICKSTART.md) or the [Linux quickstart](release/LINUX-QUICKSTART.md). Real XP SP3, Windows 7 SP1, and bare-metal CentOS 7 power-loss checks are outside this release.

## Supported platforms

Three archives, each built on its own:

- Win32 x86: Windows XP SP3 through Windows 11
- Win64 x86_64: Windows 7 SP1 through Windows 11
- Linux x86_64: CentOS 7 is the hard minimum

Each archive embeds Lua 5.5 and doesn't need a system Lua. A Windows zip contains `yaca.exe`, `Install.cmd`, `README.txt`, `LICENSE`, and `docs/`. Linux uses `yaca` and `Install.sh`. The install helper can add the extracted directory to `PATH`. It doesn't copy the program or create an install database.

Durable data lives in `__yaca__` next to the actual executable, whatever directory you start from. v0.1 has no built-in updater and makes no code-signing promise.

## Tools and permissions

The agent tool set is fixed: `list`, `read`, `search`, `write`, `patch`, `rename`, `delete`, and `exec`. `exec` runs under the broad `Shell` capability. yaca doesn't infer or sandbox what a command does to files or the network.

Two permission profiles ship with the distribution:

| Profile | Read | Write | Delete | Shell | OutsideWorkspace |
| --- | --- | --- | --- | --- | --- |
| Std (default) | allow | confirm | confirm | confirm | confirm |
| Readonly | allow | deny | deny | deny | deny |

Permission names and prompts describe behavior; they don't grant capabilities by themselves. Relative tool paths resolve against the current Context workspace and keep the same permission and reserved-tree checks.

## Configuration

Settings live in `__yaca__/config.ini`, next to the executable. The model adapters are `openai-chat` and `anthropic-messages`. Each model is one explicit connection, and a failed request doesn't switch to another model.

The whole config file is validated as one unit: an invalid, unreadable, or half-written file blocks new turns instead of falling back silently, and a running turn keeps the configuration it started with.

`yaca --config-repl` opens an offline editor for an existing valid INI. `list [page]` lists sections, `show General` shows fields, `set General LogLevel` prompts for the value, and `unset <section> <key>` restores a field's default. `preview` shows pending changes; `save config-edit-N` saves and exits; `reset`, `reload`, `quit`, `cancel`, Esc, or EOF discard unsaved edits. Key, ProxyUrl, and AdapterOptions use hidden input. If the file is invalid, a private line-repair draft opens instead: `list`, `replace <line>`, `insert <line>`, `delete <line>`, then `preview`/`validate` and `save config-repair-N`. The editor preserves unmodified bytes, comments, section order, BOM, and line endings; external changes to the file require a reload before saving.

`yaca --model-repl` manages model definitions: `list [page]`, `show <row-id>`, `set`/`unset <row-id> <key>`, `add`, `rename <row-id> <name>`, `delete <row-id>`, `move <row-id> <position>`, and `test <row-id>` — the last checks a saved model after an explicit online confirmation, and edits clear the observed status. `preview` shows changes, the new default, and affected Contexts; `save model-edit-N` confirms the preview and rechecks configuration and Context identities. In `--config-repl`, models appear as summaries; edit them in `--model-repl`. Permission profiles support editing existing fields there — add, rename, delete, or reorder profiles by hand in the INI.

Model and permission names match case-insensitively (ASCII-only folding); stored data keeps the spelling you configured.

## Contexts

Each conversation is stored as one complete XML file in a mirror tree under `__yaca__/CONTEXT/` — for example `__yaca__/CONTEXT/C/Program Files/My Task.xml`. Its path produces a displayed 16-character uppercase hex hash, which is how you select it. There is no permanent Context ID: rename or rebind changes the path and the hash immediately. The workspace root is derived from where the XML sits in the tree; the XML itself can't override it.

Opening history is always explicit. A short name selects the first usable match by scope and distance; a hash selects exactly and must be unique. Opening a Context recorded in a different workspace displays both paths and requires `CONTINUE <hash>` before proceeding. Unfinished turns, queued items, and pending compaction aren't replayed automatically — they ask for explicit recovery. A live writer blocks other processes from reading or mutating the XML, and locks aren't broken by age alone.

`yaca --continue <selector>` reopens one exact target. `yaca --context-repl recent|full` opens the offline manager: `list`, `inspect <selector>`, `search <query>`, `refresh`, `rename`, `set-auto-rename-disabled`, `delete [--yes]` (asks for the exact hash), `rebind`, `import`, `repair`, `export`, `select`, and `quit`. Destructive actions reverify the target and ask for typed confirmation (`REBIND <hash>`, `IMPORT <hash>`, `REPAIR <hash>`).

Context XML is yaca's internal versioned storage, not a stable third-party API. Export is the interchange path.

Each interactive coordinator error gets a process-local `error-N` identity. `.details` shows the newest retained error, `.details error-N` selects one. The ring keeps at most 64 sanitized records; expired identities fail closed.

## Chat

The chat interface uses the host line editor: type a command, press Enter. A new chat stays a draft until the first main message; yaca writes the Context before it calls a model or makes a change. Text fallbacks cover `.queue` (`list|delete|move|edit|clear`), `.immediate`, `.side`, `.multiline`, `.cancel`, `.cautious`, `.model`, `.context`, `.status`, `.help`, `.details`, `.prompt`, `.compact`, and `.quit`. They mirror the terminal shortcuts. yaca doesn't offer a remote or headless controller.

- `.side` answers from committed context without tools and doesn't change the current task.
- `.multiline` collects literal lines; `.submit` sends a task and `.side` sends a side question. `.show`, `.clear`, and `.cancel` inspect, clear, or discard the draft; a line starting with `..` inserts a literal dot.
- `.cautious [status|on|off|toggle|reset]` toggles high-risk action review for the current Context; with `DoubleCheck` on, the finish review is mandatory. It's a Context override, not a permission profile, and applies from the next turn.
- `.prompt [show|set|clear] [text]` inspects or changes the current Context prompt. `.prompt edit` opens a bounded multiline editor; save with the `.save prompt-edit-N` command it shows, or leave with `.cancel`. Changes apply from the next turn.
- `.model` lists up to 64 enabled models, and `.model <exact-name>` selects one. Changes that alter the endpoint, credentials, protocol, or capability limits ask for confirmation; an empty answer denies. Secrets aren't displayed, and a saved change applies from the next turn.
- `.status` checks the owned Context, shows its hash and effective session settings, and stops if the Context file changed on disk.

## Command line

The parser recognizes these spellings, and each archive includes its executable:

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

Bare `yaca` is exactly `yaca .`. `--` ends option parsing, so a directory beginning with `-` stays expressible. On Linux, a path starting with `/` isn't treated as an option.

- `--status` reports the current invocation and configuration without scanning history or creating data.
- `--export [selector]` prints verified Markdown for a Context without opening a writer, recovering history, or calling a model. Registered secrets in a valid configuration are rejected before output. A TTY is required.
- `--self-test` stages 2/3 use the production model and transport. They need a real interactive TTY plus the current-invocation flag `--i-accept-online-self-test`; a pipe isn't supported even with the flag. Online probes don't run product tools or modify configuration, and stage 3 findings are advisory.

## Out of scope for v0.1

No Web UI, image/audio input, transcription, TTS, public remote/headless API, MCP, plugin/hook/skills runtime, sub-agents, Context branching, multi-root Contexts, telemetry, diagnostic upload, built-in update, general undo, or direct HTTP agent tool. v0.1 leaves them out of configuration, help, schemas, the runtime, dependencies, and the release archives. A local web interface isn't part of v0.1.

## Development

Development documents (Chinese) live in `.develope-docs/` — start from the [current state](.develope-docs/CURRENT-STATE.md), the [implementation plan](.develope-docs/IMPLEMENTATION-PLAN.md), and the [machine contracts](.develope-docs/contracts/README.md). From the repository root, run the full coding-readiness check with:

```sh
bash .tools/run_coding_readiness.sh
```

The readiness entrypoints take a per-user test lock and refuse to start (exit 75) when host memory, load, or memory pressure is unsafe. Run the Lua suite under the same guard:

```sh
bash .tools/run_with_resource_guard.sh bin/lua55 test/run.lua
```

## License

[yaca is licensed under GPL v3](LICENSE).
