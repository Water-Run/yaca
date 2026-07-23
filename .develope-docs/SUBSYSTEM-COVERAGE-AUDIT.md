# 子系统设计覆盖审计

更新日期：2026-07-18

状态：独立审计基线；只评价现有文档是否足以转写为规范，不把任何候选提升为已确认决定

现行覆盖说明：本文保留 2026-07-18 的审计判断作为历史快照；其后 D-044 已把 Web 从“暂缓/待确认”收口为 v0.1 明确排除。当前规范与重开门以 [`subsystems/17-web.md`](subsystems/17-web.md) 为准，本文后文的“暂缓”不再表示现行待决。

计数口径：本文的 360 个 AQ 是补缝前快照；它识别出的两项新问题已经由主题库承接。修复后的当前总数以 `DESIGN-CHECKLIST.md`、`QUESTIONS.md` 和 `DECISION-COVERAGE-REPAIR.md` 为准。

## 结论先行

23 个编号子系统已经覆盖了产品的主要问题域，不存在“完全没想到 AgentLoop、TUI、Tool Calling、安全、Context 或旧平台”这一类一级空白。真正阻止项目进入实施计划的，是下面三种性质不同的缺口：

1. **文档缺失**：许多文档写出了职责、风险和推荐，却还没有输入/输出、状态转移、错误、配置、可观测字段和验收条件。这个缺口不需要项目负责人再做产品选择，设计侧可以在决定确认后直接补成规范。
2. **负责人待决**：正常完成语义、raw shell 权限、单 XML 的产品保证、TUI 页面、配置默认、undo 范围等会改变用户承诺，不能由实现者替项目负责人选择。
3. **技术证明待做**：XP 事件泵、LuaExpat/Lua 5.5 ABI、XML 提交、文件 no-replace、curl 秘密传递、终端全双工和 luainstaller Win32 x86 不是多选题；必须用原型、故障注入和目标机证据证明。

按现状，只有 11 号上下文定位系统在“可直接收口为规范”的维度上接近完整；01、09、10、14、18、19、20、21、22 已形成较深的候选设计，但仍有关键决定或精确契约缺失；02、03、04、06、07、08、12、13、15、16 仍需要明显扩写。17 号 Web 已明确暂缓，不应为了表格好看而补出一套 v0.1 Web 设计。

本审计的核心判断是：**继续无差别增加问题数量，收益已经低于把现有答案收敛成规范的收益**。现有 360 个原子问题已覆盖绝大部分负责人选择；后续应以状态机、schema、registry、truth table 和可执行验收补足深度。

## 审计范围与方法

本轮逐篇阅读了 [`subsystems/TEMPLATE.md`](subsystems/TEMPLATE.md) 与 [`subsystems/00-product-and-compatibility.md`](subsystems/00-product-and-compatibility.md) 至 [`subsystems/22-application-runtime-and-concurrency.md`](subsystems/22-application-runtime-and-concurrency.md)。同时用 [`DESIGN-CHECKLIST.md`](DESIGN-CHECKLIST.md)、[`QUESTIONS.md`](QUESTIONS.md) 和 [`ARCHITECTURE-READINESS.md`](ARCHITECTURE-READINESS.md) 判断某个缺口是“已有问题但尚未转成规范”，还是题库中真的没有问到。

每个系统按 14 个维度评价：

| 简写 | 维度 | 本轮要求 |
| --- | --- | --- |
| `RN` | 范围/非目标 | 做什么、不做什么、何时重新评估 |
| `API` | 对外契约 | 入口、输入、输出、不变量、可替换边界 |
| `DATA` | 数据模型 | schema、ID、所有权、寿命、版本 |
| `FLOW` | 状态/流程 | 正常、取消、失败、并发和恢复转换 |
| `DEP` | 依赖 | 上游、下游、禁止反向依赖 |
| `CFG` | 配置 | 字段、默认、覆盖、生效点、无效值 |
| `ERR` | 错误/恢复 | typed error、重试、部分成功、崩溃恢复 |
| `SEC` | 安全/隐私 | 权限、秘密、不可信输入、导入/导出 |
| `COMPAT` | 旧平台兼容 | XP/Win32 x86、CentOS 7、Lua 5.5、旧终端 |
| `PERF` | 性能/资源 | 时间、内存、大小、队列、背压和超限结果 |
| `OBS` | 可观测性 | 事件、状态、错误 ID、审计和诊断证据 |
| `TEST` | 测试 | 单元契约、故障注入、平台证据、完成定义 |
| `UX` | 用户体验 | 页面、提示、确认、脚本行为、可行动错误 |
| `STATUS` | 决策状态 | 已确认、候选、未采用、待决是否能被机械区分 |

矩阵中的标记含义：

