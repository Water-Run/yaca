# 设计决定追踪完整性审计

更新日期：2026-07-18

状态：第四轮反向追踪历史快照；不再表示现行未答项或当前题库数量

> 本文件冻结 2026-07-18 的 `335/360/101` 基线，用来解释后续为何扩大题库和建立唯一 owner。第 7 节的“尚未进入决定日志”已经由 Batch 02 至 Batch 06 解决，不能作为当前待办；现行状态只看 [`DECISION-REGISTER.md`](DECISION-REGISTER.md)、[`DECISIONS.md`](DECISIONS.md) 与 [`ARCHITECTURE-READINESS.md`](ARCHITECTURE-READINESS.md)。

计数口径：下列 335/360/101 是修复开始前的可复现基线。随后新增的 checklist/AQ/11 号包和关联修复不回写这份证据快照；修复后的分类与验收结果见 `DECISION-COVERAGE-REPAIR.md`。

## 1. 审计结论

当前设计资料已经形成足够宽的主题面，但还不能把“题库很大”当成“回答后自动可实施”。本轮从设计 ID 反向检查到负责人问题、子系统主责、readiness gate 和未来权威规格，得到以下结果：

| 被审计对象 | 定义总数 | 有直接追踪 | 没有直接追踪 | 说明 |
| --- | ---: | ---: | ---: | --- |
| `DESIGN-CHECKLIST.md` 设计 ID → decision group | 335 | 234 | 101 | 只统计决策组 `关联：` 行；正文提到但未关联不算直接追踪 |
| `QUESTIONS.md` 原子问题 → decision group | 360 | 298 | 62 | `AQ-001` 至 `AQ-360` 连续且唯一；62 项没有出现在任何决策组的 `关联：` 行 |
| 设计 ID → owner subsystem | 335 | 335 | 0 | 按命名空间唯一归属；跨系统消费者不取得主责 |
| 设计 ID → `ARCHITECTURE-READINESS.md` 某个具体 gate | 335 | 219 | 116 | 只统计 28 个 gate 自身区块里的显式 ID/range/wildcard；12 个 P1 gate 当前全部没有 `主要来源` ID 行 |

九个决策包共有 101 个负责人决策组。105 个设计 ID 被两个或更多决策组引用，166 个原子问题被两个或更多决策组引用。交叉引用本身不是错误：配置秘密同时影响网络和导出，Context 事件同时影响 AgentLoop、压缩与恢复。真正的要求是只有一个 owner subsystem 负责写最终规范，其他组只能提供输入或消费结果。

本轮没有发现“335 个 ID 中完全没有 owner”的项目。发现的结构性例外是 21 号扩展边界没有自己的 `EXT-*` 命名空间，只借用 `PROD-11`、`TOOL-14/16`、`LOOP-21/23` 等 ID；这会让“v0.1 不支持 MCP/插件/子 Agent”难以作为一个可独立关闭的范围决定追踪。

## 2. 判定方法

### 2.1 什么叫直接覆盖

决策包覆盖采用机械规则：

1. 从 `DESIGN-CHECKLIST.md` 的粗体定义抽取 335 个唯一设计 ID。
2. 从 `QUESTIONS.md` 的四级标题抽取 `AQ-001` 至 `AQ-360`。
3. 以 `PJ-*`、`PP-*`、`TU-*`、`M05-*`、`AL06-*`、`TS-*`、`CX-*`、`ED-*`、`RF-*` 标题切分 101 个决策组。
4. 只读取每组的 `关联：` 行，展开 ``X-01` 至 `X-05`` 和 `AQ-001` 至 `AQ-005` 形式的范围。
5. 一个 ID 只在说明正文出现、却没有出现在 `关联：` 行时，判定为“语义可能已讨论，追踪未闭合”，而不是直接覆盖。

readiness 覆盖采用同样的 range/wildcard 展开，但只检查 28 个 `AR-P0-*`/`AR-P1-*` gate 自身的区块。后面的生命周期矩阵、示例或一般说明不能替代某个 gate 的来源清单。

### 2.2 什么叫 owner

owner 是最终规范的唯一修改责任，不等于只有该系统能引用这个 ID。例如：

- `SAFE-03` 的 owner 是 08 号权限与安全；TUI 只负责显示同一审批决定。
- `PERF-*` 的 owner 是 22 号应用运行时；20 号测试系统负责测量和裁决，不重新定义预算。
- `TEST-*`/`EVAL-*` 的 owner 是 20 号测试与评估；16 号发布系统只消费发布证据。
- `PROD-08` 的 owner 是 00 号产品契约；网络、配置、Context 和诊断分别落实矩阵中的列。

