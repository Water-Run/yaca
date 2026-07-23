# 第四轮敌对式与发散式设计缺口审计

更新日期：2026-07-18

状态：独立审计底稿；不把任何推荐升级为决定，不开始编码

计数口径：本文故意保留 `AQ-001` 至 `AQ-360` 和 101 组的审计输入快照；其后新增的正式 AQ、11 号补缝包和追踪修复在主文档中维护，不反向篡改本报告的发现依据。

## 结论先行

现有 `AQ-001` 至 `AQ-360`、101 个成套决策组、23 份子系统文档已经覆盖了主要系统名称，但“主题出现过”不等于“实现者不再需要猜”。本轮不再按功能名堆题，而是把 yaca 当成一个会在旧机器上长期运行、会联网、会执行任意 shell、会修改真实文件、会崩溃和迁移的产品，从每条缝反推仍未形成唯一结果的选择。

本轮得到三类结果：

1. **31 个新增或尚未原子化的缺口**：其中 21 个为现有 AQ/决策组没有直接完整询问的 `NEW`，10 个为已有宽泛 requirement 但缺少原子方案/失败结果的 `ATOMIC-GAP`；它们仍会改变产品行为、配置、状态机或安全说明。
2. **12 个已经覆盖、不要重复询问的主题**：并行形成的技术证明债务表或既有决策包已经有明确入口；这里只确认覆盖位置。
3. **14 处需要收口的跨文档张力**：不一定真冲突，但在负责人回复前不能同时把两边都写成现行承诺。

这不意味着负责人必须再逐条回答 31 道孤立题。建议把 `O`/`J` 项并入现有决策包的相邻组，把纯 `T` 项交给权威规格和技术证明。目标是减少实现时猜测，不是追求更大的题号。

## 审阅口径

每项都按六个问题检查：

1. 谁决定；
2. 输入事实是什么；
3. 何时成为 durable 事实；
4. 能否取消或修改；
5. 失败、竞态和崩溃后是什么真实状态；
6. 用户、测试和另一台机器怎样看见同一结果。

责任标记：

| 标记 | 含义 |
| --- | --- |
| `O` | 会改变可见产品承诺，项目负责人必须选择 |
| `T` | 不改变承诺时由技术规格和证据选择，不应让负责人猜 API |
| `J` | 负责人先定保证或体验，技术侧证明可兑现；失败时回到最小取舍 |

状态标记：

| 标记 | 含义 |
| --- | --- |
| `NEW` | 现有 AQ/决策组没有直接完整询问 |
| `ATOMIC-GAP` | 已有宽泛 requirement，但没有原子方案、失败结果或责任归属 |
| `EXISTING` | 已被现有问题、决策组或技术证明完整承接，不应重复问 |

## 全生命周期反查总表

这张表用于证明本轮确实检查了完整产品，而不是只围绕新发现的 31 项打转。某行“没有新增”表示现有决策包已经问到，不表示该行已经确认或通过 readiness gate。

| 反查面 | 本轮新增/原子缺口 | 已有主要承接 | 审计判断 |
| --- | --- | --- | --- |
| 下载、解压、安装、普通用户启动 | `FGA-001`、`FGA-028`、`FGA-031` | `RF-01` 至 `RF-06`、`TP-001`、`TP-030` | 旅程已覆盖；补 CPU、文件系统与真实性 |
| 启动、缺失/损坏配置、首次可用 | `FGA-003` | `PJ-01` 至 `PJ-03`、`M05-08` 至 `M05-10` | 仍需解决 bootstrap 张力和运行中 reload |
| 正常退出、窗口关闭、崩溃、恢复 | `FGA-002`、`FGA-010`、`FGA-012` | `PJ-10`、`AQ-229`、`AQ-230`、`CX-04/CX-05` | 已有 close/recovery；补休眠、手动 retry、draft |
| 升级、降级、迁移、卸载 | `FGA-023`、`FGA-028` | `RF-03`、`UPDATE-01/02`、`AR-P0-16` | 迁移主线已有；补 Key 旧副本和签名治理 |
| Prompt、人格、指令、回复风格 | `FGA-027` | `PP-01` 至 `PP-10`、`AQ-001` 至 `AQ-008`、`AQ-292` 至 `AQ-298` | 人格/权威/语言已问得较深；新增仅是自动命名 request 漏口 |
| 页面风格、输入和微交互 | `FGA-011` 至 `FGA-016`、`FGA-026`、`FGA-030` | `TU-01` 至 `TU-12`、`AQ-331` 至 `AQ-360` | 主视觉已有；inbox/details/管理动作/并发块仍会迫使实现者猜 |
| AgentLoop、终止、queue/side/steer | `FGA-002`、`FGA-007`、`FGA-009`、`FGA-010`、`FGA-014` | `AL06-01` 至 `AL06-12` | 状态机骨架强；等待用户后的新 turn 与 purpose 账本仍缺 |
| Tool Calling、进程、取消、预算 | `FGA-004`、`FGA-017` 至 `FGA-020` | `TS-01` 至 `TS-12`、`TP-005`、`TP-014` | raw shell 风险已诚实；补 stdin/ambient config/精确工具语义 |
| 权限、审批、安全、秘密 | `FGA-011`、`FGA-021` 至 `FGA-024`、`FGA-029` | `SAFE-*`、`THREAT-*`、数据分类候选 | deterministic permission 已覆盖；补管理动作、redaction、classifier、at-rest promise |
| Model、配置、网络、self-test | `FGA-003`、`FGA-005` 至 `FGA-008`、`FGA-023`、`FGA-024` | `M05-01` 至 `M05-12`、`CV-001` 至 `CV-055` | 字段面较完整；HTTP、rate、eligibility、预算口径仍缺 |
| Context、索引、导入导出、删除 | `FGA-012`、`FGA-015`、`FGA-022`、`FGA-027`、`FGA-031` | `CX-01` 至 `CX-12`、D-022 至 D-025 | path/resolver 很深；补选择性隐私、history projection、filesystem support |
| 压缩、窗口、Model 切换 | `FGA-025` | `AL06-10` 至 `AL06-12`、`CX-12` | 总体/多代压缩已覆盖；单个不可拆原子组超窗仍无答案 |
| 文件、shell、Git/非 Git | `FGA-004`、`FGA-017` 至 `FGA-021`、`FGA-031` | `TS-01` 至 `TS-10`、`CHANGE-*`、`TP-027` | 改动归属已有；补真实 shell 输入和“只读 Git”执行风险 |
| 错误、诊断、支持、自检 | `FGA-010`、`FGA-015`、`FGA-026` | `ED-01` 至 `ED-10`、`M05-10` 至 `M05-12` | typed error 路线已有；补手动动作的精确含义和 details 恢复 |
| 性能、故障注入、测试、供应链 | `FGA-001`、`FGA-006`、`FGA-028`、`FGA-031` | `RF-07` 至 `RF-11`、`TP-001` 至 `TP-030` | 证明框架已有；补 ISA、rate、filesystem、signature 的 release evidence |
| 明确非目标和未来扩展 | 无新增 | 21 号扩展边界、`PROD-11`、D-025 | Web/MCP/plugin/sub-agent/branch 不应因“完整 v0.1”重新混入 |

## A. 新增或尚未原子化的缺口

### FGA-001 Win32 x86 到底要求哪条 CPU 指令集基线

- **状态**：`NEW`。
- **场景**：同样是 PE32 x86，编译器、Lua、Expat、curl 或压缩工具仍可能默认生成 SSE2、较新原子指令或特定 i686 指令。它可以在 Windows XP 上运行，却不能在一台同样运行 XP 的老 CPU 上运行。
- **为什么重要**：`Win32 x86` 只说明位数，不说明最低 CPU。若不冻结，构建机 flags 和第三方二进制会暗中决定真实兼容范围。
- **方案 A**：正式基线为 i686 且不强制 SSE2；依赖必须按此重建。
- **方案 B**：正式基线为 i686 + SSE2；仍支持 XP OS，但明确不承诺更老 CPU。
- **方案 C**：不声明，由当前工具链决定。
- **推荐**：B。它比 C 诚实，依赖可获得性也通常优于无 SSE2；若负责人真正要覆盖前 SSE2 机器，则明确选 A 并把依赖重建成本列为发布硬门。
- **责任**：`J`。
- **影响**：`REL-04`、`SUPPLY-04`、`AQ-206`、`RF-04`、`TP-001`、`TP-002`，以及 16/20 号子系统。

