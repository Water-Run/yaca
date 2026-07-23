# 决策包 06：AgentLoop、忙时输入、DoubleCheck 与压缩视图

更新日期：2026-07-18

状态：等待项目负责人回复；本文中的推荐、枚举、字段名、默认次数、状态名和页面行为都不是已确认决定

## 本包要解决什么

本包不只讨论一个 while 循环。它要把一次用户输入从“已经接收”走到“完成、等待、拒绝、取消、预算耗尽、卡死或错误”的全过程定义成可恢复、可测试的契约：

1. 主模型怎样明确表达 finish、ask-user 和 refusal，而不是让 Runtime 猜自然语言。
2. turn、logical request、network attempt、tool call、operation、approval、side 和 compaction 怎样建立本地身份。
3. 流式响应在什么边界成为 canonical response，工具调用什么时候才算被接受。
4. queue、steer、side、cancel 四条忙时通道各自改变什么，不改变什么。
5. Permission、DoubleCheck action review、人工批准、operation durable 和真实执行怎样严格排序。
6. DoubleCheck 的结束复核怎样继续、失败和停止。
7. request、attempt、turn、Context 多层预算怎样共同限制 retry 和 stuck loop。
8. Model 切换怎样保持 turn 一致性、隐私和工具协议兼容。
9. 压缩怎样只改变模型视图，不删除 XML 的完整事实，并让另一台机器能够解释摘要来源。

逐字段预算候选参见 [配置 Schema 候选注册表](../CONFIG-SCHEMA-CANDIDATE.md)。Prompt purpose、输入白名单和工具权限参见 [Prompt 决策包](03-prompt-personality-and-instructions.md)。本包决定上游控制流，不复制完整配置表、工具 schema 或 XML XSD。

本包不决定：

- 每个 raw tool 的最终名称与参数；
- Permission profile 的完整能力矩阵；
- 单 XML 的物理替换算法；
- TUI 的最终颜色、空格与快捷键探测实现；
- provider HTTP/SSE 解析细节；
- Lua 事件泵和 Win32 helper 的具体 ABI。

这些系统必须消费本包的领域动作和状态，不能各自再发明一套完成、取消或审批逻辑。

## 已经确认、这次不重新比较的前提

1. 正常任务完成由主模型主导；Runtime 不用关键词猜“看起来完成了”。
2. DoubleCheck 是总开关；开启至少包含结束复核，关闭时没有结束复核，不再保留独立 UseTerminationEvaluator。
3. Cautious 不是权限模式；.cautious 只改变当前 Context 的 DoubleCheck 会话覆盖。
4. Enter 是 queue，Ctrl+Enter 是 steer，Alt+Enter 是 side，Esc 是 cancel；不支持组合键的终端必须有点命令后备。
5. side 是一条只读直接回复，只看已提交会话事实，没有工具，不改变主任务。
6. 同一 Context 同时最多一个 active main turn；mutating/unknown-effect 工具始终串行，只读工具是否允许受限并行由 TS-10 唯一决定。
7. 每个已接受 tool call 最终都必须有真实或 synthetic tool result。
8. 有副作用的动作执行前必须有 durable operation；结果未知时不能自动重放。
9. Context XML 保存完整 canonical 对话和控制事实；流式 token delta 只是瞬态投影。
10. 压缩只建立派生 model view，不能删除或覆盖 XML 中的事实历史。
11. 一个 turn 冻结有效 main Model、Permission、DoubleCheck、Prompt、cwd、工具集合和预算；若后续选定专用 review Model，或在 AL06-11 A 下选定专用 compaction Model，也必须在对应 request 前按 AL06-08/30 冻结并留痕。
12. Model 是完整连接实例；失败时不静默切换另一个 Model 或 endpoint。
13. 不提供 OS sandbox。Permission、LLM review 和人工批准都是策略与证据，不是隔离保证。
14. 分支对话和 fork 首版不在范围内。

side 的并发/串行时机、同时接受量和忙时第二条输入的结果由 AL06-06 单独决定。所有候选路线都必须有硬上限，不提供无界并发 side。

## 先统一术语

| 术语 | 本包中的含义 |
| --- | --- |
| Context | 一个活动 XML 及其会话事实；没有永久 ContextId |
| main turn | 一条被接受的主用户输入到一个 typed terminal outcome 的业务边界 |
| logical request | AgentLoop 的一次模型采样意图，拥有固定 purpose 和 payload digest |
| attempt | logical request 的一次实际网络传输；retry 产生新 attempt，不产生新用户意图 |
| sampling step | 一次 main request 及其 response；工具结果、steer 或 review verdict 可引起下一 step |
| canonical fact | 已完成校验并提交到 XML、可用于恢复和重建的事实 |
| transient delta | 流式文字、tool argument delta、spinner 等可丢失 UI 事件 |
| accepted tool call | 完整 response 收口、整批校验并 durable 后，Runtime 承认要处理的调用 |
| operation | 与一个精确动作快照绑定、在副作用前 durable 的执行身份 |
| side lane | 与 main lane 分离的有界只读模型请求通道；精确调度见 AL06-06 |
| model view | 某个 request 实际看到的 Prompt、摘要、原始事件组、动态状态和工具 schema 的有序投影 |
| progress fingerprint | 由规范动作、相关文件/状态 digest、结果类别和未完成项形成的防卡死指纹 |

provider 返回的 request ID、response ID 和 tool call ID 都只是外部证据。本地关系由 yaca 分配的 ID 决定。

## 三套连贯的总体 Loop 方案

### 方案 A：单一显式状态机 + durable 事件 + 一条 side lane（推荐）

- Application core 是唯一领域状态所有者。
- 同一 Context 有一个 main state machine；side 使用一个正交、最多一实例的小状态机。
- 每个外部动作都由 typed command 驱动，每次转换产生 durable fact 或 transient projection。
- 模型使用 typed control 表达 finish、ask-user、refuse。
- response 完整收口和验证后才 canonicalize；tool batch durable 后才进入 Permission。
- queue、steer、side、cancel 都有独立 envelope、ID、线性化点和恢复状态。
- XML 恢复器根据最后一个完整 canonical event 确定性收口，不重放 unknown operation。
- Lua 协程可以实现各适配器等待，但不能把协程调用栈当成唯一业务状态。

优点：最容易证明取消、审批、工具配对、DoubleCheck、压缩和恢复不变量；TUI 与 CLI 只投影同一语义。状态和事件比“一个函数返回 true/false”多，但每个模块边界清楚。

代价：实现前必须冻结状态、事件、ID、outcome 和无效转换；XML 提交测试量较大。

### 方案 B：嵌套采样协程 + 少量阶段 checkpoint

- 一个主协程依次调用 build-view、sample、run-tools、review、compact。
- queue、steer 和 cancel 由共享 mailbox 处理；side 可启第二个协程。
- 只在 turn 开始、工具前后和 turn 结束写少量 checkpoint。
- typed control 和 operation ID 仍保留，但很多中间状态由协程栈和局部 table 表达。

优点：Lua 代码短，初期容易看懂正常路径；状态枚举较少。

代价：崩溃后协程栈不存在，必须用散落 checkpoint 反推处于哪一步；steer、review retry、审批恢复和 storage fault 很容易形成第二套隐式状态机。测试只能覆盖函数路径，难以证明所有状态的 cancel 都收口一致。

### 方案 C：完整 durable workflow engine

- 所有 command、timer、retry、approval 和 worker result 都进入统一持久任务队列。
- main、side、review、compaction 和工具都是可恢复 workflow node。
- 每个 node 声明依赖、补偿、lease 和重放策略，可扩展多 Context、多 worker。

优点：长远最强的后台运行、分布式 worker、暂停恢复和观察能力。

代价：对单进程、单 Context、Lua 5.5、Win32 x86 的首版明显过重；需要 scheduler、lease、timer wheel、任务迁移和幂等协议。它会让“保持简单”变成先实现一个工作流平台。

### 推荐结论

推荐方案 A。它比方案 B 多的是明确的业务事实，不是额外产品功能；又避免方案 C 的多 worker 基础设施。状态机可以直接用 Lua table + reducer 实现，不要求引入框架。

## 推荐的组件与数据流

~~~text
TUI / CLI semantic command
          |
          v
Command normalizer
  queue / steer / side / cancel / approve / session mutation
          |
          v
AgentLoop reducer  <------------------- I/O completion events
  one main lane                         model / process / storage / timer
  zero-or-one side lane
          |
          +---- Context service: durable canonical facts
          +---- View builder: prompt + compaction + atomic event tail
          +---- Model adapter: request / attempt / normalized response
          +---- Permission service: allow / ask / deny
          +---- Review service: action / termination, no tools
          +---- Tool runner: operation -> actual result
          |
          v
Domain events -> TUI projection / CLI result / XML
~~~

核心 reducer 只接受结构化输入，并返回：

- 新领域状态；
- 必须先 durable 的事件；
- durable 成功后才可发起的 effect；
- 仅供显示的 transient event；
- effect 的取消目标和 deadline。

renderer、provider、tool runner 和 XML writer 都不能直接把 turn 标成 completed。

## typed control 与唯一 terminal outcome

### 为什么普通文本不够

下面四条自然语言都可能没有 tool call：

- “已经完成，测试通过。”
- “我需要你选择 A 还是 B。”
- “目前只完成了一半。”
- “我不能执行这个请求。”

如果 Runtime 只看 finish_reason=stop 或搜索关键词，它不能稳定区分结局。provider 的 stop 只说明一次生成结束，不说明整个任务完成。

### 候选 control 语义

基线 carrier 可以是三个 Runtime 保留、无副作用、永远不进入 Permission 的 control functions，也可以是 provider adapter 支持的等价结构。无论 carrier 怎样，进入 AgentLoop 后统一为：

~~~text
finish.v1
  result        completed | partial  # partial 仅在 AL06-36 A 时注册/接受
  report        user-facing final text
  remaining[]   required when result=partial
  evidence[]    optional local fact references

ask-user.v1
  question      one concrete question
  reason        why progress cannot safely continue
  choices[]     optional concise choices

refuse.v1
  reason        user-facing refusal reason
  alternative   optional safe alternative
~~~

若且仅若 PJ-11 B/C 启用独立 plan phase，还必须在 AL06-02 已选 carrier 中条件注册一个同等无副作用、无 Permission 的 control：

~~~text
plan-ready.v1
  goal          normalized goal
  steps[]       ordered intent/evidence steps, not executable approvals
  expected-effects[]
  verification[]
  risks[]
  open-questions[]
~~~

Runtime 验证它后补齐不可由模型伪造的身份与 digest，形成 PlanArtifact；它本身不执行任何 action。PJ-11 A 时 `phase`、`plan-ready`、PlanArtifact 及相关事件/字段均不注册，不保留空 seam。

候选校验规则：

1. 一个 response 最多一个 control。
2. control 可以伴随普通说明文本，但不能与 executable tool calls 同批出现。
3. finish(completed) 不能同时声明仍有必需未完成项。
4. finish(partial) 必须明确 remaining。
5. ask-user 不得伪装批准请求；人工工具审批使用独立 approval 状态。
6. refuse 不等于 provider refusal；两者来源分别记录。
7. control 不是工具副作用，不消耗 tool-call budget，但消耗本次 model request 和 token。

### terminal outcome 候选

每个 main turn 只能有一个 outcome；另用 progress、reason、unknown-effects 和 receipt 表达细节：

| outcome | 直接来源 | 含义 |
| --- | --- | --- |
| completed | finish(completed)，或仅在 AL06-38 C 下由兼容 stop 归一化；需要的 termination review 已通过 | 主模型明确或兼容表达完成 |
| partial | 若 AL06-36 允许，来自 finish(partial) 且需要的 review 通过 | 主模型明确收口为部分完成 |
| waiting-user | ask-user、AL06-38 选择的普通 yield 路径、PJ-11 B/C 的 plan-ready、review 无法判断或需要用户选择 | 可以继续，但必须先有新用户决定 |
| refused | 主模型 refuse 或 provider refusal | 请求被拒绝，不是网络失败 |
| cancelled | 用户取消当前 turn | 已发生动作按真实结果保留 |
| budget-exhausted | Runtime 硬预算达到上限 | 不因已有进展改写为 completed |
| stuck | 警告后仍重复且没有规范状态变化 | 防卡死停止 |
| error | 不可恢复的协议、模型、工具、存储或内部错误 | 失败类别和可能副作用必须显示 |

普通、合法、无工具、无 control 的 response 必须显示和保存；它是否直接形成 waiting-user、先做一次 control correction，或兼容为隐式完成，由 AL06-38 唯一决定。

provider content filter/refusal 规范化为独立 response outcome，不走 transport retry。若此前已有可用事实，terminal outcome 仍可为 refused，并在 progress=partial 中诚实说明；不能把拒绝伪装成主模型 finish(partial)。

Runtime 最终显示由两部分组成：

- 主模型 report 或可见回复；
- Runtime receipt：真实 outcome、改动/operation、验证证据、unknown effects、预算停止原因和 queued count。

Runtime 不改写模型的自然语言结论，但也不允许它覆盖取消、预算或存储错误事实。

## 本地身份与因果关系

### 三个核心 ID

| ID | 创建时点 | 生命周期与关系 |
| --- | --- | --- |
| turn-id | 主用户输入 durable 接受时 | 一个 main turn 唯一；直到 turn-ended |
| request-id | 准备一个固定 purpose/model-view 的 logical request 时 | 属于 main turn 或 side；continuation/review 以及仅 AL06-11 A 的 model compaction 各是新 request |
| attempt-id | 每次真正准备发送 HTTP 请求时 | 属于一个 request；transport retry 只增加 attempt |

推荐使用单 XML 内不复用的 ASCII 十进制本地 ID，并带类型前缀显示，例如 turn-41、request-97、attempt-101。精确表示由 AL06-03 单独决定。文件重命名、路径 hash 改变或复制到另一台机器不会改变这些 XML 内部关系。

### 其他本地 ID

- input-id：queue、steer 和主输入的独立身份。
- side-id：一次旁问及其 response 的身份。
- response-id：一个被接受或明确拒绝的 normalized response。
- tool-call-id：yaca 分配；provider-call-id 只作为证据。
- operation-id：绑定规范 tool、版本、参数、cwd、目标新鲜度和批准 digest。
- approval-id：绑定一个 operation snapshot，不是通用授权票。
- review-id：action-review 或 termination-review verdict。
- compaction-id：一份结构化压缩记录及其来源范围。
- event-seq：XML 内所有 canonical facts 的总顺序。

