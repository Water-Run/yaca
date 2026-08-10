# 数据分类与跨模型可见性候选

更新日期：2026-07-22

状态：Batch 06 前的候选审阅底稿；**不是**现行隐私规格

> **W3-C（2026-08-10）**：现行权威矩阵见 [`DATA-CLASSIFICATION.md`](DATA-CLASSIFICATION.md)。本文件仅保留历史风险分析；冲突时以 `DATA-CLASSIFICATION.md`、`DECISIONS.md`（D-049..D-070）为准。下文 `pending`/A/B/C 不得覆盖已选路线。

## 目的

“Key 不进 XML”只解决一种秘密。typed config-secret registry 当前至少登记 Key、proxy credential、`SecretHeader`、`EnvironmentSet` value，以及任何 adapter 后续注册为 secret 的字段；这个集合是开放的，消费者不能另写一份只认识前三项的排除名单。用户也可能把 token 粘进聊天，工作区可能有私钥，shell 输出可能打印 ambient 环境或凭据工具的结果，ContextPrompt 也可能包含内部规则。M05-59 已选择 A：低于技术证明门槛的 config-secret 不得进入精确 consumer；门槛与 matcher 仍由目标平台证据冻结。

本表统一回答一类数据是否可以：

- 发给 main、side、action-review、termination-review、compaction 或 self-test Model；
- 显示在 TUI/stderr；
- 持久化到 Context XML；
- 进入 support/export；
- 在切换到另一个 endpoint 时继续发送。

最终矩阵要由产品负责人确认的隐私边界与技术侧的 enforcement test 共同形成。当前推荐遵循“完成目的所需的最少充分信息”，但不虚称能自动发现自然语言和任意文件中的所有秘密。

## 先区分五种标记

| 标记 | 含义 |
| --- | --- |
| `never` | Runtime 硬禁止进入该目的地 |
| `needed` | 该 purpose 正常工作所需；仍受范围/大小限制 |
| `minimized` | 只发送结构化摘要或完成判断所需子集 |
| `explicit` | 只有用户本次明确选择/预览后发送 |
| `derived` | 只发送脱敏、截断、digest 或类型投影，不发送原值 |

`Prompt` 中写“不要泄露”不能替代这些 Runtime 规则。side request 无工具不是靠一句 Prompt，而是请求里根本不提供 tool schema。

## 分类与来源是两个正交维度

secret registry 的每个已登记值都必须带 source；同样的字节来自不同 source，生命周期与 admission 也不同：

| source | 含义 | 约束 owner |
| --- | --- | --- |
| `config-file` | 值实际由当前被检查的 INI/generation 承载，例如明文 Key、显式 proxy credential、条件 `SecretHeader`/`EnvironmentSet` value 或 adapter secret | typed config schema；文件 ACL/mode 不足时只由 `M05-54` 决定是否允许精确 consumer 使用 |
| `ambient-environment` | 启动环境、显式选择的 environment proxy 或其他宿主 observation | observation/generation 生命周期；不能借 config.ini 权限结论背书，也不受 `M05-54` 的文件 ACL 选项误禁 |
| `user-content` | 聊天、Prompt、文件、命令或输出中的内容；只有经 typed secret input 明确登记的值才是 registry-known，其余只是 possibly-secret | canonical user/tool-content 边界与诚实预览；启发式未命中不证明无秘密 |
| `runtime` | Runtime 临时生成或取得的 carrier、token、private binding/fingerprint | 只在最小进程内生命周期存在；不得因方便而写入 XML、argv、普通日志或 support |

`M05-54` 的问题域严格是 `source=config-file` 的秘密及承载它们的配置文件权限。它不决定 ambient 环境是否可信，不给用户正文做“已脱敏”认证，也不管理 Runtime 临时秘密。反过来，配置文件权限良好也不能放宽另外三种 source 的数据政策。M05-59 与它正交：M05-54 回答承载文件权限不足时能否使用，M05-59 回答值过短时 consumer/scanner 能承诺什么；两个结果都通过，精确 consumer 才 eligible。

### registered exact value 的统一 ingress 规则

“never 进入 XML/Model”必须在数据进入领域事实前兑现，不能等 renderer 才遮星号；但 M05-59 B 明确允许低于门槛的普通内容字节 coincidence 不被当成 secret，因此必须先区分**实际精确 secret carrier**和**普通正文中碰巧相同的字节**：

