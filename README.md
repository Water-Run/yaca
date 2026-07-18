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

> Do not manually modify the contents of the `_yaca_` directory under the installation directory.

## Configuration

`yaca` uses `config.ini` under `__yaca__` as its configuration file.  
The file is heavily commented. You may edit it by hand, then run `yaca --self-test`. Use `yaca --show-config` to print the config, and `yaca --reset-config` to restore defaults.  
The preferred way to change settings is `yaca --interactive-config-changer`. For models, use `yaca --model-repl`.  
The first model entry in the config file is the default when entering a session. A context keeps the last model used before exit; if that model is no longer valid, it falls back to the default. In a session, switch models with `.model`.

## Context Mechanism

`yaca` stores contexts as `[name].xml` files under `__yaca__`, in a tree that mirrors the corresponding paths on disk.  
A context file holds all metadata for the related conversation and can be used as a log. Each context has a display name and a hash derived from its directory. Use `yaca --dir-context` to list contexts under the current directory, and `yaca --global-context` for the global list.  
Use `yaca --continue [hash]` to jump to a conversation, including ones outside the current directory (when `AutoJumpToDir` is enabled). You can also use `yaca --continue <name>` to jump by name, but name lookup only applies to contexts under the current directory. If a name happens to equal a hash, the hash wins. `yaca --delete-context` deletes a context with the same resolution rules as `continue`; `yaca --rename-context` renames with the same rules.  
For simpler management, use interactive `yaca --manage-context` (list, delete, rename, and more).

## Permission Mechanism

Permission groups live under `Permission` in the config. Four presets are provided: `Std`, `Cautious`, `TrustMeBro`, and `Readonly`. Names are customizable and do not by themselves define behavior.  
As with models, the first permission entry in the config is the default when entering a session. A context keeps the last permission used before exit; if that permission is no longer valid, it falls back to the default. In a session, switch permissions with `.permission`.

## Command Overview

Running `yaca` directly enters the TUI in the current directory. The `yaca` binary accepts:

- `--help` / `-h`(Unix) / `/h`(Windows): Show help  
- `--version` / `-v`(Unix) / `/v`(Windows): Show version  
- `--show-config` / `-sc`(Unix) / `/sc`(Windows): Show configuration  
- `--reset-config` / `-rc`(Unix) / `/rc`(Windows): Reset configuration  
- `--interactive-config-changer` / `-icc`(Unix) / `/icc`(Windows): Interactive configuration changer  
- `--dir-context` / `-dc`(Unix) / `/dc`(Windows): List contexts under the current directory  
- `--global-context` / `-gc`(Unix) / `/gc`(Windows): List global contexts  
- `--delete-context` / `-dc`(Unix) / `/dc`(Windows): Delete a context  
- `--rename-context` / `-rc`(Unix) / `/rc`(Windows): Rename a context  
- `--manage-context` / `-mc`(Unix) / `/mc`(Windows): Context manager  
- `--self-test` / `-st`(Unix) / `/st`(Windows): Run self-test. When an LLM is available, a deeper LLM-backed check may run.  
- `--continue` / `-c`(Unix) / `/c`(Windows): Resume a session from a context  
- `--set-default-permission` / `-sdp`(Unix) / `/sdp`(Windows): Set the default permission  
- `--set-default-model` / `-sdm`(Unix) / `/sdm`(Windows): Set the default model  
- `--model-repl` / `-mr`(Unix) / `/mr`(Windows): Model add / test / delete REPL  

In the TUI, invoke commands with a leading `.`:

- `.quit`: Exit the program  
- `.context`: Switch among available contexts. Bare `.context` opens a menu; or `.context <global-hash>` / `.context <name-under-cwd>`  
- `.archive`: Archive the current context (then start a clean session). `.archive rename` also triggers auto-rename  
- `.ping`: Check model connectivity. Defaults to the current model, or `.ping <model-name>` for another  
- `.index`: Override the current context name (auto or manual). `.index <name>` renames immediately  
- `.compact`: Trigger context compaction  
- `.model`: Switch model. Bare `.model` opens a menu, or `.model <name>` switches directly  
- `.permission`: Switch permission. Bare `.permission` opens a menu, or `.permission <name>` switches directly  
- `.status`: Status (context usage, etc.)  
- `.delete`: Delete this conversation's context  