ID 在 durable 创建事件成功后才可对外使用。崩溃留下的已分配数字不要求回收；绝不能为了编号连续而复用。

### request 与 attempt 的边界

- 相同 payload 因安全的连接失败重发：同一 request，新 attempt。
- 已收到任何 normalized response event 后继续生成：不能当 transport retry；需要新 continuation request 或停止。
- finish_reason=length 后续写：同一 turn 的新 request。
- steer 注入后的重新采样：同一 turn 的新 request。
- action-review、termination-review、side 和仅 AL06-11 A 的 model compaction：独立 purpose、独立 request。AL06-11 B 的 Runtime checkpoint 不分配 request-id。
- Model 切换后：一定是新 turn 的新 request，不能复用旧 request。
- provider 支持幂等键时，可以发送 request-id 的派生值；本地 ID 不能假装远端一定幂等。

## canonical response 与 tool acceptance

### 流式阶段

Model adapter 可以产生 text delta、reasoning summary delta、tool argument delta、usage estimate 和状态更新。这些只进入有界 UI queue，不是 assistant canonical message，也不能触发工具。

收到 provider 的完整结束或明确断流后，adapter 才构造一个 normalized response candidate。

### response 候选必须整体校验

1. 对应的 request-id、attempt-id、purpose、Model snapshot 和 view digest 正确。
2. response 的 part 顺序、角色、编码、数量和大小都在上限内。
3. finish reason、provider refusal、usage 和 error 组合合法。
4. tool call 的 provider ID 在本 response 内不冲突；本地 ID另行分配。
5. 所有 tool arguments 已完整收口，可解析且通过已冻结 tool schema。
6. tool 数量和总参数大小未超限。
7. control 最多一个，且不与 executable tools 混用。
8. text 与合法 tool calls 是否可以共存只由 AL06-37 决定：A/B 保留文字与规范 block 顺序，C 把 mixed response 整体拒绝；任何路线都不能因工具存在而无声丢字。

推荐采用 tool batch 原子接受：

- 一批中任何一个调用结构无效，整批都不接受；
- 保存 model-response-rejected 诊断事实，但不产生 accepted tool call；
- 为每个 correction request 构造一份结构化错误输入；是否建立以及总共建立 0/1/2 个新 request 只服从 AL06-19；
- 不对同一个 wire response 部分执行、部分遗弃。

### canonical 提交顺序

~~~text
normalized response candidate
  -> validate full response and complete tool batch
  -> commit canonical model response
  -> commit accepted tool-call identities as one durable boundary
  -> hand the accepted batch to the TS-10 admission scheduler
  -> enter Permission for each call when TS-10 admits it
  -> after an observed failure, let TS-20 govern further admission
~~~

在 accepted tool-call durable 之前，不得审批、执行或显示成“已经调用”。在 durable 之后，每个调用都必须产生真实或 synthetic result。

AgentLoop 不在本包预选“整批串行”或“首个失败后全部 skipped”。TS-10 独占调用何时 admission、顺序与只读并行界限；TS-20 独占观测到中途失败后，尚未开始调用是继续 admission 还是生成何种 synthetic result。两组选择都不能破坏同一不变量：每个 accepted tool call 最终必须且只能配对一个真实或 synthetic canonical result，不能从 XML 中消失。

断流前只有部分文本时，可以在 response 收口时保存标有 incomplete 的可见诊断事实；它不是完成 assistant message。若完整 tool arguments 没有通过整批校验，绝不执行。

## main lane 的完整状态集合

候选状态：

| 状态 | 含义 |
| --- | --- |
| ready | 没有 active main turn，可以接受主输入或执行 session 命令 |
| turn-preparing | 主输入已 durable，正在冻结 turn snapshot |
| view-building | 组装下一次 main model view，并做窗口与能力预检 |
| compacting | 仅 AL06-11 A：运行无工具 model compaction purpose 并校验摘要 |
| model-requesting | logical request 已 durable，等待首个响应事件 |
| model-streaming | 已收到 normalized delta，仍未形成 canonical response |
| response-accepting | 收口、校验并提交完整 response/tool batch |
| permission-checking | 对 TS-10 当前 admission（或 observed failure 后 TS-20 允许继续 admission）的 accepted tool call 做确定性 Permission；可能对一组只读 call 逐项求值 |
| action-reviewing | DoubleCheck 对精确动作做无工具复核 |
| approval-waiting | 等待用户对精确动作 allow/deny |
| operation-committing | 将批准后的 operation-ready 事实 durable |
| tool-executing | operation 已 durable，一个动作或 TS-10 允许的有界只读组正在执行 |
| tool-result-committing | 逐项收口并 durable 真实或 synthetic result |
| termination-reviewing | DoubleCheck 对 finish intent 做独立完成复核 |
| retry-waiting | 有界退避；保存明确 resume target |
| cancelling | 正在收口取消请求及已发生/未知副作用 |
| turn-finalizing | 校验配对不变量并 durable 写入唯一 turn-ended |
| faulted | 存储或内部一致性已不允许继续外部动作 |

状态名是文档候选，不要求 Lua 内部使用字符串。领域语义必须等价。

## main lane 完整状态转换表

下表对上述状态的正常转换是穷尽的。表后面的全局异步控制另行覆盖。没有列出的状态/事件组合属于 invalid-transition：记录内部错误并 fail-stop，不允许“尽量继续”。

| 当前状态 | 触发或结果 | 必须完成的动作 | 下一状态 |
| --- | --- | --- | --- |
| ready | 主输入提交 | 先 durable input/turn-start，再冻结身份 | turn-preparing |
| ready | 合法 session 命令 | durable 需要保存的变更；不建 main turn | ready |
| ready | side 提交且 side-idle | 启动独立 side lane | ready |
| ready | 配置、Context 或 write lease 失效 | 禁止主请求和工具 | faulted |
| turn-preparing | snapshot 构建并 durable | 冻结 main Model、Permission、DoubleCheck、Prompt、cwd、tools、budgets | view-building |
| turn-preparing | 无可用 Model 或依赖待选择 | 形成 waiting-user 原因 | turn-finalizing |
| turn-preparing | snapshot 语义无效 | 形成 error | turn-finalizing |
| turn-preparing | snapshot durable/存储错误 | 不发任何 request | faulted |
| view-building | view 通过窗口/能力预检 | durable request 与 view manifest | model-requesting |
| view-building | AL06-11 A 下需要且 AL06-34 允许 model compaction | 固定待压缩 closed prefix | compacting |
| view-building | AL06-11 B 下需要 extractive checkpoint 且确定性输出有效/有收益 | Runtime 用固定版本规则构建并 durable checkpoint；不建 model request，不进 compacting | view-building |
| view-building | AL06-11 B 的 checkpoint 无法给出足够收益 | 不重试确定性计算，保留旧 view 并形成大 Model 选择原因 | turn-finalizing |
| view-building | 应优先选择更大 Model、跨 endpoint 或固定 Prompt 放不下 | 保存选择原因，不自动切换 | turn-finalizing |
| view-building | view builder 不可恢复错误 | 形成 error | turn-finalizing |
| compacting | 摘要 schema 有效且产生足够收益 | durable compaction 和新 view 引用 | view-building |
| compacting | 明确可安全 retry 的 attempt 失败 | 计 attempt 和退避 | retry-waiting |
| compacting | schema 无效/无收益，且仍有 redo budget | 保留旧 view 和拒绝证据，建立新的 compaction request | retry-waiting |
| compacting | schema 无效、无收益或 redo 达到上限 | 保留旧 view，形成 waiting-user | turn-finalizing |
| model-requesting | 收到首个 normalized delta | 仅更新 transient projection | model-streaming |
| model-requesting | 直接收到完整 result | 构造 response candidate | response-accepting |
| model-requesting | 尚无响应且明确可重试 | 计 attempt 和退避 | retry-waiting |
| model-requesting | 不可重试模型/协议/网络错误 | 形成 error；provider refusal 仍走完整 result | turn-finalizing |
| model-streaming | 收到完整 terminal result | 收口所有 parts | response-accepting |
| model-streaming | 断流、超限或协议错误 | 收口 incomplete candidate，不整请求盲重放 | response-accepting |
| response-accepting | 合法 tool batch（mixed 时还须符合 AL06-37） | durable response 和全部 accepted calls；初始只由 TS-10 admission eligible call，观测到 failure 后才调用 TS-20 | permission-checking |
| response-accepting | finish 且 DoubleCheck=false | 保存 finish intent | turn-finalizing |
| response-accepting | finish 且 DoubleCheck=true | 保存 finish intent 和 review input | termination-reviewing |
| response-accepting | PJ-11 B/C 的 plan phase 返回合法 plan-ready | durable PlanArtifact 及全部 binding digest，形成 waiting-user/reason=plan-ready | turn-finalizing |
| response-accepting | ask-user | 形成 waiting-user | turn-finalizing |
| response-accepting | refuse 或 provider refusal | 形成 refused | turn-finalizing |
| response-accepting | 普通无工具无 control 回复 | 按 AL06-38 形成 model-yield、control correction 或兼容完成 | turn-finalizing 或 view-building |
| response-accepting | length/incomplete 且 continuation 合法有预算 | 保存 incomplete 事实，建立新 sampling step | view-building |
| response-accepting | response 无效且 AL06-19 选定的 0/1/2 次 correction 仍有余额 | 保存拒绝证据和结构化修正输入 | view-building |
| response-accepting | response 无效且修正/预算用尽 | 形成 error 或 budget-exhausted | turn-finalizing |
| permission-checking | TS-10（以及 observed failure 后的 TS-20）判定当前没有可 admission 且所有 accepted calls 已配对 | 将完整结果组加入下一 view | view-building |
| permission-checking | Permission=deny | 生成 synthetic denied result | tool-result-committing |
| permission-checking | Permission=allow/ask 且命中 DoubleCheck scope | 固定 action-review input | action-reviewing |
| permission-checking | Permission=allow 且不复核 | 固定 operation snapshot | operation-committing |
| permission-checking | Permission=ask 且不复核 | durable pending approval | approval-waiting |
| permission-checking | 参数、路径或目标已 stale/冲突 | 生成 synthetic conflict result | tool-result-committing |
| action-reviewing | verdict=allow 且 Permission=allow | 保存 review | operation-committing |
| action-reviewing | verdict=allow 且 Permission=ask | 保存 review 和 pending approval | approval-waiting |
| action-reviewing | reject/uncertain 且允许精确人工 override | 显示 reviewer 证据和风险 | approval-waiting |
| action-reviewing | reject/uncertain 且不允许 override | 生成 synthetic review-rejected result | tool-result-committing |
| action-reviewing | 明确可重试且有 review budget | 计 review attempt | retry-waiting |
| action-reviewing | 失败且 retry 用尽 | 保守进入人工决定或 synthetic reject | approval-waiting 或 tool-result-committing |
| approval-waiting | 用户 allow 且 action snapshot 仍新鲜 | durable approval 和精确 digest | operation-committing |
| approval-waiting | 用户 deny 或 Esc | durable denial，生成 synthetic denied result | tool-result-committing |
| approval-waiting | action snapshot 变化 | 旧 approval 失效并重新求值 | permission-checking |
| approval-waiting | 普通无效输入 | 不猜批准；保留输入草稿并重显语法 | approval-waiting |
| operation-committing | operation-ready durable 成功 | 交给 tool runner | tool-executing |
| operation-committing | durable 失败 | 不执行，进入 fail-stop | faulted |
| tool-executing | 成功、失败、超时或已知取消 | 形成真实 canonical result | tool-result-committing |
| tool-executing | cancel，或 AL06-05 A 的 steer 到达 | 发终止请求；不宣称已经停止 | cancelling |
| tool-executing | AL06-05 B/C 的 steer 到达 | durable pending steer；不取消已启动 tool，批次继续服从 TS-10/TS-20 并在收口后注入 | tool-executing |
| tool-result-committing | 任一 result durable，仍有 accepted calls 未配对 | 先收口 TS-10 已启动 calls；非 failure 结果继续按 TS-10 admission，observed failure 把尚未开始 calls 交 TS-20，pending steer/cancel 则服从 AL06-05/35 | permission-checking 或 tool-result-committing |
| tool-result-committing | 所有 accepted calls 已配对且无 pending control | 将结果组用于下一 sampling step | view-building |
| tool-result-committing | 副作用后持久化失败 | outcome 不明，停止所有新外部动作 | faulted |
| termination-reviewing | verdict=finish | 保存 review 和原 finish 关联 | turn-finalizing |
| termination-reviewing | verdict=continue 且仍有 round budget | 把缺口作为 control fact 交回 main | view-building |
| termination-reviewing | transport 在响应前失败且可安全 retry | 同 request 新 attempt，计退避 | retry-waiting |
| termination-reviewing | verdict=uncertain/无效且有 correction budget | 保存无效证据，建立新的 review request | retry-waiting |
| termination-reviewing | 请求失败、无效或 round 用尽 | 不伪装通过，形成 waiting-user | turn-finalizing |
| retry-waiting | timer 到期且局部/turn 预算仍可用 | 使用保存的 resume target | compacting、model-requesting、action-reviewing 或 termination-reviewing |
| retry-waiting | 局部或 turn 预算耗尽 | 形成 budget-exhausted | turn-finalizing |
| cancelling | pending=cancel-turn，request/review/compaction 已确认收口 | 补齐可能的 synthetic results | turn-finalizing |
| cancelling | pending=steer，request/review/compaction 已确认收口 | 保存 incomplete/superseded 事实并注入 steer | view-building |
| cancelling | tool 返回真实结果 | 先 durable result；收口 TS-10 已启动组，尚未开始 calls 按 AL06-05/35 的 pending control 收口，若同时有 observed failure 再记录 TS-20 决策；保留 pending control | tool-result-committing |
| cancelling | tool 终止期限到且结果未知 | durable unknown-effect result，保留 pending control | tool-result-committing |
| tool-result-committing | 所有 calls 已配对且 pending=cancel-turn | 形成 cancelled 和真实 effect receipt | turn-finalizing |
| tool-result-committing | 所有 calls 已配对且 pending=steer | 将结果和 steer 用于下一 sampling step | view-building |
| turn-finalizing | finish 被已线性化 steer 失效 | 保存 superseded finish 并注入 steer | view-building |
| turn-finalizing | 配对、receipt 和 turn-ended durable | 释放 active turn，执行 outcome queue policy | ready |
| turn-finalizing | terminal commit 失败 | 不启动 queue，不发新请求 | faulted |
| faulted | 显式恢复验证成功 | 重新取得 write lease，重建 projection | ready |
| faulted | 任何会产生外部动作的命令 | 拒绝；只允许诊断、只读查看、恢复或退出 | faulted |

