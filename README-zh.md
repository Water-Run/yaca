# yaca: Yet Another Coding Agent

[English](./README.md)

yaca 是一款简单、单 Agent、terminal-only Coding Agent 的设计，以 GPL v3 许可开源。

> **项目状态（2026-08-30）：平台无关核心已实现至 M9；controller 收口和目标资格验证待完成。** 目前还没有任何目标发行包通过资格验证。下文描述已经实现的 v0.1 契约；Win32 x86、Win64 x86_64 与 Linux x86_64 的目标相关行为仍须分别验证。Gate A/B 保持通过，Release Gate R 仍关闭。

## 支持的发行目标

v0.1 计划只发布三个彼此独立构建、独立验收的便携 zip：

- Win32 x86：Windows XP SP3 至 Windows 11；
- Win64 x86_64：Windows 7 SP1 至 Windows 11；
- Linux x86_64：CentOS 7 是最低硬基线。

每个包嵌入 Lua 5.5，不依赖系统 Lua。Windows zip 根包含 `yaca.exe`、`Install.cmd`、`README.txt`、`LICENSE`、`docs/`；Linux 对应使用 `yaca` 与 `Install.sh`。薄安装脚本只可把解压目录加入 `PATH`，不复制程序，也不建立安装数据库。

长期数据根始终是实际 executable 相邻的 `__yaca__`，不随调用者 cwd 漂移。v0.1 没有内建更新器，也不承诺代码签名。目前尚无可下载或已验证的发行包。

## 产品形态

- 一套逐行 TUI、一个 active Context、一个 active main turn，工具全部串行。
- 每个 Context 恰好一个 workspace root；它由 XML 在 `__yaca__/CONTEXT/` 镜像树中的父目录解码，XML 字段不能覆盖。
- 长期用户事实只允许 `__yaca__/config.ini` 与每个 Context 的一个完整 XML。没有长期 WAL、索引数据库、独立日志、备份历史、trash 或通用 undo。
- 正式 Model adapter 只有 `openai-chat` 与 `anthropic-messages`。每个 Model 是显式完整连接记录；失败时不静默切换到另一 Model。
- 新 chat 在第一条 main 消息前只是内存草稿；必须先建立并 durable 发布初始 XML，之后才允许 Model 请求或副作用。

Context XML 是 yaca 内部版本化存储，不是稳定第三方 API；人类或其他工具的互操作主路径是 export。

## 配置与安全

主 INI 每次作为一个完整 typed generation 校验。每个新顶层 main/side turn 都观察整份文件；候选无效、不可读或半写时阻断新 turn，不静默回退。一个 turn 及其 retry、工具、review 和 compaction 始终使用 admission 时冻结的 immutable generation。

发行模板包含两个 Permission profile：

| Profile | Read | Write | Delete | Shell | OutsideWorkspace |
| --- | --- | --- | --- | --- | --- |
| Std（默认） | allow | confirm | confirm | confirm | confirm |
| Readonly | allow | deny | deny | deny | deny |

固定 Agent 工具集是 `list`、`read`、`search`、`write`、`patch`、`rename`、`delete`、`exec`。raw `exec` 只由宽能力 `Shell` 管理；yaca 不声称能从命令文本推断或沙箱化其文件系统/网络副作用。Permission 名称、Description 与 Prompt 都不授权。

`DoubleCheck` 开启时控制可选的高风险 action review，并强制 finish review。`.cautious` 只修改当前 Context 的覆盖值，不是 Permission profile。

## Context

Context 文件位于镜像树，例如 `__yaca__/CONTEXT/C/Program Files/我的任务.xml`。包含 XML 文件名的当前逻辑路径产生一个用户可见的 16 位大写十六进制 hash。没有永久 Context ID：rename 或 rebind 后路径/hash 立即改变，旧 hash 失效。

