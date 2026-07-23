# 决策包 08：Context XML、实时索引与恢复闭环

更新日期：2026-07-18

状态：等待项目负责人回复；本文所有推荐、元素名、流程和选项都不是已确认决定

## 本包要决定什么

本包回答一个核心问题：一个 Context 怎样在单个 XML 中成为可以长期保存、崩溃后恢复、跨机器接盘、被浏览器安全管理、又不会让旧 Windows 因大文件而失控的任务事实源。

它集中讨论：

- 单 XML 的三条物理路线：完整重写、必要时允许有界 WAL 退路、排除非法追加；
- “复制 XML 就能接盘”究竟保证到什么程度；
- 事实事件、snapshot pool、model-view manifest 和可重建投影怎样分工；
- 没有永久 ContextId 时，单个 XML 内怎样使用局部 ID；
- LuaExpat/Expat 候选怎样安全读取大而不可信的 XML；
- 哪些 AgentLoop 边界必须先 durable，才能联网或产生副作用；
- temp、stable lock、previous-valid 的唯一角色和崩溃真值表；
- 外来 XML、历史 Permission、ContextPrompt、DoubleCheck 和 approval 怎样重新建立本机信任；
- 路径镜像、16 位实时 hash、统一 Resolver 与 context-repl 怎样共享一套语义；
- stale selection、rename、archive、delete、quota、import mapping 和当前活动 Context 怎样收口；
- compaction 怎样只改变模型视图，不删除 XML 事实；
- XP/旧 Linux 上只用 ASCII 标签和逐行命令怎样完成 context-repl 与 recovery。

本包不决定具体 Win32/POSIX 文件 API、锁实现、flush 指令、XML C ABI、hash 库函数、毫秒阈值或 MiB 上限。负责人决定产品保证和可接受退路，技术侧必须用目标平台实测选择能兑现它的实现。

## 已经确认、这次不重新询问的前提

1. 每个活动 Context 使用一个 XML 文件作为事实存储，不改成 SQLite 或永久分段事件目录。
2. 活动文件位于 `__yaca__/CONTEXT/` 的工作路径镜像树中。
3. 已确认 Windows 示例是 `CONTEXT/C/Program Files/我的任务.xml`，对应逻辑路径和 hash 输入严格为 `/C/Program Files/我的任务.xml`。
4. Context 没有永久 ContextId、UUID 或跨重命名不变的隐藏主键。
5. 当前固定 16 字符 hash 从当前逻辑 XML 路径实时计算；重命名/移动后新 hash 生效，旧 hash 立即失效。
6. 所有 selector 入口共用统一 Resolver；距离优先，同一搜索环名称优先于 hash，当前环必须完成必要扫描后裁决。
7. 非 16 字符 hash token 的选择器不计算候选 hash；同一解析中每个 XML 候选最多做一次有效性探测和匹配。
8. `.status` 从当前运行时句柄的最新逻辑路径计算 hash，不扫描整棵 Context 树找自己。
9. 索引从当前已提交 XML 树实时派生；不建立永久 index database 作为事实源。
10. v0.1 不提供 Context fork/分支机制。
11. XML 保存完整对话、日志相关信息、会话级参数及元数据；`.cautious` 的 `DoubleCheck` 覆盖属于会话元数据。
12. UI 固定程序文案使用 English/ASCII；颜色只是增强，不依赖鼠标或全屏。

关联决定：D-021 至 D-025。

## 先统一几个通俗术语

| 术语 | 本包含义 |
| --- | --- |
| active XML | Resolver 可以发现、可作为某个 Context 当前正式版本打开的 XML |
| canonical event | 已经完成 schema 校验、足以成为会话事实的用户输入、模型结果、工具/审批/控制事件等 |
| UI delta | 流式 token、进度块、spinner 等临时显示；不等于 canonical event |
| snapshot pool | XML 内去重保存的 Model、Prompt、Permission、tool schema、会话参数等非秘密历史投影 |
| model-view manifest | 某次 Model 请求实际使用了哪些 Prompt/snapshot/event/summary，以及它们的顺序与 digest |
| current projection | 为快速阅读生成的当前状态摘要；失配时可以丢弃并由事实事件重建 |
| commit footer | 说明该完整 XML 覆盖到哪个局部事件序号和 digest 的提交元数据 |
| temp | 同目录生成中的完整新版本；未发布，不参与 Resolver |
| previous-valid | 最多一个、能够证明曾正式发布过的上一完整 XML；只用于恢复，不参与 Resolver |
| stable lock/lease | 不随 active XML replace 而换身份的单 writer 协调对象；不是会话事实 |
| recovery WAL | 只有完整重写在实测上失败时才可能允许的、有界近期事件恢复 XML |
| imported/foreign XML | 从另一机器、另一个程序或无法认证来源取得的 XML；digest 不能证明它可信 |
| observation credential | 浏览器选中时记录的路径、文件身份、大小/mtime、头部 digest 等复核依据，不是永久 ID |

## “完整保存”分成四种保证

“完整”不能等于无限内嵌每个字节，也不能只等于能看到聊天文字。推荐把保证拆开：

| 保证 | 推荐含义 |
| --- | --- |
| 可查看 | 用户输入、已显示 assistant 内容、工具/审批/错误和会话参数变化都有明确记录 |
| 可继续 | 能重建当前目标、历史决定、有效 Model/Prompt/Permission 投影、未完成事项和下一次模型视图 |
| 可审计 | 每个外部请求、工具动作、授权、结果、取消、unknown 副作用和恢复决定有局部关系 |
| 可修复 | 损坏、未知 schema、缺失 Model/工作区、未完成 operation 可以只读诊断并产生新的恢复事件，不改写旧事实 |

大工具输出可以保存受限的 canonical 文本、头尾、原始大小、encoding、truncated/reference 状态和 digest；外部附件或工作区文件不存在时必须明确显示“证据不自包含”。隐藏推理、API Key、secret header 和无限 token delta 不属于“完整对话”承诺。

## 单 XML 的三条物理路线

### 路线 A：每个 canonical durable 点完整重写（正确性基线，推荐先采用）

逻辑上事件只追加；物理上每次提交都在同目录流式生成一个完整新 XML，验证并 flush 后，用目标平台已经实测证明的 replace/publish 协议替换 active XML。

```text
active A0
  -> stream parse/copy/transform into temp T1
  -> append new canonical event/snapshot/view references
  -> write commit footer
  -> flush T1
  -> parse T1 from start and verify schema/digests
  -> preserve at most one previous-valid P0
  -> publish T1 as active A1
  -> prove publication durability
```

优点：任何对外可见的 active 文件都是一份独立、well-formed、可复制的完整 XML；没有第二份近期事件事实源，最直接兑现“复制 XML 接盘”。流式生成不要求把整个大 XML 与 DOM 同时放进 Win32 x86 内存。

代价：一次提交是 O(当前 XML 大小)，长会话累计 I/O 可能是 O(n²)。因此不能每个 token 重写，也必须在 XP x86/旧磁盘上实测大小、提交延迟、写放大和空间峰值，并在安全硬门前告警或 fail-stop。

### 路线 B：有界 recovery WAL 作为经证据触发的退路

active XML 保存已合并的完整基线，近期少量 canonical event 暂存在另一个小型、完整、well-formed 的 recovery WAL XML 中；WAL 本身仍通过 temp/replace 安全更新，并在空闲、关闭、导出、达到事件/大小门或显式 consolidation 时合并回 active XML。

```text
active base XML through event N
+ bounded WAL XML for events N+1..M
= current recoverable state

safe consolidation
  -> build one complete XML through M
  -> validate/flush/publish
  -> clear WAL only after active publication is proven
```

优点：高频 canonical event 只重写一个受硬上限约束的小文件，能显著降低长 XML 的写放大；主 XML 仍定期回到独立可读形态。

代价：WAL 未合并时，最新真相临时分布在两份文件中。盲目只复制 active XML 会丢失已 durable 的近期事件；导出/复制必须先取得锁并 consolidation，崩溃恢复也必须理解 base/WAL 关系。这会修订“任何时刻单个 active XML 就包含最新事实”的强承诺，所以只能由负责人明确允许，不能由实现暗中引入。

### 路线 C：根未闭合或在根结束标签后直接追加（直接排除）

普通 well-formed XML 只有一个根元素。保持根未闭合会让正常文件在绝大多数时间不可解析；在 `</yaca-context>` 后追加 `<event>` 会产生多个顶层内容；把多份 XML 文档串起来也不是一个合法文档。

这条路线看似 O(1) 追加，实际破坏“复制 XML 可直接读取”、标准 parser、损坏定位与第三方 conformance。除非放弃“活动文件始终是合法 XML”并重新定义成自制日志格式，否则它不是可选实现，本文明确排除。

