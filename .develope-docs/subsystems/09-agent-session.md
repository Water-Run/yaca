# 09 AgentLoop 与会话状态机

状态：讨论中

## 为什么先讨论它

AgentLoop 决定 yaca 何时继续工作、何时询问、何时落盘、怎样执行工具、怎样取消以及什么才算完成。上下文、权限、配置、模型协议和 TUI 都要服从同一套 turn/event 语义，因此它是当前第一个产品级设计主题。

完整问题地图见 [`../DESIGN-CHECKLIST.md`](../DESIGN-CHECKLIST.md) 的 `LOOP-*`；五个参考实现的源码核对见 [`../references/agent-loop-reference-study.md`](../references/agent-loop-reference-study.md)。

## 职责

- 接受已经规范化的用户输入和 Runtime 提供的已验证 immutable `ConfigGeneration`，创建 turn 并冻结本轮运行视图。
- 通过上下文系统取得模型视图，通过模型层采样并解释规范化生成事件。
- 把工具请求交给权限和工具调度系统，将每个结果送回模型。
- 处理 busy input、取消、重试、压缩、验证、预算和防卡死。
- 产生持久化领域事件和机器可读的终止结果。

## 边界

- 不直接绘制终端；TUI、CLI 和内部测试 adapter 只是同一循环的输入/事件投影。v0.1 不存在 headless/remote 前端。
- 不直接读写上下文文件；只请求 10 号系统提交、flush、查询或构建模型视图。
- 不监视、读取或解析 INI；22 号 Runtime 在每个顶层 turn admission 前完成 D-048 的完整 bytes 观察与 generation 发布。AgentLoop 只接受一个已验证 generation，不能自行 fallback 到旧配置或物理第一项。
- 不理解 curl、SSE 或 provider 私有消息；只消费 06 号系统的规范化事件与错误。
- 不自行推断文件/命令是否安全；权限系统返回 allow、deny、ask 和授权范围。
- 不把“已写入文件”和“任务已完成”视为同一事实；完成还受验证与结束契约约束。

## 候选总体结构

建议由一个核心循环产生领域事件，所有前端消费相同事件：

```text
TUI ---------+
CLI ---------+--> command/input --> AgentLoop --> durable domain events --> Context Store
test adapter-+                         |
       ^                                +--> transient stream events
       |                                                |
       +------------------ event projection <-----------+
```

这样同一任务不会因从 TUI、CLI 或测试 fixture 注入而拥有不同的取消、权限、完成或持久化语义。PJ-17/D-044 已排除 v0.1 的 remote/headless 控制面；测试 adapter 不进入配置、help、发行包或公共协议，也不能被误写成未来前端预留。

## 已确认的 turn 配置冻结边界

D-048 已关闭“运行中配置何时生效”这一主轴。每个顶层 `main`/`side` turn admission 前，22 号 Runtime 完整读取 INI；source digest 未变就复用现有 immutable `ConfigGeneration`，变化则在整份 parse/schema/cross-field validation 全部通过后原子发布新 generation。AgentLoop 收到 generation 后，先冻结本 turn 的 Model、Permission、`DoubleCheck`、Prompt、工具 registry、网络/retry、预算以及由当前 Context XML 镜像父目录派生的唯一 workspace root，再允许建立 Model request 或工具副作用。

同一 turn 派生的 provider retry、工具循环、action/termination review、compaction 和其他 child activity必须继续使用这份快照；活动期间 INI 再变化不能逐字段热换。新候选删除、半写、不可读或无效时，只阻断尚未 admission 的新 turn并进入配置/Model self-fix；已经活动的 turn 仍按旧快照如实收口。当前 Model/Permission 在新 generation 中失效时，AgentLoop 不自动选择配置第一项。

Context Store 要保存能解释每个 turn 所用非秘密 generation、Model/Permission/Prompt/tool-schema/root snapshot 的事实或可验证引用；精确 XML schema 仍由 10 号系统和 `CFG-12` 决定。AgentLoop 不把 private INI source digest、Key 或其他 registered secret 写入 XML。

## 候选状态图

这是一张讨论底稿，不是已经确认的枚举：

```text
Idle
  |
  v
Preparing --storage/config error--------------------------> Error
  |
  v
RequestingModel <----------- Retry / Compact ------------+
  |                                                    ^  |
  v                                                    |  |
Streaming --complete text------------------------------+  |
  |                                                       |
  +--tool calls--> AwaitingApproval --> ExecutingTools ----+
  |                    | deny/cancel                         |
  |                    v                                     |
  +--------------> WaitingUser / Cancelled                   |
  |                                                          |
  +--typed ask/yield----------> WaitingUser
  |
  +--typed finish--> [DoubleCheck?] --> Finalizing --> terminal outcome
```

任意活动状态还必须接受 out-of-band cancel。`WaitingUser` 是可恢复的业务状态，`Cancelled` 是已结束结果；两者不能共用一个模糊的 paused 标记。

