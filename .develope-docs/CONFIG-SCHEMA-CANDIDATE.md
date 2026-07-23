# 配置 Schema 候选注册表

更新日期：2026-07-22

状态：冻结的答复前候选审计；不是现行 schema，也不是可直接使用的 config.ini 模板

> 2026-07-22 状态说明：本文件保留 `decision-inventory-v9` 收到答复前的完整候选空间、条件字段与 `CV-*` 校验依据，内部出现的 DirectHttp、DirectNetwork、细分 Outside、SensitiveRead、Autonomy、Notification、金额、强 undo、`Model.CustomPrompt` 等分支不再是现行产品配置。负责人集中答复后的唯一产品配置 owner 是 [`subsystems/05-configuration.md`](subsystems/05-configuration.md)，现行决定为 D-049 至 D-056；实现字段注册表必须从该 owner 规格继续冻结精确拼写/默认/迁移，不能把本文件的互斥候选合并回 INI。

## 本文解决什么

项目负责人已经确认两个大方向：

- 一个 Model section 表示一个完整的 LLM 连接实例，不再拆 Provider、Credential 和 Model。
- API Key 直接以明文写在主 INI。

本文进一步推荐 Runtime 自己控制的结构化 carrier 不把 registered config-secret value 复制到 Context XML，并且 XML 只保存经过允许的会话覆盖和非秘密快照；普通正文中与过短 secret 相同的字节是否也能维持全局 exact-scan 排除，只服从 M05-59 的 A/B/C 候选。这个泄漏边界仍是候选，不能从“明文存 Key”自动推导成已确认决定。

但“配置项很多”不等于配置完整。实现者还必须知道每个值的类型、单位、缺失含义、默认、来源、生效时间、是否属于秘密、是否进入 Context 快照，以及它和其他字段组合后是否仍然有效。本文把这些信息收进一份候选注册表，供后续逐项决策。

本文不会修改 src/_CONFIG_.ini，也不把下列候选自动升级为正式契约。正式决定仍以 DECISIONS.md 为准。主要关联问题是 QUESTIONS.md 中的 AQ-131 至 AQ-160、AQ-185、AQ-196 至 AQ-201、AQ-218 至 AQ-221、AQ-235、AQ-236、AQ-244、AQ-245、AQ-361、AQ-362、AQ-374、AQ-395、AQ-407 至 AQ-413、AQ-417 与 AQ-432 至 AQ-437；主要设计条目是 CFG-01 至 CFG-29、NET-01 至 NET-13、MODEL-01 至 MODEL-12、MODEL-14 至 MODEL-17、PROC-13、SAFE-01 至 SAFE-18、LOOP-04、LOOP-15、LOOP-31、CTX-06 与 CTX-07。

第四轮配置完整性审计把字段表之外的生命周期缺口补进本文：运行中 reload、双 digest、内部工具的 ambient-config 隔离、reset/backup、optional grammar、XML override 和 generic CLI 来源；后续审阅又补齐 Permission 管理、Exec profile、金额估算、通知、approval aging、全部明文配置秘密的文件权限政策、raw shell 的宿主环境继承边界，以及资源简称、per-Model retry 配置面和过短 config-secret scanner 保证等条件契约。新增内容仍只是候选；负责人选择集中在 [决策包 05](decision-packets/05-model-configuration-network-selftest.md) 的 57 个正式 `M05-*` 组，编号最晚至 `M05-59`，并由其他 owner packet 中明确列出的条件组拥有各自产品轴。运行中配置观察的 `F4-01` 已由 D-048 收口为逐顶层 turn 自动载入；scheduler 仍集中在 [决策包 11](decision-packets/11-cross-system-operational-seams.md) 的 `F4-02`。本表不得把未选择的方案字段混成一份“全都支持”的 INI：每个条件字段必须标出 owner 选择，未命中的字段从 parser、REPL、help、XML projection 和 self-test 同时消失。

## 先统一几个通俗概念

### Schema 是配置的说明书，不是示例文件

Schema 负责回答“什么值才算合法”。config.ini 只是 Schema 的一个实例。建议由同一份版本化、typed schema 驱动：

- 内置默认值；
- INI 解析和逐字段校验；
- 跨字段校验；
- config-repl 与 model-repl 的字段帮助；
- 默认配置模板；
- show-config 的来源显示与秘密脱敏；
- Context XML 覆盖白名单；
- self-test 第一阶段；
- 配置迁移和废弃字段诊断。

否则很容易出现模板说允许、程序拒绝，或者 UI 忘记把新 secret 字段遮住。关联 AQ-131、CFG-18。

### 默认值、缺失值和空值不是一回事

候选规则：

- 字段“缺失”表示 INI 根本没有这个 key。
- 空字符串表示用户明确写了一个空文本。
- optional integer 的 unset 表示不设置用户上限或使用 provider 默认；最终 INI 拼写仍待 AQ-200 决定。
- required 字段缺失是结构错误，不允许实现时猜测。
- Schema 可以有“生成模板时写入的候选默认”，但正常 reader 是否允许省略该字段需要逐字段说明。

M05-19 需要冻结 optional scalar 的唯一 grammar。当前推荐候选是按含义使用不同 ASCII sentinel，而不是复用布尔值：

| sentinel | 精确含义 | 典型字段 | 不能被解释成 |
| --- | --- | --- | --- |
| `unknown` | 用户不知道该事实，Runtime 采用保守路径 | ContextLength | provider-default、0 |
| `provider-default` | 请求中不发送该 optional 参数 | MaxOutputTokens 或 adapter generation option | yaca 自己选一个数字 |
| `inherit` | Context 不覆盖 INI 值 | XML override | 缺失定义、允许任意上调 |
| `off` | 仅在该字段 schema 明确允许时关闭某项能力 | Streaming 等枚举的一部分 | unknown、无限 |

字段缺失、空字符串与这些 sentinel 仍分别定义。数字字段候选不再接受 `false`；旧 `false` 必须通过版本化迁移表解释，不能由消费者临场猜测。

### 配置来源与优先级

候选来源链如下：

    Runtime 不可降低的安全/资源硬上限
      -> typed schema 内置默认
      -> 完整用户 INI
      -> 当前 Context XML 白名单覆盖
      -> 注册过的命名 session action

仓库文件不属于配置来源。XML 只能选择或覆盖白名单会话值，不能带来 endpoint/Protocol 定义、registered config-secret value、代理定义或新的 Permission/Exec profile 定义。Model 切换、Permission 切换、DoubleCheck 覆盖和 ContextPrompt 编辑这类注册过的命名 session action 必须各自声明类型、生效点和是否形成 XML 事件；chat 中的实际 root 只由 TU-32 投影。是否再提供 generic `--set Section.Key=value` 是 M05-22 的负责人选择，在确认前不能把“当前命令参数”当成一个开放配置层。关联 CFG-01 至 CFG-03、AQ-159、CCA-Q-15。

### 生效点

本文使用四种生效点：

- bootstrap：在普通 Agent 启动之前决定；修改后需要重新装载应用服务。
- next-turn：不改变已经开始的 turn；下一 turn 重新冻结配置快照时生效。
- next-request：不改变在途 HTTP/进程；下一次同类请求生效。
- immediate-display：只影响之后产生的诊断显示，不改变领域事实。

候选总原则是：一个 active turn 冻结 Model、Permission、DoubleCheck、Prompt、工作目录、工具集合和预算。这里的顶层 turn 包括 main 与 side；它们各自在 admission 前观察配置。已经属于该 turn 的 child tool、review、retry 和其他内部 activity 始终沿用同一个 frozen snapshot，手工编辑 INI 不会在 turn 中途改变行为。关联 AQ-031、AQ-107、LOOP-15、D-048。

### 配置 generation 与运行中 reload

字段的 `next-turn`/`next-request` 只描述“新 generation 获准后何时消费”，不能替代“谁发现磁盘变化、坏文件怎么办”的生命周期。候选统一流程是：

~~~text
locate portable data root before reading INI
  -> parse bootstrap schema/version
  -> parse and validate the complete INI
  -> create immutable ConfigGeneration
  -> open Context and apply exact XML whitelist
  -> before every top-level main/side turn admission:
       read complete INI bytes and calculate private source digest
       unchanged -> reuse immutable ConfigGeneration
       changed -> parse + cross-validate the complete candidate
                  atomically publish one new ConfigGeneration
  -> freeze EffectiveTurnSnapshot
  -> child tools/reviews/retries consume only that snapshot
  -> write any non-secret effective transition to Context XML
~~~

`ConfigGeneration` 是 Runtime 内部版本化对象，不是 INI 字段。D-048 已确认每个顶层 main/side turn 的 admission 都完整读取 INI bytes 并计算 private source digest；不能只相信 mtime、size 或缓存的文件身份。digest 未变时复用现有 immutable generation；发生变化时自动全量 parse、逐字段和跨字段验证，并且只有完整候选通过后才原子激活新 generation。这个行为没有 watcher、reload interval、确认步骤或用户可调 policy field。

- active turn、它的 child tool/review/retry、在途 HTTP attempt 和已启动进程继续使用创建时 snapshot，不能逐字段热替换；
- 新 INI 必须作为完整文件 parse + cross-validate，一项错误就不能开始新 turn；
- 在 turn admission 观察到无效、删除或半写的文件，或当前 Model/Permission 已被删除、禁用、重命名或变得无效时，拒绝开始该 turn并指向对应 config/model self-fix；不能静默使用 last-known-good，也不能自动选第一项；旧 generation 只可让已经 active 的 turn 如实收口和支撑只读诊断；
- 只改注释会改变磁盘冲突身份，但若规范有效投影不变，不产生虚假的行为 transition；
- config-repl/model-repl 保存使用短期 writer lock、expected source digest 和同目录原子替换；锁只覆盖发布临界区，不覆盖用户编辑草稿的时间；
- REPL、普通 chat、self-test 和 show-config 共用一个 generation service，不各缓存一份 mutable table；
- 活动 Context 的 writer lock 不阻止独立的 model/config INI 编辑与原子发布；相反，另一个进程通过 context-repl 对该活动 Context 做 rename/rebind/delete/marker 等 mutation 必须返回 lock conflict，直到活动 writer 释放。

### private source digest 与 public effective digest

必须维护两个用途不同、绝不互换的 digest：

| 名称 | 输入 | 可以去哪里 | 禁止用途 |
| --- | --- | --- | --- |
| private source digest | 原始 INI bytes，包含所有 `source=config-file` secret 所在 bytes | 只在当前进程做外部修改/stale writer 检测 | XML、终端、日志、support、导出和 Model request |
| public effective digest | typed schema 规范化后的非秘密有效投影 | Context transition/snapshot、status、跨机映射证据 | 不包含任一 registered secret value、secret query 或 private equality fingerprint |

不能用“整份 INI 的 hash”同时完成两件事：即使 hash 不直接显示 secret value，它仍是 secret-derived identifier，会给离线比对和错误日志制造额外泄漏面。digest 算法、canonicalization、版本和字段投影必须进入 schema/测试元数据；本规则是技术不变量，不新增用户开关。

### Runtime 硬上限与用户上限

用户配置只能把资源预算调到 Runtime 允许的有界范围内，不能把队列、XML、HTTP event、工具输出或循环设成真正无界。Schema 中的 unset 只表示“没有更低的用户上限”，仍受发行物硬上限约束。硬上限应由旧机性能和故障测试确定，不一定全部暴露为配置字段。

## 注册表列说明

下列表格中：

- “缺失/默认候选”同时说明 reader 看见字段缺失时怎么办，以及生成新配置时建议写什么。
- “来源”说明字段能否来自 INI 或 XML。snapshot 表示 XML 只保存当时有效的非秘密投影，用于解释历史，不表示 XML 可以覆盖定义。
- “秘密”中的 conditional 表示值可能含凭据，例如带用户名密码的代理 URL。
- “未决”表示必须经过对应 AQ 确认；推荐值不是决定。

当前 Markdown 表为了可读性合并了一些列；它还不是可供实现直接加载的最终 schema。负责人答复后，每个保留字段必须补齐并由同一 registry 驱动 parser/REPL/help/self-test：稳定 field ID 与 introduced version、唯一领域 consumer、为何需要用户可调、完整 grammar/字节界限、missing/empty/sentinel、secret class、允许来源/merge、effective boundary、turn freeze/transition、migration、UI/redaction 以及 XP x86/CentOS 7 proof IDs。缺少任一项时只能继续标候选，不能让某个消费者自行补默认。

## General

| 字段 | 类型、单位与范围 | 缺失/默认候选 | 来源 | 秘密 | 生效点 | Context 快照 | 跨字段约束与状态 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SchemaMajor | ASCII 十进制整数，1..65535 | 缺失为硬错误；新文件候选 1 | INI only | no | bootstrap | 保存观察到的版本号 | 旧程序遇到更大 major 只读或拒绝写；格式仍待 AQ-185 |
| SchemaMinor | ASCII 十进制整数，0..65535 | 缺失为硬错误；新文件候选 0 | INI only | no | bootstrap | 保存观察到的版本号 | 更大 minor 只有在未知 required feature 不存在时才可读取；待 AQ-185 |
| SystemPrompt | UTF-8 文本；字节和估算 Token 都有硬上限 | 缺失候选等同空字符串；新文件写空值 | INI only | user-content | next-turn | 进入去重 Prompt snapshot，request 引用其 digest | 只能补充用户人格/偏好，不能覆盖 Runtime 规则；多行语法待 AQ-002、AQ-055、AQ-062、AQ-200 |
| StartupSelfTest | `off`、`stage1`、`stage2`、`stage3` | 缺失/新文件均为 `off` | INI only | no | 下一次普通 Agent 入口，Context 打开/创建前 | 不作 XML override；self-test 报告按 M05-35 处理 | `stageN` 严格表示从 Stage 1 顺序运行至 N，每次启动重跑而不复用永久 pass 缓存。Stage 1 除配置/依赖外还离线检查 Context codec、镜像目录与 workspace 可用性、Catalog/XML partial 状态、扫描 hard cap 及耗时预算；Stage 2/3 仍需展示本次外发/费用并确认，取消或 required stage 未通过就阻断 chat，但不阻断 help/version、管理 REPL 与显式 self-test |
| LogLevel | M05-17 A：error/warn/info/debug/trace；B：字段不存在；C：normal/trace | A 缺失/新配置为 info；C 为 normal；B 遇到旧字段给迁移诊断 | INI only | no | 载入完整新 generation 后的 next diagnostic event | turn 保存有效级别 | 只控制终端与 XML optional diagnostic；绝不能省略 canonical 对话、审批、工具或恢复事实；A/C 的 enum 不可混用 |
| SelfTestReviewerModel | **仅 M05-12 B 时存在**；引用一个 Model logical name | 缺失为 Stage 3 unavailable，不影响普通 Agent 或 Stage 1/2 | INI only | no | next self-test Stage 3 | 报告保存所选 reviewer 与当次 non-secret snapshot | 必须 enabled、在本次 Stage 2 通过；缺失/失败不 fallback；请求前仍需再次 consent |

候选不增加 Language、含糊的通用 Mode、Vivid、Theme 或自动更新字段。只有 TS-18 明确选择 B 时才在 Agent 中生成语义窄化的 `Autonomy`；它不是旧 `Mode` 的自动改名。固定 English UI、自动终端能力降级、无隐式遥测/更新已经有更简单的候选边界；是否正式删除旧字段见 AQ-157、AQ-246。

数据根位置也不建议放在 General。程序必须先找到配置才能读取该字段，会产生 bootstrap 循环；便携 zip 的数据根由发行布局决定，见 AQ-244。

`StartupSelfTest` 只是普通 Agent 入口的默认 gate，不改写显式 self-test 的单次参数。self-test controller 必须接收一份 typed run specification：`through_stage=1|2|3`、重复的 `excluded_models`、重复的 `excluded_checks`、可重复的 `selected_checks`；并提供不联网的 `list-checks` 动作让 CLI/REPL 发现 stable check ID。初次 run 永远从 Stage 1 开始，`through_stage=3` 不等于直跳 Stage 3；排除 required Model/check 会使结果成为 `partial`，不得进入 Stage 3 或满足启动 gate。启动 gate 自身总是全量 required scope，不消费持久 selection/exclusions；精确 argv 仍只由 TU-18 投影。Stage 3 在通过 Stage 2 的 Model 上审阅脱敏配置投影，其中包括 Permission 的名称、Description、SystemPrompt 与 capability matrix 是否语义相称，以及面向用户的自然语言拼写；它只能给 advisory，不能修配置或改变 Stage 1/2 结果。

## TUI

本 section 始终存在于完整配置 schema，但只承载相互独立的启动信息显示字段，以及 TU-27 B/C 时才生成的通知字段。启动信息没有 master switch；每个 `StartupShow*` bool 直接决定自己的那一行。它不承载 theme、vivid、language、快捷键、提示符或 renderer mode；chat ready 输入 `>>` 是固定 TUI 契约，不是配置字段。

| 字段 | 类型、单位与范围 | 缺失/默认候选 | 来源 | 秘密 | 生效点 | Context 快照 | 跨字段约束与状态 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| StartupShowSlogan / StartupShowVersion / StartupShowWorkDir / StartupShowDataRoot / StartupShowConfigStatus / StartupShowContext / StartupShowContextHash / StartupShowModel / StartupShowPermission / StartupShowDoubleCheck / StartupShowStatusHint | 各自独立 bool | 除 `StartupShowDataRoot=false` 外均为 true | INI only | no | 下一次启动头渲染 | 不保存 | 每个 enabled 字段独占一行并从行首开始；字段顺序和文案固定，不提供模板。Slogan 严格为 `yaca: Yet Another Coding Agent.`，StatusHint 只提示 `.status`。DataRoot 默认隐藏以减少日常噪声，ConfigStatus 是已发布 generation 的显示投影；新 Context 尚未产生 XML 时不伪造名称/hash，配置无效时仍使用固定 bootstrap error，machine renderer 忽略本字段族 |
| NotificationChannel | TU-27 B：off、bell；TU-27 C：off、bell、desktop、both | 缺失/新配置均为 off | INI only | no | next canonical event | 保存实际 channel、能力 generation 与结果；不作为 override | 不携带正文/路径/命令/secret；adapter 不可用只退回 transcript + 有界 warning；外来 XML 不能启用本机声音或 OS API |
| NotificationEvents | **仅 TU-27 B/C 且 TU-30 C 时存在**；固定 canonical event registry 的 typed allowlist | 缺失采用 TU-30 A 的 action-required 集合 | INI only | no | next canonical event | 保存实际 scope generation 和每个 event 的 once receipt | TU-30 A/B 使用固定集合且不得出现此字段；恢复/重绘/replay 不补发；每个 canonical event ID 至多通知一次 |