| ingress | exact registered value 命中后的规范结果 |
| --- | --- |
| 专用 config/secret carrier | 无论路线都只能去登记的精确私有目的地，不成为通用消息、tool argument 或 XML 字段。低于门槛时，M05-59 A 使该 consumer ineligible、仅保留管理/替换/删除；B/C 允许满足其他 policy 的 consumer，B 也不能把值复制到 argv/普通 carrier |
| 尚未提交的 chat/Prompt/Context name/Description、direct/raw tool argument 或 stdin | 对 M05-59 所选路线纳入 ordinary-content exact scan 的 pattern，typed reject 本次 submit/call，只显示 secret class 与 byte span，不回显值；draft 只可留在当前进程内供用户删除命中部分，F4-05 B/C 不得持久化。B 的低于门槛 coincidence 保留为原数据类，不宣称已扫描/已脱敏，并显著标记 guarantee-contracted |
| 已发生工具动作产生的 stdout/stderr/file result | 对纳入 ordinary-content exact scan 的 pattern，不能假装副作用没发生；在 TS-16/TS-39 canonical retention/digest 前把 exact bytes 换成 typed redaction marker，保留 occurrence/digest scope，不保留 raw-secret-derived digest。B 的低于门槛 coincidence 按普通 possibly-secret 内容保留并继承 export 警告 |
| 外来/第三方 XML | 对纳入 ordinary-content exact scan 的 pattern，原文件不改写；命中形成 `registered-secret-content` compatibility gap，只读浏览时 mask，任何 writable import/继续必须由 CX-07 的显式 sanitized copy 换成 typed marker，或在目标机移除/轮换 registry value 后重评。B 的低于门槛 coincidence 不形成该 exact-match gap，但必须保留外来内容和收缩保证说明 |

扫描必须跨 chunk，空值不登记，所有 secret 的 count/总 bytes 有 Runtime hard cap；M05-59 的 `MinimumScannableSecretBytes`、尾窗和 matcher 资源上限只来自 fixture/manifest，不是配置。相同 raw bytes 的多个 registry 项折叠成一个 pattern 与稳定 category/source set；全部 eligible pattern 都参与扫描，重叠命中取 maximal byte-interval union，admission/marker 不得随 registry 或 matcher 遍历顺序改变，marker 不保存原值、原长度或可离线比对的 equality fingerprint。不能根据运行时“常见/高频”临时跳过 pattern。普通内容中未登记、M05-59 B 明确豁免的过短 coincidence、编码/切片/派生的秘密仍可能持久化/发送，未命中绝不成为“安全”证明。终端/OS 自己的 paste/history 也可能已经取得原文，yaca 只能如实说明。

## 候选数据类别

| 类别 | 示例 | 默认敏感性 | canonical owner |
| --- | --- | --- | --- |
| Registered config secret | Key、proxy credential、`SecretHeader`、`EnvironmentSet` value、任何 adapter-registered secret | secret | typed secret registry；source 可为 config-file/ambient-environment/user-content/runtime |
| Connection public | Protocol、host、remote Model、窗口、TLS mode | conditional | Model snapshot |
| Connection secret-like | URL userinfo/query、内部 hostname、custom secret header name；若 schema/adapter 标为 secret 则进入同一 registry | secret/conditional | config service + typed secret registry |
| Built-in Prompt | Runtime rules、tool protocol、purpose template | internal-public | versioned program resource |
| User SystemPrompt | 全局人格/规则 | user-content/conditional | INI |
| Permission SystemPrompt | 当前命名 Permission profile 的有界模型指令；不授予能力 | user-content/conditional | INI definition；XML 保存实际采用的原文快照、digest 与 source ref |
| ContextPrompt | 当前任务长期说明 | user-content/conditional | XML |
| Current user input | 当前任务文本 | user-content | XML event |
| Historical conversation | 用户/assistant canonical messages | user-content | XML events |
| Workspace metadata | 工具实际 cwd/path、size、digest、Git status；只作历史证据 | conditional | tool result/XML；current root 不作为 XML 字段保存 |
| Workspace content | source、config、private keys | user-content/possibly-secret | tool result/XML bounded view |
| Tool schema | tool names/JSON schema/limits | internal-public | versioned snapshot |
| Tool invocation | path、raw shell command、cwd | conditional/possibly-secret | XML operation |
| Tool result | stdout/stderr/file content/diff；可能含未知 ambient/user secret | user-content/possibly-secret | XML bounded result |
| Permission/approval | profile、action snapshot、allow/deny/override | security-sensitive | XML event |
| Model reasoning | hidden chain, reasoning summary | provider-sensitive | provider adapter policy |
| Usage/cost | token counts、request IDs、estimated fee | metadata | XML event |
| Diagnostic | error causes、OS/imports、config projection | conditional | XML/stderr/support |
| Compaction summary | decisions/files/unknown/todos | user-content | XML derived event |
| Preimage attachment（仅 TS-08 B） | undo-protected mutation 前的普通文本/binary 内容 | user-content/possibly-secret | XML typed attachment；known secret capture 拒绝 |
| Unsent draft state（仅 F4-05 B/C） | 尚未提交的 composer/Prompt draft | user-content/possibly-secret | XML ephemeral session state；不是 canonical message |
| Context name proposal | `context-name` 输出、合法化结果、name-origin policy 判定与采用结果 | user-content/metadata | XML request/result + rename event |
| AutoRenameDisabled | 当前 Context 是否禁止周期自动命名 | metadata | Context XML 专用 metadata bool；不是通用 flags bag |
| Recovery evidence | pending operation、lease、last commit | security-sensitive | XML/recovery view |

## request purpose 可见性候选

下表覆盖六个核心 purpose。D-041/D-046 另行确认了可关闭的周期 `context-name` purpose；它不是常驻主请求列，只能在 `AutoNameEveryMainTurns>0`、达到 durable main-turn 周期且当前 `AutoRenameDisabled!=true` 时进入紧随总表定义的最小白名单。任一 gate 关闭时不得创建该 request 或发送 manifest。

### 总表

