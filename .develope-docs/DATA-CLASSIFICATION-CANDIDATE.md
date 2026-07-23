# 数据分类与跨模型可见性候选

更新日期：2026-07-18

状态：候选审阅底稿；不是已确认隐私承诺

## 目的

“Key 不进 XML”只解决一种秘密。用户也可能把 token 粘进聊天，工作区可能有私钥，shell 输出可能打印环境变量，ContextPrompt 可能包含内部规则，endpoint/query 也可能带 secret。

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

## 候选数据类别

| 类别 | 示例 | 默认敏感性 | canonical owner |
| --- | --- | --- | --- |
| Credential | API Key、proxy password、secret header | secret | INI/config service |
| Connection public | Protocol、host、remote Model、窗口、TLS mode | conditional | Model snapshot |
| Connection secret-like | URL userinfo/query、内部 hostname、custom secret header name | secret/conditional | config service |
| Built-in Prompt | Runtime rules、tool protocol、purpose template | internal-public | versioned program resource |
| User SystemPrompt | 全局人格/规则 | user-content/conditional | INI |
| ContextPrompt | 当前任务长期说明 | user-content/conditional | XML |
| Current user input | 当前任务文本 | user-content | XML event |
| Historical conversation | 用户/assistant canonical messages | user-content | XML events |
| Workspace metadata | path、size、digest、Git status | conditional | tool result/XML |
| Workspace content | source、config、private keys | user-content/possibly-secret | tool result/XML bounded view |
| Tool schema | tool names/JSON schema/limits | internal-public | versioned snapshot |
| Tool invocation | path、raw shell command、cwd | conditional/possibly-secret | XML operation |
| Tool result | stdout/stderr/file content/diff | user-content/possibly-secret | XML bounded result |
| Permission/approval | profile、action snapshot、allow/deny/override | security-sensitive | XML event |
| Model reasoning | hidden chain, reasoning summary | provider-sensitive | provider adapter policy |
| Usage/cost | token counts、request IDs、estimated fee | metadata | XML event |
| Diagnostic | error causes、OS/imports、config projection | conditional | XML/stderr/support |
| Compaction summary | decisions/files/unknown/todos | user-content | XML derived event |
| Plan artifact（仅 PJ-11 B/C） | goal、拟议步骤/目标/验证、source/binding digests、state | user-content/security-sensitive | XML canonical control event；不是 approval |
| Preimage attachment（仅 TS-08 B） | undo-protected mutation 前的普通文本/binary 内容 | user-content/possibly-secret | XML typed attachment；known secret capture 拒绝 |
| Unsent draft state（仅 F4-05 B/C） | 尚未提交的 composer/Prompt draft | user-content/possibly-secret | XML ephemeral session state；不是 canonical message |
| Context name proposal | `context-name` 输出、合法化结果、用户确认/拒绝 | user-content/metadata | XML request/result + rename event |
| Recovery evidence | pending operation、lease、last commit | security-sensitive | XML/recovery view |

## request purpose 可见性候选

下表覆盖六个核心 purpose。`context-name` 不是常驻第七列：只有产品包最终选择 `PJ-12 B` 时才存在，其条件白名单紧跟总表列出；选择 `PJ-12 A/C` 时不得创建该 request、配置或发送 manifest。

### 总表

| 数据 | main | side | action-review | termination-review | compaction | self-test capability / semantic |
| --- | --- | --- | --- | --- | --- | --- |
| Credential/secret header value | never | never | never | never | never | never |
| Connection public snapshot | needed | needed | derived | derived | needed | capability: request-local minimum; semantic: minimized |
| Built-in + user Prompt | needed | needed, side template overrides tools | minimized policy subset | minimized completion contract | needed compaction contract | capability: fixed synthetic contract; semantic: minimized review contract |
| Current user input | needed | snapshot-needed | minimized if action reason needs it | minimized goal/current outcome | needed in source range | never；fixture 不是用户正文 |
| Historical conversation | current model view | durable snapshot, bounded | only relevant action context | goal/decision/evidence subset | selected source facts | never by default |
| Workspace metadata | tool/view selected | read-only existing snapshot | exact target + identity | verification summary | needed changes/unknown | never |
| Workspace file content | only through approved/read tool result | existing committed view only | never unless exact snippet is necessary and classified | derived evidence, not arbitrary files | source range may contain bounded content | never by default |
| Tool schema | needed | never | never | never | never | capability: `Tools=native` 时只给 inert synthetic fixture；semantic: never |
| Tool invocation | needed for call/result | historical snapshot only | exact proposed action | derived completed actions | needed facts in source range | never |
| Tool result | needed bounded result | historical snapshot only | prior result only if needed | verification/unknown summary | needed source facts | never |
| Approval/verdict | needed as control facts | historical read-only | current policy + exact action; no old approval token | derived blockers/overrides | needed audit facts | never |
| Plan artifact（PJ-11 B/C） | plan phase creates；execute sees exact referenced artifact + current stale check | historical snapshot only | only exact proposed action/binding if review needs it；not an approval | derived progress/stale state | source fact if selected | never |
| Hidden reasoning | provider-specific, normally not persisted/replayed | never | never | never | never | never |
| Reasoning summary | 仅按 `M05-40` 所选公开 kind 形成有界 block | 仅在已按 `M05-40` canonical 时进入 durable snapshot | never by default | derived only | source if canonical | never |
| Usage/diagnostic | Runtime metadata, not prompt by default | never | never | never | derived only | capability: own check metadata only；semantic: minimized Stage 1/2 result |
| Preimage attachment / unsent draft payload | never | never | never | never | never | never |