| 标记 | 含义 |
| --- | --- |
| `足` | 对当前设计阶段已足够，可在决定确认后直接规范化；不表示已经批准实现 |
| `部` | 已触及，但仍缺字段、状态、错误、常量、证据或负责人选择 |
| `缺` | 文档未给出可用契约，实施者必须自行发明 |
| `免` | 对该系统有意不适用，或由明确上游拥有；不是遗漏 |

## 23 × 14 覆盖矩阵

为避免一张 15 列表在 80 列终端中不可读，14 个维度拆为两张 23 行矩阵。两表同行合起来就是完整的 23 × 14 审计。

### 契约与控制矩阵

| 系统 | RN | API | DATA | FLOW | DEP | CFG | ERR |
| --- | --- | --- | --- | --- | --- | --- | --- |
| [00 产品/兼容](subsystems/00-product-and-compatibility.md) | 部 | 缺 | 部 | 缺 | 部 | 免 | 缺 |
| [01 平台抽象](subsystems/01-platform-abstraction.md) | 足 | 部 | 部 | 部 | 足 | 免 | 部 |
| [02 进程/资源](subsystems/02-process-and-resources.md) | 足 | 缺 | 缺 | 部 | 足 | 部 | 部 |
| [03 网络传输](subsystems/03-network-transport.md) | 足 | 部 | 部 | 部 | 足 | 部 | 部 |
| [04 数据格式](subsystems/04-data-formats.md) | 足 | 缺 | 部 | 部 | 足 | 免 | 部 |
| [05 配置](subsystems/05-configuration.md) | 足 | 部 | 部 | 部 | 足 | 部 | 部 |
| [06 模型协议](subsystems/06-model-protocols.md) | 足 | 部 | 部 | 部 | 足 | 部 | 部 |
| [07 工具](subsystems/07-tool-system.md) | 部 | 部 | 部 | 部 | 足 | 部 | 部 |
| [08 权限/安全](subsystems/08-permission-and-safety.md) | 足 | 部 | 部 | 部 | 部 | 部 | 部 |
| [09 AgentLoop](subsystems/09-agent-session.md) | 足 | 部 | 部 | 足 | 足 | 部 | 部 |
| [10 Context 存储](subsystems/10-context-storage.md) | 足 | 部 | 部 | 部 | 足 | 部 | 部 |
| [11 Context 定位](subsystems/11-context-indexing.md) | 足 | 足 | 足 | 足 | 足 | 部 | 足 |
| [12 压缩](subsystems/12-context-compaction.md) | 足 | 缺 | 部 | 部 | 足 | 部 | 部 |
| [13 CLI](subsystems/13-cli.md) | 足 | 部 | 部 | 部 | 足 | 免 | 部 |
| [14 TUI](subsystems/14-tui.md) | 足 | 部 | 部 | 部 | 足 | 足 | 部 |
| [15 诊断/日志](subsystems/15-diagnostics-and-logging.md) | 足 | 缺 | 部 | 部 | 足 | 部 | 部 |
| [16 打包/发布](subsystems/16-packaging-and-release.md) | 部 | 部 | 部 | 部 | 足 | 部 | 部 |
| [17 Web](subsystems/17-web.md) | 部 | 免 | 免 | 免 | 部 | 免 | 免 |
| [18 Prompt/工作区指令](subsystems/18-prompt-and-workspace-instructions.md) | 足 | 部 | 足 | 足 | 足 | 部 | 足 |
| [19 改动/撤销](subsystems/19-change-transactions-and-undo.md) | 足 | 部 | 足 | 足 | 足 | 部 | 足 |
| [20 测试/评估](subsystems/20-testing-and-agent-evaluation.md) | 足 | 部 | 部 | 足 | 足 | 部 | 足 |
| [21 扩展边界](subsystems/21-extension-boundary.md) | 足 | 部 | 部 | 部 | 足 | 部 | 足 |
| [22 运行时/并发](subsystems/22-application-runtime-and-concurrency.md) | 足 | 部 | 部 | 足 | 足 | 部 | 部 |

### 运行与体验矩阵