历史只通过显式动作打开。短名称按既定 scope/distance 顺序选择首个可用命中；hash 是精准 selector，必须唯一。rename、rebind、永久 delete、import mapping 和 metadata 修改都会复核目标。活动 writer 会阻止第二进程读取 XML 正文或修改该 Context；绝不只按锁龄破锁。

`--continue` 会解析并复核一个精确目标、取得其 writer，且当前要求从该 Context 记录的 workspace 调用。它把 durable event/config/ModelView 与各类标识符水位恢复到 Idle Agent，绝不自动重放未完成工作。若存在 unfinished turn、active queue item、未决 operation/tool、unknown terminal outcome 或 pending compaction，则必须先显式恢复。显式确认/rebind controller 实现前，跨 workspace 继续会以 typed confirmation requirement 拒绝。

chat 中无 selector 的 `.context` 显示有界 recent 列表；`.context <selector>` 先冻结已复核的逻辑路径和精确 hash，只有当前 queue、side lane、approval 与 compaction 均安全时才关闭旧 owner，之后仅按该 hash 重新组合并打开。关闭后若发生竞态，本次 invocation 会致命失败，绝不退回短名称去打开替代对象。显式跨 workspace 确认实现前，该切换同样只限记录的 workspace。

每个交互式 coordinator 错误都会取得当前进程内的 `error-N` 标识；`.details` 显示最新保留项，`.details error-N` 精确选择一项。固定环最多保留 64 条经清理的 code/message/suggestion；过期标识 fail-closed，且这个表面不保留原始 exception 对象、Tool body 或 transport payload。

## 已实现的命令 grammar

以下拼写已在源码中实现；目前仍没有可下载且通过目标资格验证的 executable：

```text
yaca [directory]
yaca --help [topic]                 (-h，Windows /h)
yaca --version                      (-v，Windows /v)
yaca --self-test [options]          (-st，Windows /st)
yaca --model-repl                   (-mr，Windows /mr)
yaca --config-repl                  (-cfg，Windows /cfg)
yaca --context-repl recent|full     (-ctx，Windows /ctx)
yaca --continue <selector>          (-c，Windows /c)
yaca --export [selector]            (-ex，Windows /ex)
yaca --status                       (-stt，Windows /stt)
```

裸 `yaca` 与 `yaca .` 完全等价。`--` 结束选项解析，因此以 `-` 开头的目录仍可表达。Linux 永远不把 `/...` 当选项。非 TTY 执行 self-test Stage 2/3 时，必须显式带本次 invocation 的 `--i-accept-online-self-test`；否则零 Model 请求并 fail-closed。

chat 文本后备包括 `.queue`（`list|delete|move|edit|clear`）、`.immediate`、`.side`、`.multiline`、`.cancel`、`.cautious`、`.model`、`.context`、`.status`、`.help`、`.details`、`.prompt`、`.compact`、`.quit`。它们与终端快捷键投影同一 semantic action，不形成 remote/headless controller。

## v0.1 明确排除

v0.1 不提供 Web UI、图像/音频输入、transcription、TTS、公共 remote/headless API、MCP、plugin/hook/skills runtime、子 Agent、Context 分支、multi-root Context、telemetry、诊断上传、内建更新、通用 undo 或 direct HTTP Agent 工具。这些排除项在配置、help、schema、Runtime、依赖与发行包中都必须为零表面。

未来本机 Web 产品线目前只是设计预留，不授权在 v0.1 中加入 Web 组件。

## 开发资料

建议先读[当前状态](.develope-docs/CURRENT-STATE.md)、[Gate A/B/R 审计](.develope-docs/GATE-AUDIT-2026-08-29.md)、[全程序实施计划](.develope-docs/IMPLEMENTATION-PLAN.md)、[机读契约](.develope-docs/contracts/README.md)和[技术证明清单](.develope-docs/TECHNICAL-PROOF-BACKLOG.md)。从仓库根运行完整编码就绪检查：

```sh
bash .tools/run_coding_readiness.sh
```