### 2.3 三种责任不能混在同一问卷里

| 标记 | 含义 | 正确关闭方式 |
| --- | --- | --- |
| `O` | 负责人选择 | 解释 2--3 个会改变产品承诺的选项，由项目负责人明确回复，写入 `DECISIONS.md` |
| `J` | 联合责任 | 负责人先选择可接受的保证/降级，架构侧再用规范和目标平台证据证明能兑现 |
| `T` | 架构推导或技术证明 | 不能让负责人对物理事实投票；由设计侧给出唯一契约、反例、原型/基准和证据，只有产品降级才回到负责人 |

“XML 根关闭后还能否直接追加子元素”“XP 上是否存在某 API”“ELF32/x32 是否等于 Linux x86_64”属于 `T`。是否允许长期 WAL、是否接受某种旧终端降级、是否承诺 undo 属于 `O` 或 `J`。

## 3. 主题 → owner → 决策组 → gate → 未来规范

下表给出所有设计命名空间的唯一 owner 和语义 gate。`决策组` 列只列当前 `关联：` 行真正覆盖到该命名空间的组；未覆盖的具体 ID 在第 4 节精确列出。`未来权威规范` 不是新实现文件名，而是负责人回复后必须在 owner 子系统中冻结的规范角色。

| 设计主题 / ID 范围 | Owner subsystem | 当前直接 decision groups | 语义 readiness gates | 未来权威规范 | 责任 |
| --- | --- | --- | --- | --- | --- |
| `PROD-01..15` | [00 产品契约](subsystems/00-product-and-compatibility.md) | `PJ-01/02/03/04/06`、`PP-02`、`ED-08` | `AR-P0-01/02/06/08`、`AR-P1-05/08/12` | `ProductContractV1`、完整旅程/非目标/支持矩阵 | `O/J` |
| `ARCH-01..04` | [22 应用运行时](subsystems/22-application-runtime-and-concurrency.md) | `PJ-10`、`M05-10`、`ED-05` | `AR-P0-01/04/15` | `ApplicationCompositionV1`、startup/close stack | `T` |
| `RUNTIME-01..05` | [22 应用运行时](subsystems/22-application-runtime-and-concurrency.md) | `AL06-01/06`、`TS-09` | `AR-P0-04/14/15`、`AR-P1-03/08` | `RuntimeEventPortV1`、Lua module discipline | `T/J` |
| `CONC-01..04` | [22 应用运行时](subsystems/22-application-runtime-and-concurrency.md) | `PJ-07`、`AL06-06`、`TS-10` | `AR-P0-04/10/15`、`AR-P1-08` | `ConcurrencyAndBackpressureV1` | `T/J` |
| `PERF-01..03` | [22 应用运行时](subsystems/22-application-runtime-and-concurrency.md) | `AL06-09`、`CX-11`、`RF-09/10` | `AR-P0-10/16`、`AR-P1-08` | `PerformanceBudgetV1`、workload/limit result | `J` |
| `PLAT-01..12` | [01 平台抽象](subsystems/01-platform-abstraction.md) | `PJ-10`、`TU-02`、`ED-05` | `AR-P0-04/05/10/11/14/16`、`AR-P1-01/03/08` | Path/Text/File/Clock/Terminal port specs | `T/J` |
| `PROC-01..10` | [02 进程与资源](subsystems/02-process-and-resources.md) | `AL06-05` | `AR-P0-04/06/07/14`、`AR-P1-03` | `ProcessPortV1`、`ShellDialectV1`、resource resolver | `T/J` |
| `NET-01..12` | [03 网络传输](subsystems/03-network-transport.md) | `PJ-03`、`M05-01/02/04/11`、`TS-11`、`ED-04` | `AR-P0-03/04/08`、`AR-P1-02` | `HttpTransportV1`、retry/redirect/CA/secret contract | `T/J` |
| `FMT-01..07` | [04 数据格式](subsystems/04-data-formats.md) | `M05-07`、`CX-06` | `AR-P0-09/10`、`AR-P1-01/10` | JSON/INI/XML safe profiles and deterministic writers | `T/J` |
| `CFG-01..23` | [05 配置](subsystems/05-configuration.md) | `PJ-02/03/09`、`M05-02/06..10/12` | `AR-P0-08/09`、`AR-P1-04/05/07/09/12` | `ConfigSchemaV1`、bootstrap router、edit transaction | `O/J` |
| `MODEL-01..12,14` | [06 模型协议](subsystems/06-model-protocols.md) | `PP-05/07`、`M05-01/03/05`、`AL06-02/03/08/10` | `AR-P0-02/03/12`、`AR-P1-04/05` | `ModelRequest/Event/Result/ErrorV1`、provider profile | `J/T` |
| `TOOL-01..16` | [07 工具系统](subsystems/07-tool-system.md) | `TS-01/02/10/12` | `AR-P0-06/07/14/15`、`AR-P1-03/09` | `ToolRegistryV1`、per-tool argument/result contracts | `O/J/T` |
| `INSTR-01..05` | [18 Prompt 与指令](subsystems/18-prompt-and-workspace-instructions.md) | `PP-01/03/04/07/08/10` | `AR-P0-08`、`AR-P1-05/09` | `PromptAssemblyV1`、instruction source/scope spec | `O/J` |
| `CHANGE-01..07` | [19 改动事务](subsystems/19-change-transactions-and-undo.md) | `TS-08` | `AR-P0-07/10/15`、`AR-P1-06/08` | `ChangeGuaranteeV1`、freshness/preimage/undo contract | `O/J/T` |
| `SAFE-01..17` | [08 权限与安全](subsystems/08-permission-and-safety.md) | `PP-03/04`、`TU-07`、`M05-02/05/12`、`AL06-07`、`TS-03..07/11`、`CX-07`、`ED-07` | `AR-P0-06/07/08/14`、`AR-P1-02/05/07` | `PermissionMatrixV1`、approval snapshot/recheck | `O/J/T` |
| `THREAT-01..05` | [08 权限与安全](subsystems/08-permission-and-safety.md) | 无直接 group | `AR-P0-06/08/14` | `ThreatModelV1`、abuse/test corpus | `T/J` |
| `LOOP-01..19,21..27` | [09 AgentLoop](subsystems/09-agent-session.md) | `PP-06/07`、`TU-04/11`、`M05-04`、`AL06-01..10/12`、`CX-04`、`ED-02` | `AR-P0-02/04/05/06/10/13/15`、`AR-P1-04/05/07/09` | `AgentLoopStateMachineV1`、terminal outcome/control registry | `O/J/T` |
| `CTX-01..18,21..27` | [10 Context 存储](subsystems/10-context-storage.md) | `PJ-05/06/07`、`PP-05/08/10`、`M05-06`、`AL06-01/03/06/10/11/12`、`CX-01..12`、`ED-06` | `AR-P0-08/10/15`、`AR-P1-06/10` | `ContextXmlSchemaV1`、commit/recovery/import protocols | `J/T` |
| `INDEX-01..11,13..16` | [11 Context 索引](subsystems/11-context-indexing.md) | `PJ-04/05/07`、`CX-08/09/10` | `AR-P0-11/13`、`AR-P1-06/08/09` | `LogicalPathCodecV1`、Resolver/browser/mutation states | `O/J/T` |
| `COMP-01..10` | [12 Context 压缩](subsystems/12-context-compaction.md) | `PP-05/09`、`AL06-10/11/12`、`CX-12` | `AR-P0-12`、`AR-P1-04/08` | `CompactionRecordV1`、`ModelViewManifestV1` | `O/J/T` |
| `CLI-00..15` | [13 CLI](subsystems/13-cli.md) | `PJ-08`、`TU-09/10/11` | `AR-P0-13`、`AR-P1-07/09/12` | `CliGrammarV1`、command/abbreviation/exit registry | `O/T` |
| `TUI-01..19,21..27` | [14 TUI](subsystems/14-tui.md) | `PJ-01/03/08/09/10`、`PP-01`、`TU-01..12`、`CX-09`、`ED-09/10` | `AR-P0-05/13`、`AR-P1-07/08/09` | `TuiInputStateV1`、renderer semantics、golden transcripts | `O/J/T` |
| `DIAG-01..13` | [15 诊断](subsystems/15-diagnostics-and-logging.md) | `PJ-02/06`、`PP-05`、`M05-11/12`、`TU-08`、`ED-01/02/03/07` | `AR-P0-08/10`、`AR-P1-07/12` | `ErrorRegistryV1`、self-test/report/diagnostic policy | `O/J/T` |
| `TEST-01..10` | [20 测试与评估](subsystems/20-testing-and-agent-evaluation.md) | `TU-12`、`RF-07..11` | 所有 gate 的验证层，尤其 `AR-P0-16`、`AR-P1-08/11/12` | `TestArchitectureV1`、requirement→evidence ledger | `T` |
| `EVAL-01..08` | [20 测试与评估](subsystems/20-testing-and-agent-evaluation.md) | `RF-07` | `AR-P0-03/16`、`AR-P1-04/05/08` | `AgentEvaluationV1`、versioned rubric/baseline | `O/J/T` |
| `REL-01..13` | [16 发布](subsystems/16-packaging-and-release.md) | `RF-01..11` | `AR-P0-01/16`、`AR-P1-06/10/11/12` | release layout/manifest/install/migration/release gate | `O/J/T` |
| `SUPPLY-01..04` | [16 发布](subsystems/16-packaging-and-release.md) | `RF-05/06` | `AR-P0-14/16`、`AR-P1-11` | component allowlist、SBOM、provenance/ABI audit | `T` |
| `UPDATE-01..02` | [16 发布](subsystems/16-packaging-and-release.md) | `RF-02/03` | `AR-P0-01/09/10/16`、`AR-P1-10/12` | version compatibility and migration/rollback policy | `O/J/T` |
| `DOC-01..05` | [16 发布](subsystems/16-packaging-and-release.md) | `RF-11` 只直接关联 `DOC-05` | `AR-P1-09/10/12` | documentation status/synchronization/conformance policy | `T/O` |
| `WEB-01..04` | [17 Web](subsystems/17-web.md) | `PJ-14=A` / D-044 | `AR-P0-01` 的 v0.1 零表面与重开条件 | `WebReentryCriteriaV1` + negative surface scan；恢复讨论前不写运行规格 | `O/T`，已排除 |