同一行出现多个候选下一状态时，必须由后续负责人选择固定策略，不能在实现中随机决定。

## PJ-11 B/C 的条件性 plan→execute 投影（不是本包新投票）

PJ-11 是唯一产品 owner。本节只把其 B/C 的不可分割后果投影到 AgentLoop，不再询问另一个“plan mode 怎样实现”问题。

### 条件注册与入口

| PJ-11 选择 | main 入口 | phase 行为 |
| --- | --- | --- |
| A | 所有普通输入都是现有 main turn | `phase`、PlanArtifact、plan-ready、`.plan/.execute` 和其 XML 字段/事件全部不注册，不写 `phase=execute` 占位 |
| B | `.plan <text>` 建立 `phase=plan` main turn；其他普通输入仍建立普通 `phase=execute` turn | 只有用户显式选择时分两阶段 |
| C | 每个新普通 main input（包括 queue 后启动的新 turn）都先建立 `phase=plan` | 纯只读目标可在 plan turn 内直接完成；任何需要副作用的后续必须经过 PlanArtifact + `.execute` |

`.execute <plan-id>` 是 B/C 下的显式例外入口：它在 artifact 新鲜性通过后建立一个新的 `phase=execute` 普通 main turn，不在 C 下再递归包一层 plan。Runtime 不根据用户文本或模型自然语言在请求前猜“这是否需要修改”。

### plan phase 的工具与 Prompt 边界

`phase=plan` 使用独立 purpose/view manifest，只向模型注册 direct list/read/search：

- 这三类仍通过正常 Permission，敏感读取仍通过 SensitiveRead 和 AL06-07 已选 action-review 范围；plan 不是绕过读取边界的通行证。
- shell/Execute、direct Network、Write/Delete/Rename 及任何 mutating/unknown-effect tool 不出现在 plan tool schema。模型伪造这些 call 时整批零执行，按 AL06-18/19 处理，不暗中升级为 execute。
- 合法只读 batch 仍服从 TS-10/TS-20、配对、取消、预算和 XML durable 不变量。
- plan Prompt 明确要求：若现有只读证据已满足目标，可用普通 finish；若后续需要任何副作用，必须输出 plan-ready，不得声称已经执行。

### PlanArtifact 与 stale 规则

Runtime 在接受 plan-ready 后创建本地 `plan-id`，并把下列绑定连同模型提供的结构化内容一次 durable：

~~~text
PlanArtifactV1
  plan-id / source-turn-id / created-event-seq
  goal-digest
  model-view-digest
  workspace-identity-and-state-digest
  effective-config-digest
  model-snapshot-digest
  permission-snapshot-digest
  tool-schema-digest
  content-digest
  status = ready | stale | execution-started | cancelled
  plan-ready content
~~~

上述任一 binding 在 `.execute` 前变化，artifact 就追加 `plan-stale` 事件并拒绝执行；Runtime 不重新解释旧文本、不只比较路径名，也不自动把 artifact “刷新”到新工作区/配置。用户必须重新 plan。

`.execute <plan-id>` 通过新鲜性检查后：

1. 在同一 event-loop 线性化边界重算 binding、追加 plan-execution-started，以 caused-by 引用 artifact，创建新 turn-id 和全新 turn snapshot/budget。`execution-started` 后同一 plan-id 不能再开第二个 execute turn；崩溃后只能按 AL06-32 处理原 turn，不重复消费 artifact。
2. 把 artifact 作为可审计的计划事实放入 execute model view，但不把步骤文字转成 Runtime 命令。
3. 模型必须在新 turn 里重新提议每个 tool call；Permission、DoubleCheck、人工 approval、operation durable、目标新鲜性和 TS-10/20 全部重新求值。
4. PlanArtifact 不继承、不隐含、不能代替任何授权；即使 plan 阶段曾经获准 SensitiveRead，execute 也不复用旧 approval。

线性化边界之后若外部进程再改变 workspace，execute turn 中的每个工具仍必须使用自己的 expected digest/stale 检查；PlanArtifact 的开始验证不是对未来状态的锁。

### cancel、恢复、预算与 terminal outcome

- plan/execute 都使用同一 main lane，不并发、不分裂 Context writer。Esc/steer/queue/side 按本包已选语义处理；plan 取消时先配对已接受只读 calls，未 durable 的草稿不伪造成可 execute artifact。
- 未完成 plan/execute turn 的崩溃恢复服从 AL06-32，不自动重发 request/tool。已 durable artifact 可查看，但恢复和 `.execute` 时都必须重算全部 binding；旧计划不能被当成 approval。
- plan turn 是普通受限 turn，它的 request/read/review/active-time 消耗 AL06-09 预算。execute 是新 turn，可拥有新的 turn guard，但不重置 Context/runtime 累计或抹去 artifact 的 source usage/因果 trace；PlanArtifact 不是额外 Token/步骤兑换券。
- plan-ready 成功 durable 后，该 plan turn 以 `waiting-user/reason=plan-ready` 收口，不做 termination-review、不自动启动 queue；用户可 `.execute`、重新 plan 或离开。
- 纯只读目标在 plan phase 实际完成时可用 finish(completed)，或在 AL06-36 A 下用 finish(partial)，并按 DoubleCheck/AL06-36 正常做 termination-review/收口。ask-user、refuse、cancelled、budget-exhausted、stuck 和 error 均使用现有 terminal outcome，不为 plan 伪造第二套结局。
- `.execute` 前 stale 是一个可操作的 session-command 错误：不建 execute turn、不发模型/工具，显示精确变化类别并要求重新 plan。

关联：PJ-11、TU-18、LOOP-18、AQ-346、CTX-07、CTX-16、SAFE-01、SAFE-03。

## 全局异步控制的线性化规则

状态机事件泵给每个已接受 command 分配 event-seq。谁先 durable，谁先发生：

- queue 在任何 active main 状态都只增加 pending input，不改变当前状态。
- side command 先由 AL06-06 做启动/pending/拒绝决定；真正 admission 后不改写 main 业务状态，额外 side 也不会暗中变 queue。
- steer 若在 turn-ended durable 之前被接受，属于当前 turn；若 turn-ended 已先提交，则不能改写已经结束的 turn。
- cancel 只取消明确 target；取消请求不等于目标已经停止。
- session 参数变更在 active turn 中只记录 pending，不能修改冻结 snapshot。
- storage fault 优先级最高：停止发起所有新网络、review、工具和 queue turn。

跨状态硬事件使用以下固定优先级；它们不是各 handler 可自由解释的异常：

| 全局事件 | 当前条件 | 转换 |
| --- | --- | --- |
| storage-fault | 任意非 faulted 状态 | 取消尚未发出的 effect；已发生副作用在内存/UI 标 unknown，恢复器由无 result 的 operation 推导；进入 faulted |
| AL06-09 选定的 hard turn guard | 尚未执行 operation | 不再 admission 新 call/request，收口 TS-10 已启动组，其余 accepted calls 写 synthetic budget-exhausted 结果，再进入 turn-finalizing/budget-exhausted |
| AL06-09 选定的 hard turn guard | tool-executing | 请求取消并进入 cancelling；真实/unknown result 优先于预算文案 |
| stuck hard stop | warning 后再次命中且没有 operation 在执行 | 进入 turn-finalizing/stuck |
| stuck hard stop | tool-executing | 不强杀未知副作用；等待本次结果后 turn-finalizing/stuck |
| queue command | 任意 active main 状态 | durable pending item，main 状态不变 |
| steer command | model/review/AL06-11 A compaction request 活动 | AL06-05 A/C 请求取消并进入 cancelling；B 只 durable pending steer，当前状态不变 |
| steer command | tool batch 已 accepted | AL06-05 A 取消已启动 call 并配对未开始 call；B/C 不因 steer 改写 TS-10/TS-20 收口路线；三者都 durable pending steer |
| side command | 任意 main 状态 | 由 AL06-06 决定立即启动、进入唯一 pending 槽还是拒绝；main 状态不变 |
| additional side command | active/pending side 已占用容量 | AL06-06 A 拒绝并保留 draft；B 只允许一个 pending；C 只允许 main-busy 时一个 pending 并在 model-safe point 串行；超过各自上限均拒绝 |

## queue 的完整时序

~~~text
1. User presses Enter or uses .queue.
2. Runtime validates size and assigns input-id.
3. queue-item-created is durable before UI says QUEUED.
4. Current main turn continues unchanged.
5. turn-ended becomes durable.
6. Outcome gate decides auto-start or pause.
7. If allowed, the oldest item becomes a new independent turn.
8. queue-item-consumed and new turn-start are committed without losing the item between them.
~~~

当前推荐基线是每条 queue item 独立成为一个 turn；最终分轮/显式合并/自动成组由 AL06-33 唯一决定。无论选哪条路线，原 item 顺序与身份都必须保存；删除、重排、编辑或合并必须按该组允许的显式/确定规则产生事实。

## steer 的完整时序

~~~text
1. User presses Ctrl+Enter or uses .steer.
2. steer input obtains its own input-id and is durable.
3. Apply AL06-05 exactly: A cancels cancellable request/tool and pairs unstarted calls as skipped-by-steer; B lets the active request/batch close; C cancels model/review/model-compaction or Runtime-checkpoint work but lets an accepted tool batch close under TS-10/TS-20.
4. Pending approval is invalidated; no old approval survives changed intent, and its accepted call receives a typed synthetic result.
5. Wait for every already-started tool to produce a real/cancelled/unknown result; never claim rollback.
6. At the safe boundary selected by AL06-05, inject steer into the same turn.
7. Build a new request; do not mutate the old request payload.
~~~

steer 不开启新 turn，不替换当前用户目标，而是一个更晚、更高优先的当前用户纠正。多个已经 durable 的 steer 按 event-seq 作为独立 control components 注入，不丢弃旧项，也不把它们无标记拼成一段。

若 steer 到达 turn-finalizing，event-seq 决定竞态：

- steer 先 durable：旧 finish 被标记 superseded，回到 view-building；
- turn-ended 先 durable：steer-too-late，输入保留在 draft，用户明确选择 queue 或新 turn；不静默改类型。

## side 的完整时序

下面是一条 side 被 AL06-06 scheduler 真正 admission 之后的生命周期，不表示 main-busy 时必然立即启动。AL06-06 A/B/C 分别独占“立即并发、一个 pending，还是 model-safe point 串行”以及超额结果。

~~~text
1. User presses Alt+Enter or uses .side.
2. AL06-06 scheduler admits it; Runtime assigns side-id and request-id.
3. Freeze the latest durable Context snapshot, current Model and side budget.
4. Persist side-start before sending.
5. Send purpose=side with no tool schema.
6. Under AL06-06 A/B the main lane may continue; under C it remains at the admitted model-safe point until side closes.
7. Persist one complete/incomplete/cancelled side response.
8. Return to side-idle; response stays outside future main model views.
~~~

最多一个 side 请求处于 requesting、streaming、retry 或 cancelling。是否允许另外一个 pending、何时启动以及超额时怎样保留 draft 全部服从 AL06-06；任何路线都不能悄悄把 side 改成主 queue。

side：

- 可以读提交时已经 durable 的 Context snapshot；
- 看不到当前 main request 尚未提交的 delta、隐藏 reasoning 或未来 tool result；
- 没有 tool schema、Permission、action review 或 operation；
- 有独立 request/attempt/cancel 和局部 timeout；
- token/费用始终单列 side，再按 AL06-09 已选层级与 AL06-22 已选归账路线扣除；side 永不伪装成 tool call；
- 完整 response 作为 side fact 保存，但默认不进入 main model view；
- 用户要采用旁问结论时，必须把它显式 queue 或 steer 给 main。

## cancel 的完整时序

~~~text
1. Resolve target from focus/state or explicit .cancel target.
2. Persist cancel-requested when a durable activity exists.
3. Send cancellation to model, timer, tool or side adapter.
4. Wait for acknowledged, completed or deadline/unknown result.
5. Pair every accepted tool call.
6. Persist final true result and turn outcome.
7. Only then release the turn and evaluate queued inputs.
~~~

下面只演示 AL06-35 A 的焦点优先候选，不能把它误读为所有路线共同前提；若选 B/C，目标解析和 approval 结果按该组整体替换：

| 当前焦点/状态 | Esc 的候选语义 |
| --- | --- |
| 输入 draft | 清空当前 draft；第二次不靠时间窗升级 |
| side focus | 只取消 side，不影响 main |
| model/review/AL06-11 A compaction request | 取消最内层 request；默认收口当前 turn 为 cancelled |
| approval-waiting | 明确 deny 当前动作，Agent 可收到 synthetic result 后继续 |
| tool-executing | 请求终止进程树/动作，等待真实或 unknown 结果 |
| retry-waiting | 取消 backoff，不再重试 |
| ready | 不退出；退出使用 .exit/.quit |

点命令后备必须能精确表达 cancel-request、cancel-tool、cancel-side、cancel-turn 和退出意图这五种领域动作；正式命令拼写与别名由 CLI registry 冻结，本包不预占 `.cancel` 的具体 grammar。

## main outcome 后怎样处理 queue

推荐使用保守 outcome gate：

| 当前 turn outcome | 自动启动最老 queue item | 原因 |
| --- | --- | --- |
| completed | 是 | 当前目标已正常收口 |
| partial | 否 | 剩余项可能需要用户先选择 |
| waiting-user | 否 | queued 文本不一定回答当前问题 |
| refused | 否 | 用户应决定改写还是换任务 |
| cancelled | 否 | 可能有 partial/unknown effects |
| budget-exhausted | 否 | 继续可能立即再次超限 |
| stuck | 否 | 新消息可能需要先解释卡死 |
| error | 否 | 配置、存储或工具状态可能仍无效 |

暂停时 queue 保持 durable、可查看、可删除；用户可显式 run-next。不能因程序重启自动把 waiting-user 后的全部 queue 发给模型。

## side lane 状态转换表

