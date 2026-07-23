# 配置完整性专项审计

更新日期：2026-07-18

状态：第四轮审计底稿；缺口已经提升到 M05/F4/TS/AL06 正式组；本文末 `CCA-Q-*` 只保留题源追踪，不再作为并行回复入口

## 结论先行

当前配置设计已经覆盖了大部分“会出现哪些区域”，但还不能称为实施就绪。最准确的判断是：

- [`CONFIG-SCHEMA-CANDIDATE.md`](CONFIG-SCHEMA-CANDIDATE.md) 在审计输入时已经是一份很强的**候选字段注册表**，明显优于当前模板；它当时覆盖来源、秘密、生效点、XML 快照和 55 条跨字段校验，本审计发现已整合后现为连续 `CV-001` 至 `CV-065`。
- [`src/_CONFIG_.ini`](../src/_CONFIG_.ini) 是**已经漂移的旧草案**，不能继续作为 parser、默认值或测试 fixture 的事实源。它仍包含已被正式决定否定的 `Permission.Cautious`、profile 内 `DoubleCheck`、全局 retry、`UseStunnel` 和启动自动联网。
- 当前候选 schema 真正缺的不是再堆十几个“看起来高级”的开关，而是四个跨生命周期契约：明文 HTTP、per-Model rate/cooldown、运行中外部配置 reload、Runtime 内部工具与宿主配置隔离。
- 另有一些行为虽然必须实现，却**不应成为 INI 字段**：原子保存、DTD 禁用、auto-save、恢复 fail-stop、内部资源硬上限、curl 不读用户 curlrc、内部工具固定查找路径、secret 不进 XML/argv，以及 turn 内配置冻结。
- 配置只有在“字段注册表、唯一消费者、来源/覆盖、保存事务、运行时 reload、迁移、REPL、self-test、旧平台证明”全部对齐后才算完整。单纯把候选字段复制进 INI，会把未决推荐伪装成默认契约。

本审计建议把配置面收敛成七个区域：`General`、`Agent`、`Network`、`Exec`、`Context`、`Permission.*`、`Model.*`。不保留空壳 `Tui`，也不新增 `Storage`、`Update`、`Plugin`、`Telemetry`、`Project` 或 `SelfTest` section。必须存在但不适合用户调整的常量，进入版本化 Runtime limits/manifest，而不是藏成更多配置键。

后续整合把本审计发现进一步拆成了独立 owner：M05-33/36/37/38 分别拥有 Endpoint、proxy、CA、redirect，M05-23 拥有 header/body，M05-16 只拥有 Permission 字段存在性，TS-21 独占 SensitiveRead classifier/policy，TS-11 独立决定 direct HTTP 并因此决定 `DirectNetwork` 是否存在；F4-07 只拥有 raw exec stdin 的 EOF/有界 immutable payload 路线，两项都排除交互 PTY/console；TS-13 拥有 shell dialect，TS-22 拥有 stdout/stderr 跨流顺序，AL06-27 拥有 review 预算形态。M05-40/41/42 又分别拆出了公开 reasoning、self-test retry/fallback 与 secret-bearing backup/export。本文中的早期候选若与这些正式组不同，以正式组为唯一待回复入口；不能同时回答 `CCA-Q-*` 和另一个组来产生两份配置事实。

## 审计证据与边界

本轮逐项比较：

- [当前旧模板](../src/_CONFIG_.ini)；
- [配置 Schema 候选注册表](CONFIG-SCHEMA-CANDIDATE.md)；
- [数据分类与跨模型可见性候选](DATA-CLASSIFICATION-CANDIDATE.md)；
- [决策包 05：Model、完整配置、网络与 Self-Test](decision-packets/05-model-configuration-network-selftest.md)；
- [决策日志](DECISIONS.md) 与 [深层原子问题](QUESTIONS.md)；
- [05 配置子系统](subsystems/05-configuration.md)、[03 网络子系统](subsystems/03-network-transport.md)、[06 模型协议](subsystems/06-model-protocols.md)；
- [设计清单](DESIGN-CHECKLIST.md) 中的 `CFG-*`、`NET-*`、`MODEL-*`、`SAFE-*` 和 `DIAG-*`。

本文件不决定 XML 元素名、curl/native helper 选型、最终默认毫秒数或测试平台矩阵，也不修改模板。它只回答：“如果明天负责人把选项回复完，配置设计还缺什么才足以进入实现计划？”

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
  -> freeze effective turn snapshot
  -> requests/tools consume only that snapshot
  -> at safe boundary detect INI identity/digest change
  -> validate a complete new generation or fail closed
  -> record non-secret transition in Context XML
