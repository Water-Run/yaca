# YACA - Yet Another Coding Agent

*[中文](./README-zh.md)*

`yaca` is a semi-automatic, command-line coding assistant tool. Semi-automatic means that, unlike `OpenCode` and `ClaudeCode`, `yaca` requires more involvement from you.
The development of `yaca` stems from personal Vibe Coding experience. The motivation behind its creation is that fully automated Coding Agents tend to consume a large number of conversation turns on parts unrelated to the current task — such as problem analysis and toolchain invocations. This leads to several times more token consumption, while squeezing the context window, and the completed tasks often don't align that well with what you actually need.
`yaca` is built on the belief that: more human involvement, less token consumption, better task completion.

## Installation

`yaca` is published on [PyPi](). Install it using `pipx`:

```bash
pipx install yaca
```

Verify the installation:

```bash
yaca --version
```