### main

main 看到当前有效 Prompt、model view、tool schema 和本 turn 控制状态。它不自动看到 INI、Key、全部环境变量、未选择的文件或支持诊断。工具读取是一次真实能力动作，仍需 Permission。PJ-11 B/C 下 `phase=plan` 只提供 direct list/read/search，并把新 PlanArtifact 绑定当前 goal/model-view/workspace/config/Model/Permission/tool-schema digest；artifact 不含授权，execute phase 只按稳定 ID 引用它并重新走所有动作检查。

### side

side 最多读取创建时最近 durable main view snapshot。Runtime 移除工具 schema，禁止新增 read/exec；它可以回答“现有会话里为什么 XML 重写昂贵”，不能临时读取工作区验证新事实。side response 作为 XML audit 事实保存但不进入 main view，除非用户后来显式引用/发送。

### action-review

action reviewer 的最小输入是：不可覆盖安全规则、精确 tool/action snapshot、当前 Permission 结果、模型给出的理由、相关目标身份和必要的局部上下文。它不需要完整聊天、Key、任意文件正文或工具 schema，也无工具权限。

### termination-review

termination reviewer 需要目标、用户决定、主模型 typed finish/outcome、改动/验证/unknown/todo 摘要及必要的最近消息；不需要完整 shell output 和所有文件正文。唯一 verdict enum 为 `finish|continue|uncertain`；verdict 之后继续、暂停或报错的控制流只由 `AL06-26` 决定。

### compaction

compactor 必须看到被摘要事实范围，可能包含用户正文与 bounded tool result；不见 Credential。实际使用哪个完整 Model/endpoint 只由 `AL06-30` 决定；本矩阵只约束该选择最终允许发送的数据，不另行决定确认次数或 fallback。

### self-test capability / semantic

Stage 1 不发 Model 请求。Stage 2 的每个真实请求都使用同一核心 `self-test` purpose 的 `phase=capability`：只发送版本化 synthetic probe 和该测项需要的最小公开能力信息；若测试 native tool wire，可附带 inert schema，但返回调用只被 parser 记录，永不进入 Tool Runtime。`Tools=off` 不发送 synthetic tool schema，只验证 off 投影以及 M05-26 路线实际要求的 control carrier。

Stage 3 使用 `phase=semantic`，只看到脱敏配置投影和明确测试说明：section 名、Description、permission states、Model public metadata、静态/在线测试结果；不见 Key、完整 Context、工作区文件或真实用户聊天。结果只是 advisory warning。两个 phase 共享 Model scheduler，却分别拥有 request/attempt/usage/result manifest，不能把真实 Stage 2 流量藏在无 purpose 的“探测”里。

### `context-name`（仅 `PJ-12 B`）

这不是新的待决项，而是 PJ-12 B 的数据面投影。它使用独立 request identity、Prompt version、usage 和 result，不复用 side/compaction/main 的身份。

| 数据 | `context-name` 可见性 |
| --- | --- |
| Credential、secret header、代理秘密 | `never` |
| Connection public snapshot | `needed`，只为请求归属/审计，不把 endpoint 名写进命名正文 |
| Built-in Prompt | `needed`，仅 context-name 专用格式/边界 |
| SystemPrompt/ContextPrompt/采用项目规则 | `derived`，最多提供回复语言提示；正文与权威规则不发送 |
| 首条 main 用户输入 | `needed`，有界、已持久化文本 |
| 首个完成 main turn 的 assistant 结果 | `minimized`，只含任务结果/继续事项的有界规范视图 |
| 更早完整历史、side、review、compaction 原文 | `never` |
| Workspace path、同目录 Context 名称、Git metadata | `never`；合法化和碰撞全部本地完成 |
| 文件正文、tool schema/invocation/raw result | `never`；若完成摘要已含必要文件角色，只发送最小派生描述 |
| approval/verdict/hidden reasoning/diagnostic | `never` |