| 当前 side 状态 | 触发或结果 | 动作 | 下一状态 |
| --- | --- | --- | --- |
| side-idle | AL06-06 已 admission 的 side | freeze durable snapshot，写 side-start | side-requesting |
| side-requesting | 首个 delta | transient display | side-streaming |
| side-requesting | 完整 response | 校验 canonical side response | side-finalizing |
| side-requesting | 安全可重试失败 | 计 side attempt | side-retry-waiting |
| side-streaming | 完整 response | 收口 response | side-finalizing |
| side-streaming | 断流/超限 | 收口 incomplete side result | side-finalizing |
| side-requesting/side-streaming | cancel | 发取消，不影响 main | side-cancelling |
| side-retry-waiting | timer 到期且有预算 | 新 attempt | side-requesting |
| side-retry-waiting | cancel 或预算耗尽 | 形成 cancelled/error | side-finalizing |
| side-cancelling | acknowledged/completed/unknown | 保存真实状态 | side-finalizing |
| side-finalizing | durable 成功 | 显示一次结果，不注入 main view | side-idle |
| 任意 side 活动状态 | XML 持久化失败 | 触发 session fail-stop，main 在安全边界收口 | side-idle + main faulted |

side 不拥有第二个 Context writer；它的事实仍由同一个 Context service 串行提交。side-finalizing 之后是否启动一条 pending side 也由 AL06-06 决定，不是本表的隐含转换。

## Permission → action review → human approval → operation → execute

### 顺序为什么不能交换

- 先 review 后 Permission，会让 LLM 看起来能够批准 Runtime 已经确定拒绝的动作。
- 先 human approval 后 action review，会让用户在没有复核风险说明时批准。
- 先 execute 后 operation durable，崩溃后无法判断副作用是否发生。
- approval 若只绑定自然语言理由，模型可以在执行前替换参数。

### 推荐流水线

~~~text
canonical accepted tool call
  -> deterministic Permission
       deny ------------------------------> synthetic denied result
       allow / ask
  -> DoubleCheck action review when scoped
       allow / reject / uncertain
  -> human approval when Permission=ask
       or when exact review override is offered
  -> operation-ready durable
  -> execute exactly that snapshot
  -> canonical result durable
  -> TS-10 admits remaining calls; after observed failure TS-20 decides further admission; otherwise next model request
~~~

operation-id 可以在 accepted tool call 时预分配，供 Permission/review/approval 引用；只有人工决定完成且 action snapshot 仍新鲜后，才提交 operation-ready。任一规范 tool 名、版本、参数、cwd、环境非秘密摘要、目标 digest 或权限结果变化，都让旧 review/approval 失效。

箭头表示“凡是出现这些阶段时必须遵守的先后顺序”，不表示每个 Permission=allow 的普通动作都强制弹出人工批准；是否需要 human approval 仍由确定性 Permission 和精确 review override 路径决定。

### DoubleCheck action scope 的条件语义

只有 AL06-07 A/B 启用 action-review。若选 A，DoubleCheck=true 时建议复核：

- raw shell/Execute；
- direct Write、Delete、Rename；
- outside-workspace；
- 读取被配置标为敏感的来源；
- 未来 direct Network；
- Permission 本身返回 ask 的其他高风险动作。

选 B 时所有 executable tools 都复核。选 C 时完全没有 action-review：DoubleCheck 仅保留 termination-review，accepted action 直接服从 Permission=allow/ask/deny 和必要的人工批准。DoubleCheck=false 在任何路线都不做 LLM action-review；Permission=ask 的人工批准仍然存在。

reviewer：

- 使用 purpose=action-review；
- 没有工具；
- 只看精确 action snapshot、确定性 Permission 结果、相关用户意图和风险事实；
- 只能 allow、reject 或 uncertain；
- allow 不能把 Permission deny 变成 allow；
- 不能改参数后沿用旧 verdict；
- 输出和费用独立保存。

若允许人工 override，用户只能对这一个精确、仍新鲜、Permission 非 deny 的动作批准；这不是关闭 DoubleCheck，也不形成 always 授权。

## termination review

### 触发

只有 Runtime 接受了正常结束意图且当前 frozen DoubleCheck=true 时触发：通常是合法 `finish(completed)`，若 AL06-36 允许则也包括 `finish(partial)`；只有选择 AL06-38 C 时，兼容归一化后的 implicit completed 也必须触发。ask-user、AL06-38 A/B 的普通 yield、refuse、provider refusal、cancel、budget 和 error 不触发结束复核。

### 输入

termination-review 只看：

- 当前目标和本 turn 用户纠正；
- 主模型 proposed result/report；
- canonical tool/operation/approval 事实；
- 文件变化和验证 evidence；
- unknown effects、失败和未完成项；
- 当前预算、stuck warning 和 Model/Prompt snapshot refs。

它不看 Key、完整 XML、隐藏 reasoning，也没有工具。

### verdict 与控制流

| verdict/结果 | 推荐控制流 |
| --- | --- |
| finish | 保存 review，使用原主模型 report + Runtime receipt 结束 |
| continue | 保存具体缺口，交回同一 turn 的下一次 main request |
| uncertain | 在有界协议修正/attempt 后仍不明时 waiting-user |
| transport failure before response | 按 Model 安全 retry，预算用尽后 waiting-user |
| malformed verdict | 最多一次结构化修正，不当作通过 |
| 达到 MaxTerminationReviewRounds | waiting-user，显示主 finish 和未通过原因 |
| cancel | cancelled，不把主 finish 当作已批准 |

实际 review Model 只由 AL06-08 决定：A 使用当前 turn 冻结的 main Model，B/C 使用已显式配置或持久映射的完整 Model。review 的局部 round cap 与总预算归账则服从 AL06-27 对 AL06-09 预算层的映射，不在这里预选固定 turn 池。

review continue 后，旧 finish 变成 superseded intent。主模型必须看到 reviewer 列出的具体缺口和已使用 review round，不得只收到一句“继续”。

## 分层预算

### 预算层级的唯一 owner（AL06-09）

AL06-09 先决定哪些层是 hard ledger；AL06-22 只决定 side 怎样扣已存在的 ledger，AL06-27 只决定 review 在已存在的 turn guard 内怎样分额。后两组不得新建 AL06-09 没有选中的 Context/turn 硬池。

| 层级 | 典型限制 | AL06-09 A | AL06-09 B | AL06-09 C |
| --- | --- | --- | --- | --- |
| attempt | connect/first-event/idle/total timeout、response bytes | 独立 hard ledger | 由 request 内的 max-attempt/timeout 封顶 | 由 request 内的 max-attempt/timeout 封顶 |
| request | max attempts、单 response/tool arguments、单 request tokens | hard | hard | hard |
| turn | model/tool/review/compaction steps、active time、tokens/output | 可配置 hard ledger | 可配置 hard ledger | 发行版固定、不可配置为无限的 composite safety cap；至少封顶 step/request、token/output 与 active time |
| Context | 累计 model requests/tokens/output 与 side usage | hard ledger | 只累计审计，不以这些 usage 停止请求 | hard ledger |
| process/runtime | 活跃网络/进程、队列、内存和输出 | hard | hard | hard |

共同计数不变量：

- XML 文件安全上限、pending queue 容量和进程内存上限是存储/运行时正确性界限，不会因 AL06-09 B 的 Context model-usage “只审计”而失效；本组只拥有 AgentLoop 请求、Token、步骤和时间预算层。
- 每个 logical request 计一次；每个网络 attempt 另记一笔，是否是独立 hard ledger 服从 AL06-09。
- main、continuation、protocol correction 和 AL06-11 A 的 model compaction request 都消耗 AL06-09 选定的 turn guard；B 的 Runtime checkpoint 只消耗当前 turn/runtime 的计算时间与内存，不计 model request/Token；C 没有这个步骤。action/termination review 再按 AL06-27 在该 guard 内分额，side 按 AL06-22 映射。
- `context-name` 只在 PJ-12 B 下存在。以下整套语义是 PJ-12 B 不可分割的后果，不是本包新增的开关或可单独投票项：每个 Context 终身只有一个 logical request 名额，使用独立且不可扩大的 lifecycle budget；它不回记已经结束的 first main turn，但计入 Context usage、同一 Model scheduler 和 process/runtime 总量。只允许 Model 配置本来就准许的有界 transport attempts，不做 protocol correction、semantic retry 或 Model fallback。
- continuation 和 protocol correction 是新 request，不是新 attempt。
- tool call 一旦 accepted 就计数，即使后来 denied/skipped。
- backoff 和真实 I/O 消耗 active wall time。
- 等待人工 approval 的离机时间不消耗 active wall time，但记录 calendar elapsed；恢复时重新做 action freshness。
- 没有版本化价格快照时只能显示 token/费用估算，不能承诺精确硬费用上限。

AL06-09 A/B 的可配置 hard turn ledger 或 C 的固定 turn safety cap 达到时，Runtime 都停止建立新 request/operation，先收口 TS-10 已启动组，对未开始 accepted calls 写明确 synthetic budget-exhausted result，再产生 turn outcome=budget-exhausted。已有进展写入 progress receipt，不改 outcome。只有收口过程真正观测到 failure 时才另记 TS-20 决策，不把“预算用尽”伪装成 batch failure。

## retry 分类

| 情况 | 同一 request 新 attempt | 新 logical request | 推荐行为 |
| --- | --- | --- | --- |
| DNS/connect/TLS 在 body 前明确失败 | 是 | 否 | Model retry policy 内退避 |
| body 可能发送、没有 response | 默认否 | 否 | outcome unknown，不盲重放 |
| 已收到任何 normalized response event 后断流 | 否 | 可能 | 保存 incomplete；仅明确 continuation |
| finish_reason=length | 否 | 是 | 有预算时结构化 continuation |
| 完整 response 协议无效 | 否 | 按 AL06-19 为 0/1/2 个 correction | 同 payload transport retry通常无意义 |
| action/termination review 在响应前瞬时失败 | 是 | 否 | 无工具，仍受局部和 turn budget |
| review verdict schema 无效 | 否 | 最多一个 correction | 不把 invalid 当 allow/finish |
| AL06-11 A compaction request 瞬时失败 | 是 | 否 | 保持旧 view |
| AL06-11 A compaction schema 无效/无收益 | 否 | 有界重做 | 达上限后 waiting-user |
| AL06-11 B Runtime checkpoint 规则/完整性错误 | 否 | 否 | deterministic internal error/fail-stop，不发 Model request |
| tool 返回失败 | 否 | 由模型重新提出新调用 | Runtime 不自动重放副作用 |
| tool outcome unknown | 否 | 否 | 必须用户检查/决定 |

任何 retry 都记录原错误、attempt、退避和最终结果。curl 内建隐式 retry 必须关闭，避免 AgentLoop 统计不到真实 attempt。

## stuck 检测

建议检测：

- 相同 tool/version/normalized args，在相关目标 digest 未变化时重复；
- 相同动作连续得到相同错误；
- A-B-A-B 动作/错误循环；
- 多次普通无工具回复但未产生新用户决定；
- termination review 连续指出同一缺口，主模型没有新事实；
- AL06-11 A 的 model compaction 连续无收益；B 的确定性 checkpoint 无收益直接停止并提示，不重复构造来伪装进展；
- 文本看似变化但 progress fingerprint 不变。

推荐两阶段：

1. 首次达到阈值：durable stuck-warning，把模式、证据和“必须改变策略”交给主模型一次。
2. 再出现等价模式：停止为 stuck。

只有 canonical 状态变化才重置模式，例如目标文件 digest 改变、新验证证据、用户决定或工具产生不同结果。更换措辞、换 Model、重试同一请求或再次声称“我会换方法”不算进展。

stuck 阈值可以在安全范围配置，但不能关闭硬上限或设为无限。

## Model 切换

### turn 冻结

每个 turn-start 保存有效 main Model 的非秘密 snapshot/digest，包括逻辑名、Protocol、Endpoint、RemoteModel、窗口、Streaming、Tools 和关键能力。main 始终使用这个 frozen Model；action/termination review 服从 AL06-08，只有 AL06-11 A 的 model compaction 服从 AL06-30。若它们选用不同完整 Model，必须另存非秘密 snapshot、request purpose、数据范围与跨 endpoint 确认，不能改写 main Model snapshot。B 的 Runtime checkpoint 只冻结 extractor-version，不伪造 Model snapshot/request。

### 空闲切换

.model 在 ready 时：

1. 选择候选 Model。
2. 做 context window、role、tool protocol、历史 call/result 配对和 endpoint 预检。
3. 若 endpoint 改变，显示将发送的历史范围、隐私和费用变化并确认。
4. durable model-switch 事件和新非秘密 snapshot。
5. 下一 turn 生效。

### 忙时切换

active turn 中的 .model 只记录 pending switch：

- 不替换在途 request；
- 不让一个 tool batch 的 call 与 result 跨 Model；
- 当前 turn 收口后做预检；
- 若 outcome=completed 且 queue 可自动开始，必须先应用/确认 pending switch，再启动 queued turn；
- side 已创建的 request 继续使用它自己的 frozen Model。

若用户要立即改变当前模型策略，应先 cancel 当前 turn，再显式切换并建立新 turn；steer 不暗中改变 Model snapshot。

### 大小窗口与能力变化

切到更小窗口前：

1. 检查不可压缩 Prompt + tool schema + 必保动态状态是否能放下。
2. AL06-11 A/B 检查 structured compaction/checkpoint + recent atomic tail 是否能放下；C 检查不带 checkpoint 的最新完整 atomic groups。
3. 不能放下则拒绝切换，不截断 Prompt。
4. 若历史曾使用且仍配置的较大 Model 足够，优先提示切回它；再列其他更大候选。

切回大窗口后，可以从 XML 完整事实重建更丰富的 raw tail，不受旧摘要永久限制。Model 切换必须作为 control fact 出现在新 Model 的首次 main view：old、new、reason、能力/窗口差异和当前未完成事项。

恢复时原 Model 不存在，先只读展示旧 snapshot，让用户选择替代并完成上述预检；不静默使用 INI 第一项。

## structured compaction：事实、摘要与 view manifest

### 三种数据角色

| 数据 | 是否是事实源 | 可否重建 |
| --- | --- | --- |
| canonical event history | 是 | 不由压缩删除 |
| compaction record | 否，是有损派生检查点 | 可由来源事实重新生成或 supersede |
| model-view manifest | 否，是某 request 的实际输入清单 | 可由事实、Prompt 和 compaction 重建 |

