# yaca: Yet Another Coding Agent

[中文](./README-zh.md)

`yaca` is the design for a simple, single-agent Coding Agent, open-sourced under the `GPL v3` license on [GitHub](https://github.com/Water-Run/yaca). It targets Lua 5.5, Windows XP SP3 through Windows 11 on Win32 x86, and Linux x86_64 including CentOS 7.

> **Project status (2026-07-22): design phase.** There is no completed v0.1 binary or verified release yet. Platform support, installation, commands, presets, and examples below are design targets, not implemented behavior. Current decisions and unanswered design batches live in [`.develope-docs`](.develope-docs/README.md).

## Installation

The planned release unit is a platform-specific `.zip` built with the sibling `luainstaller` project. Packaging, installer entry points, and real-machine evidence remain design/release gates; the repository must not claim an archive is available before those gates pass.

The semantic `version` action is planned to identify a built release. Its exact top-level CLI spelling is still pending design decision `TU-18`; the target output shape is:

```cmd
yaca v0.1.0
Yet Another Coding Agent.
```

The product has semantic `help` and `model-repl` entrances. A usable Model connection is required before Agent chat can sample an LLM. The final protocol/preset list and exact commands remain pending decisions; no provider list in an older README is a compatibility promise.

> `__yaca__` is the logical data root used by the design. Its installed-versus-portable physical location is still pending. Do not infer an implemented layout from legacy repository resources.

## Configuration

The target design uses one complete INI under logical `__yaca__` plus explicit session overrides in each Context XML. Configuration inspection, reset, and interactive editing belong to the `config-repl` surface; Model lifecycle belongs to `model-repl`; the three-stage `self-test` is the explicit validation path.

Physical Model order selects the new-Context default. A Context records its selected Model and the historical connection snapshot; if the logical Model was renamed, removed, disabled, or changed incompatibly, yaca must show a runtime mapping/repair prompt. It must not silently fall back to another Model or endpoint. In-session Model switching is a semantic action whose final chat spelling is pending `TU-32`.

## Context Mechanism

The design stores each Context as a `[name].xml` file under `__yaca__/CONTEXT/`, in a tree that mirrors the corresponding path on disk. For example, a Windows Context may be stored as `CONTEXT/C/Program Files/我的任务.xml`.

The hash input is the logical path from the `CONTEXT` root, with a leading `/`, `/` separators, and the XML filename included. The example above uses exactly `/C/Program Files/我的任务.xml` to compute a fixed 16-character hash. yaca does not store a permanent context ID: a rename or path change recomputes the hash in real time and immediately invalidates the old hash. Context lists and hash lookups are derived from the current XML tree.

A context XML contains the complete conversation, log-related information, session-level parameters, and their metadata. The semantic `context-list` action enumerates contexts by scope; `context-repl` provides interactive browsing and management.

The semantic `continue(selector)` action accepts an exact context name or a fixed 16-character hash. Resume, rename, and delete entry points share one resolver: it starts at the mirror location for the current directory, then expands outward through recursive ancestor scopes to the `CONTEXT` root. Distance wins first; within one search scope, an exact name wins over a hash. The resolver checks both in one pass and stops after the current scope yields a conclusive result. The post-resolution working-directory policy remains pending decision `PJ-13`: options A/B retain the boolean `AutoJumpToDir`, while C replaces it with `ResumeDirectory=jump|ask|keep`.

For simpler management, use the interactive `context-repl` surface to browse the directory tree, search, select and connect, rename, delete, and refresh. It shares the same path, hash, and safety rules as the command-line interface.

## Permission Mechanism

Permission profiles live in the INI. `Std` is first in the planned distribution template and therefore the new-Context default; the final built-in capability matrices remain pending safety decisions. `Cautious` is not a separate Permission mode: cautious review is controlled by `DoubleCheck` and the current Context may override it through the semantic `.cautious` action. Names and descriptions never grant capabilities.

A Context records its selected Permission and historical effective snapshot. If the local profile was renamed, removed, or differs incompatibly, yaca must show a runtime mapping/repair prompt and remain fail-closed where required; it must not silently adopt the first profile. The chat spelling for Permission switching remains pending `TU-32`.

## Command Overview

The primary invocation is `yaca [directory]`. Bare `yaca` is exactly equivalent to `yaca .`: both enter the TUI with the current directory as the initial workspace location. `yaca <directory>` starts from the specified directory.

The product design also establishes semantic actions for `help`, `version`, `self-test`, `model-repl`, `config-repl`, `context-repl`, `context-list(scope)`, and `continue(selector)`. Decision `TU-18` still has to project these actions into an exact top-level grammar: flags, subcommands, or a mixed form, including any short aliases. Therefore action labels in this README are not executable command spellings yet. Earlier draft flag names and their conflicting short aliases are not part of the confirmed contract.

Chat also has semantic actions for status/help, queue/steer/side/cancel, Prompt and DoubleCheck overrides, Model/Permission/Context management, typed retry/recovery, and graceful exit. `TU-32` still decides the canonical dot-command namespace; conditional actions such as manual compaction exist only if their own upstream decision enables them. Older draft dot-command lists are not an executable or compatibility contract.