| 系统 | SEC | COMPAT | PERF | OBS | TEST | UX | STATUS |
| --- | --- | --- | --- | --- | --- | --- | --- |
| [00 产品/兼容](subsystems/00-product-and-compatibility.md) | 部 | 足 | 缺 | 缺 | 部 | 缺 | 足 |
| [01 平台抽象](subsystems/01-platform-abstraction.md) | 部 | 足 | 部 | 部 | 缺 | 免 | 足 |
| [02 进程/资源](subsystems/02-process-and-resources.md) | 部 | 足 | 部 | 部 | 部 | 部 | 足 |
| [03 网络传输](subsystems/03-network-transport.md) | 部 | 足 | 部 | 部 | 缺 | 部 | 足 |
| [04 数据格式](subsystems/04-data-formats.md) | 部 | 部 | 部 | 缺 | 部 | 免 | 足 |
| [05 配置](subsystems/05-configuration.md) | 部 | 部 | 缺 | 部 | 部 | 部 | 足 |
| [06 模型协议](subsystems/06-model-protocols.md) | 部 | 免 | 部 | 部 | 缺 | 免 | 足 |
| [07 工具](subsystems/07-tool-system.md) | 部 | 部 | 部 | 部 | 缺 | 部 | 足 |
| [08 权限/安全](subsystems/08-permission-and-safety.md) | 部 | 部 | 缺 | 部 | 缺 | 部 | 足 |
| [09 AgentLoop](subsystems/09-agent-session.md) | 部 | 部 | 部 | 部 | 部 | 部 | 足 |
| [10 Context 存储](subsystems/10-context-storage.md) | 部 | 部 | 部 | 部 | 部 | 部 | 足 |
| [11 Context 定位](subsystems/11-context-indexing.md) | 部 | 足 | 足 | 部 | 足 | 足 | 足 |
| [12 压缩](subsystems/12-context-compaction.md) | 部 | 缺 | 部 | 部 | 缺 | 部 | 足 |
| [13 CLI](subsystems/13-cli.md) | 部 | 足 | 免 | 部 | 缺 | 部 | 足 |
| [14 TUI](subsystems/14-tui.md) | 足 | 足 | 部 | 部 | 部 | 部 | 足 |
| [15 诊断/日志](subsystems/15-diagnostics-and-logging.md) | 部 | 部 | 缺 | 部 | 缺 | 部 | 足 |
| [16 打包/发布](subsystems/16-packaging-and-release.md) | 部 | 足 | 部 | 部 | 部 | 部 | 足 |
| [17 Web](subsystems/17-web.md) | 免 | 部 | 免 | 免 | 免 | 免 | 足 |
| [18 Prompt/工作区指令](subsystems/18-prompt-and-workspace-instructions.md) | 足 | 部 | 部 | 足 | 缺 | 部 | 足 |
| [19 改动/撤销](subsystems/19-change-transactions-and-undo.md) | 足 | 部 | 部 | 足 | 部 | 部 | 足 |
| [20 测试/评估](subsystems/20-testing-and-agent-evaluation.md) | 部 | 足 | 足 | 足 | 足 | 免 | 足 |
| [21 扩展边界](subsystems/21-extension-boundary.md) | 足 | 足 | 部 | 部 | 足 | 部 | 足 |
| [22 运行时/并发](subsystems/22-application-runtime-and-concurrency.md) | 部 | 足 | 足 | 部 | 部 | 部 | 足 |

### 如何解读矩阵

- `STATUS` 全部为“足”，说明现有文档普遍能诚实地区分候选和确认；主要问题不是偷换状态，而是候选还没变成规范。
- `DEP` 普遍较好，说明 23 个系统的划分基本可用；后文列出的孤儿责任主要发生在交叉接缝，而不是完全没有依赖意识。
- `API`、`ERR`、`TEST` 是整体最弱的三列。多数文档描述了“应该做到什么”，没有描述调用者怎样机械地知道成功、取消、unknown、部分成功和恢复结果。
- `PERF` 的“部”经常只表示“提到了上限”；没有预算值、校准方法和超限 typed result 时，不能视为性能契约。
- `UX` 的“部”不是要求每个底层模块自己画页面，而是它至少要给 13/14 号系统可投影的状态、进度、确认内容和下一步。完全由自由文本错误代替就不够。
- 17 号大量“免”是正确的暂缓结果。它只需冻结 v0.1 排除状态、复用边界和重新进入设计的条件。

## 逐系统关键发现

### 00 至 04：产品与底层能力

- **00 产品契约**：平台矩阵清楚，但缺安装到升级/卸载的旅程状态表、v0.1 完整支持/排除矩阵、离线/性能承诺和用户可感知失败结果。它还没有把“完整可用版本”变成可验收产品闭环。
- **01 平台抽象**：模块边界、依赖方向和 XP 文件 API 风险较强；仍缺每个 port 的函数级结果、capability/error 枚举、启动/关闭生命周期和契约测试。`path/fs/text/clock` 只是名字，还不是可执行接口。
- **02 进程与资源**：当前最薄的 P0 文档之一。没有 `start/poll/cancel/join/close`、ProcessSpec、ProcessEvent、ProcessResult、子进程树状态机、环境/编码/输出 backpressure 和 helper 崩溃契约。
- **03 网络传输**：重试阶段表和秘密风险方向正确，但没有 TransportRequest/Event/Result/Error、curl adapter 生命周期、redirect/CA/proxy 规则表、取消后 join、测试 fixture 和进度投影。
- **04 数据格式**：XML 库研究深入，但 JSON 与 INI 仍只有题目；缺 parser/writer streaming API、统一 limit/error、确定性 writer 规范、格式版本迁移接口和 fuzz/property test。XML 库可行不等于格式系统完整。