### 推荐算法

下面公式是 AL06-11 A 的推荐 model-summary 路线；B 把其中的 model compaction 替换为 Runtime deterministic extractive checkpoint，C 则完全移除该项，不能把公式误读成三个选项都调 Model。

~~~text
immutable effective Prompt + frozen tool schema
+ one latest valid structured prefix compaction
+ newest complete atomic event groups that fit
+ current objective / pending steer / unknown effects / unfinished work
= request model view
~~~

只压缩已经闭合的历史 prefix。当前 active turn、未配对 tool call、pending approval、operation/result、steer 和未完成 side 不可被拆开或隐藏。

后续代次默认读取“上一份 accepted compaction/checkpoint + 此后新增的 closed atomic groups”。AL06-11 A 因而不必每次要求 compaction Model 重新吞下全部原文；B 由 Runtime 以同一 extractor-version 确定性增量重建。parent-compaction-id 和条件性 request/input manifest 必须如实记录产生路线。XML 中的原始 facts 仍完整保留，切回大窗口或重建时可以从原始事实生成新的 superseding compaction/checkpoint。首版不实现多层摘要树或向量召回。

原子组至少包括：

- 一条用户输入及对应直接回复/control；
- 一个 canonical assistant response 及其全部 accepted call/results；
- Permission、action review、approval、operation 和 result；
- Model、Prompt、Permission、DoubleCheck switch；
- AL06-11 A 的 compaction correction/supersede，或 B 的 extractive-checkpoint supersede；
- cancel 与 unknown-effect receipt。

### CompactionRecordV1 候选 schema

该记录只在 AL06-11 A/B 下存在：A 使用 `producer.kind=model-summary`，B 使用 `producer.kind=runtime-extractive`，C 不写空 CompactionRecord。

~~~text
identity
  compaction-id
  generation
  status                 accepted | rejected | superseded
  created-event-seq

source
  first-event-seq
  last-event-seq
  source-digest
  parent-compaction-id
  excluded-open-groups[]

producer
  kind                   model-summary | runtime-extractive
  model-snapshot-ref     required only for model-summary
  prompt-version         required only for model-summary
  request-id             required only for model-summary
  extractor-version      required only for runtime-extractive
  estimator-version

summary
  objective
  current-state
  user-decisions[]
  constraints[]
  workspace-changes[]
    path / action / state / evidence-refs[]
  verification[]
    subject / result / evidence-refs[]
  failed-attempts[]
  unknown-effects[]
  open-questions[]
  next-actions[]
  model-prompt-permission-transitions[]
  important-terms[]

integrity
  summary-digest
  schema-version
  estimated-input-tokens  model-summary only
  estimated-output-tokens model-summary only
~~~

当前 producer kind 要求的必填槽位即使为空也要显式为空，避免 reader 不知道“没有 unknown effect”还是“摘要漏了这个字段”。另一 kind 专属的 Model/request/extractor 字段必须缺省，不写伪造空引用。摘要/提取项中的 evidence refs 指向 canonical facts，不能伪造为验证结果。

### ModelViewManifestV1 候选 schema

~~~text
request-id
purpose
model-snapshot-ref
prompt-bundle-ref
tool-schema-ref
compaction-ref
included-atomic-event-ranges[]
excluded-source-ranges[]
dynamic-state-refs[]
pending-control-refs[]
token-estimate
safety-margin
role-map-version
view-digest
~~~

每个 request 保存 manifest；不必重复保存完整 HTTP body、Key 或每份 Prompt 全文。第三方接盘者可以据此解释模型当时看到了哪些事实、摘要和工具。

### 触发、失败和无收益

以下 model compaction request 语义只适用于 AL06-11 A。若选 B，Runtime 在同一 closed-prefix/atomic-group 边界上按版本化确定性规则直接构建 extractive checkpoint，不发 Model request、不花 Model Token、不经过 model schema correction/retry/consent；同一输入+规则版本必须产生同一 digest。若选 C，Runtime 只执行窗口预检、大 Model 提示和 waiting-user，不生成任何 compaction/checkpoint。

推荐在 provider 报超限前，根据当前 Model window 扣除：

- 不可压缩 Prompt；
- tool schema；
- 期望 output；
- tool-result reserve；
- tokenizer 估算误差；
- 当前 active state。

达到安全阈值时先提示足够大的历史 Model，再提示其他大 Model；用户不切换时，AL06-11 A 按 AL06-34 进入 model compaction，B 无需 consent 地构建 deterministic extractive checkpoint，C 则 waiting-user。任何路线都不能自动跨 endpoint。

AL06-11 A 的 compaction 完整 Model 只由 AL06-30 决定，始终使用 purpose=compaction 且无工具。AL06-30 选定的 Model 连压缩输入都放不下时停止并提示选择，不偷偷用 INI 第一项或退回 main Model。AL06-11 B 没有 compaction Model；Runtime checkpoint 规则错误是确定性内部错误/fail-stop，不调用 AL06-31 让模型重试。

以下摘要 schema 无效、仍超限或连续无收益处理仅属于 AL06-11 A：

- 保持旧 compaction 和旧 model view；
- 记录 rejected attempt；
- 不删除任何事实；
- 达到硬次数后 waiting-user；
- 建议切换大 Model、缩短 Prompt、手动指定保留项或查看摘要。

AL06-11 A 下用户纠正摘要时追加 correction/superseding compaction event，不原地改旧记录。B 的 extractive checkpoint 不接受自由文本编辑；用户只能追加新的 canonical 纠正/保留事实，Runtime 再以新 source digest 确定性生成 superseding checkpoint。下一 view 使用新记录，旧记录仍可审计。

## 恢复与 fail-stop

推荐恢复时不自动重放 unfinished main turn。先根据最后 durable 状态收口：

| 最后 durable 状态 | 恢复动作 |
| --- | --- |
| turn-start，没有 request | 标记 interrupted-before-request，等待用户继续 |
| request/stream/review/AL06-11 A model compaction in-flight | 标记 interrupted response，不自动重发，等待用户 |
| AL06-11 B Runtime checkpoint 构建中 | 从已 durable source range + extractor-version 重建可验证结果；若完整性不一致则 fail-stop，不发 Model request |
| accepted tool call，尚无 operation-ready | 生成 synthetic interrupted-before-execution |
| pending approval | 旧 pending 只作审计；重新显示并重新检查新鲜度 |
| operation-ready 或 executing，没有 result | 标记 outcome unknown，绝不自动重放 |
| tool result 已 durable，未开始下一 request | 可重建完整 view，但默认先显示恢复页等待用户 |
| finish intent/review 已 durable，turn-ended 缺失 | 若所有事实完整可重新 finalizing；否则等待用户 |
| side in-flight | side 标记 interrupted；不自动重发，不污染 main |
| A compaction 或 B checkpoint accepted，view manifest 未完成 | 验证来源 digest 与 producer kind；可重建 manifest，不能重写事实 |

任何必须先 durable 的事件写入失败：

- 用户输入未 durable：不能显示成已接收；
- request/approval/operation 未 durable：不得发模型或执行工具；
- 副作用后 result 未 durable：标记 unknown，fail-stop；
- turn-ended 未 durable：不得消费 queue 或释放为可写新 turn；
- side 保存失败：整个 Context writer 进入 faulted，不让 main 继续制造无法记录的事实。

## 需要项目负责人决定的 36 组问题

下面每组只负责一个可独立回复的 owner 轴。只有明确回复后才会写入 DECISIONS.md；未回复、只阅读、没有反对推荐或只说“整体可以”都不算确认。

以下是所有选项共同遵守的既有约束，不再伪装成可投票的第四个问题：

- 普通无工具、无 typed control 的模型回复不得由散落代码自行猜 outcome；唯一兼容策略由 AL06-38 决定。
- control 与 executable tool calls 不得同批；provider refusal 独立映射 refused，不走 transport retry，也不冒充主模型 finish。
- 流式 delta、未闭合参数、含无效调用的 batch 都不能提前或部分执行；每个 accepted tool call 最终必须有真实或 synthetic result。
- 本地关系 ID 一旦 durable 就稳定、不复用；queue edit、摘要纠正和恢复都追加事实，不原地改写既有 XML 事件。
- retry、review、continuation、compaction、side、suspend/resume 都受可计算的硬上限；不得用新子循环、Model 切换、时钟跳变或重启重置已有预算。
- compaction 和 model view 可以有损，但 Context XML 的 canonical facts 不得被截断、删除或覆盖。
- 不静默切换 Model、endpoint、Permission 或缺失映射；任何跨 endpoint 历史发送都必须显式可见。

### AL06-01：总体 Loop 状态所有权

问题：首版由哪一种结构拥有 main turn 的唯一业务状态？

- A：一个显式 reducer/state machine；每次转换输出 durable facts、effects 与 transient projections。（推荐）
- B：一个显式 phase machine；正常流程由分阶段 Lua 函数组合，每个外部边界仍写足以恢复的 durable checkpoint。
- C：durable workflow engine；request、review、tool 和 timer 都是有 lease 的 workflow node。

推荐 A。它让 cancel、storage fault 和 tool pairing 可用同一张转换表验证，同时不引入 C 的 scheduler/lease 平台。side 的数量与调度不属于本组，由 AL06-06 决定。

关联：AQ-030、AQ-091、AQ-234、AQ-261、LOOP-01、LOOP-02、LOOP-11、RUNTIME-01、RUNTIME-02、CTX-16。

### AL06-02：typed control 的模型可见 carrier

问题：模型用什么线协议表达 finish、ask-user 和 refuse，以及仅 PJ-11 B/C 条件注册的 plan-ready？

- A：每个已注册 control 一个小型 Runtime control function，分别使用固定 schema；基线三个，PJ-11 B/C 时条件增加 plan-ready。（推荐）
- B：一个 agent-control function，以 kind 判别基线三个固定 payload，PJ-11 B/C 时同一 kind registry 条件增加 plan-ready。
- C：一个保留的 structured assistant envelope；adapter 严格校验后再规范化为已注册 control，PJ-11 A 时不接受 plan-ready kind。

推荐 A。弱 OpenAI-compatible endpoint 通常更容易稳定地产生多个扁平 schema；B 减少 registry 项但依赖条件字段校验；C 可覆盖没有 tool/function carrier 的协议，但需要更严格的文本与结构边界。三者进入 AgentLoop 后的已注册 control 语义完全相同；PJ-11 只条件增减 plan-ready，不再改变 carrier 选择。

关联：AQ-101、AQ-110、AQ-251 至 AQ-253、MODEL-06、PROD-03、LOOP-03、LOOP-10、LOOP-22、LOOP-25。

## AL06-03 XML 内局部关系 ID 表示（技术证明，不是负责人投票）

D-023 禁止的是永久 ContextId，不是单个 XML 内把 turn、request、attempt、tool-call 和 result 可靠配对所需的局部关系 ID。其产品不变量已经固定：带类型、只在本 XML 内有效、创建后稳定、永不复用、复制 XML 后关系不变、不会参与 Context Resolver。

十进制、base36 或随机位串本身不改变用户能力；应由公开 XML 可读性、Win32 x86 溢出、解析成本和恢复 fixture 选择。技术基线是 `类型前缀 + 单调 ASCII 十进制`（例如 `turn-41`），因为最容易让人和第三方 reader 审计；只有证明它不能满足边界时才换表示，不能由各模块自行选择。

关联：TP-015、TP-017、TP-021、AQ-092、AQ-102、AQ-103、AQ-254、AQ-256、LOOP-11、CTX-07、CTX-16、CTX-17。

### AL06-18：完整 response 中无效 tool batch 的接收结果

问题：完整流已经收口，但可见 text 合法而整个 tool batch 中至少一个调用无效时，怎样 canonicalize 这次 response？

- A：不接受为 canonical assistant response；保存 response-rejected 诊断与可见 incomplete 文本，整批零调用被接受。（推荐）
- B：保存一条 typed incomplete assistant fact 和 batch-rejected 原因，整批零调用被接受；该事实不能被视为完成回复。
- C：保存 text-only canonical assistant message，并附 batch-rejected control fact；整批零调用被接受，turn 转 waiting-user 或进入 AL06-19 的纠错流程。

推荐 A。它最不容易让下一轮误以为模型已经说出一条完整且可依赖的回复。B/C 保留更多可见文字地位，但 view builder 必须防止把被拒工具前的文字当作执行证据。三项都先等待完整响应、整批验证，禁止部分接受或流式执行。

关联：AQ-106、AQ-221、AQ-257、AQ-258、MODEL-02、MODEL-05、LOOP-13、LOOP-14、LOOP-16、CTX-07。

### AL06-19：模型协议纠错请求的自动次数

问题：完整 response/control schema 无效后，Runtime 自动给模型几次新的 logical correction request？

- A：最多一次；仍无效就 waiting-user，并显示原错误和预算。（推荐）
- B：零次；立即 waiting-user，由用户决定 retry/regenerate。
- C：最多两次；每次都使用新 request-id，并共同消耗 turn request/token/time 预算。

推荐 A。一次纠错通常能修复格式偶发错误，又不会形成隐藏循环。无论选择哪项，都不重发同一 wire response，不把 transport retry 当协议纠错，也不超过本组固定上限。

关联：AQ-101、AQ-106、AQ-221、AQ-251 至 AQ-253、LOOP-04、LOOP-14、LOOP-27、MODEL-09。

### AL06-13：text/tool block 顺序与 length 截断后的续写

问题：完整结束原因为 length 时，是否自动建立 continuation request？

- A：不自动续写；保存 incomplete 事实并转 waiting-user。（推荐）
- B：若没有任何未闭合 executable tool call，最多自动一次 continuation；合并结果再次完整校验后才可接受。
- C：不自动续写，但提供显式 continue-current；用户触发后建立新 logical request，并沿用原 turn 剩余预算。

推荐 A。它最简单，也不会猜截断文本/JSON 的真实意图。B 提升长文本体验，但必须证明合并边界；C 把成本选择交给用户。三项都保留 provider 规范 block 顺序，text 不代表 finish，截断或未闭合 tool 永不执行。

关联：AQ-324、AQ-325、MODEL-02、LOOP-13、LOOP-14。

### AL06-04：queue 的 terminal outcome 自动启动门

问题：在没有 unknown effect、没有 pending approval 且 writer 健康时，哪些 terminal outcome 可以自动启动下一条 queue？