### 推荐结论

推荐先用路线 A 建立正确性基线，同时把路线 B 写成一个必须经过硬性能门触发、再次由负责人确认的退路；路线 C 作为格式事实直接排除。

选择 CX-01=B 就同时接受两个收缩：普通外部复制只有在 Context 关闭或 consolidation 后才保证最新；WAL 永远有界且不能演变成永久分段数据库。这不是 D-035 当前“单个 Context XML 是活动事实源”的普通实现分支，而是对该保证的明确局部重开；若负责人选 B，必须同时以新决定 supersede D-035 的“任意时刻只复制 active XML”含义。这些是 B 的组成部分，不是另一个未编号选择。

## 推荐的单 XML 逻辑结构

下面只说明数据角色，不冻结最终元素拼写、属性顺序或 namespace：

```text
yaca-context
  header
    schema version, writer version, creation facts
  metadata
    current logical/workspace path, session parameters, lifecycle state
  snapshot-pool
    model snapshots (non-secret projection)
    prompt snapshots
    permission snapshots
    tool-schema snapshots
    effective session-parameter snapshots
  attachments
    conditional typed payloads such as TS-08 B preimages
  ephemeral-session-state
    conditional unsent draft payload, explicitly outside canonical conversation
  events
    canonical facts in local sequence order
  model-view-manifests
    exact ordered inputs used by each Model request
  current-projection
    rebuildable convenience view
  commit-footer
    last sequence, explicitly scoped digests, completion state
```

### 1. 事实事件是唯一历史

事实事件至少包括：

- 用户输入、queue/steer/side 的创建、取消和消费；
- 完整或明确 `interrupted/failed/refused/partial` 的 assistant response；
- request/attempt、Model error、usage 和 typed outcome；
- tool call、approval request/decision、operation start、真实或合成 result；
- Model、Prompt、Permission、DoubleCheck、预算，以及条件 ReviewModel mapping、compaction consent、workspace acknowledgement 的切换；
- adopted project-rule snapshot/transition 的 adopt、observe-changed/missing、keep、refresh、auto-replace、revoke；
- compaction、用户对摘要的纠正、Model view 激活；
- workspace/model/permission import mapping；
- turn start/end、cancel、stuck、recovery 与 unknown operation resolution；
- PJ-11 B/C 条件 PlanArtifact 的 create/cancel/stale/execute-reference 及其 goal/model-view/workspace/config/Model/Permission/tool-schema bindings；它永远不是 approval/grant；
- schema migration、rename/archive/restore 等生命周期事实。

事实只追加或由新的 superseding/resolution event 解释。不能为了“保持当前状态干净”而修改旧 approval、旧摘要或旧 Model 名。

### 2. snapshot pool 去重保存“当时有效的非秘密环境”

同一个 Model/Prompt/Permission/tool schema 可能被数百个 turn 使用，不应每条消息重复全文。snapshot pool 保存不可变版本，事件与 view 通过局部 ID 引用：

- Model snapshot：逻辑名、protocol、endpoint、remote model ID、context window、Streaming 与工具能力等非秘密投影；
- Prompt snapshot：内置 Prompt 版本、全局 SystemPrompt、ContextPrompt；实际采用的项目规则还保存完整有界 content/source/scope/digest/authority 与 PP-13 transition 引用；PP-11 B/C 时再保存 Model.CustomPrompt 完整 component、route/authority/digest 和 Model-switch transition，A 下不生成该 component；
- Permission snapshot：当时 profile 与规则摘要，用于解释历史，不自动授予未来动作；
- tool-schema snapshot：当时提供给 Model 的规范工具名、参数 schema 与版本；
- session snapshot：DoubleCheck、AL06-09 路线与可配置/固定预算来源、工作目录，以及 TS-18 B 时 INI-only Autonomy 的有效值；M05-17 A/C 时保存 exact LogLevel enum/route（B 不生成），它只解释 optional diagnostic detail、绝不改变 canonical facts；M05-06 B/C 时保存实际存在的 turn/AL06-11 A/B threshold override effective value/source，C 再保存 queue/side/tool-preview/diagnostic 四项 preference。仅在对应路线启用时还包括 AL06-08 C 的 ReviewModel mapping、AL06-11 A + AL06-34 C 的 compaction consent 和 TS-14 C 的 identity-bound workspace acknowledgement。不存在的条件字段不生成空占位。

Key、代理密码和 secret header 不进入 snapshot，也不进入 snapshot digest。相同 digest 可以复用同一 snapshot；未知或外部 snapshot 仍只是历史数据。

### 2a. 条件 attachment 与未发送 draft 不是聊天消息

- 只有 TS-08 B 才允许 `PreimageAttachment`。每项绑定 operation/tool call、规范 path/file identity、before digest、encoding、original size、stored size 和 attachment digest，普通文本按 XML 安全转义、binary 使用规范 base64；写入并 flush 成功且 per-file/per-turn/per-Context quota 都有余量后，undo-protected mutation 才可执行。已登记 secret 或命中 Runtime 已知 secret value 时 capture/admission 一并拒绝；A/C 下 attachment 类型不存在。attachment 计入单 XML/总空间硬门、复制/export/support 预览与 purge 范围，undo 只引用其稳定局部 ID。
- F4-05 B/C 才存在 `DraftSessionState`，它位于 `ephemeral-session-state` 而不是 canonical conversation/events/model view。B 由有界 idle debounce 原子替换当前 draft；C 只有 `.draft save` 才写 payload。发送/discard 时物理移除 payload，并追加只含 draft ID/digest/size/reason 的 clear fact；旧 payload 可能仍留在 previous-valid/backup，必须按隐私/清除承诺说明。A 下 section/command 不存在。恢复/复制可明确标记 `unsent draft` 并让用户 restore/discard，默认 export/support 不包含正文且必须预览；它永远不能被当作已发送用户消息。

### 3. model-view manifest 记录“模型当时真正看见什么”

每个 main、side、action-review、termination-review、compaction 或 self-test 请求都保存一个有 purpose 的 manifest；PJ-11 B/C 下 main 还必须保存 `phase=plan|execute`，A 下不得伪造该字段；`self-test` 还必须保存 `phase=capability|semantic`，Stage 1 因没有 Model request 不伪造 manifest。若且仅若 PJ-12=B 实际发起一次 `context-name` 请求，该请求也保存自己的 purpose/manifest；它是条件性的单次请求记录，不是常驻“第七类”purpose，PJ-12=A/C 时 schema/projection 不伪造该请求。每个实际 manifest 至少引用：

- ordered Prompt/snapshot segments；
- 哪些原始 event group 进入、哪些被排除；
- 使用了哪个 compaction summary 及其 source range/digest；
- Model/tool schema snapshot；
- truncation、token estimate 和安全余量；
- request/attempt 局部 ID 与最终内容 digest。

manifest 不保存带 Key 的 HTTP body，也不要求无限保存 provider wire trace。它让接盘者能够解释“旧 Model 看见了什么、现在为什么换成另一个 Model、压缩前后少了哪些原文”。

### 4. current projection 只是加速阅读

当前 Model、Permission、Prompt、未完成事项和最新 view 可以写成可直接读取的 projection，但必须记录来源事件范围/digest。失配、缺失或旧 reader 不理解时，丢弃 projection 并从事实事件重建；projection 永远不能覆盖或取代事件。

## 局部 ID：没有 ContextId 不等于没有关系

路径/hash 表示 Context 当前地址；XML 内局部 ID 表示同一文件内部的关系。两者必须严格分开。

推荐身份表：

| 局部身份 | 用途 |
| --- | --- |
| event sequence | 单调、ASCII 十进制，定义事实顺序和创建点 |
| turn ID | 关联一次用户回合及其 terminal outcome |
| input/message ID | 关联用户/assistant/side 消息和 superseding 关系 |
| request/attempt ID | 区分一次逻辑 Model 请求与传输重试 |
| tool-call/operation/result ID | 保证每个接受调用都有真实或合成结果 |
| approval ID | 把授权决定绑定到精确 operation snapshot |
| snapshot ID | 引用 immutable Model/Prompt/Permission/tool 投影 |
| compaction/view ID | 关联摘要来源、纠正和实际请求视图 |

领先候选是由创建它的 durable event sequence 派生局部 ID；已经 durable 的序号永不复用。provider 原始 request/tool-call ID 作为可重复、缺失或畸形的证据字段保存，绝不能取代 yaca 本地 ID。

每个事件还可以有完整 SHA-256 内容 digest 和 previous-event digest，用于发现意外截断、乱序或损坏。footer/root digest 必须明确规定覆盖范围并排除自身 digest 字段，避免循环定义。digest 链不是签名：能修改 XML 的程序也能重新计算 digest，不能据此认证来源或恢复授权。