## Agent

| 字段 | 类型、单位与范围 | 缺失/默认候选 | 来源 | 秘密 | 生效点 | Context 快照 | 跨字段约束与状态 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DoubleCheck | bool；M05-39 C 时 required，否则新配置写所选默认 | 缺失/新文件行为由 M05-39 冻结 | INI default + XML tri-state override | no | next-turn | 保存 INI 默认、XML override 与最终值 | 开启包含结束复核；动作范围、失败与导入降级由 AL06/CX-14；不再有独立终止评估字段 |
| Autonomy | **仅 TS-18 选 B 时存在**；direct、explanatory | 缺失/新文件候选 direct | INI only | no | next-turn | 保存有效值与来源，不作为 XML override | 只控制 PP-06/PP-14/PP-15/PP-16 已允许文字块内的解释粒度和可选额外验证建议；不能增删消息、执行验证/工具、改变报告结构、Permission、DoubleCheck、必需验证、budget 或 control flow；A/C 下字段为 unknown/deprecated |
| ActionReviewModel | **仅 AL06-07 选 A/B 且 AL06-08 选 B 时存在**；引用一个 Model logical name | 缺失表示 action-review unavailable；绝不 fallback | INI only | no | next action-review | 保存 logical name、解析结果和实际 action-review request manifest | 必须 enabled；失效或跨 endpoint 未确认时 action-review 转 waiting-user；AL06-07 C 下字段为 not-applicable/orphan，不能影响 termination-review |
| TerminationReviewModel | **仅 AL06-49 选 B 时存在**；引用一个 Model logical name | 缺失表示 termination-review unavailable；绝不 fallback | INI only | no | next termination-review | 保存 logical name、解析结果和实际 termination-review request manifest | 必须 enabled；失效或跨 endpoint 未确认时 termination-review 转 waiting-user；独立于 AL06-07 动作范围和 ActionReviewModel |
| CompactionModel | **仅 AL06-11 选 A 且 AL06-30 选 B 时存在**；引用一个 Model logical name | 缺失表示 model-generated structured compaction unavailable；绝不 fallback | INI only | no | next-turn | 保存 logical name、解析结果和实际 request manifest | 必须 enabled 且能容纳最小 request；AL06-11 B 是 Runtime deterministic checkpoint、C 是 latest-fit，两者出现字段均为 orphan error |
| MaxModelRequests | **仅 AL06-42 选 A 时存在**；正整数，count/turn，1..RuntimeMax | 缺失候选 24 | INI；仅 M05-06 允许时 XML 可下调 | no | next-turn | 保存有效值与已消耗量 | AL06-42 B 使用 manifest fixed guard，出现本字段即 orphan error；side/review/compaction 归账服从 AL06-22/27 |
| MaxToolCalls | **仅 AL06-42 选 A 时存在**；非负整数，count/turn，0..RuntimeMax | 缺失候选 64 | INI；仅 M05-06 允许时 XML 可下调 | no | next-turn | 保存有效值与已消耗量 | 0 表示本 turn 禁止工具，不表示 Model 没有 native tool 能力；AL06-42 B 下字段不存在 |
| MaxTurnActiveTimeMs | **仅 AL06-42 选 A 时存在**；正整数，毫秒，1..RuntimeMax | 缺失候选 1800000（30 分钟 active time） | INI；仅 M05-06 允许时 XML 可下调 | no | next-turn | 保存单调 active-time 基准、有效值和已消耗量 | 只累计 scheduler/network/model/tool/review/compaction 的 Runtime active time；waiting-user、人工 approval、idle、OS suspend 不计；每个 request/tool 仍有自己的墙钟 deadline；AL06-42 B 改用 manifest fixed guard |
| MaxTurnTokens | **仅 AL06-42 选 A 时存在**；optional 正整数，normalized token/turn | 缺失候选 unset；仍受 Runtime hard cap | INI；仅 M05-06 允许时 XML 可下调 | no | next-turn | 保存有效值、已消耗量和 measured/estimated 标记 | 必须定义 main、side、DoubleCheck、compaction 的实际归账；AL06-42 B 不暴露字段；不等于费用上限 |
| MaxContextModelRequests / MaxContextToolCalls | **仅 AL06-09 选 B 时存在**；正整数/context，1..RuntimeMax | 缺失候选必须由长会话 fixture 提案 | INI only | no | next Context/open or next-turn policy generation | 保存 cap、累计量、来源和 exhausted outcome | A 下 Context 只 audit，字段为 orphan；Model switch/retry/review/compaction 不重置 ledger |
| MaxContextInputTokens / MaxContextOutputTokens | **仅 AL06-09 选 B 时存在**；正整数/context，1..RuntimeMax | 缺失候选由 fixture 提案 | INI only | no | next Context/open or next-turn policy generation | 分开保存 reported/estimated 累计量和 cap | 不把 token cap 称为费用 cap；provider usage 缺失用版本化保守估算 |
| MaxContextActiveTimeMs | **仅 AL06-09 选 B 时存在**；正整数毫秒/context，1..RuntimeMax | 缺失候选由 fixture 提案 | INI only | no | next Context/open or next-turn policy generation | 保存单调累计、cap 与恢复锚点 | waiting-user、人工 approval、idle、OS suspend 不计；达到后只允许本地管理/导出/显式提高或新 Context |
| MaxNoProgressRepeats / MaxNoProgressExactOrErrorRepeats / MaxNoProgressCycleRepeats / MaxNoProgressSemanticSteps | **AL06-50 A：全部不存在**；B：只存在 `MaxNoProgressRepeats`，为 Runtime 证明范围内的正整数；C：只存在后三个由版本化 detector registry 登记的正整数字段，分别覆盖 exact-repeat/same-error、cycle、semantic no-progress | A 使用发行 manifest 的完整 threshold tuple；B 的单值 default、C 的逐 detector default 均由同一技术 fixture/registry 冻结，不在本文拍数字 | INI only；XML 永不覆盖 | no | next-turn | A 保存 manifest identity + 实际 tuple；B 保存 effective scalar/source + detector version；C 保存完整 effective detector map、source + registry version | 三条字段族互斥；0/off/infinite、超 Runtime hard maximum、未知 detector key 或 active turn 热改都拒绝。算法、progress fingerprint/reset 与 exact 数字仍属 LOOP-05/技术证明；恢复 unfinished turn 使用原 frozen snapshot；AL06-28 独占命中后的收口 |
| MaxActionReviewRounds / MaxTerminationReviewRounds | **仅 AL06-27 选 A 时存在**；termination 字段始终存在，action 字段还要求 AL06-07 A/B；正整数，1..RuntimeMax | 缺失候选由预算 fixture 提案 | INI only | no | next-turn | 分别保存实际存在项的有效值 | AL06-07 C 下 `MaxActionReviewRounds` 是 orphan error；局部 cap 共同消耗 AL06-42 所选 configurable/fixed turn guard；不能无限 |
| MaxDoubleCheckRequests | **仅 AL06-27 选 B 时存在**；正整数，1..RuntimeMax | 缺失候选由预算 fixture 提案 | INI only | no | next-turn | 保存有效值 | action/termination 共用该局部 cap，并共同受 AL06-42 所选 turn guard 约束 |
| ApprovalExpiryMinutes | **仅 AL06-44 选 C 时存在**；正整数分钟，1..RuntimeMax | 缺失为配置错误；不能使用 off/infinite | INI only | no | next newly-created approval | 每个 approval 保存 created/expires 与配置 generation | 到期只生成 synthetic expired/denied result，绝不 allow；AL06-44 A/B 下字段为 unknown/deprecated；恢复规范化服从 AL06-45 |

金额字段只在 M05-50 C 下存在，并且估算门只在 AL06-43 B/C 下存在。M05-50 A 不生成任何金额字段；B 只消费 provider 明确返回的 amount/currency，也不生成本地价格字段。C 的字段进入每个 `Model.*`，不得从名称、endpoint 或联网价目表猜测。AL06-43 A 只显示 estimate；B 条件生成 `EstimatedCostWarning`；C 条件生成 `MaxEstimatedCost`。两者不能同时存在，币种必须与该 Model 的 `PriceCurrency` 完全一致，stale/缺失价格不能被称为精确费用。

AL06-42 选 B 时，turn safety guard 是发行物中有版本、有 fixture 的硬边界，不生成四个 turn `Max*` INI 字段；AL06-09 A 只保留 Context 累计 audit，B 才生成五个 `MaxContext*`；AL06-27 C 使用固定 review reserve。Queue、steer、side 的语义、Esc、协议纠错次数和是否自动开启下一 turn 是稳定产品行为，不做成大量开关；队列、side、纠错和事件泵仍有不可关闭的 Runtime 硬上限。若以后真实使用证明需要用户调低某个上限，必须把它作为有 consumer/source/snapshot 的 typed 字段重新过 catalog gate，不能先放一个通用 `Advanced`。

## Network

这里的 Network 主要配置 yaca 自己的 Model HTTP；仅当 TS-11 B/C 加入 direct HTTP tool 时，同一 section 还条件性出现带 `DirectHttp` 前缀的独立 policy。两套 CA/proxy/origin/credential 不互相借值。raw shell 启动的 curl 等程序仍属于 Exec/Permission，不能由本 section 假装拦截。

| 字段 | 类型、单位与范围 | 缺失/默认候选 | 来源 | 秘密 | 生效点 | Context 快照 | 跨字段约束与状态 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ProxyMode | M05-36 A：off/environment/explicit；B：off/explicit；C：off/environment | 三项缺失/新配置均为 off；environment 必须显式选择 | INI only | no | next-request | 保存模式名；environment 还保存当次 non-secret 来源投影 | explicit 要求 ProxyUrl；environment 必须在 generation 建立时解析成显式 snapshot，credential 登记为 `source=ambient-environment`，内部 curl 不自行读取 ambient proxy |
| ProxyUrl | **仅 M05-36 允许 explicit 时存在**；绝对 HTTP/HTTPS proxy URL | 缺失/空表示未配置 | INI only | conditional | next-request | 不保存值；最多保存“configured”和 non-secret origin 投影 | 只有 ProxyMode=explicit 时使用；userinfo 凭据以 `source=config-file` 进入 secret registry并服从 M05-54；AQ-145、SAFE-09 |
| NoProxy | **仅所选 ProxyMode 支持 proxy 时存在**；有序 host/domain/IP/port typed 规则列表 | 缺失候选空列表 | INI only | conditional | next-request | 只保存允许的投影与规则 digest | 禁止把 shell glob、Lua pattern 和 curl NO_PROXY 语法混为一谈；environment 模式也必须规范化成同一内部规则；AQ-145、NET-04 |
| CaMode | M05-37 A：bundled/system/custom/combined；B：bundled/custom；C：system/custom | A/B 缺失及新配置为 bundled；C 为 system | INI only | no | next-request | 保存模式、bundle/system adapter 版本 | custom 要求 CaFile；目标平台证明失败的 enum 不能只因 schema 写了就接受；永不提供 insecure/skip-verify |
| CaFile | 可读普通文件路径 | 缺失/空表示无 custom CA | INI only | conditional | next-request | 保存允许的非秘密规范路径投影和 digest | 仅含 custom 的 CaMode 合法；请求前 open/identity recheck；AQ-146、NET-02 |
| DirectHttpCaMode | **仅 TS-11 B/C 时存在**；enum 集合服从 M05-37 所选且目标发行证明可用的来源 | M05-37 A/B 下缺失/new=bundled；C 下=system | INI only | no | next direct HTTP call | 保存模式和 trust adapter/version | 值独立于 Model CaMode，不读取其 active value；没有 insecure/skip-verify；custom 要求 DirectHttpCaFile |
| DirectHttpCaFile | **仅 TS-11 B/C 且 DirectHttpCaMode 含 custom 时存在**；可读普通文件路径 | 缺失/空表示无 custom CA | INI only | conditional | next direct HTTP call | 保存规范路径投影/digest | 只供 direct HTTP tool，不能被 Model transport 暗读 |
| DirectHttpProxyMode | **仅 TS-11 B/C 时存在**；off/environment/explicit | 缺失/新配置 off | INI only | no | next direct HTTP call | 保存模式与 environment non-secret snapshot | 独立于 Model ProxyMode；environment 也在 generation 建立时冻结，credential 为 `source=ambient-environment` |
| DirectHttpProxyUrl | **仅 TS-11 B/C 且 DirectHttpProxyMode=explicit 时存在**；绝对 HTTP/HTTPS proxy URL | 缺失/空表示未配置 | INI only | conditional secret | next direct HTTP call | 不保存 credential；只存 configured/origin 投影 | 绝不复制 Model ProxyUrl/credential；userinfo 以 `source=config-file` 进入 direct-tool secret registry并服从 M05-54 |
| DirectHttpNoProxy | **仅 TS-11 B/C 时存在**；与 Network.NoProxy 共用 grammar 的有序规则 | 缺失空列表 | INI only | conditional | next direct HTTP call | 保存规则投影/digest | 只匹配 direct HTTP transport；不能改变 Model 或 raw shell |
| DirectHttpRedirectMode | **仅 TS-11 B/C 时存在**；deny/same-origin | 缺失/新配置 same-origin | INI only | no | next direct HTTP call | 保存有效值和实际 redirect chain | cross-origin 与 HTTPS->HTTP 始终拒绝；次数/循环仍有 hard cap |
| DirectHttpAllowedOrigin | **仅 TS-11 B/C 时存在**；exact normalized scheme+host+port 列表，无 wildcard | 缺失/空列表表示 direct HTTP 不可调用，但不阻断其他 Agent 能力 | INI only | conditional metadata | next direct HTTP call | 保存 matched rule/digest | HTTPS 可列入；HTTP 只允许可证明 loopback 且无 registered secret；call/approval 显示 exact origin |
| MaxHeaderKiB | **仅 M05-14 A/B 时公开**；正整数，KiB，1..RuntimeMax | 缺失候选需旧机 fixture 校准 | INI only | no | next-request | 保存有效值 | 所有 attempts 共同受 Runtime/turn 内存硬门；M05-14 C 时字段必须 unknown/deprecated |
| MaxEventKiB | **仅 M05-14 A/B 时公开**；正整数，KiB/SSE event，1..RuntimeMax | 缺失候选需 fixture 校准 | INI only | no | next-request | 保存有效值 | 还受 JSON 深度、tool argument 和 response 总硬门约束 |
| MaxBufferedKiB | **仅 M05-14 A/B 时公开**；正整数，KiB，1..RuntimeMax | 缺失候选需 fixture 校准 | INI only | no | next-request | 保存有效值 | 消费者落后时暂停读取或取消，不能无限 Lua table；AQ-245、CONC-03 |
| MaxCompressedBodyKiB | **仅 M05-14 B 时公开**；正整数，KiB，1..RuntimeMax | 缺失候选需 fixture 校准 | INI only | no | next-request | 保存有效值 | 约束压缩 wire body；不替代解压后与 logical response cap |
| MaxDecompressedBodyKiB | **仅 M05-14 B 时公开**；正整数，KiB，1..RuntimeMax | 缺失候选需 fixture 校准 | INI only | no | next-request | 保存有效值 | 必须与 ratio、buffer、logical response 组合校验 |
| MaxErrorBodyKiB | **仅 M05-14 B 时公开**；正整数，KiB，1..RuntimeMax | 缺失候选需 fixture 校准 | INI only | no | next-request | 保存有效值 | 错误正文仍需脱敏/截断，不因诊断需要解除 hard cap |
| MaxToolArgumentsKiB | **仅 M05-14 B 时公开**；正整数，KiB/call，1..RuntimeMax | 缺失候选需 fixture 校准 | INI only | no | next-request | 保存有效值 | 还受 JSON depth、batch 与 turn memory hard cap |
| MaxLogicalResponseKiB | **仅 M05-14 B 时公开**；正整数，KiB/logical request，1..RuntimeMax | 缺失候选需 fixture 校准 | INI only | no | next-request | 保存有效值 | 汇总 text/tool/reasoning/usage canonical bytes，不被 retry/fallback 重置 |
| MaxDecompressionRatio | **仅 M05-14 B 时公开**；正 decimal ratio，1..RuntimeMax | 缺失候选需 fixture 校准 | INI only | no | next-request | 保存有效值 | 与 compressed/decompressed cap 同时执行，不能单独调大绕过内存门 |

候选固定而不配置的安全规则：

- 不提供 SkipTlsVerify 或 Insecure。
- `http://` 与 Key/SecretHeader 的组合由 M05-13 选择；在选择前不能把“URL 语法合法”当成“允许发送”。当前推荐候选仅允许强制 direct/bypass、无鉴权且可证明的 loopback HTTP。
- redirect 由 M05-38 冻结；无论选择哪条路线，credential 永不跨 origin，HTTPS 降级必须服从 M05-13 且不能携带 secret，次数/循环/正文都有硬门。
- curl 自带 retry 必须关闭，由 Model/Runtime 记录 request/attempt 后决定。
- 启动、配置浏览、Context 浏览和离线 self-test 不隐式联网。
- compressed body、decompressed body、error body、tool arguments、logical response total 和 decompression ratio 都有 Runtime hard cap；M05-14 只决定其中哪些成为可调低的 INI 字段。