输出只允许一个有界候选 basename 和可选极短理由。Runtime 在本地做非法字符、保留名、长度、collision suffix 和 no-replace，再显示建议；用户确认前不 rename。失败、离线、输出无效或拒绝只保留 provisional 名，不影响 main 的完成结果。

## 显示、持久化与导出矩阵

| 数据 | TUI 正常显示 | XML | stderr | support 默认 | export/copy XML |
| --- | --- | --- | --- | --- | --- |
| API Key/secret value | masked presence only | never | never | never | never |
| Public Model fields | yes, URL may be sanitized | snapshot | safe error subset | derived | included as non-secret snapshot |
| SystemPrompt/ContextPrompt | explicit view/edit | prompt snapshot/ref | startup error不回显正文 | excluded | included; warn possibly secret |
| Conversation | transcript | canonical bounded facts | no | excluded | included by definition; warn |
| File content/tool output | bounded selected view | bounded canonical result/ref | no raw body | excluded | included only to schema limit/reference |
| Raw shell command | approval/tool block | operation fact | safe startup no | excluded | included; warn possibly secret |
| Approval/override | exact action + result | canonical event | no | derived counts/IDs | included as history, never current auth |
| Hidden reasoning | no | no | no | no | no |
| Reasoning summary | only as `M05-40` projection | only as `M05-40` canonical projection | no | excluded | included only if canonical |
| Context name proposal | proposal/validation/confirmation block | request/result + rename event | no | excluded | included as historical naming evidence |
| Error/cause | safe card/details | canonical cause/metadata | safe startup card | derived | included if Context fact |
| Paths/hostnames | yes, safe escaped | exact UTF-8/logical data | safe escaped | derived/optional | included; may reveal environment |
| Usage/cost | status/details | canonical usage | no | aggregate | included |

support 是否提供“显式包含某个 Context/event range”只由 `ED-07` 决定；若所选路线允许，生成前必须显示范围、大小和秘密提醒并允许取消。任何路线都不自动上传 support 输出。

## 跨 endpoint Model 切换

同一 Model 名也可能在配置编辑后指向另一 endpoint，因此预检比较的是有效非秘密 connection snapshot，不只比较名称。

当相应正式 owner 的路线要求跨 endpoint 预检/确认时，候选最小显示如下；这个示例只规定 disclosure manifest，不决定“每次确认、Context 内记忆一次或不发生切换”的 cadence：

```text
[ACTION] Switching Model will send Context data to a different endpoint.
  from: https://old.example/...
  to:   https://new.example/...
  messages: events 120..418 via compacted view #7
  includes: user text, source snippets, tool results, ContextPrompt
  excludes: API Key values, hidden reasoning
  estimated input: 38k tokens
  tool compatibility: native -> native

  continue | cancel (default)
```

目标机器导入 XML 后映射新的 Model 时，是否以及何时请求确认服从 `AL06-29`；active main 切换服从 `AL06-10`，review/compaction 分别服从 `AL06-08`/`AL06-30`。任何路线都必须生成适用于实际发送的数据 manifest，且历史 snapshot 只解释过去，并不授权把历史发送给任意新 provider。

## 外来 XML 的数据与授权分离

导入 parser 先按资源上限、DTD/entity 禁止、schema/required feature 和 digest/commit 检查；通过格式检查也只说明“可读”，不说明“可信”。

- 历史 Permission/DoubleCheck/approval 忠实显示。
- approval 永远 audit-only。
- ContextPrompt 是外来用户内容；继续前显示来源和 effective Prompt。
- Permission 或 DoubleCheck 降低本机默认安全时需要当前用户确认。
- 外部 file/attachment reference 不自动读取；先映射并走当前权限。
- 未知 optional extension 往返保存；未知 required feature 只读或拒绝继续。

## 自动秘密检测的诚实边界

可以确定发现：schema 标为 secret 的 Key/header、URL userinfo、已知环境字段。可以启发式警告：常见 token/private key pattern、疑似凭据文件名。不能保证发现：自然语言中的新格式 token、编码/压缩后的秘密、模型生成的隐写或任意二进制。

