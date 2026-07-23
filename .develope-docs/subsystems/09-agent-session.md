# 09 AgentLoop 与会话状态机

状态：核心循环与交互语义已确认；数值上限、事件编码和旧平台取消待技术证明

## 职责

- 接受已规范化的用户输入和 Runtime 发布的 immutable `ConfigGeneration`，创建/继续 turn。
- 取得 Context 模型视图，通过 06 号统一接口采样，并解释 typed control 与 tool call。
- 把每个工具请求交给 Permission、DoubleCheck、人工审批和串行工具调度器。
- 处理 queue、steer、side、取消、retry、压缩、验证、预算和防卡死。
- 在每个 durable 屏障发布 canonical 事件，并产生唯一 typed turn outcome。

## 边界

- 不绘制终端；TUI、CLI、快捷键与测试 adapter 都只投影同一 semantic action/event。
- 不直接解析 INI、XML、curl/SSE/provider JSON 或 raw shell command。
- 不从自然语言推断“已完成”、权限或工具结果；只消费 typed control、Permission decision 和真实执行状态。
- 不提供独立 plan state、分支 Context、Web/remote controller、后台 job 或多 Agent。

## 已确认架构：单线程、单事件泵

一个 yaca 进程恰好拥有一个 active Context、一个 AgentLoop 和一个领域状态源。核心使用单 OS 线程、单有界事件泵；Lua coroutine 只能作为同一线程中的协作调度工具，不能复制或在后台拥有另一份可变会话状态。

```text
TUI / CLI semantic actions
            |
            v
      bounded event pump
            |
            v
         AgentLoop ----> serialized Permission/tool/storage actions
            |
            +----------> provider/process events returned to same pump
            |
            +----------> durable Context events + transient TUI projection
```

同一 Context 同时最多一个 active main turn。最多一个 `side` logical request 可以与 main 处于 in-flight 状态，但其网络事件仍由同一事件泵有界交错，不创建线程或第二领域状态；同一 Model 的实际并发/间隔由统一 scheduler 收口。工具一律串行。自动命名、review、compaction、retry 和 close 也是 event-pump activity，不是后台线程。

显式切换 Context 前必须先收口当前 main/side、queue/draft、writer 和所有未知副作用；不在一个进程中保留多个只读或可写 active Context。

## turn admission 与冻结

每个顶层 `main`/`side` admission 前，22 号 Runtime 完整观察主 INI。只有整份 parse/schema/cross-field/secret/reference 校验成功，才原子发布新 `ConfigGeneration`；半写、删除、不可读或无效配置阻止新 turn，不能退回旧 generation 偷跑。

AgentLoop 在发出任何 Model request 或副作用前冻结：

- 当前完整 Model 与 provider/retry/streaming 配置；
- 当前 Permission 五项矩阵与唯一 workspace root；
- `DoubleCheck`、finish goal 和 action-review 配置；
- Global、Model、Permission、Context 四层 PromptBundle；
- tool/control schema、hard caps 与当前模型视图 manifest。

同一 turn 的 retry、tool loop、action/termination review、compaction 和 context result 全部沿用这份快照。活动期间 INI 或 ContextPrompt 变化最早从下一顶层 turn 生效。Context XML 保存足以完整接盘的非秘密 generation、Model/Permission/Prompt/tool-schema/root snapshot；Key/private source digest 不进入 XML。

## 核心状态

```text
Idle
  -> Preparing
  -> RequestingModel <-> Streaming
       -> AwaitingApproval -> ExecutingTool -> RequestingModel
       -> typed ask-user / model-yield -> WaitingUser
       -> typed refuse -> Finalizing(refused)
       -> typed finish
            -> DoubleCheck off -> Finalizing(completed)
            -> DoubleCheck on  -> EvaluatingTermination
                 -> pass -> Finalizing(completed)
                 -> explicit gap -> RequestingModel (same turn)
                 -> uncertain/error/cap -> WaitingUser
  -> Finalizing
  -> one typed terminal/waiting outcome
```

任意活动状态都能接收 out-of-band cancel。`WaitingUser` 是可恢复业务状态，`cancelled` 是已结束 outcome；不能用一个模糊 `paused` 代替。

## typed finish、ask-user 与 refuse

正常完成由主模型主导，但只能通过 06 号版本化 typed control 表达：

- `finish`：提出任务完成并进入 finish review/finalize 路线；
- `ask-user`：保存明确问题并进入 waiting-user，用户回答继续同一 turn；
- `refuse`：保存拒绝理由并以 refused 如实收口。

一次完整普通回复若没有 control，保存为 `model-yield` 并进入 waiting-user；provider stop、无工具或出现“完成”等文字都不隐式等于 completed。一个 Context 同时最多一个可由普通 Enter 回答的 pending question，其他输入必须保持 queue/steer 的显式意图。

Runtime 只强制工具配对、durability、Permission、硬上限和真实副作用状态，不以自己的任务判断替代主模型的正常完成权。取消、budget exhausted、stuck、存储/协议错误和 outcome=unknown 仍按真实 Runtime 原因结束，不能投影成 completed。

## DoubleCheck

`DoubleCheck=false` 时不发 action 或 finish review。`DoubleCheck=true` 时：