- A：只有 completed。（推荐）
- B：任何 outcome 都不自动；用户总是显式 run-next。
- C：completed 或 refused；其他 outcome 一律暂停。

推荐 A。它让正常连续任务顺滑，又不会跨过 partial、waiting-user、cancelled、budget-exhausted、stuck、error 或 unknown effect。B 最可预测但操作更多；C 适合把拒绝视为已明确收口的独立任务。三项都禁止在等待问题或副作用未知时自动前进。

关联：AQ-024、AQ-032、AQ-086、AQ-092、AQ-093、AQ-234、LOOP-01、LOOP-06、LOOP-10、LOOP-24。

### AL06-14：queue 管理能力集合

问题：负责人希望首版提供哪一组 queue 管理动作？

- A：list、drop、edit、reorder、clear。（推荐）
- B：list、drop、clear；已入队文本不可 edit/reorder，始终 FIFO。
- C：list、clear；单项不可修改或删除，始终 FIFO。

推荐 A。用户离机前可能一次排入多项，精确 edit/reorder 能避免清空重输；B/C 更简洁。三项都使用稳定 queue-item-id、有界容量和 durable amendment/tombstone，不原地改写既有 enqueue 事件，也不影响已开始的 turn。

关联：CONC-02、AQ-032、AQ-086、AQ-092、CTX-07。

### AL06-20：queue 满时的新输入处理

问题：queue 达到硬上限后，当前 draft/new item 怎样处理？

- A：拒绝新 enqueue，完整保留 draft 和既有队列；用户管理后重新提交。（推荐）
- B：保留 draft并立即打开 queue 管理视图；用户显式腾出空间后再确认提交。
- C：要求用户明确选择一个既有 item-id；以同一 durable transaction 记录 drop-old + enqueue-new，否则不改变队列。

推荐 A。它的失败边界最清楚。B 更引导式；C 适合高频操作，但必须有明确替换确认。三项都不自动丢最旧/最新项，也不允许无界增长。

关联：AQ-032、AQ-086、CONC-02、LOOP-06、TUI-06。

### AL06-05：steer 对当前活动的抢占边界

问题：Ctrl+Enter 的 steer durable 后，当前活动在什么安全点让位？

- A：取消可取消的 model/review、AL06-11 A model-compaction request 或 B Runtime checkpoint；未开始的 accepted tools 写 skipped-by-steer；运行中工具等真实/unknown result 后，在同一 turn 注入 steer。（推荐）
- B：不抢占当前 request 或已接受 tool batch；该批按 TS-10/TS-20 已选 admission、并行与失败后收口策略完成后，在同一 turn 的下一次采样注入 steer。
- C：抢占 model/review、AL06-11 A model-compaction request 或 B Runtime checkpoint；若 tool batch 已 accepted，则不再因 steer 改写该批的已选 TS-10/TS-20 策略，已/尚未 admission 的调用都继续服从 TS-10，若中途观测到 failure 才用 TS-20 收口，然后注入 steer。

推荐 A。它最接近“插队纠偏”，同时不伪造回滚。B 实现最简单但错误方向可能持续更久；C 保留整批工具的原始模型意图。三项都保存 steer 身份、不丢弃事实、不建立暗中新 turn。

关联：AQ-087、AQ-089、AQ-094、AQ-098、AQ-127、AQ-233、AQ-234、AQ-255、LOOP-06、LOOP-07、LOOP-13、PROC-03。

## AL06-21 approval-waiting 的 Esc 投影（不是负责人投票）

approval 不能另有一套和全局焦点/取消规则冲突的 Esc 选项。AL06-35 是唯一负责人：其 A 在 approval 焦点下等于 deny 当前 action、写 synthetic denied result 并允许 main 继续；B 等于取消整个 main turn；C 把 approval 作为可选目标，选择后写 synthetic approval-cancelled result 并让 main waiting-user。任何路线都必须给 accepted call 配对结果，不留下悬空 approval。

关联：AL06-35、AQ-027、AQ-094、AQ-098、AQ-127、SAFE-14、LOOP-07、LOOP-13、TUI-04。

### AL06-06：side 的活动容量与 main 忙时调度

问题：Alt+Enter side 在 main 活动时怎样调度，以及额外 side 输入怎样处理？

- A：最多一个 active side 与 main 并发；side busy 时拒绝新 side 并保留 draft。（推荐）
- B：最多一个 active side、另有一个 pending side；pending 在 active side 结束后启动，超过一个 pending 就拒绝。
- C：side 不与 main 并发；main 忙时最多保留一个 pending side，在下一个 model-safe point 串行执行。

推荐 A。它最符合“一条直接回复”，又把并发硬限制为一个 side。B 减少重输但多一层排队；C 对旧平台事件泵最轻。三项都无工具、使用已提交事实快照并有明确硬上限，不允许无界 side queue。

关联：AQ-008、AQ-025、AQ-026、AQ-088、AQ-095 至 AQ-097、AQ-234、LOOP-06、LOOP-23、CONC-01、RUNTIME-02。

### AL06-22：side 的请求/token 预算归账

问题：side usage 从哪个预算池扣除？

- A：每个 side 有独立硬 cap，不消耗 active main turn guard；始终计 runtime，AL06-09 A/C 时再扣 Context hard ledger，B 时只写 Context audit。（推荐）
- B：每个 side 仍有独立硬 cap；main 活期间还同时扣当前 turn guard（AL06-09 A/B 的可配置 ledger，或 C 的固定 safety cap），空闲 side 没有可借用的 turn；Context/runtime 仍按 AL06-09 扣除或审计。
- C：side 不设独立 lifecycle 池；main 与 side 共用 AL06-09 最外层的累计 hard ledger——A/C 为 Context，B 为 runtime 内固定的累计 request/token safety quota——但每个 request 仍有 request hard cap，Context 在 B 下仍只审计。

推荐 A。它不会让一个旁问意外耗尽主任务步骤，同时总成本仍可见、有界。B 更严格地限制 main 活动期总花费；C 字段最少，但一次 side 可能挤压后续 main。三项都只映射 AL06-09 已存在的层，因此与 AL06-09 A/B/C 的九种组合全部有定义。

关联：AQ-028、AQ-096、AQ-100、AQ-153、LOOP-04、LOOP-23、CONC-01、PERF-01。

### AL06-23：side 结果进入 main model view 的显式方式

问题：用户想让 side 答案影响主任务时，采用哪种显式动作？

- A：提供 side-use <side-id>，用户再选择 queue 或 steer；生成一条用户授权的引用事实。（推荐）
- B：不提供专门动作；用户复制需要的文字到普通 queue/steer。
- C：side 完成后提供一次 use-in-main 确认；确认后选择 queue/steer，未确认永不进入 main view。

推荐 A。它既不要求复制长回复，也保留用户明确授权。B 表面最少；C 发现性更好但每次多一个提示。三项都保存 side 对话供审计，却不自动把它放入 main view，也不让 side 改变主任务。

关联：AQ-008、AQ-095、AQ-096、AQ-097、LOOP-23、CTX-07、TUI-03。

### AL06-07：DoubleCheck action-review 的动作范围

问题：DoubleCheck=true 时，哪些 accepted actions 必须经过无工具 action-review？

- A：Execute、Write/Delete/Rename、outside-workspace、敏感读取、未来 direct Network 和 Permission=ask。（推荐）
- B：所有 executable tools；只有 Runtime control 与纯 UI/session 查询排除。
- C：不提供 action-review；DoubleCheck 仅做 termination-review，所有 action 都由 Permission 直接 allow/deny 或进入人工 approval。

推荐 A。它把额外 Token 集中到真实副作用和敏感边界。B 最谨慎但成本最高；C 最简洁，但 DoubleCheck 对 action 不再有 LLM 复核层。A/B 不能改变 Permission=deny；C 直接服从 Permission。三项都不把 Cautious 变成权限 profile。

关联：AQ-020、AQ-038、AQ-104、AQ-149、AQ-150、AQ-224、SAFE-01、SAFE-03、SAFE-11、SAFE-15、LOOP-10。

### AL06-24：action-review verdict 的人工 override 范围

适用性：只有 AL06-07 A/B 存在 action-review 时本组生效。若 AL06-07 C，本组在有效配置/决策投影中标为 `not-applicable`，Permission=ask 仍可进入普通人工 approval，但不存在 reviewer verdict 可覆盖。完整回复可预先保留本组字母，它不得在 C 分支产生运行行为。

问题：Permission 非 deny 且动作 snapshot 仍新鲜时，人能否覆盖 reviewer verdict？

- A：reject 或 uncertain 都可一次性 override；只绑定该 operation snapshot。（推荐）
- B：只可 override uncertain；明确 reject 必须由模型提出新动作。
- C：任何非-allow verdict 都不可 override；当前 action 直接得到 synthetic denied result。

推荐 A。最终授权仍在用户手里，同时旧 verdict、参数变更或 Permission=deny 都不能复用。B/C 更保守，但 reviewer 故障或误判会更常阻断任务。

关联：AQ-022、AQ-038、AQ-149 至 AQ-151、AQ-224 至 AQ-226、SAFE-14、SAFE-16、LOOP-10。

### AL06-25：action-review 请求失败后的安全降级

适用性：只有 AL06-07 A/B 时本组生效。AL06-07 C 下没有 action-review request，因而必须标为 `not-applicable`，不生成 retry、reviewer 错误或相关配置字段。

问题：transport/schema 重试达到硬上限后怎样处理 action？

- A：转 waiting-user，展示 retry/reviewer 原因，并提供一次精确 approve-or-deny 选择；绝不自动 allow。（推荐）
- B：fail-closed 为 synthetic denied result，让 main 模型继续寻找替代。
- C：转 waiting-user，只提供 retry-review 或 deny，不提供人工 approve。

推荐 A。它既不把 DoubleCheck 故障当通过，也不会因临时网络问题永久卡死。B 自动收口最快；C 保留 reviewer 的强制地位。所有选择都遵守 Permission=deny 不可覆盖。

关联：AQ-021 至 AQ-023、AQ-104、AQ-151、AQ-225、SAFE-11、SAFE-14、LOOP-10、MODEL-09。

### AL06-08：DoubleCheck reviewer 使用哪个 Model

问题：DoubleCheck 的 action-review（仅 AL06-07 A/B 存在）与 termination-review 共同由哪个完整 Model 实例执行？

- A：两类 review 都使用当前 turn 冻结的 main Model，但分别以 action-review/termination-review 独立 purpose/request 执行。（推荐）
- B：配置显式命名同一个 ReviewModel，两类 review 共用；缺失、无效或跨 endpoint 未确认时转 waiting-user，不 fallback。
- C：每个 Context 首次需要任一 review 时显式选择并持久化一个共用会话映射；它作为 `ReviewModelMapping` 的非秘密逻辑 Model 引用写入 XML session snapshot 并追加 mapping-selected 事件，action/termination 都用该映射，映射失效后重新选择。

推荐 A。它不增加配置和历史外发边界。B 可用不同能力做复核；C 更灵活但交互和恢复更复杂。三项都遵守“一个 Model section 是完整连接实例”，不使用配置第一项作为暗中默认。若 AL06-07 C，action 分支不存在，本组选择仍完整决定 termination reviewer，不会因此生成空 action request。

关联：AQ-019、AQ-021、AQ-099、AQ-109、AQ-151、MODEL-12、LOOP-25、D-028。

### AL06-26：termination-review 非 finish verdict 的控制流

问题：reviewer 返回 continue/uncertain，或请求最终失败后，main turn 怎样走？

- A：合法 continue 把具体缺口交回同一 turn 继续；uncertain/最终失败转 waiting-user；达到 review round cap 也 waiting-user。（推荐）
- B：任何非 finish verdict 都立即 waiting-user，不自动建立下一次 main request。
- C：首次 continue 允许同一 turn 再采样一次；本次之后仍非 finish 或任何失败就 waiting-user。

推荐 A。它最贴近“复核发现缺口就继续做”，同时所有失败都 fail-closed。B 最省 Token；C 给一次自动修正机会且更容易预测费用。三项都不把失败、超时或 malformed verdict 当作 finish。

关联：AQ-021 至 AQ-023、AQ-099、AQ-109、LOOP-03、LOOP-25、LOOP-27、MODEL-12。

### AL06-27：action/termination review 的预算池关系

问题：review 的局部上限怎样与 main turn 总预算相交？

- A：termination 有局部 round cap；仅当 AL06-07 A/B 启用 action-review 时 action 才另有局部 cap。存在的 review 共同消耗 AL06-09 选定的 turn guard：A/B 扣可配置 request/token/active-time ledger，C 扣固定 composite safety cap。（推荐）
- B：两类 review 共用一个 DoubleCheckRequests 局部 cap，同时也按 A/B 可配置或 C 固定的方式消耗同一 turn guard。
- C：在 AL06-09 已选的 turn guard 内预留一个固定、有界 review reserve；main 不能耗用该份额，review 也不能超出它，但 reserve 不增大 turn 总 cap。A/B 仍扣同一可配置 token/time ledger，C 仍扣固定 safety cap。

推荐 A。它能分别解释两种 review 的费用，又防止二者互相绕过总预算。B 配置更少；C 为完成复核保留请求名额，但不会创造额外容量。若 AL06-07 C 关闭 action-review，本组的 action 份额自然为零，termination 份额仍按同一规则归账。三项都与 AL06-09 A/B/C 完整可组合。

关联：AQ-028、AQ-099、AQ-100、AQ-151、MODEL-12、LOOP-04、LOOP-25、LOOP-27、PERF-01。

### AL06-09：通用预算层级

问题：主 AgentLoop 使用哪种硬预算层级？

- A：attempt、request、turn、Context、runtime 五层，分别记录并由更外层封顶。（推荐）
- B：request、turn、runtime 三层；Context 只累计审计，不承担额外 hard cap。
- C：request、Context、runtime 三个 hard layer，另有一个由发行版固定、不暴露 INI 字段且不可变为无限的 per-turn composite safety cap，封顶 step/request、token/output 和 active time。

推荐 A。它能区分一次网络重试、一次模型意图和整轮成本。B 字段少但长 Context 总量不受硬界；C 用发行版安全 cap 阻止单 turn 失控，而把用户可配置总量放在 Context。三项都由本组唯一定义层级；AL06-22/27 只在已选层内归账，且 Model 切换、retry 或新子循环都不得重置任何 ledger/cap。