因此：

- 确定 secret 字段硬阻断泄漏。
- 启发式检测只能提高限制/警告，不能把未命中宣称“安全”。
- export/support 页面明确写“conversation/tool content may contain secrets”.
- 自动模型改写历史不是默认脱敏；它会破坏完整事实且仍可能漏掉。

## Owner/status 投影（不是额外问卷）

下表把旧底稿中的十个疑问归还给唯一正式 owner。这里没有可直接回复的编号；`TS-15` 是已经建立的 nonvote Runtime gate，其他 `pending` 行只能在列出的正式组中选择，不能在本文件再回答一遍。

| 数据边界 | 唯一 owner/status | 本矩阵只做的投影 |
| --- | --- | --- |
| action-review 最小输入 | `TS-15`，nonvote Runtime gate；Prompt purpose contract 是消费者 | 只给不可覆盖规则、精确 action/Permission snapshot、相关目标/意图/理由和判定所需局部事实；完整 Context、任意文件正文、Credential 和工具 schema 不因“复核”而开放。这个最小视图是安全边界的直接推导，不新增产品选票。 |
| termination-review 最小 evidence | `TS-15`，nonvote Runtime gate；非 `finish` 控制流由 `AL06-26` pending | 只给目标、决定、typed finish/outcome、改动、验证、unknown/todo 和必要最近事实；verdict 固定为 `finish|continue|uncertain`。最小输入不投票，verdict 后怎样继续只回复 `AL06-26`。 |
| compaction Model/endpoint | `AL06-30` pending；许可体验由 `AL06-34` pending | 本表只保证所选 compactor 不见 Credential、只见被摘要的有界事实；不暗定同 endpoint、专用 Model、每次选择或确认 cadence。 |
| side 看到 durable 还是 provisional | `D-033` 已确认；调度容量由 `AL06-06` pending | side 只读取允许的已提交会话信息/最近 durable snapshot，永不读取 chat draft 或 provisional model stream；调度选择不能放宽可见性。 |
| provider 公开 reasoning | `M05-40` pending | hidden reasoning 始终不请求、不推断；明确公开的 summary/text 是否显示和保存只随 `M05-40` 生成矩阵行。 |
| ContextPrompt/对话的 XML export/copy | `TS-15`，nonvote Runtime gate；XML 明文承诺由 `CX-16` pending | yaca 提供的 export/copy surface 必须先显示包含的数据类别、可能秘密和取消入口，不能声称启发式已找全；用户绕过 yaca 直接复制文件属于 OS 外部动作，程序无法拦截或补做确认。 |
| 跨 endpoint 的切换/映射 | main active switch 为 `AL06-10` pending；恢复映射为 `AL06-29` pending；termination/compaction Model 为 `AL06-08`/`AL06-30` pending | 各 owner 决定是否会发生切换及交互；共同不变量是不得 silent switch/fallback，实际外发前按所选路线生成精确 endpoint/data manifest。本表不创建“endpoint pair 永久授权”。 |
| support 是否包含 Context 正文 | `ED-07` pending | 只按 `ED-07` 所选路线生成 excluded、显式 event range 或最小 stdout；Key/结构化 secret 永不随正文选项放行。 |
| support 中 endpoint hostname/path | `M05-20` pending；XML 内投影只由 `M05-32` pending | `M05-20` 决定 reviewer/support/export 的最小化和显式增加；`M05-32` 只决定 XML snapshot，不能反向授权 support 输出。 |
| 自动 secret detector 的 warning/block | `TS-15`，nonvote Runtime gate；证明门为 `TP-028` | schema registry 已知的结构化 secret 必须硬阻断到禁止目的地；启发式命中只能提高限制/警告，未命中不能宣称干净。pattern/threshold 是可测试的技术细节，不再形成“只警告还是阻断”的非编号问卷。 |

## 实施前验证

- 为每个 request purpose 建 golden input manifest，断言禁止数据从未出现。
- 对 argv、环境、temp、XML、stderr、support、crash residue 做 Key canary 搜索。
- 构造对话内 token、shell 输出 secret、URL query secret、private key 文件、编码二进制，验证“硬发现/启发式/未知”三类说明诚实。
- 导入恶意 XML：`DoubleCheck=false`、最信任 Permission、伪 approval、外部引用、DTD/entity、深度/大小炸弹。
- 切换同名不同 endpoint、旧 Model missing、compact view、side 并发，验证实际发送 manifest 与 UI 预览一致。
- LogLevel 变化不得删除恢复必需事实，也不得让 secret 进入 trace。