| 数据 | main | side | action-review | termination-review | compaction | self-test capability / semantic |
| --- | --- | --- | --- | --- | --- | --- |
| Registered config-secret value（任意 source） | never | never | never | never | never | never |
| Connection public snapshot | needed | needed | derived | derived | needed | capability: request-local minimum; semantic: minimized |
| Built-in + global/context/project Prompt | needed | needed, side template overrides tools | minimized policy subset | minimized completion contract | needed compaction contract | capability: fixed synthetic contract; semantic: minimized review contract |
| Permission SystemPrompt | 非空时作为独立 main component；PP-03 精确排位待决 | never | never；只看结构化 Permission/action snapshot | never | never | never；Stage 3 只看脱敏字段与 capability states |
| Current user input | needed | snapshot-needed | minimized if action reason needs it | minimized goal/current outcome | needed in source range | never；fixture 不是用户正文 |
| Historical conversation | current model view | durable snapshot, bounded | only relevant action context | goal/decision/evidence subset | selected source facts | never by default |
| Workspace metadata | tool/view selected | read-only existing snapshot | exact target + identity | verification summary | needed changes/unknown | never |
| Workspace file content | only through approved/read tool result | existing committed view only | never unless exact snippet is necessary and classified | derived evidence, not arbitrary files | source range may contain bounded content | never by default |
| Tool schema | needed | never | never | never | never | capability: `Tools=native` 时只给 inert synthetic fixture；semantic: never |
| Tool invocation | needed for call/result | historical snapshot only | exact proposed action | derived completed actions | needed facts in source range | never |
| Tool result | needed bounded result | historical snapshot only | prior result only if needed | verification/unknown summary | needed source facts | never |
| Approval/verdict | needed as control facts | historical read-only | current policy + exact action; no old approval token | derived blockers/overrides | needed audit facts | never |
| Hidden reasoning | provider-specific, normally not persisted/replayed | never | never | never | never | never |
| Reasoning summary | 仅按 `M05-40` 所选公开 kind 形成有界 block | 仅在已按 `M05-40` canonical 时进入 durable snapshot | never by default | derived only | source if canonical | never |
| Usage/diagnostic | Runtime metadata, not prompt by default | never | never | never | derived only | capability: own check metadata only；semantic: minimized Stage 1/2 result |
| Preimage attachment / unsent draft payload | never | never | never | never | never | never |

这里的 `never` 是**数据角色约束**：实际 auth/proxy secret 不能成为 Model/purpose 的逻辑消息、review 输入或可持久化 request manifest；它不禁止 transport adapter 为完成已经授权的请求，在最小精确 carrier 中消费该 Model 实际需要的 secret。这个 transport consumer 同时受 source、M05-54 文件权限 admission、M05-59 短值 consumer eligibility、redaction 与 TP-006 残留证明约束，且值不能因此进入模型正文或响应历史。若 M05-59 选择 B，低于门槛的普通用户/model/file/tool 内容中碰巧出现相同短 bytes 仍保留其原数据角色，因此 `never` 不再表示“所有目的地字节串都全局无此 coincidence”；UI/XML/export 必须显著说明这项保证收缩。

### main

main 看到当前有效 Prompt、model view、tool schema 和本 turn 控制状态。若当前 Permission 的有界 `SystemPrompt` 非空，候选路线把它作为来源独立的 `permission-system-prompt` component；名称、Description 和正文都不能改变 capability states，其 PP-03 精确排位仍待正式决定。main 不自动看到 INI、任何 registered config-secret value、全部环境变量、未选择的文件或支持诊断。工具读取是一次真实能力动作，仍需 Permission。D-042 已排除独立 plan state，因此不存在 `phase=plan`、PlanArtifact 或 execute-only 数据可见性；模型在普通 main turn 内陈述计划不会产生另一类控制对象或授权。

### 独立 plan state 零表面

`PJ-11=A` 已确认不提供 PlanArtifact、`.plan`、`.execute` 或 plan/execute phase。配置、Prompt purpose、数据类别、XML schema、CLI/TUI、Permission 和恢复流程都不得保留相应字段或 disabled placeholder；普通 assistant 文本中的计划只是对话正文。

### 终端-only 零表面

负责人已排除 Web、图像/截图、音频/麦克风、公共 headless/remote controller、transcription 与 TTS。它们不产生数据类别、Model purpose、发送 manifest、consent、XML element/namespace、TUI projection 或 support/export carrier。外来 XML 中的同类历史数据只能进入通用 unknown/history 或 compatibility-gap 路径，不能激活当前 Runtime；负向测试可以点名这些类别，但活动 registry 数量必须为零。

### ASCII 生成字段与 Unicode 用户数据

程序生成的 category、purpose、component kind、schema 字段、标签和 error ID 固定为 ASCII。Prompt、Context 名、路径与用户/模型正文仍是严格 UTF-8 用户数据；Windows argv、console 和文件路径通过 wide API 与内部 UTF-8 转换。终端无法显示时可用 ASCII escape 投影，但 escape 文本不能替换 XML 原文、digest、selector、hash 或文件身份。

### side

side 最多读取创建时最近 durable main view snapshot。Runtime 移除工具 schema，禁止新增 read/exec；它可以回答“现有会话里为什么 XML 重写昂贵”，不能临时读取工作区验证新事实。side response 作为 XML audit 事实保存但不进入 main view，除非用户后来显式引用/发送。

