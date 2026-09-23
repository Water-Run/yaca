# yaca — Yet Another Coding Agent

[English](README.md)

yaca 是一个能在老机器上跑的通用终端 AI Agent。Windows XP、Server 2008、
CentOS 7——如今的 Agent 在这些系统上连启动都做不到。

把它放进 U 盘，插到出问题的机器上，直接开问，什么都不用装。它也能陪你
长时间写代码，但它更擅长的是日常那种事：走到一台机器前，把问题修好。

> [!NOTE]
> yaca 还没有正式发布。核心功能已经可用，下面三个平台的目标资格验证待完成。

## 为什么是 yaca

**别人跑不了的地方，它能跑。** 现在的编程 Agent 大多要 Node.js、Python 或者
较新的系统，很多连 Windows 10 1809 都跑不起来。yaca 一路兼容到 Windows XP SP3。
它自带 HTTPS 客户端和证书列表，老系统的 TLS 再旧，也不影响连上模型。

**便携。** yaca 就一个可执行文件。配置和历史放在它旁边的 `__yaca__` 文件夹里，
不管从哪个目录启动都一样，所以整套东西跟着 U 盘走。

**简单。** 一个对话，一个 Agent，工具一次只跑一个。写入、删除、执行命令之前
都会先问你，并告诉你它打算做什么。

| 平台 | 最低系统 |
|---|---|
| Windows 32 位（x86） | Windows XP SP3 |
| Windows 64 位（x86_64） | Windows 7 SP1 |
| Linux x86_64 | CentOS 7（glibc 2.17） |

## 版本

每个平台分三档。里面的 yaca 完全相同，区别只在附带的工具。

| 档位 | 内容 | 适合 |
|---|---|---|
| **clean** | 只有 `yaca` | 机器上已经有你要用的工具 |
| **std** | + Python 2.7、SSH/SCP/SFTP、curl、7-Zip | 大多数排障场景（推荐） |
| **full** | + Git、Python 3、编译器、SQLite、jq 等 | 在一台什么都没有的机器上改代码、编译 |

附带工具放在 yaca 旁边的 `tools/` 文件夹里。yaca 会告诉 Agent 有哪些工具可用，
但启动并不依赖它们。Lua 5.5 直接内置在 yaca 里，三档都有。

## 开始使用

解压到任意有写权限的位置，然后运行：

```bat
C:\yaca\yaca.exe
```

第一次运行会引导你连接模型。yaca 支持 OpenAI Chat Completions 和
Anthropic Messages 两种接口，大多数服务商和本地模型服务都能用。你需要准备：

- 完整的接口地址（要包含 API 路径，不能只填域名）
- 模型名称，模型需要支持工具调用
- API key（服务商要求的话）

然后打开一个文件夹，开始对话：

```bat
C:\yaca\yaca.exe C:\work\broken-service
```

比如问它“这个服务为什么起不来？”或者“帮我清理一下 D 盘空间”。
分步指南：[Windows](release/WINDOWS-QUICKSTART.md) ·
[Linux](release/LINUX-QUICKSTART.md)。

## Agent 能做什么

它有九个工具：`list`、`read`、`search`、`write`、`patch`、`rename`、
`delete`、`exec`（执行命令）和 `lua`（运行 Lua 代码）。

哪些操作不用问你，由权限配置决定：

| 配置 | 读取 | 写入 / 删除 | 执行命令 | 工作目录以外 |
|---|---|---|---|---|
| **Std**（默认） | 允许 | 先问 | 先问 | 先问 |
| **Readonly** | 允许 | 不允许 | 不允许 | 不允许 |

> [!IMPORTANT]
> 命令和 Lua 脚本以你自己的用户权限运行，和你亲手启动的程序一样。yaca
> 运行前会问你，但不会把它关进沙箱。批准之前请看清命令。

## 聊天里

直接输入就是下达任务。命令以点开头：

| 命令 | |
|---|---|
| `.help` | 全部命令 |
| `.ask` | 顺手问个问题，不用工具，也不影响当前任务 |
| `.multiline` | 一次输入多行 |
| `.cancel` | 停止当前这一轮 |
| `.status` | 当前对话、模型和设置 |
| `.model` | 切换模型 |
| `.context` | 切换到另一个已保存的对话 |
| `.compact` | 压缩历史，节省上下文 |
| `.quit` | 退出 |

每个对话都会自动保存。`.status` 会显示它的短 hash，之后用
`yaca --continue <hash>` 接着聊。

<details>
<summary><b>命令行选项</b></summary>

| 命令 | |
|---|---|
| `yaca [文件夹]` | 在某个文件夹里开始对话（默认当前文件夹） |
| `yaca --continue <名称或 hash>` | 继续一个已保存的对话 |
| `yaca --context-repl recent` | 浏览、重命名、删除或导出对话 |
| `yaca --model-repl` | 添加、编辑或测试模型 |
| `yaca --config-repl` | 修改其他设置，或修复损坏的配置 |
| `yaca --export <hash>` | 把对话导出为 Markdown |
| `yaca --self-test` | 检查这台机器和你的模型是否正常 |
| `yaca --status` | 不进入聊天，查看配置状态 |
| `yaca --lua ...` | 运行内置的 Lua 5.5 解释器 |
| `yaca --help [主题]` | 帮助 |

在 Windows 上，`/h`、`/c` 等短写法也可以用。

</details>

## 设置和数据

所有东西都在可执行文件旁边的 `__yaca__` 里：

- `config.ini` 保存模型、权限和网络设置。可以用 `--model-repl`、
  `--config-repl` 修改，也可以手动编辑。代理写在 `[Network]` 的 `ProxyUrl`。
- `CONTEXT/` 保存对话，每个对话一个文件。

升级时先退出 yaca，备份 `__yaca__`，再替换可执行文件。没有自动更新。

## 不包含的功能

没有 Web 界面、图片或语音输入、MCP、插件、子 Agent、遥测和自动更新。
yaca 是一个终端程序，保持小巧。

## 开发

开发文档（中文）在 [.develope-docs/](.develope-docs/)，从
[当前状态](.develope-docs/CURRENT-STATE.md) 开始看。在仓库根目录运行测试：

```sh
bash .tools/run_with_resource_guard.sh bin/lua55 test/run.lua
```

## 许可证

[GPL v3](LICENSE)。