Runtime 内部 curl 不继承宿主 `.curlrc`/`_curlrc`、`.netrc`、HOME 定位、隐式 proxy/CA 环境或 cwd/PATH 同名工具。它使用发行 manifest 中的绝对路径、首参数禁 default config、完整显式 CA/proxy/redirect/protocol/output 规则和受控 stdin。这个 ambient-config 隔离是 `HCFG-04` 技术不变量，不增加 `InheritCurlConfig` 开关；最终随包 curl 在 XP x86/CentOS 7 是否能兑现必须用恶意 canary 实测。

## Exec

Exec 的**资源字段**形态由 M05-51 独占：A 把两个资源字段放在 singleton `[Exec]`；B 不生成资源字段；C 使用一个或多个 `[ExecProfile.<LogicalName>]`，section 物理顺序第一项是新 Context 的默认 profile。M05-15 B 的全局环境字段始终属于 singleton `[Exec]`，不因 C 而复制到 profile；因此 B/C 下 `[Exec]` 仍可能因环境配置而存在，但不能混入资源字段。M05-15 A/B 中 `inherit` 的宿主变量成员政策由条件组 M05-55 冻结为发行版契约，不产生另一个自由文本 INI 字段；M05-15 C 及 B 中的 `clean` 使用版本化最小环境，M05-55 为 `not-applicable`。C 下 profile **只有完整逻辑名，没有 Abbreviation 字段**；逻辑名服从 ASCII 唯一性规则，config-repl 提供完整管理事务，命令只接受 exact name。当前 Context 只保存 `CurrentExecProfile` 选择器和当时的非秘密 profile snapshot，不能在 XML 定义或改写 profile 字段。该 selector 只能由 TU-32 条件命令的用户 action 在 next-turn 边界 use/reset；reset 把当前 INI 第一项的精确名称写成新 selector，不保留一个随后可因 reorder 漂移的空选择。模型可见 exec 接受原始命令；底层 Process port 仍以结构化 executable/argv 启动平台 shell。

| 字段 | 类型、单位与范围 | 缺失/默认候选 | 来源 | 秘密 | 生效点 | Context 快照 | 跨字段约束与状态 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| MaxExecTimeMs | **仅 M05-51 A/C 时存在**；positive integer，毫秒/call | 缺失候选 600000（10 分钟）；仍受发行 Runtime hard cap | A 为 `[Exec]`；C 为每个 `[ExecProfile.<Name>]` | no | next tool call / next-turn snapshot | 保存有效值、section identity 与来源 | 每次调用 wall-clock deadline 与 turn active-time guard 取更早者；C 的 tool call 只能请求比所选 profile 更短的值；AQ-126、AQ-147 |
| MaxOutputKiB | **仅 M05-51 A/C 时存在**；positive integer，stdout+stderr canonical captured bytes 合计 | 缺失候选 128 KiB；仍受 Runtime hard cap | A 为 `[Exec]`；C 为每个 `[ExecProfile.<Name>]` | no | next tool call | 保存有效值、section identity 与 observed/captured/discarded | 达到 cap 后仍 drain-and-discard 两条 pipe；结果标 truncation；C 的 tool call 不能换 profile；TUI preview 另有独立队列上限 |
| EnvironmentMode | **仅 M05-15 选 B 时存在**；枚举 inherit、clean | 缺失候选 inherit | INI only | no | next tool call | 保存模式、M05-55/clean baseline identity、公开变量名集合与非秘密 digest，不复制变量值 | inherit 精确使用 M05-55 所选且随发行版本化的 baseline；A 固定使用同一所选 baseline、C 固定 clean，都没有此字段；clean 仍需 Runtime 最小 PATH/TEMP 契约 |
| EnvironmentSet | **仅 M05-15 选 B 时存在**；有序 NAME=value 列表，名称 ASCII；所有 value 一律按 `source=config-file` secret 处理 | 缺失候选空列表 | INI only | yes（每项 value） | next tool call | 只保存 canonical 变量名、configured 标志和不含值的集合 digest | 不能覆盖 Runtime 保留变量；值不进 XML/public digest/诊断/clone/export；与 unset/重复名冲突整代 error；AQ-148、SAFE-09 |
| EnvironmentUnset | **仅 M05-15 选 B 时存在**；有序 ASCII NAME 列表 | 缺失候选空列表 | INI only | no | next tool call | 保存 canonical 名称列表 | 合成顺序固定为 baseline→unset→set→reserved/size validation；Windows 名称按不区分大小写 key、Linux 按精确 ASCII；重复或同名 set/unset 为硬错误，不 last-wins；AQ-148 |
| ShellDialect | **仅 TS-13 选 C 时存在**；目标平台注册的 ASCII enum | 缺失候选目标平台规范 shell | INI only | no | next tool call | 保存 exact dialect/adapter ID | 只能选择随平台发布并通过 quoting/cancel/encoding 证明的 allowlist，不接受任意 executable 路径 |

`TerminateGraceMs` 与全局 `OutputEncoding` 不进入 INI、XML override 或 session parameter schema：

- 终止 grace 是各平台 Process adapter 的版本化常量，由最终发行 zip manifest 携带，并由子进程树/取消技术证明冻结。status、self-test 和 operation result 可以只读显示实际 adapter ID 与 grace；用户不能把它调成无限或绕过 unknown 结果。
- 输出解码完全服从 TS-38：A 使用 spawn 时平台 encoding snapshot，B 严格 UTF-8，C 仅在 TS-23 A 的 typed per-call envelope 中从发行 allowlist 选择 decoder。三项都严格解码，失败形成 typed binary，不做 replacement 冒充原文；这个逐调用字段不是 INI 配置，也不能通过 generic override 偷渡。

候选永不公开任意 `ShellProgram` 路径。TS-13 A 固定目标 OS 的 `cmd.exe`/`/bin/sh`，B 由每个发行 zip manifest 固定一个不可切换的 canonical dialect；只有 C 出现上面的 typed `ShellDialect`，且选项来自发行 allowlist。任意路径会同时改变 quoting、取消、ambient config 和安全说明，不能借 generic 配置字段绕开 adapter 证明。stdout/stderr 是否保存 observed cross-stream sequence 是 TS-22 的结果契约，不产生配置字段。

以下规则不可关闭：

- 输出、时间、进程数量和进程树始终有硬门；stdin 只采用 F4-07 的 EOF 或有界 immutable `stdin_text` 路线；v0.1 两条路线都不支持继承 TUI stdin、交互 PTY/console，也不生成对应配置；
- 每次调用显式 cwd，默认是 turn 冻结工作目录；
- 取消尝试终止进程树，无法证明时结果为 termination-uncertain；
- raw shell 不承诺工作区、网络或文件隔离。

M05-15 若选择推荐 A，三个环境字段全部从正式 schema 删除；选择 C 时也不出现这些字段，而由 Runtime 固定 clean baseline。不存在 `ExposeConfiguredProxy`：任何选项下全局 proxy/credential 都不自动传播给 raw shell。内部 curl/Git/helper 永远不使用 raw-shell 环境：它们服从 `HCFG-04`，不能因 M05-15 的选择而读取用户 curlrc、Git external diff、pager、credential helper 或隐式 CA。

## Context

Context section 只配置用户体验和预算偏好。自动保存、canonical durable 屏障、XML 验证、损坏隔离和 no-replace 不应成为可以关闭的普通配置。

| 字段 | 类型、单位与范围 | 缺失/默认候选 | 来源 | 秘密 | 生效点 | Context 快照 | 跨字段约束与状态 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AutoNameEveryMainTurns | non-negative integer，turn count，0..RuntimeMax | 缺失/新配置均为 10；0 关闭 | INI only | no | 下一个空闲命名调度点；在途请求冻结旧 interval，但仍受当前 marker/cancel gate | 保存实际 interval、已完成 main-turn count、触发水位、request/result/cancel 与 old/new name；不作 XML override | D-041/D-046 周期命名：只计成功收口且已持久化的 main turn，side/review/tool 迭代/self-test/失败或取消 turn 不计；每个阈值最多尝试一次低优先级、无工具 `context-name` request，新 main、退出、取消、超时或 marker 变 true 可使其取消/失效且不阻塞。初始 basename 是 `Untitled Conversation [XXXX]`，`XXXX` 为四位大写 hex 随机后缀并使用 bounded retry + no-replace；它不是永久 ID，也不是路径派生的 16 位 hash。当前 Context 的 `AutoRenameDisabled=true` 时不 admission；context-repl 取消标记会建立新的调度基线，不立即命名或追补；失效后的迟到结果不得采用 |
| ListSortBy | `created`、`updated`、`name` | 缺失/新配置均为 `updated` | INI only | no | 下一次 Context 列表 render | 不保存 | `created`/`updated` 只读取 XML canonical `CreatedAt`/`UpdatedAt`：前者在初次 durable 创建时固定，后者在每次成功发布的 durable XML mutation 中原子推进，失败/inspect 不推进；绝不使用文件系统 ctime/mtime。`name` 使用规范 Context 名。相等时以 `LogicalPath` 作确定性 tie-break。只影响 context-repl/`.context` 等列表投影，不改变 Resolver、搜索命中顺序或裸 `yaca` 的不扫描历史契约 |
| ListSortDirection | `ascending`、`descending` | 缺失/新配置均为 `descending` | INI only | no | 下一次 Context 列表 render | 不保存 | 只反转 `ListSortBy` 主键；完全相同主键始终用 canonical `LogicalPath` 稳定升序 tie-break，使分页和刷新不随方向翻转相同项。默认组合为 `updated` + `descending`，即最近更新在前。缺失/非法 canonical timestamp 形成 typed Context compatibility/self-fix 结果，不 fallback 到文件系统时间 |
| CompactThreshold | **仅 AL06-11 选 A/B 时存在**；decimal ratio，0 < value < 1 | 缺失候选 0.75 | INI；M05-06 B/C 才允许 XML 下调 | no | next-turn / next compaction/checkpoint check | 保存有效值与 A structured-summary/B deterministic-checkpoint consumer | C 只做 latest-fit view，不生成 threshold 字段；触发计算还要扣除 Prompt/tool/output reserve |
| MaxContextMiB | **仅 CX-11 选 B 时存在**；positive integer，MiB | 缺失候选由 Runtime hard ceiling/fixture 提案且只能更低 | INI only | no | Context create/open/next commit admission | 保存有效值和 hard ceiling identity | 单 active XML 软配额；达到后 fail-stop/只读，不静默删历史 |
| MaxActiveContexts | **仅 CX-11 选 B 时存在**；positive integer，count | 缺失候选由 fixture 提案且只能低于 Runtime cap | INI only | no | next create/archive/restore | 保存有效值 | 只计 active；archive 可降低此计数，但仍计总量 |
| MaxContextTotalMiB | **仅 CX-11 选 B 时存在**；positive integer，MiB | 缺失候选由 fixture 提案且只能低于 Runtime cap | INI only | no | next Context mutation/commit admission | 保存有效值和扫描 generation | active/archive/trash 全计入；超额不自动删除 |
| AutoPurgeTrash | **仅 CX-11 选 C 时存在**；bool | 缺失/新文件 false | INI only | no | next maintenance scan | 保存值、generation 与每次 purge plan/result | true 要求 TrashGraceDays；只处理可证明属于 trash 的 item，不能触及 active/archive |
| TrashGraceDays | **仅 CX-11 选 C 且 AutoPurgeTrash=true 时 required**；positive integer days，1..RuntimeMax | false 时字段必须缺失；true 时无隐式默认，由 config-repl 要求用户输入 | INI only | no | next maintenance scan | 保存有效值和每项 durable trashed_at/eligibility | 无可靠 trashed_at、锁定、stale scan 或预告失败都不得 purge |

`CompactReserveTokens` 与 `MaxScanEntries` 也不属于配置 schema：

- compaction/view builder 每次按有效 Model 窗口、最大输出、固定 Prompt、tool schema、当前不可拆原子组和估算误差计算只读 effective reserve；Model/view 变化就重新计算。INI 与 XML 都不能设置它。request/view manifest 可以记录本次派生值、输入摘要与算法版本作为历史证据，但它不是可恢复的会话偏好。
- Resolver 的扫描量由各发行 zip manifest 与 Runtime 共同执行不可放宽的 hard cap；数值由目标旧机的复杂度、内存和响应测试冻结。context-repl/status/self-test 只读显示当前 cap 与 manifest identity；命中上限返回 `ScanLimit`/incomplete，不把未扫描范围报告为不存在。

候选不放 RootDir、AutoSave、RepairOnOpen、ExportSecrets 或通用 RetentionDelete；只有 CX-11 C 才有上表严格限于 trash 的两个 auto-purge 字段：

- RootDir 在配置加载前就必须确定，见 AQ-244。每个 Context 的唯一 workspace root 也不是 INI/XML 字段：它由 active XML 在 `__yaca__/CONTEXT/` 镜像树中的父目录解码。
- 旧 `AutoNameOnExit` 与 `SuggestContextNameAfterFirstTurn` 不能直接迁成新字段；它们分别表达退出时/终身一次，而 `AutoNameEveryMainTurns` 表达已完成 main turn 的周期调度。迁移器只显示候选，不猜 interval 或是否覆盖手工名称。
- AutoSave=false 会破坏 XML 作为核心事实源的恢复契约。
- 损坏修复必须保守且留证据，不能按偏好静默截断。
- export 每次都应显式预览。
- 自动年龄删除与“完整接盘”冲突，若未来需要保留策略应独立讨论。

## Permission.*

section suffix 是本地逻辑名称，例如 Permission.Std。它本身就是用户选择器，不再重复保存 Name 字段。所有 Permission section 都必须完整有效，不设置 Enabled；物理顺序第一项是新 Context 默认项，见 D-021、AQ-037、AQ-134。

Model/Permission 的第二选择器只由 M05-57 决定：A 完全不生成 `Abbreviation`；B 允许显式 optional 值；C 要求每个 Permission 和 enabled Model 存在，disabled Model 草稿可暂缺但启用前必须补齐。三条路线都把 logical name 当 D-029 下的 Unicode user data：必须是非空 well-formed UTF-8 scalar sequence，不含 NUL/CR/LF、ASCII control、INI section delimiters `[`/`]` 或首尾 ASCII whitespace；内部空格、点、连字符、下划线与其他有效非控制 Unicode scalar 保留。显示原始 UTF-8 拼写，比较时只 fold ASCII `A-Z`，其他合法 bytes 精确比较；Model 与 Permission 分属两个 namespace。最大 bytes、section parser/writer round-trip 和跨平台 vectors 由 TP-019 冻结，不能随 locale/codepage/filesystem 改写。B/C 中同类型全部 logical name/Abbreviation 共用一个折叠 namespace，简称不能与自己的长名折叠相同。用户输入简称后先解析并冻结完整 logical name；CurrentModel/CurrentPermission 永远写完整名，简称只可作为非秘密历史说明，不能成为永久 ID。ExecProfile 不受 M05-57 影响，继续只有完整名。

每个能力字段候选使用 deny、confirm、allow 三态。缺失是硬错误，不按字段默认，以免新增安全能力时旧 profile 被静默放行。关联 AQ-149、AQ-150。

| 字段 | 类型、单位与范围 | 缺失/默认候选 | 来源 | 秘密 | 生效点 | Context 快照 | 跨字段约束与状态 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Abbreviation | **仅 M05-57 B/C 存在**；1..16 个 ASCII letter/digit/hyphen，首字符 letter | B 缺失合法且不得暗中生成；C 的 Permission 缺失为硬错误；A 下字段为 unknown/deprecated | INI definition；XML 当前选择只写完整 section logical name | no | next-turn | B/C 可在非秘密 policy snapshot 中保存当时简称；不作为 selector identity | 与 Permission namespace 内全部长名/简称 ASCII-fold 后唯一，且不能等于自己的长名；M05-57、AQ-135、AQ-199 |
| Description | UTF-8 user text，0..256 bytes | 缺失候选空字符串 | INI definition | user-content | next-turn | 保存非秘密文本或 digest；待定 | 名称/描述不决定真实安全语义；self-test 第三阶段只能 advisory；AQ-202 |
| SystemPrompt | 有界 UTF-8 user text，共用 General.SystemPrompt 的唯一多行 grammar | 缺失等于空字符串 | INI definition only | user-content | next-turn | 作为独立 Permission Prompt component 保存实际文本/digest、profile 与 transition；不作 XML override | 只是模型行为提示，不是授权证据；名称、Description 或本文本声称 `allow` 都不能扩大 Read/Write/Delete/Shell/条件能力矩阵。在指令链中的精确位置由 PP-03，purpose 可见性由 PP 契约/数据分类收口 |
| Color | **仅 M05-21 B 才存在**；basic 8/16-color ASCII enum | 缺失由 TUI 确定性分配 | INI definition | no | next-turn/display | 保存枚举 | 只影响 Permission label；颜色不能是唯一语义，语义角色/后备由 TU-02；A/C 时删除 |
| Read | deny/confirm/allow | 缺失硬错误 | INI definition | no | next-turn | 保存有效值 | 只约束 yaca 直接 read/list/search；raw shell 不受它隔离 |
| SensitiveRead | **仅 M05-56 B 才存在**；deny/confirm/allow | 若存在则缺失硬错误，内置模板候选 confirm | INI definition | no | next-turn | 保存有效值与分类器版本/原因 | 字段存在性由 M05-56；分类来源与 `Read` 的更严格求值由 TS-21；未命中绝不表示安全；与 M05-16 的 outside 粗/细选择正交 |
| Write | deny/confirm/allow | 缺失硬错误 | INI definition | no | next-turn | 保存有效值 | 约束直接 create/write/patch；raw shell 仍只看 Shell |
| Delete | deny/confirm/allow | 缺失硬错误 | INI definition | no | next-turn | 保存有效值 | delete/replace-existing/rename source 的映射需工具表冻结；AQ-117、AQ-118 |
| Shell | deny/confirm/allow | 缺失硬错误 | INI definition | no | next-turn | 保存有效值及“broad capability”标志 | 一旦允许，Runtime 不能证明命令不写文件、不联网或不越界；AQ-224 |
| DirectNetwork | **只有 TS-11 B/C 选择 direct HTTP tool 时存在**；deny/confirm/allow | 若存在则缺失硬错误，内置模板候选 confirm | INI definition | no | next-turn | 保存有效值 | 这是 direct HTTP 的必需真实消费者字段；不由 M05-16 再开关，不约束 Model provider HTTP，也不能隔离 raw shell；NET-11 |
| OutsideWorkspace | **仅 M05-16 选 A 时存在**；deny/confirm/allow | 缺失硬错误 | INI definition | no | next-turn | 保存有效值 | 作为 direct Read/Write/Delete 的共同 modifier，与基本能力取更严格结果；不能单独表达外读/外写差异 |
| OutsideRead | **仅 M05-16 选 B 时存在**；deny/confirm/allow | 缺失硬错误 | INI definition | no | next-turn | 保存有效值 | 与 Read 取更严格结果；链接目标按真实规范路径判定 |
| OutsideWrite | **仅 M05-16 选 B 时存在**；deny/confirm/allow | 缺失硬错误 | INI definition | no | next-turn | 保存有效值 | 与 Write 取更严格结果；raw shell 不受它隔离 |
| OutsideDelete | **仅 M05-16 选 B 时存在**；deny/confirm/allow | 缺失硬错误 | INI definition | no | next-turn | 保存有效值 | 与 Delete 取更严格结果；rename/replace 映射由 tool matrix 冻结 |