### FGA-002 系统休眠、恢复和长时间离机后的活动 turn

- **状态**：`NEW`；`AQ-270` 只区分 wall/monotonic clock，`AQ-315` 只说明不能用时间猜异常关闭，没有定义活动 I/O 的恢复行为。
- **场景**：模型正在流式返回或 shell 正在运行时机器休眠；数小时后恢复。连接、进程、文件 lease、代理和工作区都可能已经变化。
- **为什么重要**：若只继续旧 timer，可能永久等待；若盲目重发，可能重复计费或副作用；若把休眠时间全算 active time，又会和“人工审批离机不计 active time”混淆。
- **方案 A**：检测恢复/显著时钟间隙；所有在途网络和无法证明仍连续的操作收口为 cancelled/unknown，重新验证 workspace、lease、配置和目标后等待用户。
- **方案 B**：冻结所有 deadline，恢复后从原状态无条件继续。
- **方案 C**：把休眠视为进程崩溃并立即退出，不尝试页面恢复。
- **推荐**：A；等待人工审批可继续保持 waiting-user，但动作新鲜度必须重验。模型/工具 I/O 不自动重放。
- **责任**：`J`。
- **影响**：`RUNTIME-01`、`PLAT-06`、`LOOP-07`、`LOOP-24`、`CONC-03`、`NET-09`、`PROC-03`、22 号运行时和 20 号故障测试。

### FGA-003 运行中手工修改 `config.ini` 是否自动生效

- **状态**：`ATOMIC-GAP`；`CFG-11` 和 `LOOP-15` 提到热更新/turn 冻结，但没有决定谁触发 reload、无效新文件怎样影响已运行会话。
- **场景**：用户在另一个编辑器里改 Key、Endpoint、Permission 或预算；文件保存时短暂无效，或改完后当前 yaca 仍在等待审批。
- **为什么重要**：自动 reload 会让行为在 turn 边界外漂移；永不 reload 又会让 config-repl 保存后看似无效。Key/Endpoint 改变还涉及隐私目的地变化。
- **方案 A**：外部修改永不自动加载；显式 reload 或重启后全量验证。yaca 自己的 config/model REPL 保存可在返回 chat 时明确提出“next turn 使用新版本”。
- **方案 B**：只在 idle/turn 边界检测 digest 变化，显示脱敏 diff，用户确认后加载；无效文件保持旧内存版本但阻止新 turn。
- **方案 C**：文件一变化就热应用可解析字段。
- **推荐**：A，最简单且最确定；若以后实测觉得重启太重，再增加 B。绝不采用 C。
- **责任**：`O` 决定体验，`T` 定义版本/digest 和失败结果。
- **影响**：`CFG-10`、`CFG-11`、`CFG-19`、`LOOP-15`、`AQ-290`、`CONFIG-SCHEMA-CANDIDATE.md` 和 command × state 表。

### FGA-004 内部 curl/cmd/sh/Git 是否读取宿主的隐式配置

- **状态**：`NEW`。
- **场景**：用户目录或工作区放有 `.curlrc`、Git config、pager/external diff；Windows `Command Processor\AutoRun` 或环境变量让 shell 启动时执行额外命令。yaca 以为自己只执行固定内部动作，宿主配置却改变了 endpoint、header、输出或副作用。
- **为什么重要**：这会绕过配置 schema、secret 传递、只读 Git 展示和依赖搜索边界。仅仅固定 executable 的绝对路径还不够。
- **方案 A**：内部基础设施进程使用最小 allowlisted 环境并显式禁用用户配置、pager、交互启动脚本和 shell AutoRun；模型主动调用的 raw shell 仍按已确认的宽 `Shell` 环境规则运行。
- **方案 B**：内部进程与 raw shell 都继承全部宿主配置。
- **方案 C**：内部和 raw shell 都使用完全空环境。
- **推荐**：A。它区分“yaca 的可信基础设施”与“用户授权的原始 shell”，既安全又不虚假限制 raw shell。
- **责任**：`T`；若某平台无法禁用且会改变产品保证，再转 `J`。
- **影响**：`PROC-06`、`PROC-08`、`THREAT-03`、`NET-03`、`NET-04`、`TOOL-12`、`TP-006`、`TP-029`。

### FGA-005 HTTP 明文 Model Endpoint 的边界

- **状态**：`NEW`；当前配置候选允许绝对 HTTP/HTTPS URL，但没有决定 HTTP 是否能携带 Key 或对话。
- **场景**：本机 Ollama 常用 `http://127.0.0.1`；局域网兼容端点也可能是 HTTP；公网 HTTP 会暴露 Key、Prompt 和代码。
- **为什么重要**：这不是普通 TLS 错误，而是用户主动配置的长期隐私边界。一个 warning 不能替代禁止把明文 Key 发到公网。
- **方案 A**：只允许 HTTPS；唯一例外是 loopback + `AuthMode=none`。
- **方案 B**：HTTP 只允许 `AuthMode=none` 且 Key/secret header 为空；loopback 直接允许，非 loopback 需显著确认并由 self-test 持续警告。
- **方案 C**：任意 HTTP，包括明文 Key，均按配置发送。
- **推荐**：B；它保留本地/LAN 开源模型，同时硬禁止通过 HTTP 发送 yaca 知道的结构化秘密。
- **责任**：`O`。
- **影响**：`NET-02`、`NET-10`、`CFG-04`、`AQ-137`、`AQ-146`、`M05-01`、`CV-012/CV-013` 和数据分类矩阵。

### FGA-006 每个 Model 的并发、速率和冷却

- **状态**：`NEW`。
- **场景**：main 与 side 同时请求；紧接着又发生 action review、termination review 或 compaction。某些本地/套餐端点只允许一个并发请求，另一些会按 RPM/TPM 限流。
- **为什么重要**：仅有 retry 不能决定请求是否应先排队；盲目并发会增加 429、费用和 side 饥饿，盲目串行又违反“旁问直接回复”。
- **方案 A**：不增加本地调度字段；最多 main+side 两个并发，429 后只按 `Retry-After` 退避。
- **方案 B**：每个 Model 至少配置/派生 `MaxConcurrentRequests` 与 `MinRequestIntervalMs`；所有 purpose 共用一个调度器和 `Retry-After` 冷却，RPM/TPM 高级字段暂缓。
- **方案 C**：为每个 request purpose 单独限流，互不知晓。
- **推荐**：B。两个简单限制足以表达单并发本地模型和常见套餐，不需要首版实现完整 token bucket 配置面。
- **责任**：`O` 确认 side 的等待体验，`T` 设计调度账本。
- **影响**：`Model.*` schema、`AL06-06`、`LOOP-23`、`CONC-04`、`NET-06`、`AQ-359`。

### FGA-007 side/review/compaction 的预算字段与总账不一致

- **状态**：`ATOMIC-GAP`。
- **场景**：配置候选只有一个 `MaxModelRequests`、`MaxTurnTokens`、`MaxDoubleCheckRounds`；AgentLoop 包却建议 side 不消耗 main turn request count，action-review 与 termination-review 又各有局部 round cap。
- **为什么重要**：同一字段可被解释成三种不同上限。恢复、`.status` 和费用报告将无法机械复算。
- **方案 A**：所有 main/side/review/compaction 请求都计入一个 turn 总上限，不设局部目的上限。
- **方案 B**：保留 Context/进程 aggregate hard ledger，再为 side、action-review、termination-review、compaction 设置少量局部 cap；局部只能更早停止，不能突破总账。
- **方案 C**：每种 purpose 独立预算，没有 aggregate hard cap。
- **推荐**：B；用户配置只暴露真正需要调整的少量局部值，其余可由 Runtime 常量派生，但 XML 必须保存当时实际 cap 和计数口径。
- **责任**：`J`。
- **影响**：`AQ-028`、`AQ-097`、`AQ-153`、`AQ-196`、`AQ-359`、`AL06-06` 至 `AL06-09`、`SCA-D11`、`CONFIG-SCHEMA-CANDIDATE.md`。

### FGA-008 `Tools=off` 的 Model 能否成为主 Coding Agent