### action-review

action reviewer 的最小输入是：不可覆盖安全规则、精确 tool/action snapshot、当前 Permission 结果、模型给出的理由、相关目标身份和必要的局部上下文。它不需要完整聊天、任何 registered config-secret value、任意文件正文或工具 schema，也无工具权限。实际完整 Model 只由 AL06-08 的 action-purpose 路线选择；不能读取或跟随 AL06-49 的 termination selector/mapping。

### termination-review

termination reviewer 需要目标、用户决定、主模型 typed finish/outcome、改动/验证/unknown/todo 摘要及必要的最近消息；不需要完整 shell output 和所有文件正文。实际完整 Model 只由 AL06-49 的 termination-purpose 路线选择；AL06-07 C 仍正常执行这条路线，不能读取或跟随 action selector/mapping。唯一 verdict enum 为 `finish|continue|uncertain`；verdict 之后继续、暂停或报错的控制流只由 `AL06-26` 决定。

### compaction

compactor 必须看到被摘要事实范围，可能包含用户正文与 bounded tool result；不见任何 registered config-secret value。实际使用哪个完整 Model/endpoint 只由 `AL06-30` 决定；是否允许本次跨 endpoint 特殊 purpose 外发及其确认复用 cadence 只由 `AL06-51` 决定。本矩阵只约束该选择最终允许发送的数据，不能以历史 disclosure consent 造成 fallback、扩大 data-class envelope 或替代 `AL06-34` 的 compaction consent。

### self-test capability / semantic

Stage 1 不发 Model 请求。Stage 2 的每个真实请求都使用同一核心 `self-test` purpose 的 `phase=capability`：只发送版本化 synthetic probe 和该测项需要的最小公开能力信息；若测试 native tool wire，可附带 inert schema，但返回调用只被 parser 记录，永不进入 Tool Runtime。`Tools=off` 不发送 synthetic tool schema，只验证 off 投影以及 M05-26 路线实际要求的 control carrier。

Stage 3 使用 `phase=semantic`，只看到由 typed registry 机械生成的脱敏配置投影和明确测试说明：Model/Permission logical name、Description、有界 SystemPrompt、实际 capability matrix、Model public ID/endpoint origin 摘要以及静态/在线测试结果。它用来提示名称/说明/Prompt 与真实行为的明显错配和自然语言拼写；不见任何 registered config-secret value、完整 Context、工作区文件或真实用户聊天，也不能修改配置、推导授权或覆盖 Stage 1/2。结果只是 advisory warning。两个 phase 共享 Model scheduler，却分别拥有 request/attempt/usage/result manifest，不能把真实 Stage 2 流量藏在无 purpose 的“探测”里。

### `context-name`（已确认的周期后台 purpose）

D-041 已取代原先“仅第一个完成 turn、终身一次”的 PJ-12 B 候选。`AutoNameEveryMainTurns=N` 在每 N 个成功收口且已持久化的 main turn 后，允许调度一次低优先级、无工具 `context-name` request；`0` 关闭。它使用触发时当前 Model、独立 request identity/Prompt version/usage/result，不新增 NamingModel，不复用 side/compaction/main 的身份或工具权限。

| 数据 | `context-name` 可见性 |
| --- | --- |
| Registered config-secret value（包括 adapter 后续登记项） | `never` |
| Connection public snapshot | `needed`，只为请求归属/审计，不把 endpoint 名写进命名正文 |
| Built-in Prompt | `needed`，仅 context-name 专用格式/边界 |
| SystemPrompt/ContextPrompt/Permission Prompt/采用项目规则 | `never`；命名使用固定 built-in purpose Prompt，不把这些指令当名称控制面 |
| 当前名称、目标和最近已完成 main turns | `needed`，只取有界、已持久化的规范摘要/文本窗口 |
| 更早完整历史、side、review、compaction 原文 | `never`；可消费现有结构化目标/检查点摘要，不发送这些 purpose 的原文 |
| Workspace path、同目录 Context 名称、Git metadata | `never`；合法化和碰撞全部本地完成 |
| 文件正文、tool schema/invocation/raw result | `never`；若完成摘要已含必要文件角色，只发送最小派生描述 |
| approval/verdict/hidden reasoning/diagnostic | `never` |

输出只允许一个有界候选 basename 和可选极短理由。Runtime 在本地做非法字符、保留名、长度和 no-replace；只有当前 `AutoRenameDisabled!=true` 时才可自动提交 rename。手工 rename 的成功管理事务默认同时置 `AutoRenameDisabled=true`；自动 rename 不设置。context-repl 取消标记只从新调度基线恢复资格，不立即命名或追补。新 main、退出、显式取消、purpose deadline，或 marker 被置为 `true`，都会取消/逻辑失效尚未完成的请求；传输迟到结果只能保存 request/usage/cancel 事实，不可采用名称。不重试、不在恢复时补跑；失败、离线、输出无效或拒绝只保留当前名称，不影响 main 的完成结果。

## 显示、持久化与导出矩阵