### 05 至 09：配置、模型、工具、安全与 AgentLoop

- **05 配置**：已另有完整候选 catalog，但本系统尚无 accepted schema。需要把 load/validate/edit/save/migrate/bootstrap 变成状态机，并给出 draft、外部修改、secret 输入、备份/恢复和 source/effective value 的接口。
- **06 模型协议**：canonical 轮廓存在，精确 wire profile、event schema、content block 顺序、tool-call assembly、typed finish/refusal/length 和 purpose capability 表仍缺。没有 conformance fixture 就不能称 OpenAI-compatible 已支持。
- **07 工具系统**：缺正式 tool registry 和每个工具的参数/result schema。list/read/search/write/patch/rename/delete/exec 是否进入 v0.1、名称、大小限制、expected digest、特殊文件、错误、模型可见文本和 UI 摘要都未冻结。
- **08 权限与安全**：raw shell 的诚实边界已写清，这是重要优点；但 tool × capability × profile、approval snapshot、有效期、batch approval、DoubleCheck action-review、人工 override、导入覆盖和非 TTY fail-closed 仍是候选。
- **09 AgentLoop**：状态图和核心不变量已具备骨架；仍缺 typed terminal control、完整 transition table、事件/ID schema、同刻事件优先级、budget ledger、取消收口、DoubleCheck 拒绝/失败、side 并发和逐状态 golden trace。

### 10 至 14：Context、压缩与交互入口

- **10 Context 存储**：诚实指出单 XML 的物理限制，但“完整接盘”还没有 schema，commit/lock/temp/previous-valid/recovery 也没有状态机。必须把 durable 屏障和副作用去重与 09/19/22 对齐。
- **11 Context 定位**：当前最完整的子系统；服务分层、算法、复杂度、错误和浏览器均有较深说明。未收口项集中在 LogicalPathCodec、hash vectors、损坏候选优先级、active rename/delete/import 和平台路径技术证明。
- **12 压缩**：算法思想正确但文档偏短。缺 ModelViewAssembler 接口、Summary schema、必保原子组形式、token estimator、trigger/no-gain/cancel 状态、purpose-specific 隐私和确定性重建测试。
- **13 CLI**：主入口和 Resolver 接缝明确，但缺正式 grammar、command registry、唯一简称、`--`、点命令转义、command × AgentState、machine output、exit class 和非 TTY truth table。
- **14 TUI**：兼容方向和安全显示边界较强，但仍是视觉/输入候选。需要冻结页面全集、ASCII 词汇、输入状态机、draft/async 输出、确认默认、busy 动作、error detail、40 列、颜色映射和 golden transcript。

### 15 至 18：诊断、发布、暂缓界面与 Prompt

- **15 诊断与日志**：当前职责远大于篇幅。需要统一 Error、Diagnostic、SelfTestCheck、SelfTestRun、SupportReport schema；三阶段状态机、根因去重、LogLevel 与 durable fact 分界、stderr/XML 路由、脱敏和页面/非 TTY 输出也未规范化。
- **16 打包与发布**：平台目标和 luainstaller 硬阻塞记录准确；仍缺 ArtifactManifest、资源 allowlist 的机器契约、build/assemble/verify/package 状态、数据根、zip/安装、升级/降级/卸载、回滚、发布证据和用户文档同步门。
- **17 Web**：v0.1 暂缓是合理的。只需确认它是“明确排除”还是“未排期”，并给出恢复设计前的触发条件；不需要为 IE6、HTTP、安全和页面补虚假设计。
- **18 Prompt/工作区指令**：信任分层、bundle、失败表和不可越权边界很强；缺最终工作区根、文件名/发现、优先级、作用域、freeze/reload、snapshot 内容、token 上限和注入测试。

### 19 至 22：改动、测试、扩展与运行时

- **19 改动/撤销**：已清楚区分最小安全写入与强 undo，这是正确的候选结构。待负责人选择 `AQ-312` 后，应删除未采用分支并把 operation/change evidence 或 preimage/compensation 之一写成规范；两套不能同时留给实现者挑。
- **20 测试/评估**：测试分层、事件证据和平台真实性方向完整；缺正式 TestManifest、ScenarioFixture、TraceMatcher、EvidenceRecord、发布阻断规则、证据存放/保留和运行器选择。
- **21 扩展边界**：未来风险分析充分，但 v0.1 是否正式选择封闭核心仍待确认。确认排除后，首版规范只需保留内置来源 ID/version 和重新开放门槛，不应实施空插件框架。
- **22 运行时/并发**：启动/关闭、单线程领域所有权和背压方向较强；缺异步 port ABI、event priority、queue-by-queue 限额/动作、lease/commit lock 状态、生命周期 error 和 XP/CentOS 原型证据。