21 号 [扩展边界](subsystems/21-extension-boundary.md) 是唯一没有独立 ID namespace 的 owner 文档。当前建议保持 00 号拥有 `PROD-11` 的产品范围，21 号只拥有未来的 `ExtensionBoundaryV1` 规范；若后续确实需要逐项追踪扩展生命周期，应新增 `EXT-*`，不能让 `PROD-11` 同时承担 MCP、插件、hook、skill、自定义工具和子 Agent 的全部细节。

## 4. 没有 decision group 直接覆盖的项目

### 4.1 101 个 checklist ID

以下是严格按 `关联：` 行计算的完整清单。它们并不全是“没想过”：例如 `CLI-00` 已确认、`INDEX-13` 已排除、`ARCH-03` 已确认核心；问题是它们没有一个可接受负责人回复、或可明确声明“这是技术规格而非负责人选择”的决策组入口。

- `PROD`：`PROD-02`、`PROD-03`、`PROD-04`、`PROD-05`、`PROD-06`、`PROD-08`、`PROD-10`、`PROD-11`、`PROD-13`、`PROD-09`。
- `ARCH/RUNTIME/CONC`：`ARCH-03`、`ARCH-04`、`RUNTIME-04`、`RUNTIME-05`、`CONC-02`、`CONC-04`。
- `PLAT`：`PLAT-01`、`PLAT-02`、`PLAT-03`、`PLAT-04`、`PLAT-05`、`PLAT-06`、`PLAT-07`、`PLAT-08`、`PLAT-09`、`PLAT-12`。
- `PROC`：`PROC-01`、`PROC-02`、`PROC-04`、`PROC-05`、`PROC-06`、`PROC-07`、`PROC-08`、`PROC-09`、`PROC-10`。
- `NET/FMT`：`NET-01`、`NET-02`、`NET-04`、`FMT-03`、`FMT-05`、`FMT-06`、`FMT-07`。
- `CFG/MODEL`：`CFG-07`、`CFG-08`、`CFG-13`、`CFG-14`、`CFG-15`、`CFG-16`、`CFG-17`、`CFG-18`、`MODEL-09`、`MODEL-14`。
- `TOOL/THREAT`：`TOOL-05`、`TOOL-07`、`TOOL-08`、`TOOL-09`、`TOOL-10`、`TOOL-11`、`TOOL-12`、`TOOL-13`、`TOOL-14`、`TOOL-16`、`THREAT-01` 至 `THREAT-05`。
- `LOOP/CTX/INDEX`：`LOOP-09`、`LOOP-12`、`LOOP-16`、`LOOP-17`、`LOOP-18`、`LOOP-21`、`LOOP-26`、`CTX-23`、`CTX-24`、`INDEX-13`。
- `CLI/TUI/DIAG`：`CLI-00`、`CLI-02`、`CLI-03`、`CLI-05`、`CLI-06`、`CLI-07`、`CLI-09`、`CLI-13`、`CLI-14`、`CLI-15`、`TUI-07`、`DIAG-09` 至 `DIAG-12`。
- `REL/DOC/WEB`：`REL-11`、`DOC-01` 至 `DOC-04`、`WEB-01` 至 `WEB-04`。