候选内置 profile 只是生成模板，不让名称决定含义：

| Profile | Read | Write | Delete | Shell | Outside（按 M05-16 A/B 展开） | SensitiveRead（仅 M05-56 B） | DirectNetwork（仅 TS-11 B/C） |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Std | allow | confirm | confirm | confirm | confirm | confirm | confirm |
| Trusted（仅 TS-04 选择提供第三预设时） | allow | allow | allow | allow 或 confirm，依 TS-04 | allow | allow | allow |
| Readonly | allow | deny | deny | deny | deny | confirm | deny |

以上具体矩阵仍待负责人确认。Cautious 不是 profile，DoubleCheck 不出现在 Permission section。上表只是 TS-04、M05-16、M05-56 与 TS-11 组合后的生成示意：M05-16 B 把 outside 展开成三列；只有 M05-56 B 才生成 SensitiveRead 列，并继续服从 TS-21；若没有 direct HTTP tool，DirectNetwork 列必须完全消失，而不是保留一个永远无消费者的 deny。

候选删除 AllowRegex/ExcludeRegex。正则无法证明复合 shell 的副作用；若保留，只能作为附加 deny/warn 规则，绝不能凭匹配授予原本没有的能力。关联 SAFE-07、AQ-224。

## Model.*

section suffix 是 yaca 本地 Model 逻辑名，例如 Model.DeepSeek。一个 section 自含协议、endpoint、远端模型、Key、能力、超时和 retry，落实 B-06/AQ-016。不要再添加另一个含义模糊的 Name；远端 ID 使用 RemoteModel。

| 字段 | 类型、单位与范围 | 缺失/默认候选 | 来源 | 秘密 | 生效点 | Context 快照 | 跨字段约束与状态 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Enabled | bool | 缺失硬错误；新建内存修复草稿候选 false | INI definition；XML 只选逻辑名 | no | next-turn | 保存当时值 | 零个有效 enabled Model 或物理第一 Model disabled/不完整时，整份配置不得发布为普通 Agent ConfigGeneration，也不跳到后项；model/config-repl 只可保持未发布 repair draft。disabled 完整度严格服从 M05-08：A 至少有 Protocol，B 除 Key 外与 enabled 同样完整，C 与 enabled 同样完整但不要求在线测试；所有已出现值仍全量校验 |
| Abbreviation | **仅 M05-57 B/C 存在**；1..16 个 ASCII letter/digit/hyphen，首字符 letter | B 始终 optional；C 的 enabled Model 必填、disabled 草稿可缺失但启用事务必须先补齐；A 下字段为 unknown/deprecated | INI definition；XML 当前选择只写完整 logical name | no | next-turn | B/C 已存在时可保存逻辑名与当时简称；缺失草稿只保存逻辑名 | 与 Model namespace 内全部长名/简称 ASCII-fold 后唯一，且不能等于自己的长名；M05-08 不再决定简称 requiredness；M05-57、AQ-135、AQ-199 |
| Description | UTF-8 user text，0..256 bytes | 缺失候选空字符串 | INI definition | user-content | next-turn | 保存文本或 digest，待数据分类 | 不用于自动判断 provider/model 是否匹配；AQ-202 |
| CustomPrompt | **仅 PP-11 选 B/C 时存在**；有界 UTF-8 user-configured text | 缺失候选空字符串 | INI definition only | user-content | next-turn | 保存完整 Prompt component snapshot/digest、PP-03/PP-11 route 与 Model transition 引用 | B 是 Model-specific 用户默认：PP-03 A/B 下位于 adopted rules 与 SystemPrompt 之间，PP-03 C 下加入持久冲突集合；C 是低于 SystemPrompt/其他持久层的 compatibility hint；两者都低于当前明确用户要求和 Runtime，C 不能改 serializer/role/tool/control/purpose/权限；A 下字段必须 unknown/deprecated |
| Color | **仅 M05-21 B/C 才存在**；basic 8/16-color ASCII enum | 缺失由 TUI 确定性分配 | INI definition | no | next-turn/display | 保存枚举 | 只影响 Model label；颜色非语义，TU-02 拥有语义角色/后备；A 时删除 |
| Protocol | 稳定 ASCII enum；首版候选 openai-chat | enabled 及所有 M05-08 disabled 路线均为 required | INI definition | no | next-turn | 完整保存 | 不从 Endpoint 猜；v0.1 是否只支持一种见 AQ-138、AQ-218 |
| Endpoint | M05-33 A：完整请求 URL；B：origin/base URL；C：可含部署前缀的 base URL；长度受限 | enabled、M05-08 B/C 时缺失/空为硬错误；A 的 disabled 可暂缺 | INI definition | conditional | next-turn / next request | 仅保存 M05-20/M05-32 允许的 secret-aware 非秘密投影与 public digest | adapter 不得猜未被 M05-33 选择的 path 规则；HTTP/Auth/Proxy、userinfo/query secret 与 redirect 由 M05-13/36/38 冻结 |
| ApiPath | **仅 M05-33 选 C 时存在**；以 `/` 开始的受限 path，不含 scheme/host/query/fragment | enabled 以及 M05-08 B/C disabled 时缺失为硬错误；M05-08 A disabled 可暂缺 | INI definition | conditional | next-turn / next request | 保存允许的规范 path 投影与 digest | 与 Endpoint 只按唯一规范算法拼接；不能覆盖 origin、携带 secret 或使用 `..` 猜部署路径；所有 adapter-required conditional fields 都必须逐行服从同一 disabled 完整度规则 |
| RemoteModel | UTF-8/ASCII provider model ID，1..512 bytes | enabled、M05-08 B/C 时缺失/空为硬错误；A 的 disabled 可暂缺 | INI definition | conditional | next-turn | 保存非秘密投影 | 不能从本地 section 名推断；AQ-136 |
| AuthMode | M05-02 A：protocol/none；B：再加 adapter 注册的 typed auth enum；M05-02 C 时字段不存在 | 缺失候选取决于 M05-02；未确认前不冻结 | INI definition | no | next-turn | 保存枚举/adapter identity | 空 Key、header 名和 none endpoint 全由 adapter schema 校验；自由 header 不得冒充 Runtime auth |
| AllowPlainHttp | **仅 M05-13 选 B/C 时存在**；bool，逐 Model 风险确认 | 缺失 false | INI definition | no | next-turn / first request to origin | 保存选择、实际 origin class 与确认事件 | 只放开 M05-13 已选定的 private/any scope，永不放开 Key/SecretHeader/proxy credential 的 HTTP 发送；A 时字段必须不存在 |
| Key | 任意非 NUL 文本；字节上限 | 缺失候选空；enabled 与 M05-08 C 按 M05-02 选中的 auth/adapter schema 校验，M05-08 B 的 disabled 可暂缺 | INI definition only | yes | next-turn / next request | 永不进入 XML、public effective/Model snapshot digest、诊断或支持输出 | private source digest 只留进程内；明文风险与 carrier 证明见后文；AQ-017、AQ-040、SAFE-09 |
| ContextLength | optional positive integer，tokens | 缺失候选 unknown | INI definition | no | next-turn | 保存值及 declared/observed 来源 | unknown 进入保守预算；必须大于必要 Prompt/工具/输出余量；AQ-142 |
| MaxOutputTokens | optional positive integer，tokens | 缺失候选 provider-default | INI definition | no | next-turn | 保存有效值 | 已知 ContextLength 时必须更小；provider 实际 cap 可进一步限制；MODEL-08 |
| PriceCurrency / PriceAsOf / PriceSourceLabel | **仅 M05-50 C**；currency 为固定 ASCII code，as-of 为明确日期/版本，source label 为有界用户证据文字 | 任一 required metadata 缺失表示本地估算 unavailable | INI definition | conditional metadata | next-turn / next request | 每个 request 保存 price generation、currency、as-of/source digest | 不联网抓价，不从 Model 名/endpoint/品牌猜；source label 不成为权威价目表 |
| PriceInputPerMillion / PriceOutputPerMillion / 条件 cache/reasoning rates | **仅 M05-50 C**；非负 decimal，固定每百万 token 单位；额外类别只在 adapter usage taxonomy 明确支持时存在 | required 类别缺失表示该 request 无法保守估算 | INI definition | no | next-turn / next request | usage event 分开保存 estimated/reported、rate generation 和实际类别 | rounding/上界算法版本化；M05-50 A/B 下全部为 unknown/deprecated |
| EstimatedCostWarning | **仅 M05-50 C + AL06-43 B**；与 PriceCurrency 同币种的非负 decimal/turn | 缺失表示该 Model 不启用金额 warning | INI definition | no | next-turn / request admission | 保存阈值、累计 estimate、worst-case increment 或 unavailable reason 与 consent receipt | 配置了 threshold 但 price/usage stale、类别缺失或无法保守估算时，必须对 exact next request 显示 `estimate unavailable` 并 fresh consent，不能当作未跨阈值；只形成知情确认，不替代 request/token/time hard guard；不能与 MaxEstimatedCost 同时存在 |
| MaxEstimatedCost | **仅 M05-50 C + AL06-43 C**；与 PriceCurrency 同币种的正 decimal/turn | 缺失表示该 Model 不满足金额 hard-admission 路线 | INI definition | no | next-turn / request admission | 保存 cap、累计 estimate、worst-case increment 与拒绝原因 | price/usage stale、类别缺失或无法保守估算时 fail-closed；无模糊 override；不能与 EstimatedCostWarning 同时存在 |
| Streaming | enum force、try、off | 缺失候选 try | INI definition | no | next-turn / next request | 保存值与实际使用模式 | force 不可静默降级；try 只在任何规范响应事件前按明确能力错误回退；AQ-018、AQ-139、AQ-198 |
| Tools | M05-03 A：native/off；B：字段不存在，Protocol adapter 静态必须 native；C：native/off/required-native | A/C 的缺失行为由选择冻结；B 遇到字段为 unknown/migration diagnostic | INI definition | no | next-turn | A/C 保存声明与 observation；B 保存 adapter manifest capability snapshot | 不做文本 emulation；B 的在线 observation 只 support/warn，不是启用 gate；M05-26 及无工具 main eligibility 仅在 A/C 的 Tools=off 下存在，B 下强制 not-applicable |
| PublicReasoning | **仅 M05-40 C 时存在**；off/summary/full-public，且 enum 受 Protocol adapter capability 约束 | 缺失候选 off | INI definition | user-content policy | next-turn / next request | 保存选择、实际公开 kind 与来源 | A 自动消费明确公开 summary 而无字段，B 完全不消费；任何路线都不请求/伪造 hidden reasoning |
| ConnectTimeoutMs | **M05-04 A/B 时公开**；positive integer，毫秒 | 缺失候选由网络 fixture 提案 | INI definition | no | next request | 保存有效值 | 不得越过 logical/turn deadline；M05-04 C 时字段不存在 |
| FirstEventTimeoutMs | **M05-04 A/B 时公开**；positive integer，毫秒 | 缺失候选由网络 fixture 提案 | INI definition | no | next request | 保存有效值 | 从 request 发送完成到首个 canonical event；M05-04 C 时字段不存在 |
| IdleTimeoutMs | **M05-04 A/B 时公开**；positive integer，毫秒 | 缺失候选由网络 fixture 提案 | INI definition | no | next request | 保存有效值 | 只有有效 canonical event 重置；M05-04 C 时字段不存在 |
| TotalTimeoutMs | **仅 M05-04 A 时公开**；positive integer，毫秒/logical request | 缺失候选由网络 fixture 提案 | INI definition | no | next request | 保存有效值 | 覆盖 attempts 与 backoff，且受 turn deadline；不能在每 attempt 重置 |
| MaxLogicalElapsedMs | **仅 M05-04 B 时公开**；positive integer，毫秒/logical request | 缺失候选由网络 fixture 提案 | INI definition | no | next request | 保存有效值 | 封顶各 attempt total + retry/backoff；每 attempt 内部 cap 仍不可关闭 |
| RequestDeadlineMs | **仅 M05-04 C 时公开**；positive integer，毫秒/logical request | 缺失候选由网络 fixture 提案 | INI definition | no | next request | 保存有效值 | Runtime 仍有不可关闭的内部 connect/idle/attempt 上限，错误必须说明命中阶段 |
| RetryCount / RetryBaseDelayMs | **仅 M05-58 A/B 存在**；分别为 attempts-after-first 的非负整数和非负毫秒，均不得超过 Runtime hard range；count=0 明确关闭自动 retry | 所选路线下缺失为配置错误；新配置的精确数字由旧机/endpoint fixture 提案，不在本文冻结 | INI definition only | no | next logical request | 保存 route、effective count/base、manifest identity 与实际 attempt/backoff 事实 | A 的 exponent/jitter/max 来自 versioned Runtime manifest；B 的 jitter 仍来自 manifest；outcome unknown、收到 canonical event、协议/auth/普通 4xx/内容拒绝/cancel 都不因较大数字重放；M05-58、AQ-140、AQ-197、AQ-221 |
| RetryMaxDelayMs | **仅 M05-58 B 存在**；非负毫秒且在 Runtime hard range 内 | B 下缺失为配置错误，精确新配置值由 fixture 提案；A/C 下为 unknown/deprecated | INI definition only | no | next logical request | 保存 effective max、manifest identity 与实际 capped backoff | 必须 >= RetryBaseDelayMs；Retry-After、退避与全部 attempts 仍不得越过 logical/turn/Runtime 门；M05-58、NET-06 |
| RetryPolicy | **仅 M05-58 C 存在**；typed enum `none|standard|patient` | C 下缺失为配置错误；新配置推荐值在 fixture 后提案，不能把本表的排列当默认；A/B 下为 unknown/deprecated | INI definition only | no | next logical request | 保存 policy、当次展开的 count/base/max/jitter、manifest identity 与实际 attempt/backoff 事实 | preset 展开表必须版本化并可见；upgrade 不让旧 active request 热换语义；不能与任何 RetryCount/Delay 字段并存；M05-58 |
| MaxConcurrentRequests | **仅 F4-02 选 B 才存在**；positive integer，1..RuntimeMax | 缺失候选 1；精确默认待负责人/fixture | INI definition | no | next request / scheduler admission | 保存声明值与实际排队原因 | 同一 Model 的六个核心 purpose 与 `AutoNameEveryMainTurns>0` 条件生成的 `context-name` 共用；只约束当前进程，不宣称账户级跨进程配额；AQ-362、MODEL-15 |
| MinRequestIntervalMs | **仅 F4-02 选 B 才存在**；non-negative integer，毫秒 | 缺失候选 0；精确默认待负责人/fixture | INI definition | no | next request / scheduler admission | 保存声明值与实际等待 | 与有界 Retry-After/cooldown 取更严格值；等待可取消且不得越过 local/aggregate deadline；AQ-362、MODEL-15 |
| AdapterOption.<Name> | **M05-05 A 时由 M05-01 选中 Protocol 的发行 artifact 登记的 exact typed 字段族**；类型/范围/secret/wire encoding 逐项冻结 | 缺失表示该 registry 项声明的 provider-default/不发送语义 | INI definition | per option | next-turn / next request | 只保存实际发送的允许投影及 registry version | 不是开放任意字段；编码前 registry 必须列齐并有 fixture，未登记名为 unknown；禁止覆盖核心 body；MODEL-11 |
| GenerationIntent.<Name> | **仅 M05-05 B 时存在**；核心登记 exact intent，M05-01 选中 Protocol 的发行 artifact 逐项声明 mapping/support/wire fixture | 缺失表示不发送相关参数 | INI definition | no | next-turn | 保存 intent、adapter mapping/version 与实际 wire projection | 不是开放名称；未登记或不能无损映射就静态拒绝，不假定不同 Protocol 同名参数同义，也不总是发送 |
| PublicHeader | **仅 M05-23 选 B/C 时存在**；有序、有界 header name/value | 缺失空列表 | INI definition | conditional | next-turn / next request | 只保存经过允许的非秘密投影 | 禁止覆盖 auth、content、host、tool/control 和 Runtime 保留 header；选择 A 时字段必须 unknown/deprecated |
| SecretHeader | **仅 M05-23 选 B 时存在**；有序、有界 header name/value | 缺失空列表 | INI definition only | yes | next-turn / next request | 只保存 header 名、数量与 configured 标志 | 值不进 XML/public digest/诊断/reviewer；选择 A/C 时字段必须 unknown/deprecated |

### Model request scheduler 不是 retry 的别名

F4-02 决定是否加入 `MaxConcurrentRequests`/`MinRequestIntervalMs`。如果选择候选 B，单进程内所有引用同一 Model 的 purpose 必须经过同一个 scheduler：六个核心 purpose 与 `AutoNameEveryMainTurns>0` 的条件 `context-name` 不能各自拥有互不相知的 retry timer。