D-020 与 D-027 在“主模型提出 typed finish”和 `Finalizing` 之间增加一条条件分支：有效 `DoubleCheck` 关闭时直接进入 `Finalizing`；开启时进入 `EvaluatingTermination` 并发起独立完成复核请求。普通 provider stop/no-tool response 只说明一次生成结束，不能自动进入这条分支。评估允许后进入 `Finalizing`，评估拒绝或失败后的去向仍由后续原子问题确认。

## 事件的两层含义

### Durable 领域事件候选

- `turn_started`：用户输入、session/turn ID 和冻结视图已经可恢复。
- `model_request_started` / `model_message_committed`：记录请求身份、请求用途与完整、校验后的模型消息；主生成和终止评估不得共用模糊身份。
- `termination_evaluation_committed`：候选事件，记录评估请求对应的主模型终止意图、结构化 verdict 和结束状态。
- `tool_call_accepted` / `tool_result_committed`：保持一一配对；拒绝和取消使用合成结果。
- `approval_requested` / `approval_resolved`：审批是循环状态，不是 TUI 私有弹窗。
- `compaction_committed`：记录派生模型视图对应的事实事件范围。
- `turn_ended`：唯一 typed terminal outcome 与结束报告。

### 瞬态投影候选

- 文本/推理/tool-argument delta。
- spinner、状态行、进度百分比和临时提示。
- 可以在崩溃后丢失、也不参与 replay 的 UI 更新。

是否保留断流前的部分文本供用户查看仍待讨论；即使保留，也不能无标记地变成下一次模型输入中的 canonical assistant message。

## 候选硬不变量

1. 同一 session 同时最多一个 active turn；多 session 的并行和全局上限另行决定。
2. 每个 turn 都有且只有一个 `turn_ended`；记录主模型终止、评估器同意、取消、硬预算、卡死或错误等实际结束来源，而不是由最终显示文案反向猜测。
3. 每个已接受 tool call 都有真实或合成 tool result；失败、拒绝、取消和恢复同样适用。
4. 用户输入在首个模型请求前 durable；执行有副作用的工具前先持久化 operation ID。
5. 取消信号不依赖模型采样结束，可到达模型、审批、工具、重试和压缩状态。
6. 网络传输重试、整次模型重试、工具重试和压缩恢复分别计数，并受总 turn 预算约束。
7. 达到最大步骤、预算耗尽、防卡死或基础设施错误不能仅因循环停止就被投影成 completed；这不改变正常完成由主模型主导。
8. 压缩改变模型视图，不隐式改变原始事实的保留承诺。

这些都是推荐候选；项目负责人确认后才写入 `DECISIONS.md`。

## 决策一：完成与停止契约

### 方案一：模型主导（已确认）

主模型产生终止意图后结束；“由主模型主导”已经确认，“终止意图怎样无歧义表达”仍未确认。一次模型响应正常结束且没有工具调用也可能是在向用户提问、报告部分进展或拒绝，不能直接等于 completed；同样不能搜索自然语言中的“完成”“停止”等词语猜测。

当前领先候选是版本化、无副作用的 typed control：主模型明确返回 `finish(completed|partial)`、`ask-user` 或等价枚举。普通无工具回复只结束这次采样并把控制交给用户。若项目负责人不接受 typed control，就必须相应降低 typed outcome 承诺，而不能同时声称 Runtime 可以可靠区分完成与提问。

模型主导意味着 Runtime 不以“验证还不充分”等自己的任务判断否决正常终止意图。Runtime 仍要收口尚未配对的工具，并把取消、硬预算耗尽、传输/协议/存储错误按实际原因结束；这些不是主模型发出的正常终止意图。

### 方案二：Runtime 契约主导（未采用）

模型只能提出完成意图，Runtime 结合以下事实决定继续或结束：

- 是否还有未配对工具、待处理 steer 或必需审批。
- 当前任务是否要求验证，验证证据是否满足最低承诺。
- 是否命中预算、防卡死、取消、存储错误或不可恢复错误。
- stop hook 是否给出结构化的 continue/wait/stop 结果。

建议终止 reason 至少包含：

- `completed`：完成条件成立，并附改动与验证证据。
- `partial`：产生有效改动，但明确仍有未完成项或验证未完成。
- `waiting_user`：需要信息或决定；可以继续，但当前 turn 已收口。
- `cancelled`：用户或上层明确取消。
- `budget_exhausted`：步骤、时间、token、输出或费用达到硬上限。
- `stuck`：无进展检测达到停止阈值。
- `error`：不可恢复的模型、工具、协议、存储或基础设施错误，并带 error category。

优点是状态可测试、CLI 可给稳定退出码、恢复不会猜测；代价是必须先定义任务完成/验证最小证据。

### 方案三：独立评估器强制主导（未采用）