### 4.2 这 101 项的首要关闭责任

为了避免把技术事实继续丢给负责人，101 项按“下一步先由谁动作”分成三类。分类只决定首要动作；`O` 项回答后仍要形成架构规格，`T` 项若只能降级仍要回到负责人。

#### O-first：先补负责人选择或把已经给出的回复正式归档（63）

`PROD-02/03/04/05/06/08/09/11/13`；`PLAT-02/05/08`；`PROC-01/02/05`；`NET-01/02/04`；`FMT-06`；`CFG-07/08/13/14/15/17`；`MODEL-09/14`；`TOOL-05/07/10/11/12/13/14`；`THREAT-01/02/04/05`；`LOOP-09/12/16/18/21`；`CTX-23/24`；`CLI-02/03/05/06/07/13/14/15`；`TUI-07`；`DIAG-09/10/11/12`；`REL-11`；`WEB-01/02/03/04`。

这里包含两种不同情况：真正待选，例如 plan mode、Git 定位、reasoning 显示；以及负责人已有口头方向但尚未完整落档，例如 English UI、无 MCP、streaming 三态。后者应先归档而不是重新问同一个问题。

#### T-spec：已有上游方向后由架构侧写成唯一规格（31）

`ARCH-03/04`；`RUNTIME-04/05`；`CONC-02/04`；`PLAT-01/03/06/07`；`PROC-06/07/08/09`；`FMT-03/05/07`；`CFG-16/18`；`TOOL-08/09/16`；`LOOP-17/26`；`INDEX-13`；`CLI-00/09`；`DOC-01/02/03/04`。