- scheduler admission 只决定“何时允许开始 attempt”，不扩大 turn/request/tool hard budget；
- 服务端 `Retry-After` 与连续明确限流形成有界进程内 cooldown，所有 purpose 共同看见；
- 等待必须可取消，deadline 先到则返回 local scheduling timeout，不伪装成 provider response；
- 每个 purpose 有 local request/token/time cap；main/side/review/compaction 进入所属 Context/turn aggregate ledger，显式 self-test 在无 Context/turn 时进入独立 `self_test_run` aggregate；D-041 周期 `context-name` 使用独立的有界周期命名预算，计入 Context/runtime 而不回记已结束 turn；scheduler admission 与账本归属是两张表，不能因为共享排队就伪造共同 turn；
- v0.1 候选不承诺同 Key、同 endpoint 的多个 yaca 进程共享账户配额，进程重启也不伪造持久 cooldown；
- self-test 仍进入 scheduler，不能为“测试”绕过服务端保护。

如果 F4-02 选择 A，两个 per-Model 字段和共享公平队列不进入正式 schema；Runtime 仍必须有不可关闭的进程并发 hard cap、Retry-After 上限、可取消等待和 aggregate ledger，不能让“没有可调字段”变成“没有边界”。

待单独决定而不先加入无条件字段：

- Model.CustomPrompt：只有 PP-11 B/C 才按上表生成，A 删除；B 的精确位置和 PP-03 C 冲突行为服从 PP-03 × PP-11 组合表，C 始终低于其他持久用户 Prompt；无论路线，真正协议 serializer/template 都属于内置版本化 adapter，不能被用户文字替换；AQ-143。
- Model 级 Proxy：用户已要求代理全局，不重复；AQ-145。
- FallbackModel：失败时不静默换 endpoint、费用和隐私域；MODEL-10。
- price snapshot / amount gate：只按 M05-50 C 与 AL06-43 B/C 的精确条件字段生成；没有 `MaxCost` 泛化别名，也不联网抓价。
- reasoning effort、response format、provider API version 等协议专用项：只通过明确的 `AdapterOption.<Name>` typed schema 增加，不能用 generic `ExtraParameter` 任意覆盖 JSON body。

## 旧配置草案的候选迁移

这一表只说明新旧语义怎样对应，不授权现在修改模板。迁移器必须先识别旧 schema 版本；没有版本证据时，不可按字段名字猜测并静默重写。

| 旧字段/结构 | 新候选 | 迁移与诊断 |
| --- | --- | --- |
| Network.FollowProxy | Network.ProxyMode | true 候选迁到 environment，false 候选迁到 off；保存前展示 |
| Network.UseStunnel | 删除 | 当前发行资源没有 stunnel；硬诊断，不保留一个实际无效的开关 |
| Network.MaxRetry / RetryDelayMs | M05-58 A/B 的每 Model `RetryCount/RetryBaseDelayMs`，或 C 的 typed `RetryPolicy` | 不能静默复制给未来新增 Model；A/B 逐 Model 显示候选数字，C 不能凭接近值猜 preset，必须显示展开表并要求选择；旧值不能生成 A-only/B-only/C-only 混合字段 |
| Exec.TimeoutMs=false / MaxOutputKB=false | `MaxExecTimeMs` / `MaxOutputKiB` 的 typed positive 值或 M05-51 B 的 manifest default | “false 等于无限”的旧语义不能突破 Runtime hard limit；迁移时显示单位与实际 cap |
| Permission.Allow* + Confirm* | deny/confirm/allow 三态 | Allow=false 映射 deny；Allow=true + Confirm=true 映射 confirm；Allow=true + Confirm=false 映射 allow |
| Permission.*.DoubleCheck | Agent.DoubleCheck | 多个 profile 值可能互相冲突，不能自动选择；要求用户确认全局默认 |
| Permission.Cautious 的内置身份 | 删除特殊身份 | 同名 section 可以保留为普通自定义 profile，但名称不再自动开启 DoubleCheck |
| Permission.AllowRegex / ExcludeRegex | 候选删除 | 若负责人保留，只能作为附加 deny/warn，不能授予 raw shell 能力 |
| Tui.CheckModelOnStart / CheckModelPerformanceOnStart | General.StartupSelfTest 的显式候选，不自动迁移 | 旧 bool 没有阶段顺序、精确外发 manifest 或逐次 consent 语义；迁移器默认写 `off`并请用户显式选择 `stage1|stage2|stage3`，不把旧 true 当作联网授权 |
| Tui.DotCommandCompletion | 候选固定能力自动降级 | 不再建立 TUI mode；旧终端不支持时使用完整文本命令 |
| TUI.StartupHeader 或其他启动头 master | 删除，无替代字段 | D-040 后每个 `StartupShow*` bool 都是独立开关；master 是未注册且无消费者的字段，不能静默接受或迁移成某个子字段值 |
| Context.AutoJumpToDir / ResumeDirectory | 删除，无新配置目标 | Context root 由 XML 的 `CONTEXT` 镜像父目录决定；迁移器显示 deprecated diagnostic 后移除，不把旧 bool/enum 转成 jump/ask/keep 或隐藏 rebind。显式 rebind 只由 context-repl 安全移动 XML |
| Context.AutoNameOnExit / SuggestContextNameAfterFirstTurn | Context.AutoNameEveryMainTurns 的显式候选，不自动迁移 | 旧值分别表达 exit/one-shot，无法无损推导周期；迁移器默认保持新 schema 的 10，并让用户显式确认或设 0。手工名称保护由每 Context XML 的 `AutoRenameDisabled` 表达，不从旧全局 bool 猜测 |
| Model.Style | Model.Protocol | 必须通过受支持枚举迁移，不能从 URL 猜 |
| Model.Name | Model.RemoteModel | 消除和 section 逻辑名的歧义 |
| Model.Url | Model.Endpoint | 迁移后验证是完整 endpoint 还是 base URL，等待该契约确认 |
| Model.TimeoutMs | Connect/FirstEvent/Idle/TotalTimeoutMs | 一个旧值无法无损推导四个值；迁移器提出候选并要求确认 |
| Model.CustomPrompt | PP-11 A 对每个非空 Model 来源分别选择 SystemPrompt、一个明确命名的 ContextPrompt 或 discard；多个来源进入同一目标先形成可编辑的有序 merge draft；B/C 保留为上表各自 typed 语义 | 迁移是可取消、可恢复的 ManagementMutation：先发布并验证目标，再清除该旧来源；失败保留未迁移字段并记录 partial outcome。不得猜“当前 Context”、静默串接、丢内容或把旧自由文本无提示提升为 C 的 adapter compatibility instruction；历史 request snapshot 不改写 |

## Context XML 覆盖白名单

### 候选可覆盖项

| XML 会话项 | 缺失语义 | 有效值 | 生效点 | 安全/恢复规则 |
| --- | --- | --- | --- | --- |
| CurrentModel | 新 Context 继承 INI 第一 Model；已有 Context 缺失视为旧 schema 迁移 | INI 中 enabled Model 的逻辑名 | next-turn | 不复制 Model 定义；失效时先只读打开并要求显式映射，不能静默改用第一项；AQ-235、AQ-236 |
| CurrentPermission | 新 Context 继承 INI 第一 Permission | INI 中 Permission 逻辑名 | next-turn | 引用失效或比本机默认更宽松时显著显示并确认；不能从 XML创建 profile |
| CurrentExecProfile | 新 Context 把 INI 第一 ExecProfile 的精确逻辑名写入 selector | **仅 M05-51 C 时存在**；INI 中有效 `ExecProfile.<Name>` 的逻辑名 | next-turn | 只是 profile selector，不复制或覆盖定义；XML 另存两个 effective resource 值、schema/profile-definition identity 与非秘密 digest。名称失效、snapshot 缺失/不同或外来 XML 未显式映射时阻止新 exec，但 TU-32 的条件 show/use/reset 仍可修复；reset 持久选中当前第一合法 profile，不能 fallback 或动态跟随 reorder；切换只能由用户 action，Model call 无权选择更宽 profile |
| DoubleCheckOverride | inherit | inherit、true、false | next-turn | 复制/导入来的 false 若降低本机默认，需要确认；AQ-151 |
| ContextPrompt | 空字符串 | UTF-8 文本及大小上限 | next-turn | 保存当前值、变更事件和 Prompt snapshot；不能覆盖 Runtime 规则；AQ-003、AQ-058、AQ-163 |
| AutoRenameDisabled | false | bool；`true` 禁止当前 Context 的周期自动命名 | next naming admission；变为 true 还取消/逻辑失效在途命名结果 | 专用 metadata，不是通用 flags bag 或 INI override。手工 rename 成功的同一管理事务默认置 true；自动 rename 不设置。context-repl 可查看/添加/取消；取消建立新调度基线，不立即命名或追补。变为 true 后，迟到 response 只保存 usage/result/cancel 证据且不得采用名称。导入/复制时随 XML 保留 |
| ActionReviewModelMapping | 缺失表示尚未为本 Context 选择 action reviewer | **仅 AL06-07 选 A/B 且 AL06-08 选 C 时存在**；INI 中 enabled Model 的逻辑名 | next action-review | 首次选择与 remap 写 action-purpose event；失效时 action-review 转 waiting-user，不 fallback/复制定义；AL06-07 C 下为 not-applicable/orphan，不能影响 termination-review |
| TerminationReviewModelMapping | 缺失表示尚未为本 Context 选择 termination reviewer | **仅 AL06-49 选 C 时存在**；INI 中 enabled Model 的逻辑名 | next termination-review | 首次选择与 remap 写 termination-purpose event；失效时 termination-review 转 waiting-user，不 fallback/复制定义；独立于 AL06-07 和 action mapping |
| CompactionConsent | 缺失表示尚未询问 | **仅 AL06-11 选 A 且 AL06-34 选 C 时存在**；auto、ask-each | next compaction | 首次选择写事件；cancel 不持久化伪偏好；只决定 model request consent，执行 Model 仍由 AL06-30；B/C 下禁止出现 |
| EndpointDisclosureConsent | 缺失表示没有可复用的跨 endpoint disclosure consent | **仅 AL06-51 C 时存在**；按 `action-review|termination-review|compaction` purpose 分开的 typed collection，每项保存 exact disclosure binding、data-class envelope、选择事件引用和 consent generation | next matching special-purpose request | 不是 INI 定义或 M05-06 override。A 只保存每次确认/request disclosure receipt而无 reusable state；B 的 reusable state 只在 active Context handle 内存中，每次发送仍保存 receipt；C 才保存本项。purpose 永不共享；event range 在同一已确认 data-class envelope 内增长不单独失效，但 main/目标 endpoint identity、tenant/auth policy、proxy route、相关 Model/config generation、purpose、data-class envelope、mapping/import generation 或所选 Model 变化即 stale。foreign/imported XML、workspace rebind 或目标机 remap 后只作 audit，fresh confirm 前不得发送 |
| WorkspaceAcknowledgement | 缺失表示未确认 | **仅 TS-14 选 C 时存在**；acknowledged + exact workspace identity/schema binding | Context open/resume | identity/path/schema 任一不匹配即失效并重新询问；只减少提示，不授予能力，也不形成跨 Context trust registry |
| MaxModelRequestsOverride | inherit | 1..INI effective 值 | next-turn | 仅 M05-06 选 B/C 且 AL06-42 选 A 时存在；只允许下调；AQ-159、AQ-395 |
| MaxToolCallsOverride | inherit | 0..INI effective 值 | next-turn | 仅 M05-06 选 B/C 且 AL06-42 选 A 时存在；只允许下调；AQ-159、AQ-395 |
| MaxTurnActiveTimeMsOverride | inherit | 1..INI effective 值 | next-turn | 仅 M05-06 选 B/C 且 AL06-42 选 A 时存在；只允许下调；等待用户/审批/idle/suspend 不计；AQ-159、AQ-395 |
| MaxTurnTokensOverride | inherit | positive integer、且不高于 INI effective 值 | next-turn | 仅 M05-06 选 B/C 且 AL06-42 选 A 时存在；usage 定义必须先确认；AQ-395 |
| CompactThresholdOverride | inherit | 0 < value <= INI effective threshold，或 inherit | next-turn | 仅 M05-06 选 B/C 且 AL06-11 选 A/B 时存在；数值更低表示更早执行 structured summary/extractive checkpoint；AQ-159、COMP-02 |
| MaxQueuedMessagesOverride | inherit | **仅 M05-06 C 时存在**；0..Runtime/有效 queue cap | next queue admission | 限制本 Context 未消费 queue 项；0 禁止新增但不删除已 durable 项；不能扩大 AL06 queue policy |
| MaxSideRequestsOverride | inherit | **仅 M05-06 C 时存在**；0..Runtime/有效 outstanding-side cap | next side admission | pending + active 合计；0 禁止新增，不能扩大 AL06-06 的并发/排队路线 |
| ToolPreviewKiBOverride | inherit | **仅 M05-06 C 且 TU-29 B/C 时存在**；0..有效 TUI live-preview cap | next preview block | 只减少运行中 preview；TU-29 A 没有 live preview，因此本字段必须不存在；不改变完成后展示、canonical tool result、XML 或 details semantic action 可声明的实际保留边界，chat root 只由 TU-32 投影 |
| DiagnosticDetailOverride | inherit | **仅 M05-06 C 时存在**；inherit、minimal | next diagnostic event | minimal 只减少 optional detail；阻断错误、canonical events、恢复证据和 typed outcome 不能被隐藏 |

预算/偏好覆盖、AL06 条件字段、M05-51 C 的 profile selector 和 TS-14 C 的 acknowledgement 都是候选扩展，不是用户已经确认的字段。无条件最小白名单只有 CurrentModel、CurrentPermission、DoubleCheckOverride 和 ContextPrompt；M05-06 B/C 共享四个 budget/threshold override，只有 C 再增加精确四项 session preference，其中 ToolPreview 项还要求 TU-29 B/C；`CurrentExecProfile`、`ActionReviewModelMapping`、`TerminationReviewModelMapping`、`CompactionConsent`、`EndpointDisclosureConsent`、`WorkspaceAcknowledgement` 也只有选中各自对应路线才进入 schema，不能由旧 XML 自行启用功能或授予信任。action 与 termination mapping 是两个独立 purpose 字段；AL06-07 C 只让前者 not-applicable，后者仍按 AL06-49 生效。`EndpointDisclosureConsent` 不是配置 override：AL06-51 A/B 不生成 reusable XML state，C 也只能按 purpose 保存本 Context 的精确 disclosure binding，不能定义 endpoint、Model 或跨 Context trust。

### 明确禁止 XML 覆盖

- Schema 本身和 Runtime hard limits；
- General.SystemPrompt 与 Permission.*.SystemPrompt；两者只能作为当时实际 Prompt component 快照进入历史；
- General.StartupSelfTest、Context.AutoNameEveryMainTurns、Context.ListSortBy、Context.ListSortDirection 与 TUI 启动信息逐字段开关；命名计数/触发/request 是 canonical 运行事实，不是 XML 对 INI 的反向定义；
- Agent.Autonomy（TS-18 B 时只允许保存有效 snapshot，不允许 XML override）；
- Endpoint、Protocol、RemoteModel、Key、AuthMode、headers 与 Model retry；
- Proxy、CA 和所有 Network 字段；
- Permission profile 的任何能力定义；
- Exec 环境与 profile 定义、timeout/output 数值和代理暴露；M05-51 C 的 `CurrentExecProfile` 只是上表登记的选择器例外；
- 数据根、锁、原子提交和修复策略。

### 快照不等于覆盖

为了让另一台机器解释历史，XML 可以保存当时有效的非秘密 Model、Permission、Prompt、工具 schema、预算、条件 ExecProfile 与 ExecEnvironmentSnapshot。恢复时仍要把 snapshot 映射到目标机当前 INI；snapshot 不会在目标机临时创建一个带 credential 的 Model/Exec environment，也不能越过本机 Permission。

M05-20 还需冻结 conditional metadata 的目的地矩阵；当前推荐候选不是“一律保存”或“一律删除”，而是 purpose-specific projection：

| 目的地 | 候选最小信息 | 始终禁止 |
| --- | --- | --- |
| Context XML / 跨机接盘 | Protocol、RemoteModel、窗口、Streaming/Tools、允许的 Endpoint origin/path、条件 ExecProfile/ExecEnvironment 公开投影、public effective digest、切换前后关系 | 任一 registered secret value、secret query、private source/equality digest |
| Stage 3 reviewer | 判断名称/权限/能力一致性所需的脱敏结构；exact internal hostname 默认最小化 | 任一 registered config-secret value、完整 URL query、NoProxy 明文、Context/工作区正文 |
| support/sanitized export | 用户预览后选择的诊断字段、版本、typed errors 和 secret-aware projection | 未经预览的正文、secret、private digest、无限 raw body |
| Model request | 该 request purpose 必需的 Prompt/消息/工具与连接 metadata | 不属于该 purpose 的其他 Context、配置浏览内容和 support 数据 |

字段的 `conditional` 分类必须在 typed schema 中列出每个目的地规则；不能只在 renderer 临时用字符串替换“看起来像 token”的内容。

## 明文配置秘密：已经接受的风险与仍需关闭的泄漏面

项目负责人已经选择 Key 明文保存在主 INI。条件字段中的 ProxyUrl credential、SecretHeader、EnvironmentSet value 和 adapter-secret 也进入同一 typed secret registry；每项必须标记 `config-file|ambient-environment|user-content|runtime` source。这意味着 yaca 不承诺“磁盘被读取后其中的 config-file secret 仍保密”。实现仍应缩小其他泄漏面：