- **状态**：`NEW`；`AQ-144` 只决定能力字段，`M05-03` 明确留下“能否成为主 Agent”未决。
- **场景**：模型可以普通聊天，但不能调用 native tools，也不能可靠调用 `finish/ask-user/refuse` control functions。
- **为什么重要**：若允许，它不是同一套 AgentLoop 的小降级，而是另一种完成协议和功能承诺；若不允许，model-repl/self-test 必须在选择前说明可用 purpose。
- **方案 A**：`Tools=off` 不能用于 main；只可用于被证明不需要 tools/control 的 side 或其他明确 purpose。
- **方案 B**：允许作为“聊天/只读建议”主模式，并为它另建无工具 typed outcome 协议和显著降级页面。
- **方案 C**：用自然语言解析模拟工具与完成。
- **推荐**：A。yaca 首版保持一个 AgentLoop，不暗中增加第二套文本 Agent。
- **责任**：`O`。
- **影响**：`MODEL-03`、`MODEL-05`、`MODEL-06`、`AQ-144`、`M05-03`、`AL06-02`、model-repl 列表和 self-test capability 结果。

### FGA-009 `ask-user` 后的回复属于旧 turn 还是新 turn

- **状态**：`NEW`。
- **场景**：主模型发出 typed `ask-user`，Context 进入 waiting-user。用户回答后，预算、Model/Permission/Prompt 快照和 queue gate 应怎样计算？
- **为什么重要**：若仍属旧 turn，可能跨数小时持有旧配置和已耗尽预算；若是新 turn，又必须保存它与原问题的因果关系。
- **方案 A**：用户回复恢复同一个 turn-id 和旧冻结快照。
- **方案 B**：`ask-user` 结束当前 turn 为 waiting-user；回复建立新 turn，并以 `reply-to`/pending-question ref 关联，重新冻结配置和预算。
- **方案 C**：普通无工具文本自动拼入旧请求，不形成 durable 用户输入。
- **推荐**：B；任务语义连续，但账本、配置和用户输入边界清楚。
- **责任**：`O`。
- **影响**：`LOOP-01`、`LOOP-10`、`LOOP-15`、`AQ-251`、`AL06-02`、`AL06-04`、Context event/ID schema。

### FGA-010 用户主动“重试”到底重试什么

- **状态**：`NEW`；现有问题详细定义自动 transport attempt，却没有定义错误页上的手动 retry。
- **场景**：模型 timeout、tool failed、shell outcome unknown 或存储恢复后，用户看到 `retry`。复用旧 request、建立新 request，还是重放 tool？
- **为什么重要**：一个泛化“重试”按钮很容易重复收费、重复生成或重复副作用。
- **方案 A**：手动 retry 可以原样重放任意上一步。
- **方案 B**：只有 Runtime 能在“确认请求体未发送/无规范事件”等安全阶段建立同一 logical request 的新 attempt；用户重试始终建立有因果链接的新模型 turn/request，绝不自动重放 accepted/unknown operation。
- **方案 C**：不提供任何手动 retry，只让用户重新输入。
- **推荐**：B；UI 必须写清 `retry request`、`send again` 或 `inspect unknown`，不显示含糊的 `retry`。
- **责任**：`O` 决定可见操作，`T` 执行幂等规则。
- **影响**：`NET-07`、`LOOP-14`、`TOOL-15`、`AQ-221`、`AQ-316`、错误卡和 recovery 页。

### FGA-011 审批页能否直接修改命令或工具参数

- **状态**：`NEW`。
- **场景**：模型提议 `rm -rf build cache`，用户只想删 `build`。若在审批框直接改参数，旧 Permission、DoubleCheck verdict、digest 和 operation snapshot 是否还有效？
- **为什么重要**：审批绑定精确参数；“小改后沿用旧批准”会破坏最重要的安全不变量。
- **方案 A**：审批只允许 allow/deny/details；要改参数就 deny，再 steer 让模型提出新调用。
- **方案 B**：允许编辑，但编辑产生新的 user-authored action，重新走 schema、Permission、DoubleCheck、审批和 durable operation。
- **方案 C**：就地修改并沿用旧 verdict/approval。
- **推荐**：A，符合简单产品；未来若实际需求强再增加 B。C 永远禁止。
- **责任**：`O`。
- **影响**：`SAFE-03`、`SAFE-12`、`AQ-225`、`AQ-279`、`AL06-07`、`TU-07` 和 approval snapshot schema。

### FGA-012 未提交输入 draft 是否属于“完整 Context”

- **状态**：`NEW`。
- **场景**：用户写了多行问题尚未按发送，程序崩溃或窗口关闭。恢复后是否应找回草稿？
- **为什么重要**：持续保存 draft 会把敏感未提交文本写入 XML，并增加单 XML 重写；不保存则必须让“完整对话”明确只从提交动作开始。
- **方案 A**：只有已提交 queue/steer/side/main 输入 durable；未提交 draft 只在进程内，崩溃可丢失，界面明确 `not saved`。
- **方案 B**：idle debounce 后把 draft 作为可删除的 XML session state 保存。
- **方案 C**：另建 draft 文件。
- **推荐**：A；它最符合长期只有 INI/XML和单 XML 性能边界，也不扩大“用户尚未发送”的隐私承诺。
- **责任**：`O`。
- **影响**：`CTX-01`、`CTX-23`、`TUI-22`、`TUI-23`、`AQ-264`、`AQ-351`、`AQ-353`。

### FGA-013 已提交 queue 的查看、删除、编辑和重排

- **状态**：`ATOMIC-GAP`；AgentLoop 文本说编辑/删除/重排必须显式并产生日志，但决策组没有决定首版究竟提供哪些动作。
- **场景**：用户连续 Enter 排了三条消息，随后发现第二条错误或已经过时。
- **为什么重要**：没有管理入口会让错误任务自动运行；原地编辑又会破坏已经 durable 的输入事实。
- **方案 A**：首版提供 list + drop；修改通过 drop 后重新提交，FIFO 不支持重排。
- **方案 B**：提供 list/edit/drop/reorder；所有变化追加 supersede/reorder 事实，不改旧输入。
- **方案 C**：queue 完全不可见、不可取消。
- **推荐**：A，能力足够且命令/状态最少。
- **责任**：`O`。
- **影响**：`LOOP-06`、`AL06-04`、`AQ-032`、`AQ-086`、command registry、XML queue event schema。

### FGA-014 queue 达到硬上限时保留哪一边

- **状态**：`NEW`；全局资源上限存在，但输入溢出的用户结果未定义。
- **场景**：旧机内存紧张或用户粘贴/连发，pending queue 达到条数/字节上限。
- **为什么重要**：静默丢最旧会执行与用户认知不同的任务；静默丢最新又会让已按 Enter 的输入消失。
- **方案 A**：拒绝新增项，保留 editor draft 和现有 FIFO，显示实际/上限；用户可 drop 后重试。
- **方案 B**：自动删除最旧项。
- **方案 C**：无限增长。
- **推荐**：A。
- **责任**：`O` 确认体验，`T` 冻结上限。
- **影响**：`CONC-02`、`CONC-04`、`PERF-01`、`LOOP-06`、TUI queue feedback 和 `SCA-D11`。

### FGA-015 `.history` 与 `.details` 是临时 UI 还是可恢复契约

- **状态**：`NEW`；TUI 包把两个命令写进候选 registry，却没有定义数据源、可寻址期限和截断边界。
- **场景**：用户恢复昨日 Context 后输入 `.details tool:21`；或者工具原始输出已经按 canonical limit 截断。
- **为什么重要**：如果只依赖内存卡片，恢复后命令会失效；如果承诺“完整 details”，又与有界工具结果矛盾。
- **方案 A**：两者只查看当前进程缓存，退出后不保证。
- **方案 B**：从 canonical XML 与稳定局部 event ID 派生；`.history` 查看 transcript，不是另一个永久输入历史；`.details` 只展示 XML 实际保存的完整/截断事实，绝不声称可恢复被丢弃字节。
- **方案 C**：新增独立 history/detail 文件。
- **推荐**：B。
- **责任**：`O` 确认用户承诺，`T` 定义投影。
- **影响**：`TU-06`、`TUI-09`、`CTX-01`、`CTX-06`、`AQ-125`、`AQ-165`、command registry。