其中 `INDEX-13` 和 `CLI-00` 已有明确产品结论，下一步只是把排除/入口语义传播到 registry 和测试；不应再次做 A/B/C 投票。

#### T-proof：先取得物理可行性证据，再冻结承诺（7）

`PROD-10`、`PLAT-04`、`PLAT-09`、`PLAT-12`、`PROC-04`、`PROC-10`、`THREAT-03`。

这些项目直接受 XP x86、CentOS 7、Unicode 路径、双管道、临时秘密和加载劫持影响。负责人可以决定“希望什么体验”，但不能在没有故障注入和真实平台证据时确认“已经能够保证”。

### 4.3 62 个没有 decision group 直接覆盖的 AQ

完整清单如下：

`AQ-016`、`AQ-035`、`AQ-041`、`AQ-042`、`AQ-043`、`AQ-057`、`AQ-058`、`AQ-105`、`AQ-121`、`AQ-122`、`AQ-123`、`AQ-124`、`AQ-128`、`AQ-129`、`AQ-130`、`AQ-143`、`AQ-146`、`AQ-147`、`AQ-148`、`AQ-155`、`AQ-157`、`AQ-171`、`AQ-184`、`AQ-193`、`AQ-210`、`AQ-212`、`AQ-220`、`AQ-222`、`AQ-247`、`AQ-266`、`AQ-267`、`AQ-270`、`AQ-274`、`AQ-275`、`AQ-276`、`AQ-277`、`AQ-278`、`AQ-282`、`AQ-283`、`AQ-284`、`AQ-285`、`AQ-286`、`AQ-287`、`AQ-288`、`AQ-289`、`AQ-290`、`AQ-291`、`AQ-313`、`AQ-317`、`AQ-318`、`AQ-319`、`AQ-320`、`AQ-322`、`AQ-323`、`AQ-324`、`AQ-325`、`AQ-346`、`AQ-347`、`AQ-348`、`AQ-349`、`AQ-350`、`AQ-357`。

这些 AQ 可再分为：

- **已有大组选项但漏引用**：例如 `AQ-035` 工具并发应归 `TS-10`；`AQ-041/042/043` 应归 `CX-01/02/05`；`AQ-313` 应归 `PJ-05`；`AQ-317..320` 应归 `M05-11/12`；`AQ-350` 应归 `RF-11`。这类修正 `关联` 即可。
- **必须补进负责人选项**：`.prompt` 交互 `AQ-057/058`、多工具部分失败 `AQ-105`、进程/工具输出 `AQ-121..130`、reasoning `AQ-222`、非 TTY `AQ-247`、plan mode `AQ-346`。
- **技术设计/证明，不应孤立投票**：加载路径 `AQ-267`、时钟 `AQ-270`、JSON/tool batch 安全 `AQ-322..325`、secret temp 生命周期 `AQ-277/278`。应把它们写进相应 `T` 规格和 proof gate。
- **已有回复但尚未成为决定**：单 Model 实例 `AQ-016`、显示模式删除 `AQ-157`、工作区/Git 根边界部分 `AQ-212`。应对照原回复补归档，不能让“状态：已答/部分”永远停在题库。

## 5. 没有具体 readiness gate 直接引用的 116 个 ID