- config.ini 创建/替换后尽力设置并复核仅当前用户可读，结果规范化为 `protected|weak|unverifiable`。FAT、旧 Windows ACL、共享目录或 adapter 失败时，实际消费该文件中 `source=config-file` secret 的 consumer 是进程内确认后可用、仅警告可用，还是精确禁用，完全服从 M05-54；ambient/user/runtime secret 不借用这个 ACL 结论。该政策是产品常量，不新增“忽略权限”配置开关。
- 原子内容发布和 ACL/mode 分类是两个结果：前者不能证明时不激活 generation；前者已完成而后者只能得到 weak/unverifiable 时，generation 可发布但必须立即执行 M05-54 所选 admission。
- 权限在 generation 载入/激活、secret-bearing publish 后和每次 secret-bearing use 前重新观察。可重用的 observation credential 至少绑定规范路径、文件身份、ConfigGeneration、权限结论和平台能提供的 ACL/mode fingerprint；纯权限变化不得因内容 digest 未变而被忽略。无法 fingerprint 时结论仍是 unverifiable，不声称能检出后续 ACL 改动。
- show-config、REPL 列表、错误、diff、XML、日志、支持输出和剪贴板默认只显示 configured/replace/clear，不回显原值；名单由 registry 生成。
- registered secret value 不参与 public/Model/environment snapshot digest，避免形成可离线比对的凭据指纹；value equality 只用进程内临时 keyed fingerprint/observation binding。
- Runtime 自己控制的结构化 config-secret value 只进入已授权 consumer 的精确私有 carrier，不进入 argv、shell 命令正文、Context XML 字段或普通 stderr/stdout；EnvironmentSet 只能作为用户显式选择的 raw-exec 环境消费者注入，不是 yaca 内部 helper/Model carrier。普通正文的 exact-value scanner 服从 M05-59：A 对低于 manifest 门槛的值禁用精确 consumer，B 允许 consumer 但对该短值免除普通正文全局扫描并明确收缩 XML 保证，C 对任意长度继续扫描并接受误阻断/误 marker。达到所选扫描覆盖的 registered exact value 若由工具输出，统一 secret boundary 在 direct TS-16 或 exec TS-39 retention/digest 前写 typed redaction marker；未知或变形 secret 仍可能作为 user/tool content 进入完整 XML，不能承诺自动找全。
- M05-59 的最小安全扫描字节数、跨 chunk 尾窗和 matcher 资源门由 fixture/manifest 冻结，不生成 INI 开关。相同 raw bytes 的 registry 项折叠为一个 pattern 并保留稳定类别/source 集；全部 exact patterns 都参与扫描，重叠命中取 maximal byte-interval union，admission/marker 不能随 registry 或 matcher 遍历顺序改变，也不按运行时“高频”猜测跳过。
- 专用 secret-entry prompt 的值不写 yaca-owned 输入召回/补全；终端无法安全隐藏输入时必须先说明能力限制。普通 chat 可能含未知秘密，不能作同样承诺。
- 进程内字符串、崩溃 dump、swap、同用户恶意进程和已经感染的机器仍可能读取 Key，UI masking 不是加密。
- ProxyUrl userinfo、SecretHeader 和所有 EnvironmentSet value 使用同一秘密策略；EnvironmentSet 不提供可误标为 public 的逐项逃生口。
- 用户自己把 Key 粘进消息或 shell 命令属于 conversation/tool content；“完整历史”和自动脱敏存在冲突，应在导出时显著预览，不能声称已自动识别所有秘密。
- 配置 backup/previous-valid 复制了任一 config-file secret 时就是 secret 配置文件：eligible set 由 registry 生成，使用同级权限、固定位置、有界数量和显式清除/恢复规则；不得把备份路径或 private digest 当普通诊断上传。

## 把 Key 交给 curl 的三个候选方案

### A. curl 配置经 stdin，request body 使用受保护临时文件（CLI curl 首选候选）

流程：

1. yaca 把 Key、proxy credential 和 secret headers 写入 curl 的 stdin config stream。
2. 规范 JSON request body 写入同一受控临时目录中的 no-replace 文件。
3. curl 从 body 文件读取请求，stdout/stderr 由 Process adapter 有界流式捕获。
4. 请求结束后清理 body；崩溃恢复识别并安全删除残留。

优点：

- Key 不进入 argv、环境变量或磁盘；
- 可继续使用随包 curl；
- stdout 可以流式处理。

代价：

- 对话/request body 暂时落盘，可能含用户秘密；
- Windows XP 上临时文件权限、no-replace、清理和杀进程必须实测；
- config stdin 与 curl 生命周期要避免写入错误日志。

### B. request body 经 stdin，secret curl config 使用受保护临时文件

优点：

- 完整对话 body 不落盘；
- request 可直接流向 curl。

代价：

- Key/代理密码进入临时文件，泄漏后果更高；
- 必须证明创建权限、删除和崩溃残留；
- 配置文件路径可能出现在 argv，虽然内容不应出现。

在“明文只长期保存在 INI”之外又产生一份 Key 临时副本，因此不推荐作为默认。

### C. 极小 native libcurl/helper 在内存中接收 headers 和 body

优点：

- Key 与 request body 都不需要 argv、环境或临时文件；
- 流式、取消、headers/status 通道和 backpressure 更容易形成结构化 ABI。

代价：

- 增加 Windows XP x86 与 CentOS 7 的 native 构建、TLS、libcurl ABI、供应链和 luainstaller 打包负担；
- helper 崩溃与内存清理仍需测试；
- 原生层必须保持窄接口，不能拥有 Model 或 AgentLoop 状态。

当前候选建议：若继续采用 CLI curl，先验证 A；若 02/03/22 号系统最终已经需要 native helper，再比较 C。最终选择必须和 AQ-043（临时文件）、AQ-219、AQ-223、AQ-250 一起确认。绝不采用“Key 直接放 curl argv”或“把 Key 放通用子进程环境”。

## INI 语法与往返候选

### 基础语法

- 文件编码固定 UTF-8；reader 可接受一个 UTF-8 BOM，writer 候选不生成 BOM。
- section/key 名、枚举和机器字段固定 ASCII；用户文本值仍可为 UTF-8，服从 AQ-045。
- section/key 名候选大小写敏感，以便准确发现拼写错误；选择器的 ASCII 大小写规则另见 AQ-199。
- bool 只接受 true/false；整数只接受 ASCII 十进制；单位写在字段名。
- 字符串使用双引号并定义反斜杠转义；不接受依赖平台的本地代码页。
- 分号或井号只在引号外开始注释；精确选择仍待 FMT-04。
- 重复 singleton section、重复非列表 key 和同名 Model/Permission section 是硬错误。
- 物理 section 顺序保留；第一个 Permission 与第一个 Model 的顺序具有默认选择语义。

### 集合字段的唯一物理表示

集合不是另一种 multiline string，也不能让每个 consumer 自己发明逗号/分号语法。候选固定为 **schema 明确标记的 collection key 可以重复出现，一行一个已经按基础字符串规则解码的 item，物理出现顺序就是规范顺序**：

```ini
NoProxy = "localhost"
NoProxy = ".example.invalid"
NotificationEvents = "approval"
NotificationEvents = "fatal-error"
EnvironmentSet = "BUILD_MODE=release"
PublicHeader = "X-Project: demo"
```

- key 缺失表示空集合；`Key = ""` 是一个空 item，并按该字段 item grammar 接受或拒绝，不能表示空集合。
- 只有 typed schema 标为 collection 的 key 才允许重复；singleton 重复仍是硬错误。reader/writer/REPL 必须保留 item 顺序和逐项注释，编辑使用稳定 draft row ID，但 row ID 不写入最终 INI。
- `NoProxy`、`DirectHttpNoProxy`、`DirectHttpAllowedOrigin`、`NotificationEvents`、`EnvironmentUnset` 各行只有一个相应 typed scalar；字段自己的 host/origin/event/name validator 继续生效。
- `EnvironmentSet` 在解码后按第一个 `=` 分成非空 ASCII NAME 与任意有界 VALUE；VALUE 中后续 `=` 属于值。所有 VALUE 一律按 secret 处理，名称可以进入脱敏 diff/XML snapshot，值不得进入 XML、public digest、诊断、clone 或 export。
- `PublicHeader`/`SecretHeader` 在解码后按第一个 `:` 分成 header name/value；name 必须满足 adapter-independent header token 规则，value 可以含后续冒号。两者分别使用 public/secret 目的地政策，不能根据名字临场猜秘密。
- list/map 的 item 数量、单项字节、总解码字节均受字段与 Runtime hard cap；任一 item 非法使整个 ConfigGeneration 无效，不跳过坏项后继续。

这是一项 parser/writer 技术契约，不新增负责人投票；M05-07 仍只决定字符串/多行的基础编码，M05-28 仍只决定 unknown/deprecated 字段政策。若未来新增 collection 字段，必须先在 typed schema 登记 item grammar、顺序语义、secret class、合并规则和 consumer，不能复用含糊的“逗号列表”。

### 多行文本

需要支持全局 SystemPrompt，但不值得实现多个含糊的 INI continuation 方言。三种候选：

1. 双引号字符串内使用明确的反斜杠 n 转义；parser 最简单、跨平台最确定，REPL 可用真正多行编辑后编码。当前推荐。
2. 自定义三引号 block；手改更直观，但必须定义结束标记转义、缩进、换行和注释。
3. 行尾反斜杠 continuation；容易与 Windows 路径、尾随空格和注释混淆，不推荐。

在 AQ-200/FMT-04 决定前，模板和实现不能各选一种。

### 注释、顺序与未知字段

若 AQ-133 确认支持手工编辑，推荐 parser 保留 concrete syntax tree：

- 未修改字段的注释、空行、原始顺序和换行风格继续存在；
- REPL 只修改目标节点；新增字段放到 schema 定义的位置；
- move-first/move-before/move-after 是显式事务，并在保存前显示默认项变化；
- secret diff 只显示 unchanged/replaced/cleared；
- disabled Model 草稿也保留，不因暂时未配置 Key 被自动删除。

未知字段不能简单忽略，精确宽严由 M05-28 选择：

- 缺失 required、疑似拼错和安全/权限/secret/network/process unknown 必须阻断；错误包含 section/key/行号，parser/REPL 仍保留原文供修复。
- 明确废弃字段由迁移表给出 warning/error 和替代字段，不能与新字段同时生效。
- config 的 major 高于程序支持时只读诊断或拒绝，绝不重写。
- 已登记 future namespace 或 non-security unknown 能否往返保留按 M05-28 A/B/C；保留只表示不丢原文，从不表示字段生效。

这既避免一个拼错的安全字段被静默忽略，也避免 REPL 为了报错就毁掉用户手写内容。

### 手工编辑与 REPL 的事务

手工编辑是外部写者；REPL 保存必须执行：

1. 读取原始 bytes、文件身份和 digest。
2. 解析成保留注释/顺序的草稿树。
3. 所有编辑只改内存草稿，显示 dirty。
4. 运行逐字段和完整跨字段校验。
5. 显示脱敏 diff、第一 Model/Permission 变化和生效点。
6. 只在发布临界区取得 config writer lock，再重新读取完整原始 bytes、检查 expected file identity/private source digest；不在用户编辑草稿期间长期持锁。
7. expected digest 不匹配就拒绝覆盖并要求 reload/compare；匹配时在同目录创建 no-replace 临时文件，写完、flush、重新解析并完成全部跨字段验证。
8. 使用目标平台已证明的安全替换协议原子发布；失败保持旧文件，成功后由下一顶层 main/side turn admission 的 D-048 观察自动激活，不需要 watcher 或 reload policy。
9. 原子发布需要的受控 temp/recovery 服从写入协议；是否另外产生含任一 registered config-file secret 的用户 backup/export 只由 M05-42 决定，任何这种副本都按完整 secret 文件处理。

普通 Agent 启动必须严格加载完整配置；没有有效 enabled Model 也是配置不通过，不存在可发布的“无 Model 管理态 ConfigGeneration”。model-repl、config-repl 和 self-test Stage 1 使用只依赖内置 schema 的 bootstrap reader：它们可编辑未发布 repair draft 或报告静态根因，但不启动 Agent、工具或网络请求。context-repl 不借用坏配置：它从配置前已定位的 data root 打开独立 Context Catalog，可以 list/inspect/rename/delete/import/restore/repair，只把无法解析的 Model/Permission 引用显示为 unresolved，不因此 continue chat。新对话 Context 仍由第一条已接受 main 消息创建，context-repl 不制造空对话。某 Context 有活动 writer 时，context-repl 仍可显示可证明的 busy metadata，但所有会改变该 XML/逻辑路径/marker 的外部 mutation 都拒绝；这个 Context lock 不妨碍 model-repl/config-repl 修改独立 INI。

三个管理 REPL 是独立顶层 semantic entrance，每个只提供本域 `self-fix` 选单：model-repl 修 Model，config-repl 修完整 INI/schema/migration，context-repl 修 XML/Catalog/lock/reference。self-fix 始终先预览再确认并经过同一原子发布契约，不是发现问题就自动改写。每个 TUI domain action 都必须由同一 typed action registry 提供等价 CLI projection；这只保证本机 CLI/TUI 行为一致，不发布 remote/headless IPC，也不允许非 TTY 绕过确认或 Permission。

### reset 不是 parser 默认值操作

M05-18 只冻结 non-secret `config reset` 的字段范围；M05-42 独占含 registered config-file secrets 的 backup/export，Context purge 由 CX/F4 管理事务独占。无论选择哪项，reset 都不是“把内存 table 清空后直接 save”；M05-15 B 的 EnvironmentMode/Set/Unset 必须作为一组预览，A 路线不由 bulk reset 改写。候选事务必须先生成：

~~~text
reset plan
  targets: exact config generation and sections
  non-secret defaults to rebuild
  Model/config-secret/Permission disposition: preserved
  Context references affected: report only, never purge
  secret-bearing backup/export: separate M05-42 action only
  -> redacted confirmation
  -> stale generation check
  -> one atomic ManagementMutation commit
  -> completed | failed | recovery-required
~~~

默认候选不清除 Key、不删除 Context、不递归删除 `__yaca__`，也不把“修复配置”与“销毁历史”合成一个确认。reset、Model 删除/重排、migration 和 config import 共用 F4-09 的 `ManagementMutation` 正确性协议，但各自仍有独立 typed plan。

## 完整跨字段与生命周期校验表

严重度候选：

- error：普通 Agent 不得启动或不得保存草稿。
- warning：配置可以使用，但用户必须看见风险或能力降级。
- advisory：只由 self-test 第三阶段给建议，绝不改变确定性结果。

