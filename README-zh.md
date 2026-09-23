# yaca — Yet Another Coding Agent

[English](README.md)

yaca 是一个通用终端 Agent。一个聊天界面、一个 Agent、同时只有一个 Context，工具一个接一个执行。写代码是常见工作，其他任务也同样。以 GPL v3 许可开源。

> **发行：** v0.1 为三个目标各提供一个便携压缩包。从 [Windows 首次使用](release/WINDOWS-QUICKSTART.md) 或 [Linux 首次使用](release/LINUX-QUICKSTART.md) 开始。真实的 XP SP3、Windows 7 SP1，以及裸机 CentOS 7 的断电检查不在这一版里。

## 支持的平台

三个压缩包，各自单独构建：

- Win32 x86：Windows XP SP3 至 Windows 11
- Win64 x86_64：Windows 7 SP1 至 Windows 11
- Linux x86_64：CentOS 7 是最低基线

每个包内嵌 Lua 5.5，不需要系统里的 Lua。Windows 的 zip 里有 `yaca.exe`、`Install.cmd`、`README.txt`、`LICENSE` 和 `docs/`。Linux 使用 `yaca` 和 `Install.sh`。安装脚本可以把解压目录加入 `PATH`。它不复制程序，也不建立安装数据库。

长期数据放在实际可执行文件旁边的 `__yaca__` 里，不随启动目录变化。v0.1 没有内建更新器，也不做代码签名。

## 工具与权限

Agent 的工具是固定的：`list`、`read`、`search`、`write`、`patch`、`rename`、`delete`、`exec`。`exec` 走较宽的 `Shell` 能力。yaca 不会从命令文本推断或沙箱化它对文件和网络的影响。

发行包带两套权限配置：

| 配置 | Read | Write | Delete | Shell | OutsideWorkspace |
| --- | --- | --- | --- | --- | --- |
| Std（默认） | allow | confirm | confirm | confirm | confirm |
| Readonly | allow | deny | deny | deny | deny |

权限名和提示只是在说明行为，本身不授予能力。工具的相对路径按当前 Context 的工作目录解析，并做同样的权限和保留目录检查。

## 配置

设置写在可执行文件旁边的 `__yaca__/config.ini`。模型适配器是 `openai-chat` 和 `anthropic-messages`。每个模型是一条明确的连接；请求失败时设计上不会改去另一个模型。

整份配置作为一份来校验：文件无效、读不了或只写了一半时，新的回合会停下来，而不是悄悄退回旧配置。正在进行的回合一直用它开始时的那份配置。

`yaca --config-repl` 为已有的有效 INI 打开离线编辑器。`list [页码]` 列出区段，`show General` 查看字段，`set General LogLevel` 会提示输入值，`unset <区段> <键>` 把字段恢复成默认。`preview` 看未保存的改动；`save config-edit-N` 保存并退出；`reset`、`reload`、`quit`、`cancel`、Esc 或 EOF 丢掉未保存的编辑。Key、ProxyUrl 和 AdapterOptions 用隐藏输入。文件无效时改为逐行修复草稿：`list`、`replace <行>`、`insert <行>`、`delete <行>`，然后 `preview`/`validate`，再用 `save config-repair-N` 保存。编辑器保留未改动的字节、注释、区段顺序、BOM 和换行；文件在外面被改过时，要先 reload 再保存。

`yaca --model-repl` 管理模型定义：`list [页码]`、`show <row-id>`、`set`/`unset <row-id> <键>`、`add`、`rename <row-id> <名称>`、`delete <row-id>`、`move <row-id> <位置>`，以及 `test <row-id>`。最后这个要在明确确认联网之后，才测试已保存的模型；编辑会清掉观察到的状态。`preview` 显示改动、新的默认模型，以及受影响的 Context；`save model-edit-N` 确认这份预览，并重新核对配置和 Context 身份。在 `--config-repl` 里模型只显示摘要，要到 `--model-repl` 里改。权限配置可以在那里改已有字段；新增、改名、删除或调整顺序请直接改 INI。

模型和权限的名字按不区分大小写匹配（只折叠 ASCII）；存下来的仍是你配置时的拼写。

## Context

每次对话存成 `__yaca__/CONTEXT/` 镜像树里的一份完整 XML，例如 `__yaca__/CONTEXT/C/Program Files/我的任务.xml`。路径会显示成 16 位大写十六进制哈希，选择时用它。没有永久的 Context ID：重命名或重新绑定后，路径和哈希马上改变。工作区根目录由 XML 在树里的位置决定，XML 自己改不了它。

打开历史都要显式操作。短名称按范围和距离挑第一个可用的匹配；哈希必须精确且唯一。打开记录在另一个工作区里的 Context 时，会同时显示两条路径，输入 `CONTINUE <哈希>` 后才继续。没做完的回合、队列里的项和待压缩的内容不会自动重放，需要明确恢复。已有写入者时，别的进程不能读或改这份 XML；锁也不会只因为放得久就被拆掉。