精确 ID 拼写、宽度和 digest serialization 属于技术规格，不要求负责人选择 UUID、十进制还是某个 Lua table 结构；负责人只需确认“局部关系可审计，但没有永久 Context 身份”这一产品语义。

## canonical durable 点

推荐规则是：一个动作如果在崩溃后可能被重复、误授权或忘记，就必须先有足以解释它的 durable 事实。UI 流式显示则不必每个 token 重写 XML。

| 边界 | 必须先 durable 的事实 | durable 后才允许 |
| --- | --- | --- |
| 新 Context 第一条输入 | Context header、用户 input、turn start、有效 snapshot refs | 发起第一次 Model 请求 |
| 每个 Model 请求 | request ID、purpose、model-view manifest、预算/Model refs | 写网络请求 |
| assistant 完整/中断 | canonical response、finish/error、usage/attempt 关系 | 接受其中的 tool calls 或结束判断 |
| tool call 接受 | 已验证参数、tool snapshot、call/operation ID | 请求审批或准备执行 |
| approval | 精确 operation snapshot、决定、范围和来源 | 执行已批准动作 |
| 副作用开始 | operation-start 与幂等/未知风险元数据 | 调用工具/进程/网络副作用 |
| 工具结束/取消 | 真实或 synthetic result、输出边界、known/unknown 状态 | 下一次 Model 采样 |
| queue/steer/side | 类型、局部 ID、创建顺序和目标 Context/turn | 确认已接受并调度 |
| Model/Prompt/Permission/DoubleCheck 切换 | 新 snapshot 和 transition/mapping event | 下一请求使用新值 |
| compaction | summary、source digest、生成 snapshot、校验结果 | 激活新 model view |
| turn 收口 | typed terminal outcome、未完成/unknown 列表 | 开始下一 turn 或正常关闭 |
| rename/archive/delete | 操作意图、目标观察、收口状态（写入适当事实位置） | 改变 active 逻辑路径或生命周期 |

流式 token、spinner、下载进度和工具 stdout chunk 可以先作为有界 UI delta；完整 response、明确中断 response 或 canonical tool result 才提交。达到 durable 失败时必须 fail-stop：不能继续发新请求、批准或副作用。若副作用已经发生而 result 无法记录，当前 operation 进入 `unknown`，持续告警并阻止自动继续。

## temp、lock 与 previous-valid 的唯一角色

允许这三个有界辅助物，不等于允许任意 sidecar 变成第二数据库：

| 辅助物 | 允许做什么 | 禁止做什么 |
| --- | --- | --- |
| temp | 同目录构建一个候选完整 XML；验证后发布 | 参与 Resolver、被当作已提交历史、无限积累 |
| stable lock/lease | 保证最多一个 writer；保存最小 owner/epoch 证据 | 保存会话内容；只凭年龄自动抢锁；随 active replace 丢失保护 |
| previous-valid | 最多一个已经证明曾正式发布的上一代完整 XML | 平时参与搜索；保存多代隐藏历史；比 active 更新 |
| recovery WAL（若获准） | 有界保存尚未合并的近期 canonical event | 永久增长、普通 Resolver 发现、绕开 consolidation/copy 提示 |

这些是瞬时/恢复控制物，不改变长期用户数据只以 INI/XML 表达的方向。Scanner 必须用固定保留名/后缀排除它们；不能只靠“文件此刻看起来不像 XML”猜测。

锁必须稳定地绑定 Context 地址或专用协调路径。只锁住旧 active 文件 handle 不够，因为 replace 后路径可能指向新文件；陈旧 lease 也不能仅凭 mtime 或“超过五分钟”接管。具体 Win32/POSIX 锁原语由平台验证决定。

## 完整重写的崩溃真值表

下面的 `A0/A1` 是完整 active generation，`T1` 是未发布 temp，`P0` 是上一已发布 generation。表格规定恢复语义，不声称所有文件系统 API 天然实现这些结果；技术侧必须在 XP/CentOS 7 证明所选协议。

| 崩溃/启动观察 | 可以称为已提交的真值 | 恢复动作 |
| --- | --- | --- |
| 还没建立 `T1` | `A0` | 正常打开 `A0` |
| `T1` 只写了一部分，`A0` 完整 | `A0` | 忽略/隔离 `T1`；不得 salvage 成新事实 |
| `T1` 完整且验证过，但尚未 publish | `A0` | `T1` 仍不是已提交；丢弃或只作诊断候选 |
| publish 后 official path 是完整 `A1`，`P0` 也在 | `A1` | 使用 `A1`；保留/轮换最多一个 `P0` |
| official path 完整 `A0`，另有更高序号 `T1` | `A0` | 不能因序号更高自动提升 temp |
| official path 缺失/损坏，`P0` 完整且有 previous-valid 证明 | `P0` 是最后可证明事实 | 进入 recovery，只读展示；恢复时另写新 active，不覆盖原证据 |
| active 与 previous 都完整但序号/角色违反协议 | 无法自动证明 | recovery required；不简单选“数字更大” |
| active schema/digest 无效，只有可解析前缀 | 前缀不是已提交事实 | 原文件只读隔离；salvage 明确标记 unverified |
| stable lock owner 仍活跃 | 当前进程没有写权 | 拒绝第二 writer；可按已确认策略只读查看 |
| lease 看似旧但无法证明 owner 已死 | 写权未知 | 不自动抢占；重试、只读或 recovery |

进程崩溃与突然断电要分开测试。replace 返回成功并不自动证明目录项已经越过掉电边界；temp flush、active replace、previous-valid 和目录 metadata 的具体顺序必须按目标文件系统证据写入平台契约。

## 副作用崩溃真值表

| 最后 durable 事实 | 恢复时能证明什么 | 默认行为 |
| --- | --- | --- |
| 只有 tool call，尚无 operation-start | 工具没有获得“可以开始”的 durable 屏障 | 生成明确 skipped/interrupted result；不自动执行 |
| operation-start 已 durable，但 helper 有证据从未启动 | 动作未开始 | 记录 not-started/interrupted；是否重试交给新决定 |
| operation-start durable，无法证明外部动作是否完成 | 结果 unknown | 禁止自动重放；进入 recovery 让用户检查/解算 |
| operation result 已 durable | 已知结果及其边界 | 正常重建 call/result 配对 |
| approval durable，但 action snapshot 已变化或重启后来源不可信 | 历史上批准过旧动作 | approval 只作 audit；新动作重新求值/确认 |

“unknown”不是错误猜测，而是对已经无法观察的真实世界保持诚实。用户以后可以追加“确认已完成/确认未完成/仍未知”的 resolution event，但不能删除旧 operation-start。

## 如果启用 WAL，额外的真值规则

| 观察 | 当前可恢复事实 | 规则 |
| --- | --- | --- |
| base through N；WAL 完整覆盖 N+1..M | base + WAL | normal open 必须 replay 验证 WAL；raw base copy 不是最新 |
| WAL 来源 base digest/sequence 不匹配 | 无法组合 | recovery required；绝不把两条历史拼接 |
| consolidation temp 完整但未 publish | base + 旧 WAL | temp 不是新真值 |
| 新 active through M 已 publish，旧 WAL 仍在 | active through M | 只有确认 active footer 覆盖 WAL 后才能清 WAL |
| WAL 损坏，base 完整 | base 是最后独立完整事实；近期范围未知 | 隔离 WAL、只读报告丢失/未知范围，不静默忽略 |

任何复制/export 动作必须先 consolidation 到单个 XML，或明确生成一个独立完整 snapshot XML。用户不应被要求手工猜要复制哪几个控制文件。

## LuaExpat/Expat 安全读取候选

当前最合适的候选是通过窄接口封装 LuaExpat 1.5.2 + Expat 2.8.2，并由 yaca 实现固定 schema 的流式 writer。它的价值是 SAX/分块解析，不要求把完整 XML 和 DOM 同时放进 Win32 x86 内存；它本身不解决 flush、replace 或锁。

正式采用前必须满足：

- Windows x86/Lua 5.5 与 CentOS 7 x86_64/Lua 5.5 分别构建并验证 ABI；当前 Lua 5.5 smoke 不能代替目标平台证据；
- `allowDTD=false`，并优先在 Expat 构建时关闭 DTD/general entity；
- 任何 external entity 请求立即拒绝，绝不读取本地文件、UNC、URL 或网络；
- 固定 UTF-8，拒绝不支持的 encoding、XML version、DTD、processing instruction 与 schema 外结构；
- 对总字节、元素数、深度、属性数/长度、单文本、buffer、snapshot/事件数设置硬上限；
- malformed、entity expansion、超深、超大属性和 chunk 边界进入 fuzz/malformed corpus；
- parser error 不启用“尽量修好后继续 Agent”的宽松模式；活动 Context 转 recovery/read-only；
- writer 只接受固定 ASCII 元素/属性名，正确转义文本/属性，拒绝 XML 1.0 禁止字符，不产生 DTD/实体声明；
- temp 写完后用同一安全 parser 从头验证 schema/digest，再允许 publish；
- 固定来源、版本、源码 hash、许可证、编译选项和安全更新流程。

