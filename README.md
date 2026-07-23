# yaca: Yet Another Coding Agent

[中文](./README-zh.md)

`yaca` is a simple, single-agent Coding Agent, open-sourced under the `GPL v3` license on [GitHub](https://github.com/Water-Run/yaca).  
Unlike many heavier Coding Agents, `yaca` is written in `lua` and runs well on legacy systems such as Windows XP or CentOS 7, out of the box.

## Installation

Download the archive for your system from [GitHub Release](https://github.com/Water-Run/yaca/releases), then extract it.  
Run `INSTALL.bat` or `install.sh`, and follow the guide.  
After installation, you can run `yaca --version` to verify it. It should output:

```cmd
yaca v0.1.0
Yet Another Coding Agent.
```

Use `yaca --help` for help.  
As a Coding Agent, configuring a model is required. Use `yaca --model-repl` to enter model management, then choose `Add Model` to add a model. Built-in quick presets:

- `DeepSeek`  
- `MiniMax`(`Token Plan China`, `Token Plan Global`, `API China`, `API Global`)  
- `MiMo`(`Token Plan China`, `Token Plan Singapore`, `Token Plan Europe`, `API`)  
- `Zhipu GLM`(`Coding Plan China`, `Coding Plan Global`, `API`)  
- `Kimi`(`Code`, `API`)  
- `Qwen`  
- `OpenAI`  
- `Anthropic`  
- `Gemini`  
- `Grok`  
- `Poe`  
- `Ollama`  

> Do not manually modify internal files under `__yaca__` except through documented configuration entry points. Its final user-data or portable location is still being designed.

## Configuration

`yaca` uses `config.ini` under `__yaca__` as its configuration file.  
The file is heavily commented. You may edit it by hand, then run `yaca --self-test`. Use `yaca --show-config` to print the config, and `yaca --reset-config` to restore defaults.  
The preferred way to change settings is `yaca --interactive-config-changer`. For models, use `yaca --model-repl`.  
The first model entry in the config file is the default when entering a session. A context keeps the last model used before exit; if that model is no longer valid, it falls back to the default. In a session, switch models with `.model`.

## Context Mechanism

`yaca` stores each context as a `[name].xml` file under `__yaca__/CONTEXT/`, in a tree that mirrors the corresponding path on disk. For example, a Windows context may be stored as `CONTEXT/C/Program Files/我的任务.xml`.

The hash input is the logical path from the `CONTEXT` root, with a leading `/`, `/` separators, and the XML filename included. The example above uses exactly `/C/Program Files/我的任务.xml` to compute a fixed 16-character hash. yaca does not store a permanent context ID: a rename or path change recomputes the hash in real time and immediately invalidates the old hash. Context lists and hash lookups are derived from the current XML tree.

A context XML contains the complete conversation, log-related information, session-level parameters, and their metadata. Use `yaca --dir-context` to list contexts under the current directory, and `yaca --global-context` for the global list.

`yaca --continue <selector>` accepts an exact context name or a fixed 16-character hash. Resume, rename, and delete entry points share one resolver: it starts at the mirror location for the current directory, then expands outward through recursive ancestor scopes to the `CONTEXT` root. Distance wins first; within one search scope, an exact name wins over a hash. The resolver checks both in one pass and stops after the current scope yields a conclusive result. `AutoJumpToDir` separately controls whether yaca changes the working directory after resolution.

For simpler management, use interactive `yaca --manage-context` to browse the directory tree, search, select and connect, rename, delete, and refresh. It shares the same path, hash, and safety rules as the command-line interface.

## Permission Mechanism

Permission groups live under `Permission` in the config. Three presets are provided: `Std`, `TrustMeBro`, and `Readonly`. `Cautious` is not a separate permission mode; cautious review is controlled by the default `DoubleCheck` switch and may be overridden for the current session with `.cautious`. Names are customizable and do not by themselves define behavior.
As with models, the first permission entry in the config is the default when entering a session. A context keeps the last permission used before exit; if that permission is no longer valid, it falls back to the default. In a session, switch permissions with `.permission`.

## Command Overview

The primary invocation is `yaca [directory]`. Bare `yaca` is exactly equivalent to `yaca .`: both enter the TUI with the current directory as the initial workspace location. `yaca <directory>` starts from the specified directory. The `yaca` binary also accepts:

- `--help` / `-h`(Unix) / `/h`(Windows): Show help  
- `--version` / `-v`(Unix) / `/v`(Windows): Show version  
- `--show-config` / `-sc`(Unix) / `/sc`(Windows): Show configuration  
- `--reset-config` / `-rc`(Unix) / `/rc`(Windows): Reset configuration  
- `--interactive-config-changer` / `-icc`(Unix) / `/icc`(Windows): Interactive configuration changer  
- `--dir-context` / `-dc`(Unix) / `/dc`(Windows): List contexts under the current directory  
- `--global-context` / `-gc`(Unix) / `/gc`(Windows): List global contexts  
- `--delete-context` / `-dc`(Unix) / `/dc`(Windows): Delete a context  
- `--rename-context` / `-rc`(Unix) / `/rc`(Windows): Rename a context  
- `--manage-context` / `-mc`(Unix) / `/mc`(Windows): Browse, search, select, rename, and delete contexts
- `--self-test` / `-st`(Unix) / `/st`(Windows): Run self-test. When an LLM is available, a deeper LLM-backed check may run.  
- `--continue` / `-c`(Unix) / `/c`(Windows): Resume a session from a context  
- `--set-default-permission` / `-sdp`(Unix) / `/sdp`(Windows): Set the default permission  
- `--set-default-model` / `-sdm`(Unix) / `/sdm`(Windows): Set the default model  
- `--model-repl` / `-mr`(Unix) / `/mr`(Windows): Model add / test / delete REPL  

In the TUI, invoke commands with a leading `.`:

- `.quit`: Exit the program  
- `.context`: Switch contexts. Bare `.context` opens the browser; `.context <name-or-16-character-hash>` uses the common resolver
- `.archive`: Archive the current context (then start a clean session). `.archive rename` also triggers auto-rename  
- `.ping`: Check model connectivity. Defaults to the current model, or `.ping <model-name>` for another  
- `.index`: Override the current context name (auto or manual). `.index <name>` renames immediately  
- `.compact`: Trigger context compaction  
- `.model`: Switch model. Bare `.model` opens a menu, or `.model <name>` switches directly  
- `.permission`: Switch permission. Bare `.permission` opens a menu, or `.permission <name>` switches directly  
- `.cautious`: Change the current session's `DoubleCheck` override; the override is stored in the context XML
- `.status`: Status, including the 16-character context hash computed from the current logical path
- `.delete`: Delete this conversation's context  
