# 配置完整性专项审计

更新日期：2026-07-22

状态：Batch 06 前的字段审计底稿；正式组均已回答，本文只保留题源/CV 追踪，不再拥有现行分支

> 现行配置产品面只由 [`DECISIONS.md`](DECISIONS.md) D-049 至 D-056 与 [`subsystems/05-configuration.md`](subsystems/05-configuration.md) 拥有。本文件中仍出现的 `pending`、A/B/C、条件字段或“唯一待回复入口”是冻结的审计语境；必须按 [`DECISION-REGISTER.md`](DECISION-REGISTER.md) 的已选路线生成或删除，不能交给实现者再选。`CV-001..CV-076` 继续作为配置规格必须吸收的验证题源。

## 结论先行

当前配置设计已经覆盖了大部分“会出现哪些区域”，但还不能称为实施就绪。最准确的判断是：

- [`CONFIG-SCHEMA-CANDIDATE.md`](CONFIG-SCHEMA-CANDIDATE.md) 在审计输入时已经是一份很强的**候选字段注册表**，明显优于当前模板；它当时覆盖来源、秘密、生效点、XML 快照和 55 条跨字段校验，本审计发现及后续去捆绑已整合为连续 `CV-001` 至 `CV-076`。
- [`src/_CONFIG_.ini`](../src/_CONFIG_.ini) 是**已经漂移的旧草案**，不能继续作为 parser、默认值或测试 fixture 的事实源。它仍包含已被正式决定否定的 `Permission.Cautious`、profile 内 `DoubleCheck`、全局 retry、`UseStunnel` 和启动自动联网。
- 本审计最初识别的四个跨生命周期缺口是明文 HTTP、per-Model rate/cooldown、运行中外部配置 reload、Runtime 内部工具与宿主配置隔离；它们后来都已提升到正式 owner 或技术门。后续闭包审阅又补齐 config-secret registry/source、ExecProfile 接盘、M05-55 环境快照、输出 secret redaction，以及 M05-57 资源 selector、M05-58 per-Model retry 配置面和 M05-59 过短 config-secret consumer/scanner 保证，因此本文不能再把“只剩四项”当成当前结论。
- 另有一些行为虽然必须实现，却**不应成为 INI 字段**：原子保存、DTD 禁用、auto-save、恢复 fail-stop、内部资源硬上限、curl 不读用户 curlrc、内部工具固定查找路径、结构化 secret 不进 XML/argv、M05-59 scanner 的门槛/匹配资源常量，以及 turn 内配置冻结。普通正文中与过短 secret 相同的字节是否也保证全局排除，必须按 M05-59 A/B/C 诚实表述，不能偷换成无条件不变量。
- 配置只有在“字段注册表、唯一消费者、来源/覆盖、保存事务、运行时 reload、迁移、REPL、self-test、旧平台证明”全部对齐后才算完整。单纯把候选字段复制进 INI，会把未决推荐伪装成默认契约。

本审计建议把配置面收敛成八个核心区域：`General`、`Agent`、`Network`、`Exec`、`Context`、`TUI`、`Permission.*`、`Model.*`。`TUI` 始终存在，因为相互独立的启动信息逐字段开关已有明确消费者；不提供启动 master，只有通知字段仍由 TU-27/TU-30 条件生成。它不是旧空壳 `Tui` 的沿用，也不承载 theme/vivid/language/快捷键或输入提示符配置；chat 输入提示符固定为 `>>`。仍不新增 `Storage`、`Update`、`Plugin`、`Telemetry`、`Project` 或 `SelfTest` section；启动自检策略是 `General.StartupSelfTest`。必须存在但不适合用户调整的常量，进入版本化 Runtime limits/manifest，而不是藏成更多配置键。

后续整合把本审计发现进一步拆成了独立 owner：M05-33/36/37/38 分别拥有 Endpoint、proxy、CA、redirect，M05-23 拥有 header/body，M05-16/M05-56 拥有粗粒度 workspace 外权限与零 `SensitiveRead`，M05-57/M05-58/M05-59 拥有 selector、per-Model retry 和过短 secret 保证；TS/AL/F4 分别拥有工具、运行时与跨系统语义。它们现在都已经在 Batch 06 取得现行选择。本文中的早期候选若与正式登记不同，一律以正式登记和 owner 规格为准；`CCA-Q-*` 不再接收回复。

## 审计证据与边界

本轮逐项比较：

- [当前旧模板](../src/_CONFIG_.ini)；
- [配置 Schema 候选注册表](CONFIG-SCHEMA-CANDIDATE.md)；
- [数据分类与跨模型可见性候选](DATA-CLASSIFICATION-CANDIDATE.md)；
- [决策包 05：Model、完整配置、网络与 Self-Test](decision-packets/05-model-configuration-network-selftest.md)；
- [决策日志](DECISIONS.md) 与 [深层原子问题](QUESTIONS.md)；
- [05 配置子系统](subsystems/05-configuration.md)、[03 网络子系统](subsystems/03-network-transport.md)、[06 模型协议](subsystems/06-model-protocols.md)；
- [设计清单](DESIGN-CHECKLIST.md) 中的 `CFG-*`、`NET-*`、`MODEL-*`、`SAFE-*` 和 `DIAG-*`。

本文件不决定 XML 元素名、curl/native helper 选型、最终默认毫秒数或测试平台矩阵，也不修改模板。它只回答：“如果负责人把选项回复完，配置设计还缺什么才足以进入实现计划？”

## 五种结论标记

| 标记 | 含义 | 谁关闭 |
| --- | --- | --- |
| `C` | 已有明确项目决定；文档/模板只能服从，不再比较产品方案 | 文档维护者归档一致性 |
| `D` | 可由已确认方向直接推导的工程不变量；不需要负责人再选偏好，但必须写规格和测试 | 技术设计/测试 |
| `O` | 会改变产品行为、兼容性、隐私或配置体验，必须由负责人选择 | 项目负责人 |
| `T` | 产品方向明确后仍需目标平台实验证明，不能靠文档投票 | 技术验证 |
| `J` | 产品保证已经明确，技术侧需证明实现；只有证明失败且退路会改变保证时才回到负责人 | 联合 gate |

一个条目可以同时是 `O+T`：例如负责人可以允许 HTTP loopback，但 curl/代理/重定向是否真的按契约工作仍需测试。本文写 `J/T` 时表示当前没有未归属的产品选项：先由技术证明冻结实现值，只有失败退路会改变已确认保证时才重新询问负责人。

## 何谓“一个配置字段完整”

每个最终保留字段都必须在同一份 typed schema 中拥有下列 14 个属性；缺一个，就不能让模板、REPL 或 Runtime 自行猜：

1. 稳定字段 ID、section/key 拼写和 schema 引入版本；
2. 唯一领域消费者，以及只是显示该值的投影消费者；
3. 为什么必须由用户配置，而不是固定产品行为或 Runtime hard limit；
4. 类型、编码、单位、闭/开区间和最大字节数；
5. 缺失、空字符串、`false`、`0`、`unknown`、`auto` 的不同语义；
6. 新模板写出的默认值，以及 reader 对旧版本缺失值的迁移行为；
7. 敏感级别：public、conditional、user-content、secret；
8. 允许来源：schema、INI、XML selector/override、显式本次命令；
9. merge/override 规则，以及哪些来源绝对不能提供该值；
10. 生效点：bootstrap、Context open、next-turn、next-request、next-tool-call 或 display-only；
11. active turn 是否冻结，以及配置变化怎样形成 transition/snapshot；
12. 逐字段、跨字段、迁移和未知字段验证；
13. config-repl/model-repl/show-config/self-test 怎样显示、编辑、脱敏和解释它；
14. XP x86、CentOS 7、文件系统、终端、curl/CA、32 位内存或代码页风险。

现有候选表已经覆盖其中约 8 项，但“消费者、是否真的需要用户可调、运行中 reload、逐字段迁移、UI/self-test 责任、目标平台证明”仍分散在其他文档中。本审计的作用就是补这六列，而不是再建立第二份相互竞争的 schema。

## 配置生命周期必须先闭合

字段表之前要先冻结整个生命周期，否则同一个值在不同入口会有不同答案。

```text
locate portable data root (before reading INI)
  -> bootstrap parse schema/version
  -> parse complete INI concrete syntax
  -> field + cross-field validation
  -> create immutable loaded generation
  -> open/create Context XML
  -> apply XML selector/override whitelist
  -> before every top-level main/side turn admission:
       read complete INI bytes + private source digest
       unchanged -> reuse immutable generation
       changed -> parse + cross-validate complete candidate
                  atomically publish one generation or fail closed
  -> freeze effective turn snapshot
  -> child tools/reviews/retries consume only that snapshot
  -> record any non-secret effective transition in Context XML
```

必须同时存在两种 digest，不能复用一个值：

- **private source digest**：对原始 INI bytes 计算，只在本进程内用于外部修改检测；它间接包含全部 `source=config-file` secret，不能写 XML、日志或 support。
- **public effective digest**：只对允许进入历史的非秘密规范投影计算，写入 XML 解释某 turn 使用了哪套配置；任一 registered secret value/private equality fingerprint 都不参与。

这是 `D`。既然 Key 已确认明文位于 INI，而 Key 又不得进入 XML digest，就不可能安全地用“整份 INI hash”同时承担冲突检测和可移植快照身份。D-048 还确认上面的逐顶层 turn observation：每次都读取完整 bytes/digest，不靠 mtime/size、不需要 watcher、轮询间隔、人工 reload 确认或配置 policy 字段；active turn 及其 child activity 始终冻结旧 generation。

## 配置来源与覆盖审计

| 来源 | 可以定义什么 | 不可以定义什么 | 冻结/生效 | 审计结论 |
| --- | --- | --- | --- | --- |
| Runtime hard limits | 不可关闭的内存、队列、XML、网络、循环和安全上限 | 用户人格、endpoint、Key、默认 Model/Permission | 程序版本/bootstrap | `D`；不是 INI section |
| typed schema | 字段、类型、安全默认、迁移、帮助、脱敏元数据 | 用户秘密和用户选择 | 程序版本/bootstrap | `O` 需确认唯一事实源；推荐沿用 M05-07/AQ-131 |
| 完整用户 INI | 八个核心 section 家族；`TUI` 固定含启动头显示字段，通知字段按 TU-27/TU-30 条件生成 | Context 当前选择的历史事实 | load/reload generation | `C` 方向已确认；通知字段仍待 TU-27/30 |
| Context XML | 无条件项为 `CurrentModel`、`CurrentPermission`、`DoubleCheckOverride`、`ContextPrompt`、`AutoRenameDisabled`；AL06-07 A/B + AL06-08 C 才有 `ActionReviewModelMapping`，AL06-49 C 独立生成 `TerminationReviewModelMapping`，AL06-11 A + AL06-34 C 才有 `CompactionConsent`，AL06-51 C 才有按 purpose 分离的 reusable `EndpointDisclosureConsent`，TS-14 C 才有 identity-bound `WorkspaceAcknowledgement`，M05-51 C 才有 `CurrentExecProfile` selector + non-secret definition snapshot/mapping evidence；M05-06 B/C 共享条件 turn/threshold overrides，只有 C 再有 queue/side/tool-preview/diagnostic 四项精确 preference；raw shell 历史保存 `ExecEnvironmentSnapshot` 公开投影。AL06-51 三条路线都逐 request 保存 disclosure receipt，B 的 reuse 只在当前 active Context handle 内存中；AL06-50 的 no-progress threshold 从不成为 XML override | registered secret values、endpoint/proxy/CA/Permission/Exec profile/environment 定义或变量值、current workspace root/workdir/root list/alias/selector、跨 Context trust registry、任意 session key；AL06-51 A/B 的 reusable consent state | Context open / next-turn / next purpose | 唯一 current root 从 XML 在 `CONTEXT` 下的镜像父目录解码；XML 中工具 cwd/path 只作历史证据。`AutoRenameDisabled` 是专用 bool，不是通用 flags bag。其他白名单及条件字段由同一 registry 生成；action/termination mapping 与 endpoint disclosure consent 按 purpose 独立验证；foreign/imported consent 只作 audit。XML 不能反向启用功能、环境、压缩、权限或跨 endpoint 外发，`O` |
| 进程环境 | 只有在 `ProxyMode=environment` 或 raw shell environment policy 明确允许时被消费者读取 | 不能成为 Key 的隐式 fallback；不能覆盖 typed schema | request/tool boundary | `D+O`；必须列明读取哪些变量 |
| CLI/TUI 动作 | 选择 Model/Permission、`.cautious`、`.prompt` 等明确动作；每个 TUI domain action 由同一 typed action registry 提供 CLI projection | 不提供通用 `--set any.key=value` 第三套配置层；CLI parity 不发布 remote/headless API，也不允许非 TTY 绕过确认/Permission | next-turn/transaction | domain-action parity 已确认；generic override 仍由 M05-22，`D+O` |
| 工作区文件 | 只作为模型/工具读取的数据或明确采用的项目指令 | endpoint、Key、Permission、proxy、工具开关 | tool/prompt contract | `D`；不新增 project config |