LuaExpat 没有 writer；自行实现窄 writer 不等于自行实现 parser。手写正则/字符串 XML parser、把整个文件读成 Lua string 的 DOM 库、依赖系统随意安装的 XML 命令都不适合成为默认路线。

未知 optional extension 若要往返保存，必须位于明确 extension 容器并受同样资源上限；未知 required feature 只能只读或拒绝继续，不能静默丢弃后重写。

## “复制一个 XML 就能接盘”的精确承诺

推荐承诺：一份已经提交、well-formed 的 standalone Context XML，在另一台机器上足以重建会话事实、历史环境投影、当时模型视图、未完成/unknown 状态和依赖清单；目标机无需原 yaca 的永久索引、UUID 数据库或隐藏消息文件。

它不等于把整台机器装进 XML：

| XML 应当自包含 | 仍需目标机提供/映射 |
| --- | --- |
| 完整 canonical 对话与控制事件 | API Key、代理密码和本机凭据 |
| 非秘密 Model/Prompt/Permission/tool snapshots | 一个可用且经用户确认的本机 Model/Permission 映射 |
| 每次请求的 model-view manifest | 实际 provider 服务仍然存在并兼容 |
| 工作区原逻辑路径、Git/digest 摘要、已知改动事实 | 项目文件本身或用户指定的新 workspace root |
| 有界工具结果、truncation/reference/digest | 被明确标成 external 的大附件或机器外证据 |
| compaction summary 与完整事实来源 | 目标模型的上下文窗口和工具能力 |
| unknown operation 与恢复证据 | 用户检查外部世界后给出的 resolution |

对已关闭或成功 snapshot/export 的 Context，复制该 XML 应能接盘。外部程序在 writer 活动时盲目复制不属于 atomic/latest snapshot 契约：它可能失败，也可能取得较旧 generation，不能据此声称包含最后一刻事件。受支持的热复制必须通过 context-repl 动作固定 generation，若有 WAL 则先 consolidation。

公开 schema 的 v0.1 承诺应是第三方可读、yaca 是唯一受支持 active writer。Codex、CodeWhale 或其他工具可以依据公开 schema/样例读取接盘信息，但不因为“XML 是文本”就自动获得 writer lease、迁移、unknown extension 往返和授权能力。

## 外来 XML 是数据，不是授权

外来 XML 与跨 endpoint Model 切换涉及的逐类可见/持久/导出规则另见 [数据分类候选](../DATA-CLASSIFICATION-CANDIDATE.md)；本文只定义 Context 信任、mapping 和恢复控制流。

无签名的 digest 链只能发现意外损坏，不能证明 XML 来自可信 yaca；路径位置或一个 `origin=local` 字段同样不能成为认证。安全规则不应依赖“是否成功识别外来文件”：恢复后的历史 approval 默认都不授权未来动作，任何会把当前本机安全基线调低的 XML 覆盖都需要显式确认。下面是 CX-07=A、CX-14=A 与 CX-17=A 组合后的推荐候选流程，不是额外的未编号选择：

1. 以 LuaExpat 安全子集流式解析，先做 schema/size/digest/extension 检查。
2. 只读显示来源声明、原逻辑路径、最后状态、Model/Permission/Prompt snapshots 和 portability gaps。
3. 明确映射目标 workspace、Model 与 Permission；绝不按目录名全盘搜索后自动选择。
4. imported Permission/DoubleCheck 覆盖按 CX-14 的实际选择激活；任何路线都不得静默降低本机安全基线，并且必须记录来源。
5. imported ContextPrompt 按 CX-17 的实际选择 accept/edit/disable/受限自动激活；它不能改变不可变安全规则。
6. 所有历史 approval 只作 audit-only。它们解释过去发生了什么，不能授权目标机的新 operation。
7. 本机 permission engine 对每个未来动作重新求值；历史 Permission snapshot 只是历史证据。
8. 兼容通过后，以新的 local mapping/import-accepted event 记录目标机选择，不改写原 snapshot。

同名/同路径导入必须 no-replace：digest 完全相同可以报告 already present；内容不同则让用户重命名、选择另一镜像路径或取消。不能覆盖本机 Context，也不能自动采用第一个候选。

未知 optional extension 在受限容器内往返保留；未知 required feature、较高不兼容 schema 或无法验证的安全字段只读/拒绝继续。原 XML 与诊断证据在迁移成功前保持不变。

## 路径镜像、实时 hash 与统一 Resolver

### LogicalPathCodec 必须先于 hash

hash 只接受已经规范化的逻辑路径；绝不能把各平台 native path 字符串直接交给 hash。技术规格必须为下列输入给出跨平台 golden vectors：

- Windows drive root/subdirectory、UNC/share、保留名、尾随点/空格、8.3 alias 和大小写碰撞；
- Linux `/`、非 UTF-8 原始名字节、大小写区分和 mount/link 边界；
- `.`、`..`、重复分隔符、非法 XML filename、超长路径；
- symlink、junction、reparse point、hardlink 与逃出 `CONTEXT` 根；
- Unicode/CJK 用户数据与固定 ASCII 程序字段。

CX-08=A 的用户可见方向是 16 个规范小写 hexadecimal 字符。逻辑路径仍使用 `/`、包含 `.xml`、以 UTF-8 表达用户可见名称，Windows drive 使用规范段 `C`。精确摘要算法、domain separation、取位/编码和完整事件 digest 都由 TP-012/TP-013 证据冻结；无论选哪个字母表，都不能把 16 字符地址 hash 当安全校验。

精确大小写、Unicode normalization、UNC/Linux root 编码与非法原生名字节处理需要平台 fixture 冻结，不让负责人凭感觉选择某个 Win32 API。

当前地址的权威输入永远是 Scanner/Verifier 观察到的物理位置经 `LogicalPathCodec` 转换后的逻辑路径。XML 内保存的原路径、workspace path 和历史 hash 只是解释/mapping 事实；外来 XML 自报 `/C/Work/task.xml` 不能让位于另一物理路径的文件获得那个当前地址或 hash。二者不一致时显示 mismatch 并走 mapping/recovery，不能让内容覆盖目录事实。

### Resolver 已确认的裁决流程

```text
selector + current workspace mirror start
  -> build nearest not-yet-scanned ring
  -> stream candidates once
       exact name observations
       and, only for a valid 16-char hash token, hash observations
  -> finish the ring's necessary scan
  -> same ring: exact name before hash
  -> if uniquely decidable, stop; never let a farther name beat a nearer hash
  -> otherwise continue to next non-overlapping ring
```

同环多个可用同名项返回 `AmbiguousName`；多个同 hash 返回 `HashCollision`；当前环部分不可读返回 `ScanIncomplete`，不能越过它找远处“看起来唯一”的项。高优先名称对应损坏 XML 时，推荐返回 `MatchedUnavailable`，而不是偷偷连接更远同名任务。

项目负责人已经排除 `name:`、`hash:`、`path:` 前缀；本包不重新加入。普通搜索只是列候选，精确 selector 才走上述正式裁决。

## context-repl、浏览器与 stale selection

CX-09=A 的推荐候选不加载完整对话来做日常搜索，只搜索名称、逻辑路径、精确 16 字符 hash，以及状态/时间等可安全从头部读取的元数据；选择 CX-09=B 才增加显式、有界、可取消的全文扫描。

浏览器使用有界页快照：每页 row ID 只在当前 `view generation` 内有效。刷新、搜索、外部文件变化或任何 mutation 后旧 generation 失效。select/rename/archive/delete/import 前必须：

```text
show exact logical path + current hash + intended action
  -> re-open target
  -> verify still inside CONTEXT root
  -> compare observation credential/file identity/header digest
  -> obtain mutation lock
  -> recheck source and destination
  -> apply or return TargetChanged
```

如果 row 2 已经变成另一个文件，系统不得再次按旧名称解析并操作“现在的 row 2”。它只能显示 `TargetChanged`、取消副作用、刷新并让用户重新选择。

### ASCII context-repl 候选 transcript

下面用于确认信息和动作，不冻结最终空格、命令简称或 hash 示例：

