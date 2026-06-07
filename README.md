# yaca: Yet Another Coding Agent

[中文](./README-zh.md)

`yaca` is a simple and basic Coding Agent, open-sourced under the `GPL v3` license on [GitHub](https://github.com/Water-Run/yaca).
`yaca` is developed with `lua` + `c`. It is small and straightforward, but highly compatible -- it can run well on legacy systems such as Windows XP or CentOS 7, and works out of the box.

> Tested on: `Windows XP(VM)`, `Windows 7(VM)`, `React OS(VM)`, `Cent OS 7`, `Windows 11`, `Fedora 44`, `Debian 13`

## Installation

Download the archive for your system from [GitHub Release](), then extract it.
Run `INSTALL.bat` or `install.sh`, and follow the guide.
After installation, you can run `yaca /v` to verify it. It should output:

```cmd
yaca v26.01
Yet Another Coding Agent.
```

Use `yaca /h` for help.

> Do not manually modify the contents of the `_yaca_` directory under the installation directory.

## Basics

### Configuration File

### Context Mechanism

## Before Use

## Command Overview

Running `yaca` directly will enter the TUI in the current directory. The `yaca` binary accepts the following parameters:

* `/h` / `/help`: Show help
* `/v` / `/version`: Show version
* `/c` / `/config`: Show configuration
* `/r` / `/reset`: Reset
* `/icc` / `/interactive-config-changer`: Start the interactive configuration changer
* `/dc` / `/dir-context`: Show the context list under the current directory
* `/gc` / `/global-context`: Show the global context list
* `/st` / `/self-test`: Run self-test

When using the `TUI`, you can invoke commands with the `.` command form. These include:

* `.quit`: Exit the program
* `.context`: Switch between available contexts under the current directory
* `.archive`: Archive the current context
* `.ping`: Check model connectivity
* `.index`: Override the name of the current context
* `.export`: Export the current context in Markdown format