候选 schema 开头写了“当前命令显式的一次性参数”，但目前没有列出允许的一次性字段。最终规范要么列出有限命令，要么删除这个泛化来源；否则实现者会自然加入一套未审计的 `--set` 机制。

## Section 与字段族逐项审计

### 1. `General`

| 字段族 | 必要性与消费者 | 完整契约检查 | 迁移、UI/self-test 与旧平台风险 | 结论 |
| --- | --- | --- | --- | --- |
| Exec section/profile 形态 | M05-51 的资源策略与 Context selector 消费 | A 的资源字段在 singleton `[Exec]`；B 不生成资源字段；C 在有序 `[ExecProfile.<Name>]` 中定义两个字段，并用条件 `CurrentExecProfile` 只选择、不覆盖定义；M05-15 B 的环境字段始终留在全局 `[Exec]` | config-repl 管理 profile/引用；TU-32 条件生成 show/use/reset 用户 action；首项精确选择、rename/delete/stale mapping、next-turn 切换 receipt 与 XML snapshot 必须完整；同名定义不同/外来 selector 必须显式映射，Model 不得选择更宽 profile | 条件结构，M05-51 唯一 owner，CX-07/18 消费 import gap，`O+T` |
| `SchemaMajor` / `SchemaMinor` | bootstrap parser、迁移器、REPL writer 必需；不是 AgentLoop 配置 | ASCII decimal；major/minor 分开；INI only；bootstrap；缺失是否可识别为 pre-schema 文件需迁移表 | config-repl 顶部显示；Stage 1 检查 reader/writer 能力；旧程序不得重写更高 major | `O` 冻结版本语义，随后 `D` |
| `SystemPrompt` | Prompt assembler 必需，用户已要求全局 Prompt | UTF-8 用户内容、明确字节/token 上限；INI only；next-turn；进入 XML 的是 Prompt component snapshot，不是 XML override | PP-11 A 时旧 `Model.CustomPrompt` 逐来源、逐目标确认迁移，不能自动拼到当前 Context；B/C 按各自条件字段保留；REPL 多行编辑、预览、秘密提醒；XP 内存和控制台 echo 需测 | 保留；多行 grammar/上限为 `O+T` |
| `StartupSelfTest` | 启动路由和 self-test controller 消费；是唯一的启动自检 gate | `off|stage1|stage2|stage3`，新配置默认 `off`；INI only；bootstrap 配置验证后、打开/创建 Context 前生效；`stageN` 始终严格依次执行 1..N | Stage 1 还要离线检查 Context codec、镜像/workspace、Catalog/XML partial、scan cap 与性能预算；Stage 2/3 仍须当次明示网络/费用/外发范围并取得同意；Stage 3 对 Permission 名称/Description/Prompt/capability 和自然语言拼写只作 advisory；取消、失败或 partial 均阻止进入 chat | 新的已确认字段；不从旧 `CheckModelOnStart` 自动迁移 |
| `LogLevel` | 只应控制可选诊断详细度；不能改变 canonical XML 事实 | M05-17 A 为 error/warn/info/debug/trace、默认 info；B 无字段；C 为 normal/trace、默认 normal；INI only，next diagnostic event | show-config 显示；Stage 1 拒绝混用两个 enum；没有独立日志文件时 `trace` 的目的地必须写清 | 条件字段，M05-17 唯一 owner |
| `SelfTestReviewerModel` | **仅 M05-12 B** 的 Stage 3 reviewer selector 消费 | Model logical name；缺失/禁用/本次 Stage 2 未通过时 Stage 3 unavailable，不 fallback；普通 Agent/Stage 1/2 不受影响 | config-repl 显示引用状态；Stage 3 仍显示并再次 consent | 条件字段，M05-12 唯一 owner |
| 生成/更新时间、程序版本 | 没有领域消费者；文件 mtime 不可靠但也不应由用户配置 | 不是用户字段；程序版本与 schema 版本分离，构建版本进入诊断/快照 | 当前模板仅用注释 `GeneratedAt/UpdatedAt`，不可作为迁移依据 | 不加入 schema，`D` |

审计判断：`General` 不应继续膨胀。`Language`、含糊的通用 `Mode`、`Vivid`、`Theme`、自动更新、遥测、数据根都没有合法消费者或会产生 bootstrap 循环。只有 TS-18 B 才在 Agent 生成语义窄化的 `Autonomy`，它不是旧 Mode 的自动迁移。固定 English/ASCII UI、自然语言跟随用户、自动终端降级已经由其他系统表达。

### 1A. `TUI`

| 字段族 | 必要性与消费者 | 完整契约检查 | 迁移、UI/self-test 与旧平台风险 | 结论 |
| --- | --- | --- | --- | --- |
| `StartupShowSlogan` / `StartupShowVersion` / `StartupShowWorkDir` / `StartupShowDataRoot` / `StartupShowConfigStatus` / `StartupShowContext` / `StartupShowContextHash` / `StartupShowModel` / `StartupShowPermission` / `StartupShowDoubleCheck` / `StartupShowStatusHint` | startup transcript renderer 的逐行投影消费；没有 master | 全部 bool/INI-only/display-only；除 `StartupShowDataRoot=false` 外默认 `true`；各开关互相独立，每个 enabled 字段独占一行并从行首开始；Slogan 文本固定为 `yaca: Yet Another Coding Agent.`，status hint 固定指向 `.status`；ConfigStatus 只投影已发布 generation，未持久化 Context 不伪造名称/hash | XP 代码页下 UI 标签与 Slogan 仅用 ASCII，路径/名称经宽字符边界再显示；配置损坏时使用固定 bootstrap error；`StartupHeader`/任何总开关是未注册、无消费者字段，必须诊断而非忽略 | 已确认字段族，`D+T` |
| `NotificationChannel` | 仅 TU-27 B/C 的 notification adapter 消费 | B 为 off/bell，C 为 off/bell/desktop/both，默认 off；INI-only、next-event；XML 只 snapshot，不能 override | XP/SSH/无桌面 session 能力缺失只回退 transcript；不能携带正文/路径/secret，也不能成为审批/错误唯一信号 | 条件字段，TU-27 唯一 owner，`O+T` |
| `NotificationEvents` | 仅 TU-27 B/C 且 TU-30 C 的 event filter 消费 | 固定 typed allowlist，缺失采用 action-required 集合；TU-30 A/B 的 scope 固定且没有字段 | 每 canonical event ID 至多一次；恢复/重绘不补发；未知事件名 error | 条件字段，TU-30 唯一 owner，`O+T` |

### 2. `Agent`

| 字段族 | 必要性与消费者 | 完整契约检查 | 迁移、UI/self-test 与旧平台风险 | 结论 |
| --- | --- | --- | --- | --- |
| `DoubleCheck` | AgentLoop/review router 必需；`.cautious` 形成 XML tri-state override | bool INI default + `inherit|true|false` XML；next-turn；至少包含 termination review；不能放进 Permission/Model | config-repl 显示 INI/XML/effective；`.status` 显示来源；Stage 1 检查轮次预算；旧 Cautious/profile 值迁移需人工选择 | 结构 `C`，默认/动作范围/失败策略 `O` |
| `Autonomy` | 只有 TS-18 B 的 prompt/UI experience policy 消费 | `direct|explanatory`，INI only、next-turn；只影响 PP-06/PP-14/PP-15/PP-16 已允许文字块内的解释粒度和可选额外验证建议；不能增删消息、执行额外验证或改变报告结构/安全/预算 | config-repl/status 显示 effective；Context 只 snapshot 不 override；A/C 拒绝 orphan field；旧 Mode 不自动迁移；各 PP 组选定的时点/栏目/长度仍有效 | 条件字段，TS-18 唯一 owner；进度、工具叙述、报告、普通详略仍分别归对应 PP 组 |
| `ActionReviewModel` / `TerminationReviewModel` / `CompactionModel` | ActionReviewModel 仅由 AL06-07 A/B + AL06-08 B 的 action-review 消费；TerminationReviewModel 仅由 AL06-49 B 的 termination-review 消费；CompactionModel 只在 AL06-11 A + AL06-30 B 消费 | 都是 enabled Model logical name；三个 purpose 独立解析、冻结和失败关闭，缺失/失效不 fallback；AL06-07 C 时 action 字段 not-applicable，但 termination 字段仍按 AL06-49；AL06-11 B/C 不发 compaction Model request | config-repl 分别显示引用解析、目的和外发边界；Stage 1 按条件静态解析，实际 request manifest 保存对应最终实例 | 条件字段，AL06-07/08/11/30/49；Context C 路线分别使用独立 event/条件 mapping，不复制定义 |
| turn request/tool/token guard | AgentLoop scheduler 必需，防止单轮无限循环 | AL06-42 A 才公开 `MaxModelRequests`、`MaxToolCalls`、`MaxTurnTokens`；B 使用版本化 manifest fixed guard；M05-06 只决定 XML 是否可下调 | UI 显示 configurable/fixed、来源和剩余量；Stage 1 拒绝未选分支字段；XP x86 soak 校准 | 条件字段，AL06-42 唯一 owner，`O+T` |
| active-time turn guard | 每个 turn 的 composite hard guard 必需 | AL06-42 A 才有 `MaxTurnActiveTimeMs`；B 使用发行物固定 guard；只累计 Runtime active work，不累计 waiting-user、人工 approval、idle 或 OS suspend；各 request/tool 另有 wall-clock deadline | `.status` 显示来源、已用/剩余和 active-time 定义；单调时钟、sleep/suspend/恢复测试 | 条件字段，AL06-42 唯一 owner，`O+T` |
| Context 累计 ledger | 长会话 audit 始终需要；是否成为 hard gate 由 AL06-09 独占 | A 只保存累计 audit、无 `MaxContext*`；B 生成 request/tool/input/output token/active-time 五个 hard cap；不与 per-turn field 混名 | status 显示 Context 累计与 turn 剩余两个层级；恢复/Model switch/retry 不重置；provider usage 缺失保守估算 | 条件字段族，AL06-09 唯一 owner，`O+T` |
| stuck/repeat | AgentLoop progress detector 消费 | AL06-50 A 不生成 INI 字段，使用发行 manifest 的 versioned threshold tuple；B 只生成一个有界 `MaxNoProgressRepeats`；C 只生成版本化少量 detector keys：`MaxNoProgressExactOrErrorRepeats`、`MaxNoProgressCycleRepeats`、`MaxNoProgressSemanticSteps`。B/C 均 INI-only、next-turn，不能为 0/off/infinite 或超过 Runtime maximum；算法、默认和 exact range 仍由技术证明冻结 | config-repl/status 只显示所选分支及 actual manifest/scalar/map source；active turn 与 unfinished-turn recovery 使用冻结 snapshot；Stage 1 拒绝 mixed/orphan/XML override，self-test/评测 fixture 不让 Stage 3 LLM 判定算法 | 条件字段族，AL06-50 唯一 owner；算法/数字为 `T`，配置表面为 `O` |
| DoubleCheck 局部预算 | review controller 消费 | AL06-27 A 始终有 `MaxTerminationReviewRounds`，仅 AL06-07 A/B 再有 `MaxActionReviewRounds`；27 B 才有共用 `MaxDoubleCheckRequests`；27 C 使用 fixed reserve。所有路线仍受 AL06-42 turn guard | config-repl 只显示真实存在分支；Stage 1 拒绝 AL06-07 C 下 action cap 及 orphan/mixed fields；测试拒绝循环、无效 verdict、超时 | 条件字段集，AL06-07/27，`O+T` |
| `ApprovalExpiryMinutes` | 仅 AL06-44 C 的 approval aging controller 消费 | 正整数分钟且受 Runtime maximum；不允许 off/infinite；到期只能 synthetic expire/deny，永不 allow | wall-clock 回退/恢复可信度不足按 expired；A/B 下字段 unknown；页面显示 exact expiry | 条件字段，AL06-44 唯一 owner，`O+T` |

审计判断：不要为 main、side、action-review、termination-review、compaction 各复制一整套几十个预算字段。AL06-42 独占每 turn guard 是可配置还是 manifest fixed；AL06-09 独占 Context 累计只审计还是也成为 hard ledger；只有用户明确需要独立调节的 purpose 才进入 INI。`context-name` 由 `AutoNameEveryMainTurns>0` 周期产生，但不复制 purpose 预算字段；它共用 Model scheduler/admission/cancel 证据。字段数量少不代表预算不完整，关键是计数表和条件存在性完整。

### 3. `Network`

`Network` 描述 yaca 自己发往 Model endpoint 的全局传输策略；TS-11 B/C 时还包含一组明确以 `DirectHttp` 命名、与 Model credential/transport 隔离的 direct-tool policy。它始终不约束 raw shell 中用户/模型自行启动的网络程序。