`yaca --continue <选择器>` 重新打开一个精确目标。`yaca --context-repl recent|full` 打开离线管理器：`list`、`inspect <选择器>`、`search <查询>`、`refresh`、`rename`、`set-auto-rename-disabled`、`delete [--yes]`（要求精确哈希）、`rebind`、`import`、`repair`、`export`、`select` 和 `quit`。会改数据的操作会再次核对目标，并要求按提示输入确认（`REBIND <哈希>`、`IMPORT <哈希>`、`REPAIR <哈希>`）。

Context XML 是 yaca 自己的版本化存储，不是给外部当稳定接口用的。交换数据走导出。

每个交互式协调错误在本进程里有一个 `error-N` 标识。`.details` 显示最新保留的一条，`.details error-N` 指定一条。环里最多留 64 条清理过的记录；过期标识会直接拒绝。

## 聊天

聊天用系统自带的行编辑：输入命令，按 Enter。新聊天在第一条 main 消息之前只是草稿；调用模型或做出改动之前，yaca 会先把 Context 写下来。文本命令有 `.queue`（`list|delete|move|edit|clear`）、`.immediate`、`.side`、`.multiline`、`.cancel`、`.cautious`、`.model`、`.context`、`.status`、`.help`、`.details`、`.prompt`、`.compact` 和 `.quit`。它们和终端快捷键是同一组动作。yaca 不提供远程或无界面控制器。

- `.side` 根据已提交的上下文回答，不调用工具，也不改当前任务。
- `.multiline` 逐行收集原文；`.submit` 提交任务，`.side` 提交旁路问题。`.show`、`.clear`、`.cancel` 用来查看、清空或放弃草稿；以 `..` 开头的行表示一个字面点号。
- `.cautious [status|on|off|toggle|reset]` 开关当前 Context 的高风险动作复查；打开 `DoubleCheck` 时，结束复查是必须的。这是 Context 上的覆盖，不是权限配置，从下一回合起生效。
- `.prompt [show|set|clear] [文本]` 查看或修改当前 Context 的提示词。`.prompt edit` 打开有长度限制的多行编辑器；用它显示的 `.save prompt-edit-N` 保存，用 `.cancel` 离开。改动从下一回合起生效。
- `.model` 最多列出 64 个已启用的模型，`.model <精确名称>` 选定一个。改动端点、凭据、协议或能力上限时会要求确认；空回答视为拒绝。密钥设计上不会显示出来，已保存的改动从下一回合起生效。
- `.status` 检查当前持有的 Context，显示哈希和有效的会话设置；Context 文件在磁盘上变了就会停下来。

## 命令行

解析器认识这些写法，每个发行包都带上对应的可执行文件：

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

裸 `yaca` 就是 `yaca .`。`--` 结束选项解析，所以以 `-` 开头的目录仍然可以写。在 Linux 上，以 `/` 开头的路径不会被当成选项。

- `--status` 报告当前这次运行和配置，不扫描历史，也不创建数据。
- `--export [选择器]` 输出核对过的 Context Markdown，不取得写入者，不恢复历史，也不调用模型。有效配置里登记过的密钥会在输出前被拒绝。需要 TTY。
- `--self-test` 的第 2、3 阶段使用正式的模型和传输。它们需要真实的交互 TTY，以及本次运行的 `--i-accept-online-self-test`；管道即使带了这个标志也不支持。在线探测不运行产品工具，也不修改配置，第 3 阶段的结果只供参考。

## v0.1 不做的事

不做 Web UI、图像或音频输入、转写、语音合成、公共的远程或无界面 API、MCP、插件/钩子/技能运行时、子 Agent、Context 分支、多根 Context、遥测、诊断上传、内建更新、通用撤销，以及直接的 HTTP Agent 工具。这些都不进入 v0.1 的配置、帮助、schema、运行时、依赖和发行包。本地网页界面也不在 v0.1 里。

## 开发

开发文档在 `.develope-docs/`，从[当前状态](.develope-docs/CURRENT-STATE.md)、[实施计划](.develope-docs/IMPLEMENTATION-PLAN.md)和[机读契约](.develope-docs/contracts/README.md)看起。在仓库根目录运行完整的编码就绪检查：

```sh
bash .tools/run_coding_readiness.sh
```

就绪检查会取得当前用户的测试锁；主机内存、负载或内存压力不安全时拒绝启动（退出码 75）。Lua 测试套件走同一道保护：

```sh
bash .tools/run_with_resource_guard.sh bin/lua55 test/run.lua
```

## 许可

[yaca 以 GPL v3 许可开源](LICENSE)。
