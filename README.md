# yaca: Yet Another Coding Agent

[中文](./README-zh.md)

`yaca` is a simple and basic coding agent, open-sourced under the `GPL v3` license on [GitHub](https://github.com/Water-Run/yaca).
`yaca` is developed with `Lua` + `C`. It is concise and lightweight, while offering strong compatibility — it runs well on legacy systems such as Windows XP and CentOS 7, and works out of the box.

> Tested on: `Windows XP (VM)`, `Windows 7 (VM)`, `CentOS 7`, `Windows 11`, `Fedora 44`

## Installation

Download the `.zip` package for your system from [GitHub Releases](), then extract it.
Run `INSTALL.bat` or `INSTALL.sh`.
After installation, verify it in the terminal:

```cmd
yaca /v
```

If the command prints the expected output, the installation is complete.

## Source Layout

- `src/c/app`: C entry points.
- `src/c/core`: C runtime modules.
- `src/c/include`: shared C headers.
- `src/lua`: Lua agent scripts.
