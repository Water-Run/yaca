# 当前状态

更新日期：2026-09-28。产品基线 `32d053e`，资料整理节点 `9aed60f`；
`9724797` 已完成 R23--R28，本轮收口 [R29 分页预算修正](CODE-REVIEW-2026-09-28.md#r29-验证与人工-review)。

**核心已实现，目标资格验证待完成。** 机读阶段为 `implemented-unqualified`，
Release Gate R 为 `closed`，`release_authorized=false`。
当前依据是 [readiness](contracts/readiness.lua)、[发行清单](../release/manifest.lua)
和[依赖锁](../release/dependencies.lock)，历史包的资格不自动转给新源码。

## 已有实现

| 范围 | 当前能力 | 对应实现或记录 |
| --- | --- | --- |
| Agent 核心 | 单 Agent、串行工具、双模型协议、审批、流式输出、取消、压缩、Context 持久化与恢复 | `src/runtime.lua`、`model.lua`、`session.lua`、`context.lua` |
| 交互与管理 | 首次配置、配置/模型/Context 管理、status/export、自检；`.ask` 纯问答 | `src/main.lua`、`cli.lua`、`terminal.lua` |
| 工具面 | 原八个工具加正式 `lua` 工具；与核心同版本的内嵌解释器，共用权限、预算、取消和收尾 | `src/tools.lua`、`process.lua`、`release/launcher.lua` |
| 便携发行 | clean/std/full 装配；同平台核心相同；可选 tools 的位置与能力说明 | [工具清单](../release/TOOL-BUNDLES.md)、`release/tool-bundles.json` |
| 旧终端与原生层 | Cygwin PTY、Unicode 路径/参数/输出、异步 stdin、进程树回收及 FAT32 修复 | [便携实现](PORTABLE-IMPLEMENTATION-2026-09-22.md)、[R01--R22](CODE-REVIEW-2026-09-22.md) |
| 旧编码 | 原生代码页转换、编码规范化、read/search 解码、write/patch 无损编码、exec 输出解码与环境事实 | `native/yaca_text.h`、`src/textcodec.lua`、`tools.lua`、`prompt.lua` |
| 大文件 | 超过 16 MiB 时区间读取、有界搜索、`from_end`、续页令牌和超长行截断 | `native/yaca_native.c` 的 seek、`src/tools.lua` |
| 结果分页 | read/search/list 按最终 JSON 字节预算选取记录；超大显示片段在 UTF-8 边界截断 | [R29](CODE-REVIEW-2026-09-28.md#r29-验证与人工-review)、`src/tools.lua` |
| 注释约束 | 文件头与函数/类型全量结构检查已接入 readiness；人工语义 Review 尚未完成 | [编码规范](CODING-STANDARD.md) |

9 月 26 日新增的编码和大文件实现已提交。恢复基线的资料整理已提交为 `9aed60f`；
随后修正编码映射、UTF-16 分块/修复、超长行续页/尾读、长首行编码采样及搜索完整性。
当前 API 的 `partial_start` 标明尾部片段，`truncated_lines` 标明搜索遗漏的长行内容。
本轮收口的分页修复避免 JSON 转义膨胀导致整页内容和续页信息一起被省略。

## 本轮基线复核

开发机为 Fedora 44 / x86_64，内核 `7.2.7-200.fc44.x86_64`。
完整测试在资源守卫下串行运行。日志保存在
`out/page-review-20260928/`；此前的编码复核和资料整理日志分别保留在
`out/f4-review-20260928/` 与 `out/development-reset-20260928/`。
这些是开发机复核记录，不是发行目标资格。

| 检查 | 2026-09-28 结果 |
| --- | --- |
| 完整 Lua suite | 657/657 通过；R23--R28 新增 8 项，R29 新增 3 项 |
| 全仓注释结构 | 207 个文件、5068 个声明、0 缺项；tree-sitter 0.25.2 |
| 原生编码探针 | 沿用本日 F4 记录：当前 native 构建通过，Linux 12 组往返及严格拒绝通过；R29 未改原生层 |
| TP-003 / TP-010 | 重跑通过；453 / 5,564,743 条断言 |
| 注释检查器反例 | 14/14 通过 |
| 契约 / 证明登记 / readiness | 7687 / 56 / 562 条断言通过 |
| 公开文档真值 | 5 项通过 |
| 完整 coding readiness 链 | TP-003/006/008/010、RP-001 全部通过，退出码 0 |

初次证明校验发现 TP-003 与 TP-010 的源码摘要已过期。两项均已实际重跑，
随后更新[证明清单](proofs/modern-2026-08-29/manifest.lua)和检查器固定摘要；
旧记录由 Git 保留。注释结构零缺项仅说明覆盖，不能代替语义 Review。

复核使用 Python 3.13 及固定解析器；本机复现命令如下，其他构建机按
`.tools/comment_check_requirements.txt` 安装相同依赖，并提供自己的锁定源码缓存：

```sh
.tools/run_with_resource_guard.sh bin/lua55 test/run.lua
PYTHONPATH="$PWD/out/code-comment-audit-20260923/site313" \
YACA_PROOF_SOURCE_CACHE="$PWD/out/qualification/sources" \
  .tools/run_with_resource_guard.sh bash .tools/run_coding_readiness.sh
```

## 目标证据的边界

| 环境 | 已有证据 | 当前缺口 |
| --- | --- | --- |
| XP SP3 x86 | N23 核心、NTFS/FAT32、Unicode、Lua 工具及控制台旅程 | 重建当前源码；纳入 R21/R22 与新编码/seek 后复验 |
| Win7 SP1 x64 | N4 核心与原生探针；R21 修正 Lua 源码配旧原生组件的复验 | 当前源码完整单文件产物与全套目标复验 |
| CentOS 7 x86_64 | 历史候选、3.10 内核下的进程监督及模型旅程 | 当前源码构建、完整资格与最终包 |
| 指定 Server 2008 / Cygwin SSH | 直接交互、中文 Ask、真实 Lua/模型等旧候选证据 | 当前候选复验；旧 SSH 外层 255 与握手失败记录仍须分辨 |
| std/full 工具 | win32 std 的部分构建/运行证据；三目标候选版本和装配约束 | win64/Linux std、三个 full 的完整工具闭包与目标运行 |

详细路径、失败记录与适用候选见[Review 记录](CODE-REVIEW-2026-09-22.md)和
[开发历程](DEVELOPMENT-HISTORY.md)。Windows 新编码转换与 seek 目前只有交叉编译证据；
旧包的运行结果不覆盖这些改动。

## 尚未完成

- 全仓人工语义 Review；新编码/区间读取的文件变化、错误路径与原生资源生命周期接续 R23--R29 审查。
- 当前源码的三目标完整构建、目标回归、网络故障、恢复与容量矩阵。
- A08/A09 的 GiB 级日志、增长/轮转、旧代码页及真实模型读取旅程。
- 工具来源、许可证、依赖闭包及三目标 clean/std/full 共九包验收（C32--C34）。

已知行为边界：大文件单次扫描预算为 256 MiB，不计算整文件摘要；
超过 16 MiB 的文件不能 write/patch。文件在接纳与执行之间增长仍可能得到
`TargetChanged`，需要重试；不把这一边界记作已解决。

下一步和逐项完成条件统一放在 [TRACKING.md](TRACKING.md)。