## P0 缺口

P0 表示在这些内容闭环前，完整实施计划仍会迫使开发者发明产品行为或物理保证。编号只属于本审计，不新增产品决定。

### 文档缺失：设计侧必须补成规范

| ID | 缺失工件 | 影响系统 | 为什么是 P0 |
| --- | --- | --- | --- |
| `SCA-D01` | 产品旅程与 v0.1 支持/排除状态表 | 00、13、14、16、17、21 | 没有唯一启动、恢复、退出、升级和失败结果 |
| `SCA-D02` | 端口与服务接口 catalog | 01、02、03、04、05、06、07、10、22 | 当前只有模块名，没有机械可替换的 input/result/error/lifecycle |
| `SCA-D03` | 领域 ID、事件和关系 registry | 06、07、09、10、12、19、22 | request/attempt/message/call/operation/approval/compaction 容易重名或错连 |
| `SCA-D04` | AgentLoop 完整状态/转换/终止表 | 09、06、08、10、14、22 | 流结束、询问、取消、复核、工具和恢复没有唯一收口 |
| `SCA-D05` | Tool registry 与 capability/Permission 矩阵 | 07、08、19、05 | raw shell 与 direct tools 的真实保证无法由配置机械推导 |
| `SCA-D06` | Context XML schema 与提交/恢复状态机 | 04、09、10、11、12、15、19、22 | 单 XML、完整接盘和副作用去重都依赖它 |
| `SCA-D07` | typed 配置 schema、bootstrap 和编辑事务 | 05、13、14、15、16 | 配置无效时哪些入口可用、字段怎样生效仍需猜测 |
| `SCA-D08` | Model canonical protocol 与 conformance fixtures | 03、04、06、09 | OpenAI-compatible 不是足够精确的协议契约 |
| `SCA-D09` | TUI 输入状态机、页面 catalog 和 golden transcripts | 09、13、14、15 | 固定快捷键在 XP/cooked/SSH 上没有完整等价行为 |
| `SCA-D10` | 全局 error/diagnostic/exit-class registry | 02 至 16、18 至 22 | 同一根因会被多层改名、重复显示或错误重试 |
| `SCA-D11` | 预算与资源账本规范 | 02、03、06、07、09、10、11、12、22 | request、side、tool、retry、compaction 和 queue 上限目前分散 |
| `SCA-D12` | requirement → decision → spec → test → platform evidence 追踪表 | 全部 | 问题回答完仍不能证明所有承诺已有规范和测试 |

### 项目负责人待决：已有题目，不应由设计侧暗定

| ID | 必须确认的产品边界 | 主要现有问题 | 影响系统 |
| --- | --- | --- | --- |
| `SCA-O01` | v0.1 产品闭环、zip/安装、数据根、升级/卸载 | `AQ-044`、`AQ-215`、`AQ-244`、`AQ-329`、`AQ-330` | 00、01、13、16 |
| `SCA-O02` | typed finish/ask-user/partial/refused 与普通无工具回复 | `AQ-251`、`AQ-252`、`AQ-253` | 06、09、10、14、20 |
| `SCA-O03` | DoubleCheck 动作范围、复核模型、失败/拒绝与敏感视图 | `AQ-020` 至 `AQ-023`、`AQ-109`、`AQ-358` | 05、06、08、09、10 |
| `SCA-O04` | 首版工具集合、raw shell 宽权限、审批和 undo 保证 | `AQ-033` 至 `AQ-039`、`AQ-184`、`AQ-271` 至 `AQ-281`、`AQ-312` | 02、07、08、09、19 |
| `SCA-O05` | 配置字段、默认、INI/XML 覆盖、无效配置 bootstrap | `AQ-131` 至 `AQ-160`、`AQ-282` 至 `AQ-291` | 05、13、14、15 |
| `SCA-O06` | 单 XML 保证、WAL/硬上限、公开写入与热复制 | `AQ-303` 至 `AQ-307` | 04、10、11、12、16 |
| `SCA-O07` | Context 路径、hash、损坏匹配、rename/delete/import/active 生命周期 | `AQ-169` 至 `AQ-180`、`AQ-237`、`AQ-308`、`AQ-354` 至 `AQ-356` | 01、10、11、13、14 |
| `SCA-O08` | Prompt 权威链、工作区根、指令来源和快照 | `AQ-001` 至 `AQ-008`、`AQ-046` 至 `AQ-065`、`AQ-296` | 05、09、10、12、18 |
| `SCA-O09` | 一套 TUI 视觉、页面、提示、确认、状态和非 TTY 行为 | `AQ-066` 至 `AQ-090`、`AQ-293` 至 `AQ-300`、`AQ-331` 至 `AQ-340` | 13、14、15 |
| `SCA-O10` | 测试门、真实模型评估地位和平台“完整测试”的定义 | `AQ-202`、`AQ-204` 至 `AQ-211`、`AQ-343` 至 `AQ-345`、`AQ-357`、`AQ-360` | 00、16、20 |