主模型声称完成后，再由规则或第二次模型调用判断目标是否满足。它适合以后更强的自主任务和评测，但增加成本、延迟、失败模式与旧机器负担；评估器本身也不能取代硬状态机。

### 已确认组合：主模型 + DoubleCheck 完成复核

配置提供全局 `DoubleCheck` 默认值，当前 XML 可由 `.cautious` 保存会话覆盖：

- 有效值关闭：AgentLoop 接受主模型的正常终止意图并结束。
- 有效值开启：主模型提出明确 typed finish 后，AgentLoop 单独发起一次请求，请完成复核器判断是否允许结束。
- 评估请求拥有独立的请求 ID、用量、错误和日志身份，不能伪装成主模型原请求的一部分。
- 评估器只判断是否终止，不因此取得工具执行权，也不能绕过权限系统产生副作用。

当前只确认总开关归属与触发时机。复核拒绝后怎样继续、使用当前模型还是专用模型、看到哪些上下文、输出什么结构、默认是否开启、失败/超时如何降级以及最多复核几次，都必须分别确认。

运行时必须把评估请求、触发它的主模型终止意图和 verdict 正确关联，避免把结果应用到另一轮生成。是否以及何时持久化、保存哪些评估内容、完整解释是否进入可见历史或主模型视图，由 `CTX-03`、`CTX-07` 后续确认；不能未经设计就把评估器文字伪装成主模型 assistant 消息。

## 决策二：忙时输入

### 方案一：全部 FIFO

Agent 忙时的新输入只排到下一个 turn。语义简单、恢复容易，但用户不能及时纠正正在走偏的任务。

### 已给出的四个显式动作方向

- `queue`：Enter；持久化为下一 turn 输入。只有当前 outcome=completed 时才候选自动启动，waiting-user/partial/cancel/error/unknown 时先暂停确认。
- `steer`：Ctrl+Enter；对当前 turn 纠偏。在工具尚未执行时使旧调用形成 synthetic skipped result；工具已开始则只能请求取消并等待真实结果后注入。
- `side`：Alt+Enter；一条只读直接回复，无工具，不进入主模型 view。当前推荐最多一个并发 side，读取创建时的 durable snapshot，拥有独立 ID/预算/取消。
- `cancel`：Esc；取消当前最内层活动。cooked/不支持按键的终端使用 `.cancel request|tool|side|turn|exit` 后备。

四者分别显示身份、状态和目标 turn，不能由系统按输入文字猜测。Shift+Enter 只负责能支持 raw editor 的多行输入；cooked 后备使用显式 begin/end。side 是否能在所有目标平台即时并发还需事件泵原型证明，但不能静默退化后仍称“直接”。

### 方案三：自动判断

系统根据文字内容或输入时机决定 queue/steer/cancel。交互看似轻便，但不可预测，也很难在恢复和审计中解释，不建议作为默认行为。

## 决策三：工具调度

### 方案一：全部串行（当前推荐）

最容易保证旧平台、审批和副作用顺序，符合“保持简单”。一个调用失败、取消或被 steer 后，其余未开始调用形成 synthetic skipped result。

### 方案二：基于 capability 与资源锁（以后重审）

工具声明只读性、副作用、并发安全、可取消性和资源互斥键；调度器只并行无冲突调用，并按模型原调用顺序回送结果。写入、审批、交互工具默认串行。

### 方案三：模型声明并发即并发

吞吐最高，但无法保护文件、进程和共享上下文，不适合作为 yaca 的安全默认值。

## 决策四：持久化边界

需要逐项确认以下 durable 屏障：

1. 用户输入提交后、发模型请求前。
2. tool call 被接受后、有副作用工具执行前。
3. 每个 tool result 产生后、下一次模型请求前。
4. 权限决定产生后、动作执行前。
5. compaction view 替换生效前。
6. `turn_ended` 对外报告前。

“放入内存队列”“write 返回”和“已 flush 到稳定存储”是三个不同强度；具体选择必须和 XP/CentOS 7 的文件能力契约一起讨论。

## 建议讨论顺序

1. 终止评估器拒绝后的继续方式和循环上限。
2. turn 边界和同 session 执行所有权。
3. busy input 的 queue、steer、side、cancel 语义及 side 并发原型。
4. 取消在每个状态中的收口结果。
5. durable 与 transient 事件分类、提交点和恢复。
6. 工具配对、调度、并发与 operation ID。
7. 分层重试预算、最大步骤和防卡死。
8. 验证责任、结束报告和计划模式。

## 当前待决策

Q-012 已确认主模型拥有正常完成权；D-027 又确认有效 `DoubleCheck` 开启时触发独立完成复核请求。当前最高优先项是 `AQ-251/AQ-252`：先定义主模型怎样区分 typed finish、ask-user、partial/refused 与普通 yield；随后才能完整决定复核拒绝、queue 自动启动和最终报告。