### FGA-016 main/side/tool/status 同时输出时的 transcript 顺序

- **状态**：`NEW`；事件泵有顺序概念，但没有可见块的交错规则。
- **场景**：main 正在 streaming，side 回复完成，同时 shell 输出和 cancel 状态到达。
- **为什么重要**：按字节交错会把两段文本混成一句；长期 buffer 又会让 cancel/approval 看不见。
- **方案 A**：按到达的规范 UI event 顺序追加，使用 lane/event 标签；每个可见块原子，绝不字节级交错。必要控制卡可在块边界抢占，已打印内容不重排。
- **方案 B**：main 完成前隐藏全部 side/tool/status。
- **方案 C**：所有 producer 直接写 stdout。
- **推荐**：A。
- **责任**：`O` 选择体验，`T` 证明调度。
- **影响**：`ARCH-04`、`LOOP-11`、`TUI-03`、`TUI-08`、`CONC-02`、`TP-022`、`TP-023`。

### FGA-017 模型 raw shell 的 stdin 来源

- **状态**：`NEW`；Runtime internal process port 写了 `stdin source`，但模型可见 `exec` 没有选择。
- **场景**：命令意外提示 `Are you sure?`、测试 runner 等待输入，或恶意子进程读取 yaca TUI 的用户按键。
- **为什么重要**：若继承终端，子进程可以偷走 queue/approval 输入并永久卡住；若提供交互桥，又等于加入 PTY/交互程序系统。
- **方案 A**：模型 `exec` 的 stdin 固定关闭/EOF；首版只支持非交互前台命令。基础设施进程必须显式声明自己的受控 stdin source。
- **方案 B**：默认继承 yaca 的 stdin。
- **方案 C**：提供交互式 PTY/console 透传。
- **推荐**：A。
- **责任**：`O` 确认非交互边界，`T` 实现。
- **影响**：`PROC-02`、`PROC-04`、`PROC-05`、`AQ-128`、`TS-09`、`AR-P1-03`。

### FGA-018 direct `list` 的递归、链接、ignore 和排序语义

- **状态**：`ATOMIC-GAP`；`AQ-113` 问递归边界，`TOOL-11` 提到 ignore，但没有一套完整 schema。
- **场景**：模型列出大 monorepo、隐藏目录、submodule、symlink 环或 `.gitignore` 排除的生成目录。
- **为什么重要**：默认无限递归会耗尽 XP 内存；自动遵守 ignore 会隐藏用户明确要求的文件；跟随链接可能越界。
- **方案 A**：默认只列一层；递归必须给 depth/entry limit；默认不跟随目录链接；hidden/ignored 是显式参数；显式路径可覆盖 ignore 但仍走 Permission；每页稳定排序并标 incomplete。
- **方案 B**：默认递归并自动遵守 `.gitignore`，后端自行决定顺序。
- **方案 C**：不提供 direct list，只用 shell。
- **推荐**：A。
- **责任**：`O` 确认模型可见语义，`T` 冻结 schema/复杂度。
- **影响**：`TOOL-01`、`TOOL-10`、`TOOL-11`、`AQ-113`、`PERF-03`、`TS-02`、`TS-07`。

### FGA-019 direct `search` 的匹配语言

- **状态**：`ATOMIC-GAP`；`AQ-114` 主要问实现后端，没有定义用户/模型可依赖的匹配结果。
- **场景**：同一个 pattern 在 bundled rg、BusyBox grep、Windows findstr 和 Lua pattern 下含义不同；大小写、二进制、无效 UTF-8和 ignore 又改变结果。
- **为什么重要**：模型会依据“没有匹配”做修改；后端偶然差异不能改变事实判断。
- **方案 A**：工具 schema 固定 literal 默认和一个受限、版本化 regex dialect；case/hidden/ignored/binary/encoding 都是显式参数，超限返回 incomplete 而非零匹配。
- **方案 B**：把 pattern 原样交给当前平台可用搜索程序。
- **方案 C**：只暴露 raw shell search。
- **推荐**：A；后端可以更换，但必须通过同一 corpus。
- **责任**：`O` 审阅模型工具体验，`T` 定义 dialect。
- **影响**：`TOOL-01`、`TOOL-10`、`TOOL-11`、`AQ-114`、`AQ-184`、`TP-014`。

### FGA-020 stdout/stderr 的跨管道顺序怎样诚实表达

- **状态**：`ATOMIC-GAP`；`PROC-04` 要求定义顺序，尚无方案。
- **场景**：一个进程交替写 stdout/stderr；两个独立 pipe 的读取完成顺序并不等于进程原始写入顺序。
- **为什么重要**：测试失败原因、编译错误和安全诊断可能依赖顺序；伪造精确合并会误导模型。
- **方案 A**：分别保存两个 stream，并为 Runtime 观察到的 chunk 分配 arrival seq；可生成观察顺序视图，但明确不保证跨 pipe 的原始字节全序。
- **方案 B**：在 shell 层强制 `2>&1`，只保留一条流。
- **方案 C**：按 wall-clock timestamp 事后推断精确顺序。
- **推荐**：A；用户明确要求合并时可由 raw command 自己重定向。
- **责任**：`T`。
- **影响**：`PROC-04`、`PROC-07`、`AQ-122`、`TOOL-06`、XML tool result schema、TUI details。

### FGA-021 “只读 Git status/diff”会不会偷偷执行外部程序

- **状态**：`NEW`。
- **场景**：系统 Git 或仓库 config 可启用 pager、external diff、textconv、filter、alias 或其他 helper；所谓只读展示可能启动工作区/用户指定程序。Git 版本、safe-directory 和 submodule/worktree 行为也不同。
- **为什么重要**：若它在 `Read=allow` 下自动运行，就绕过了 `Shell=confirm`。如果 yaca 不随包 Git，系统 Git 也不属于 release allowlist。
- **方案 A**：随包并审计固定 Git，使用硬化环境和禁用外部 helper 的参数，正式提供只读 adapter。
- **方案 B**：v0.1 不自动调用系统 Git；Git 命令只经 raw shell/Execute。yaca 的 direct file evidence 和 unified diff 仍可工作，Git 不可用不影响非 Git 闭环。
- **方案 C**：自动调用 PATH 中的 Git，并把 status/diff 当纯 Read。
- **推荐**：B，最符合“简单”和当前最小供应链；若负责人要求自动 Git 状态，再升级到 A，不能采用 C。
- **责任**：`O`。
- **影响**：`PROD-06`、`TOOL-12`、`AQ-129`、`AQ-249`、`TS-02`、`TP-027`、`SUPPLY-01`。

### FGA-022 Context 内误贴秘密后的选择性擦除

- **状态**：`NEW`。
- **场景**：用户把 API token 粘进普通消息或 shell 命令；按“完整历史”它进入 XML、previous-valid/backup/temp 和可能的导出。之后用户希望只删除这段秘密而保留工作。
- **为什么重要**：自动 detector 不能保证发现，XML digest/事实历史又不适合静默改写；普通 delete 也不能承诺 SSD/FAT/备份上的物理安全擦除。
- **方案 A**：v0.1 不支持 in-place message redaction；只提供整 Context purge 与明确的 sanitized export，文档说明已发送给 provider 的内容无法收回。
- **方案 B**：提供版本化 redaction rewrite：追加审计事件并从新 generation 删除选定正文；清理所有 yaca 知道的旧副本，但只承诺 best-effort，不宣称物理 secure erase。
- **方案 C**：直接编辑 XML 文本且不留记录。
- **推荐**：A 作为首版简单诚实保证；如果“保留任务但删除秘密”是硬需求，再正式选择 B 并扩展 migration/digest/backup 协议。
- **责任**：`O`。
- **影响**：`PROD-08`、`SAFE-09`、`CTX-01`、`CTX-06`、`CTX-11`、`CTX-16`、`AQ-238`、`AQ-349`、data classification。

### FGA-023 配置备份会复制多少份明文 Key