| 字段族 | 必要性与消费者 | 完整契约检查 | 迁移、UI/self-test 与旧平台风险 | 结论 |
| --- | --- | --- | --- | --- |
| `ProxyMode` | network policy compiler 必需 | M05-36 A 为 off/environment/explicit、B 为 off/explicit、C 为 off/environment；三项 missing/new 均 off，environment 必须显式选择并把实际 credential 标为 `source=ambient-environment`，不借用 config.ini ACL | `FollowProxy` 迁移；REPL 显示实际模式/source 但不泄露 credential；Stage 2 显示将用 proxy/bypass | 条件 enum，M05-36 唯一 owner，`O+T` |
| `ProxyUrl` | 仅 explicit 模式需要 | 绝对 proxy URL；credential 是 `source=config-file` secret；禁止进入 XML/argv；空值与 missing 分开；不能在 off/environment 下偷偷生效；weak/unverifiable config 时每个真正经过它的 consumer 服从 M05-54 | UI 只显示 sanitized origin/configured/source；ACL/secret canary；旧 curl proxy auth 需目标机测试 | 保留，`D+T` |
| `NoProxy` | 企业/本地 endpoint 可能需要 | 必须选择一种稳定语法；不能把 curl 不同版本语义直接当 schema；conditional internal metadata；next-request | config-repl 逐规则验证；Stage 2 显示匹配结果；CIDR 是否受随包 curl 版本支持需测 | 保留与语法均为 `O+T` |
| `CaMode` / `CaFile` | TLS trust compiler 必需 | M05-37 A 为 bundled/system/custom/combined、B 为 bundled/custom，二者 missing/new=bundled；C 为 system/custom，missing/new=system。CaFile 仅 custom；禁止 insecure fallback | 删除 `UseStunnel`；Stage 1 检查有效 trust source，Stage 2 测证书错误；XP system store 能力不可假定 | 条件 enum/default，M05-37 唯一 owner，`O+T` |
| transport limit fields | network parser/backpressure 必需 | M05-14 A 只公开 header/event/buffer；B 另公开 compressed/decompressed/error/tool-arguments/logical-response/ratio；C 全部只在 Runtime manifest。所有用户值只能下调 hard cap | self-test 用压缩炸弹、无限 SSE、巨大 error/tool args fixture；32 位组合内存校准 | 条件字段集，M05-14 唯一 owner，`O+T` |
| `DirectHttp*` policy | **仅 TS-11 B/C** 的 direct HTTP tool 消费 | 独立 CA 值（来源集合/default 跟随 M05-37 分支）、proxy/no-proxy、same-origin redirect 与 exact allowed-origin；不读 Model Key/header/proxy credential | config-repl 独立 secret/redaction；call approval 显示 origin/CA/proxy；TS-11 A 时全组消失 | 条件字段族，TS-11 唯一 owner，`O+T` |

#### 明文 HTTP 是未闭合的产品策略

候选 `Endpoint` 接受 `http` 或 `https`，同时允许明文 Key，却没有说明什么时候可以把 credential、对话、源码和工具结果通过无 TLS 连接发送。这不是 `SkipTlsVerify` 问题；HTTP 本身没有传输加密。

建议负责人从三种策略选择：

- A：`https` 普遍允许；`http` 只允许可证明的 loopback、强制 direct/bypass 且 `AuthMode=none`，任何 Key/secret header + HTTP 都是静态错误。（推荐，最简单）
- B：A 之外允许 per-Model 显式确认 `http`，但 REPL/每次跨 endpoint 预检都显示“内容与 Key 明文传输”；需要一个不能被 preset 静默开启的危险字段。
- C：任何绝对 HTTP URL 都按用户显式配置直接使用，仅警告。

这个选择是 `O`；loopback 判断、代理是否使“本地 URL”实际离机、redirect scheme downgrade 和 DNS/IPv6 细节是 `T`。在选择前不要草率新增 `AllowInsecure`，因为它会把“明文 HTTP”“跳过 TLS 验证”“弱 TLS”三个不同风险揉成一个开关。

#### 宿主 curl 配置必须隔离

Runtime 内部 curl 不能读取用户 `.curlrc`、`_curlrc`、`.netrc`、`CURL_CA_BUNDLE` 或 cwd/PATH 中碰巧出现的 CA/tool。否则同一 INI 在两台机器可能改变 proxy、header、redirect、credential、CA、trace 和输出。

