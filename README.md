# yaca — Yet Another Coding Agent

[中文](README-zh.md)

yaca is a general-purpose AI agent for the terminal that runs on old
machines. Windows XP, Server 2008, CentOS 7: places where today's agents
won't even start.

Put it on a USB stick, plug it into the machine that's misbehaving, and
ask. There's nothing to install. It can write code over a long session
too, but it's built for the everyday job of walking up to a system and
fixing something.

> [!NOTE]
> yaca isn't released yet. The core works; target qualification pending on
> the three platforms below.

## Why yaca

**It runs where others don't.** Most current coding agents need Node.js,
Python or a recent OS, and many won't run on anything older than Windows 10
1809. yaca goes back to Windows XP SP3. It brings its own HTTPS client and
certificate list, so an old system's outdated TLS doesn't stop it from
reaching the model.

**It's portable.** yaca is a single executable. Settings and history live in
a `__yaca__` folder right next to it, wherever you start it from, so the
whole thing moves with the USB stick.

**It's simple.** One conversation, one agent, one tool at a time. It asks
before it writes, deletes or runs anything, and shows you what it's about
to do.

| Platform | Oldest system |
|---|---|
| Windows 32-bit (x86) | Windows XP SP3 |
| Windows 64-bit (x86_64) | Windows 7 SP1 |
| Linux x86_64 | CentOS 7 (glibc 2.17) |

## Editions

Each platform comes in three sizes. The yaca inside is identical; only the
extra tools differ.

| Edition | Contents | Good for |
|---|---|---|
| **clean** | `yaca` only | Machines that already have the tools you need |
| **std** | + Python 2.7, SSH/SCP/SFTP, curl, 7-Zip | Most troubleshooting (recommended) |
| **full** | + Git, Python 3, compilers, SQLite, jq and more | Fixing and building code on a bare machine |

The extra tools sit in a `tools/` folder next to yaca. yaca tells the agent
they're there; it doesn't need them to start. Lua 5.5 is built into yaca
itself, in every edition.

## Getting started

Unzip anywhere you can write to, then run it:

```bat
C:\yaca\yaca.exe
```

The first run walks you through connecting a model. yaca speaks the
OpenAI Chat Completions and Anthropic Messages APIs, so most providers and
local servers work. You'll need:

- the full endpoint URL (including the API path, not just the host name)
- the model name, for a model that supports tool calling
- an API key, if your provider uses one

Then open a folder and talk to it:

```bat
C:\yaca\yaca.exe C:\work\broken-service
```

Try "why won't this service start?" or "free up space on drive D". Step-by-step
guides: [Windows](release/WINDOWS-QUICKSTART.md) ·
[Linux](release/LINUX-QUICKSTART.md).

## What the agent can do

It has nine tools: `list`, `read`, `search`, `write`, `patch`, `rename`,
`delete`, `exec` (run a command) and `lua` (run Lua code).

What it may do without asking depends on the permission profile:

| Profile | Read | Write / delete | Run commands | Outside the folder |
|---|---|---|---|---|
| **Std** (default) | yes | asks | asks | asks |
| **Readonly** | yes | no | no | no |

> [!IMPORTANT]
> A command or Lua script runs with your own user rights, like any program
> you start yourself. yaca asks before running one but doesn't sandbox it.
> Read the command before you approve it.

## In the chat

Type normally to give a task. Commands start with a dot:

| Command | |
|---|---|
| `.help` | All commands |
| `.ask` | Ask a quick question without tools and without changing the task |
| `.multiline` | Enter several lines at once |
| `.cancel` | Stop the current turn |
| `.status` | Current conversation, model and settings |
| `.model` | Switch model |
| `.context` | Switch to another saved conversation |
| `.compact` | Summarize the history to save space |
| `.quit` | Exit |

Every conversation is saved automatically. `.status` shows its short hash;
`yaca --continue <hash>` picks it up again later.

<details>
<summary><b>Command-line options</b></summary>

| Command | |
|---|---|
| `yaca [folder]` | Start a chat in a folder (default: current folder) |
| `yaca --continue <name or hash>` | Continue a saved conversation |
| `yaca --context-repl recent` | Browse, rename, delete or export conversations |
| `yaca --model-repl` | Add, edit or test models |
| `yaca --config-repl` | Edit other settings, or repair a broken config |
| `yaca --export <hash>` | Print a conversation as Markdown |
| `yaca --self-test` | Check that this machine and your model work |
| `yaca --status` | Show configuration status without opening a chat |
| `yaca --lua ...` | Run the built-in Lua 5.5 interpreter |
| `yaca --help [topic]` | Help |

On Windows, `/h`, `/c` and the other short forms also work.

</details>

## Settings and data

Everything lives in `__yaca__` next to the executable:

- `config.ini` holds models, permissions and network settings. Edit it
  with `--model-repl` and `--config-repl`, or by hand. A proxy goes under
  `[Network]` as `ProxyUrl`.
- `CONTEXT/` holds saved conversations, one file each.

To upgrade, quit yaca, back up `__yaca__`, and replace the executable.
There's no auto-update.

## Not included

No web UI, image or audio input, MCP, plugins, sub-agents, telemetry or
automatic updates. yaca is a terminal program and stays small.

## Development

Development notes (in Chinese) are in [.develope-docs/](.develope-docs/),
starting with [the current state](.develope-docs/CURRENT-STATE.md). Run the
tests from the repository root:

```sh
bash .tools/run_with_resource_guard.sh bin/lua55 test/run.lua
```

## License

[GPL v3](LICENSE).