语义上，第 3 节已经为每个 namespace 分配 gate；但当前 `ARCHITECTURE-READINESS.md` 的 gate 源清单没有落实这些映射。尤其 `AR-P1-01` 至 `AR-P1-12` 都没有逐项 `主要来源`，因此机器无法证明某个 P1 已覆盖哪些 requirement。

当前 116 个直接引用缺口是：

- `PROD`：`PROD-02`、`PROD-03`、`PROD-04`、`PROD-05`、`PROD-06`、`PROD-07`、`PROD-09`、`PROD-10`、`PROD-13`、`PROD-14`、`PROD-15`。
- `ARCH/RUNTIME/CONC/PERF`：`ARCH-01` 至 `ARCH-04`、`RUNTIME-03`、`RUNTIME-05`、`CONC-04`、`PERF-01` 至 `PERF-03`。
- `PLAT`：`PLAT-02`、`PLAT-03`、`PLAT-05` 至 `PLAT-12`。
- `NET/FMT`：`NET-01`、`NET-02`、`NET-04` 至 `NET-08`、`NET-10` 至 `NET-12`、`FMT-03`、`FMT-05` 至 `FMT-07`。
- `INSTR/CHANGE`：`INSTR-01` 至 `INSTR-05`、`CHANGE-06`、`CHANGE-07`。
- `LOOP`：`LOOP-01`、`LOOP-02`、`LOOP-04` 至 `LOOP-09`、`LOOP-11` 至 `LOOP-19`、`LOOP-21`、`LOOP-23` 至 `LOOP-27`。
- `DIAG`：`DIAG-01`、`DIAG-02`、`DIAG-04` 至 `DIAG-13`。
- `TEST/EVAL`：`TEST-01` 至 `TEST-10`、`EVAL-01` 至 `EVAL-08`。
- `UPDATE/DOC/WEB`：`UPDATE-01`、`UPDATE-02`、`DOC-01` 至 `DOC-05`、`WEB-01` 至 `WEB-04`。

这里的 range 都只包含实际已定义 ID；编号空洞不因写范围而创建新 requirement。正式修复时应把第 3 节的语义映射写回每个 gate 的 `主要来源`，并由机器验证每个 P0/P1 requirement 至少到达一个 gate。

## 6. 重复归属与高扇出

### 6.1 owner 重复：当前为零

按 namespace 主责，335 个 ID 都只有一个 owner。下面这些看起来重复、实际应保持“owner/consumer”关系：

| 主题 | 唯一 owner | Consumer | 风险 |
| --- | --- | --- | --- |
| 性能预算 `PERF-*` | 22 应用运行时 | 20 测试、16 发布 | 测试不能测着测着改预算 |
| 测试分层/替身 `TEST-02/03` | 20 测试 | `REL-06/07` | 16 号不应维护第二套测试架构 |
| 平台完整验收 `TEST-08` | 20 测试 | `REL-08/13` | 发布只判断证据是否满足声明 |
| 文档追踪 `DOC-05` | 16 发布/文档交付 | `TEST-10`、`RF-11` | 测试负责证据，发布负责公开状态 |
| 数据分类 `PROD-08` | 00 产品 | 03/05/08/10/15 | 各子系统不能自行发明相反默认值 |
| Prompt/项目指令 | 18 Prompt | 08 权限、09 Loop、10 Context | 项目文本不能借“配置”扩大权限 |

### 6.2 需要合并裁决的语义重复

下列 ID 不是 owner 重复，但目前容易出现两套答案：

1. `PROD-09` 与 `PROD-15` 都处理语言；前者仍写本地化选择，后者已经拆分 UI、模型回复、配置和机器字段。应由 `PROD-15` 成为规范，`PROD-09` 删除或改为兼容别名。
2. `TUI-12` 与 `TUI-21` 都定义自动能力降级；前者应拥有探测输入，后者只定义跨 renderer 语义等价。
3. `TUI-17` 与 `TUI-27` 都定义线性可读/无颜色；前者是产品验收原则，后者是可执行 golden/reader 测试。
4. `REL-06`/`REL-07` 分别重复 `TEST-02`/`TEST-03`。发布条目应改成“消费 20 号已通过证据”，不再定义测试方法。
5. `REL-08` 与 `TEST-08` 都描述真实平台完整测试。20 号拥有测试内容，16 号拥有平台声明和放行结果。
6. `DIAG-01/02/03` 与 `DIAG-10/11/12` 有总则/细化关系，未来 `ErrorRegistryV1` 应只生成一套字段、归因和 retry presentation，不建立两套 error model。

### 6.3 高扇出 ID

以下 ID 被至少四个 decision groups 引用，负责人回复转换成规格时必须做冲突合并，不能让“后处理的包覆盖先处理的包”：