| 数据 | TUI 正常显示 | XML | stderr | support 默认 | export/copy XML |
| --- | --- | --- | --- | --- | --- |
| Registered config-secret value | masked type/presence only | never | never | never | never |
| Public Model fields | yes, URL may be sanitized | snapshot | safe error subset | derived | included as non-secret snapshot |
| SystemPrompt/ContextPrompt | explicit view/edit | prompt snapshot/ref | startup error不回显正文 | excluded | included; warn possibly secret |
| Permission SystemPrompt | explicit view/edit；同时显示“advisory, not capability” | 实际采用的 component 原文快照 + digest/source ref | startup error不回显正文 | excluded | included as history; warn possibly secret |
| Conversation | transcript | canonical bounded facts | no | excluded | included by definition; warn |
| File content/tool output | bounded selected view | bounded canonical result/ref | no raw body | excluded | included only to schema limit/reference |
| Raw shell command | approval/tool block | operation fact | safe startup no | excluded | included; warn possibly secret |
| Approval/override | exact action + result | canonical event | no | derived counts/IDs | included as history, never current auth |
| Hidden reasoning | no | no | no | no | no |
| Reasoning summary | only as `M05-40` projection | only as `M05-40` canonical projection | no | excluded | included only if canonical |
| Context name proposal | proposal/validation/adoption outcome | request/result + rename event | no | excluded | included as historical naming evidence |
| AutoRenameDisabled | context details/status；context-repl 可显式切换 | current metadata + change/rename transaction fact | no | excluded | included；复制后继续保护手工名称 |
| Error/cause | safe card/details | canonical cause/metadata | safe startup card | derived | included if Context fact |
| Paths/hostnames | yes, safe escaped | exact UTF-8/logical data | safe escaped | derived/optional | included; may reveal environment |
| Usage/cost | status/details | canonical usage | no | aggregate | included |

上表的 Registered config-secret `never` 同样约束 Runtime 控制的精确 secret carrier。M05-59 B 下，低于门槛的普通正文 coincidence 按 Conversation/File content/Tool output 等原行处理，并继续标记 possibly-secret/guarantee-contracted；它不能被重新标成“已确认 secret”，也不能借此允许结构化 carrier 泄漏。

support 是否提供“显式包含某个 Context/event range”只由 `ED-07` 决定；若所选路线允许，生成前必须显示范围、大小和秘密提醒并允许取消。任何路线都不自动上传 support 输出。

## Context XML 的配置选择与环境证据

Context XML 中“允许出现”不等于“可以定义 INI 配置”。无条件会话覆盖与其他条件字段仍以 `M05-06` 的最终选择和配置 schema 为准；本节补齐需要跨恢复解释的条件 snapshot/session-state 投影：

- **current workspace root 不属于 XML session state。** 每个 Context 恰好一个 root，打开时只由 active XML 在 `__yaca__/CONTEXT/` 下的镜像父目录经 `LogicalPathCodec` 解码；XML 中工具 cwd/path/Git evidence 只解释历史。context-repl rebind 通过 no-replace/可恢复移动 XML 改变绑定、逻辑路径和实时 hash，不写 `CurrentWorkDir`、root list、alias 或 selector。
- **`AutoRenameDisabled` 是无条件允许的专用 XML metadata bool。** 缺失/false 允许周期命名，true 禁止；手工 rename 成功事务默认置 true，自动 rename 不置。它随 XML 导入/复制，不授予工具或网络能力，也不能被未知通用 flag 替代。

- **`CurrentExecProfile` 只在 `M05-51 C` 存在。** XML 只能保存精确 selector，以及 non-secret effective resource snapshot、schema/profile-definition identity、public digest、old/new/source/generation transition 和 CX-07 import/mapping evidence。它不能保存或覆盖 `[ExecProfile.*]` 定义，不能让 Model 选择 profile，也不能仅凭同名在另一台机器激活；定义缺失/不同或 mapping 未确认时，新 exec 保持阻断。M05-51 A/B 下 parser、writer、REPL、help 与迁移都不得生成这个 selector。
- **`CurrentModel` / `CurrentPermission` 永远以完整 logical name 作为当前 identity。** M05-57 A 不存在 `Abbreviation` 或 alias snapshot；B/C 可在 non-secret selector transition/history snapshot 中保存“当时输入/定义的简称”作为解释，但 admission 后必须解析并冻结完整名，简称变化不重写当前引用、历史或资源 identity。每个实际 request 还保存当时完整 capability snapshot 引用、profile/config generation，以及实际采用的 `Permission.SystemPrompt` component 原文/digest；这些只解释历史，不在 XML 中定义 profile。Model 与 Permission namespace 分离，XML 不能定义简称、能力、Prompt、自动生成简称或把它升级为永久 ID。
- **`ModelRetrySnapshot` 是每个 logical request/attempt 的恢复与诊断证据，不是 XML override。** M05-58 A 保存 route、effective count/base 和 manifest 提供的 exponent/jitter/max；B 保存 count/base/max 与 manifest jitter；C 保存 preset 名及当次完整 count/base/max/jitter 展开。三路都保存 manifest identity、实际 attempt/backoff/result，不能只存一个会随升级变义的裸 preset；配置修改只影响下一 logical request。
- **`ExecEnvironmentSnapshot` 是 operation/approval 的公开证据，不是 XML override。** M05-15 A/B 时记录所选 `M05-55` baseline identity/version、mode/source、canonical variable **name** 集合和 public digest；M05-15 C 只记录其版本化 clean baseline identity。任何路线都不保存环境 value、secret-derived digest、private keyed fingerprint 或可离线比对的相等性证据。环境 generation 或公开摘要变化会使未执行的旧 approval stale，私有 value binding 只存在于进程内。
- **`StuckThresholdSnapshot` 是 turn/recovery 证据，不是 XML override。** AL06-50 A 保存发行 manifest identity、实际 threshold tuple 和 detector version；B 保存 effective `MaxNoProgressRepeats`、source 与 detector version；C 保存完整 effective detector map、各项 source 与 registry version。三条路线都只在 turn 创建时冻结，运行中编辑不热换也不重置 detector state；unfinished turn 恢复原 snapshot。A 不产生 INI 字段，B/C 的字段也从不由 XML 定义或覆盖。
- **`EndpointDisclosureConsent` 只有 AL06-51 C 才是 reusable XML session state。** A 不保存 reusable state，只为每次实际 request 保存 fresh confirmation 与 disclosure receipt；B 只在当前进程的 active Context handle 内按 `purpose + exact binding` 复用，XML 仍只保存逐 request receipt；C 才按 `action-review|termination-review|compaction` purpose 保存绑定严格的 consent state，同时每次发送仍保存 exact event/view range、data classes、endpoint/Model identity 与 receipt。main/target endpoint identity、tenant/auth policy、proxy route、相关 Model/config generation、purpose、data-class envelope、mapping/import generation 或所选 Model 变化会使 state stale；同一 envelope 内 event range 增长本身不单独失效。foreign/imported XML、workspace rebind 或目标机 remap 后，历史 state 只可作 audit evidence，fresh confirm 前不得外发。