| ID | 条件 | 候选严重度与处理 | 关联 |
| --- | --- | --- | --- |
| CV-001 | SchemaMajor/Minor 缺失、越界或程序不支持 | error；旧程序不写新版配置 | AQ-185、CFG-07 |
| CV-002 | singleton section 缺失/重复 | error；精确指出 section | FMT-04、CFG-08 |
| CV-003 | 未知 key/section 或废弃字段与新字段同时出现 | error 或 migration warning；安全字段绝不静默忽略 | CFG-08、CFG-22 |
| CV-004 | bool/int/decimal/enum/string 不符合规范拼写 | error；显示脱敏实际值和期望类型 | AQ-200、AQ-201 |
| CV-005 | Model/Permission 长名或简称在各自命名空间冲突 | error；不按文件顺序猜 | AQ-135、AQ-199 |
| CV-006 | 没有任何 Permission section | error | CFG-06 |
| CV-007 | 没有任何 Model section | 配置不通过且不发布 Agent ConfigGeneration；help/version、bootstrap model/config-repl、context-repl 与 self-test Stage 1 仍可用 | AQ-217、CFG-09 |
| CV-008 | 没有 enabled Model，或物理第一 Model disabled/连接字段无效 | 配置不通过；管理入口只打开未发布 repair draft，不把它称为 schema-valid active generation，不静默跳到下一个 | AQ-134、M05-30 |
| CV-009 | disabled Model 不满足 M05-08 所选完整度：A 缺 Protocol；B 缺除 Key/在线 observation 外任一 enabled-required 字段；C 缺任一 enabled-required 字段或所选 adapter/AuthMode 对 enabled Model 实际要求的 Key/auth 值；或任何已出现字段类型、组合、名称非法 | error；disabled 不是跳过 parser，也不能落入三条方案之外的“任意空 section”第四种行为 | AQ-080、AQ-134 至 AQ-137、M05-08、M05-02、CFG-08 |
| CV-010 | enabled Model 缺 Protocol/Endpoint/RemoteModel 或所选 adapter/auth/endpoint 路线的其他 required 字段 | error | AQ-136、AQ-138、M05-01 至 M05-03、M05-33 |
| CV-011 | AuthMode=protocol 但协议要求 Key 且 Key 空 | error；none 不能从空 Key 自动推断 | AQ-137 |
| CV-012 | Endpoint 不是允许的绝对 http/https URL | error | NET-10、AQ-220 |
| CV-013 | Endpoint 含 userinfo、secret query 或跨 origin redirect 行为不明确 | warning/error 按策略；值脱敏 | AQ-219、AQ-220、SAFE-09 |
| CV-014 | Protocol 不受发行物支持，或 PublicReasoning/adapter option 声明了该 adapter 没有的能力 | error；不联网猜协议/能力，也不把 hidden reasoning 当兼容 fallback | AQ-138、AQ-218、M05-40 |
| CV-015 | Streaming=force 但 protocol/Model 明确不支持 | error；不降成 try/off | AQ-139 |
| CV-016 | M05-03 A/C 的 Tools 声明与 adapter 静态 schema 不兼容、`Tools=off` 的 main 资格违反 M05-26，B 的 Protocol adapter manifest 不是 native/却生成 Tools 或 no-tool-main 分支，或 required-native 的显式在线证据失败 | 静态不兼容为 error；B 下 M05-26 强制 not-applicable；B 的未测试/普通 observation failure 只 support/warn，不把联网测试变成启用 gate；不做文本 emulation | AQ-144、AQ-374、MODEL-16、M05-03、M05-26、D-031 |
| CV-017 | ContextLength/MaxOutputTokens 非正数或 output >= context | error | AQ-142、MODEL-08 |
| CV-018 | 已知 context 无法容纳固定 Prompt/tool schema/output reserve | error/warning；不得先发请求再碰运气 | AQ-062、COMP-05 |
| CV-019 | Connect/FirstEvent/Idle/Total timeout 越界或相互矛盾 | error；具体不等式由 NET-05 冻结 | AQ-141 |
| CV-020 | M05-58 B 的 RetryMaxDelayMs < RetryBaseDelayMs；A/C 下出现该字段由 CV-074 处理 | error；不交换、不 clamp，也不借用另一条路线的默认 | AQ-140、M05-58 |
| CV-021 | Retry 最坏等待或单 request total 明显越过 turn/请求边界 | error/warning；AL06-42 A 对照 MaxTurnActiveTimeMs，B 对照发行物固定 safety cap；独立 request wall-clock deadline 始终截断 | LOOP-27、AL06-42 |
| CV-022 | M05-58 A/B 的 RetryCount 超过 RuntimeMax 或配置成无限 | error；C 只接受已登记 preset，分支混用与完整 range/snapshot 由 CV-074 处理 | AQ-140、AQ-197、M05-58 |
| CV-023 | PublicHeader/SecretHeader 名非法、重复冲突或覆盖 Runtime 核心 header | error | AQ-219、MODEL-11 |
| CV-024 | AdapterOption/GenerationIntent/PublicHeader/SecretHeader/CustomPrompt 尝试覆盖 model/messages/tools/stream/auth/Runtime limit；对应 M05-05/23 或 PP-11 方案未启用却出现条件字段；PP-11 B/C 违反 PP-03 × PP-11 权威链；或 adapter 无法映射 GenerationIntent | error；PP-11 C 的 CustomPrompt 也只是最低优先级用户 compatibility hint，不能改写 serializer/role/tool/control/purpose/权限 | M05-05、M05-23、PP-03、PP-11、AQ-219 |
| CV-025 | Model 或 DirectHttp ProxyMode=explicit，但对应 ProxyUrl 空/非法 | error；两个 policy 不互相借值 | AQ-145、TS-11 |
| CV-026 | Model 或 DirectHttp ProxyMode=off/environment 时，对应 explicit ProxyUrl 非空 | error；不能悄悄使用，也不能跨 policy 复制 credential | AQ-145、TS-11 |
| CV-027 | NoProxy/DirectHttpNoProxy 规则非法、混用未声明语法或被错误用于另一 transport | error | NET-04、TS-11 |
| CV-028 | Model 或 DirectHttp CaMode 含 custom，但对应 CaFile 空、不可读或变化 | error before request；两个 trust policy 独立 snapshot | AQ-146、TS-11 |
| CV-029 | 配置试图关闭 TLS 验证 | unknown field/error；不提供这种 schema | AQ-146 |
| CV-030 | 所选 M05-14 字段集不完整/混入另一分支，任一 transport limit 为 0/超 RuntimeMax，或 compressed/decompressed/ratio/logical-response 组合无法容纳最小协议消息 | error；B 的九字段与 Runtime hard cap 机械对齐 | AQ-245、M05-14 |
| CV-031 | AL06-42 A 的 Agent turn guard 为 0/负数/超 RuntimeMax，或 B 下出现四个用户 turn 字段 | error；只有 MaxToolCalls 明确允许 0；B 使用版本化 fixed guard，不接受 orphan 字段；AL06-09 只决定 Context hard ledger | AQ-395、LOOP-04、AL06-09、AL06-42 |
| CV-032 | AL06-27 A 下所需局部 cap 缺失/越界（termination 始终；action 仅 AL06-07 A/B）；AL06-07 C 下出现 MaxActionReviewRounds；AL06-27 B 下 MaxDoubleCheckRequests 缺失/越界；C 下出现上述用户字段 | error；局部 cap 始终再受 AL06-42 所选 configurable/fixed turn guard 约束 | AQ-019 至 AQ-023、AQ-395、AL06-07、AL06-27、AL06-42 |
| CV-033 | AL06-42 A 的 MaxTurnTokens 小于固定 Prompt/工具 schema/最小输出预算 | error/warning；不能开始 turn；B 对 manifest fixed guard 做同类发行 fixture，不读取该字段 | AQ-062、AQ-153、AQ-395、AL06-42 |
| CV-034 | 未选择 M05-50 C 时出现 price/estimate 字段，或未选择 AL06-43 B/C 时出现对应金额门字段 | error/unknown field；不得由无 consumer 字段暗中启用金额功能 | AQ-283、AQ-410、M05-50、AL06-43 |
| CV-035 | M05-51 A/C 的 MaxExecTimeMs 非正/超 RuntimeMax；A/C 混用 `[Exec]` 与 `[ExecProfile.*]` 资源形态；B 下出现资源字段；C 没有有效 profile、CurrentExecProfile 失效/被 Model 选择，或 active call 试图热改/换 profile | error/warning；调用时与有效 turn active-time guard 取更早边界；C 只允许用户 next-turn 选择并保存 snapshot；termination grace 是 adapter/manifest release gate | AQ-126、AQ-147、AQ-395、M05-51、AL06-42 |
| CV-036 | MaxOutputKiB 或条件环境列表超限 | error；输出 decoder 是 Runtime `auto` 契约，不读取配置 | AQ-123 至 AQ-125 |
| CV-037 | EnvironmentSet/Unset 重复或 canonical 同名冲突、名称非法、覆盖 Runtime 保留变量、超单项/总环境上限，或未按 baseline→unset→set→validation 合成；Windows 大小写折叠与 Linux exact-name 规则不一致 | error；整个 ConfigGeneration 无效，不 last-wins、不部分注入；公开 snapshot 不含 value/private fingerprint | AQ-148、AQ-423、M05-15、M05-55 |
| CV-038 | 出现已排除的 ExposeConfiguredProxy，或 raw-shell environment 字段尝试引用全局 ProxyUrl/credential | unknown/deprecated error；全局 proxy 永不自动传播给 raw shell | M05-15、NET-11、SAFE-09 |
| CV-039 | AL06-11 A/B 的 CompactThreshold 不在开区间 (0,1)，或 C 下出现该字段/override | error；C 的 latest-fit view 只消费 Runtime 计算的 effective reserve，不伪造 compaction trigger | COMP-02、AL06-11 |
| CV-040 | Runtime 计算的 effective reserve、Model 输出与 Prompt/tool 余量合计超过 ContextLength；AL06-11 B/C 下出现 CompactionModel/CompactionConsent；或 CompactionModel 无法容纳最小请求 | error；提示更大 Model/调整真实配置；不允许无消费者的 compaction 字段反向启用压缩，也不允许 INI/XML 提供 reserve | AQ-156、AQ-240、AL06-11、AL06-30、AL06-34 |
| CV-041 | CX-11 B 的三个 quota 缺失/非正/超过发行硬门，A/C 下出现这些字段；或 C 的 AutoPurgeTrash/TrashGraceDays 条件不闭合 | error；A 无用户 quota/purge 字段，B/C 字段族互斥；auto purge 无 durable trashed_at/预告/稳定 scan 时 fail closed；resolver scan cap 属于 manifest release gate | CTX-12、PERF-02、CX-11 |
| CV-042 | Permission 能力缺失或不是 deny/confirm/allow | error；不补“安全默认”掩盖旧 schema | AQ-149、AQ-150 |
| CV-043 | Permission 同时保留旧 Allow*/Confirm* 与新三态字段 | migration error；禁止双重求值 | CFG-16、AQ-150 |
| CV-044 | Permission section 含 profile 内 DoubleCheck 或名为 Cautious 的旧内置语义 | migration diagnostic；不自动改变用户自定义同名 section | D-021、CFG-16 |
| CV-045 | DirectNetwork=deny 但 Shell=allow | warning：shell 仍可能联网；不得声称隔离 | AQ-224、NET-11 |
| CV-046 | Read/Write/Delete=deny 但 Shell=allow | warning：shell 仍可能绕过细粒度直接工具策略 | AQ-224 |
| CV-047 | M05-16 A 的 OutsideWorkspace，或 B 的 OutsideRead/OutsideWrite/OutsideDelete 任一为 deny/confirm，而 Shell=allow；M05-56 B 的 SensitiveRead 比 Shell 更严格时亦同 | warning：这些字段只约束 direct tools，Runtime 不能证明 raw command 不越界或不读取敏感路径；不得把 profile 描述成相应能力已被 OS 隔离 | AQ-224、AQ-430、SAFE-06、SAFE-09、M05-16、M05-56 |
| CV-048 | XML 覆盖不在无条件白名单，或 AL06/M05/TS 条件未启用却出现 CurrentExecProfile、ActionReviewModelMapping、TerminationReviewModelMapping、CompactionConsent、EndpointDisclosureConsent、WorkspaceAcknowledgement、预算覆盖；特别是 AL06-07 C 下出现 action mapping，或 AL06-51 A/B 下出现 reusable endpoint-disclosure state | error/read-only diagnostic；绝不合并任意 key，也不由数据文件反向启用功能/信任；action 字段 not-applicable 不得连带禁用合法 termination 字段；foreign/imported disclosure consent 即使 C 路线也只作 audit，不能直接激活 | AQ-159、AL06-07、AL06-08、AL06-49、AL06-34、AL06-51、M05-51、TS-14 |
| CV-049 | XML CurrentModel/Permission/CurrentExecProfile/ActionReviewModelMapping/TerminationReviewModelMapping 引用不存在；INI ActionReviewModel/TerminationReviewModel/CompactionModel 引用不存在，或分别在 AL06-07 A/B + AL06-08 B、AL06-49 B、AL06-11 A + AL06-30 B 之外出现；或 CurrentExecProfile 同名但历史/本地 resource 值、definition identity/digest 不同、snapshot 缺失、外来 selector 未在 import mapping generation 激活 | 条件 INI 字段越界为 error；引用失效时只读打开或仅对应 purpose 转 waiting-user并提示显式映射/修复；一个 review purpose 失效不得使另一个已正确配置的 purpose fallback 或改绑；Exec profile 失效/定义不同至少阻止新 exec，精确严重度服从 CX-18；不静默 fallback、按名绑定或动态跟随 | AQ-236、AQ-380、CTX-27、AL06-07、AL06-08、AL06-49、AL06-11、AL06-30、M05-51、CX-07、CX-18 |
| CV-050 | XML 选择的 Permission 或 DoubleCheck 比本机默认更宽松 | 继续前显著确认；精确策略未决 | SAFE-04、CTX-27 |
| CV-051 | 本机将发布的 XML 结构化 snapshot/配置投影直接携带任一 registered config-secret value、private source/equality fingerprint 或未声明 scope 的 secret-derived digest；或者 XML 普通 canonical content 命中 M05-59 所选路线仍要求扫描排除的 exact value | 结构化泄漏在所有 M05-59 路线都 publication fail closed；普通正文按 M05-59 A/B/C 与 CV-075 处理。需排除的本机内容 fail closed；外来原文件保持只读并形成 `registered-secret-content` compatibility gap，不原地改写，writable continuation 只允许 CX-07 的显式 sanitized copy/generation 或在 registry value 轮换/移除后重评；B 的低于门槛普通正文 coincidence 不触发本条，但必须保留 guarantee-contracted 标记/警告。排除集合由 typed registry 生成，不用手写字段名 | AQ-040、AQ-168、M05-54、M05-59、CX-07、TS-15 |
| CV-052 | XML budget/threshold override 在 M05-06 A、turn override 在 AL06-42 B、threshold override 在 AL06-11 C 下出现；M05-06 B 下出现 C-only session preference；TU-29 A 下出现 ToolPreviewKiBOverride；或任一允许项高于有效上限/使用未登记值 | error；不 clamp 后继续，也不允许外来 XML 提高预算、扩大 queue/side 或减少 canonical 事实 | CCA-Q-11、AQ-159、AQ-395、M05-06、AL06-11、AL06-42、TU-29 |
| CV-053 | ContextPrompt 超大小/Token 上限或编码无效 | error；不静默截断后当完整 Prompt | AQ-062、AQ-063 |
| CV-054 | LogLevel 较低导致实现试图不保存 canonical 事实 | 实现/契约测试失败，不是用户配置错误 | CTX-01、DIAG-03 |
| CV-055 | self-test LLM 认为名称与行为“不合理” | advisory only；不覆盖以上确定性结果 | AQ-202 |
| CV-056 | Model Endpoint 使用 HTTP/发生 scheme downgrade，或 DirectHttpAllowedOrigin/redirect 违反 exact-origin、loopback-HTTP、no-downgrade 规则 | Model 按 M05-13；direct HTTP 非 loopback HTTP、registered secret、cross-origin redirect 或 downgrade 一律 error | CCA-Q-01、NET-13、AQ-220、TS-11 |
| CV-057 | MaxConcurrentRequests/MinRequestIntervalMs 非法、超 RuntimeMax，或 Retry-After/cooldown 等待越过 request/turn deadline | error 或 typed local scheduling timeout；不报告为 provider 拒绝 | CCA-Q-02、AQ-362、MODEL-15 |
| CV-058 | optional scalar 使用未注册 sentinel，或数字字段用 false 同时表达关闭/未知/无限 | error + versioned migration diagnostic；不交给消费者猜 | CCA-Q-10、AQ-200、M05-19 |
| CV-059 | generic CLI override 尝试覆盖未注册字段、secret、endpoint、Permission 定义或 unknown key | M05-22 A 时 unknown option；B 时只接受逐字段 typed allowlist；永不绕过完整 validator | CCA-Q-15、CFG-01、CFG-12 |
| CV-060 | public effective digest、XML、status/support 中出现 private source digest 或 secret-derived bytes | 实现/secret-canary 失败；不得发布该 transition/snapshot | SAFE-09、HCFG-02 |
| CV-061 | D-048 在任一顶层 main/side turn admission 前完整读取 INI 后发现 bytes 已变且候选无效、删除、半写，或 current Model/Permission 已失效；或者实现只看 mtime/size、跳过本轮读取、需要确认才激活有效 generation、让 child activity 热换 snapshot | 阻止该新 turn 并指向 config/model self-fix；active turn 及其 child tool/review/retry 保持旧 snapshot并如实收口。有效候选全量验证后自动原子激活；不得静默 last-known-good、fallback 第一项、部分载入或建立 watcher/reload interval/policy 字段 | AQ-361、CFG-24、F4-01、D-048 |
| CV-062 | reset/migration/backup/export 会复制或清除任一 registered config-file secret，Exec environment reset 拆散 Mode/Set/Unset 安全组合，或 config reset 试图顺带 purge Context，但 plan 未按 M05-18/M05-42/CX owner 分离 secret 副本、引用、stale generation 与恢复路径 | ManagementMutation validation error；不提交 | CCA-Q-09、AQ-132、ARCH-05、M05-15、M05-18、M05-42 |
| CV-063 | conditional metadata 被投影到 XML/reviewer/support/request 之外的目的地，目的地策略未登记，或 Autonomy/CustomPrompt/workspace acknowledgement 被赋予其 owner 禁止的权限、安全或协议含义 | error/contract-test failure；按 typed data-classification matrix 最小化 | CCA-Q-12、AQ-358、M05-20、PP-11、TS-14、TS-18 |
| CV-064 | internal curl/Git/helper 读取宿主 default config、cwd/PATH 同名工具、隐式 CA/proxy、pager/editor/external diff/textconv/credential helper | self-test/release gate failure；不是可忽略 warning 或用户配置选项 | PROC-13、HCFG-04 |
| CV-065 | compressed/decompressed/error/tool-argument/aggregate response 或多个用户上限组合可越过 Runtime hard cap/Win32 x86 内存预算 | error/release gate failure；字段缺失或任何已登记 sentinel 也不得解除 hard cap | AQ-245、AQ-322、HCFG-03 |
| CV-066 | NotificationChannel/NotificationEvents 出现在未激活分支、enum/allowlist 非法，或外来 XML 尝试启用/覆盖通知 | error/unknown field；通知只从本机 INI 生效，XML 只保存 snapshot；transcript 仍是唯一规范信号 | AQ-338、AQ-413、TU-27、TU-30 |
| CV-067 | price metadata/rates 缺失、单位/decimal/category/currency 冲突、generation stale，或 estimated/reported 被合并为一个金额 | error 或 estimate unavailable；不联网补价、不换汇、不声称精确账单 | AQ-283、MODEL-09、M05-50 |
| CV-068 | EstimatedCostWarning 与 MaxEstimatedCost 同时存在、币种不同、分支不符，或金额门无法保守估算 | error/typed admission：B 在已配置 warning 时把 unavailable 当成必须 fresh consent 的显著 warning，绑定 exact turn/Model/price/request generation；C fail-closed 且无模糊 override | AQ-410、M05-50、AL06-43 |
| CV-069 | ApprovalExpiryMinutes 在 AL06-44 A/B 下出现、非正/无限/超 hard maximum，或到期后仍接受旧 composer/approval ID | error；到期只产生配对 synthetic expired/denied result，旧输入 typed stale，绝不 allow | AQ-226、AQ-412、AL06-44、AL06-45 |
| CV-070 | collection key 未在 typed schema 登记却重复、把空 item 当空集合、item/总量超限、顺序被 writer 改变，或 EnvironmentSet/header 等 tuple 无法按唯一 delimiter 规则解析 | error；整个 ConfigGeneration 无效，不跳过坏 item；EnvironmentSet value 始终 secret，不能因变量名陌生而降成 public | FMT-02、FMT-04、CFG-18、M05-07、M05-15、M05-23 |
| CV-071 | 任一 `source=config-file` registered secret 存在且其承载文件 permission 为 weak/unverifiable，却未按 M05-54 产生对应 process-bound consent/warning/exact-consumer-disabled state；或实际 use 前没有重查，路径、file identity、generation、权限结论/ACL-mode fingerprint 变化后仍复用旧确认；或把 ambient/user/runtime secret 错绑到 config.ini ACL | fail closed/contract error；A 的确认不写 XML且非 TTY 拒绝，B 仍必须显示持续 warning，C 禁用会消费该文件秘密的精确 Model/purpose/tool 且不静默改路。内容发布结果 unknown 与 ACL/mode=`weak|unverifiable` 是两个独立 error axis，任何路线都不能互相伪装 | AQ-417、SAFE-09、M05-54、M05-15、M05-23、M05-36、TP-006、TP-010 |
| CV-072 | AL06-50 A 下出现任一 `MaxNoProgress*` INI/XML 字段；B 下混入 C-only detector key，或显式单值不是技术证明范围内正整数；C 下出现 B-only 单值、缺少 registry 要求的 effective detector 项、含未知 detector key 或任一值越界；任一路线允许 0/off/infinite、XML override、active-turn 热改，或 turn/recovery snapshot 未保存所选来源要求的 manifest identity/effective scalar/完整 detector map 与算法/registry version | ConfigGeneration error、foreign XML compatibility error 或 snapshot contract failure；不 clamp、不 fallback 到更宽阈值，也不继续建立新的 Model/tool effect。A 只消费发行 manifest tuple，B/C 只消费 next-turn 冻结的完整 effective snapshot；unfinished turn 恢复原 snapshot，算法与 exact 数字继续由技术证明冻结 | AQ-029、AQ-101、AQ-154、AQ-196、AQ-197、AQ-283、CFG-13、CFG-15、LOOP-05、LOOP-14、AL06-28、AL06-50、TP-017、TP-022 |
| CV-073 | Model/Permission logical name 为空、非 well-formed UTF-8 scalar sequence、含 NUL/CR/LF/ASCII control/`[`/`]`/首尾 ASCII whitespace、超 TP-019 byte cap 或 parser/writer 不能无损往返；M05-57 A 下出现 `Abbreviation`；B 下把简称变为 required、自动生成或保存未登记暗简称；C 下 Permission/enabled Model 缺简称；B/C 下简称 grammar 非法、简称等于自己的 logical name、任一同类型长名/简称 ASCII-fold 后冲突；任一路线跟随 filesystem/locale/Unicode case mapping、跨 Model/Permission namespace 误判冲突，或 CurrentModel/CurrentPermission 把简称写成持久 identity | ConfigGeneration/selector/snapshot contract error；不按物理顺序选第一项、不自动加数字/禁用对象，也不规范化/替换用户名称或把简称变化当成永久 resource rename。输入简称只能在 admission 时解析为完整 logical name；XML 当前引用保存完整名，历史 snapshot 可条件保存当时简称说明；所有平台消费 TP-019 的同一 grammar/vectors | AQ-135、AQ-136、AQ-199、CFG-05、CFG-06、CFG-12、M05-08、M05-57、TP-019 |
| CV-074 | M05-58 A 混入 `RetryMaxDelayMs`/`RetryPolicy`，B 缺少 count/base/max 或混入 preset，C 混入任一数字字段、缺失/未知 preset；A/B 数值越过技术 hard range，B max < base；任一路线混合字段、使用未经 fixture/manifest 冻结的默认/退避/jitter、让 retry 越过 logical/turn/Runtime 门，或 request snapshot 未保存路线、effective 展开和 manifest identity | 对未开始请求为 Model ConfigGeneration error，对 active/saved request 为 snapshot/contract failure；不 clamp、不按“最像”preset 迁移、不 fallback 到另一字段路线。配置只从下一 logical request 生效；outcome unknown、任何 canonical event、协议/auth/普通 4xx/内容拒绝/cancel 仍不得重放 | D-036、AQ-140、AQ-197、AQ-221、CFG-05、MODEL-15、NET-06、LOOP-14、LOOP-27、M05-58、F4-02 |
| CV-075 | M05-59 A 允许低于版本化 `MinimumScannableSecretBytes` 的 config-secret consumer 运行、把门槛做成可调值或静默降级 B；B 把短值复制到非精确结构化目的地、仍把所有普通短字节 coincidence 当 secret 阻断/marker 却未声明收缩保证；C 因短值常见而跳过普通正文 exact scan。任一路线不跨 chunk、遗漏某个 exact pattern、让相同 raw bytes 产生多份顺序相关结果、重叠命中不取 maximal byte-interval union，或 marker 保存原值/长度/equality fingerprint | consumer admission、publication 或 scanner contract fail closed；A 只保留管理/替换/移除能力并使精确 consumer ineligible，B 只豁免低于门槛的普通正文 coincidence且必须显示 guarantee-contracted，C 继续按目的地 reject/typed marker并接受误阻断。重复值折叠为一个 pattern+稳定类别/source 集，union/admission/marker 与 registry/matcher 顺序无关；门槛与资源数值只由 fixture/manifest 冻结 | AQ-017、AQ-040、AQ-168、AQ-238、AQ-277、AQ-349、CFG-04、CTX-06、NET-03、SAFE-09、M05-59、TP-006、TP-010 |
| CV-076 | `StartupSelfTest` 非 `off|stage1|stage2|stage3`、尝试跳过前置阶段，或用 exclusions 满足启动 gate；TUI 出现 `StartupHeader`/任意启动信息 master、任一 `StartupShow*` 不是 bool、为启动信息引入未登记字段/提示符配置，或改写固定 Slogan/`>>`；`ListSortBy`/`ListSortDirection` 非登记 enum、用文件系统 ctime/mtime 代替 XML canonical time、主键相同却不按 `LogicalPath` 升序或随主方向反转 tie-break，或让排序改变 Resolver/裸启动；`AutoNameEveryMainTurns` 越界、计入非 durable main turn、复用 16 位路径 hash、忽略 `AutoRenameDisabled`，或初始名不符合 `Untitled Conversation [XXXX]`；把标记编码进名称/目录、建立通用 flags bag、手工 rename 成功却未置 true、自动 rename 错误置 true、取消后立即/追补命名，或 marker 已 true/请求已取消超时仍采用迟到名称；Permission `SystemPrompt` 越界/被 XML 覆盖/被当作 capability grant；旧 `AutoJumpToDir`/`ResumeDirectory` 仍出现，XML 保存/消费 current root/workdir/root-list/alias/selector，或 rename/rebind 没有把 canonical metadata/event 与目标路径作为同一可恢复事务 | ConfigGeneration error 或 contract-test failure；旧启动 master 是未注册且无消费者的字段，各逐字段 bool 独立生效；self-test 只能严格 Stage 1→2→3，partial 不能过 gate；Context list 默认 `updated+descending`，仅影响列表 render，主键相同始终以 `LogicalPath` 升序消歧且与 direction 无关；D-041/D-046 周期命名请求可取消且不建立 ID，任何失效/迟到结果都不采用；Permission Prompt 只是 Prompt component；唯一 Context root 只由 XML 的 `CONTEXT` 镜像父目录解码，root authority 只通过移动 XML 改变，但同一事务仍必须写 rename/rebind metadata/event、推进 `UpdatedAt` 并保持 `CreatedAt` 不变 | CFG-05、CFG-06、CFG-08、D-040、D-041、D-045 至 D-048、PJ-12、PJ-13、PJ-18、TU-18 |