- `CTX-07`：`PP-05`、`PP-10`、`AL06-03`、`AL06-06`、`AL06-11`、`CX-03`。
- `DIAG-05`：`PJ-02`、`PP-05`、`M05-11`、`M05-12`、`ED-01`。
- `COMP-08`：`PP-09`、`AL06-10`、`AL06-12`、`CX-12`。
- `CTX-17`：`PJ-06`、`AL06-03`、`AL06-12`、`CX-04`。
- `CTX-27`：`PJ-06`、`M05-06`、`AL06-10`、`CX-07`。
- `LOOP-04`：`TU-04`、`TU-11`、`AL06-08`、`AL06-09`。
- `LOOP-06`：`TU-04`、`AL06-04`、`AL06-05`、`AL06-06`。
- `LOOP-10`：`AL06-02`、`AL06-04`、`AL06-07`、`ED-02`。
- `PERF-02`：`AL06-09`、`CX-11`、`RF-09`、`RF-10`。
- `SAFE-03`：`TU-07`、`AL06-07`、`TS-04`、`TS-05`。
- `SAFE-09`：`M05-02`、`M05-05`、`M05-12`、`ED-07`。
- `TUI-26`：`PJ-08`、`PJ-09`、`TU-09`、`CX-09`。

## 7. 现有互相矛盾或尚未被统一解释的项目

### 7.1 题库已经明确标记的三处矛盾

| 项目 | 冲突 | 必须怎样收口 |
| --- | --- | --- |
| `AQ-045` ASCII 限制作用域 | “只支持 English/内部不使用非 ASCII”与中文路径、用户正文、Context XML 可移植要求冲突 | 程序自带 UI、命令、element/field/enum 固定 ASCII；用户数据与路径保持 UTF-8/平台原始身份。显示替换不能改变 hash/文件目标 |
| `AQ-132` 只使用 INI/XML | 单 XML 正确提交仍需 temp/lock/recovery；support/self-test 也可能显式输出文件 | 把承诺精确成“长期权威用户数据只有 INI/XML”，并单列短期辅助文件的创建、回收和非事实源地位；若连临时文件也禁止，必须接受无法安全发布的事实 |
| `AQ-202` self-test 第三阶段 | “完整测试”容易被误解成 LLM 语义评分是 hard gate；但 LLM 判断本质非确定 | Stage 1/2 的 schema/protocol 是 hard result；Stage 3 只作带 Model/Prompt/digest 的 advisory，不能自动改配置或覆盖确定性失败 |

### 7.2 已通过 supersede 解决、但工具必须识别的历史冲突

- `D-005` → `D-006` → `D-018`：最终规则是 main 本地提交可以，默认不 push。
- `D-020` 的独立开关 → `D-027`：用户配置不再有 `UseTerminationEvaluator`；完成复核并入 `DoubleCheck`，但 request identity 仍独立。
- `Cautious` permission profile → `D-021`：`.cautious` 只改 Context 的 `DoubleCheck` override，不切换 Permission。

历史记录可以保留，但 schema/help/template/测试只能引用最终决定，不能因为旧文字仍存在就生成旧字段。

### 7.3 尚未进入决定日志的负责人回复

1. 首批综合回复已经写明“v0.1 不需要 MCP”，但 `DECISIONS.md` 没有对应决定，21 号文档仍把整张扩展矩阵标为候选。
2. 负责人说配置损坏时 yaca 无法启动，同时又要求用 `model-repl` 创建首份配置和强 self-test。决策包把它解释成“Agent 正常启动失败，但受限 bootstrap 管理入口可运行”；这个解释合理但尚未被明确确认，不能当作事实。
3. 负责人说“相信模型、原始工具、不需要 Sandbox”，同时 `DoubleCheck` 又要获得更多安全。必须明确这是策略审批/复核而非 OS 隔离，尤其 raw shell 不能被 Read/Write/Network 细粒度声明伪装约束。
4. 负责人要求 zip 分平台、由 luainstaller 打包，但“zip 是便携根、安装输入还是外层装配物”仍未确认；这会改变 `__yaca__` 数据位置、升级和多副本语义。

## 8. 已知技术事实与证明缺口

这些不是 A/B/C 偏好，不能靠负责人回复关闭：