- **状态**：`ATOMIC-GAP`；配置事务要求 backup/rollback，明文 Key 决定已确认，但备份数量、清除和权限没有产品选择。
- **场景**：用户替换或清除 Key，`config.previous.ini`、升级备份或失败 temp 仍保留旧 Key。
- **为什么重要**：UI 显示“Key cleared”若只清当前文件，会制造错误安全感；无限备份也违反简单数据面。
- **方案 A**：只保留一个受保护的 previous-valid INI；Key clear/credential rotation 时明确询问是否同时清理已知旧备份，清理只承诺 best-effort unlink。
- **方案 B**：永不保留配置备份，只依赖原子替换前旧文件仍在。
- **方案 C**：按时间无限保留备份。
- **推荐**：A；它在迁移恢复和秘密副本之间取得最小平衡。
- **责任**：`O`。
- **影响**：`CFG-04`、`CFG-07`、`CFG-10`、`CFG-15`、`THREAT-04`、`AQ-132`、`FMT-06`、`UPDATE-02`。

### FGA-024 `SensitiveRead` 怎样识别敏感路径

- **状态**：`NEW`；配置候选有 `SensitiveRead` 三态，数据分类只说启发式不能保证，但没有 classifier 的输入、版本和用户解释。
- **场景**：direct read 打开 `.env`、SSH private key、云凭据、普通源码内 token 或一个名称无害的二进制文件。
- **为什么重要**：没有 classifier，字段没有消费者；若 classifier 未命中却显示“safe”，会夸大保证。
- **方案 A**：v0.1 删除 `SensitiveRead`；所有 direct read 只按 Read/OutsideWorkspace，用户依赖显式 Permission。
- **方案 B**：保留版本化内置路径/内容启发式，只能把 Read 提升为 confirm/deny，永远不能降低限制；审批显示命中规则并承认未命中不代表安全。
- **方案 C**：宣称能自动识别所有秘密并据此允许读取。
- **推荐**：B；若不愿维护规则 corpus，就诚实选 A，不能保留一个无定义字段。
- **责任**：`O` 决定配置面，`T` 建 classifier/corpus。
- **影响**：`SAFE-01`、`SAFE-05`、`SAFE-09`、`CFG-13`、`AQ-149`、`TS-04`、`CONFIG-SCHEMA-CANDIDATE.md`。

### FGA-025 单个不可拆原子组已经大于 Model 窗口

- **状态**：`NEW`；压缩设计规定原子组不能拆，但只讨论摘要/最近窗口总体超限。
- **场景**：一条用户输入、一个工具 call/result 组或导入的历史原子组本身就超过当前 Model 可用输入，即使删掉其余历史也放不下。
- **为什么重要**：继续压缩无效；静默拆分会破坏 tool 配对和用户原意；截断后却称“完整输入”会误导模型。
- **方案 A**：新输入在建立 active turn 前预检并保留 draft；过大则拒绝提交给该 Model，提示缩短/选择更大 Model。恢复/导入中的过大旧组保留事实，但不进入 view，要求显式更换 Model 或创建有证据的派生摘要。
- **方案 B**：按字节任意切开原子组。
- **方案 C**：静默截断头尾。
- **推荐**：A。
- **责任**：`O` 确认体验，`T` 定义 preflight/error。
- **影响**：`COMP-03`、`COMP-06`、`AQ-062`、`AQ-310`、`AQ-352`、`AL06-11`、`TP-025`。

### FGA-026 配置/模型/Context 管理动作是否共用安全确认协议

- **状态**：`NEW`；Agent tool approval 已很细，但 `reset config`、删除 Model、purge Context、import/migrate 等管理动作仍可能各写一个随意 yes/no。
- **场景**：用户在 config-repl 清空配置、在 model-repl 删除仍被 Context 引用的 Model、在 context-repl 永久清除文件。
- **为什么重要**：这些动作不来自模型，不能硬塞进 Tool Permission；但它们同样需要精确目标、影响预览、默认取消、no-replace 和 crash recovery。
- **方案 A**：每个 REPL 自己设计确认词和保存方式。
- **方案 B**：定义一个非 Agent 的 `ManagementMutation` 契约：plan/target/impact/stale credential/default cancel/commit/result；三个 REPL 和 CLI 只投影它。
- **方案 C**：复用历史 Agent approval，或单字母 `y` 全批通过。
- **推荐**：B。
- **责任**：`O` 确认默认和文案，`T` 定义事务。
- **影响**：`CFG-10`、`CFG-15`、`CTX-11`、`INDEX-15`、`AQ-080`、`AQ-178`、`TU-07`、`TU-09`、`TU-10`。

### FGA-027 Context 自动命名是否要增加第七种 Model request purpose

- **状态**：`NEW`。
- **场景**：`AutoNameOnExit` 和 `.archive rename` 需要名字；`AQ-216` 提到模型建议，但当前正式候选只有 main/side/action-review/termination-review/compaction/self-test 六类 request purpose。
- **为什么重要**：额外 naming 请求会产生费用、发送历史和增加恢复事件；偷偷复用 compaction/side purpose 会污染权限与统计。
- **方案 A**：首版只用 deterministic provisional name + 用户手工 rename，不调用 Model。
- **方案 B**：主模型的 typed finish 可附带可选 title suggestion；用户确认后 rename，不增加请求。
- **方案 C**：新增独立 naming request purpose，另定最小 view、预算和失败策略。
- **推荐**：B；主模型已经知道任务，额外字段不产生新 endpoint/费用，用户仍掌握最终名称。模型不提供时退回 A。
- **责任**：`O`。
- **影响**：`CTX-11`、`INDEX-01`、`AQ-216`、`AQ-259`、`CONFIG-SCHEMA-CANDIDATE.md` 的 `AutoNameOnExit`、`PP-05`、`AL06-02`。

### FGA-028 发布物的真实性：hash 之外是否签名

- **状态**：`NEW`；`RF-06` 询问 SHA-256/SBOM/可复现清单，`REL-10` 提到签名但没有负责人选择或 XP 兼容策略。
- **场景**：攻击者能同时替换 zip 和同一下载页上的 hash；Windows XP 对现代 Authenticode 算法支持有限，Linux zip 又没有系统级签名体验。
- **为什么重要**：hash 证明下载字节一致，不证明是谁发布；签名则引入私钥治理、证书费用、旧系统验证和发布权限。
- **方案 A**：v0.1 只发布 SHA-256、SBOM 和 provenance，不承诺签名。
- **方案 B**：每个平台 zip 都有同一项目离线私钥的 detached signature；Windows 另评估 Authenticode，但不以弱 SHA-1 签名伪装现代安全。
- **方案 C**：只给 Windows Authenticode，Linux 无真实性工件。
- **推荐**：B 作为公开 release 目标；若目前没有可治理的发布私钥，就明确选择 A 并记录限制，不能把 hash 写成签名。
- **责任**：`O` 决定是否承担密钥治理，`T` 设计格式/验证说明。
- **影响**：`REL-10`、`REL-12`、`SUPPLY-03`、`RF-06`、release manifest 和文档。

### FGA-029 本地静态数据到底防谁

- **状态**：`ATOMIC-GAP`；明文 Key 已确认，`THREAT-01` 仍未把“其他 OS 用户、同用户进程、管理员、磁盘离线读取”分层成产品承诺。
- **场景**：便携目录放在共享盘；另一个本机用户读取 config/context；同一用户下恶意进程读取内存或文件。
- **为什么重要**：masking、ACL 与加密是三种不同保证。明文 Key 不等于可以完全不检查文件权限，也不等于能防同用户进程。
- **方案 A**：尽力设置当前 OS 用户可读写并在无法兑现时 self-test 警告；明确不防管理员、同用户恶意进程、离线磁盘、swap/crash dump。
- **方案 B**：为 INI/XML 引入应用层加密和解锁流程。
- **方案 C**：不检查权限，也不说明风险。
- **推荐**：A，符合简单/旧平台/明文 Key 决定。
- **责任**：`O` 确认安全承诺，`T` 实现能力诊断。
- **影响**：`CFG-04`、`THREAT-01`、`THREAT-04`、`PLAT-04`、`REL-02`、`AQ-040`、self-test Stage 1。

### FGA-030 终端尺寸变化后的重排规则