这不是用户偏好，建议作为 `D`：内部 curl 使用随包绝对路径和完整显式参数，禁用默认 curlrc，禁止 netrc，显式传 proxy/CA/redirect/protocol/output 规则。官方 curl 手册说明 [`-q/--disable` 只有作为第一个参数时才阻止读取 curlrc](https://curl.se/docs/manpage.html#-q)，并说明 [`CURL_HOME`/`XDG_CONFIG_HOME`/`HOME` 会参与默认配置定位](https://curl.se/docs/manpage.html#ENVIRONMENT)、[`CURL_CA_BUNDLE` 可能改变 CA](https://curl.se/docs/manpage.html#ENVIRONMENT)。最终随包版本是否具有相同选项必须作为 `T` 验证，不能只引用最新版手册。

### 4. `Exec`

| 字段族 | 必要性与消费者 | 完整契约检查 | 迁移、UI/self-test 与旧平台风险 | 结论 |
| --- | --- | --- | --- | --- |
| `MaxExecTimeMs` | raw-shell tool controller 消费；仅 M05-51 A/C 公开 | 正整数毫秒/call；不能用 `false=无限`；受 Runtime hard cap，并与 turn active-time guard 取更早者；next-tool-call | 旧 `TimeoutMs=false` 迁移为 schema default/explicit auto；审批显示 deadline；XP 取消/进程树证明 | 条件字段，M05-51 唯一 owner，默认 `O+T` |
| termination grace（非配置字段） | process adapter 消费 | 各平台发行 manifest 固定有界毫秒值；grace 后强制终止；无法证明树终止仍返回 unknown；INI/XML 不得覆盖 | status/self-test 只读显示 adapter、manifest 与实际值；child-tree/XP 取消 fixture 冻结常量 | Runtime/manifest 常量，`J/T` |
| `MaxOutputKiB` | capture/canonical result 消费；仅 M05-51 A/C 公开 | stdout+stderr canonical captured bytes 合计；达到 cap 后仍 drain-and-discard，分别记录 observed/captured/discarded 与 truncation；不能关闭 Runtime hard cap | `MaxOutputKB` 迁移并改 KiB；Stage 1 大输出；32 位内存/pipe backpressure | 条件字段，M05-51 唯一 owner，默认 `O+T` |
| output decoding（通常不是配置字段） | text boundary/process result 消费 | TS-38 A 严格使用 spawn 时平台 encoding snapshot，B 严格 UTF-8，C 仅在 TS-23 A 的 typed envelope 中允许逐 call 从发行 allowlist 选 decoder；Process 先观察 raw bytes，M05-59 所选路线仍纳入 exact-scan 集的 registered config-secret value 在 direct TS-16/exec TS-39 persistence/digest 前写 typed redaction marker，其余 retained canonical bytes 才无损保存；A 的过短值不能进入精确 consumer，B 的过短普通正文 coincidence 不伪装成已扫描 secret，C 对任意长度继续扫描；失败形成 typed binary，不做有损 replacement | XP OEM/codepage、Linux locale、非法序列、NUL、binary、门槛前后与跨 chunk/重复/重叠 secret canary；decoder/digest scope 进入 result，换机不能重写历史 | 无全局 `OutputEncoding`；TS-38 唯一 owner，M05-59 独占短值保证，C 的逐调用字段为条件 tool schema，不是 INI |
| `EnvironmentMode` | **仅 M05-15 B** 的 raw shell launcher 消费 | `inherit|clean`；inherit 精确采用 M05-55 选定的版本化 baseline，clean 使用 Runtime 最小环境；合成固定为 baseline→unset→set→reserved/size validation；A 固定采用同一所选 inherit baseline、C 固定 clean，都没有该字段 | approval/status 显示 baseline identity、公开名称集合与 public digest；value equality 只用进程内 private binding；Stage 1 做宿主 credential/proxy/agent canary；XP `%COMSPEC%/TEMP%/PATH%` 最小集合需测 | 条件字段，M05-15 拥有字段/合成，M05-55 条件性拥有 inherit 成员政策 |
| `EnvironmentSet` / `EnvironmentUnset` | **仅 M05-15 B** 在用户确有稳定全局 shell 环境需求时存在 | 共用 schema collection grammar；Windows 名称 case-fold、Linux exact ASCII；重复、set/unset 同名、保留变量和大小超限整代 error，不 last-wins；`EnvironmentSet` value 是 `source=config-file` secret，XML/public digest 只保存 canonical 名称与集合摘要；weak/unverifiable config 时其 raw exec consumer 服从 M05-54 | secret 输入/脱敏/支持输出；Windows env block 大小、case-insensitive 名称和 reset family 原子预览 | 条件字段；A/C 时必须从 schema 删除 |
| `ShellDialect` | **仅 TS-13 C** 允许从发行 allowlist 选择；A 固定 OS baseline，B 由发行 manifest 固定且不可配置 | typed enum，不接受任意 executable path；每项绑定 quoting/encoding/cancel adapter | model/config REPL 只列目标 zip 已证明项；跨平台不能复制一个不存在的 dialect | 条件字段，TS-13 唯一 owner；跨流输出顺序由 TS-22 且无配置键 |
| `ExposeConfiguredProxy` | 没有合法消费者；会把 Network secret 复制给 raw shell | M05-15 三项都不自动传播 configured proxy；需要代理时由获批 raw command 明确表达 | 字段出现即 unknown/deprecated error，避免 XML command/环境暗中泄密 | 删除，不再是负责人问题 |

#### “内部工具”与“模型 raw shell”必须是两条配置边界

建议固定：

- yaca 自己调用的 curl、可能的 Git evidence、diff/helper 使用 Runtime 构造的隔离环境、绝对路径和机器输出参数，不继承 system/global 用户 alias、pager、editor、credential helper、外部 diff 或 trace 配置。
- 模型 raw shell 的环境严格采用 M05-15：A 受控继承、B 可配置 inherit/clean/set/unset、C 固定 clean；三者都不自动继承 yaca configured proxy/credential。UI 明确它不具有 OS sandbox 保证，`Permission.Shell` 决定是否允许发起，而不是解析任意命令的真实副作用。
- direct file tools 不通过 Git、shell 或用户可替换外部工具实现核心读写。

如果 internal Git evidence 进入 v0.1，repository-local config 不能简单归入“用户全局配置”后一律忽略：`core.ignorecase` 等值可能是正确解释工作树所需事实，而 external diff、textconv、pager、credential helper、alias 或网络相关配置又可能启动程序或改变输出。最终 Git adapter 必须列出允许读取的 repository semantics，并用显式参数禁掉可执行扩展；做不到时就不把 Git 作为 Runtime 内部依赖，只把它留给 raw shell。这个选择属于工具包，不能靠新增 `InheritGitConfig` 布尔掩盖。

Git 官方文档说明普通命令默认读取 system/global/repository 配置，且环境还可注入配置；它提供 [`GIT_CONFIG_GLOBAL`、`GIT_CONFIG_SYSTEM`、`GIT_CONFIG_NOSYSTEM` 等控制](https://git-scm.com/docs/git#Documentation/git.txt-codeGITCONFIGGLOBALcodecodeGITCONFIGSYSTEMcode)。目标系统实际 Git 版本支持哪些隔离手段是 `T`。这条边界不需要新增 `[Tool.Git]` 或 `[Host]` section。

### 5. `Context`

| 字段族 | 必要性与消费者 | 完整契约检查 | 迁移、UI/self-test 与旧平台风险 | 结论 |
| --- | --- | --- | --- | --- |
| mirror-derived single root（非配置字段） | Context open/resume、默认 tool cwd 和 Resolver 起点消费 | 新建时以用户传入且可进入的真实目录为唯一 root；打开时由 active XML 在 `__yaca__/CONTEXT/` 下的镜像父目录解码。XML/INI 不保存 current root/workdir/root list/alias/selector；上级 Git root只作证据。续接不自动 jump/ask/keep；显式 context-repl rebind 以 no-replace/可恢复协议移动 XML | context-repl/status 显示 derived root 与可用性；目录不存在/无权限时拒绝进入 Agent并给出修复路径；Windows 宽字符、junction、Linux bytes、移动后 hash/stale approval 需测 | D-045 与 F4-14=A/AS-006-03 已确认，剩余为 `T` |
| `CompactThreshold` | 仅 AL06-11 A 的 structured-summary 或 B 的 deterministic-checkpoint trigger 消费 | ratio 严格 `(0,1)`；按有效 Model 窗口、Prompt/tool/output reserve 计算；C 下字段/override 不存在 | 旧字段只有 A/B 路线迁入；status 显示 consumer/threshold；未知 ContextLength 保守 | 条件字段，AL06-11 唯一 owner，`O+T` |
| `AutoNameEveryMainTurns` + XML `AutoRenameDisabled` | D-041/D-046 低优先级 Context 周期自动命名 scheduler 消费 | interval 为 integer `0..RuntimeMax`、默认 `10`、`0` 全局关闭；INI only。专用 XML bool 缺失/false 允许、true 禁止当前 Context；二者都在 next-idle admission 检查 | XML 保存 effective interval、main-turn count、watermark、request/result/cancel、old/new name 与标记。手工 rename 成功事务默认置 true，自动 rename 不置；context-repl 可切换，取消从新基线等待完整间隔而不立即/追补命名 | 已确认字段与 metadata；不生成通用 flags bag、名称/目录编码或额外 INI precedence 开关，`D+T` |
| `ListSortBy` / `ListSortDirection` | context-repl、`.context` 等 Context 列表 renderer 消费 | INI-only；`ListSortBy=created|updated|name` 默认 `updated`，`ListSortDirection=ascending|descending` 默认 `descending`；next list render。created/updated 只用 XML canonical `CreatedAt`/`UpdatedAt`：初次 durable 创建固定前者、每次成功 durable mutation 原子推进后者，失败/inspect 不推进；相等以 `LogicalPath` 稳定升序 tie-break，不读取文件系统 ctime/mtime | 缺失/非法 canonical time 显示 compatibility/self-fix，不用文件时间猜；XP/CentOS 的 Unicode/path、同时间戳、稳定顺序 fixture。排序仅投影列表，不改变 Resolver、搜索优先级或裸启动不扫描历史 | D-047 已确认字段族，`D+T` |
| effective compaction reserve（非配置字段） | 三条 AL06-11 路线的 fit/view calculator 消费 | Runtime 按有效 Model、输出、Prompt、tool schema、不可拆组和估算误差实时计算；只读且随 view 变化；不等于 trigger | status/request-view manifest 显示派生值、输入摘要与算法版本；跨 Model/超大原子组 fixture | 当前无 `CompactReserveTokens`；算法保证与证明为 `J/T` |
| XML session preference allowlist | M05-06 的 Context-scoped consumers | A 无额外项；B/C 共享条件 turn budgets 与 AL06-11 A/B threshold override；C 再有 `MaxQueuedMessagesOverride`、`MaxSideRequestsOverride`、`DiagnosticDetailOverride=inherit|minimal`，并只在 TU-29 B/C 时生成 `ToolPreviewKiBOverride`；全部只能收紧 | config-repl/context status 显示 INI/Runtime/XML/effective；导入拒绝 unknown/orphan/放宽值；TU-29 A 没有 live-preview consumer，字段必须不存在 | 条件 XML 项，M05-06/TU-29 各自拥有存在条件，`O+T` |
| endpoint disclosure consent（非 INI/override） | action-review、termination-review、model compaction 跨 endpoint request admission 消费 | AL06-51 A 每 request fresh confirm，无 reusable state；B 每 active Context handle + purpose + binding 首次确认，reuse 只在内存；C 才把同样按 purpose 分离的 `EndpointDisclosureConsent` session state 写入 XML。三路每次实际发送都保存 exact event/view range、data classes、endpoint/Model identity 与 request receipt | C 的本机恢复只在 binding 未变时复用；foreign/imported XML、workspace rebind、目标机 remap 一律 audit-only/fresh confirm。main/target endpoint、tenant/auth policy、proxy route、相关 Model/config generation、purpose、data-class envelope、mapping/import generation 或所选 Model 变化使 consent stale；一个 purpose 永不授权另一个 | 条件 XML session state，AL06-51 唯一 owner；不是 M05-06 override，也不新增 INI key，`O+T` |
| quota / auto purge | CX-11 storage admission/maintenance 独占 | A 无字段；B 才有 `MaxContextMiB/MaxActiveContexts/MaxContextTotalMiB` 且只能低于 Runtime hard cap；C 才有 `AutoPurgeTrash` + true 时 required `TrashGraceDays` | context browser/self-test 显示来源；C 只对 durable trash、stable scan、预告清单生效；Win32 x86/慢盘/时钟测试 | 条件字段族，CX-11 唯一 owner；B/C 互斥，`O+T` |
| resolver scan hard cap（非配置字段） | Context resolver 消费 | per operation；发行 manifest/Runtime 不可放宽；超限必须返回 incomplete/ScanLimit，不能返回 not found | context-repl/status/self-test 只读显示 cap 与 manifest identity；大目录、junction、不可读目录校准 | 当前无 `MaxScanEntries`；数值冻结与失败退路为 `J/T` |

不要加入 `RootDir`、`AutoSave`、`RepairOnOpen`、通用 `RetentionDelete`、`ExportSecrets` 或“WAL 开关”；CX-11 C 的 auto purge 是严格限于 trash 的条件例外：

- data root 必须在读 INI 前定位；
- durable commit 和损坏 fail-stop 是正确性不变量；
- 删除/导出是显式危险动作；
- XML/WAL 方案由存储架构决定，不能让每个用户配置出一种事实源。

### 6. `Permission.*`

| 字段族 | 必要性与消费者 | 完整契约检查 | 迁移、UI/self-test 与旧平台风险 | 结论 |
| --- | --- | --- | --- | --- |
| section suffix / `Abbreviation` | permission selector、CLI/REPL 消费 | section suffix 始终是完整逻辑名；它是非空 well-formed UTF-8 user data，禁 NUL/CR/LF、ASCII control、`[`/`]` 与首尾 ASCII whitespace，内部空格/点/连字符/下划线/非控制 Unicode 保留，byte cap 与 round-trip 由 TP-019 冻结。M05-57 A 完全没有简称，B 允许显式 optional 简称，C 要求每个 Permission 有简称。B/C 的长名与简称在 Permission 自己的共享 namespace 内只做 ASCII `A-Z` fold 后唯一，简称不能等于自身长名；Model namespace 独立；输入简称先解析为完整名，XML 当前选择只写完整名 | A 下旧简称给 unknown/deprecated 迁移；B 不自动生成，C 缺失阻止发布；REPL rename/alias change 分别报告 Context stale reference 与仅入口变化；filesystem/locale/Unicode normalization 不参与比较；两平台使用同一 TP-019 vectors | 条件字段，M05-57 唯一 owner，`O+T` |
| `Description` | 只供 UI/Stage 3 advisory | UTF-8 user-content、有界；不得决定权限 | Stage 3 可指出名称/描述不匹配但不能修改 policy | 可保留，`D` |
| `SystemPrompt` | Prompt assembler 的 Permission 层消费；用于描述该 Permission 的行为倾向 | 有界 UTF-8 多行文本，grammar 与 `General.SystemPrompt` 一致；INI definition only；next-turn；按 PP-03 确定的 Prompt 层级组装 | XML 只保存当次 component/digest、profile transition 和必要的非秘密定义快照，不覆盖定义；REPL 必须将 Prompt 文字与 capability matrix 分栏显示 | 已确认字段；它永远不授予、扩大或绕过任何 capability |
| `Color` | 只供 TUI label 投影 | M05-21 B 才允许 Permission Color；A/C 不存在。固定 8/16 色 enum、缺失可确定性分配，颜色不进授权 | 无色仍有文字；语义角色/后备只由 TU-02；旧控制台测试 | 字段存在性 M05-21；颜色语义 TU-02 |
| direct read/write/delete | direct tool permission evaluator 消费 | `deny|confirm|allow`；缺失硬错误；tool-to-capability 表版本化 | Allow/Confirm 对迁；审批显示精确 action；链接/外部路径测试 | 保留，矩阵默认 `O` |
| `Shell` | raw shell 唯一宽权限消费者 | `deny|confirm|allow`；允许意味着可能读/写/删/联网/越界/启动子程序 | 旧 AllowWrite/Delete/Network 不能推导 Shell；迁移必须显式问；UI 显著写 broad | 保留，`O` |
| `OutsideWorkspace` 或拆分的 `OutsideRead/Write/Delete` | direct tools 的外部路径 modifier | M05-16 A 使用一个粗字段，B 使用三字段；都与基本 Read/Write/Delete 取更严格且不约束 raw shell | path canonicalization/junction/symlink 技术测试；未选字段必须从 schema/help 消失 | M05-16 唯一 owner，`O+T` |
| `SensitiveRead` | **仅 M05-56 B** 存在；依赖不完备 classifier | 字段只定义三态策略；TS-21 决定分类来源，命中后与 Read 取更严格结果，未命中不能叫安全；不受 outside 粗/细路线影响 | UI 显示分类原因/版本；大量 false-positive/negative fixture | 字段存在性 M05-56；classifier/policy TS-21，`O+T` |
| `DirectNetwork` | 只有 TS-11 B/C 选择 direct HTTP tool 时有消费者 | 不约束 Model provider HTTP，也不约束 raw shell；不再由 M05-16 额外开关 | TS-11 A 时从 schema/help/template 删除；不能保留永远 deny 的空壳字段 | TS-11 条件字段，`D` |
| regex filters | 不能可靠分类复合 shell 副作用 | 最多作为附加 deny/warn，绝不能授予 | 旧 AllowRegex/ExcludeRegex 不应直接迁为安全保证 | 推荐删除，`O` 若仅保留 deny |

`Cautious` 不是 profile，`DoubleCheck` 不属于 Permission；这是 `C`。发行模板首项为 `Std` 且必须包含 `Readonly` 已确认；是否再提供 `Trusted`，以及各内置 profile（包括 `Readonly`）的精确 Shell policy，由 TS-04 唯一决定。profile 名称和 Description 永远不能改变真实 policy。

### 7. `Model.*`

一个 `Model.*` 是完整连接实例，这是 `C`。下面每组都由 Model registry 保存，但由不同消费者使用，不能因为放在同一 section 就让一个模块读取全部秘密。

| 字段族 | 必要性与消费者 | 完整契约检查 | 迁移、UI/self-test 与旧平台风险 | 结论 |
| --- | --- | --- | --- | --- |
| `Enabled` | selector/startup validator | bool required；disabled 完整度由 M05-08 精确分支：A 至少 Protocol，B 除 Key 外与 enabled 同样完整，C 与 enabled 同样完整但跳过在线测试；任何已出现字段仍校验。没有任何有效 enabled Model，或物理第一项 Model 无效时，不得发布 Agent 可用 ConfigGeneration | 普通 Agent/chat 拒绝启动；bootstrap 读取器仍允许 help/version、config/model REPL、context-repl 的独立 CRUD 和 self-test Stage 1，且不发送 Model 请求。model-repl 显示未发布 repair draft 与缺失项 | 保留，disabled 完整度 `O`；无 Model 不是第二种“有效运行配置” |
| logical name / `Abbreviation` | selector、history mapping | section suffix 始终是完整逻辑名，并服从与 Permission 相同的 well-formed UTF-8/禁用字符/首尾 whitespace/TP-019 byte cap 与 round-trip grammar。M05-57 A 完全没有简称，B 对所有 Model 都是显式 optional，C 只要求 enabled Model 有简称、disabled draft 可暂缺但启用前必须补齐。B/C 的长名与简称在 Model 自己的共享 namespace 内只做 ASCII `A-Z` fold 后唯一，简称不能等于自身长名；Permission namespace 独立；XML 当前选择只写完整名，历史可保存当时简称说明 | A 下旧简称给 unknown/deprecated 迁移；B 不自动生成，C 的 enable 事务先校验；rename 显示受影响 Context，alias change 不改永久 identity；不同 locale/filesystem 结果一致 | 条件字段，M05-57 唯一 owner；M05-08 不再决定简称 requiredness，`O+T` |
| `Description` / `Color` | UI/advisory only | 有界用户文本；M05-21 B/C 才有 Model Color；颜色不是能力 | Stage 3 advisory；无颜色/语义后备由 TU-02 | Description 可保留；Color 存在性 M05-21 |
| `CustomPrompt` | 只有 PP-11 B/C 有消费者 | B 为 Model-specific 用户默认：PP-03 A/B 下位于 adopted rules 与 SystemPrompt 之间，PP-03 C 下加入持久冲突集合；C 为低于其他持久层的 compatibility hint；均有界、INI only、next-turn、完整 component snapshot，且低于当前明确用户要求和 Runtime；A 下字段不存在 | model/config-repl 显示 route/authority；Model switch 写 transition；C 不能替换 serializer/role/tool/control/purpose/权限；A 的旧文本逐来源选择明确目标、先写目标后清源并可恢复 partial outcome | 条件字段，PP-11 唯一 owner；A 推荐删除但不猜目标、不静默合并或丢内容 |
| `Protocol` | protocol adapter | 稳定 enum；enabled required；不从 URL/名称探测 | `Style` 迁移；Stage 1 enum，Stage 2 wire check | 保留，v0.1 enum 范围 `O+T` |
| `Endpoint` | network destination | 完整绝对 URL还是 base URL；scheme/host/port/path/query/userinfo；conditional sensitive；跨 endpoint 预检 | `Url` 迁移需确认语义；REPL sanitized；HTTP/redirect/DNS/proxy/TLS 测试 | 保留，精确语义 `O+T` |
| `RemoteModel` | request encoder | 有界 provider ID；不能从 section 名推断；conditional metadata | `Name` 迁移；Stage 2 回显观察值若协议提供 | 保留，`D` |
| `AuthMode` / `Key` | auth compiler only | AuthMode 的存在/枚举由 M05-02 决定；Key 是 registered config secret、INI only，不进入 XML/argv/diagnostic 的结构化 carrier；HTTP 明文策略联动；文件权限规范化为 protected/weak/unverifiable，ACL admission 只由 M05-54；低于安全扫描门槛时 exact consumer/scanner 保证另由 M05-59 A/B/C 决定，不能用 ACL 路线代替 | Key keep/replace/clear；ACL/echo/canary；旧空 Key 不能自动读 env；分别覆盖 M05-54 的权限路线与 M05-59 的门槛前后/普通正文路线，两轴独立组合 | Key 保留；AuthMode、M05-54、M05-59 为独立 `O`，秘密 carrier/权限与 scanner 证明为 `T` |
| `ContextLength` / `MaxOutputTokens` | budget/compaction/request encoder | optional positive token count；unknown/provider-default 的规范拼写；output < context | 旧数字迁；model-repl 显示 declared/observed；跨模型窗口测试 | 保留，`O+T` |
| price snapshot metadata/rates | **仅 M05-50 C** 的本地 estimate engine 消费 | `PriceCurrency/PriceAsOf/PriceSourceLabel` 加 input/output 与 adapter 明确支持的 cache/reasoning decimal rate；单位、rounding、generation、stale 规则完整；不联网抓价、不从名称猜 | model-repl 显示来源/过期/缺项；每 request/usage event 冻结 generation；reported/estimated 永远分栏 | 条件字段族，M05-50 唯一 owner，`O+T` |
| `EstimatedCostWarning` / `MaxEstimatedCost` | 仅 M05-50 C 且分别由 AL06-43 B/C 的 admission controller 消费 | 同币种、per-turn；B 跨阈值形成 exact-bound consent，且已配置 warning 但无法保守估算时也必须以 `estimate unavailable` fresh consent；C 无法估算时 fail-closed；A 两者均无；不能同时存在 | config-repl/status 显示阈值、累计、worst-case/unavailable 原因；price/usage stale 的 B/C 结果不同且必须测试 | 条件字段，AL06-43 唯一 owner，`O+T` |
| `Streaming` / `Tools` | request adapter/Agent eligibility | Streaming fallback 由 M05-25；M05-03 A/C 有条件 enum，且只有真实 `Tools=off` 时才由 M05-26 决定无工具 main 资格；B 完全没有 Tools 字段、Protocol adapter 静态必须 native、M05-26 强制 not-applicable。任何路线的 observation 都不改写权威，B 也不把在线测试变启用 gate | 旧模板新增；Stage 1 校验 manifest/字段/资格分支，拒绝 B 下的 orphan Tools 或 no-tool-main；Stage 2 只观察且不执行 tool | Streaming fallback/Tools 精确范围及 `MODEL-16` 资格 `O+T` |
| `PublicReasoning` | **仅 M05-40 C** 的 protocol adapter/request projection 消费 | off/summary/full-public 且受 adapter capability；A 无字段并只消费公开 summary，B 完全不消费 | XML 记录公开 kind/来源；hidden reasoning 永不请求/伪造 | 条件字段，M05-40 唯一 owner |
| deadline 字段族 | network deadline compiler | M05-04 A 为 connect/first/idle/total，B 为前三项 + MaxLogicalElapsed，C 为单 RequestDeadline + 内部硬门；所有路线明确 logical/attempt/turn 归属 | 旧单 `TimeoutMs` 无损迁移不可能；REPL 提候选后确认；慢流/半连接测试 | M05-04 唯一 owner，条件字段集 `O+T` |
| retry config surface | request retry controller | M05-58 A 只生成 required `RetryCount+RetryBaseDelayMs`，exponent/jitter/max 来自 versioned manifest；B 再 required `RetryMaxDelayMs`，jitter 仍由 manifest；C 只生成 required `RetryPolicy=none|standard|patient` 并按版本化表完整展开。三路互斥、受技术 hard range，均只对下一 logical request 生效；unknown outcome、收到 canonical event、协议/auth/普通 4xx/内容拒绝/cancel 不重放，也不能调用 curl 自带 retry | 全局旧字段逐 Model 显示迁移候选；A/B 数字不能猜 C preset，C preset 也不能倒推任意旧数字；UI 显示 route/effective count/base/max/jitter/manifest 与实际 attempt；429/5xx/断流 fixture 冻结精确范围/default | 条件字段族，M05-58 唯一 owner，`O+T` |
| generation options | protocol adapter | M05-05 A 用 adapter typed whitelist；B 用核心 generation intent 且 adapter 必须证明映射或拒绝；M05-01 选定 Protocol 后，发行 artifact 必须在编码前列齐 exact name/type/missing/wire/conflict/secret/fixture，未登记项为 unknown | model-repl Advanced 只能列当前 registry；Stage 1 adapter/version parity | `MaxOutputTokens` 保留；条件字段族由 M05-05，registry 不是开放扩展口 |
| `PublicHeader` / `SecretHeader` | 只有 M05-23 B/C 的 auth/network compiler 消费 | B 允许 public+secret，C 只允许 public，A 两者都没有；SecretHeader 是 config secret，weak/unverifiable config 时其 consumer 服从 M05-54；重复/顺序 grammar 与 reserved header 禁止覆盖 | redacted diff；canary；旧端点 gateway fixture；未选字段为 unknown/deprecated | 条件字段，M05-23 唯一 owner，权限 admission 为 M05-54，`O+T` |
| `AdapterOption.<Name>` | protocol adapter | 只允许所选 Protocol 发行 artifact 的 exact typed registry；编码前冻结 wire mapping，不能覆盖 messages/model/tools/stream/auth/limits | Advanced UI 只投影已登记字段；Stage 1 offline parity/golden validation | 条件 family；generic/open-ended `ExtraParameter` 删除，`D` |

#### per-Model rate/cooldown 题源已提升到 F4-02（非投票）

M05-58 所选 retry 配置面——A 的 count/base、B 的 count/base/max 或 C 的 typed preset——只回答“一个 logical request 失败后是否重试”，不能回答：

- 正常请求是否要主动限速；
- main、side、DoubleCheck、compaction 是否共享同一 Model 配额；
- 收到 `Retry-After` 后，同一进程后续新 logical request 是否等待；
- 连续 429/5xx 是否开启 circuit breaker/cooldown；
- 两个 yaca 进程使用同一个 Key 时是否声称共享账户级配额。

本节早期曾列 A/B/C，但它们已经 superseded，不再是负责人回复入口。唯一正式选择是决策包 11 的 F4-02：它决定只使用固定单请求 scheduler，还是公开 `MaxConcurrentRequests/MinRequestIntervalMs`；跨进程账户 broker 不在当前简单数据面内。无论 F4-02 选择哪项，六个核心 purpose 与 `AutoNameEveryMainTurns>0` 条件产生的 `context-name` 之 admission、`Retry-After`、cooldown、取消和当前进程边界都必须写入同一 scheduler artifact。字段存在性以 F4-02 为准，不能再回答本节旧方案。

### 8. 旧 `Tui` 与新 `TUI` section

当前模板只有：

- `CheckModelOnStart=true`：不再作为布尔联网开关，必须删除；不自动迁移为同意，新启动 gate 由 `General.StartupSelfTest=off|stage1|stage2|stage3` 精确表达。
- `CheckModelPerformanceOnStart=false`：同上；必须删除。
- `DotCommandCompletion=true`：旧控制台不一定能可靠提供 Tab/raw input；点命令本身必须始终可输入，补全只是 renderer 自动能力；推荐不配置。

因此旧 `Tui` section 的三个字段全部删除。新 `[TUI]` 始终存在，只含 Slogan/Version/WorkDir/DataRoot/Context/ContextHash/Model/Permission/DoubleCheck/ConfigStatus/StatusHint 的逐字段 bool；没有 `StartupHeader` 或其他 master。DataRoot 默认 false，其余默认 true，Slogan 和 chat `>>` 文本不可配置。只有 TU-27 B/C 才额外生成 `NotificationChannel`，只有 TU-30 C 再生成 `NotificationEvents`。固定快捷键、基本颜色、无鼠标、无 theme/vivid/mode、自适应降级仍是产品/TUI 契约。

### 9. 明确不新增的 section/字段

| 不新增 | 理由 |
| --- | --- |
| `UseTerminationEvaluator` | 已由 D-027 合并进 `DoubleCheck` |
| `Permission.Cautious` / profile `DoubleCheck` | 已由 D-021 否定 |
| `DefaultModel` / `DefaultPermission` ID | 已确认物理第一项决定默认；需要完善重排/无效首项，不建立第二真相 |
| `Provider` / `Credential` / secrets 文件引用 | 已确认一个 Model 完整实例、Key 明文 INI |
| per-Model proxy | 用户已要求 proxy 全局 |
| `FallbackModel` | 失败时不静默改变 endpoint、费用、隐私和行为 |
| `Model.CustomPrompt` | 不是无条件排除：PP-11 A 才删除并迁移到 SystemPrompt/ContextPrompt；B/C 按条件 typed 字段保留 |
| arbitrary `ShellProgram` path | 永不提供；TS-13 C 若被选择，只出现发行 allowlist 驱动的 typed `ShellDialect`，不能借路径绕过 quoting/cancel/security 证明 |
| `AutoSave` / `RepairOnOpen` | 正确性和恢复不变量不可关闭 |
| data root | 必须在加载 INI 前定位，放进 INI 会形成 bootstrap 循环 |
| `Theme` / `Vivid` / generic `Mode` / `Language` / keybinding | 已要求保持一个简单 TUI；TS-18 B 的窄 `Autonomy` 是独立条件字段，不复活 generic Mode；终端能力自动降级 |
| `Update` / `Telemetry` / `Web` / `MCP` / `Plugin` / `Hook` | 当前产品范围不需要，也没有消费者 |
| `Sandbox` | 项目已明确不承诺 OS sandbox；Permission 只能表达策略 |
| generic curl flags / arbitrary JSON body | 会绕过 Runtime 生成的 auth/messages/tools/limits |
| generic `MaxCost` | 不建立含糊别名；M05-50 C 才生成逐 Model versioned price snapshot，AL06-43 B/C 才分别生成 `EstimatedCostWarning` 或 `MaxEstimatedCost` |
| self-test pass/fail 缓存 | 在线观察不是永久配置权威；报告属于诊断事实 |
| config watch/reload interval 或 reload policy | D-048 固定每个顶层 main/side turn admission 前读取完整 bytes/digest；不需要 watcher、轮询间隔、restart-only 或人工确认开关 |

## 运行中外部配置 generation：F4-01 已按 D-048 收口

`next-turn` 不再只是一句字段注释。D-048 已确认：每个顶层 main 或 side turn admission 前，Runtime 都完整读取 INI bytes 并计算 private source digest。digest 未变就复用 immutable ConfigGeneration；发生变化就全量 parse、逐字段与跨字段验证，成功后自动原子激活一个完整 generation，失败则阻止该新 turn 并指向对应 self-fix。

不建立 watcher、reload interval、restart-only policy、人工 reload gate 或对应配置字段；也不以 mtime/size 代替当次完整 bytes/digest 读取。active turn 以及它派生的 child tool、review、retry 和已经开始的 HTTP/process activity 全部冻结创建时 snapshot，不因下一顶层 turn 观察到变化而热换。

还必须冻结：

1. active turn 永远继续使用创建时 snapshot；外部变更不撤销已批准/已开始动作，child activity 也不重新观察 INI。
2. `LogLevel` 即使定义为 display-immediate，也只能在成功载入新 generation 后生效。
3. turn admission 发现新配置无效、删除或半写时不能静默继续执行 last-known-good；可以用旧 generation 展示来源并让已经 active 的 turn 收口，但该新 turn fail-closed。
4. Model/Permission 被删除或重命名时，当前 Context 先只读，走显式 mapping/switch；不自动选第一项。
5. endpoint、SystemPrompt、Permission、DoubleCheck、条件 ExecProfile/ExecEnvironment 或 registered secret 发生有效变化时，下一个相关 request/exec 前生成 non-secret transition；secret value 与 private fingerprint 本身不写 XML。
6. 只改注释是否产生 generation：推荐 private digest 变化但规范 effective digest 不变，不显示行为 transition；REPL 仍需避免覆盖注释改动。
7. REPL 和 chat 同进程共享一个 config service；不能各自缓存一份 table。config-repl/model-repl 只在发布临界区取得短期 writer lock，携带 expected source digest，写同目录 temp、flush/revalidate 并原子替换；外部 digest 变化时拒绝覆盖而不是 merge 猜测。
8. AL06-50 的 no-progress 阈值在 turn 创建时冻结：A 保存 manifest identity + tuple，B 保存 effective scalar/source + detector version，C 保存完整 detector map/source + registry version；编辑不热换也不重置 detector state，unfinished turn 恢复原 snapshot。
9. AL06-51 的 consent 不追溯改变已经发送的 request；每次实际发送都保存 disclosure receipt。只有 C 可保存 reusable per-purpose XML state，且 binding 变化立即 stale；foreign/imported XML、workspace rebind 或目标机 remap 只提供 audit evidence，不能直接授权下一次发送。
10. M05-57 B/C 的简称只在用户输入 admission 时解析为完整 logical name；当次动作和 XML 当前引用随后都绑定完整名。修改简称不重命名资源、不重写历史，M05-57 A 不保存不存在的 alias snapshot。
11. 每个 logical request 在创建时冻结 M05-58 的 route、effective count/base/max/jitter 和 manifest identity；配置编辑只影响下一 logical request，恢复不能只保存一个会随发行升级变义的裸 preset。
12. M05-59 的 scan threshold、pattern set 与 matcher manifest 随实际 consumer/publication generation 冻结；A 的过短 secret consumer ineligible，B 的收缩保证必须可见，C 不得因命中频繁而临时跳过扫描。

F4-01 不再是待回复项。文件身份、case-only replace、mtime 粒度、同大小快速改写、网络盘/FAT、Win32 share mode、短期锁与原子替换失败仍需技术证明。

## 旧模板必须删除、迁移或改写的内容

### 必须删除

| 旧内容 | 原因 | 新位置/行为 |
| --- | --- | --- |
| `Network.UseStunnel` | 发行资源没有 stunnel，也没有已确认架构 | 删除并报明确 deprecated diagnostic |
| `Permission.Cautious` 的特殊内置语义 | D-021 已确认不是 Permission mode | 可作为普通用户自定义名保留，但不自动启用复核；默认模板删除 |
| `Permission.*.DoubleCheck` | 总开关已移到 Agent + XML override | 迁移时聚合冲突并让用户选择 `Agent.DoubleCheck` |
| `Tui.CheckModelOnStart` | 旧 bool 无法表达阶段、同意和 partial gate | 删除；`General.StartupSelfTest` 默认 `off`，由用户显式选择 stage1/2/3，旧 true 不自动充当网络/费用同意 |
| `Tui.CheckModelPerformanceOnStart` | 同上且会产生费用/延迟 | 显式 Stage 2 测试 |
| `Tui.DotCommandCompletion` | 没有稳定用户可调语义，旧终端需自动后备 | renderer capability，不是 schema |
| `TUI.StartupHeader` 或其他启动信息 master | 项目负责人明确不需要总开关；它没有领域消费者 | 按 unknown/unregistered 拒绝；若迁移器识别某个历史草案，只能给迁移诊断，不能让它生效或从 master 批量改写逐个 `StartupShow*` bool |
| `Model.CustomPrompt` | PP-11 A 时逐来源迁往明确选择的 SystemPrompt/指定 ContextPrompt 或 discard；B/C 时迁到各自 typed 语义 | 多源同目标先形成可编辑 merge draft；先验证目标再清旧源，partial outcome 可恢复；始终展示文本/authority/Model 范围，绝不猜当前 Context、静默拼接/丢弃或把旧文本提升为协议权威 |
| `AllowRegex` 作为授予依据 | 无法证明 raw shell 副作用 | 删除；若保留只能额外 deny/warn |
| “exactly four built-ins” | 已不存在 Cautious 固定四预设 | 文档改成最终确认的 profile 模板 |

### 必须迁移

| 旧内容 | 候选目标 | 不能静默处理的地方 |
| --- | --- | --- |
| `Network.FollowProxy` | `ProxyMode=environment|off` | 旧文件无法表达 explicit/no-proxy/CA |
| `Network.MaxRetry` / `RetryDelayMs` | M05-58 A/B 的每 `Model.*` 数字字段，或 C 的 typed `RetryPolicy` | 多 Model 逐项显示，不能自动影响未来 Model；A/B 保留精确数字候选，C 必须显示 preset 展开并由用户选择，不能按“最接近”静默猜测或混用三路线字段 |
| `Exec.TimeoutMs=false` | M05-51 A/C 的 `MaxExecTimeMs` 正整数，或 B 的 manifest default | `false=无限` 不能越过 Runtime hard cap；迁移时显示实际毫秒值/来源 |
| `Exec.MaxOutputKB` | `MaxOutputKiB` | 单位从含糊 KB 改 KiB；false 不等于真无限 |
| `AllowWrite/AllowDelete/AllowNetwork` + `ConfirmWrite/ConfirmDelete/ConfirmNetwork` | per-capability `deny|confirm|allow` | raw `Shell` 无法从 Write/Delete/Network 组合可靠推导 |
| `Model.Style` | `Protocol` | 只迁到发行物支持的稳定 enum |
| `Model.Name` | `RemoteModel` | 避免与 section logical name 混淆 |
| `Model.Url` | `Endpoint` | 必须先决定完整 URL/base URL，再验证 path |
| `Model.MaxTokens` | `MaxOutputTokens` | 明确它是请求输出上限，不是上下文总长或 turn 总 token |
| `Model.TimeoutMs` | connect/first/idle/total | 一个数字无法无损变成四个 deadline，需用户确认候选 |
| `Context.CompactThreshold=false` | 明确 `auto/off` 语法是否允许 | 自动压缩能否关闭是产品决定，不沿用混合类型 |
| 预写五个 Disabled Model | model-repl quick presets | 最终 INI 不应带大量空 credential/endpoint 假配置 |

### 可保留拼写、但必须进入新 schema 重新验证

| 旧内容 | 新验证责任 |
| --- | --- |
| `Permission.*.Description` / `Color` | Description 只作有界用户文本；Permission Color 只有 M05-21 B 保留，否则迁移时忽略并提示，语义色不由此字段决定 |
| `Context.AutoJumpToDir` / `ResumeDirectory` / `AutoNameOnExit` | 前两项删除并给 deprecated diagnostic：current root 由 XML 的镜像父目录决定，不迁移为 jump/keep 开关；显式 rebind 由 context-repl 移动 XML。`AutoNameOnExit` 也删除；周期命名由 `AutoNameEveryMainTurns` 控制，手工名称保护由 XML `AutoRenameDisabled` 控制，旧 true/false 不自动猜成任一新值 |
| `Model.*.Enabled` | disabled 仍需名称/类型合法；第一项 disabled 的普通启动语义由负责人确认 |
| `Model.*.Description` / `Color` | 只作 UI/advisory，不推断厂商、能力或安全；Model Color 只有 M05-21 B/C 保留，语义色由 TU-02 |
| `Model.*.Key` | 继续明文 INI，但进入统一 secret 元数据、keep/replace/clear、M05-54 ACL admission 和 M05-59 门槛前后 consumer/scanner 测试；两条路线不能互相替代 |
| `Model.*.ContextLength` | 仍是 declared token window，必须允许明确 unknown 并与 Prompt/output reserve 交叉验证 |

旧 Permission 没有 `Read`、`Shell`、`OutsideWorkspace`，也不能从 `AllowWrite/AllowDelete/AllowNetwork` 安全推导这些新能力。迁移器必须从负责人确认的安全 profile 模板生成候选并显示完整矩阵；尤其不能把旧 `AllowNetwork=true` 自动解释为 raw shell 已获准执行任意命令。

### 文件头与公开文档必须同步改写

- 模板写“不要手工编辑、用 `yaca /cc`”，README 又写可以手工编辑并推荐 `--interactive-config-changer`；必须选择正式手工编辑契约并统一为规范命令。
- 模板写 `yaca /d` 修复，但公开命令没有唯一对应；bootstrap config-repl/self-test/reset 的责任必须冻结。
- README 的 `--set-default-model` / `--set-default-permission` 与“物理第一项就是默认”重复；推荐由 REPL `first/move-*` 实现并移除第二语义。
- README 当前说历史 Model/Permission 无效时 fallback 第一项，与 AQ-236 推荐的只读 mapping 冲突；不能把新 Context 默认当历史隐私授权。
- `GeneratedAt` / `UpdatedAt` 注释不能代替 schema/version/generation；若仅装饰则删除，若保留必须明确不参与语义。

## 候选 schema 的真实缺项

下列是“需要补完整契约”，不等于每项都应新增 INI key：

| 缺项 | 最合适的落点 | 类型 |
| --- | --- | --- |
| HTTP 明文、Key/secret header 与 scheme downgrade 策略 | Model/Network 跨字段规则 + REPL 预检 | `O+T` |
| per-Model scheduler、Retry-After、cooldown、跨 purpose 共享 | Model request scheduler；是否有字段由负责人选 | `O+T` |
| 逐顶层 turn 外部 INI observation/fail-close | D-048 config-generation 生命周期；不生成开关 | `D+T`，只剩目标平台证明 |
| 内部 curl/Git/helper 与宿主配置隔离 | process/network adapter 固定不变量 | `D+T` |
| private source digest 与 public effective digest 分离 | config service + XML snapshot | `D+T` |
| compressed/decompressed/error/total response hard limits | Runtime limits registry | `D+T` |
| 环境代理变量的精确 allowlist、读取时点和 snapshot | Network policy compiler | `O+T` |
| `LogLevel` 在“只有 INI/XML”下各级实际目的地 | Diagnostics contract | `O` |
| non-secret config reset 的字段范围 | config-repl/CLI transaction；M05-18 | `O+T` |
| 含任一 registered config-file secret 的 backup/export 是否存在 | 独立 config export/backup transaction；eligible set 由 registry 生成；M05-42 | `O+T` |
| generic CLI one-shot override 是否存在 | CLI/config source contract | `O`；推荐不存在 |
| 每个字段的唯一 owner/consumer 与 stable field ID | typed schema metadata | `D` |
| optional scalar 的唯一拼写 | INI grammar | `O` |
| list/map collection 的重复 key、顺序、空集合、tuple delimiter 与总量 grammar | INI parser/writer 的统一 collection profile；不能让各 consumer 自解逗号字符串 | `D+T` |
| exact XML override whitelist 与 imported downgrade | XML/config merge contract | `O+T` |
| M05-51 C 的 ExecProfile section、默认、selector、条件 show/use/reset、rename/delete 与 stale mapping | `[ExecProfile.<Name>]` + 条件 `CurrentExecProfile`；定义与选择分离；reset 持久当前第一项精确名，不动态跟随 reorder | `O+T` |
| M05-15 A/B 的 raw-shell inherit baseline 暴露哪些 ambient 环境 | M05-55 的发行版 compatibility allowlist、完整宿主继承或高置信 denylist；每次 admission/spawn 冻结 exact environment generation，内部 helper 始终隔离 | `O+T` |
| 含任一 `source=config-file` secret 的承载文件权限为 weak/unverifiable 时的 consumer admission | M05-54 的 process consent/warning/exact-consumer-disabled policy + 每次 use 前权限 observation credential；ambient/user/runtime secret 不借用 config.ini ACL；内容发布失败与 ACL 分类分开 | `O+T` |
| no-progress threshold 的条件配置面、branch exclusivity 与 turn/recovery snapshot | AL06-50：manifest tuple、单一 bounded INI scalar 或 versioned small detector map；永不 XML override | `O+T` |
| 跨 endpoint 特殊 purpose 的 consent cadence、purpose 隔离与失效 | AL06-51：A/B 只写 request receipt，C 才有 reusable XML session state；不新增 INI key | `O+T` |
| Model/Permission 是只用完整名、optional 简称还是可用资源 required 简称，以及 collision/fold/XML identity | M05-57：条件 `Abbreviation` schema + selector/REPL/rename/import snapshot；Model 与 Permission namespace 分离 | `O+T` |
| per-Model retry 是 count+base、count+base+max 还是 versioned preset，以及字段互斥/range/request snapshot | M05-58：Model request retry controller + migration/UI/fixture；scheduler/cooldown 仍独立归 F4-02 | `O+T` |
| 低于安全扫描门槛的 config-secret 是否禁用 consumer、收缩普通正文保证或继续全局 exact scan | M05-59：secret consumer admission + canonical publication scanner；门槛/重复/重叠/cross-chunk matcher 由 fixture/manifest 证明 | `O+T` |
| endpoint/hostname/Description 等 conditional data 是否进入 XML/self-test reviewer | data-classification matrix | `O` |
| capability observation 的内存缓存失效规则 | Model registry/runtime observation | `O+T` |

## 不应为了“看起来完整”而增加的字段

1. 不暴露所有 Runtime hard limit。用户能理解并有合法调节场景的上限才进入 INI；其余在版本化 limits manifest 中有名字、有测试、有错误即可。
2. 不把 every purpose 做成独立 Model。默认 current Model、无工具和最小可见性由 request purpose 固定；只有负责人明确选择专用 selector 时才生成。action-review 与 termination-review 已分别由 AL06-08/49 拥有，不能再用一个共用 reviewer selector 把两种 endpoint、费用或隐私决定捆绑；compactor 仍由 AL06-30 独立拥有。
3. 不为 quick preset 添加永久 provider 品牌字段。preset 只生成一个完整 Model section，之后 Runtime 只认 Protocol/Endpoint/RemoteModel/能力。
4. 不把 self-test observation 写回 `Streaming`、`Tools`、ContextLength 或 Enabled；配置是授权，观察是诊断。
5. 不建立 `[Storage]` 来开关 save/repair/WAL，也不建立 `[Security]` 来声称 sandbox。
6. 不为 curl、Git、patch、diff 建立用户可替换工具路径。内部依赖由发行 manifest/绝对路径控制；模型需要任意宿主工具时走 raw shell。
7. 不配置组合键、mouse、renderer mode、theme、vivid 或 Markdown engine；TUI 自动降级并保持相同 controller actions。
8. 不提供 arbitrary environment/header/body 逃生口。每一个扩展都必须由 adapter schema 命名、类型化、脱敏并禁止覆盖核心。

## 配置浏览器与 Self-Test 的完整责任

### config-repl / model-repl / context-repl

三个 REPL 都是独立顶层管理命令，不经过 chat 页面，也不依赖当前 Model 请求。每个 REPL 都有自己领域的 `self-fix-program` 选单：config-repl 修复 grammar/schema/migration，model-repl 修复 Model 定义/顺序/引用，context-repl 修复 Catalog/XML 结构与外来 mapping。修复必须先扫描、预览 typed plan、确认，再原子发布；不自动修改。没有有效 Model 时它们仍可用 bootstrap reader 运行，但不得生成 Agent 可用 generation 或发送 Model 请求。context-repl 可独立 list/inspect/rename/rebind/delete/import/restore/repair Context，并查看/添加/取消专用 `AutoRenameDisabled`；取消标记不立即命名。“add”只表示导入/恢复已有 XML，不创建空对话。

锁域必须分开：活动 Context 的 writer lock 只阻止另一个进程对该 Context 做 rename/rebind/delete/restore/marker 等 mutation，context-repl 仍可显示 busy metadata；它不阻止 model-repl/config-repl 修改独立 INI。INI writer 只在提交临界区持短锁，保存前重读完整 bytes 并验证 expected private source digest，再以同目录 temp + flush/revalidate + atomic replace 发布；草稿编辑期间不长期占锁。

所有 TUI domain action 都必须从同一 typed action registry 获得等价 CLI projection，包括列表、详情、修改、self-fix、确认与取消；renderer 的方向键/补全等手势只映射这些 action，不另造业务语义。这里的 CLI parity 只覆盖本机命令入口，不发布 remote/headless control surface，也不允许非 TTY 跳过确认或 Permission。

每个字段详情页至少显示：

```text
field id / section.key
meaning and sole consumer
type, unit, valid range
INI value / Context override / effective value
source generation and applies-at boundary
secret classification and XML snapshot rule
default or missing semantics
cross-field errors and warnings
```

保存前必须显示：脱敏 diff、第一 Model/Permission 是否改变、会在何时生效、是否改变 endpoint/HTTP/Key presence/Permission/DoubleCheck、哪些 active Context 将失去引用。M05-57 B/C 下简称编辑必须同时显示完整 identity、namespace collision 和“当前 XML 不会改名”；M05-58 显示所选字段路线及完整 effective 展开，不把混合路线保存为“尽量可用”。Key 只允许 keep/replace/clear，不能 reveal/copy；M05-59 A 的过短值仍可在管理入口替换/清除，但不能启用 exact consumer。两个 REPL 共用一个 draft/validator/publisher；model-repl 不是第二套 parser。

### show-config

不能打印原始 INI。默认输出 effective non-secret projection，明确区分：

- configured value；
- Context override；
- effective value；
- secret `configured|empty`；
- unknown/invalid preserved raw location；
- next-turn/next-request/restart 生效。

机器输出若进入范围，必须有版本化 ASCII 字段，不把彩色 TUI 文案混入 stdout。

### self-test Stage 1

self-test 是单一语义动作，接收 typed run specification：`through_stage=1|2|3`、重复 `excluded_models`、重复 `excluded_checks`、可重复 `selected_checks`；另有不联网的 `list-checks` 发现动作。CLI 的 through-stage/list/exclude/check 长/短名仅是该语义面的投影，本文不冻结 TU-18 的 argv 拼写。任何 run 都从 Stage 1 开始，严格按 1→2→3 执行；前一阶段未通过，后一阶段不可用。排除 required Model/check 会产生 `partial`，不得进入 Stage 3，也不得满足 `StartupSelfTest` 启动 gate；启动 gate 总是全量 required scope。

静态阶段至少验证：

- schema/version、INI grammar、所有字段/跨字段 CV 规则；
- default section 顺序和 enabled/required fields；
- secret 只存在允许位置；INI 文件权限结论规范化为 protected/weak/unverifiable，并验证 M05-54 所选确认/warning/exact-consumer-disabled 路线不会被非 TTY、旧 generation、纯 ACL/mode 改动或静默改路绕过；
- portable root/temp/no-replace/atomic replace/外部修改检测；
- 随包 curl/helper 绝对路径、版本/hash、不会读取宿主 config 的 canary；
- proxy/NoProxy/CA 语法与 bundle；
- HTTP cleartext policy；
- Runtime hard limits 能容纳最小 Prompt/tool schema；
- AL06-50 所选分支的 no-progress 字段族不混用、不越界、不出现在 XML override，manifest/scalar/map snapshot 具有对应 detector/registry version；
- M05-57 所选完整名/简称分支不混用，Model/Permission 各自 namespace 的 ASCII-fold collision、requiredness、rename/alias/XML 完整名 identity 都一致；
- M05-58 所选 retry 字段族不混用、不缺项、不越界，并能生成 route/effective count/base/max/jitter/manifest 的 request snapshot；
- M05-59 所选短 secret 路线与 consumer eligibility、普通正文 publication guarantee 一致；threshold/duplicate/overlap/cross-chunk matcher 数值来自同一 fixture/manifest，而不是可调配置；
- M05-15/M05-55 所选 raw-shell environment baseline 的 manifest、变量名集合、credential/proxy/agent canary 与内部 helper 隔离；不打印变量值；
- XML override whitelist 和 imported downgrade；其中 AL06-51 A/B 不接受 reusable consent，C 的 foreign/imported/rebind/remap consent 也只能作为 audit evidence；
- Context codec/schema/UTF-8 与镜像路径 round-trip；每个 XML 的 parent-derived workspace 存在、可 `cd`、identity 可证明，缺失/移除/无权限或错绑给出 exact context-repl self-fix check ID；
- Context Catalog 的 temp/partial/recovery artifact、损坏/不兼容对象、活动锁与可证明 owner 状态；Stage 1 只诊断，不 force unlock 或自动修 XML；
- Context `CreatedAt`/`UpdatedAt` canonical metadata、`ListSortBy`/`ListSortDirection` enum，以及主键相同时始终升序且不随 direction 反转的 `LogicalPath` tie-break；绝不用文件系统 ctime/mtime 补齐；
- Context Resolver/Catalog 的 scan hard cap、实际 entries/hash 计算量、elapsed/peak-memory 预算和 incomplete/ScanLimit 结果；Context 太多、目录太深或 16 位 hash 计算超出旧机预算时给出明确 warning/error 与 self-fix 入口，不能无界遍历后只说“慢”。

Stage 1 不执行 raw shell、不连接 Model、不把“curl 二进制存在”当 TLS/secret 路径已通过。

### self-test Stage 2/3

- Stage 2 只能在 Stage 1 完整通过后开始；Stage 3 只能在所有 required Stage 2 Model/check 通过且结果非 partial 后开始。每次进入 Stage 2/3 前仍显示网络、费用、将使用的 Model 和外发数据并请求同意；配置中允许这个阶段不等于持久网络同意。
- Stage 2 显示每个 origin、scheme、proxy/bypass、auth/config-secret `configured|not-required` 状态、最大 request/token 和测试项，绝不显示值；测试 protocol/auth/stream/native tool call，但 synthetic tool 永不执行。
- rate/cooldown 若存在，测试请求也必须进入可解释 scheduler；不能为了 self-test 绕过 provider 保护。
- Stage 3 只接收脱敏结构投影。是否把 exact endpoint/internal hostname 发送给 reviewer 要由数据分类决定；判断“DeepSeek 名却是 Mimo”不需要任何 registered config-secret value 或完整 URL，排除集合由 registry 生成。
- Stage 3 必须审阅 Permission 的 logical name、optional Abbreviation、Description、SystemPrompt 与实际 capability matrix 是否语义相称，并检查面向用户的自然语言拼写/明显笔误。例如名为 `Readonly` 却允许写/exec，或宽权限名/说明却配只读矩阵，都应形成带字段定位的 advisory；名字从不决定真实授权。
- Stage 3 永远 advisory，不改写 Enabled、Permission、Prompt、Streaming、Tools、ContextLength 或任何名称，也不覆盖 Stage 1/2 的确定性结果。

## 旧平台专项风险

| 风险 | 配置侧必须保证 | 证明方式 |
| --- | --- | --- |
| Win32 x86 地址空间 | 所有字符串/list/Prompt/header/body/result 有硬界；REPL 不复制多份 Key/大 INI | 大配置、大 Prompt、长 header、外部改写 soak，记录 private bytes |
| XP 文件 API/ACL | config/temp/no-replace/replace/flush/share mode 走宽字符窄适配器；权限结果为 protected/weak/unverifiable，无法证明时按 M05-54 处理，不预设“只警告” | FAT/NTFS、只读、共享打开、磁盘满、杀进程 fixture |
| 时间/mtime 粒度 | reload 不能只看 mtime；使用 identity + bytes digest，turn deadline 用单调时钟 | 同秒同大小改写、clock jump、replace/delete/recreate |
| 旧 console secret input | 星号显示不等于关闭 echo；失败时提示安全手工路径；专用 secret-entry 值不进 yaca recall/completion，普通 chat 未知秘密不作同样承诺 | XP cmd、QuickEdit、重定向 stdin、Ctrl+C |
| curl 行为差异 | 最终随包版本的 `-q`、stdin config、CA、proxy、redirect、SSE、cancel 全部实测 | canary curlrc/netrc/env/argv/temp/trace |
| CA/TLS | 不依赖 XP/CentOS 系统默认；bundle 来源/hash/version 明确 | valid/expired/wrong-host/custom CA/proxy CONNECT/SNI |
| Windows env case | environment set/unset/proxy name折叠规则稳定 | 混合大小写、重复、超长 env block |
| Linux locale/bytes | INI/机器字段 UTF-8/ASCII，用户文本错误定位稳定 | C/POSIX/非 UTF-8 locale、BOM、CRLF/LF |
| 原子更新差异 | 同目录 temp、flush、replace、backup/recovery 不假设 POSIX rename 等于 Windows | 双平台 fault injection |
| host tool drift | internal tool 不从 cwd/PATH/HOME/registry 隐式改变行为 | 恶意同名工具、curlrc、gitconfig、pager/diff/credential helper canary |

## 技术证明清单

这些项目不由负责人“接受推荐”替代：

### CCA-TP-01 INI parser/writer 往返

对注释、顺序、重复、未知字段、UTF-8、BOM、CRLF、转义、多行、空/缺失和超限做 golden bytes；REPL 修改一个字段不能改写不相关文本。Win32 x86 与 CentOS 7 都要跑。

### CCA-TP-02 原子发布与外部写者

证明 digest conflict、same-directory no-replace temp、flush、reparse、replace、失败保留、backup/recovery；覆盖断电/kill、磁盘满、杀软占用、FAT/NTFS 权限和两个 REPL 并发。

### CCA-TP-03 secret 全路径 canary

从 typed registry 为每个 `config-file|ambient-environment|runtime` secret class 生成 canary（至少覆盖 Key、显式/ambient proxy credential、SecretHeader、EnvironmentSet value 和 adapter secret），分别搜索 argv、环境、process list、temp、stderr、yaca recall、XML、public digest、support、backup/export 和 crash residue。对 M05-59 A/B/C 分别覆盖低于、等于和高于 `MinimumScannableSecretBytes`：A 证明过短值只能管理而 exact consumer ineligible；B 证明精确结构化 carrier 不泄漏，同时普通正文 coincidence 保留并显著标记 guarantee-contracted；C 证明任意长度继续阻断/marker。所有需要扫描的 pattern 还要覆盖跨 stdout chunk/head-tail 边界、相同 raw value 的多 source/category、前缀/后缀重叠和 registry/matcher 顺序扰动，证明折叠后的稳定 source set、maximal interval union 与 marker 不含 raw value/长度/private equality fingerprint。任何命中按 source×purpose×destination 契约判断失败；普通用户内容中的未知 secret 不得被虚假计为“已全部识别”。

### CCA-TP-04 curl/CA/proxy 宿主隔离

放置恶意 curlrc/netrc、`CURL_CA_BUNDLE`、proxy env、cwd 同名 CA/tool，证明 internal request 只消费 effective snapshot；再测最终随包 curl 的首参数禁 config、redirect、SSE、取消和错误脱敏。

### CCA-TP-05 HTTP 明文与 origin transition

覆盖 loopback、LAN、DNS 指向 loopback、IPv4/IPv6、proxy、HTTP→HTTPS、HTTPS→HTTP、同/跨 origin redirect、Key/header 转发和 Model switch 预览。

### CCA-TP-06 rate/cooldown scheduler

若选择相关能力，测试所有 request purpose 共享、公平排队、`Retry-After` seconds/date、超大/非法 header、cancel waiting、turn deadline、进程重启和两个独立进程的诚实说明。

### CCA-TP-07 runtime reload

覆盖每个顶层 main/side admission 都读取完整 bytes/digest，active request/tool/review/retry 中改 INI、idle 改注释、改 Key、删当前 Model、降 Permission、损坏/删除/替换文件、mtime/size 不变和两个 REPL 同时保存；断言 digest 未变复用 immutable generation，有效变化自动原子激活，旧 turn/child activity 不变，无效变化阻止新 turn并指向 self-fix。证明没有 watcher/interval/policy 字段，且短期 writer lock + expected digest + atomic replace 不丢外部编辑。

### CCA-TP-08 schema/UI/self-test 单一事实源

对每个 stable field ID 自动核对模板、parser、validator、help、config-repl、model-repl、show-config、redaction、XML whitelist 和 self-test；任何消费者出现 schema 未登记字符串都失败。特别断言不存在 `StartupHeader`/启动 master，逐字段 startup bool 各自生效；Context sort 只消费 XML canonical time/name + LogicalPath，不触碰 Resolver。组合 fixture 必须证明 M05-57 A/B/C 的 `Abbreviation` 条件生成与完整名持久 identity、M05-58 A/B/C 的 retry 字段互斥与 request snapshot 均由同一 schema 元数据投影，不能由 UI/parser 各自写一套分支；同一 typed action registry 还要覆盖所有 TUI domain action 的 CLI projection。

### CCA-TP-09 Runtime limits 与 Win32 x86

对大 Prompt、Model 列表、headers、SSE event、response、tool args、Exec output、Context XML 和 scan entries 做组合压力；证明 unset/auto 仍受 hard cap，不因多个小上限组合越过内存预算。

### CCA-TP-10 migration fixtures

每个历史模板版本至少有一份合法、一份矛盾和一份损坏 fixture；迁移先预览、备份、写新文件、重新验证，无法无损推导的字段必须问用户而不是猜。

### CCA-TP-11 Context self-test 与列表投影

在 XP x86/CentOS 7 以缺失/不可进入 workspace、错镜像、损坏/partial XML、busy lock、大量 Context、深目录、同名/同时间戳和 scan cap 命中做 fixture；证明 Stage 1 有界报告 codec/workspace/Catalog/hash-scan 时间与内存，不 force unlock/自动修复。分别验证 `created|updated|name` × `ascending|descending`，默认 updated-descending，缺 timestamp 不 fallback 到 ctime/mtime；主键相等时 `LogicalPath` tie-break 始终升序、绝不随主方向反转，并且跨平台确定。另证明 `CreatedAt` 初建后不变，`UpdatedAt` 只在成功 durable mutation 中原子推进，rename/rebind 成功推进而失败/inspect 不推进；排序不改变 Resolver 或裸启动。

## 配置完整性门

只有全部门关闭，才能把候选 schema 改名为正式 schema 并开始配置子系统实施计划。

| Gate | 通过条件 |
| --- | --- |
| `CCA-G-01 Decision closure` | 本文负责人问题与 M05/相关安全、Prompt、AgentLoop 问题已有明确回复；推荐不自动算决定 |
| `CCA-G-02 Field registry` | 每个最终字段具备 14 项完整元数据、stable ID、唯一 owner/consumer；无“实现时再定” |
| `CCA-G-03 No phantom fields` | 每个 INI 字段有真实消费者；每个可配置行为有字段或明确 fixed invariant；无空壳 section |
| `CCA-G-04 Source/override` | INI、XML、环境、CLI 的允许来源和 merge 表完整；XML 任意 key 无法覆盖安全/连接定义 |
| `CCA-G-05 Freeze/reload` | startup、Context open、逐 main/side admission 全 bytes/digest observation、turn/child freeze、external edit、短期 REPL lock/expected digest/atomic save、invalid candidate、Model/Permission 删除全部有状态表；无 watcher/interval/policy field |
| `CCA-G-06 Secret boundary` | secret registry 与 data-classification matrix 一致；结构化 carrier 永不把 secret 带入禁止目的地；普通正文 scan 保证准确服从 M05-59 A/B/C，门槛前后/重复/重叠/cross-chunk canary 通过；private/public digest 分开 |
| `CCA-G-07 Migration` | 当前 `_CONFIG_.ini` 每个字段有 keep/rename/transform/delete/manual disposition；迁移失败不破坏原文件 |
| `CCA-G-08 Transaction` | comment/order-preserving draft、redacted diff、digest conflict、atomic publish/recovery 在目标平台通过 |
| `CCA-G-09 UI parity` | model-repl/config-repl/context-repl/show-config/help 都从同一 schema 显示类型、来源、生效点、秘密和错误；每个 TUI domain action 有同 registry CLI projection但不暗开 remote/headless |
| `CCA-G-10 Self-test` | Stage 1 完整离线并覆盖 Context codec/workspace/Catalog/scan-cap/performance；Stage 2 显式 consent；Stage 3 检查 Model/Permission 名称、说明、Prompt、能力和拼写但只 advisory；三者不改写权威配置 |
| `CCA-G-11 Host isolation` | internal curl/Git/helper 不受 cwd/PATH/home config/隐式 env 改写；raw shell 的继承边界诚实显示 |
| `CCA-G-12 Legacy proof` | XP x86 与 CentOS 7 完成 parser、secret、TLS、reload、atomic update、resource 和 terminal fixtures |
| `CCA-G-13 Cross-doc parity` | 正式 schema、模板、README 中英、CLI help、decision log、XML whitelist 与 release manifest 同批校验 |
| `CCA-G-14 Minimality` | 不存在无消费者字段、重复默认来源、泛化 escape hatch 或可以关闭正确性不变量的开关 |

## 原审计题源映射（不再直接回复）

下面 15 项记录第四轮如何发现配置缺口。它们已经被拆入 M05、F4、TS、AL06 的唯一 owner 正式组，不再是“当前决策包之外”的第二套问卷，也不应回复 `CCA-Q-*`。多数原选项只用于审计旧候选为何被提升；容易被误答为当前选择的 scheduler/reload A/B/C 已直接替换成 superseded 说明。正式选择只以决策包内编号为准。

| 题源 | 现行唯一 owner |
| --- | --- |
| CCA-Q-01 | M05-13 |
| CCA-Q-02 | F4-02 |
| CCA-Q-03 | F4-01 已选择 custom，现行结果为 D-048 |
| CCA-Q-04 | raw 环境由 M05-15；内部工具隔离为 HCFG-04/TP-029 技术门 |
| CCA-Q-05 | M05-14 |
| CCA-Q-06 | M05-15 拥有 EnvironmentMode/Set/Unset；M05-55 条件拥有 inherit baseline |
| CCA-Q-07 | M05-16 只定 outside 粗/细字段；M05-56 定 SensitiveRead 是否存在，classifier/policy 由 TS-21；direct HTTP/DirectNetwork 由 TS-11 |
| CCA-Q-08 | M05-17 |
| CCA-Q-09 | M05-18 只定 config reset；secret-bearing backup/export 由 M05-42；Context purge 由 CX/F4；跨资源事务由 F4-09 |
| CCA-Q-10 | M05-19 |
| CCA-Q-11 | M05-06 |
| CCA-Q-12 | M05-20/M05-32 |
| CCA-Q-13 | M05-05；公开 reasoning 独立由 M05-40 |
| CCA-Q-14 | M05-21 只定字段存在性；颜色语义由 TU-02 |
| CCA-Q-15 | M05-22 |

### CCA-Q-01 明文 HTTP

- A：只允许可证明且强制绕过代理的无鉴权 loopback HTTP；任何 Key/secret header + HTTP 为静态错误。（推荐）
- B：允许 per-Model 危险确认后向任意 HTTP 发送，持续显示明文警告。
- C：配置写了 HTTP 就直接使用，只在 self-test 提醒。

### CCA-Q-02 per-Model rate/cooldown（superseded，非投票）

旧 A/B/C 已由 F4-02 的正式 scheduler 选项替代。本节只保留题源：retry 与 admission/cooldown 不同，所有 request purpose 必须进入同一当前进程 scheduler；是否出现 per-Model 并发/间隔字段只回答 F4-02。

### CCA-Q-03 运行中外部 INI 变化（已由 D-048 收口，非投票）

旧 A/B/C 已由 F4-01 的 custom 回复和 D-048 替代。本节只保留题源：每个顶层 main/side turn admission 前完整读取 bytes/digest；未变复用 immutable generation，变化则全量验证并自动原子激活；无效/删除/半写或当前 Model/Permission 失效阻止该新 turn。active turn 及 child activity 不热换，不建立 watcher、reload interval 或 policy 字段。

### CCA-Q-04 宿主工具配置

- A：Runtime 内部 curl/helper 隔离宿主配置；internal Git 若存在则禁 system/global 和可执行扩展，只读取明确允许的 repository semantics；raw shell 明确继承用户环境/工具配置。（推荐）
- B：所有子进程都清除宿主配置，包括模型 raw shell。
- C：给每种内部/外部工具增加继承开关。

### CCA-Q-05 传输资源上限是否公开

- A：header/event/buffer/compressed/decompressed/total 均有 Runtime hard cap，INI 只公开确有用户场景的少数字段。（推荐）
- B：全部作为高级配置公开，但都不能超过 hard cap。
- C：完全依赖 curl/系统内存。

### CCA-Q-06 Exec 环境配置面

本题已拆分并 superseded，不再接受 `CCA-Q-06` 回复：M05-15 独占是否提供 `EnvironmentMode` 与 typed set/unset；M05-55 在 M05-15 A/B 下独占 `inherit` baseline 是发行 allowlist、近乎完整宿主环境，还是高置信 denylist。M05-15 C 固定 clean baseline；所有路线都删除 `ExposeConfiguredProxy`，内部 curl/Git/helper 使用独立最小环境。

### CCA-Q-07 Permission 精简字段

- A：首版保留 Read/Write/Delete/Shell/OutsideWorkspace；无 direct HTTP tool 就不加 Network，不加 SensitiveRead/regex。（推荐）
- B：再加 SensitiveRead 和 direct Network。
- C：继续旧 Allow*/Confirm*/regex 结构。

### CCA-Q-08 `LogLevel` 的去留

- A：保留，并精确定义 error..trace 只影响后续可选 XML/终端诊断，canonical 事实永不受影响。（推荐，若诊断包需要）
- B：v0.1 删除，用固定简洁诊断；self-test 显式 details。
- C：保留但让低级别省略 XML 工具/审批事实。

### CCA-Q-09 reset 行为

- A：reset 总是先脱敏预览和备份；默认重建 non-secret defaults，Key/自定义 Model 是否保留逐项选择，不自动清空 Context。（推荐）
- B：一条命令删除整个 `__yaca__`。
- C：只改内存，退出后不保存。

### CCA-Q-10 optional 值语法

- A：每个 optional 类型使用明确 schema enum，如 `auto`/`unknown`/`provider-default`，数字字段不再接受 bool `false`。（推荐）
- B：继续用 `false` 同时表示关闭、未知、无限和 provider default。
- C：缺失字段承载所有 optional 语义。

### CCA-Q-11 XML budget override（superseded，非投票）

唯一正式入口是 M05-06：A 为无条件最小四项；B 在 AL06 条件允许时增加只能下调的 turn budgets/compaction threshold；C 完整继承 B，并且只再增加 `MaxQueuedMessagesOverride`、`MaxSideRequestsOverride`、`DiagnosticDetailOverride=inherit|minimal`，以及仅在 TU-29 B/C 已建立 live-preview consumer 时存在的 `ToolPreviewKiBOverride`。旧“XML 可覆盖任意 INI”已排除，不能作为第四条路线复活。

### CCA-Q-12 conditional metadata 跨 endpoint 可见性

- A：XML 保存接盘所需的非秘密 Model snapshot；发送给 self-test reviewer/support 时再最小化 endpoint/hostname/Description。（推荐）
- B：exact endpoint 永远不进 XML，因此目标机只看到 Model 名。
- C：所有 endpoint/query/header 原值都进入 XML/reviewer。

### CCA-Q-13 Model generation options

- A：核心只保留 MaxOutputTokens；其他参数来自所选 Protocol 发行 artifact 的 exact typed registry，缺失就不发送。（推荐）
- B：使用核心 generation intent，但每个 Protocol artifact 必须证明 wire mapping 或静态拒绝。
- C：除 MaxOutputTokens 外不提供生成参数，使用 provider defaults。

这是 M05-05 的题源快照，不是第二回复入口；A/B 都要求编码前列清 exact registry/mapping，任何路线都不接受开放 JSON body override。

### CCA-Q-14 profile/Model 自定义颜色

- A：不配置 Color；TUI 根据状态/顺序确定性选择基本色，文字标签始终完整。（推荐最简）
- B：允许 8/16 色 enum 作为纯显示字段。
- C：加入 theme/真彩色表达式。

### CCA-Q-15 generic CLI override

- A：不提供任意 `--set`; CLI/TUI 只有命名的 session actions，长期值经 REPL 事务保存。（推荐）
- B：允许白名单 `--set Section.Key=value` 一次性覆盖并显示来源。
- C：允许任意 key/section 覆盖。

## 回答后如何收口

负责人回答本文件与决策包 05 后，应按固定顺序执行文档收口：

1. 把选择写入 `DECISIONS.md`，不直接改候选表冒充已确认。
2. 更新 `CONFIG-SCHEMA-CANDIDATE.md` 为单一最终字段注册表，删除被拒绝字段和候选措辞。
3. 为每个字段分配 stable ID、consumer、introduced version、secret class、source、override、effective boundary、migration 和 test IDs。
4. 写完整迁移表与旧模板 fixtures；无法无损迁移的值进入交互确认。
5. 同步生成最小合法 INI、完整注释 INI、无效 fixtures、XML override whitelist 和 redaction manifest。
6. 关闭 `CCA-G-01` 至 `CCA-G-14`；技术证明未通过时不能把“负责人接受”写成“平台已支持”。
7. 最后才更新 `src/_CONFIG_.ini`、README/README-zh、CLI help 和 config/model REPL transcript，进入配置子系统实施计划。

在完成这条流程前，最诚实的项目状态仍是：“配置范围已经深入审计，关键选择和目标平台证明尚待关闭”，而不是“配置已经完整”。