```text
[YACA] context-repl
root: C:\Tools\yaca\__yaca__\CONTEXT
path: /C/Work
view: 17

1  [DIR] demo
2  [CTX] fix-parser.xml   8a21f5c0d34071be   ready   2.4 MiB
3  [CTX] old-task.xml     1c04aa9d8a50be11   recovery-required

Commands:
  open <row>       details <row>      search <text>
  rename <row>     archive <row>      delete <row>
  up               root               refresh
  help             quit

context> details 2

[CTX]
name: fix-parser
logical path: /C/Work/fix-parser.xml
hash: 8a21f5c0d34071be
state: ready
last committed event: 418
workspace: C:\Work
portable gaps: none known

context> rename 2 parser-v2

[WARNING CTX-TARGET-CHANGED]
The selected item changed after view 17.
No file was renamed. Refresh and select it again.
```

固定标签和命令帮助是 ASCII English；Context 名、路径和正文是用户数据，可以是 Unicode。颜色只增强 `[DIR]/[CTX]/[WARNING]`，无颜色时含义完整。plain/cooked 终端用逐行命令；可识别方向键的 renderer 只翻译为相同 controller action。

## rename、archive、delete 与活动 Context

### rename

首版推荐只允许同一镜像目录内修改 basename，不同时改变关联 workspace：

```text
verify -> lock
  -> durable rename-intent(old logical path, new logical path)
  -> move_no_replace
  -> update active handle and compute new hash
  -> durable rename-completed
  -> invalidate browser views
```

成功后旧 hash 立即失效；失败时文件和句柄仍在旧路径。崩溃时，“旧路径 + pending intent”表示尚未移动，“新路径 + pending intent”表示移动已发生、需要恢复收口；若平台 fallback 可能留下双路径，必须有单独真值表，不能按 mtime 选一个。跨镜像目录移动、工作区 rebinding 和跨机器 mapping 是独立动作，不伪装成 rename。

### archive

archive 把完整 XML 移到 Scanner 明确排除的非活动区，保留原逻辑路径、最后 hash、归档原因和时间供恢复；归档项不参与普通 Resolver。restore 使用 no-replace，目标已占用时必须重命名或取消，不能覆盖。

### delete 与永久清除

CX-15=A 的推荐候选让 `delete` 默认进入同样不参与 Resolver 的回收区，并与长期 archive 在状态/列表中区分；`purge` 才永久删除。两者都显示完整目标并默认取消。损坏 XML 也只能移动/隔离，不能因无法解析就跳过确认。

永久 purge 后不保留隐藏 Context tombstone 或永久 ID；如果用户需要删除审计，必须先导出。没有文件就是已经清除，Resolver 不能依靠另一个数据库继续记住它。

archive/delete/restore 与 rename 一样，需要 `durable intent -> no-replace mutation -> durable completion` 或具有同等证据的恢复协议。若 active XML 损坏而无法追加 intent，先把原文件只读隔离并保留 observation evidence，再建立新的恢复记录；不能为了写一条“已删除”而覆盖损坏证据。

### 当前活动 Context

活动 writer 不能直接删除或归档自己的路径。必须先：收口/取消 active turn，列出 queue/side/unknown operation，完成可写 durable 点，释放 writer lock，然后让用户选择 archive-and-exit、切换其他 Context 或显式新建。不能删除后继续写旧 handle，也不能自动创建同名空 XML 让任务“复活”。

## quota、保留与硬门

“保存完整历史”不等于允许无限资源。推荐同时显示：Context 数量、活动/归档/回收区总大小、单个 XML 大小、最近 commit 延迟和临时空间需求。

- soft threshold：提前告警，建议 archive、purge、export 或新建 Context；不自动删除事实；
- hard size/commit threshold：无法继续满足安全提交预算时转只读/fail-stop，不再发新请求或副作用；
- temp space threshold：完整重写至少需要新 XML、previous-valid 和文件系统余量；不足时在写前拒绝；
- archive/recycle 仍占磁盘，必须计入总量并明确显示；
- 默认不按年龄自动删除最旧任务；永久清理由用户明确选择；
- 精确 MiB、数量、p95 commit 时间由 XP x86/旧磁盘和 CentOS 7 的 workload 实测冻结，不让负责人猜数字。

如果路线 A 在已确认的合理工作负载上超过硬门，项目必须回到 CX-01 明确选择 WAL 退路或收缩 Context 大小承诺；不能暗中降低 durable 频率、删除旧事件或继续到 OOM。

## compaction 与 XML 的交叉契约

压缩是派生 Model view，不是存储清理：

1. 完整 canonical 事实事件始终保留。
2. compaction 产生结构化 summary event，必填目标、用户决定、约束、文件/工作区变化、验证、失败尝试、unknown 副作用、待办、Model/Prompt 切换。
3. summary 记录 source event range/full digest、生成 Model/Prompt snapshot、代次和校验结果。
4. tool call/result、operation/approval/result、用户输入/直接回复、当前 active turn 和 unknown side effect 是不可拆原子组。
5. 新 model-view manifest 引用 summary + 最近完整原子组 + 当前控制状态；旧 view manifest 仍是历史事实。
6. 压缩失败、schema 无效、仍超限或无收益时保留旧 view，停止自动循环。
7. 用户纠正摘要时追加 superseding/correction event，不改写旧 summary。
8. 切回较大窗口 Model 时从完整事实重建更丰富 view；旧 summary 保留但可以不再发送。

这套关系保证新 Model 能知道原来使用的 Model/Prompt、何时切换、哪些内容是摘要，且第三方 reader 能从同一 XML 解释当前请求视图。

## ASCII recovery interaction 候选 transcript

recovery 是一套逐行 interaction，不是自动修复黑盒。这份 transcript 只冻结语义动作和默认结果；它装在独立 surface、context-repl view 还是 chat state 完全服从 PJ-08，Context 存储包不再选一次。默认动作只读/退出；任何会改变 active XML、恢复 previous-valid、映射依赖或解算 unknown 的动作都追加新事实并明确确认。

恢复 previous-valid 时，原损坏 active 先以 Scanner 排除的只读隔离角色保留，再从已验证 previous-valid 生成新的 active generation 和 recovery event；“restore”不能原地抹掉唯一故障证据。

```text
[RECOVERY CTX-INCOMPLETE]
context: fix-parser
logical path: /C/Work/fix-parser.xml
active XML: invalid commit footer
previous-valid: event 417, verified
unverified temp: event 418, ignored
writer lease: owner not running, takeover not yet approved

Unresolved operation:
  id: op-416
  tool: exec
  target: cmd.exe /c build.bat
  state: unknown
  rule: never replay automatically

Actions:
  1  Inspect active XML read-only        (default)
  2  Inspect previous-valid
  3  Restore previous-valid as a new active generation
  4  Record an operation resolution
  5  Export a standalone diagnostic XML
  q  Exit without changes

recovery>
```

若 XML 来自另一台机器，recovery/compatibility interaction 还要列出：原 workspace、建议 mapping、缺失 Model/Permission、ContextPrompt、DoubleCheck 降权、unknown required extensions 和外部 evidence gaps。没有明确选择前不发 Model 请求、不执行工具。

## 真正需要项目负责人回答的十三组问题

可以回复：`CX-01 A；CX-02 A；CX-13 A；CX-14 A；CX-16 A；CX-17 A；CX-15 B；其余接受推荐`。没有明确回复的编号继续待决，不会因为本文写了推荐就自动进入 `DECISIONS.md`。每个编号只承担一个可独立回复的产品轴；并发 writer、导入安全覆盖、ContextPrompt 激活、明文隐私边界和 archive/trash/purge 范围分别由 CX-13、CX-14、CX-17、CX-16 和 CX-15 唯一定义。

### CX-01 单 XML 的物理提交路线

通俗解释：合法 XML 不能在根结束标签后继续加事件。要么每次生成一个完整新文件，要么明确承认近期事实暂时还在一个 WAL 中。

- A：先采用完整重写；在实测硬门内坚持单个 active XML 包含最新事实，超过门就 fail-stop/只读，只有真实 XP/CentOS 7 证据失败才重新打开 WAL 决策。（推荐）
- B：明确重开并局部 supersede D-035，现在就授权有界 recovery WAL；关闭、导出和安全点必须 consolidation，WAL 未合并时不声称单独复制 active XML 已包含最新事实。

推荐 A。A 的代价是 O(n²) 累计 I/O 和更高临时空间；B 的代价是最新真相临时分布、复制前必须合并和更复杂恢复，而且选 B 不能只记录为 CX 实现偏好，必须同步修订 D-035 的产品保证。“根未闭合”或“根结束后追加片段”在格式上不是合法 XML，已作为技术事实排除，不是可回复选项。

技术侧必须证明：流式内存峰值、commit latency、写放大、flush/replace 和掉电结果；不让负责人选择文件 API 或 MiB 数字。

关联：`CTX-03`、`CTX-21`、`CTX-22`、AQ-172、AQ-227、AQ-228、AQ-303、AQ-305。

### CX-02 “复制 XML 接盘”与第三方写入边界