- **状态**：`ATOMIC-GAP`；`TP-023` 已要求 resize fixture，但 TUI 还没有选择视觉结果。
- **场景**：用户把 80 列窗口缩到 40 列，再放大；此前 transcript、正在编辑的 draft、审批卡和 diff 已经打印。
- **为什么重要**：全屏重绘在 XP/SSH 上容易闪烁或复制重复内容；不处理又可能让新审批超出宽度。
- **方案 A**：已经打印的 transcript 永不回流/重画；从 resize 事件后的新块和当前 draft 开始使用新宽度，窄屏改为逐字段多行。
- **方案 B**：清屏并重绘完整历史。
- **方案 C**：始终假定 80 列。
- **推荐**：A，最符合追加式 transcript。
- **责任**：`O` 确认体验，`T` 在 `TP-023` 证明。
- **影响**：`TUI-01`、`TUI-16`、`AQ-299`、`AQ-332`、`TU-01`、`TU-02`。

### FGA-031 支持哪些文件系统，Context 数据根和 workspace 是否同一承诺

- **状态**：`ATOMIC-GAP`；`PLAT-04`/`TP-011` 要测试 FAT/NTFS/ext4/跨卷，却没有产品支持矩阵。
- **场景**：Context 数据根在 FAT32/U 盘/SMB/NFS，workspace 在网络盘；lock、no-replace、directory flush、大小写和断线语义都不同。
- **为什么重要**：单 XML durability 需要比“能读写文件”更强的能力；但禁止网络 workspace 又可能过度限制普通 Coding 使用。
- **方案 A**：数据根和 workspace 都只允许经过完整证明的本地文件系统。
- **方案 B**：Context/配置数据根只允许经过 durability/lock 证明的本地文件系统；workspace 可以在其他可访问文件系统，但 direct write/rename 按能力失败关闭并显示保证降级。
- **方案 C**：所有文件系统都宣称同等原子、锁和掉电保证。
- **推荐**：B。
- **责任**：`J`。
- **影响**：`PLAT-02`、`PLAT-04`、`TOOL-02`、`CTX-21`、`CONC-03`、`REL-02`、`TP-011`、`TP-014`。

## B. 已有覆盖，不应再次包装成“新题”

| 主题 | 状态 | 已有承接 | 本轮结论 |
| --- | --- | --- | --- |
| raw shell 过长/编码无法传给平台 | `EXISTING` | `SCA-NQ01` | 并入进程/shell 规格；推荐首版 typed reject，不另起重复 AQ |
| active workspace 被删除/卸载/重命名 | `EXISTING` | `SCA-NQ02` | 扩展到在途 tool/cwd 收口，推荐 fail-stop + 显式 rebind |
| event pump 的控制优先级与饥饿 | `EXISTING` | `TP-022`、`CONC-02` | 属技术证明；只有失败导致取消体验降级才回负责人 |
| ANSI/OSC/C0、Bidi/零宽和 resize corpus | `EXISTING` | `TP-023`、`AQ-231` | 安全净化由技术规格硬保证；FGA-030 只补 resize 的可见布局选择 |
| CRLF/BOM/编码/属性与 direct file 保真 | `EXISTING` | `CHANGE-04`、`TP-014` | 不再问是否可以静默转换；默认必须保真或拒绝 |
| XML digest 不是来源认证 | `EXISTING` | `CX-07`、“外来 XML 是数据” | 历史 approval audit-only；不要新增“签名 XML 才安全”的伪前提 |
| 活动 XML 热复制是否最新 | `EXISTING` | `CX-02` | 只有 close/snapshot/export 的 generation 承诺可接盘 |
| 模块/DLL/内部工具搜索劫持 | `EXISTING` | `AQ-267`、`TP-029`、`AR-P0-14` | 内部依赖绝不从 CWD/PATH 回退；FGA-004 补宿主配置而非路径 |
| Windows 非管理员/zip 解压即运行 | `EXISTING` | `RF-01` 路线 A | 若选该路线，不再把管理员安装当隐藏前提 |
| stdout/stderr 是否分开 | `EXISTING` | `PROC-04`、`AQ-122` | FGA-020 只补跨 pipe 全序不能伪造 |
| Context 数量/单 XML/回收区 hard gate | `EXISTING` | `CX-11`、`AR-P1-06`、`TP-009` | 数字由旧机证据冻结，超限行为由已选 fail-stop 路线决定 |
| Git/非 Git 改动归属与不自动 commit/push | `EXISTING` | `AQ-249`、`TS-08`、`TP-027` | FGA-021 只补自动“只读 Git”本身可能执行外部程序 |

## C. 跨文档张力与危险默认

这些条目不是新方案题。负责人回复相邻决策包时，收口流程必须明确哪一边被确认、修订或排除。

### CR-FGA-01 配置损坏时“无法启动”与 bootstrap REPL/self-test

- 项目负责人原话强调：yaca 启动包括配置加载与检查，配置损坏则无法启动。
- `M05-10` 推荐 help/version、bootstrap model/config REPL 与 self-test Stage 1 仍可运行。
- 最小待确认差异：**“无法启动”是只禁止主 Agent，还是禁止可执行文件的所有管理入口**。不能一边说全部入口失败，一边承诺用 self-test 修配置。

### CR-FGA-02 README 的失效 Model fallback 与候选显式 mapping

- 公开 README 写恢复时失效 Model/Permission 自动回落第一项。
- `CV-049`、`CX-07`、`CX-12` 推荐先只读并要求显式映射，不能静默 fallback。
- 两者直接改变 endpoint、隐私与权限，必须由后来的正式决定取代旧 README，不可并存。

### CR-FGA-03 “zip 解压后安装脚本”与“zip 直接运行”

- README 把 `INSTALL.bat/install.sh` 写成安装前提。
- `RF-01` 推荐 portable zip 直接运行，安装脚本只是未来薄层。
- 这会改变数据根、PATH、升级与卸载；在 RF-01 确认前公开文档只能标目标/候选。

### CR-FGA-04 “相信模型的 raw tools”与 direct tools/expected digest

- 项目负责人要求像 Codex 一样把原始工具交给模型、保持简单。
- `TS-01/TS-02` 推荐少量 direct tools 加 raw shell，以 direct write/patch 提供新鲜度和 no-replace。
- 需要确认“原始”是指模型直接调用清晰工具 schema，还是只有一个 shell。两者不是实现细节：后者失去 direct file 冲突保证。

### CR-FGA-05 “完整对话/复制 XML 接盘”与 canonical truncation

- 用户期望 XML 达到另一台机器完整接盘水平。
- 文档把完整定义为有界 canonical result，允许 `truncated/reference/incomplete`，不保存无限原始字节和隐藏推理。
- 需要在 `CX-02/CX-03` 明确确认：完整是**完整语义事实和明确缺口**，不是无限原始输出。未确认前不能对外写“所有内容原样保存”。

### CR-FGA-06 “一个 XML 是活动事实源”与 WAL/temp/previous-valid

- 一个 XML 的逻辑事实源方向已确认。
- 正确提交至少需要 temp/lock；性能失败时可能需要 WAL；迁移还可能有 previous-valid。
- 必须区分“长期权威事实只有一个 XML”与“磁盘永远只能出现一个文件”。后者无法同时兑现安全替换和恢复。

### CR-FGA-07 “长期只有 INI/XML”与 support/self-test/备份产物

- 用户要求文件只有 INI/XML。
- 文档允许显式 `report.xml`、support output、临时/锁/previous-valid 和配置备份。
- 应冻结：长期业务数据只用 `.ini/.xml`；临时锁不成为事实源；显式 support/export 也必须是 XML 或 stdout。不能暗中新增 `.log/.json/.db`。

### CR-FGA-08 English/ASCII UI 与 Unicode 用户数据

- 用户要求只支持英文、内部不使用 ASCII 之外字符。
- Context 路径示例明确含中文；配置 Prompt/Description、模型输出和工作区内容都可能是 UTF-8。
- `AQ-340` 应把“程序固定标签/机器字段为 ASCII”与“用户数据必须无损 UTF-8/Windows wide path”拆开，否则无法同时支持示例路径。

### CR-FGA-09 `MaxDoubleCheckRounds` 单字段与两类独立 round

- 配置候选只有一个字段。
- `AL06-07/AL06-08` 建议 action-review 与 termination-review 分别有局部 cap。
- FGA-007 需要在 schema 冻结前消除口径，不允许实现者自行解释为共享或各自。

### CR-FGA-10 side 是否消耗 turn request/token budget

