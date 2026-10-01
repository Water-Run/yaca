# 当前状态

更新日期：2026-10-01。本地 `main` 与 `origin/main` 一致于 `9188a2e`，工作区干净。
本轮按队列完成 fs/textcodec/process 错误与资源收尾及 tools 写发布路径的
人工语义 Review：未发现缺陷、未修改产品源码，专项探针 36/36、完整 suite 697/697，
证据见 [10 月 1 日 Review](CODE-REVIEW-2026-10-01.md)。9 月 30 日轮修复附带软件
索引及内核取消、超时、失败回执和 Ask 关闭路径，提交脉络见
[开发历程](DEVELOPMENT-HISTORY.md)，证据见
[9 月 30 日复核](CODE-REVIEW-2026-09-30.md)与[内核审查](KERNEL-REVIEW-2026-09-30.md)。
实机范围按 [D-077](DECISIONS.md#d-077-本次收尾的兼容检查与实机范围2026-09-30)，
不再要求本次重跑整个旧系统实机/VM 矩阵。

**核心已实现，目标资格验证待完成。** 机读阶段为 `implemented-unqualified`，
Release Gate R 为 `closed`，`release_authorized=false`。依据是
[readiness](contracts/readiness.lua)、[发行清单](../release/manifest.lua)和
[依赖锁](../release/dependencies.lock)。旧源码或旧包通过不能转为当前源码资格。

## 已有实现

| 范围 | 当前能力 | 实现或记录 |
| --- | --- | --- |
| Agent 核心 | 单 Agent、串行工具、OpenAI/Anthropic 两协议、审批、流式输出、取消、压缩、Context 持久化与恢复 | `src/runtime.lua`、`model.lua`、`session.lua`、`context.lua` |
| 交互与管理 | 首次配置、配置/模型/Context 管理、status/export、自检；`.ask` 纯问答 | `src/main.lua`、`cli.lua`、`terminal.lua` |
| 工具面 | 八个基础工具及正式内嵌 `lua` 工具；共用权限、预算、取消与收尾 | `src/tools.lua`、`process.lua`、`release/launcher.lua` |
| 附带软件 | `tools/INDEX.txt` 说明、模型环境投影和 `.software` 本地查询/问答；通过 exec/lua 使用程序 | `src/bundled.lua`；本轮统一完整读取、16 KiB 上限与无进展拒绝 |
| 便携发行 | clean/std/full 装配器；同平台核心相同，可选 tools；历史候选已装配 7/9 | [工具清单](../release/TOOL-BUNDLES.md)、`release/tool-bundles.json` |
| 旧终端与原生层 | Cygwin PTY、Unicode 路径/参数/输出、异步 stdin、进程树回收、FAT32 修复 | [便携实现](PORTABLE-IMPLEMENTATION-2026-09-22.md)、[R01--R22](CODE-REVIEW-2026-09-22.md) |
| 旧编码与资源 | 原生代码页转换、无损写回、exec 原字节保留；Lua 分配失败时原生资源清理 | `native/yaca_text.h`、`src/textcodec.lua`；[R34--R50](CODE-REVIEW-2026-09-28.md) |
| 大文件与分页 | 超过 16 MiB 时区间读取、有界搜索、尾读、续页和长行截断；身份/版本变化明确失败 | `src/tools.lua`、原生 seek；[R23--R33](CODE-REVIEW-2026-09-28.md) |
| 开发检查 | 全仓注释结构检查；支持 CRLF 文件头；Git 保持脚本、补丁和 golden 的 LF 字节 | [编码规范](CODING-STANDARD.md)、`.gitattributes`；人工语义 Review 未全量完成 |

## 本轮开发机复核

环境为 Windows 宿主上的 Ubuntu 24.04.4 / WSL2，内核
`6.6.87.2-microsoft-standard-WSL2`。Lua 5.5.1 由锁定 SHA-256 的源码本地构建，
完整 Lua suite 通过资源守卫串行运行。注释检查使用隔离的 Python 3.13.15
和 `.tools/comment_check_requirements.txt` 的固定解析器。

| 检查 | 本轮结果 |
| --- | --- |
| 内核状态机专项回归 | 52/52；覆盖取消/转向/超时/回执丢失、旧响应和 Ask 关闭 |
| 索引及模型环境专项回归 | 25/25；含 EOF 上限、无进展、完整读取、BOM 和损坏 UTF-8 |
| 完整 Lua suite | 开发机及 Server 2008 当前源码均 697/697 通过 |
| 注释检查器反例 | 15/15 通过；新增六种文件后缀的 CRLF 正反例 |
| 全仓注释结构 | 219 文件、5256 声明、0 缺项；包含新增原生最小访问权和目录身份 helper |
| 契约 / 证明登记 / readiness / 公开文档 | 7739 / 56 / 565 条断言及 5 项文档真值检查通过；Gate R 仍关闭 |
| 完整 coding readiness | TP-003/006/008/010、RP-001 全链 PASS；TP-010 为 5,564,779 条断言 |
| 发行装配 | Python 5/5；修复无 tool-inputs 的独立 clean 装配错误 |
| 收尾复核（同一工作区重跑） | 完整 suite 697/697、内核专项 52/52、四个校验器 PASS、注释 219 文件 / 5256 声明、装配单测 5/5；用已核对核心经 `package_editions.py` 重装配 win32-x86 clean 成功 |
| 人工语义核对 | 本轮内核状态转换、所有权、失败停止、索引及回归夹具已核对；不扩展为全仓完成 |

日志与完整注释清单在 `out/review-20260930/`。已重建 Win32 当前单文件/clean，
在指定 Server 2008（192.168.5.10）通过 697/697；Stage 1 在建立隔离数据目录后
12 PASSED / 0 FAILED，配置未初始化与非 TTY 警告如实保留，online-requests=0。
后续普通用户 Win64 原子发布与父目录时间戳缺陷已修复，两种 Windows 核心再次刷新；
Win32 SHA-256 为 `857680865d91c0a8cbc7f1540717c8c51631392a8cf018913b3b60150cca0a04`，
Win64 为 `a75a106cfecd7a3b053f0e895baf39bb7ea169655530868bbdab86f3fadb72f3`。
Win64 本机 Stage 1 也是 12 PASSED / 0 FAILED，实际 inherited DACL、长名称
rename/replace/delete 与 XML smoke 通过；Server 2008 刷新后的 Stage 1 再通过。
Linux / 本机 Win64 / Server 2008 Win32 最终原生故障探针均 0 句柄/缓冲泄漏，
编码资源、严格 Unicode 与同状态恢复通过，原始结果在内核审查中分别记录。
本轮不补 XP/Win7/CentOS 7 的实机矩阵，未执行模型联网旅程。
历史 Fedora 开发机 readiness 和目标组件证据保留在
[9 月 28 日 Review](CODE-REVIEW-2026-09-28.md)；两批环境与证据分别记录。

收尾复核在同一工作区重跑，日志在 `out/final-verify-20260930/`。契约校验的
7739 计数含 xmllint 外部 Relax NG 检查；本机未安装该工具时为 7738 并打印
跳过说明，两者都不是失败。用已核对的 Win32 核心经 `.tools/package_editions.py`
重装配 clean 得到 `editions=PASS`：clean 载荷与已做 Stage 1 的候选件逐字节相同，
归档 SHA-256 不同（装配器写入固定时间戳，候选构建脚本保留真实 mtime）；notices
归档的成员形状也不同，见 TRACKING 的 C33 布局项。
本工作区没有 Win64 的 companion notices 与 Linux 核心，因此没有在这里
重装配这两项。

## 目标与发行候选

以下为截至 `344f864` 的历史记录，原始日志主要位于原构建机的 `out/`。
本工作区没有这些批次的完整缓存、VM 与最终包；本轮修复后仍需统一源码重建。

| 平台 | clean | std | full | 证据与缺口 |
| --- | --- | --- | --- | --- |
| win32-x86 | 已装配 | 已装配 | 未装配 | XP 当前组件 suite 670/670、原生探针与 stage-1；Server 2008 std 干净机旅程通过。full 的 Python 3.4.10 源码构建待可用工具链 |
| win64-x86_64 | 已装配 | 已装配 | 未装配 | Win7 当前组件 suite 670/670、codec/进程流/seek 与 stage-1；fs-open 真机复跑仍缺。std 工具 Wine 冒烟通过，原子发布失败不算目标资格；Python 3.8.20 构建待完成 |
| linux-x86_64 | 已装配 | 已装配 | 已装配 | CentOS 7 当前组件 suite 670/670、三故障探针、真实 2.3 GiB 旅程 10/10；full 干净 CentOS 7 工具旅程通过。Git 以 NO_CURL=1 构建，HTTP/HTTPS 传输缺口待收口 |

**7/9 是候选装配进度，不是最终资格通过数。** 附带软件功能后来使历史开发机
suite 增至 678 项；本轮为 697 项。目标端旧 670 项对应早期源码，不能写成已覆盖
后续附带软件修复。详细记录见[目标及工具批次](CODE-REVIEW-2026-09-28.md)。

人工语义 Review 已记录 R01--R50 各批、附带软件特性、index.lua、network.lua 的
SSE 子面、compact.lua 的断路器/恢复子面、terminal.lua，以及 10 月 1 日
fs/textcodec/process 的错误与资源收尾和 tools 读写/写发布路径（无缺陷，探针
36/36）。子面通过不代表所在整个模块通过，其余源码仍须继续审查。

## 当前剩余与边界

- 继续全仓人工语义 Review：fs/textcodec/process 与 tools 读写已收口，余
  model/runtime/session/context 的发布与恢复边界；随后进入三目标统一重建与目标回归。
- Python 3.4.10 已源码构建并在 Server 2008 验证；Windows 两个 full 的其余完整闭包及最终装配、Python 3.8.20 构建、Linux Git 传输能力仍待收口。VS2019 候选下载清单的整体 SHA/大小与 channel 不一致，保留失败证据，未把该清单记为已验证。
- 按 D-077 核对兼容源码、ABI 和导入闭包；用已有指定实机补相应运行证据。
- A08/A09 已有 CentOS 7 离线大文件证据；旧终端、轮转/截断和真实模型续页旅程仍待补齐。
- 最终九包的布局、核心一致性、干净机旅程、SHA-256、许可证与 SBOM，之后再评审 Gate R。

大文件单次扫描预算为 256 MiB，不计算整文件摘要；超过 16 MiB 的文件不能
write/patch。`partial_start`、`truncated_lines` 和续页信息明确表示部分结果。
文件身份或版本变化返回 `TargetChanged`；身份复核不是文件系统快照，持续增长与
旧文件系统时间精度仍需目标验收。

执行顺序、依赖与完成条件统一见 [TRACKING.md](TRACKING.md)。
