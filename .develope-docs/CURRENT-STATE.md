# 当前状态

更新日期：2026-10-05。核心已实现，正在收尾发行验收。阶段为
`implemented-unqualified`，目标资格验证待完成；Release Gate R 为 `closed`，
`release_authorized=false`。依据见 [readiness](contracts/readiness.lua)、
[发行清单](../release/manifest.lua)及[依赖锁](../release/dependencies.lock)。

候选节点交付后，工作树新增 **R77 Windows reparse 修复**：使用实际 SubstituteName，
按声明/返回长度检查完整头和 UTF-16 范围，拒绝 NUL、未知 flags 和无法支持的 NT
命名，避免把绝对目标错误映射到进程 cwd。两指定 Windows 实机的生产函数探针各
**20/20**，其中真实 junction 的内核跟随对象与解析目标相同；旧实现同组各失败 14 项。
完整开发 suite 706/706、coding readiness PASS。此结果覆盖原生产函数和窄探针，
尚未构建含 R77 的三平台单文件及九包；下述已发布候选的 SHA-256 不覆盖本修复。

本节点已修复 R75：OpenAI 工具流后续 ID/name/arguments 的显式 null 表示不更新，
首片身份和后续非 null 身份变化仍严格校验；R76：压缩取消的日志写入失败后，仍使用
原句柄清理 Model，返回结构化失败，不再访问已清空的 active。
产品版本入口统一为 `1.0.0`。三目标核心已从同一份源码成员快照构建，Linux C7
用户态、Server 2008 Win32、Windows 11 Win64 分别通过完整 suite **706/706**。
原生 C 本轮只修改路径、文件与元数据的契约注释，运行行为未改。
三平台 clean/std/full 已重新装配，九包完整性与文件证据检查通过；Linux 三档在
C7 用户态分别通过 10/10 离线核心旅程。本节点交付为
[`v1.0.0-preview.20261005`](https://github.com/Water-Run/yaca/releases/tag/v1.0.0-preview.20261005)
候选预发布，正式资格仍待完成。
负责人已按 [D-080](DECISIONS.md#d-080-继续收尾至-v10-正式版2026-10-05) 撤回暂停安排，
正式版本目标为 `1.0.0`。本节点候选不等于正式版；后续产品源码变化仍须重新构建并绑定证据。
历次实现与修复见[开发历程](DEVELOPMENT-HISTORY.md)，剩余任务只在
[TRACKING.md](TRACKING.md)维护。本轮证据见
[10 月 5 日 Review](CODE-REVIEW-2026-10-05.md)。

## 已有实现

| 范围 | 当前能力 | 实现 |
| --- | --- | --- |
| Agent 核心 | 单 Agent、串行工具、OpenAI/Anthropic 协议、流式输出、审批、取消、压缩、Context 持久化与恢复 | `runtime.lua`、`model.lua`、`session.lua`、`context.lua` |
| 交互与管理 | 首次配置、配置/模型/Context 管理、status/export、自检；`.ask` 纯问答 | `main.lua`、`cli.lua`、`terminal.lua` |
| 工具 | 八个基础工具及正式内嵌 `lua`；共用权限、预算、取消与收尾 | `tools.lua`、`process.lua`、`release/launcher.lua` |
| 附带软件 | 可选 `tools/`、索引、模型环境投影和 `.software` 查询；clean/std/full 三档装配 | `bundled.lua`、`release/tool-bundles.json`、`package_editions.py` |
| 便携与旧系统 | 单文件、Windows PTY/Unicode、异步 stdin、进程树回收、FAT32 发布、旧代码页无损读写 | `native/`、`fs.lua`、`textcodec.lua` |
| 大文件 | 区间读、尾读、有界搜索、续页和长行截断；身份/版本变化返回 `TargetChanged` | `tools.lua`、原生 seek |
| 发行验收 | clean/std/full 逐文件与来源包校验、九包核心一致性汇总；Linux 离线旅程使用真实 PTY | `audit_editions.py`、`edition_journey.py`、`test/release/journeys.lua` |

## 当前复核

本轮开发宿主为 Fedora / Linux `7.2.7-200.fc44.x86_64`。Lua 测试使用
`bin/lua55`；注释检查使用隔离 Python 3.13.8 和仓库固定版本的解析器。
构建、完整测试和容器均经资源守卫串行执行。

新增发行校验逐一核对 ZIP 外层 SHA-256、成员 SHA-256/CRC、路径和模式、工具版本、
入口/许可证/来源、SPDX 与同平台核心。缺包、缺构建/测试证据和未完成的目标资格分别记录。
它不会把完整性通过转为发布授权。

Linux 离线旅程验收包完整性、解包、版本、非 TTY 零写入拒绝、内嵌 Lua、真实 PTY
Stage 1、移除 tools、整体移动、卸载及临时目录无残留。已有 scratch 内容保留。
在线步骤与跨平台执行不由该驱动完成，选择后非零退出，不报告跳过即通过。

本轮逐文件复核确认，10-05 的 Linux clean companion 缺项目 GPL 许可证和
核心依赖 SBOM；Windows 两 full companion 缺完整测试摘要。Linux 缺项已在本轮
九包重装配时补齐，并核对核心源码快照与各依赖来源摘要。当前 1.0.0 Windows 两目标
已补齐实际日志、环境和计数绑定，不再以开发机或旧核心结果代填。

Linux full 已替换早期 Git 输入。在 C7 用户态补建 Git 2.55.0、静态
libcurl/Mbed TLS 和 Perl 5.42.3/libxcrypt 4.4.38；Perl 上游完整 **2654 文件 /
1,338,437 项测试**与 libxcrypt **45/45** 通过，RPATH 和 glibc 2.17 校验通过。
SDK 补齐签名 C7 运行库和默认 sysroot，带空格的移动路径下 C/C++ 编译运行通过，
生成程序最高 glibc 要求 2.17。十个工具、Git Perl 模块和真实 GitHub HTTPS 在 C7
容器的只读移动路径下通过。full 来源包分别绑定对应工具与新增 C7 来源。
Linux SDK 存在合法的大小写不同头文件；装配和审计按 Linux 大小写敏感规则核对，
Windows 仍拒绝大小写冲突，精确重复和文件/目录冲突在两平台都拒绝。

负责人已提供本轮模型访问：DeepSeek `deepseek-flash`、DGX Spark `qwen3.8-27b`。
凭据仅保存在忽略的私有目录。当前 1.0.0 Linux 核心在全新隔离部署复跑 Stage 2：
**两模型各 7/7、14 次请求全过**。真实 PTY 在 DeepSeek 下通过多行 Ask、精确 Lua
审批执行、结果问答、主任务随机 token 跨进程召回和两次终端恢复。落盘 XML 另核对
唯一一次 Lua operation、stdout=42、exit=0 和后代 proven-stopped。
驱动和模型的此前失败在日期 Review 与原始日志保留，不扩展为其它目标的恢复资格。

| 本节点 1.0.0 核心 | SHA-256 | 当前证据 |
| --- | --- | --- |
| Linux | `406752564e2e68e541fd7f4078500bc3434e65f56a07c647702d1646d5a5fefa` | C7 用户态构建及 ELF/glibc 闭包 PASS；完整 suite 706/706 |
| Win32 | `d681140088429ccfff8cb6a05bdc5ae9a231b4cdb2ef3f4a3851aa4c2045f728` | 统一交叉构建及导入闭包 PASS；Server 2008 实机完整 suite 706/706 |
| Win64 | `d90f49960cd03af9a9a77e6c80e02d0d605fcf1839776520841f40acc4563638` | 统一交叉构建及导入闭包 PASS；Windows 11 x64 实机完整 suite 706/706 |

最终测试数、注释清单及逐包摘要记录在[本轮 Review](CODE-REVIEW-2026-10-05.md)
和 `out/node-r76-20261005/`；包内核心的历史测试数不随开发机新增测试改写。

## 候选产物与证据边界

三目标各 clean/std/full 已装配，共九个候选包。本轮从已核对的当前核心及锁定工具输入
重新装配三档，逐包校验并检查同平台核心一致。候选装配完成不代表九包目标资格完成。

当前三核心共享未压缩源码 tar SHA-256
`64afb701973f9be775919f1757312de3b74b55305a354e69aa16155d0f6b224e`。
归档基线为 `a71bb76` 加工作树改动，不冒充该 HEAD 的源码。Python/zlib 的压缩结果
不同，但三目标未压缩 tar 与逐成员内容相同；压缩摘要在各自构建证据中保留。
构建后新增的打包路径校验、回归和用户文档不改变产品源码，最终提交与构建快照的
差异另记在日期 Review，不改写核心捕获来源。

旧 Windows full 的工具/移动/卸载、大文件旅程，以及 R75 Linux 的模型/恢复子集，
均在日期 Review 保留其精确摘要，不能扩展成当前九包完整 C33 通过。当前节点的
首次配置、三平台完整交互、保留数据的升级和剩余目标运行证据仍须补齐。

实机范围按 [D-077](DECISIONS.md#d-077-本次收尾的兼容检查与实机范围2026-09-30)，
不重新要求整套旧系统实机/VM 矩阵。兼容底线仍是 XP SP3 x86、Win7 SP1 x64、
CentOS 7 x86_64；未实测的面如实保留。

## Review 与验收状态

注释结构检查覆盖 Git 维护的全部自有源码和新增文件。结构覆盖与人工语义 Review
分开记录。10-01 四批已核对产品模块及组合/发布边界；保留面为 main 交互事件分发
内部、原生 C 层和测试辅助代码，不宣称全仓逐项语义审核完成。
本轮 compact 状态机已通读并修复 R76，原生 Windows 目录/链接与发布准入面继续到
约 4400 行并修复 R77。Snapshot/metadata 在 Lua 表/字符串分配异常下的资源生命周期
仍待故障注入取证；main 交互内部继续。
本轮新增校验、PTY 生命周期、临时目录所有权及回归逐项核对。

C32/C33/C34 的剩余项完成并形成精确字节证据后，才评审 Gate R。
执行顺序、依赖与退出条件见 [TRACKING.md](TRACKING.md)。

本节点全量 coding readiness PASS：注释结构 **240 文件 / 5408 声明 / 0 缺项**，
检查器反例 15/15；装配/审计/旅程/快照/审批/staging/Windows 证据回归均通过，
四校验器及全部 TP/RP 通过。人工语义 Review 保留面仍未完成。

本轮交付节点按 [D-081](DECISIONS.md#d-081-下一个开发节点打包推送2026-10-05)：
推送源码到 `origin/main` 并发布三目标九包候选预发布。正式 v1.0 的 Gate R 保持关闭，
剩余语义 Review 和交互/升级旅程继续登记。