- `AL06-06` 建议 side 不消耗 main turn 的 tool/request 次数，但计入 Context 总量。
- `MaxModelRequests/MaxTurnTokens` 候选字段仍写“main/side/review/compaction 怎样计数待统一”。
- 如果不加 purpose ledger，`.status`、恢复和 hard cap 无法一致。

### CR-FGA-11 六种 request purpose 与自动命名

- Prompt 包把六类 purpose 当完整集合。
- Context 配置和 README 又存在自动命名流程。
- FGA-027 必须选择复用 main finish 的 title suggestion、纯本地命名或正式新增第七种 purpose，不能偷偷借用 side/compaction。

### CR-FGA-12 配置 Key 明文与“清除 Key”用户预期

- 当前 INI 明文风险已接受。
- 配置事务、升级和 previous-valid 可能保留旧 Key；Context 对话也可能含用户手贴 Key。
- FGA-022/FGA-023 必须让 UI 区分“清当前结构化 Key”“清 yaca 已知备份”“无法撤回已发送/底层物理残留”。

### CR-FGA-13 Git diff 展示与未确定的 Git 执行来源

- TUI 包把 unified Git diff 当规范展示能力。
- 发行 allowlist 没有确认 Git，`TOOL-12` 也未确认 dedicated adapter。
- 可以显示 yaca direct operation 生成的 unified diff；不能因此暗示会自动安全调用任意系统 Git。FGA-021 必须先收口。

### CR-FGA-14 “完整 v0.1”与暂缓能力的措辞

- 项目负责人说 v0.1 是完整可用版本，同时要求产品保持简单、不要 MCP 等。
- 完整应指已选择闭环的质量与恢复完整，不是把 Web/MCP/plugin/sub-agent/branch/auto-update 全部装入首版。
- `PROD-11`/21 号系统应把每个排除项写成明确 non-goal，避免以后把“未包含”误报为“不完整实现”。

## D. 需要并入现有决策包的位置

不建议创建第 11 个巨型包。按下表把负责人真正需要决定的新增项并入相邻主题；纯技术项只进入规范/证明。

| 目标包 | 应并入的 FGA | 原因 |
| --- | --- | --- |
| 02 产品旅程 | FGA-012、FGA-029 | draft/本地安全属于产品承诺，不是 TUI 小细节 |
| 03 Prompt/人格 | FGA-027 | 自动命名若使用模型，会改变 request purpose 和 Prompt |
| 04 TUI/CLI | FGA-011、FGA-013 至 FGA-016、FGA-026、FGA-030 | 输入 inbox、details、审批与管理确认都是统一交互契约 |
| 05 Model/配置/网络 | FGA-003、FGA-005 至 FGA-008、FGA-023、FGA-024 | 直接改变 schema、reload、endpoint 与 model eligibility |
| 06 AgentLoop | FGA-002、FGA-007、FGA-009、FGA-010、FGA-014、FGA-025 | 改变 turn、budget、retry、resume 和 compaction guard |
| 07 Tools/安全/进程 | FGA-004、FGA-011、FGA-017 至 FGA-021、FGA-024、FGA-031 | 改变真实工具语义、process 安全和 filesystem 保证 |
| 08 Context/XML | FGA-012、FGA-015、FGA-022、FGA-023、FGA-025、FGA-027、FGA-031 | 改变 XML 内容、删除、命名、view 和物理保证 |
| 09 错误/兼容 | FGA-001、FGA-002、FGA-016、FGA-020、FGA-029 至 FGA-031 | 主要产物是诚实降级/error/平台说明 |
| 10 发布/测试 | FGA-001、FGA-028、FGA-029、FGA-031 | CPU、签名、权限和文件系统是 release support matrix |

## E. 新增 readiness 门建议

现有 readiness gate 已经很多，不必为每个 FGA 建 gate。只有下面四项值得进入现有 gate 的通过条件：

1. **AR-P0-02 / AgentLoop outcome**：加入 `ask-user reply` 的新 turn/因果关系，以及 manual retry 不重放 operation。
2. **AR-P0-06 / Tool + Permission**：加入 model `exec` stdin 固定 EOF、管理动作不复用 Agent approval、Git 自动只读执行不得绕过 Shell。
3. **AR-P0-08 / 数据分类**：加入 Context redaction/whole purge 的正式承诺、配置 backup 中旧 Key 的清理说明、SensitiveRead classifier 的诚实边界。
4. **AR-P0-16 / 发布可行性**：加入 Windows CPU ISA、正式支持 filesystem 类别、release signature 或明确 unsigned policy。

其余项目进入下列权威工件即可：

- budget ledger；
- process/shell contract；
- direct list/search tool schema；
- TUI experience book；
- config reload/migration contract；
- Context lifecycle/compaction spec。

## E1. 可直接转成第四轮决策包的六个聚类

如果负责人希望把本轮新增内容一次读完，可以新增一个薄的“第四轮交叉缝隙包”，内部按以下六组排列。它不重复九个主包的完整解释，只引用原组并询问这里真正新增的差异。

### F4-01 旧平台、数据落点与发布真实性

- **包含**：`FGA-001`、`FGA-028`、`FGA-029`、`FGA-031`。
- **负责人选择**：Win32 最低 CPU 是无 SSE2 还是 SSE2；Context 数据根与 workspace 各正式支持哪些文件系统；是否承担 release signing 的密钥治理；明文数据的本地攻击者边界。
- **技术证明**：编译器/依赖 ISA 审计；NTFS/FAT/SMB/POSIX 文件系统原语；ACL/普通用户权限；签名格式和 XP 验证能力。
- **确认后落点**：00、01、08、16、20 号规范与 release support matrix。

### F4-02 Model、配置、网络与 purpose 资源账本

- **包含**：`FGA-003`、`FGA-005` 至 `FGA-008`、`FGA-023`、`FGA-024`。
- **负责人选择**：外部 config 是否显式 reload；HTTP 明文端点边界；Model concurrency/cooldown；aggregate 与 purpose 局部预算；`Tools=off` 主模型资格；Key backup 保留；是否保留 `SensitiveRead`。
- **技术证明**：reload digest/version；per-Model scheduler；统一 budget ledger；classifier corpus；secret canary 与配置迁移。
- **确认后落点**：05/06/08/09 号规范、typed config schema、self-test 与 XML snapshot。

### F4-03 AgentLoop 连续性、等待、重试与过大输入

- **包含**：`FGA-002`、`FGA-009`、`FGA-010`、`FGA-025`。
- **负责人选择**：休眠恢复时等待还是 fail-stop；`ask-user` 回复是否新 turn；手动 retry 的用户含义；不可拆原子组超窗时的交互。
- **技术证明**：suspend/resume trace；request/attempt/turn 因果 ID；队列 hard cap；model-view preflight 与 oversized fixture。
- **确认后落点**：AgentLoop transition spec、budget ledger、Context event schema 与 TUI error cards。

### F4-04 TUI 输入、历史、并发显示与管理确认

- **包含**：`FGA-011` 至 `FGA-016`、`FGA-026`、`FGA-030`。
- **负责人选择**：审批能否改参数；draft 是否持久；queue 管理范围；`.history/.details` 的恢复承诺；并发块顺序；管理型破坏动作的确认；resize 后是否重画。
- **技术证明**：command × state；稳定 local event ID；慢终端/resize golden transcript；ManagementMutation 的 stale/commit/failure trace。
- **确认后落点**：04 号 TUI 包、CLI/action registry、TUI Experience Book、Context 投影。

### F4-05 Process、direct tools 与 Git 的诚实边界

- **包含**：`FGA-004`、`FGA-017` 至 `FGA-021`。
- **负责人选择**：raw exec 是否严格非交互；list/search 的模型可见语义；是否自动提供 Git status/diff adapter。
- **技术证明**：禁用 ambient config；stdin EOF；list/search corpus；双 pipe arrival ordering；Git external diff/textconv/pager/hook 与系统 Git 来源测试。
- **确认后落点**：02/07/08 号规范、process port、tool registry、release allowlist。

### F4-06 Context 隐私、删除与自动命名