| 事实/风险 | 当前证据 | 仍需的 proof |
| --- | --- | --- |
| luainstaller Windows x86 | 当前 profile guard 拒绝非 x86_64，随附 MSVC recipe/tests 固定为 x64；这不证明底层 launcher/bundler 无法适配 x86，XP 也未验证 | 先 qualification 现有设计，按证据做必要 guard/toolchain/profile 适配；同一最终 x86 包在 XP--11 验收 |
| 当前 Linux `bin/` ABI | 现有工具为 ELF32/i386，curl 是 x32 ABI，不是目标普通 x86_64 | 从最小 allowlist 重建 ELF64/x86_64 资源并在 CentOS 7 验收 |
| Win32 curl/UPX | PE32 方向正确，但 UPX stub 遮蔽真实 imports | 审计未压缩来源、CRT/API/TLS/DLL，再对最终包装物重测 |
| Lua 5.5 XML binding | LuaExpat 1.5.2 + Expat 2.8.2 现代 Linux smoke 可构建；上游公开支持止于 Lua 5.4 | Windows x86/XP 与 CentOS 7 原生构建、ABI、DTD/entity off、资源攻击 corpus |
| 单 XML durable commit | 闭合根后直接追加 child 不是 well-formed XML；每事件整文件重写会形成 O(n²) I/O | crash-point、磁盘满、flush/replace、第二 writer、大 Context/x86 内存与延迟基准；失败后再决定 sidecar/WAL 或硬上限 |
| full-duplex TUI | Lua coroutine 不会让阻塞 console/curl/process 自动非阻塞；XP 又缺部分现代取消 API | `start/poll/cancel/join/close` 最小端口在 XP/CentOS 的双请求、双管道、输入、取消和关闭验证 |
| 模块/DLL/工具加载 | 工作区是进程 cwd；默认搜索可能在权限系统前执行陌生代码 | CWD/PATH/module/DLL 劫持 fixtures，绝对 manifest path 与 no-replace/open-verify 证明 |
| secret-safe curl | 明文 Key 在 INI 已接受，但 argv/XML/log 禁止泄漏 | stdin/config/temp 两条候选的进程列表、权限、崩溃残留、redirect 和泄漏扫描 |

## 9. 回答后的确定性转换流程

负责人回复某个 decision group 后，不能直接把该组标成“完成”。每个回复必须依次经历：

1. **解析回复**：保存 group ID、选择、例外、负责人原文和时间；未明确回复保持待决。
2. **冲突检查**：查本文件的高扇出 ID、`DECISIONS.md` supersede 链和其他已回复 group；冲突时先向负责人呈现具体差异，不按文件顺序覆盖。
3. **责任分流**：`O` 写决定；`J` 同时产生需要证明的降级/平台条件；`T` 不写成负责人偏好。
4. **更新 owner 规格**：只由第 3 节 owner 写 normative state/schema/algorithm；consumer 文档引用它。
5. **更新 gate**：把 requirement、decision、spec、contract test、target evidence 写进同一 gate 记录。
6. **机器验证**：所有 ID 有 owner、group 或明确 `T/deferred` 分类、gate 和未来 test；公共名称/枚举唯一。
7. **才允许规划实现**：P0 全部有已确认产品结论、可执行规格与必需技术 proof；没有“推荐即决定”或“问完即实现”。

建议为每条最终记录固定以下字段：

| 字段 | 含义 |
| --- | --- |
| `requirement_ids` | checklist ID 与相关 AQ |
| `decision_group` | 负责人实际回复的 group；纯 `T` 项写 `technical` |
| `decision_ids` | `DECISIONS.md` 中生效决定及 supersedes |
| `owner_subsystem` | 本文件第 3 节的唯一 owner |
| `normative_spec` | schema/state table/registry 的稳定名称与版本 |
| `readiness_gates` | 一个或多个具体 `AR-P0/P1` |
| `contract_tests` | 纯 Lua/port/conformance/fault/golden/e2e 中的稳定 test ID |
| `target_evidence` | 对应源码、最终 zip、平台、版本与 hash 的证据 |
| `status` | proposed/confirmed/specified/proven/implemented/released，不能互相冒充 |

## 10. 本审计的完成判定

本文件只证明“当前追踪状态已被精确盘点”，不证明架构已经 ready。进入实施计划前至少还需要：

- 把 101 个 checklist 直接缺口分别接入 decision group、`T` 规格或已确认/deferred 决定；
- 把 62 个 AQ 直接缺口接入现有组或明确归入技术 proof；
- 给 12 个 P1 gate 增加可机器读取的 `主要来源`，并消除 116 个 gate 直接引用缺口；
- 为 21 号扩展边界补一个可关闭的范围决定，或正式增加 `EXT-*`；
- 解决 `AQ-045`、`AQ-132`、`AQ-202` 三处显式矛盾；
- 对第 8 节的硬技术门形成可重复证据；
- 负责人回复后完成 group → decision → owner spec → gate → test/evidence 的双向追踪。

在这些条件完成前，正确状态仍是“设计覆盖广、追踪和证明未闭环”，而不是“问题已经问完，可以编码”。