这些结构化 snapshot/session-state 不会把环境或待发送数据变成“已无秘密”。获准 shell 可以打印环境、读取用户文件或调用凭据工具；任一 direct/exec result 进入 TS-16/TS-39 canonical retention 前，M05-59 所选路线仍纳入 ordinary-content exact scan 的 registry pattern 必须变成 typed redaction marker，但未知 ambient/user secret 与 M05-59 B 明确豁免的过短 coincidence 仍可能作为 tool output 进入 XML。export/copy/support 必须因此继续显示 possibly-secret 提示，B 还必须显示 guarantee-contracted；不能把 `ExecEnvironmentSnapshot` 的 public digest、`ModelRetrySnapshot` 或 `EndpointDisclosureConsent` 当成内容安全证明。

配置 schema 的连续校验集当前是 `CV-001..076`。其中 CV-037 检查环境集合冲突，CV-048/049 检查条件 whitelist、consent/profile mapping 与 stale，CV-051 禁止结构化 XML snapshot 携带 registered secret/value-derived digest并按 M05-59 区分普通正文，CV-070 保证 collection/secret typing 不被坏 tuple 绕过，CV-071 检查 `source=config-file` 的 M05-54 permission observation 与 consumer admission，CV-072 检查 AL06-50 的 branch/orphan/range 与 turn/recovery snapshot 完整性；CV-073 检查 selector/Abbreviation，CV-074 检查 per-Model retry，CV-075 检查短 secret scanner，CV-076 检查启动 self-test、启动头、周期命名/`AutoRenameDisabled`、Permission Prompt 与 mirror-derived single-root 字段族。这里只投影这些校验的数据显示边界，不把仍待决的 A/B/C 或推荐提前当作负责人已选答案。

## 跨 endpoint Model 切换与特殊 purpose 外发

同一 Model 名也可能在配置编辑后指向另一 endpoint，因此预检比较的是有效非秘密 connection snapshot，不只比较名称。

当相应正式 owner 的路线要求跨 endpoint 预检/确认时，候选最小显示如下。main active switch 与恢复 mapping 的交互分别仍由 `AL06-10`/`AL06-29` 决定；action-review、termination-review、compaction 的 endpoint disclosure cadence 则由 `AL06-51` 独占：

```text
[ACTION] Switching Model will send Context data to a different endpoint.
  from: https://old.example/...
  to:   https://new.example/...
  messages: events 120..418 via compacted view #7
  includes: user text, source snippets, tool results, ContextPrompt
  excludes: registered config-secret values, hidden reasoning
  estimated input: 38k tokens
  tool compatibility: native -> native

  continue | cancel (default)
```

AL06-51 的三个候选投影是：A 无 reusable state，每个特殊 purpose request 都 fresh confirm；B 按当前 active Context handle + purpose + exact binding 在内存复用，进程/XML 恢复后重新确认；C 才按 Context + purpose + exact binding 把 reusable consent 写入 XML，本机恢复且 binding 未变时可复用。三条路线每次实际发送都保存 disclosure receipt；同一 data-class envelope 内新的 event/view range 不单独使 C stale，但 endpoint/Model、tenant/auth policy、proxy、相关 generation、purpose、data-class envelope、mapping/import generation 任一变化都必须重新确认。失败或状态不确定时 fail closed，不自动 fallback。