1. 每个 typed `finish` 必须经过独立 `termination-review`，finish review 不能由另一个 target/toggle 关闭；
2. 高风险动作是否经过 `action-review` 是独立可配置项；普通低风险动作不因此固定增加请求；
3. 两类 reviewer 默认使用当前 turn Model，也可分别选择 Model，跨 endpoint 首次使用前取得同意；
4. reviewer 没有工具，使用独立 request/purpose/usage/hard cap，并严格关联被审 finish 或 operation；
5. action reviewer 只能维持或收紧 Permission；不能授予 Runtime 已拒绝的动作；
6. finish reviewer 指出明确缺口时，把 typed 缺口交回主模型并在同一 turn 继续；uncertain、无效输出、失败、超时或达到 review 上限时进入 waiting-user。

面向用户的简洁 English slogan 固定为 `Spend more time and tokens for greater safety.`；它只解释取舍，不替代有效开关、请求/Token 预算或真实审阅状态。

`DoubleCheckGoal` 是有界的任务目标/验收标准，INI 可给默认，Context 可 override/reset；为空时从当前 task facts 构造 finish-review data。它只约束完成复核，不成为 plan state、action approval 或 Permission。

## busy input

固定四条 lane 均有快捷键与点命令等价入口：

- `queue`：Enter 或 `.queue`；只在上一 turn `completed` 且没有 pending/unknown 时自动启动。支持 list/delete/edit/move/clear，排序/编辑必须作用于稳定 queue item identity。
- `steer`：Ctrl+Enter 或 `.immediate`；取消可取消的 Model/review 与未开始工具，再把纠正注入同一 turn。已开始工具只能先请求取消并等待真实/unknown result。
- `side`：Alt+Enter 或 `.side`；最多一个，无工具、只读、基于创建时 durable snapshot 的一次直接回复。side 已活动时拒绝新 side 并保留 draft。
- `cancel`：Esc 或 `.cancel`；按当前焦点取消最内层 activity，而不是凭输入文字猜目标。

Shift+Enter 与 `.multiline` 提供多行输入。旧终端无法区分组合键时仍能完整使用点命令；self-test 检查快捷键能力并提示后备，不把“不能识别组合键”当作 Agent 核心失败。

## 工具、Permission 与 durable 屏障

Model 提出的 `list/read/search/write/patch/rename/delete/exec` 一律按响应原顺序串行处理。每个调用依次经过：schema/目标校验、deterministic Permission、条件 action review、条件人工确认、operation intent durable、执行、真实或 synthetic result durable。任一步失败、取消或 steer 后，未开始调用形成有原因的 synthetic skipped result，保证每个 accepted call 恰好配对一个 result。

强制提交点至少包括：

1. 用户输入接受后、首个 Model request 前；
2. canonical assistant/tool/control message 接受后、解释执行前；
3. Permission/approval 与 operation intent 产生后、副作用前；
4. 每个真实或 synthetic tool result 产生后、下一 Model request 前；
5. compaction view 发布前；
6. review verdict 生效前；
7. `turn_ended` 或 waiting outcome 对外报告前。

存储提交失败时停止后续请求/副作用，并报告最后 durable 水位；“已进入内存 queue”不等于已保存。

## hard caps、retry、stuck 与验证

- request、turn 和进程层都有不可关闭 hard caps，至少覆盖步骤、墙钟、Model request、tool call、review、retry、token/bytes 与输出。用户配置只能在发行安全范围内收紧。
- Context 保存累计 usage 审计，但不设置会让长历史永久无法继续的 lifetime hard ledger，也不默认计算货币金额。
- transport attempt、逻辑 Model retry、tool retry、review 和 compaction 分别计数，同时受 turn/process 上限。
- 已收到任何 canonical response event 后不自动重放整个 Model request；可能已经发生但不可证明的副作用标记 unknown。
- 重复调用、ABAB、无状态变化或压缩无收益达到阈值时先产生一次 durable warning，并只允许一次受剩余预算约束的策略改变；仍无进展则 `stuck`。
- 存在明显、安全且当前 Permission 允许的验证命令时，模型默认应运行验证；不能运行或结果不完整时，在 finish data 和最终报告中如实列明，不能伪造通过。

## durable 与 transient events

canonical durable 事件至少覆盖：turn start/end、用户输入、Model request/message、typed control、tool call/result、Permission/approval、operation、review、compaction、Model/Prompt/Permission transition、cancel 和 unknown side effect。每个 turn 恰好一个 typed 收口结果。

text/reasoning/tool-argument delta、spinner 和临时进度是 transient projection。断流残片可以作为明确 `incomplete` 诊断事实保存，但绝不能无标记地成为下一请求中的 canonical assistant message。

## close 与恢复

退出进入同一有界 close 状态机：停止 admission、取消 Model/side/review/compaction/自动命名、丢弃未提交 draft 和未开始 queue、拒绝 pending approval、尽力终止工具，随后把已证明结果收口为 completed/interrupted/unknown 并恢复终端。它不等待后台命名，也不跳过必要 XML 提交。

恢复只从 canonical durable events 重建。没有 result 的 accepted operation 必须显示 unknown 并要求用户决定，绝不自动重放工具或把锁龄当作安全依据。

## 仍需技术证明

冻结状态/event 枚举、每层 hard-cap 数值、single-event-pump adapter 接口、Model/side 调度、旧平台取消/进程树时序和 fault-injection fixture。产品路线不再比较多 Context 并发、多线程领域状态、自然语言完成判断、并行工具或可关闭 finish review。