通俗解释：XML 可以带走会话脑海和历史证据，但不能安全地带走 API Key、整个工作区和另一个 endpoint 的授权。

- A：已关闭的完整 generation 或显式 snapshot/export 产生的 standalone XML 足以语义接盘；目标机显式映射 workspace/Model/Permission，v0.1 公开 reader/import contract，yaca 是唯一受支持 active writer。（推荐）
- B：除 A 的 reader/import contract 外，再公开 offline producer conformance；第三方可以生成新的 foreign import candidate，但绝不原地修改正被 yaca 管理的 active XML。

推荐 A。代价是热复制要经受支持动作，另一台机器第一次继续前会有 compatibility/mapping 步骤；优点是不需要隐藏 index/UUID/消息目录，也不把 secret 放进 XML。B 增加第三方 writer conformance 的长期成本。把 active schema 改成私有格式、要求另一份专有导出物才能接盘，会违反 D-035 的“复制 Context XML 可移交”保证，不是可回复选项。

技术侧必须交付公开 schema、字段语义、完整/中断/压缩/导入样例和 reference reader/conformance fixtures。

关联：`CTX-01`、`CTX-05`、`CTX-15`、AQ-041、AQ-042、AQ-161、AQ-165、AQ-169、AQ-180、AQ-210、AQ-306。

### CX-16 Context XML 明文、OS 权限与第三方 reader 的隐私边界

通俗解释：“XML 里不写 API Key”不等于 XML 没有秘密。用户消息、ContextPrompt、文件片段、shell 输出和错误详情都可能敏感。OS 目录/文件权限只能阻止未获得该账户访问权的主体，不能阻止同一账户的恶意软件、管理员、备份或用户主动复制。本组决定这一产品承诺，也决定通用第三方 XML reader 能看懂到哪一层。

- A：Context 是公开 schema 的明文 XML，yaca 只依赖已证明的 OS 目录/文件权限和安全创建模式；第三方 reader 可读取全部非 Key canonical 内容，UI/export 持续明示警告“能读该 XML 就能读会话”。（推荐）
- B：XML 结构、关系和必要元数据保持公开，允许用户为正文/Prompt/工具内容启用字段级口令加密；未解锁 reader 只能保真转运密文节点，不能声称已语义接盘。
- C：只保留公开明文 envelope/最小路由元数据，canonical payload 整体口令加密；普通第三方 XML reader 不能继续任务。选 C 必须显式修订 D-035，把“复制 XML 可接盘”改为“复制 XML 与必需解密材料才可接盘”。

推荐 A。它最符合简单、旧平台可移植和第三方接盘目标，但隐私代价必须直白告知，不能把“文件权限”宣传成加密。B/C 增加丢失口令、旧机密码库、流式解密、迁移和 reference-reader 成本。三项都不得把 API Key、proxy credential 或 secret header 写入 XML，也不承诺 secure erase。

技术侧必须用 TP-010/TP-028 验证安全创建、权限降级失败、备份/导出警告、secret canary 和第三方 reader fixture；选 B/C 还要新增密码格式/密钥生命周期证据门。

关联：D-028、D-035、`CTX-06`、`CTX-15`、`SAFE-09`、`THREAT-01`、AQ-040、AQ-041、AQ-132、AQ-238、TP-010、TP-028。

## CX-03 事实事件、snapshot 与 model-view 的物理组织（不是负责人投票）

通俗解释：D-035 已要求 XML 能回答“发生过什么、当时有效环境是什么、模型究竟看见什么”。在不改变公开 schema 语义和 reference-reader 结果的前提下，把不可变 snapshot 去重存在 pool，或把同一投影内联进 turn/request record，只是体积、流式内存和重建复杂度的实现取舍，不应让负责人凭偏好选。

技术证明必须在 TP-008/TP-010/TP-020 中比较候选，并冻结 canonical event、非秘密有效快照、每请求精确 model-view manifest、局部 ID namespace、确定性 writer 与重建测试。无论物理组织如何，Key/secret header 都不得进入 XML，只保存当前投影也不得通过技术证明。

关联：`CTX-02`、`CTX-07`、`CTX-16`、`CTX-23`、AQ-162 至 AQ-168、AQ-257 至 AQ-260。

## CX-04 canonical durable 点与批处理（不是负责人投票）

通俗解释：“外部请求/命令/文件动作前先记稳 intent，result 在下一个可产生新副作用的步骤前记稳，无法保存就 fail-stop”是避免自动重放的正确性不变量，不是性能风格选择。多个纯 UI/control 事实只有在还未对用户承诺 durable、明确标记 `not yet saved`、且不跨过任何外部动作屏障时才可合并。

精确 commit batching、flush/publish 次数和失败注入是 TP-008/TP-018 的技术证明。必须为每个 durable barrier 做 kill/disk-full/flush-fail fixture，并证明 tool call/result、approval/action、request/attempt 始终可配对。“只在 turn 结束或退出时保存”无法通过该证明。

关联：`CTX-03`、`CTX-17`、`LOOP-08`、`LOOP-13`、AQ-167、AQ-227、AQ-228、AQ-254 至 AQ-256。

### CX-05 temp、lock、previous-valid 与 recovery 默认动作

通俗解释：单个正式 XML 不等于磁盘上永远只能出现一个路径；安全替换需要临时新文件，replace 后仍需要稳定锁，坏文件还需要一份可证明的上一代。

- A：允许同目录 temp、stable writer lock/lease、最多一个 previous-valid；全部被 Resolver 排除。恢复默认只读，明确确认后才从 previous-valid 生成新 active generation。（推荐）
- B：允许同目录 temp 和 stable writer lock/lease，发布成功后不保留 previous-valid；active 损坏时只读诊断/导出，不提供回退代。
- C：允许 A 的三种有界工件；若 active 无效、previous-valid 的角色和完整性可唯一证明，则自动从它发布新 recovery generation 并记录 recovery event，其他情形才转只读。

推荐 A。A 在可恢复性与不自动改写证据之间最容易解释；B 更简单但丢失一代恢复保障，C 会在启动时自动发布新事实。本组不授权 WAL：只有 CX-01=B 时 recovery WAL 才存在，CX-01=A 时 CX-05 任何选项都不得引入 WAL。第二 writer 的用户体验由 CX-13 独立回复。

技术侧必须产出本文两张崩溃真值表、锁取得顺序、previous-valid 证明、Scanner 排除规则和 XP/CentOS 7 fault tests。

关联：`CTX-08`、`CTX-09`、`CTX-22`、AQ-043、AQ-173 至 AQ-175、AQ-304、AQ-315、AQ-316。

## CX-06 XML parser、安全子集与完整性证明（不是负责人投票）

外来的 XML 可以故意写成超深、超大或要求读取本地文件；手写字符串解析很容易把这些攻击当普通文本。项目负责人已经要求“合适的高性能 Lua XML 库 + 详细测试”，而三条实现路线——窄 LuaExpat/Expat in-process、受证据门约束的纯 Lua 流式 parser、受限独立 helper——只要兑现相同公开 contract，就不构成三种产品行为。

技术证明应优先评估成熟、窄封装的流式库，并对每个最终平台验证 Lua 5.5 ABI、Win32 x86/CentOS 7 构建、DTD/external entity 永久关闭、深度/属性/文本/总量硬门、取消、malformed corpus、fuzz、writer round-trip、许可证和内存峰值。若该候选失败，再比较纯 Lua 与 helper；选择结果、版本、hash 和失败理由进入 TP/供应链证据，而不是请负责人凭名称投票。

只有所有可行路线都会改变已确认产品保证（例如必须放弃公开 XML reader、目标平台或完整接盘）时，才以最小保证差异重新请负责人决定。

关联：`FMT-01`、`CTX-25`、AQ-161、AQ-185 至 AQ-188、TP-003、TP-008。

### CX-07 外来 XML 信任、approval 与 import mapping

通俗解释：别人给你的 XML 可以诚实记录“以前批准过删除”，也可以伪造这句话；无论哪种，都不应让新机器真的删除东西。

- A：外来 XML 先只读 compatibility report；历史 approval 永远 audit-only，pending/unknown operation 不自动执行；完成 schema/完整性检查和 workspace/Model/Permission 映射后，发布一个带 import/mapping event 的本地管理 generation 再继续。（推荐）
- B：外来 XML 始终保持只读；yaca 在新本地 Context 中完整转写已验证的 canonical history、非秘密 snapshot 和 view 关系，再建立映射和续作 turn；历史 approval/pending operation 同样只作审计。

推荐 A。A 保留原 XML 结构和局部 ID，B 以转写成本换取更清楚的外来/本地边界。两项都履行“数据不是能力”不变量，也都不拒绝 D-035 要求的跨机续作。imported Permission/DoubleCheck 的安全激活由 CX-14 独立回复，ContextPrompt 由 CX-17 独立回复。