目标机器导入 XML 后映射新的 Model 时，是否以及何时请求确认服从 `AL06-29`；active main 切换服从 `AL06-10`，action-review、termination-review、compaction 的 Model 选择分别服从 `AL06-08`/`AL06-49`/`AL06-30`，它们的跨 endpoint 外发 admission 再服从 `AL06-51`。任何路线都必须按实际 purpose 和 endpoint 分别生成发送数据 manifest；一个 review purpose 的历史确认、snapshot 或 mapping 不能授权另一个 purpose，历史 snapshot 只解释过去，并不授权把历史发送给任意新 provider。AL06-51 不新增 INI key，也不创建“endpoint pair 永久授权”。

## 外来 XML 的数据与授权分离

导入 parser 先按资源上限、DTD/entity 禁止、schema/required feature 和 digest/commit 检查；通过格式检查也只说明“可读”，不说明“可信”。

- 历史 Permission capability 与实际 `SystemPrompt` component snapshot、DoubleCheck、approval 忠实显示。
- approval 永远 audit-only。
- ContextPrompt 是外来用户内容；继续前显示来源和 effective Prompt。
- 外来 Permission 名称、能力或 `SystemPrompt` 都不能创建、覆盖或自动激活本机 profile；继续前映射本机完整 logical name/schema/generation，降低本机默认安全时需要当前用户确认。
- 外部 file/attachment reference 不自动读取；先映射并走当前权限。
- 未知 optional extension 往返保存；未知 required feature 只读或拒绝继续。

## 自动秘密检测的诚实边界

可以确定发现：typed registry 已登记、当前进程仍持有且被 M05-59 所选路线纳入该目的地 exact-scan 集的 registered value。M05-59 A 对低于门槛的值禁用精确 consumer；B 允许精确私有 consumer，但普通正文中的低于门槛 coincidence 不属于这个“确定发现”承诺；C 对任意长度维持普通正文 exact scan。可以启发式警告：普通用户正文、shell output、URL query、常见 token/private key pattern、疑似凭据文件名。不能保证发现：未知 ambient 变量、自然语言中的新格式 token、编码/压缩后的秘密、模型生成的隐写或任意二进制。registry 是 typed 候选集合，不是脱离 M05-59 路线的全内容安全证明。

因此：

- 实际结构化 registered secret carrier 对禁止目的地始终硬阻断；普通内容 exact scan 按 M05-59 A/B/C，枚举由 typed registry 生成，不维护 Key/header 的手写旁路表。
- 启发式检测只能提高限制/警告，不能把未命中宣称“安全”。
- export/support 页面明确写“conversation/tool content may contain secrets”.
- 自动模型改写历史不是默认脱敏；它会破坏完整事实且仍可能漏掉。

## Owner/status 投影（不是额外问卷）

下表把旧底稿及后续审阅发现的数据边界归还给唯一正式 owner。这里没有可直接回复的编号；`TS-15` 是已经建立的 nonvote Runtime gate，其他 `pending` 行只能在列出的正式组中选择，不能在本文件再回答一遍。