### 技术证明待做：不能靠负责人选择代替

| ID | 技术证明 | 最低证据 | 影响系统 |
| --- | --- | --- | --- |
| `SCA-T01` | luainstaller Win32 x86/XP profile | 同一 Win32 x86 产物在 XP SP3 至 11 的构建、启动和依赖证据 | 00、01、16 |
| `SCA-T02` | XP/CentOS 异步事件 port | console、curl/网络流、双管道、进程退出、cancel/join 和队列满原型 | 02、03、14、22 |
| `SCA-T03` | LuaExpat 1.5.2 + Expat 2.8.2 + Lua 5.5 | Windows x86/CentOS 7 构建、DTD/entity 禁用、limit/fuzz 和包内加载 | 04、10、16 |
| `SCA-T04` | 单 XML durable commit | 每个崩溃点、磁盘满、replace/flush 失败、第二写者、外改和长会话写放大 | 01、04、10、19、22 |
| `SCA-T05` | 文件身份/no-replace/链接复核 | NTFS、FAT、常见共享盘和 Linux FS 的 symlink/junction/hardlink/竞态 fixture | 01、07、08、11、19 |
| `SCA-T06` | curl/TLS/CA/代理/秘密传递 | Key 不进 argv/日志；redirect、临时残留、取消、解压炸弹和旧 TLS 证据 | 02、03、05、06、15、16 |
| `SCA-T07` | TUI 全双工与旧终端恢复 | XP console、POSIX TTY、`TERM=dumb`、SSH PTY、QuickEdit、Ctrl+C/Esc/EOF | 01、14、22 |
| `SCA-T08` | 受控模块/DLL/工具搜索 | cwd/PATH 中恶意同名 Lua/C/DLL/curl 不会在权限前加载 | 01、02、16、22 |
| `SCA-T09` | Win32 x86 长会话资源预算 | 大 XML、大目录、大输出、反复压缩/切换/恢复的峰值内存与延迟 | 10、11、12、20、22 |
| `SCA-T10` | 跨机语义接盘 | XML 在另一台机器缺 Model、路径、工具、Prompt 来源时的只读检查、映射和继续证据 | 05、06、08、10、18、20 |

## P1 缺口

这些内容不必先于所有 P0 决定，但必须在相应子系统实施计划之前闭环。

| ID | P1 缺口 | 建议工件 |
| --- | --- | --- |
| `SCA-P01` | 01 号没有 port contract tests | platform capability matrix + fake/real adapter suite |
| `SCA-P02` | 02/03 没有输出、重试和进度投影规范 | process/network event vocabulary + UI projection table |
| `SCA-P03` | 04 的 JSON/INI 不如 XML 具体 | JSON/INI grammar、limits、error locations、round-trip fixtures |
| `SCA-P04` | 05 的配置 REPL 页面仍是候选 | controller state、draft diff、secret edit、conflict/recovery transcripts |
| `SCA-P05` | 06 缺 provider refusal/reasoning/usage 的公开显示边界 | purpose × content × persistence × display table |
| `SCA-P06` | 07 缺每个 direct tool 的具体旧平台边界 | tool-by-tool file type/encoding/size/atomicity catalog |
| `SCA-P07` | 08 缺审批文本和授权生命周期 UX | approval request/result schema + timeout/expiry/non-TTY transcripts |
| `SCA-P08` | 12 缺摘要质量与无收益评估 | deterministic builder tests + adversarial compaction evaluation |
| `SCA-P09` | 13 缺 machine output version | stdout schema、stderr contract、exit class compatibility policy |
| `SCA-P10` | 15 缺 self-test/report schema 和根因去重 | check registry + dependency graph + report renderer golden files |
| `SCA-P11` | 16 缺发行 manifest 和迁移/回滚运行手册 | artifact manifest + release evidence manifest + rollback matrix |
| `SCA-P12` | 17 缺明确重新评估条件 | 一页 exclusion/re-entry record；不设计 v0.1 Web |
| `SCA-P13` | 18 缺指令发现的固定 corpus | path/encoding/size/conflict/injection fixtures |
| `SCA-P14` | 19 最小保证与强 undo 分支尚未裁剪 | 选定保证的单一 normative change contract |
| `SCA-P15` | 20 缺证据保存与复现协议 | fixture/evidence versions、retention、re-run identity |
| `SCA-P16` | 21 在排除扩展后仍可能过度预留 | v0.1 seam allowlist；无消费者字段不得进入 runtime |
| `SCA-P17` | 22 缺逐队列背压 truth table | producer/consumer/capacity/full action/loss policy/metric table |