- **包含**：`FGA-022`、`FGA-027`。
- **负责人选择**：首版是否允许选择性 redaction；自动命名由 main finish 建议、本地规则还是独立 Model 请求完成。
- **技术证明**：redaction rewrite/known-copy cleanup（若选择）；title collision/path sanitization；Prompt purpose 与 XML migration fixture。
- **确认后落点**：08 号 Context 包、03 号 Prompt 包、Context lifecycle/schema 与命名 registry。

### 六组的建议讨论顺序

建议顺序为 `F4-01 -> F4-02 -> F4-03 -> F4-05 -> F4-04 -> F4-06`：先锁平台/数据与配置事实，再锁 Loop 和工具，最后确定投影与 Context 便利功能。若负责人只想先回答最影响实现的部分，优先 `F4-02`、`F4-03`、`F4-05`。

## E2. 哪些值得新增 AQ，哪些只扩展已有 AQ/TP

新增 AQ 的标准是：现有题目没有能够承载该选择的主问题，而且该选择会改变用户承诺。技术细节或只是补齐现有问题的失败分支，不为追求编号新增 AQ。

### 建议新增 10 个原子 AQ

| FGA | 建议新增 AQ 的问题核心 | 为什么不能只塞进现有题目 |
| --- | --- | --- |
| `FGA-003` | 外部 config 变更的 reload 触发与无效新版本 | `AQ-290` 只管 REPL 保存冲突，没有定义运行中生效 |
| `FGA-006` | per-Model concurrency/cooldown 与 side 等待 | 现有 retry/全局并发都不等于请求调度 |
| `FGA-009` | ask-user 回复的 turn/快照/预算边界 | typed ask-user 只定义输出，没有定义下一条用户输入 |
| `FGA-010` | 用户手动 retry 的可重放范围 | 自动 transport retry 不能代表用户操作 |
| `FGA-012` | 未提交 draft 的 durable/隐私承诺 | 现有 draft 只讨论异步重绘，不讨论崩溃恢复 |
| `FGA-015` | `.history/.details` 的数据源和恢复期限 | 命令已出现，但没有对应产品契约 |
| `FGA-017` | raw exec 的 stdin/交互边界 | `AQ-128` 问交互/后台，但没有决定默认 stdin 会不会偷 TUI 输入 |
| `FGA-022` | Context 选择性 redaction 与 secure-erasure 免责声明 | delete/export 问题只处理整 Context，没有处理单条秘密 |
| `FGA-026` | 非 Agent 管理破坏动作的共同事务/确认 | Tool approval 不能合法承担 config/model/context 管理动作 |
| `FGA-031` | data root 与 workspace 的正式文件系统支持矩阵 | `PLAT-04` 只列原语，没有决定哪些 filesystem 属于公开支持 |

新增时应接在 `AQ-360` 之后连续编号，但编号由主文档维护者统一分配；本审计不预占 `AQ-361` 等正式号，避免并行编辑冲突。

### 只扩展既有 AQ/决策组，不新增编号

| FGA | 扩展入口 | 要补的最小分支 |
| --- | --- | --- |
| `FGA-001` | `AQ-206`、`RF-04` | compiler/CRT 之外加入 CPU ISA floor |
| `FGA-002` | `AQ-270`、`AQ-315`、`AL06-12` | 活动网络/进程/lease 在 suspend/resume 后的真值 |
| `FGA-005` | `AQ-137`、`AQ-146`、`AQ-220`、`M05-01` | HTTP + AuthMode/Key/loopback/LAN 组合 |
| `FGA-007` | `AQ-028`、`AQ-097`、`AQ-153`、`AQ-359`、`AL06-09` | aggregate ledger 与 purpose local cap |
| `FGA-008` | `AQ-144`、`M05-03` | `Tools=off` 的 main/purpose eligibility |
| `FGA-011` | `AQ-225`、`AQ-279`、`TU-07` | 参数编辑必须使旧 review/approval 失效 |
| `FGA-013` | `AQ-032`、`AQ-086`、`AL06-04` | queue list/drop/edit/reorder 的首版范围 |
| `FGA-014` | `AQ-086`、`CONC-02`、`AL06-04` | overflow 拒绝哪一项和 draft 保留 |
| `FGA-016` | `AQ-299`、`AQ-333`、`TU-03` | lane block 原子与可见顺序 |
| `FGA-018` | `AQ-113`、`TS-02`、`TS-07` | list depth/link/ignore/order/incomplete |
| `FGA-019` | `AQ-114`、`AQ-184`、`TS-02` | search dialect/case/binary/ignore/incomplete |
| `FGA-020` | `AQ-122`、`PROC-04` | 跨 pipe 只保存 observed order，不伪造原始全序 |
| `FGA-021` | `AQ-129`、`AQ-249`、`TS-02` | automatic Git adapter 是否属于 Execute，来源与 helper 禁用 |
| `FGA-023` | `AQ-132`、`CFG-10`、`UPDATE-02` | backup 数量、Key clear 与 known-copy cleanup |
| `FGA-024` | `AQ-149`、`TS-04`、`SAFE-09` | SensitiveRead classifier 的来源、版本和 only-raise 规则 |
| `FGA-025` | `AQ-062`、`AQ-310`、`AQ-352`、`AL06-11` | 单一 atomic group 超窗而非总体超窗 |
| `FGA-027` | `AQ-216`、`AQ-259`、`PP-05` | 自动命名的 request purpose/finish field |
| `FGA-028` | `AQ-208`、`RF-06`、`REL-10` | checksum 与 authenticity signature 分开 |
| `FGA-029` | `AQ-040`、`THREAT-01`、`RF-02` | other-user/same-user/admin/offline-disk 威胁分层 |
| `FGA-030` | `AQ-299`、`AQ-332`、`TU-01` | resize 后不重画旧 transcript，只影响新块 |

### 只扩展技术证明，不新增负责人 AQ

| FGA | 扩展 TP | 原因 |
| --- | --- | --- |
| `FGA-004` | `TP-006`、`TP-029` | 禁用 `.curlrc`/AutoRun/pager 等是兑现既有安全保证的方法 |
| `FGA-016` | `TP-022`、`TP-023` | 负责人只选块顺序；公平性/慢终端正确性由证据决定 |
| `FGA-018`、`FGA-019` | `TP-014` 或新增 tool corpus 子检查 | backend 一致性是 conformance，不是偏好 |
| `FGA-020` | `TP-005` | 双 pipe 观察顺序由 process port 证明 |
| `FGA-030` | `TP-023` | resize corpus/恢复 draft 属 renderer 技术门 |

一个 FGA 同时出现在“扩展 AQ”和“扩展 TP”是有意的：AQ 冻结用户可见语义，TP 证明旧平台实现真的做到；两者不能互相替代。

## F. 负责人回复后仍不能自动宣告完成的技术证明

即使负责人接受所有推荐，以下事实仍必须由目标证据决定：

- i686/SSE2 选择能否由全部 Lua/native/curl/Expat 依赖一致兑现；
- XP/CentOS 对 suspend/resume、事件泵和 in-flight cancel 的真实结果；
- curl、cmd、sh、Git 的宿主配置是否已被可靠禁用；
- 支持文件系统上的 lock/no-replace/flush/replace/directory durability；
- regex/list/search backend 是否对同一 corpus 结果一致；
- stdout/stderr arrival seq、UI block ordering和 resize 是否在慢终端下稳定；
- Context redaction/Key backup 清理是否只宣称能够实际做到的 best-effort；
- release signature 的密钥、旧系统验证与发布权限流程。

这些证明应分别并入 `TECHNICAL-PROOF-BACKLOG.md` 的 TP-001/003/005/006/011/014/022/023/027/030，必要时新增子检查点，不再让负责人选择 API 名。

## G. 本轮完成标准

本文件完成的是“敌对式查漏”，不是项目设计确认。后续满足下列条件才算本轮缺口真正收口：

- 每个 `NEW/ATOMIC-GAP` 被并入准确决策组、权威规格或技术证明，且没有重复 AQ；
- 负责人只回答 `O/J` 中会改变产品承诺的部分；
- 14 个 `CR-FGA-*` 均标记为 resolved、superseded 或明确仍待决；
- config schema、AgentLoop budget ledger、Context XML、command registry 和 release matrix 使用同一口径；
- 被排除的能力从 help、配置、XML 和 README 同时移除，不留下无消费者字段；
- 在这些决定收口前不开始实现代码，也不把推荐写成现状。