技术侧必须实现 no-replace、schema/digest/extension 验证、秘密/gap 报告、mapping event 和 threat fixtures。

关联：`CTX-06`、`CTX-13`、`CTX-26`、`CTX-27`、`SAFE-12`、AQ-166、AQ-168 至 AQ-170、AQ-175、AQ-176、AQ-236 至 AQ-238、AQ-274、AQ-275。

### CX-08 16 字符 hash 使用哪个可见字母表

通俗解释：hash 是当前地址的短写，不是身份证。D-024 已确认长度固定为 16 字符；本组只决定用户要读、输入和复制的字母表/大小写契约，不让负责人凭喜好选摘要算法。

- A：16 个小写 hexadecimal 字符，只接受 `[0-9a-f]{16}`。（推荐）
- B：16 个小写 Crockford Base32 字符，规范输出排除 `i/l/o/u`；selector 严格按规范小写字母表匹配，不做隐式纠错。
- C：16 个 base64url 字符，使用 `A-Z a-z 0-9 - _` 并严格区分大小写。

推荐 A。它在老终端、口述、报错和手工输入中最简单；B/C 在同样 16 字符下可表达更多编码位，但复制/大小写契约更严。三项都使用已确认的逻辑路径字节输入，都不增加永久 ContextId。

底层碰撞安全摘要、domain separation、从 digest 到所选字母表的精确取位/编码、LogicalPathCodec、跨平台 golden vectors、碰撞呈现和链接逃逸全部归 TP-012/TP-013 技术证明。不完整扫描仍 fail-closed。

关联：`CTX-10`、`CTX-18`、`INDEX-01`、`INDEX-02`、`INDEX-05`、AQ-177、AQ-189、AQ-199。

### CX-09 context-repl 搜索、浏览与 stale selection

通俗解释：列表中的“第 2 项”只在当前页面快照里有意义。刷新或外部变化后，旧第 2 项不能继续代表同一个文件。

- A：提供名称/路径/精确 hash 元数据搜索，只列候选，不因“唯一模糊项”自动连接。（推荐）
- B：在 A 之上增加显式、可取消的 canonical 文本全文流式搜索；工具大输出只按 XML 已保存的规范文本/摘要搜索，结果仍只列候选。
- C：不提供模糊搜索；context-repl 只提供目录树浏览和精确 selector，资源开销最小。

推荐 A。三项都使用有界 page generation 和 observation credential，破坏动作前都复核；stale 一律返回 `TargetChanged` 并刷新，不按永久行号操作。区别只是搜索深度与 XP x86 上的延迟/内存成本。

技术侧必须证明目录枚举顺序不影响结果、每候选最多探测一次、分页/取消有界、plain/快捷键动作等价和 stale race 安全。

关联：`INDEX-04`、`INDEX-07` 至 `INDEX-11`、`INDEX-14`、`INDEX-16`、`TUI-11`、`TUI-26`。

### CX-10 rename、路径/hash 与活动 writer

通俗解释：改名会立即改变逻辑路径和 16 字符 hash；当前正在写的 Context 不能边 replace 边把旧 handle 当成新地址。archive/trash/purge 的产品范围另由 CX-15 决定。

- A：rename 首版只改同一镜像目录内的 basename；活动 Context 先到 durable idle、释放 writer，以 no-replace 发布新路径，再重新取得 writer 并同步运行时句柄/hash。（推荐）
- B：允许把 Context 移到另一个镜像目录，但必须作为显式 `rebind/move` 管理动作，重新展示 workspace/Prompt/Permission 变化并使旧 approval 失效；不把它伪装成普通 rename。
- C：只允许对非活动 Context rename；当前 Context 必须先退出或切换，再由 context-repl 改名。

推荐 A。A 保持改名语义最窄，B 增加受管理的跨目录绑定，C 最易实现但迫使用户先离开当前会话。三项都禁止活动 writer 继续写旧路径，也都不保留旧 hash 别名。

技术侧必须实现 move/publish no-replace、目标复核、句柄/hash 原子更新、reserved-tree Scanner 排除和每个崩溃点恢复。

关联：`CTX-11`、`INDEX-03`、`INDEX-15`、AQ-117、AQ-173、AQ-178、AQ-237、AQ-308。

### CX-11 quota、保留与单 XML 硬门

通俗解释：完整历史必须有边界；否则旧 XP 最终不是“保存更多”，而是 OOM、磁盘满或每句话等待很久。

- A：默认不自动删除；数量/总量/单文件/commit latency 的软硬门全部来自版本化 Runtime/benchmark manifest，不生成用户 quota 或 auto-purge 字段；所有 archive/trash 仍计入总占用。硬门后只读、导出或在仍有容量时新建 Context，禁止新副作用。（推荐）
- B：只生成三个可下调的 INI 软配额：`MaxContextMiB`（单 XML）、`MaxActiveContexts`（active 数量）与 `MaxContextTotalMiB`（active/archive/trash 总量）。超额时必须由用户显式 archive（只帮助 active 数量）、purge、导出/迁移数据根或在仍满足全部配额时新建；底层证据硬门仍 fail-stop，不自动删除。
- C：不生成 B 的 quota 字段；在 A 的证据硬门外，只生成 INI `AutoPurgeTrash=false|true` 与 true 时 required 的 `TrashGraceDays`。用户必须在 config-repl 脱敏 diff 中显式开启并给正整数天数；只有带 durable `trashed_at` 且超过 grace 的 trash 可在 maintenance 前预告清单后自动 purge，active/archive 永不自动删除。

推荐 A。它保留用户控制并让失败可预测；B 提供主动管理但不改变底层安全门，C 以两个显式持久字段和数据寿命取舍换取自动空间回收。A 下五个条件字段都不存在，B/C 字段族互斥；任何选项都不得在磁盘压力下降低 durable 频率或删除 active Context。

技术侧必须在 XP x86/旧磁盘与 CentOS 7 冻结 workload 后提出精确数字、告警余量与 temp 空间公式；不让负责人猜 MiB/毫秒。

关联：`CTX-12`、`PERF-01`、`PERF-02`、AQ-195、AQ-205、AQ-305、AQ-307。

## CX-12 compaction、Model 切换与恢复视图投影（不是负责人投票）

压缩策略、摘要/原文 view、触发顺序、执行 Model、失败重试与人工许可分别只由 AL06-11、AL06-12、AL06-30、AL06-31、AL06-34 选择；本包不能再提供一套 A/B/C 让负责人组合出相反策略。

无论那些组怎样选择，Context 层都必须保存全部 canonical facts、每次 Model old/new/reason transition 和每个 request 的实际 view manifest。若 AL06-34 C 被选中，还要以 typed session parameter + transition event 保存 `auto|ask-each`；首次询问选择 `cancel` 只保存本次取消事实，不伪造持久偏好。若策略产生 compaction/checkpoint，还要保存 producer、source event ranges/digest、schema/status/supersede 关系；若策略不产生摘要，manifest 要明确记录确定性选取与 excluded ranges。切回更大 Model 时只能从完整事实重建更丰富 view，不能因过去压缩而永久丢信息。

技术侧必须依据 AL 选择冻结 summary/checkpoint schema、原子组、view builder 和从同一 XML 确定性重建测试。这是 D-035 可移交承诺的存储投影，不是第二个产品偏好。

关联：`CTX-04`、`COMP-01` 至 `COMP-10`、AQ-179、AQ-240 至 AQ-243、AQ-309 至 AQ-311、AL06-11、AL06-12、AL06-30、AL06-31、AL06-34。

### CX-13 第二 writer 遇到活动 Context 时怎样收口

通俗解释：稳定锁只能阻止两个写者同时改文件，不会自动回答第二个 yaca 应该报错、只读打开，还是请求第一个交接。“锁很旧”不能单独证明 owner 已死。

- A：第二进程拒绝写入，但可以在标明 `read-only / writer active` 后浏览最后已提交 generation；只有平台协议能证明 owner 结束才允许取得 writer，绝不按年龄 force unlock。（推荐）
- B：当 writer 活跃时拒绝对该 Context 的所有打开，context-repl 只显示名称/路径/忙状态，不解析正文。
- C：实现协作交接；第二进程请求活着的 writer 到 durable idle 后释放，然后自己重新竞争锁；对方不响应或无法证明身份时退回 A，不强抢。

推荐 A。它只需要单 writer 协议和一个诚实的只读投影；B 更保守但降低可观察性，C 体验更好但新增跨进程身份和交接状态机。

关联：`CTX-08`、`CTX-09`、`CTX-22`、AQ-043、AQ-174、AQ-304、AQ-315、AQ-316。

### CX-14 导入后 Permission/DoubleCheck 安全覆盖怎样激活