关联：AQ-028、AQ-029、AQ-100、AQ-153、AQ-154、AQ-196、AQ-197、LOOP-04、LOOP-05、LOOP-27、PERF-01、PERF-02。

### AL06-28：检测到无进展循环后的收口策略

问题：progress fingerprint 达到 stuck 阈值后怎样给最后机会？

- A：durable warning 一次并允许一个受剩余预算限制的策略改变 step；再次等价循环就 stuck。（推荐）
- B：首次达到阈值就立即 stuck，不再采样。
- C：转 waiting-user，用户可明确授权最多一个 escape step；若仍无进展就 stuck。

推荐 A。它允许模型自行纠正一次，仍有确定硬停。B 最省成本；C 把额外花费交给用户。阈值只能在安全范围内配置，任何选项都不能关闭 hard cap，也不能靠改措辞重置 fingerprint。

关联：AQ-029、AQ-101、AQ-154、AQ-196、AQ-197、AQ-283、LOOP-05、LOOP-14、LOOP-27。

### AL06-15：存在明确验证命令时的执行策略

问题：任务有安全、可授权且可运行的明确验证命令时，Agent 默认怎样做？

- A：在剩余预算内至少自动尝试一次，并保存 typed command/outcome/evidence。（推荐）
- B：执行前总是询问一次用户，即使 Permission 本可直接 allow。
- C：不自动执行；最终 receipt 必须明确 unverified 并给出精确命令，绝不声称 tests passed。

推荐 A。它最符合完整 Coding Agent 闭环。B 控制更强但频繁中断；C 适合极保守环境。任何选项下，失败后的修正都受同一 turn budget/stuck gate，无法验证不能伪装成通过。

关联：LOOP-09、TOOL-13、AQ-153、AQ-154。

### AL06-10：active turn 中 Model switch 的生效方式

问题：main turn 活动时执行 .model，怎样避免同一 turn 混用能力不同的 Model？

- A：记录 pending switch，当前 turn 收口后预检并从下一 turn 生效。（推荐）
- B：先要求确认取消当前 turn；真实/unknown effect 收口后切换，并等待用户显式继续，不自动重发旧目标。
- C：忙时拒绝切换；用户必须先显式 cancel turn，回到 ready 后再执行 .model。

推荐 A。它保留当前工具配对和 turn snapshot。B 更快地改变策略但会结束当前轮；C 规则最简单。三项都禁止在同一 turn 的下一 sampling step 偷换 Model，并在切换前检查窗口、roles、tools、历史配对与 endpoint。

关联：AQ-031、AQ-065、AQ-107、AQ-108、AQ-142、AQ-156、AQ-235、MODEL-07、MODEL-10、LOOP-15。

### AL06-29：恢复时旧 Model 缺失的映射体验

问题：Context snapshot 引用的旧 Model 已不在 INI 时，用户怎样恢复可运行映射？

- A：先只读展示旧 snapshot；用户选择替代 Model，预检后写 durable mapping/switch，新 Model 首个 view 带 old/new/reason/能力差异/未完成项。（推荐）
- B：拒绝替代映射；只有重新建立同逻辑名且通过预检的 Model 后才能继续。
- C：允许从非秘密 snapshot 建立一个 disabled Model draft；用户补 Key/必要字段并通过 self-test 后再显式启用。

推荐 A。它最容易换机接盘且不静默 fallback。B 身份最严格；C 辅助重建配置但需要 config-repl 事务。所有选项都不把 INI 第一项、同名 RemoteModel 或相似 endpoint 当作自动映射，XML 也始终保存完整 Model 转换事实。

关联：AQ-031、AQ-107、AQ-108、AQ-164、AQ-235、AQ-236、AQ-347、MODEL-07、MODEL-10、CTX-27、D-035。

### AL06-11：压缩后的 main model-view 结构

问题：在不改变 XML 事实历史的前提下，首版采用哪种有损视图策略？

- A：一个 structured prefix compaction + 最近完整 atomic groups；每 request 保存 view manifest。（推荐）
- B：一个 deterministic extractive checkpoint（事实字段与 refs，不生成自由摘要）+ 最近完整 atomic groups + manifest。
- C：首版不执行任何 compaction model request；保留 immutable Prompt 和必保动态状态后，只附加能完整容纳的最新 atomic groups；任一必保项不能容纳时转 waiting-user/推荐大 Model。

推荐 A。它在简洁、语义密度和可审计性之间最好。B 更少模型幻觉但压缩率较低；C 最简单，却会更早要求换 Model。三项都保留全部 canonical facts，只改变派生 view，不允许摘要替换、截断或删除 XML 事件。

关联：AQ-061、AQ-164、AQ-179、AQ-190、AQ-240 至 AQ-243、AQ-260、COMP-01、COMP-03、COMP-06、COMP-07、COMP-09、CTX-02、CTX-04、CTX-07。

### AL06-16：单个 atomic group 大于 Model 窗口时的产品行为

问题：一个完整、必需的 atomic group 自身已经放不进当前 Model 时怎样停？

- A：阻断该 request，优先推荐 Context 历史中曾使用且足够大的 Model，再列其他兼容 Model；waiting-user。（推荐）
- B：若该 atom 对当前 purpose 非必需，则整组不发送并在 manifest 放 typed unavailable-atom ref；一旦必需就按 A 阻断。
- C：把当前 turn 收口为 error，reason=capacity-mismatch，receipt 完整保存未完成项；不提供自动推荐，由用户在 model-repl 自行选择后开新 turn。

推荐 A。它不会让模型在缺关键事实时猜测。B 可让无关 purpose 继续，但必须证明“非必需”；C 状态最明确但体验更硬。三项都不拆 tool call/result 或 approval/operation 对，不截取头尾，也不删除原 XML 事实。

关联：AQ-061、AQ-164、AQ-179、AQ-190、AQ-240 至 AQ-243、AQ-260、COMP-01、COMP-03、COMP-06、CTX-02、CTX-07。

### AL06-12：历史大窗口 Model 之后的候选展示范围

问题：已确认“Context 历史中曾使用且窗口足够的 Model 必须优先提示”；在它之后还展示多少替代 Model？

- A：先单独置顶历史中足够大的旧 Model，再列出其余已经配置、能力预检通过且窗口足够的 Model。（推荐）
- B：只提示历史中足够大的旧 Model；其他选择必须显式进入 model-repl 查找。
- C：同屏列出所有预检通过的足够大 Model，但历史 Model 固定排第一并标注 `previously used`，不替用户预选。

推荐 A。它忠实执行“先前 Model 优先”，同时在旧实例已失效或费用不合适时给出可用退路。B 页面最简单；C 比较最快但信息更密。三项都在 provider 真正报 context error 前预检，不自动切换、不自动跨 endpoint；用户不切换后，AL06-11 A 的 compaction 许可只由 AL06-34 决定，B 直接运行 deterministic Runtime checkpoint 且 AL06-34=`not-applicable`，C 则 waiting-user 且 AL06-34=`not-applicable`。

关联：AQ-030、AQ-156、AQ-179、AQ-227、AQ-240、AQ-241、COMP-02、COMP-04、COMP-08、LOOP-08。

### AL06-30：compaction request 使用哪个 Model

适用性：只有 AL06-11 A 会建立 model compaction request，本组才生效。AL06-11 B/C 下本组标为 `not-applicable`：B 是 Runtime deterministic checkpoint，C 没有 checkpoint；即使完整回复中预先给了字母，也不生成 `CompactionModel` 条件配置、Model mapping、request 或跨 endpoint 确认。

问题：真正执行 structured compaction 时使用哪个完整 Model 实例？

- A：当前 turn 冻结的 main Model，独立 purpose/request、无工具。（推荐）
- B：配置显式命名 CompactionModel；跨 endpoint 前显示历史范围并确认，失效时 waiting-user。
- C：每次压缩时从兼容 Model 列表显式选择；选择只对本次 compaction 生效并写入事实。

推荐 A。它不增加数据外发和映射。B 可用更便宜/长窗口模型；C 控制最细但频繁中断。三项都禁止使用配置第一项或静默 fallback，也不能给 compaction Model 工具权。

关联：AQ-156、AQ-179、AQ-240 至 AQ-243、COMP-04、COMP-08、MODEL-07、MODEL-12。

### AL06-31：compaction schema 无效或无收益后的重试

适用性：只有 AL06-11 A 时本组生效。AL06-11 B/C 下不存在 model compaction response/schema，因而本组标为 `not-applicable`：B 的 Runtime 完整性错误是 fail-stop，C 无 checkpoint；两者都不产生 correction/retry 计数或 rejected-model-compaction 事件。

问题：一次 compaction 完整返回但 schema 无效、摘要无收益或仍超限时怎么办？

- A：最多一次新的 correction/compaction request；仍失败就保留旧 view 并 waiting-user。（推荐）
- B：不自动重试；立即保留旧 view 并 waiting-user。
- C：不做 schema correction；立即转为 AL06-12 的大 Model 选择提示，用户拒绝后 waiting-user。

推荐 A。它给偶发格式错误一次恢复机会，又保持确定上限。B 最省 Token；C 优先解决根本窗口不足。三项都记录 rejected attempt、保留旧 compaction/事实，不递归无限压缩，也不自动重放 main/tool 请求。

关联：AQ-227、AQ-230、AQ-240 至 AQ-243、COMP-04、COMP-05、LOOP-08、LOOP-24。

### AL06-32：崩溃后 unfinished main turn 的恢复边界

问题：恢复器收口 interrupted request/tool/review 后，旧 main turn 怎样继续？

- A：保留为 resumable waiting-user；用户显式 resume 后重建 view，但 unknown operation 必须先检查/决定。（推荐）
- B：把旧 turn 结束为 error，reason=interrupted；用户的新输入建立新 turn，并通过 caused-by 引用旧轮。
- C：按最后 durable state 分类：从未发出外部 effect 时允许显式 same-turn resume；否则以 error/reason=interrupted 结束旧 turn，用户开新 turn。

推荐 A。它最能保留原目标和预算账本。B 的恢复模型最简单；C 在安全与连续性之间折中。三项都先写恢复事实，不自动重发 model request、review、tool 或 unknown operation，也不重新分配/改写旧 ID。

关联：AQ-030、AQ-227、AQ-230、LOOP-08、LOOP-24、CTX-08、CTX-16、CTX-17。

### AL06-17：系统 suspend/resume 后的活动请求处理

问题：检测到长时间系统停顿后，当前 main/side 网络与 helper 活动怎样收口？

- A：用 monotonic 时间保留已消耗预算；重新检查 workspace/config/writer/network identity，取消过期活动并形成 timeout/cancel/unknown，安全的本地状态才继续。（推荐）
- B：完成同样重检和取消，但整个 active turn 一律转 waiting-user，由用户显式 resume。
- C：完成同样重检和取消，并把 active turn 收口为 error，reason=suspend-interrupted；queue 保留，用户开新 turn。

推荐 A。它对短暂休眠最顺滑，又不相信跨 suspend 的旧 socket/process。B/C 更保守。三项都记录 wall-clock gap，不重置 budget/deadline、不复用未验证句柄，也不因时钟跳变自动 retry 副作用。

关联：RUNTIME-06、PROC-03、NET-04、LOOP-04、LOOP-08。

### AL06-33：多条 queue item 怎样组成后续 turn

问题：当前 main turn 忙时连续按 Enter 排入多条消息，释放后它们是一条条独立任务，还是合成一次模型输入？

- A：每条 queue item 按当前顺序独立建立一个新 turn；完成门由 AL06-04 决定。（推荐）
- B：默认仍逐条建立 turn，但 queue REPL 提供显式 `merge <item-id>...`；合并写 durable amendment，保留原 item 边界与顺序。
- C：同一个 active turn 期间新增、且在消费前没有被 edit/reorder 的连续 queue item 自动合成下一个 turn；XML 仍保存每条原输入身份。

推荐 A。它最符合“Enter 是排队消息”而不是隐式多行输入，也避免后一句本来依赖前一轮结果却被提前拼入。B 适合用户明确组织一批约束；C 打字最快，但自动分组边界容易和用户意图不同。三项都不把 waiting-user 后的 queue 当作问题答案自动发送，也不丢失原始 item 身份。

关联：AQ-024、AQ-032、AQ-086、AQ-092、AQ-093、LOOP-01、LOOP-06、CTX-07、TUI-06。

### AL06-34：达到阈值后的 compaction 许可体验

适用性：只有 AL06-11 A 时本组生效。AL06-11 B/C 下本组标为 `not-applicable`：B 的 deterministic Runtime checkpoint 既不花 Model Token 也不询问 consent，C 不做 checkpoint；两者均不显示 compaction consent、不生成 `CompactionConsent` XML 投影，也不因模板中的预先字母而发起模型压缩。

问题：AL06-12 已决定“大 Model 提示与压缩的先后”，但真正产生有损摘要前默认是否还要人工确认？

- A：在状态区说明来源范围、估算收益和可取消性后自动压缩；使用 AL06-30 已选定的 Model，其失效或跨 endpoint 确认未完成时 waiting-user。（推荐）
- B：每一次 compaction 都先等待一次 `compact/cancel/switch-model` 选择；`switch-model` 只进入 AL06-30 已选路线，本组不自己选 Model；未确认不花 Token，也不改变当前 view。
- C：每个 Context 第一次需要压缩时询问 `auto for this Context/ask every time/cancel`；`auto`/`ask-every` 必须作为会话级 `CompactionConsent` 投影写入 XML session snapshot 并追加选择事件，`cancel` 只取消本次且不伪造持久偏好；以后仍显示每次开始和结果。

推荐 A。它保持长任务连续，且 XML 原始事实从未被删除；代价是会自动产生一次可见的模型费用。B 费用最透明但频繁打断；C 平衡二者，却新增一个必须由 Context schema 完整恢复的会话状态。本组只拥有 consent；使用哪个 Model、跨 endpoint 确认和兼容预检全部服从 AL06-30，必保原子组放不下也不能靠本组自动批准。

关联：AQ-030、AQ-156、AQ-179、AQ-227、AQ-240、AQ-241、COMP-02、COMP-04、COMP-08、LOOP-08、CTX-07。

### AL06-35：Esc 在多活动面中的目标选择

问题：main、side、REPL/详情页和本地 draft 可能同时存在时，Esc 用什么确定规则选择取消目标？