| 数据边界 | 唯一 owner/status | 本矩阵只做的投影 |
| --- | --- | --- |
| action-review 最小输入 | `TS-15`，nonvote Runtime gate；Prompt purpose contract 是消费者 | 只给不可覆盖规则、精确 action/Permission snapshot、相关目标/意图/理由和判定所需局部事实；完整 Context、任意文件正文、registered config-secret value 和工具 schema 不因“复核”而开放。这个最小视图是安全边界的直接推导，不新增产品选票。 |
| termination-review 最小 evidence | `TS-15`，nonvote Runtime gate；非 `finish` 控制流由 `AL06-26` pending | 只给目标、决定、typed finish/outcome、改动、验证、unknown/todo 和必要最近事实；verdict 固定为 `finish|continue|uncertain`。最小输入不投票，verdict 后怎样继续只回复 `AL06-26`。 |
| compaction Model/endpoint | `AL06-30` pending；compaction 许可体验由 `AL06-34` pending；跨 endpoint disclosure cadence 由 `AL06-51` pending | 本表只保证所选 compactor 不见 registered config-secret value、只见被摘要的有界事实。AL06-51 的 consent 只允许精确 purpose/binding/data-class envelope 外发，不替代 AL06-34，也不授权 fallback 或扩大输入。 |
| side 看到 durable 还是 provisional | `D-033` 已确认；调度容量由 `AL06-06` pending | side 只读取允许的已提交会话信息/最近 durable snapshot，永不读取 chat draft 或 provisional model stream；调度选择不能放宽可见性。 |
| provider 公开 reasoning | `M05-40` pending | hidden reasoning 始终不请求、不推断；明确公开的 summary/text 是否显示和保存只随 `M05-40` 生成矩阵行。 |
| ContextPrompt/对话的 XML export/copy | `TS-15`，nonvote Runtime gate；XML 明文承诺由 `CX-16` pending | yaca 提供的 export/copy surface 必须先显示包含的数据类别、可能秘密和取消入口，不能声称启发式已找全；用户绕过 yaca 直接复制文件属于 OS 外部动作，程序无法拦截或补做确认。 |
| 跨 endpoint 的切换/映射/特殊 purpose 外发 | main active switch 为 `AL06-10` pending；恢复映射为 `AL06-29` pending；action-review、termination-review、compaction Model 分别为 `AL06-08`/`AL06-49`/`AL06-30` pending；三者的 endpoint disclosure cadence 与 reusable state 由 `AL06-51` pending | Model/mapping owner 决定目标，AL06-51 再以 A 每 request、B active-handle memory 或 C per-purpose XML state 决定外发 admission；三路每次发送都保存精确 manifest/receipt。action 与 termination 即使目标 endpoint 相同也不共享 consent；C 也不是 endpoint-pair 永久授权，foreign/import/rebind/remap state 只作 audit。共同不变量是不得 silent switch/fallback。 |
| support 是否包含 Context 正文 | `ED-07` pending | 只按 `ED-07` 所选路线生成 excluded、显式 event range 或最小 stdout；registered config-secret value 永不随正文选项放行。 |
| support 中 endpoint hostname/path | `M05-20` pending；XML 内投影只由 `M05-32` pending | `M05-20` 决定 reviewer/support/export 的最小化和显式增加；`M05-32` 只决定 XML snapshot，不能反向授权 support 输出。 |
| 短 config-secret consumer/scanner 保证 | `M05-59` pending；确定性 matcher 证明门为 `TP-028` | A 使门槛下 exact consumer ineligible，B 允许精确私有 consumer但收缩普通正文保证，C 对任意长度扫描；结构化 carrier 都不能泄漏。threshold 数值、重复折叠、maximal overlap union、cross-chunk 和顺序无关由 fixture/manifest 证明，不形成第四条产品路线。 |
| 配置文件权限不足时能否使用秘密 | `M05-54` pending | 只消费 `source=config-file` 的 ACL/mode observation，并按所选 A/B/C 约束精确 secret-bearing consumer；ambient/user-content/runtime source 不继承这个结论。 |
| raw shell inherit baseline | `M05-15 A/B` 时由 `M05-55` pending；`M05-15 C` 为 not-applicable | XML/approval 只投影 baseline identity、变量名集合与 public digest，不保存 value；unknown shell output 可能含秘密，不能因选择 allowlist/denylist 就标成 safe。 |
| Context 的 Exec profile 选择 | 仅 `M05-51 C`；导入/缺口分别消费 `CX-07`/`CX-18` pending | `CurrentExecProfile` 只是 selector；non-secret snapshot/transition/mapping evidence 可持久化，profile 定义、环境 value 与历史 authorization 不可随 XML 激活。 |
| Model/Permission 完整名与简称投影 | `M05-57` pending | A 无简称，B optional，C 要求 Permission/enabled Model且允许 disabled draft 暂缺；XML 当前引用始终完整名，历史简称只作 non-secret explanation，两个资源 namespace 分离。 |
| Permission SystemPrompt 的 purpose 与排位 | 字段存在性来自负责人上游答复；精确 authority order 由 `PP-03` pending | 只候选投影给 main，按有界 user-content 处理；名称/Description/正文不进入 capability evaluator，XML 保存实际 snapshot，foreign/imported snapshot 不激活本机定义。 |
| per-Model retry 的 XML/request evidence | `M05-58` pending | A/B/C 只生成各自数字/preset 字段；每次 request 保存 route、完整 effective 展开、manifest 和 attempt 事实，不把裸 preset 当跨版本恢复语义，也不把它混同 F4-02 scheduler。 |

## 实施前验证

- 为每个 request purpose 建 golden input manifest，断言禁止数据从未出现。
- 从 typed registry 自动生成 Key、proxy credential、`SecretHeader`、`EnvironmentSet` value 与 adapter secret canary，对 argv、环境 carrier、temp、XML、stderr、support、crash residue 逐 source 搜索；新增 secret 类型后测试必须自动扩展。覆盖 M05-59 A/B/C 的门槛前后、重复 raw value、重叠、cross-chunk、顺序扰动和不含 raw/length/equality fingerprint 的 marker。
- 构造对话内 token、shell 输出 secret、URL query secret、private key 文件、编码二进制，验证“硬发现/启发式/未知”三类说明诚实。
- 导入恶意 XML：`DoubleCheck=false`、最信任 Permission、伪 approval、外部引用、DTD/entity、深度/大小炸弹。
- 切换同名不同 endpoint、旧 Model missing、compact view、side 并发，验证实际发送 manifest 与 UI 预览一致。
- 覆盖 M05-57 A/B/C 的 alias requiredness/collision/ASCII-fold、完整名 XML identity，以及 M05-58 A/B/C 字段互斥/range/迁移/request snapshot。
- 覆盖 `M05-51 C` 同名不同 ExecProfile、外来 selector 未映射、profile transition，以及 `M05-55` baseline/环境 generation 变化，验证旧 approval stale、XML 无 value/private fingerprint、未知 shell secret 仍有诚实提示。
- 为 `Permission.SystemPrompt` 覆盖空/超限/Unicode/registered-secret 命中、profile 切换、同名不同 capability/Prompt、XML import 与 main-only purpose manifest；断言 Prompt 不能改变任一 Runtime verdict。
- 对 PlanArtifact/plan phase、Web、图像、音频、remote、transcription、TTS 做 category/purpose/XML/TUI/support registry 零项扫描。
- LogLevel 变化不得删除恢复必需事实，也不得让 secret 进入 trace。