通俗解释：XML 应忠实保留旧机器当时的 Permission/DoubleCheck 投影，但“历史上用过”不等于“新机器已授权再用”。本组只决定安全覆盖在首次新 Model 请求/工具动作前的激活强度；历史 approval 在 CX-07 中已统一为 audit-only，ContextPrompt 由 CX-17 独立决定。

- A：先按本机 schema/profile 重算安全基线；与本机已定义值精确匹配或提高保护的 imported override 可激活，任何会降低 Permission/DoubleCheck 的差异必须展示精确变化并单独确认。（推荐）
- B：任何 imported Permission/DoubleCheck 覆盖，即使与本地相同或更严，也都要在一张脱敏差异卡上确认后才激活；无法映射则不得发请求或执行工具。
- C：不激活任何 imported Permission/DoubleCheck override；它们仅作历史可见，新机器以本地默认开始，用户必须以新的本地变更事件重新设置。

推荐 A。它自动恢复相同/更严保护，又不让外来 XML 静默降低本机安全基线；B 最强调人工重新授权，C 的能力边界最简单。三项都不得把 XML 中的 Key/秘密值激活为本地 credential。

关联：`CTX-07`、`CTX-13`、`CTX-26`、`CTX-27`、`SAFE-12`、AQ-168 至 AQ-170、AQ-236 至 AQ-238、AQ-274、AQ-275。

### CX-17 导入后 ContextPrompt 怎样激活

通俗解释：ContextPrompt 不是 OS 权限，但会直接改变模型下一请求的行为。它必须连同来源、authority、digest 和历史生效范围完整保留，但是否在新机器上再次生效是独立产品选择，不能和 Permission 确认捆成一个选项。

- A：第一次新 Model 请求前显示有界 preview、完整 digest、来源和 `accept / edit / disable`；选择作为新本地 Prompt 事件记录。（推荐）
- B：通过 schema/完整性验证且来源明确是用户的 ContextPrompt 可自动激活并显示一次通知；模型、项目文件或未知来源必须按 A 确认。
- C：所有 imported ContextPrompt 默认 disabled；用户必须在 `.prompt`/Context 管理中显式 accept 或 edit，否则下一请求只使用本机有效 SystemPrompt。

推荐 A。它让语义接盘与指令注入可见性同时成立，又不强迫用户离开 recovery 流程去找 Prompt。B 对可证明的用户指令更顺滑，C 最保守。三项都要把实际激活的 Prompt snapshot/view manifest 写入 XML，不修改原历史 Prompt 事实。

关联：`CTX-07`、`CTX-13`、`CTX-27`、`INSTR-05`、AQ-168、AQ-169、AQ-236、AQ-274、PP-10、PP-12。

### CX-15 archive、trash/restore 与 purge 哪些进入 v0.1

通俗解释：archive 是“保留但不参与日常 Resolver”，trash 是“已删除但可恢复”，purge 才是“永久从 yaca 已知数据中清除”。三者不能共用一个含糊的 `delete`。

- A：v0.1 同时提供 archive/unarchive、delete-to-trash/restore 和独立 purge；archive/trash 都被普通 Resolver 排除，context-repl 可显式进入它们。（推荐）
- B：v0.1 不提供 archive；`delete` 只移入 trash，可 restore，`purge` 为独立永久动作。
- C：v0.1 不提供 archive 或 trash；只有明确命名的不可逆 `purge`，必须展示影响清单并输入非默认确认，不使用含糊 `delete`。

推荐 A。A 最完整但状态最多，B 保留日常删除的后悔路并省去 archive，C 最简单但没有恢复机会。所有选项都要求活动 Context 先 durable 收口并释放 writer，破坏动作经 stale check/no-replace，不让旧 handle 继续写入。

关联：`CTX-11`、`INDEX-03`、`INDEX-15`、AQ-117、AQ-173、AQ-178、AQ-237、AQ-308。

## 推荐的整包组合

若希望采用当前推荐基线，请明确回复全部 13 个正式组；CX-03/CX-04/CX-06 是技术证明，CX-12 是 AL06 选择的存储投影，都不在回复清单：

~~~text
CX-01 A
CX-02 A
CX-16 A
CX-05 A
CX-07 A
CX-08 A
CX-09 A
CX-10 A
CX-11 A
CX-13 A
CX-14 A
CX-17 A
CX-15 A
~~~

也可以只回复差异，例如 `本包其余接受推荐；CX-01 B；CX-09 C；CX-15 B。` 推荐不是决定，未明确回复的编号继续保持 unanswered。

## 本包确认后必须形成的权威工件

负责人回复后，应分别形成：

1. `ContextSchema`：公开 namespace/version、安全子集、事实/snapshot/view/projection/commit schema。
2. `ContextIdentity`：所有局部 ID、provider ID、event digest 和引用不变量。
3. `ContextCommitProtocol`：canonical 点、temp/previous/lock、完整重写或获准 WAL、fail-stop。
4. `ContextCrashMatrix`：每个 process crash、power loss、disk full、replace fail 和副作用边界的唯一真值。
5. `ContextImportTrust`：foreign XML、unknown extension、approval audit-only、mapping 与 secret/gap 报告。
6. `LogicalPathCodecAndHash`：Windows/Linux 映射、16 字符 hash vectors、链接/非法名规则。
7. `ContextResolver`：搜索环、裁决、结果 enum、损坏/不完整范围和复杂度门。
8. `ContextBrowserController`：有界 view generation、search、details、stale 与单一 ASCII TUI 动作。
9. `ContextWriterCoordination`：second-writer 拒绝/只读/交接、owner identity 与 takeover 证明。
10. `ContextImportSafetyActivation`：foreign mapping、approval audit-only 与 Permission/DoubleCheck 安全激活。
11. `ContextPromptActivation`：imported Prompt 的来源、preview/digest、accept/edit/disable 和实际 view 记录。
12. `ContextPrivacyBoundary`：明文/加密路线、OS 权限承诺、第三方 reader 能力和用户警告。
13. `ContextLifecycle`：rename/archive/delete/purge/restore/import/quota 状态机。
14. `ModelViewAndCompaction`：summary schema、原子组、manifest、Model 切换和恢复。
15. `ContextRecoveryUX`：ASCII transcript、只读默认、unknown resolution 与证据保留。
16. `ContextConformanceSuite`：最小/完整/中断/损坏/迁移/压缩/导入 fixtures 和 reference reader。

候选元素名和伪代码不能直接充当权威 schema。最终规格必须删除被否决分支，精确给出正常、取消、失败、恢复、资源上限和目标平台证据。

## 本包的完成标准

本包只有在下列问题都有唯一答案时才算产品决策完成：

1. 正常路线是完整重写还是已授权 WAL；非法 XML 追加已经明确排除。
2. 什么时候复制一个 XML 足以接盘，哪些本机依赖必须显式 mapping。
3. 事实事件、snapshot pool、model-view manifest 与 current projection 谁是事实、谁可重建。
4. 没有永久 ContextId 时，所有 turn/request/tool/approval/compaction 关系仍能用局部 ID 重建。
5. 哪些 canonical 点不 durable 就绝不允许联网或产生副作用。
6. temp、lock、previous-valid、可选 WAL 的角色和数量不会产生多个候选真相。
7. 每个崩溃观察能由真值表确定 active、previous、temp、WAL 与 unknown operation 的处理。
8. LuaExpat/Expat 候选只有在 DTD/entity/资源上限和两个目标 ABI 证明后才可进入发行。
9. 外来 XML 的历史 approval 永远不会变成目标机授权，导入形态与本地 generation 边界唯一。
10. imported Permission/DoubleCheck 与 ContextPrompt 的激活由两个独立决定收口，任何降权都不静默发生。
11. 路径镜像、16 字符 hash、Resolver、浏览器与 stale selection 使用同一逻辑路径和目标复核。
12. rename 和活动 writer 的收口不保留旧 hash、不继续写旧 handle。
13. 第二 writer 的拒绝、只读或协作交接有唯一策略，不能仅按 lease 年龄抢锁。
14. archive/trash/restore/purge、quota 和自动清理范围有唯一生命周期，不会覆盖、复活或误删 active。
15. Context XML 的明文/加密承诺、OS 权限边界和第三方 reader 能力有唯一说法，不把可读文件宣传为保密容器。
16. compaction 只改变派生 view，完整事实仍可让更大窗口 Model 或按 CX-16 具有读取能力的第三方 reader 恢复细节。

任何未回复推荐仍然是候选。即使十三个正式组全部回复，如果完整重写尚未通过 XP/CentOS 7 基准、XML parser ABI 未证明、崩溃矩阵未执行或公开 schema/conformance fixtures 不存在，也只能说“产品边界已决定”，不能说 Context 子系统已经达到实施或发布就绪。