- A：焦点优先、再取消该焦点的最内层活动；完整 focus×state 规则见下表 A。（推荐）
- B：本地页面焦点优先 back；否则只要 main turn 活动就取消整轮，side 业务取消必须用显式命令；完整规则见下表 B。
- C：从当前 local/draft/approval/main/side 状态确定生成候选；唯一候选直接执行，两个以上打开 ASCII 单选列表；完整规则见下表 C。

表中“本地页面”只指 config/context/model REPL、详情页、help 和普通本地 modal，不包括属于 main 状态的 approval。按键事件先用最新 UI event-seq 规范化焦点；已关闭面板或已结束 lane 的 stale focus 不参与决策。这使下面每个表都是完整、不依赖时间窗的优先级。

#### A：焦点优先的完整规则

| 优先级 | 当前 focus × state | Esc 结果 | 未选 lane |
| --- | --- | --- | --- |
| 1 | 本地页面有焦点，无论 main/side 是否活动 | 执行该页的 back；有未保存事务时进入它自己的 discard-confirm，不暗中放弃 | main/side 不变 |
| 2 | approval 焦点 + approval-waiting | deny 精确 action，写 synthetic denied result，main 可按结果继续 | side 不变 |
| 3 | 输入区焦点 + 非空 draft，无论 main/side 是否活动 | 清空当前 draft；后续 Esc 重新从新状态计算，不靠双击时间窗升级 | main/side 不变 |
| 4 | side 焦点 + side active | 只取消 side，等 complete/incomplete/cancelled 真实收口 | main 不变 |
| 5 | main 焦点 + model/review/AL06-11 A compaction request/B checkpoint/retry active | 取消当前最内层 effect，然后把 main turn 真实收口为 cancelled | side 不变 |
| 6 | main 焦点 + tool-executing | 请求终止，等真实/unknown result 并配对 batch 后把 main 收口为 cancelled | side 不变 |
| 7 | main 焦点 + 其他 active main 状态 | durable cancel-turn，在该状态的下一安全边界收口 | side 不变 |
| 8 | 无上述有效焦点且 main active | 焦点归一为 main，再按 5–7 处理 | side 不变 |
| 9 | main 不 active、side active，且无 local/draft/approval 可取消焦点 | 焦点归一为 side，再按 4 处理 | main 不变 |
| 10 | ready、无 side active、无 draft/本地页 | 不退出，显示 `.exit/.quit` 提示 | 无变化 |

#### B：“本地 back，否则整轮 main”的完整规则

| 优先级 | 当前 focus × state | Esc 结果 | 其他活动 |
| --- | --- | --- | --- |
| 1 | 本地页面有焦点，无论 main/side 是否活动 | 只 back/discard-confirm 本地页 | main/side 不变 |
| 2 | main active，且没有本地页面焦点；不问当前是 main、side、draft 还是 approval 焦点 | 取消整个 main turn；approval 中未执行 call 写 synthetic cancelled，tool 按真实/unknown 收口 | side 不变 |
| 3 | main 不 active + 非空 draft | 清空 draft | side 不变 |
| 4 | main 不 active + side active + 无 draft/本地页 | 不取消 side，显示唯一显式 side-cancel 命令的提示 | side 继续 |
| 5 | main/side 都不 active、无 draft/本地页 | 不退出，显示 `.exit/.quit` 提示 | 无变化 |

#### C：候选集合与选择结果的完整规则

Esc 到达时从当前 focus×state 一次性生成候选：本地页面活动列 `local`；非空输入草稿列 `draft`；approval-waiting 同时列 `approval` 与 `main`，使用户能区分“取消这次批准”与“取消整轮”；其他 main active 列 `main`；side active 列 `side`。候选与当前视觉焦点无关，因此 main + local modal 不会发生隐式优先级。

| 当前 chooser/候选状态 | Esc 或选择的确定结果 |
| --- | --- |
| cancel chooser 已打开 | Esc 只关闭 chooser，不取消候选中任何目标 |
| 0 个候选 | 不退出，显示 `.exit/.quit` 提示 |
| 1 个候选 | 不开 chooser，直接执行下表对应动作 |
| 2 个以上候选 | 打开 ASCII 单选；列表按 `local, draft, approval, main, side` 固定排序，不预选、不因当前 focus 自动提交 |

| 选中目标 | 确定结果 |
| --- | --- |
| local | 对页面执行 back/discard-confirm，main/side 不变 |
| draft | 只清空 draft，main/side 不变 |
| approval | 写 synthetic approval-cancelled result，main 转 waiting-user，side 不变 |
| main | 取消整轮；运行中 tool 先收口真实/unknown result，side 不变 |
| side | 只取消 side，main 不变 |

推荐 A。它符合“Esc 终止当前正在处理的东西”，快捷且可用状态/焦点表完整测试。B 最容易记忆，但查看 side 时也可能误杀主任务；C 最明确，却让紧急取消多一步。三项都必须显示已经接受取消、正在收口还是最终 unknown，重复 Esc 不得重复执行副作用。

关联：D-033、AQ-027、AQ-068、AQ-069、AQ-094、AQ-098、AQ-127、LOOP-07、TUI-04、PROC-03。

### AL06-36：`finish(partial)` 是否构成真实终态

问题：主模型明确知道目标没有全部完成时，能否用 `finish(partial)` 正常结束这一 turn，而不是一直问用户或等预算错误？

- A：可以；必须给出已完成、未完成、原因、验证与 unknown effects，形成 `partial` terminal outcome；DoubleCheck=true 时仍做 termination-review。（推荐）
- B：不可以；唯一正常完成 control 是 `finish(completed)`，未完成时只能 `ask-user`/普通 yield 等待决定，或由 Runtime 以 budget/error/cancel 等真实原因收口。

推荐 A。现实任务可能因外部依赖、权限或用户限定范围只能部分交付；把它做成有结构的诚实终态，比伪装 completed 或无限追问更清楚。B 的完成语义最严格，但用户想接受阶段成果时缺少正常收口语言。无论哪项，Runtime 都不能替模型伪造 `finish(partial)`，AL06-04 仍独占 queue 是否自动前进。

关联：AQ-024、AQ-101、AQ-251、AQ-252、PROD-03、LOOP-03、LOOP-10、LOOP-25、ED-05。

### AL06-37：合法 mixed text + tool response 的展示与模型历史

问题：一份完整合法的 assistant response 同时包含说明文字和一个或多个 tool calls 时，文字怎样保存、显示并进入下一次采样？

- A：保留 provider 的规范 block 顺序；TU-03 允许的 provisional delta 可实时显示，完整 response 验证成功后立即在原位置提升/标记为 canonical 调用说明，而非 terminal outcome。工具批次收口后，下一 request 同时看到原文字、calls 和逐项 results。（推荐）
- B：canonical/XML 仍保存原 block 顺序，TU-03 允许的 provisional delta 也可能已经在原位置显示；本项只延迟“已收口/canonical”的 TUI promotion，直到该批全部 calls/results 配对。收口时只输出指向原 block 的稳定标记/引用，不重排、重放或假装先前没有显示过；模型视图不改变。
- C：首版拒绝 mixed response，按 AL06-19 请求模型改成“纯 tool batch”或“纯文字/control”；纠错失败就 waiting-user。

推荐 A。它最忠实于模型实际输出，也符合常见“我先检查……”后调用工具的体验。B 避免在工具最终失败前就把说明标成已收口，又不与 TU-03 的 provisional streaming 冲突；C 协议最窄但会增加兼容失败和额外 Token。A/B 必须等完整 response 和整批参数校验后才接受工具；C 整份拒绝且零调用被接受。任何路线都不能把文字当作 completed，也不能无声丢弃它。

关联：AQ-099、AQ-254、AQ-256、AQ-324、MODEL-02、MODEL-05、LOOP-13、LOOP-14、CTX-07、TUI-03。

### AL06-38：普通无 control 回复怎样收口

问题：主模型返回完整、合法、无工具、也没有 `finish/ask-user/refuse` control 的普通文字时，Runtime 怎样处理？

- A：把文字显示并保存为 model-yield，main turn 形成 `waiting-user`；不自动续采样，也不启动 queue。（推荐）
- B：立即把完整文字显示并保存为 canonical `model-yield-needs-control` 事实，再最多建立一次只允许 control/report 的 protocol-correction request；有效 control 决定本 turn outcome，仍无 control 就按 A waiting-user。
- C：兼容传统 chat：provider 正常 stop 且没有未完成项/unknown effect 时视为隐式 `finish(completed)`；DoubleCheck=true 时仍触发 termination-review，其他 finish reason 按 A。

推荐 A。它既不把一句解释误判成任务完成，也不会为普通对话强制多花一次纠错请求；模型确实完成时应明确调用 finish。B 协议最严格但每次遗漏都会增加延迟和 Token；C 兼容弱 endpoint，却重新引入 Runtime 推断完成的歧义。三项都不根据“看起来完成了”等自然语言关键词判断，也不允许普通文字跳过真实错误、审批或工具配对；B 的原回复已经完整收口，不能再称 streaming provisional/incomplete，也不能由纠错响应改写或删除。

关联：AQ-024、AQ-101、AQ-110、AQ-251、AQ-252、MODEL-06、PROD-03、LOOP-03、LOOP-10、LOOP-24。

## 推荐的整包组合

若负责人接受推荐基线，可以逐项回复下面的完整模板：

~~~text
AL06-01 A
AL06-02 A
AL06-04 A
AL06-05 A
AL06-06 A
AL06-07 A
AL06-08 A
AL06-09 A
AL06-10 A
AL06-11 A
AL06-12 A
AL06-13 A
AL06-14 A
AL06-15 A
AL06-16 A
AL06-17 A
AL06-18 A
AL06-19 A
AL06-20 A
AL06-22 A
AL06-23 A
AL06-24 A
AL06-25 A
AL06-26 A
AL06-27 A
AL06-28 A
AL06-29 A
AL06-30 A
AL06-31 A
AL06-32 A
AL06-33 A
AL06-34 A
AL06-35 A
AL06-36 A
AL06-37 A
AL06-38 A
~~~

也可以只回复差异，例如：

~~~text
本包其余明确接受推荐；
AL06-06 C，旧平台首版 side 排到 model-safe point；
AL06-15 B，每次验证命令先询问；
AL06-24 C，不允许人工覆盖 reviewer；
AL06-32 C，只有没有外部 effect 的旧 turn 才允许 same-turn resume；
AL06-34 B，每次压缩先确认；
AL06-35 C，多目标时打开取消目标列表；
AL06-38 B，缺 control 时先纠错一次。
~~~

没有明确回复的编号继续保持 unanswered。回复“按最合适方案”“看起来没问题”或只讨论其中一句，都不会自动把 36 组推荐、默认次数或 schema 拼写升级为决定。

## 本包确认后的归档与实现前证据

负责人回复后，应分别更新：

- DECISIONS.md：只记录明确确认的 AL06 选择。
- subsystems/09-agent-session.md：唯一状态机、typed control、outcome、busy input 和预算。
- subsystems/08-permission-and-safety.md：action review、人工 override 和 approval binding。
- subsystems/10-context-storage.md：ID、canonical event、恢复收口和 model-view manifest。
- subsystems/12-context-compaction.md：结构化 schema、触发、无收益与 correction。
- subsystems/22-application-runtime-and-concurrency.md：main/side lane、事件泵、取消和背压。
- CONFIG-SCHEMA-CANDIDATE.md：只把确认的预算/round/stuck 字段转为正式 schema。

进入编码计划前至少需要以下可执行证据：

1. 每个 main 状态对 cancel、storage fault 和 invalid event 的表驱动测试。
2. finish、ask-user、refuse、ordinary yield、provider refusal、length 和 malformed control golden responses。
3. request/attempt retry trace，证明一次 logical request 不重复计费统计。
4. 流式 tool arguments 在 response 未完整结束前绝不执行的故障测试。
5. 多 tool batch 的成功、失败、deny、steer、cancel 和 synthetic pairing 测试。
6. Permission → review → approval → operation → execute 的顺序与 stale approval 测试。
7. termination continue、uncertain、失败、cancel 和 round cap 测试。
8. queue outcome gate、steer race、side 独立取消和 side-busy transcript。
9. 预算无法被 retry/review/compaction/Model switch 重置的测试。
10. exact-repeat、same-error、ABAB 和 no-progress warning/stuck fixture。
11. 小窗口切换、跨 endpoint 确认、旧 Model 消失和切回大窗口 view 重建测试。
12. AL06-11 A 的 compaction 必保槽位/schema/无收益/纠正，B 的 deterministic extractor-version/同输入同 digest/零 Model request，C 的零 CompactionRecord，以及 A/B 共同的原子组、source digest 与旧 view 保留测试。
13. 在每个 durable 边界模拟崩溃，证明 unknown operation 不自动重放。
14. XP x86 与最低 Linux 上主流、输入、side、tool 输出和 XML 慢写并存时仍有界响应。
15. 三种本地 ID 表示的唯一/不复用/复制后关系测试，以及 queue edit/reorder/drop 只追加 amendment 的恢复重放测试。
16. 协议纠错和 length continuation 的 0/1/2 上限 trace，证明不将新 logical request 记成 transport attempt，也不早执行 tool。
17. 在 AL06-07 A/B 下执行 action-review override、reviewer 失败、approval Esc 和 review budget pool 的 command × state 表驱动测试；C 下证明相关分支/字段为 `not-applicable`。
18. queue 逐项/显式合并、AL06-11 A 的 compaction 许可与 B/C 的 `not-applicable`、main/side/modal/approval 多焦点 Esc、partial terminal、ordinary yield 与 mixed text+tool 的 golden transcript 和恢复重放测试。
19. side 并发/串行、pending 上限、预算归账和显式进入 main view 的 golden transcript/usage ledger 测试。
20. 明确验证命令在 auto/ask/report-unverified 三种路线下的 receipt 和“没有证据不宣称通过”测试。
21. suspend/resume 注入 monotonic/wall-clock 跳变、过期 socket/helper 和 workspace/config 变化，证明不重置预算、不复用未验证句柄。
22. PJ-11 A 下证明 plan 字段/control/命令完全不注册；B/C 下用 plan-only tool schema、PlanArtifact 全 binding stale matrix、单次 `.execute`、不继承授权、cancel/crash/budget 和 plan-ready/read-only finish terminal golden trace 证明分阶段契约。