## 跨系统孤儿责任

“孤儿”不表示没人提到，而是多个文档都引用它，却没有一个系统明确拥有最终契约。若不指定主责，实施时会出现重复 table、循环依赖或两个不同真相。

| ID | 孤儿责任 | 当前散落位置 | 建议唯一主责 | 其他系统只提供什么 |
| --- | --- | --- | --- | --- |
| `SCA-X01` | 工作区身份与安全根 | 00、01、07、08、13、18 | 18 定义 WorkspaceIdentity；01 提供路径事实 | 13 提供起点，08 执行权限，07 消费范围 |
| `SCA-X02` | 用户数据根与多发行副本 | 01、10、15、16 | 16 定义安装/portable/升级数据生命周期 | 01 解析平台路径，10/15 使用已确定目录 |
| `SCA-X03` | Model view 装配 | 06、09、10、12、18 | 09 下设 `ModelViewAssembler` | 10 给事实，12 给摘要，18 给 instruction bundle，06 只编码 |
| `SCA-X04` | turn/request/tool/operation 等 ID registry | 06、07、09、10、19、22 | 09 拥有领域 ID；10 只编码持久形式 | provider ID 由 06 作为外部证据保存 |
| `SCA-X05` | 全局预算账本 | 03、05、06、09、12、22 | 09 拥有 turn/purpose ledger；22 施加进程硬限 | 各 adapter 报告用量，不自行重置总账 |
| `SCA-X06` | error category、retryability 和显示去重 | 02 至 16 | 15 拥有 registry 和 projection policy | 源系统产生 typed cause，13/14 不重分类 |
| `SCA-X07` | 数据分类与 purpose-specific 可见性 | 03、05、06、08、10、12、15、18、19 | 08 拥有 policy matrix | 各系统标数据类别并执行矩阵 |
| `SCA-X08` | durable barrier 与副作用提交编排 | 01、09、10、19、22 | 10 拥有 commit/durability；09 决定业务屏障 | 19 给 operation facts，22 调度，01 提供原语 |
| `SCA-X09` | 启动恢复与 unknown operation 收口 | 09、10、11、15、19、22 | 10 拥有 `ContextRecoveryService` | 19 判定文件证据，11 定位，22 编排，15 呈现 |
| `SCA-X10` | command/action registry | 05、11、13、14、15 | 13 拥有 command ID/grammar/state availability | 14 映射按键，05/11/15 实现 application action |
| `SCA-X11` | 原生异步 port ABI | 01、02、03、14、22 | 22 拥有共同 ABI 和事件序列 | 各平台 adapter 实现自己的 capability |
| `SCA-X12` | 发行资源 provenance 与运行时解析 | 02、15、16、22 | 16 拥有 manifest/allowlist | 02 只按 manifest 启动，15 校验，22 固定搜索路径 |
| `SCA-X13` | 跨机导入/映射/继续 | 05、06、08、10、11、18 | 10 拥有 `ContextImportService` | 05 映射 Model/Permission，18 映射指令，08 重算授权 |
| `SCA-X14` | Agent 改动归属与 diff evidence | 07、09、10、19 | 19 拥有 change evidence，即使不提供强 undo | 07 执行动作，09 分配关联 ID，10 持久化 |
| `SCA-X15` | persistent diagnostic 写入 | 09、10、15、22 | 15 决定什么是诊断；10 是唯一持久化端口 | 22 只安排关闭顺序，不另建日志事实源 |

建议把这些主责写入 23 份最终规范的“上游/下游/所有者”段落。它们不要求新建 15 个代码模块；名称表达的是契约归属，而不是提前决定文件数量。

## 建议新增的问题

现有 `AQ-001` 至 `AQ-360` 已覆盖大多数负责人选择。以下只有两项是真正没有被现有题目直接、完整询问的产品问题；其余审计缺口应新增规范，不应再包装成大量选择题。

### `SCA-NQ01` raw shell 命令超过平台传输边界时怎么办

问题：当原始命令超过 Win32/CreateProcess 或目标 shell 可安全传递的长度，或包含无法在该 shell 输入编码中无损表达的字符时，yaca 应当：

- A. 明确拒绝并给出长度/编码错误；
- B. 在受保护临时位置生成脚本，再让固定 shell 执行该脚本；
- C. 自动拆分成多条命令。

