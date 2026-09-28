# 当前状态

更新日期：2026-09-28。`709aa85` 完成
[R46--R47](CODE-REVIEW-2026-09-28.md#r46--r47-进程输出与执行结果)
进程输出故障保留和 UTF-16 严格校验，随后 XP 当前源码 670/670 通过。
收尾补充原生 seek 目标验证，并修正 R48 文件读取在 Lua 内存异常时的原生缓冲泄漏。
提交脉络见[开发历程](DEVELOPMENT-HISTORY.md)。

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
| 旧编码 | 原生代码页转换、编码规范化、read/search 解码、write/patch 无损编码、exec 输出解码与环境事实；Lua 内存错误后的原生资源清理 | `native/yaca_text.h`、`src/textcodec.lua`、`tools.lua`、`prompt.lua` |
| 大文件 | 超过 16 MiB 时区间读取、有界搜索、`from_end`、续页令牌和超长行截断 | `native/yaca_native.c` 的 seek、`src/tools.lua` |
| 结果分页 | read/search/list 按最终 JSON 字节预算选取记录；超大显示片段在 UTF-8 边界截断 | [R29](CODE-REVIEW-2026-09-28.md#r29-验证与人工-review)、`src/tools.lua` |
| 范围一致性 | 页结束时核对完整身份与路径，续页绑定大小/修改时间；读错误和模式异常明确失败并清理句柄 | [R30--R33](CODE-REVIEW-2026-09-28.md#r30--r33-验证与人工-review)、`src/tools.lua` |
| 注释约束 | 文件头与函数/类型全量结构检查已接入 readiness；人工语义 Review 尚未完成 | [编码规范](CODING-STANDARD.md) |

当前 API 的 `partial_start` 标明尾部片段，`truncated_lines` 标明搜索遗漏的长行内容。
分页保留预算内的内容与续页信息，读取失败和文件版本变化返回明确错误。
原生转换器在 Lua 内存错误后释放已持有的缓冲和转换句柄；Windows 原生 malloc
失败返回 OutOfMemory，错误结果为 false/error，成功才返回 exact 标志。
read/search 保留转换器不可用与资源错误；write/patch 解码失败在文件发布前返回。
XP 显式替换非法旧编码字节，保留周围有效文字；GB18030 使用目标支持的标志并校验往返。
原生编码入口校验 UTF-8 标量，不依赖旧 Windows 的宽松转换行为。
exec/Lua 通道解码失败时保留 Base64 原字节和 decode_error，命令完成状态保持真实；
已识别的损坏 UTF-16 输出不会静默丢弃尾部字节。

## 最新基线复核

开发机为 Fedora 44 / x86_64，内核 `7.2.7-200.fc44.x86_64`。
完整测试在资源守卫下串行运行。最新原生读取回归日志为 `out/native-io-review-20260928/`，
偏移探针在 `out/seek-qualification-20260928/`，XP 全套源码回归在 `out/xp-closeout-20260928/`；
进程输出回归日志为 `out/exec-projection-20260928/`，
Lua 名称回归日志为 `out/codec-alias-20260928/`，
原生与 XP 回归日志为 `out/codec-xp-20260928/`；
工具层回归日志为 `out/codec-propagation-20260928/`；
原生分配审查在 `out/codec-errors-20260928/`，此前日志保留在 `out/native-codec-review-20260928/`、
`out/range-stability-20260928/`、`out/page-review-20260928/`、
`out/f4-review-20260928/` 与 `out/development-reset-20260928/`。
开发机复核和 XP 当前组件证据分别记录，均不代表最终发行包资格。

资料整理的独立复核在 `out/handoff-baseline-20260928/`，当次源码为 `18adc05`。
后续原生修复重新构建并执行探针和 readiness；本批新增 XP 当前组件实测，完整目标资格仍待完成。

| 检查 | 2026-09-28 结果 |
| --- | --- |
| 完整 Lua suite | 开发机与 XP 当前源码均 670/670 通过；原生探针独立计数 |
| 全仓注释结构 | 210 个文件、5129 个声明、0 缺项；tree-sitter 0.25.2 |
| Lua 分配失败与恢复 | Linux 解码/编码/有损各 18 个位置；Wine Win32 4/4/20、Win64 4/4/18，XP 4/4/20；0 资源错误 |
| Windows 原生分配失败与恢复 | Wine Win32/Win64 和 XP 各九个位置，覆盖严格/有损解码及编码；返回 OutOfMemory、清理与同状态恢复通过 |
| 原生构建与编码 smoke | 三平台 native 构建通过；Linux/XP 各 13 组、Wine 各 12 组往返；新增坏字节/重复映射/UTF-8 拒绝检查通过；Wine cp54936 不可用单列 |
| UTF-8 标量校验 | Linux、Wine 两架构及 XP 各 1,114,113 个候选、截断前缀及 8 组非法形式全部通过 |
| 原生文件读取异常 | Linux、Wine 两架构和 XP 各 13 个分配位置，0 原生泄漏；同句柄恢复、OS 读错误收尾通过 |
| 原生字节偏移 | Linux、Wine 两架构、XP NTFS/FAT32 的 12 偏移通过，覆盖 2 GiB / 4 GiB 边界与 EOF；不代替真实大文件扫描 |
| TP-003 / TP-010 | 重跑通过；453 / 5,564,743 条断言 |
| 注释检查器反例 | 14/14 通过 |
| 契约 / 证明登记 / readiness | 7687 / 56 / 562 条断言通过 |
| 公开文档真值 | 5 项通过 |
| 完整 coding readiness 链 | TP-003/006/008/010、RP-001 全部通过，退出码 0 |

TP-003 与 TP-010 已重跑，[证明清单](proofs/modern-2026-08-29/manifest.lua)
与检查器摘要相符。注释结构零缺项仅说明覆盖，不能代替语义 Review。

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
| XP SP3 x86 | 当前 native 编码、错误注入及源码 suite 670/670；新增 NTFS/FAT32 seek 边界探针；历史 N23 控制台旅程 | 重建当前单文件与三档包；完整目标矩阵和真实大文件旅程 |
| Win7 SP1 x64 | N4 核心与原生探针；R21 修正 Lua 源码配旧原生组件的复验 | 当前源码完整单文件产物与全套目标复验 |
| CentOS 7 x86_64 | 历史候选、3.10 内核下的进程监督及模型旅程 | 当前源码构建、完整资格与最终包 |
| 指定 Server 2008 / Cygwin SSH | 直接交互、中文 Ask、真实 Lua/模型等旧候选证据 | 当前候选复验；旧 SSH 外层 255 与握手失败记录仍须分辨 |
| std/full 工具 | win32 std 的部分构建/运行证据；三目标候选版本和装配约束 | win64/Linux std、三个 full 的完整工具闭包与目标运行 |

详细路径、失败记录与适用候选见[Review 记录](CODE-REVIEW-2026-09-22.md)和
[开发历程](DEVELOPMENT-HISTORY.md)。Windows 新编码转换已有交叉编译、Wine 和 XP 探针，
XP 已补原生 seek 探针，Win7 当前组件仍待实测；不能沿用旧包的目标资格。

## 尚未完成

- 全仓人工语义 Review；R23--R48 修改范围已逐项核对，接续原生 open/create 与进程流临时资源审查。
- Win7 当前原生组件和真实旧终端输出旅程；现有 VM 登录上下文待补。
- 当前源码的三目标完整构建、目标回归、网络故障、恢复与容量矩阵。
- A08/A09 的 GiB 级日志、增长/轮转、旧代码页及真实模型读取旅程。
- 工具来源、许可证、依赖闭包及三目标 clean/std/full 共九包验收（C32--C34）。

已知行为边界：大文件单次扫描预算为 256 MiB，不计算整文件摘要；
超过 16 MiB 的文件不能 write/patch。文件在接纳、读取或续页之间的身份变化返回
`TargetChanged`，需要重新读取。身份复核不是文件系统快照；持续增长与旧文件系统时间精度
仍需实际目标验收，不把这些边界记作已解决。

下一步和逐项完成条件统一放在 [TRACKING.md](TRACKING.md)。