`TerminateGraceMs`、全局 `OutputEncoding`、`CompactReserveTokens`、`MaxScanEntries` 若出现在 INI 或 XML，统一由 CV-003 当作 unknown/deprecated 字段处理；不得为了兼容旧草案而把它们悄悄恢复为可调配置。TS-38 C 唯一允许的是 TS-23 A typed tool envelope 中的逐调用 decoder allowlist 字段，并非配置；其余 adapter/Runtime/manifest 值与技术证明属于发行 gate，不另造假的用户字段校验。

## 字段生效与快照总表

| 字段类别 | active turn 中编辑 | 下一 turn | XML 保存 |
| --- | --- | --- | --- |
| SystemPrompt | 不改变当前 turn | 使用新 Prompt snapshot | 保存历史有效 Prompt snapshot；不作为 XML override |
| StartupSelfTest | 不影响已进入的 Agent/session | 下一次普通 Agent 进入点按 `off|stage1|stage2|stage3` 从 Stage 1 顺序重跑 | 不作 XML override；启动前无 Context 时不伪造会话事实，报告按 M05-35 |
| TUI startup information fields | 不回改已输出 transcript | 下一次启动信息逐行按各自 `StartupShow*` bool 独立渲染；没有 master | 不保存；必需错误/动作不受任何逐字段开关影响 |
| Model definition | 不改变在途/当前 turn | 若仍选择该逻辑名，先做能力/隐私预检后使用新 snapshot | 保存非秘密旧/新 snapshot 与切换/映射事件 |
| CurrentModel | 忙时记为 pending | 下一 turn 生效 | 白名单 selector |
| Permission definition / Permission.SystemPrompt | 不改变当前授权/turn | 下一 turn 同时使用新 policy snapshot 与所选 Prompt component | 保存历史 policy 及实际 Prompt component/transition；不复制定义为本机配置，Prompt 不授权 |
| CurrentPermission | 忙时记为 pending | 下一 turn 生效 | 白名单 selector |
| DoubleCheck | 不改变当前 turn 或已经创建的 pending approval；编辑只形成下一 turn 的 staged 值 | 下一 turn | tri-state override + 最终值；approval 保存创建时冻结的 effective snapshot |
| Agent budgets | 当前 turn 继续用冻结值 | 下一 turn | snapshot；白名单 override 待决 |
| stuck/no-progress thresholds | 当前 turn 继续使用 AL06-50 所选 manifest/scalar/map snapshot；编辑不重置 detector state | 下一 turn 使用完整新 effective tuple | A 保存 manifest identity + tuple；B 保存 scalar/source + detector version；C 保存完整 detector map/source + registry version；从不作为 XML override |
| ApprovalExpiryMinutes（仅 AL06-44 C） | 不改变已经创建的 approval expiry | 下一份新 approval | approval event 保存实际 created/expires/config generation；XML 不覆盖定义 |
| Network/Model retry | 不改变在途 attempt | 下一 logical request 使用 M05-58 所选 A/B/C 的完整有效展开 | 每个 request 保存 route、effective count/base/max/jitter 或 preset 展开、manifest identity 和 attempt/backoff 事实；不保存一个会随升级变义的裸 preset |
| DirectHttp policy（仅 TS-11 B/C） | 不改变已启动 direct HTTP call | 下一 direct HTTP call | operation 保存 exact origin、CA/proxy/redirect non-secret snapshot；credential 永不复制 Model 值或进入 XML |
| Model scheduler 字段 | 不移动已经 admission 的 request；等待项继续使用入队 generation | 下一次 scheduler admission | 保存声明值、实际等待/cooldown 原因与非秘密 Model identity |
| Model price/amount gate（条件） | 不改变进行中 request，也不逆向取消后验费用 | 下一 turn/request admission 使用新 price/threshold generation | 保存 exact rates/来源/估算与 reported amount 分栏；不允许 XML override |
| Exec | 不改变已启动进程 | 下一 tool call/turn | 保存有效非秘密值 |
| ContextPrompt | 当前候选不改变 active turn | 下一 turn | 当前值 + 变更事件 + snapshot |
| Context ListSortBy / ListSortDirection | 不回排已经输出的列表 | 下一次 Context 列表 render 使用 XML canonical time/name + LogicalPath tie-break | INI only；不保存、不改变 Resolver 或裸启动 |
| AutoNameEveryMainTurns / AutoRenameDisabled | 全局 interval 不改变在途命名 request 的冻结输入；新 main/退出/取消/超时或 marker 变 true 会取消/逻辑失效请求，迟到结果不采用 | 下一空闲调度点同时检查 interval、完成 main-turn 水位和标记；取消标记从新基线等待完整间隔 | 保存 interval、count、threshold intent、request/result/cancel、old/new name；`AutoRenameDisabled` 是专用 XML metadata，不是 interval override |
| LogLevel | 只有完整新 generation 载入后才影响以后可选诊断 | 继续有效 | 保存当时级别；canonical 事件不受影响 |
| NotificationChannel/Events（条件） | 不重放或撤销已经处理的 event | 下一 canonical event | 只保存实际 channel/scope generation 与 once receipt，不作为 XML override |
| endpoint disclosure consent | 不追溯改变已发送 request；binding 变化立即使尚未 admission 的 reusable consent stale | 下一 matching special-purpose request 按 AL06-51 A/B/C fresh/reuse | 每个 request 都保存 disclosure receipt；只有 C 保存 reusable per-purpose state，本机恢复可条件复用，foreign/import/rebind/remap 只作 audit |
| 外部 INI bytes | active turn 及其 child activity 永不逐字段热换；每个顶层 main/side turn admission 前完整读取 bytes/digest | 未变复用 immutable generation；变化后全量验证并自动原子替换，失败阻止该新 turn | 只写 non-secret transition/public digest，不写 private digest；无 watcher/interval/policy field |
| 其他命名 session action | 按动作契约形成 pending/事件，不开放任意 key | 声明的 next-turn/next-request | 只有白名单 selector/override 写 XML；generic `--set` 待 M05-22 |

## 仍需项目负责人明确的高杠杆选择

1. DoubleCheck 的 INI 默认是 false 还是 true；Imported XML 能否降低本机默认。
2. XML 最小覆盖白名单是否只有 Model、Permission、DoubleCheck、ContextPrompt，还是还允许预算/压缩阈值覆盖。
3. Permission **能力面**的两个独立轴：M05-16 选择粗粒度或按动作拆分 outside；M05-56 决定是否增加 SensitiveRead，若增加再由 TS-21 选择分类来源。DirectNetwork 只随 TS-11 的 direct HTTP tool 存在；名称选择器另由 M05-57 独立决定。
4. raw shell 允许即意味着可能读写/联网/越界的宽能力说明是否接受。
5. Model 首版协议是否只有 openai-chat；Endpoint 是完整 URL 还是 base URL。
6. AuthMode 是否需要显式字段；M05-13 对 HTTP loopback、Key、proxy 与 redirect downgrade 采用哪条策略。
7. Tools 是否只支持 native/off；首版是否拒绝主 Agent 使用 Tools=off Model；在线 observation 是否只作为 support/warn。
8. Model generation options 采用 adapter typed optional whitelist、可证明映射的跨协议 intent，还是完全使用 provider default；缺失是否明确“不发送”。
9. Network 默认 bundled CA、ProxyMode=environment 是否接受。
10. M05-51 的 Exec 是最小全局两字段、manifest 常量还是命名 profile；M05-15 是否保留 EnvironmentSet/Unset，M05-15 A/B 下的 inherit baseline 由 M05-55 选择什么暴露政策，且任何路线都删除 ExposeProxy。
11. SystemPrompt 多行采用反斜杠 n、三引号还是其他唯一语法；optional scalar 是否采用 M05-19 的唯一 sentinel。
12. 手工编辑是否成为正式支持入口，以及 REPL 是否必须保留注释/顺序。
13. M05-18 的 non-secret config reset 范围与 Exec environment family 原子预览，以及 M05-42 是否另外提供会复制任一 registered config-file secret 的 backup/export；Context purge 始终由 CX/F4 管理动作决定。
14. M05-50 是否完全不算金额、只接 provider reported amount，还是增加 versioned per-Model price snapshot；只有第三条路线才继续回答 AL06-43 的 display/warning/hard-admission 门。自动 preimage/undo 仍由工具包独立决定。
15. M05-14 选择公开哪些 transport limits；MaxContextMiB、Network buffer、Exec output 和循环默认数字在 XP/CentOS 7 fixture 后怎样冻结。
16. F4-02 是否加入 MaxConcurrentRequests/MinRequestIntervalMs，并怎样共享 Retry-After/cooldown。
17. M05-17 保留 LogLevel 还是删除；若保留，其唯一目的地是否只为终端和 XML optional diagnostics。
18. M05-20 怎样分别投影 conditional metadata 到 XML、reviewer、support 和 Model request。
19. M05-21 是否存在 Model/Permission Color 字段；实际语义色与 fallback 由 TU-02 独占。
20. M05-22 是否拒绝 generic `--set`，只保留注册过的命名 session actions。
21. M05-40 是否保存 provider 明确公开的 reasoning summary，以及 M05-41 的 online self-test 是否复现配置的 retry/fallback。
22. M05-12 是每次显式选择 Stage 3 reviewer，还是使用条件字段 `SelfTestReviewerModel`/全部通过模型。
23. TS-11 是否增加 direct HTTP；若增加，是否接受独立 `DirectHttp*` CA/proxy/no-proxy/redirect/exact-origin 字段族及不复用 Model credential 的边界。
24. TU-27 是否提供 bell/desktop notification；启用后 TU-30 是固定 action-required、加终态，还是开放有限 typed event allowlist。
25. AL06-44 的 pending approval 是否不过期、使用 manifest fixed expiry，还是生成有界 `ApprovalExpiryMinutes`。
26. AL06-50 的 no-progress 阈值是完全由发行 manifest 固定、只公开一个有界总阈值，还是公开版本化的少量 detector 阈值组。
27. AL06-51 的跨 endpoint 特殊 purpose 外发是每次确认、只在当前 active Context handle 内按 purpose 记忆，还是把绑定严格且可失效的 per-purpose consent 写入 Context XML。
28. M05-57 的 Model/Permission 资源 selector 是只用完整 logical name、允许 optional Abbreviation，还是要求每个可用资源显式简称；三路共享 ASCII-only fold、同类型唯一性和 XML 只写完整名。
29. M05-58 的 per-Model retry 配置面是 count+base、count+base+max，还是 `none|standard|patient` preset；精确数字、范围、jitter 与 hard maximum 由 fixture/manifest 冻结，不能把推荐路线当决定。
30. M05-59 对低于安全扫描门槛的 config-secret 是禁用精确 consumer、允许但收缩普通正文 exact-scan/XML 保证，还是继续全局扫描并接受误阻断；重复/重叠 matcher 规则不是第二张选票。

## 从候选到正式 schema 的验收物

负责人确认上述选择后，配置子系统设计至少应生成：

- 最终字段注册表和版本迁移表；
- 一份合法的最小配置、一份完整注释配置和每类无效 fixture；
- INI grammar 与多行/转义测试向量；
- Context XML override whitelist 与安全降级 fixture；
- secret 字段列表和 show-config/REPL/XML/curl 泄漏测试，并覆盖 M05-59 门槛前后、A/B/C、跨 chunk、相同值与重叠值；
- 全部 CV-* 跨字段校验的 table-driven 测试；
- 配置草稿、外部修改冲突、临时写入、flush、替换和恢复测试；
- self-test 三阶段输入/输出和不会隐式联网的测试；
- 文档、模板、REPL help 和 typed schema 一致性检查。

在这些证据完成前，本文只能叫“候选注册表”，不能据此宣称配置已经完整或可运行。