推荐 A 作为 v0.1 保证，B 只在独立设计脚本编码、权限、删除、审计和等价性后开放；不推荐 C，因为自动拆分会改变 shell 语义和副作用。它补充 `AQ-119`、`AQ-121`、`AQ-266`，后者确定了 raw command 和 shell 方言，却未处理物理传输上限。

### `SCA-NQ02` 活动会话的工作目录中途失效时怎么办

问题：会话运行中，关联工作目录被外部重命名、删除、卸载或变为不可访问时，是立即停止当前 turn 并保留只读 Context、允许用户显式重新绑定，还是继续用进程仍持有的目录句柄工作？

推荐 fail-stop 当前副作用，Context 继续只读可检查；重新绑定必须是显式动作，生成路径/Prompt/权限的新快照。`CTX-13`/`CTX-27` 已覆盖“恢复时依赖失效”，但没有完整覆盖 active turn 中途失效及在途 tool/cwd 的收口。

这两项若被主审计合并进现有题目，应扩充原问题，而不是为了追求编号继续增加 AQ 数量。

## 建议新增的规范工件

以下工件比继续增加问卷更重要。每份工件都应由负责人决定输入生成，去掉未采用方案后成为单一权威来源。

1. **Product Journey Contract**：启动、配置、创建、恢复、锁冲突、离线、退出、升级、降级、卸载的状态表。
2. **Port Contract Catalog**：path/fs/text/clock/process/network/terminal 的函数、结果、capability、lifecycle 和 fake adapter 约束。
3. **Domain Registry**：AgentState、terminal outcome、event、ID、request purpose、tool result、approval 和 error 的唯一拼写与版本。
4. **AgentLoop Transition Specification**：逐状态合法事件、guard、durable barrier、输出、取消和恢复。
5. **Tool and Permission Contract**：完整 tool descriptor/result 与 tool × capability × profile 矩阵。
6. **Configuration Normative Schema**：字段 catalog、INI grammar、XML override、bootstrap、migration 和 editor transaction。
7. **Model Protocol Profile**：wire fixture、canonical events、content ordering、typed control 和 purpose capability。
8. **Context XML Public Read Schema**：事件/关系、model-view manifest、日志/会话参数、版本、limit 和 reader conformance。
9. **Context Commit and Recovery Protocol**：lock/temp/previous-valid、flush/replace、crash truth table、external reader 和 hard limit。
10. **Model View and Compaction Specification**：instruction、facts、summary、recent atoms、token estimate、switch/rebuild。
11. **CLI/Action Registry**：长名、唯一简称、参数、TTY 条件、AgentState、stdout/stderr 和 exit class。
12. **TUI Experience Book**：页面 catalog、固定英文文案、ASCII transcripts、40/80 列、raw/cooked、busy/approval/error/recovery。
13. **Diagnostic and Self-Test Registry**：check dependency、阶段、联网/费用、error ID、根因去重和报告 schema。
14. **Release Artifact Manifest**：来源、版本、hash、许可证、ABI/API、CRT/TLS、包路径、平台证据。
15. **Verification Matrix**：每项 invariant 的 normal/failure/platform/soak fixture 和保存证据。

## 建议收口顺序

这个顺序按“减少返工”而不是文档编号排列：

1. 先确认 00 的产品旅程、v0.1 排除项和 16 的数据/发行形态。
2. 同时确认 09 的 terminal intent、07/08/19 的工具/权限/undo 保证、05 的配置/启动保证。
3. 在产品承诺稳定后冻结 Domain Registry、Port Contract 和 Error Registry。
4. 冻结 06 的 Model protocol、09 的状态机、18/12 的 Model view，再冻结 10 的 XML schema。
5. 把 10 的 schema 与 01/22 的物理能力合成 commit/recovery 技术验证；不达标时回到负责人选择 WAL 或硬限制。
6. 冻结 13/14/15 的命令、页面、提示和 self-test，使每个领域状态都有确定投影。
7. 用 20 的验证矩阵证明 XP/CentOS、长会话、取消、崩溃、秘密和跨机接盘。
8. 只有 P0 追踪全部闭环，才把规范拆成逐子系统实施计划；仍包含“任选一种”“以后确定”的规范不能进入编码。

## 审计完成标准

本文件只证明“现有 23 个子系统文档在哪些维度够或不够”，不证明项目已经实施就绪。后续若满足以下条件，才可把本审计标记为已收口：

- 所有 `SCA-O*` 已由项目负责人明确回复并归档；
- 所有 `SCA-D*` 已转成去除未采用分支的 accepted specification；
- 所有 `SCA-T*` 已有目标平台或明确可接受降级证据；
- 所有 `SCA-X*` 已指定唯一主责，依赖方向无循环；
- `SCA-NQ01`、`SCA-NQ02` 已并入正式题库或由既有决定明确覆盖；
- requirement、decision、spec、test 和 release evidence 能双向追踪。