```

必须同时存在两种 digest，不能复用一个值：

- **private source digest**：对原始 INI bytes 计算，只在本进程内用于外部修改检测；它间接包含 Key，不能写 XML、日志或 support。
- **public effective digest**：只对允许进入历史的非秘密规范投影计算，写入 XML 解释某 turn 使用了哪套配置；Key、secret header、proxy credential 不参与。

这是 `D`。既然 Key 已确认明文位于 INI，而 Key 又不得进入 XML digest，就不可能安全地用“整份 INI hash”同时承担冲突检测和可移植快照身份。

## 配置来源与覆盖审计

| 来源 | 可以定义什么 | 不可以定义什么 | 冻结/生效 | 审计结论 |
| --- | --- | --- | --- | --- |
| Runtime hard limits | 不可关闭的内存、队列、XML、网络、循环和安全上限 | 用户人格、endpoint、Key、默认 Model/Permission | 程序版本/bootstrap | `D`；不是 INI section |
| typed schema | 字段、类型、安全默认、迁移、帮助、脱敏元数据 | 用户秘密和用户选择 | 程序版本/bootstrap | `O` 需确认唯一事实源；推荐沿用 M05-07/AQ-131 |
| 完整用户 INI | 七个 section 家族的用户配置 | Context 当前选择的历史事实 | load/reload generation | `C` 方向已确认 |
| Context XML | 无条件项为 `CurrentModel`、`CurrentPermission`、`DoubleCheckOverride`、`ContextPrompt`；AL06-08 C 才有 `ReviewModelMapping`，AL06-11 A + AL06-34 C 才有 `CompactionConsent`，TS-14 C 才有 identity-bound `WorkspaceAcknowledgement`；M05-06 B/C 共享条件 turn/threshold overrides，只有 C 再有 queue/side/tool-preview/diagnostic 四项精确 preference | Key、endpoint 定义、proxy、CA、Permission 定义、Exec 环境、跨 Context trust registry、任意 session key | Context open / next-turn / next purpose | 精确白名单及条件字段必须由同一 registry 生成，不能由 XML 反向启用功能、压缩或权限，`O` |
| 进程环境 | 只有在 `ProxyMode=environment` 或 raw shell environment policy 明确允许时被消费者读取 | 不能成为 Key 的隐式 fallback；不能覆盖 typed schema | request/tool boundary | `D+O`；必须列明读取哪些变量 |
| CLI/TUI 动作 | 选择 Model/Permission、`.cautious`、`.prompt` 等明确动作 | 不提供通用 `--set any.key=value` 第三套配置层 | next-turn/transaction | 推荐 `D`；若要 generic override 则新开 `O` |
| 工作区文件 | 只作为模型/工具读取的数据或明确采用的项目指令 | endpoint、Key、Permission、proxy、工具开关 | tool/prompt contract | `D`；不新增 project config |

候选 schema 开头写了“当前命令显式的一次性参数”，但目前没有列出允许的一次性字段。最终规范要么列出有限命令，要么删除这个泛化来源；否则实现者会自然加入一套未审计的 `--set` 机制。

## Section 与字段族逐项审计

### 1. `General`

| 字段族 | 必要性与消费者 | 完整契约检查 | 迁移、UI/self-test 与旧平台风险 | 结论 |
| --- | --- | --- | --- | --- |
| `SchemaMajor` / `SchemaMinor` | bootstrap parser、迁移器、REPL writer 必需；不是 AgentLoop 配置 | ASCII decimal；major/minor 分开；INI only；bootstrap；缺失是否可识别为 pre-schema 文件需迁移表 | config-repl 顶部显示；Stage 1 检查 reader/writer 能力；旧程序不得重写更高 major | `O` 冻结版本语义，随后 `D` |
| `SystemPrompt` | Prompt assembler 必需，用户已要求全局 Prompt | UTF-8 用户内容、明确字节/token 上限；INI only；next-turn；进入 XML 的是 Prompt component snapshot，不是 XML override | PP-11 A 时旧 `Model.CustomPrompt` 经确认合并；B/C 按各自条件字段保留；REPL 多行编辑、预览、秘密提醒；XP 内存和控制台 echo 需测 | 保留；多行 grammar/上限为 `O+T` |
| `LogLevel` | 只应控制可选诊断详细度；不能改变 canonical XML 事实 | M05-17 A 为 error/warn/info/debug/trace、默认 info；B 无字段；C 为 normal/trace、默认 normal；INI only，next diagnostic event | show-config 显示；Stage 1 拒绝混用两个 enum；没有独立日志文件时 `trace` 的目的地必须写清 | 条件字段，M05-17 唯一 owner |
| `SelfTestReviewerModel` | **仅 M05-12 B** 的 Stage 3 reviewer selector 消费 | Model logical name；缺失/禁用/本次 Stage 2 未通过时 Stage 3 unavailable，不 fallback；普通 Agent/Stage 1/2 不受影响 | config-repl 显示引用状态；Stage 3 仍显示并再次 consent | 条件字段，M05-12 唯一 owner |
| 生成/更新时间、程序版本 | 没有领域消费者；文件 mtime 不可靠但也不应由用户配置 | 不是用户字段；程序版本与 schema 版本分离，构建版本进入诊断/快照 | 当前模板仅用注释 `GeneratedAt/UpdatedAt`，不可作为迁移依据 | 不加入 schema，`D` |

审计判断：`General` 不应继续膨胀。`Language`、含糊的通用 `Mode`、`Vivid`、`Theme`、自动更新、遥测、数据根都没有合法消费者或会产生 bootstrap 循环。只有 TS-18 B 才在 Agent 生成语义窄化的 `Autonomy`，它不是旧 Mode 的自动迁移。固定 English/ASCII UI、自然语言跟随用户、自动终端降级已经由其他系统表达。

### 2. `Agent`

| 字段族 | 必要性与消费者 | 完整契约检查 | 迁移、UI/self-test 与旧平台风险 | 结论 |
| --- | --- | --- | --- | --- |
| `DoubleCheck` | AgentLoop/review router 必需；`.cautious` 形成 XML tri-state override | bool INI default + `inherit|true|false` XML；next-turn；至少包含 termination review；不能放进 Permission/Model | config-repl 显示 INI/XML/effective；`.status` 显示来源；Stage 1 检查轮次预算；旧 Cautious/profile 值迁移需人工选择 | 结构 `C`，默认/动作范围/失败策略 `O` |
| `Autonomy` | 只有 TS-18 B 的 prompt/UI experience policy 消费 | `direct|explanatory`，INI only、next-turn；只影响主动说明与可选额外验证，必需验证/安全/预算不变 | config-repl/status 显示 effective；Context 只 snapshot 不 override；A/C 拒绝 orphan field；旧 Mode 不自动迁移 | 条件字段，TS-18 唯一 owner |
| `ReviewModel` / `CompactionModel` | ReviewModel 由 AL06-08 B 的所有实际 review 消费；CompactionModel 只在 AL06-11 A + AL06-30 B 消费 | enabled Model logical name；ReviewModel 对 AL06-07 A/B 的 action 与 termination 共用，AL06-07 C 仅 termination；AL06-11 B/C 不发 compaction Model request；缺失/失效不 fallback | config-repl 显示引用解析和外发边界；Stage 1 静态解析，实际 request manifest 保存最终实例 | 条件字段，AL06-08/11/30；Context 路线分别使用 event/条件 mapping，不复制定义 |
| 总请求/工具预算 | AgentLoop scheduler 必需，防止无限循环 | AL06-09 A/B 才公开 `MaxModelRequests`、`MaxToolCalls`；C 使用版本化固定 turn safety cap，不生成字段；PJ-12 B 的 `context-name` 另用每 Context 一次的 lifecycle budget并计 Context/runtime | UI 只显示所选路线真实存在的总量和剩余量；Stage 1 拒绝 orphan 字段；XP x86 需 soak 校准默认或固定 cap | 条件字段，AL06-09 唯一拥有预算层，默认值与 XML override 为 `O+T` |
| 时间预算 | turn deadline owner 必需 | AL06-09 A/B 才有 `MaxTurnTimeMs`；C 使用发行物固定 deadline；所有 request/retry/tool/review 子 deadline 不能越过当前路线的 turn boundary | `.status` 显示来源；单调时钟技术证明；sleep/挂钟跳变测试 | 条件字段，AL06-09 唯一 owner，`O+T` |
| token 预算 | 用于费用/窗口保护，但 provider usage 不总可靠 | AL06-09 A/B 才有 `MaxTurnTokens`；C 使用固定 turn safety cap；estimated/reported、输入/输出及 side/review/compaction 归账由 owner matrix 冻结，不能叫精确费用上限 | show-config 标明 configurable/fixed、hard/estimated；Stage 2 观察 usage；旧端点无 usage 时保守估算 | 条件字段，AL06-09/22/27；不加 `MaxCost` |
| stuck/repeat | AgentLoop progress detector 消费 | `MaxNoProgressRepeats` 有界；算法版本固定；不能允许 unlimited；next-turn | self-test/评测 fixture，不由 Stage 3 LLM 判定；默认需跨模型测试 | 保留或固定 hard limit 为 `O+T` |
| DoubleCheck 局部预算 | review controller 消费 | AL06-27 A 始终有 `MaxTerminationReviewRounds`，仅 AL06-07 A/B 再有 `MaxActionReviewRounds`；27 B 才有共用 `MaxDoubleCheckRequests`；27 C 使用固定 reserve。所有路线仍受 AL06-09 turn 边界 | config-repl 只显示真实存在分支；Stage 1 拒绝 AL06-07 C 下 action cap 及 orphan/mixed fields；测试拒绝循环、无效 verdict、超时 | 条件字段集，AL06-07/27，`O+T` |

审计判断：不要为 main、side、action-review、termination-review、compaction 各复制一整套几十个预算字段。AL06-09 先定义 turn 边界：A/B 才公开总预算，C 使用不可关闭的固定 safety cap；只有用户明确需要独立调节的 purpose 才进入 INI。条件 `context-name` 固定为每 Context 一次、无 INI 调节项。字段数量少不代表预算不完整，关键是计数表和条件存在性完整。

### 3. `Network`

`Network` 描述 yaca 自己发往 Model endpoint 的全局传输策略；TS-11 B/C 时还包含一组明确以 `DirectHttp` 命名、与 Model credential/transport 隔离的 direct-tool policy。它始终不约束 raw shell 中用户/模型自行启动的网络程序。

| 字段族 | 必要性与消费者 | 完整契约检查 | 迁移、UI/self-test 与旧平台风险 | 结论 |
| --- | --- | --- | --- | --- |
| `ProxyMode` | network policy compiler 必需 | M05-36 A 为 off/environment/explicit、B 为 off/explicit、C 为 off/environment；三项 missing/new 均 off，environment 必须显式选择 | `FollowProxy` 迁移；REPL 显示实际模式但不泄露 credential；Stage 2 显示将用 proxy/bypass | 条件 enum，M05-36 唯一 owner，`O+T` |
| `ProxyUrl` | 仅 explicit 模式需要 | 绝对 proxy URL；conditional secret；禁止进入 XML/argv；空值与 missing 分开；不能在 off/environment 下偷偷生效 | UI 只显示 sanitized origin/configured；ACL/secret canary；旧 curl proxy auth 需目标机测试 | 保留，`D+T` |
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
| `TimeoutMs` | raw-shell tool controller 消费 | 正整数毫秒/call；不能用 `false=无限`；受 turn deadline；next-tool-call | 旧 `false` 迁移为 schema default/explicit auto；审批显示 deadline；XP 取消/进程树证明 | 保留，默认 `O+T` |
| termination grace（非配置字段） | process adapter 消费 | 各平台发行 manifest 固定有界毫秒值；grace 后强制终止；无法证明树终止仍返回 unknown；INI/XML 不得覆盖 | status/self-test 只读显示 adapter、manifest 与实际值；child-tree/XP 取消 fixture 冻结常量 | Runtime/manifest 常量，`J/T` |
| `MaxOutputKiB` | capture/canonical result 消费 | stdout+stderr 合计还是分别必须明确；头尾截断、原始字节数和 XML result 契约 | `MaxOutputKB` 迁移并改 KiB；Stage 1 大输出；32 位内存/pipe backpressure | 保留，默认 `O+T` |
| output decoding（非配置字段） | text boundary/process result 消费 | Runtime 内建 `auto`；result 记录实际 decoder、替换/失败和原始字节；不自动改写文件内容 | 多代码页/二进制 fixture；仅当旧平台证明无法可靠检测时，技术证明才可提案 typed troubleshooting override | 当前无 `OutputEncoding`；基线与例外 gate 为 `J/T` |
| `EnvironmentMode` | **仅 M05-15 B** 的 raw shell launcher 消费 | `inherit|clean` 必须说清哪些变量；A 固定受控继承、C 固定 clean，都没有该字段 | approval/status 显示；Stage 1 canary；XP `%COMSPEC%/TEMP%/PATH%` 最小集合需测 | 条件字段，M05-15 唯一 owner |
| `EnvironmentSet` / `EnvironmentUnset` | **仅 M05-15 B** 在用户确有稳定全局 shell 环境需求时存在 | 列表 grammar、重复、大小写、secret 标记、保留变量、XML 投影都必须完整 | secret 输入/脱敏/支持输出；Windows env block 大小和 case-insensitive 名称 | 条件字段；A/C 时必须从 schema 删除 |
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
| `AutoJumpToDir` / `ResumeDirectory` | Context resume controller 消费；由 PJ-13 条件生成且互斥 | PJ-13 A/B 才有 bool AutoJump；C 才有 `jump|ask|keep`，默认候选 ask；跨 initial boundary/Git root/identity 始终不能静默跳转 | A/B 旧 bool 可直接验证；迁到 C 必须显示 typed 转换候选；context-repl/status 显示 initial/recorded/effective cwd；路径/权限/junction 测试 | 条件字段，PJ-13 唯一 owner，`O+T` |
| `CompactThreshold` | 仅 AL06-11 A 的 structured-summary 或 B 的 deterministic-checkpoint trigger 消费 | ratio 严格 `(0,1)`；按有效 Model 窗口、Prompt/tool/output reserve 计算；C 下字段/override 不存在 | 旧字段只有 A/B 路线迁入；status 显示 consumer/threshold；未知 ContextLength 保守 | 条件字段，AL06-11 唯一 owner，`O+T` |
| effective compaction reserve（非配置字段） | 三条 AL06-11 路线的 fit/view calculator 消费 | Runtime 按有效 Model、输出、Prompt、tool schema、不可拆组和估算误差实时计算；只读且随 view 变化；不等于 trigger | status/request-view manifest 显示派生值、输入摘要与算法版本；跨 Model/超大原子组 fixture | 当前无 `CompactReserveTokens`；算法保证与证明为 `J/T` |
| XML session preference allowlist | M05-06 的 Context-scoped consumers | A 无额外项；B/C 共享条件 turn budgets 与 AL06-11 A/B threshold override；C 再有 `MaxQueuedMessagesOverride`、`MaxSideRequestsOverride`、`ToolPreviewKiBOverride`、`DiagnosticDetailOverride=inherit|minimal`，只能收紧 | config-repl/context status 显示 INI/Runtime/XML/effective；导入拒绝 unknown/orphan/放宽值；不存在路线不生成空字段 | 条件 XML 项，M05-06 唯一 owner，`O+T` |
| quota / auto purge | CX-11 storage admission/maintenance 独占 | A 无字段；B 才有 `MaxContextMiB/MaxActiveContexts/MaxContextTotalMiB` 且只能低于 Runtime hard门；C 才有 `AutoPurgeTrash` + true 时 required `TrashGraceDays` | context browser/self-test 显示来源；C 只对 durable trash、stable scan、预告清单生效；Win32 x86/慢盘/时钟测试 | 条件字段族，CX-11 唯一 owner；B/C 互斥，`O+T` |
| resolver scan hard cap（非配置字段） | Context resolver 消费 | per operation；发行 manifest/Runtime 不可放宽；超限必须返回 incomplete/ScanLimit，不能返回 not found | context-repl/status/self-test 只读显示 cap 与 manifest identity；大目录、junction、不可读目录校准 | 当前无 `MaxScanEntries`；数值冻结与失败退路为 `J/T` |

不要加入 `RootDir`、`AutoSave`、`RepairOnOpen`、通用 `RetentionDelete`、`ExportSecrets` 或“WAL 开关”；CX-11 C 的 auto purge 是严格限于 trash 的条件例外：

- data root 必须在读 INI 前定位；
- durable commit 和损坏 fail-stop 是正确性不变量；
- 删除/导出是显式危险动作；
- XML/WAL 方案由存储架构决定，不能让每个用户配置出一种事实源。

### 6. `Permission.*`

| 字段族 | 必要性与消费者 | 完整契约检查 | 迁移、UI/self-test 与旧平台风险 | 结论 |
| --- | --- | --- | --- | --- |
| section suffix / `Abbreviation` | permission selector、CLI/REPL 消费 | section suffix 是逻辑名；简称 ASCII、各自命名空间折叠唯一；INI definition，XML 只选择 | 旧名称保留；REPL rename 必须报告 Context stale references；不同文件系统不参与大小写 | 保留，精确规则 `O` |
| `Description` | 只供 UI/Stage 3 advisory | UTF-8 user-content、有界；不得决定权限 | Stage 3 可指出名称/描述不匹配但不能修改 policy | 可保留，`D` |
| `Color` | 只供 TUI label 投影 | M05-21 B 才允许 Permission Color；A/C 不存在。固定 8/16 色 enum、缺失可确定性分配，颜色不进授权 | 无色仍有文字；语义角色/后备只由 TU-02；旧控制台测试 | 字段存在性 M05-21；颜色语义 TU-02 |
| direct read/write/delete | direct tool permission evaluator 消费 | `deny|confirm|allow`；缺失硬错误；tool-to-capability 表版本化 | Allow/Confirm 对迁；审批显示精确 action；链接/外部路径测试 | 保留，矩阵默认 `O` |
| `Shell` | raw shell 唯一宽权限消费者 | `deny|confirm|allow`；允许意味着可能读/写/删/联网/越界/启动子程序 | 旧 AllowWrite/Delete/Network 不能推导 Shell；迁移必须显式问；UI 显著写 broad | 保留，`O` |
| `OutsideWorkspace` 或拆分的 `OutsideRead/Write/Delete` | direct tools 的外部路径 modifier | M05-16 A 使用一个粗字段，B/C 使用三字段；都与基本 Read/Write/Delete 取更严格且不约束 raw shell | path canonicalization/junction/symlink 技术测试；未选字段必须从 schema/help 消失 | M05-16 唯一 owner，`O+T` |
| `SensitiveRead` | **仅 M05-16 C** 存在；依赖不完备 classifier | 字段只定义三态策略；TS-21 决定分类来源，命中后与 Read 取更严格结果，未命中不能叫安全 | UI 显示分类原因/版本；大量 false-positive/negative fixture | 字段存在性 M05-16；classifier/policy TS-21，`O+T` |
| `DirectNetwork` | 只有 TS-11 B/C 选择 direct HTTP tool 时有消费者 | 不约束 Model provider HTTP，也不约束 raw shell；不再由 M05-16 额外开关 | TS-11 A 时从 schema/help/template 删除；不能保留永远 deny 的空壳字段 | TS-11 条件字段，`D` |
| regex filters | 不能可靠分类复合 shell 副作用 | 最多作为附加 deny/warn，绝不能授予 | 旧 AllowRegex/ExcludeRegex 不应直接迁为安全保证 | 推荐删除，`O` 若仅保留 deny |

`Cautious` 不是 profile，`DoubleCheck` 不属于 Permission；这是 `C`。发行模板首项为 `Std` 已确认；是否再提供 `Readonly`/`Trusted` 及其精确 Shell policy 由 TS-04 唯一决定。profile 名称和 Description 永远不能改变真实 policy。

### 7. `Model.*`

一个 `Model.*` 是完整连接实例，这是 `C`。下面每组都由 Model registry 保存，但由不同消费者使用，不能因为放在同一 section 就让一个模块读取全部秘密。

| 字段族 | 必要性与消费者 | 完整契约检查 | 迁移、UI/self-test 与旧平台风险 | 结论 |
| --- | --- | --- | --- | --- |
| `Enabled` | selector/startup validator | bool required；disabled 仍语法合法但连接字段可空；第一项必须有效还是跳过待决 | 旧字段迁；model-repl 显示 draft；Stage 1 不联网验证 | 保留，首项策略 `O` |
| logical name / `Abbreviation` | selector、history mapping | section suffix + ASCII 简称；折叠唯一；重命名不改写历史 XML | rename 显示受影响 Context；旧 Model missing 只读映射 | 保留，`O` |
| `Description` / `Color` | UI/advisory only | 有界用户文本；M05-21 B/C 才有 Model Color；颜色不是能力 | Stage 3 advisory；无颜色/语义后备由 TU-02 | Description 可保留；Color 存在性 M05-21 |
| `CustomPrompt` | 只有 PP-11 B/C 有消费者 | B 为高于 SystemPrompt 的 Model-specific 用户层；C 为受限 compatibility instruction；均有界、INI only、next-turn、完整 component snapshot，且低于 Runtime；A 下字段不存在 | model/config-repl 显示 route/authority；Model switch 写 transition；C 不能替换 serializer/role/tool/control；旧文本迁移必须预览 | 条件字段，PP-11 唯一 owner；A 推荐删除但不静默丢内容 |
| `Protocol` | protocol adapter | 稳定 enum；enabled required；不从 URL/名称探测 | `Style` 迁移；Stage 1 enum，Stage 2 wire check | 保留，v0.1 enum 范围 `O+T` |
| `Endpoint` | network destination | 完整绝对 URL还是 base URL；scheme/host/port/path/query/userinfo；conditional sensitive；跨 endpoint 预检 | `Url` 迁移需确认语义；REPL sanitized；HTTP/redirect/DNS/proxy/TLS 测试 | 保留，精确语义 `O+T` |
| `RemoteModel` | request encoder | 有界 provider ID；不能从 section 名推断；conditional metadata | `Name` 迁移；Stage 2 回显观察值若协议提供 | 保留，`D` |
| `AuthMode` / `Key` | auth compiler only | AuthMode 的存在/枚举由 M05-02 决定；Key secret、INI only、never XML/argv/diagnostic；HTTP 明文策略联动 | Key keep/replace/clear；ACL/echo/canary；旧空 Key 不能自动读 env | Key 保留；AuthMode 条件 schema 为 `O`，秘密路径 `T` |
| `ContextLength` / `MaxOutputTokens` | budget/compaction/request encoder | optional positive token count；unknown/provider-default 的规范拼写；output < context | 旧数字迁；model-repl 显示 declared/observed；跨模型窗口测试 | 保留，`O+T` |
| `Streaming` / `Tools` | request adapter/Agent eligibility | Streaming fallback 由 M05-25；M05-03 A/C 有条件 enum，B 完全没有 Tools 字段且 Protocol adapter 静态必须 native。任何路线的 observation 都不改写权威，B 也不把在线测试变启用 gate | 旧模板新增；Stage 1 校验 manifest/字段分支，Stage 2 只观察且不执行 tool | Streaming fallback/Tools 精确范围 `O+T` |
| `PublicReasoning` | **仅 M05-40 C** 的 protocol adapter/request projection 消费 | off/summary/full-public 且受 adapter capability；A 无字段并只消费公开 summary，B 完全不消费 | XML 记录公开 kind/来源；hidden reasoning 永不请求/伪造 | 条件字段，M05-40 唯一 owner |
| deadline 字段族 | network deadline compiler | M05-04 A 为 connect/first/idle/total，B 为前三项 + MaxLogicalElapsed，C 为单 RequestDeadline + 内部硬门；所有路线明确 logical/attempt/turn 归属 | 旧单 `TimeoutMs` 无损迁移不可能；REPL 提候选后确认；慢流/半连接测试 | M05-04 唯一 owner，条件字段集 `O+T` |
| retry count/backoff/max | request retry controller | per-Model `C`；哪些阶段、`Retry-After` cap、jitter、unknown outcome；不能调用 curl 自带 retry | 全局旧字段逐 Model 迁；UI 显示 attempt；429/5xx/断流 fixture | 保留，精确字段/default `O+T` |
| generation options | protocol adapter | M05-05 A 用 adapter typed whitelist；B 用核心 generation intent 且 adapter 必须证明映射或拒绝；M05-01 选定 Protocol 后，发行 artifact 必须在编码前列齐 exact name/type/missing/wire/conflict/secret/fixture，未登记项为 unknown | model-repl Advanced 只能列当前 registry；Stage 1 adapter/version parity | `MaxOutputTokens` 保留；条件字段族由 M05-05，registry 不是开放扩展口 |
| `PublicHeader` / `SecretHeader` | 只有 M05-23 B/C 的 auth/network compiler 消费 | B 允许 public+secret，C 只允许 public，A 两者都没有；重复/顺序 grammar 与 reserved header 禁止覆盖 | redacted diff；canary；旧端点 gateway fixture；未选字段为 unknown/deprecated | 条件字段，M05-23 唯一 owner，`O+T` |
| `AdapterOption.<Name>` | protocol adapter | 只允许所选 Protocol 发行 artifact 的 exact typed registry；编码前冻结 wire mapping，不能覆盖 messages/model/tools/stream/auth/limits | Advanced UI 只投影已登记字段；Stage 1 offline parity/golden validation | 条件 family；generic/open-ended `ExtraParameter` 删除，`D` |

#### per-Model rate/cooldown 题源已提升到 F4-02（非投票）

`RetryCount/RetryBaseDelayMs/RetryMaxDelayMs` 只回答“失败后是否重试”，不能回答：

- 正常请求是否要主动限速；
- main、side、DoubleCheck、compaction 是否共享同一 Model 配额；
- 收到 `Retry-After` 后，同一进程后续新 logical request 是否等待；
- 连续 429/5xx 是否开启 circuit breaker/cooldown；
- 两个 yaca 进程使用同一个 Key 时是否声称共享账户级配额。

本节早期曾列 A/B/C，但它们已经 superseded，不再是负责人回复入口。唯一正式选择是决策包 11 的 F4-02：它决定只使用固定单请求 scheduler，还是公开 `MaxConcurrentRequests/MinRequestIntervalMs`；跨进程账户 broker 不在当前简单数据面内。无论 F4-02 选择哪项，六个核心 purpose 与 PJ-12 B 条件 `context-name` 的 admission、`Retry-After`、cooldown、取消和当前进程边界都必须写入同一 scheduler artifact。字段存在性以 F4-02 为准，不能再回答本节旧方案。

### 8. 当前 `Tui` section

当前模板只有：

- `CheckModelOnStart=true`：与“启动/浏览不隐式联网、self-test 显式征得同意”冲突；必须删除。
- `CheckModelPerformanceOnStart=false`：同上；必须删除。
- `DotCommandCompletion=true`：旧控制台不一定能可靠提供 Tab/raw input；点命令本身必须始终可输入，补全只是 renderer 自动能力；推荐不配置。

因此整个 `Tui` section 当前没有必须由用户调整的字段。固定快捷键、基本颜色、无鼠标、无 theme/vivid/mode、自适应降级都是产品/TUI 契约。删除 section 不代表删除完整 TUI，只是避免为固定行为制造空壳配置。

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
| `MaxCost` | 没有版本化价格、币种和 cache/reasoning 计价来源时不能兑现硬费用 |
| self-test pass/fail 缓存 | 在线观察不是永久配置权威；报告属于诊断事实 |
| config watch interval | 推荐在安全状态边界比较 identity/digest，不需要旧平台 watcher 和轮询调参 |

## 运行中外部配置 reload 题源已提升到 F4-01（非投票）

候选文档定义了“REPL 保存前发现外部修改”，却没有决定一个已经运行的 chat 看到 INI 被编辑、替换、删除或损坏时怎么办。`next-turn` 只说明字段何时能生效，没有说明谁发现新 generation。

本节早期曾列显式 reload、safe-boundary 检测和 watcher A/B/C，但已经 superseded，不再接受回复。唯一正式入口是决策包 11 的 F4-01；它同时拥有 Runtime generation activation 和 REPL stale-write 行为。无论选择哪条发现路线，active turn 不热换、完整 parse/validate、无效新文件 fail-closed、non-secret transition 与 current Model/Permission mapping 都是共同约束。

还必须冻结：

1. active turn 永远继续使用创建时 snapshot；外部变更不撤销已批准/已开始动作。
2. `LogLevel` 即使定义为 display-immediate，也只能在成功载入新 generation 后生效。
3. 新配置无效时不能静默继续执行 last-known-good；可以用它展示旧来源，但新 turn fail-closed。
4. Model/Permission 被删除或重命名时，当前 Context 先只读，走显式 mapping/switch；不自动选第一项。
5. endpoint、SystemPrompt、Permission、DoubleCheck 或 secret 改变时，下一个 request 前生成 transition；Key 值本身不写 XML。
6. 只改注释是否产生 generation：推荐 private digest 变化但规范 effective digest 不变，不显示行为 transition；REPL 仍需避免覆盖注释改动。
7. REPL 和 chat 同进程共享一个 config service；不能各自缓存一份 table。

产品选择只回复 F4-01；文件身份、case-only replace、mtime 粒度、同大小快速改写、网络盘/FAT、Win32 share mode 和原子替换失败仍需技术证明。

## 旧模板必须删除、迁移或改写的内容

### 必须删除

| 旧内容 | 原因 | 新位置/行为 |
| --- | --- | --- |
| `Network.UseStunnel` | 发行资源没有 stunnel，也没有已确认架构 | 删除并报明确 deprecated diagnostic |
| `Permission.Cautious` 的特殊内置语义 | D-021 已确认不是 Permission mode | 可作为普通用户自定义名保留，但不自动启用复核；默认模板删除 |
| `Permission.*.DoubleCheck` | 总开关已移到 Agent + XML override | 迁移时聚合冲突并让用户选择 `Agent.DoubleCheck` |
| `Tui.CheckModelOnStart` | 启动不得隐式联网 | 显式 `self-test` / model-repl test |
| `Tui.CheckModelPerformanceOnStart` | 同上且会产生费用/延迟 | 显式 Stage 2 测试 |
| `Tui.DotCommandCompletion` | 没有稳定用户可调语义，旧终端需自动后备 | renderer capability，不是 schema |
| `Model.CustomPrompt` | PP-11 A 时与 SystemPrompt/ContextPrompt 合并；B/C 时迁到各自 typed 语义 | 始终展示文本/authority/Model 范围并要求确认，绝不静默丢弃或把旧文本提升为协议权威 |
| `AllowRegex` 作为授予依据 | 无法证明 raw shell 副作用 | 删除；若保留只能额外 deny/warn |
| “exactly four built-ins” | 已不存在 Cautious 固定四预设 | 文档改成最终确认的 profile 模板 |

### 必须迁移

| 旧内容 | 候选目标 | 不能静默处理的地方 |
| --- | --- | --- |
| `Network.FollowProxy` | `ProxyMode=environment|off` | 旧文件无法表达 explicit/no-proxy/CA |
| `Network.MaxRetry` / `RetryDelayMs` | 每个 `Model.*` retry | 多 Model 逐项显示，不能自动影响未来 Model |
| `Exec.TimeoutMs=false` | typed `auto/default` 或明确正整数 | `false=无限` 不能越过 Runtime hard cap |
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
| `Context.AutoJumpToDir` / `ResumeDirectory` / `AutoNameOnExit` | PJ-13 A/B 保留并验证 AutoJump；C 删除 bool、生成 `ResumeDirectory=jump|ask|keep`，迁移必须预览且不能静默把 false 猜成 ask/keep。`AutoNameOnExit` 在 PJ-12 A/B/C 下都删除并给 deprecated diagnostic；B 已固定首个完成 turn 后执行一次建议，不另设开关，也不把旧 true/false 静默迁移 |
| `Model.*.Enabled` | disabled 仍需名称/类型合法；第一项 disabled 的普通启动语义由负责人确认 |
| `Model.*.Description` / `Color` | 只作 UI/advisory，不推断厂商、能力或安全；Model Color 只有 M05-21 B/C 保留，语义色由 TU-02 |
| `Model.*.Key` | 继续明文 INI，但进入统一 secret 元数据、keep/replace/clear 和禁止目的地测试 |
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
| 运行中外部 INI reload/fail-close | config service 生命周期，不建议开关 | `O+T` |
| 内部 curl/Git/helper 与宿主配置隔离 | process/network adapter 固定不变量 | `D+T` |
| private source digest 与 public effective digest 分离 | config service + XML snapshot | `D+T` |
| compressed/decompressed/error/total response hard limits | Runtime limits registry | `D+T` |
| 环境代理变量的精确 allowlist、读取时点和 snapshot | Network policy compiler | `O+T` |
| `LogLevel` 在“只有 INI/XML”下各级实际目的地 | Diagnostics contract | `O` |
| non-secret config reset 的字段范围 | config-repl/CLI transaction；M05-18 | `O+T` |
| 含 Key/Proxy credential 的 backup/export 是否存在 | 独立 config export/backup transaction；M05-42 | `O+T` |
| generic CLI one-shot override 是否存在 | CLI/config source contract | `O`；推荐不存在 |
| 每个字段的唯一 owner/consumer 与 stable field ID | typed schema metadata | `D` |
| optional scalar 的唯一拼写 | INI grammar | `O` |
| exact XML override whitelist 与 imported downgrade | XML/config merge contract | `O+T` |
| endpoint/hostname/Description 等 conditional data 是否进入 XML/self-test reviewer | data-classification matrix | `O` |
| capability observation 的内存缓存失效规则 | Model registry/runtime observation | `O+T` |

## 不应为了“看起来完整”而增加的字段

1. 不暴露所有 Runtime hard limit。用户能理解并有合法调节场景的上限才进入 INI；其余在版本化 limits manifest 中有名字、有测试、有错误即可。
2. 不把 every purpose 做成独立 Model。默认 current Model、无工具和最小可见性由 request purpose 固定；只有负责人明确需要专用 reviewer/compactor 时才加 selector。
3. 不为 quick preset 添加永久 provider 品牌字段。preset 只生成一个完整 Model section，之后 Runtime 只认 Protocol/Endpoint/RemoteModel/能力。
4. 不把 self-test observation 写回 `Streaming`、`Tools`、ContextLength 或 Enabled；配置是授权，观察是诊断。
5. 不建立 `[Storage]` 来开关 save/repair/WAL，也不建立 `[Security]` 来声称 sandbox。
6. 不为 curl、Git、patch、diff 建立用户可替换工具路径。内部依赖由发行 manifest/绝对路径控制；模型需要任意宿主工具时走 raw shell。
7. 不配置组合键、mouse、renderer mode、theme、vivid 或 Markdown engine；TUI 自动降级并保持相同 controller actions。
8. 不提供 arbitrary environment/header/body 逃生口。每一个扩展都必须由 adapter schema 命名、类型化、脱敏并禁止覆盖核心。

## 配置浏览器与 Self-Test 的完整责任

### config-repl / model-repl

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

保存前必须显示：脱敏 diff、第一 Model/Permission 是否改变、会在何时生效、是否改变 endpoint/HTTP/Key presence/Permission/DoubleCheck、哪些 active Context 将失去引用。Key 只允许 keep/replace/clear，不能 reveal/copy。两个 REPL 共用一个 draft/validator/publisher；model-repl 不是第二套 parser。

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

静态阶段至少验证：

- schema/version、INI grammar、所有字段/跨字段 CV 规则；
- default section 顺序和 enabled/required fields；
- secret 只存在允许位置、INI 文件权限能力；
- portable root/temp/no-replace/atomic replace/外部修改检测；
- 随包 curl/helper 绝对路径、版本/hash、不会读取宿主 config 的 canary；
- proxy/NoProxy/CA 语法与 bundle；
- HTTP cleartext policy；
- Runtime hard limits 能容纳最小 Prompt/tool schema；
- XML override whitelist 和 imported downgrade；
- Context 目录扫描上限。

Stage 1 不执行 raw shell、不连接 Model、不把“curl 二进制存在”当 TLS/secret 路径已通过。

### self-test Stage 2/3

- Stage 2 显示每个 origin、scheme、proxy/bypass、Key presence、最大 request/token 和测试项；测试 protocol/auth/stream/native tool call，但 synthetic tool 永不执行。
- rate/cooldown 若存在，测试请求也必须进入可解释 scheduler；不能为了 self-test 绕过 provider 保护。
- Stage 3 只接收脱敏结构投影。是否把 exact endpoint/internal hostname 发送给 reviewer 要由数据分类决定；判断“DeepSeek 名却是 Mimo”不需要 Key 或完整 URL。
- Stage 3 永远 advisory，不改写 Enabled、Permission、Streaming、Tools、ContextLength 或任何名称。

## 旧平台专项风险

| 风险 | 配置侧必须保证 | 证明方式 |
| --- | --- | --- |
| Win32 x86 地址空间 | 所有字符串/list/Prompt/header/body/result 有硬界；REPL 不复制多份 Key/大 INI | 大配置、大 Prompt、长 header、外部改写 soak，记录 private bytes |
| XP 文件 API/ACL | config/temp/no-replace/replace/flush/share mode 走宽字符窄适配器；无法证明 ACL 时警告 | FAT/NTFS、只读、共享打开、磁盘满、杀进程 fixture |
| 时间/mtime 粒度 | reload 不能只看 mtime；使用 identity + bytes digest，turn deadline 用单调时钟 | 同秒同大小改写、clock jump、replace/delete/recreate |
| 旧 console secret input | 星号显示不等于关闭 echo；失败时提示安全手工路径且不进 history | XP cmd、QuickEdit、重定向 stdin、Ctrl+C |
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

Key、proxy password、secret header 分别搜索 argv、环境、process list、temp、stderr、TUI history、XML、public digest、support 和 crash residue；任何命中按目的地契约判断失败。

### CCA-TP-04 curl/CA/proxy 宿主隔离

放置恶意 curlrc/netrc、`CURL_CA_BUNDLE`、proxy env、cwd 同名 CA/tool，证明 internal request 只消费 effective snapshot；再测最终随包 curl 的首参数禁 config、redirect、SSE、取消和错误脱敏。

### CCA-TP-05 HTTP 明文与 origin transition

覆盖 loopback、LAN、DNS 指向 loopback、IPv4/IPv6、proxy、HTTP→HTTPS、HTTPS→HTTP、同/跨 origin redirect、Key/header 转发和 Model switch 预览。

### CCA-TP-06 rate/cooldown scheduler

若选择相关能力，测试所有 request purpose 共享、公平排队、`Retry-After` seconds/date、超大/非法 header、cancel waiting、turn deadline、进程重启和两个独立进程的诚实说明。

### CCA-TP-07 runtime reload

覆盖 active request/tool 中改 INI、idle 改注释、改 Key、删当前 Model、降 Permission、损坏/删除/替换文件、mtime 不变和 REPL 同时保存；断言旧 turn 不变、新 turn 使用完整新 generation 或 fail-closed。

### CCA-TP-08 schema/UI/self-test 单一事实源

对每个 stable field ID 自动核对模板、parser、validator、help、config-repl、model-repl、show-config、redaction、XML whitelist 和 self-test；任何消费者出现 schema 未登记字符串都失败。

### CCA-TP-09 Runtime limits 与 Win32 x86

对大 Prompt、Model 列表、headers、SSE event、response、tool args、Exec output、Context XML 和 scan entries 做组合压力；证明 unset/auto 仍受 hard cap，不因多个小上限组合越过内存预算。

### CCA-TP-10 migration fixtures

每个历史模板版本至少有一份合法、一份矛盾和一份损坏 fixture；迁移先预览、备份、写新文件、重新验证，无法无损推导的字段必须问用户而不是猜。

## 配置完整性门

只有全部门关闭，才能把候选 schema 改名为正式 schema 并开始配置子系统实施计划。

| Gate | 通过条件 |
| --- | --- |
| `CCA-G-01 Decision closure` | 本文负责人问题与 M05/相关安全、Prompt、AgentLoop 问题已有明确回复；推荐不自动算决定 |
| `CCA-G-02 Field registry` | 每个最终字段具备 14 项完整元数据、stable ID、唯一 owner/consumer；无“实现时再定” |
| `CCA-G-03 No phantom fields` | 每个 INI 字段有真实消费者；每个可配置行为有字段或明确 fixed invariant；无空壳 section |
| `CCA-G-04 Source/override` | INI、XML、环境、CLI 的允许来源和 merge 表完整；XML 任意 key 无法覆盖安全/连接定义 |
| `CCA-G-05 Freeze/reload` | startup、Context open、turn freeze、external edit、REPL save、invalid reload、rename/delete 全部有状态表 |
| `CCA-G-06 Secret boundary` | secret registry 与 data-classification matrix一致；canary 不进禁止目的地；private/public digest 分开 |
| `CCA-G-07 Migration` | 当前 `_CONFIG_.ini` 每个字段有 keep/rename/transform/delete/manual disposition；迁移失败不破坏原文件 |
| `CCA-G-08 Transaction` | comment/order-preserving draft、redacted diff、digest conflict、atomic publish/recovery 在目标平台通过 |
| `CCA-G-09 UI parity` | model-repl/config-repl/show-config/help 都从同一 schema 显示类型、来源、生效点、秘密和错误 |
| `CCA-G-10 Self-test` | Stage 1 完整离线；Stage 2 显式 consent；Stage 3 advisory；三者不改写权威配置 |
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
| CCA-Q-03 | F4-01 |
| CCA-Q-04 | raw 环境由 M05-15；内部工具隔离为 HCFG-04/TP-029 技术门 |
| CCA-Q-05 | M05-14 |
| CCA-Q-06 | M05-15 |
| CCA-Q-07 | M05-16 只定字段面；SensitiveRead classifier/policy 由 TS-21；direct HTTP/DirectNetwork 由 TS-11 |
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

### CCA-Q-03 运行中外部 INI 变化（superseded，非投票）

旧 A/B/C 已由 F4-01 的正式 config-generation/reload/stale-write 选项替代。本节只保留题源：active turn 不热换、完整新 generation 校验、无效变更 fail-closed 与 non-secret transition 是所有路线的共同约束；发现和激活路线只回答 F4-01。

### CCA-Q-04 宿主工具配置

- A：Runtime 内部 curl/helper 隔离宿主配置；internal Git 若存在则禁 system/global 和可执行扩展，只读取明确允许的 repository semantics；raw shell 明确继承用户环境/工具配置。（推荐）
- B：所有子进程都清除宿主配置，包括模型 raw shell。
- C：给每种内部/外部工具增加继承开关。

### CCA-Q-05 传输资源上限是否公开

- A：header/event/buffer/compressed/decompressed/total 均有 Runtime hard cap，INI 只公开确有用户场景的少数字段。（推荐）
- B：全部作为高级配置公开，但都不能超过 hard cap。
- C：完全依赖 curl/系统内存。

### CCA-Q-06 Exec 环境配置面

- A：raw shell 固定继承受控宿主环境，不提供全局 EnvironmentSet/Unset/ExposeProxy。（推荐最简）
- B：提供 inherit/clean + typed set/unset，但不自动暴露 proxy credential。
- C：提供任意环境模板与 secret 注入。

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

唯一正式入口是 M05-06：A 为无条件最小四项；B 在 AL06 条件允许时增加只能下调的 turn budgets/compaction threshold；C 完整继承 B，并且只再增加 `MaxQueuedMessagesOverride`、`MaxSideRequestsOverride`、`ToolPreviewKiBOverride`、`DiagnosticDetailOverride=inherit|minimal`。旧“XML 可覆盖任意 INI”已排除，不能作为第四条路线复活。

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
