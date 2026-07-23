# AgentLoop 开源实现源码核对

更新日期：2026-07-22

状态：参考资料，不是 yaca 决策

## 目的与方法

本文件只回答“成熟 Coding Agent 的实际代码已经处理了哪些循环问题”。它不按功能数量评判项目，也不把任一实现直接移植为 yaca 的结论。

核对方法：固定源码提交，阅读主循环、工具调度、取消/忙时输入、重试、防卡死、压缩和持久化相关实现；宣传页只用于确认项目身份，不作为机制证据。官方协议 README/生成 schema 可用来证明客户端可见的 wire lifecycle，但实际循环、持久化和工具顺序仍以同提交源码复核。

| 项目 | 固定提交 | 主要核对入口 |
| --- | --- | --- |
| xAI Grok Build | [`98c3b243`](https://github.com/xai-org/grok-build/tree/98c3b2438aa922fbbe6178a5c0a4c48f85edc8ce) | [`turn.rs`](https://github.com/xai-org/grok-build/blob/98c3b2438aa922fbbe6178a5c0a4c48f85edc8ce/crates/codegen/xai-grok-shell/src/session/acp_session_impl/turn.rs)、[`tool_calls.rs`](https://github.com/xai-org/grok-build/blob/98c3b2438aa922fbbe6178a5c0a4c48f85edc8ce/crates/codegen/xai-grok-shell/src/session/acp_session_impl/tool_calls.rs)、[`types.rs`](https://github.com/xai-org/grok-build/blob/98c3b2438aa922fbbe6178a5c0a4c48f85edc8ce/crates/codegen/xai-grok-shell/src/session/acp_session_impl/types.rs) |
| OpenAI Codex | [`2895d82b`](https://github.com/openai/codex/tree/2895d82b5e449407712439ba4f89954f3fa0c7e3) | [`turn.rs`](https://github.com/openai/codex/blob/2895d82b5e449407712439ba4f89954f3fa0c7e3/codex-rs/core/src/session/turn.rs)、[`parallel.rs`](https://github.com/openai/codex/blob/2895d82b5e449407712439ba4f89954f3fa0c7e3/codex-rs/core/src/tools/parallel.rs) |
| OpenClaude | [`0effa0f4`](https://github.com/Gitlawb/openclaude/tree/0effa0f42b6dbc6a4800e19f4b2d8d588269906b) | [`query.ts`](https://github.com/Gitlawb/openclaude/blob/0effa0f42b6dbc6a4800e19f4b2d8d588269906b/src/query.ts)、[`transitions.ts`](https://github.com/Gitlawb/openclaude/blob/0effa0f42b6dbc6a4800e19f4b2d8d588269906b/src/query/transitions.ts)、[`StreamingToolExecutor.ts`](https://github.com/Gitlawb/openclaude/blob/0effa0f42b6dbc6a4800e19f4b2d8d588269906b/src/services/tools/StreamingToolExecutor.ts) |
| CodeWhale | [`a34c43d9`](https://github.com/Hmbown/CodeWhale/tree/a34c43d9cc50e7938b05f2b8bc3fdaef055f448b) | [`turn_loop.rs`](https://github.com/Hmbown/CodeWhale/blob/a34c43d9cc50e7938b05f2b8bc3fdaef055f448b/crates/tui/src/core/engine/turn_loop.rs)、[`stuck_guard.rs`](https://github.com/Hmbown/CodeWhale/blob/a34c43d9cc50e7938b05f2b8bc3fdaef055f448b/crates/tui/src/core/engine/stuck_guard.rs)、[`termination.rs`](https://github.com/Hmbown/CodeWhale/blob/a34c43d9cc50e7938b05f2b8bc3fdaef055f448b/crates/tui/src/core/runtime_contract/termination.rs) |
| OpenCode | [`901c9e73`](https://github.com/anomalyco/opencode/tree/901c9e732921891e1fd71eb735ef5e78013f582f) | [`prompt.ts`](https://github.com/anomalyco/opencode/blob/901c9e732921891e1fd71eb735ef5e78013f582f/packages/opencode/src/session/prompt.ts)、[`processor.ts`](https://github.com/anomalyco/opencode/blob/901c9e732921891e1fd71eb735ef5e78013f582f/packages/opencode/src/session/processor.ts)、[`run-state.ts`](https://github.com/anomalyco/opencode/blob/901c9e732921891e1fd71eb735ef5e78013f582f/packages/opencode/src/session/run-state.ts) |

这里的 Grok 指 xAI 官方开源的 Grok Build，不是其他同名 `grok-cli` 仓库。

2026-07-19 另对 OpenAI Codex 当日 `main` 的 [`b8b61bc6`](https://github.com/openai/codex/tree/b8b61bc692517adcd18622df260f2ddd80635122) 做了定向复核，只检查 `expectedTurnId`、manual compaction 与 mixed text+tool 三个新边界。它不替换上表对完整循环的固定提交样本。

## 共同的概念循环

五个实现的代码组织不同，但核心都可还原为以下概念循环：

```text
接收并记录/排队输入
        |
        v
装配本次模型视图 --> 请求/流式接收模型
        ^                    |
        |                    v
  压缩/重试/steer <-- 解析文本、工具调用和结束原因
        ^                    |
        |                    v
        +---------- 审批并执行工具
                             |
                             v
                 继续采样或产生 typed outcome
```

关键不在 `while`，而在每条边上的契约：输入何时 durable、部分流是否算历史、取消如何补齐 tool result、工具副作用是否可重试、压缩是否改写事实源，以及什么状态才允许报告完成。

“记录/排队”不表示五个项目具有相同的 flush/fsync 保证；这正是 yaca 需要单独决定的持久化边界。

## 对照矩阵

| 维度 | Grok Build | Codex | OpenClaude | CodeWhale | OpenCode |
| --- | --- | --- | --- | --- | --- |
| 循环结束 | `Completed`、`Cancelled`、`MaxTurnsReached` 等 typed outcome | 无待处理工具/输入后结束，stop hook 可要求继续 | `Terminal` 与 `Continue` 是显式联合类型 | 有共享的 typed termination/receipt，但主循环仍有接线不一致 | 依据 finish、工具和任务状态退出 |
| 忙时输入 | 区分排队、mid-turn interjection、send-now 取消 | pending input 在后续采样前 drain | 有普通队列与 `now` 优先级取消；工具可声明中断行为 | turn loop 有 steer 通道与独立 cancel token | 同 session 单 runner；新 durable 消息由后续循环重新读取 |
| 工具调度 | 先准备/审批，再并发；按路径锁冲突资源 | `FuturesOrdered` 保持回送顺序；可并行工具走读锁，不安全工具走写锁 | fallback/批处理路径上限 10；活跃流式执行器无同等总上限，且可先回送后完成的安全调用 | 只读且声明安全的调用可并行；另有无需审批/交互的 detached background-start 例外 | 默认路径把 provider/tool dispatch 委托给 `streamText`；本仓此层未实现统一资源互斥键或总上限 |
| 重试与防卡死 | transport/recovery 分层且有预算；max-turn；doom-loop 有限恢复 | provider 提供 request/stream retry 上限；取消 token 贯穿 | API/recovery 有各自上限；tool-failure loop 与 compaction circuit breaker | 同工具参数、ABAB、相同无工具答案先警告再停止 | 相同工具输入三次触发 doom-loop 审批；retry schedule 在此层未见总次数上限 |
| 压缩 | 失败抑制与重新提交状态显式；原事件可支持 rewind | compacted replacement history 持久化；恢复取最新 replacement + 尾部 | 多级压缩；连续失败有 circuit breaker/cooldown | turn loop 内预请求压缩，另有工作集/checkpoint 机制 | 压缩消息形成模型视图，原持久消息仍在；可保留 tail |
| 持久化/恢复 | JSONL 对 torn tail 和损坏副本有处理；`FlushAndAck` 是排空 pending writes 的顺序屏障，不等于 fsync | rollout append + reconstruction 支持 resume/fork | append-only JSONL 与 `parentUuid` 链；有未完成对话修复逻辑 | session/checkpoint 能持久化，但部分热路径保存和续跑仍明确标注缺口 | 完整 message/part 进入数据库；流式 delta 与 durable part 分离；不应假定外部副作用可自动续跑 |

矩阵描述的是固定提交的可见实现，不代表项目作者对所有边界作了稳定 API 承诺。

## 分项目观察

### xAI Grok Build

- [`SamplerTurnOutcome`、`TurnOutcome`、`ToolLoop`](https://github.com/xai-org/grok-build/blob/98c3b2438aa922fbbe6178a5c0a4c48f85edc8ce/crates/codegen/xai-grok-shell/src/session/acp_session_impl/types.rs) 把采样恢复、回合终止和工具循环结果分开，避免用一个布尔值同时表达继续、取消和预算耗尽。
- [`process_conversation_turn`](https://github.com/xai-org/grok-build/blob/98c3b2438aa922fbbe6178a5c0a4c48f85edc8ce/crates/codegen/xai-grok-shell/src/session/acp_session_impl/turn.rs) 在完成前再次 drain interjection，并以 `max_turns` 形成硬边界；send-now 则走取消后发送的新路径。
- [`execute_tool_calls`](https://github.com/xai-org/grok-build/blob/98c3b2438aa922fbbe6178a5c0a4c48f85edc8ce/crates/codegen/xai-grok-shell/src/session/acp_session_impl/tool_calls.rs) 先准备调用，再用文件路径锁处理读写冲突并并发派发；提前拒绝或取消后，后续调用仍得到合成 tool result。
- [`storage/jsonl`](https://github.com/xai-org/grok-build/blob/98c3b2438aa922fbbe6178a5c0a4c48f85edc8ce/crates/codegen/xai-grok-shell/src/session/storage/jsonl/mod.rs) 会识别 torn tail，并在部分损坏恢复时保存 `.corrupt` 副本；[`PersistenceMsg::FlushAndAck`](https://github.com/xai-org/grok-build/blob/98c3b2438aa922fbbe6178a5c0a4c48f85edc8ce/crates/codegen/xai-grok-shell/src/session/persistence.rs) 让调用方等待 pending writes 完成。该消息本身调用 `flush_pending()`，不能在 yaca 设计中未经验证就等同于 OS `fsync`/稳定介质承诺。

对 yaca 的启示：必须给“进入队列、write 完成、flush/fsync 完成”分别命名；typed outcome 也应区分完成、取消和预算耗尽。

### OpenAI Codex

- [`run_turn`](https://github.com/openai/codex/blob/2895d82b5e449407712439ba4f89954f3fa0c7e3/codex-rs/core/src/session/turn.rs) 把一次用户 turn 实现为多次 sampling；工具需要 follow-up 或 pending input 存在时继续，stop hook 还可阻止过早结束。
- pending input 不直接篡改正在流式生成的请求，而是在下一次构建模型输入前 drain。这说明“忙时可输入”与“立即打断”是两个不同产品语义。
- [`ToolCallRuntime`](https://github.com/openai/codex/blob/2895d82b5e449407712439ba4f89954f3fa0c7e3/codex-rs/core/src/tools/parallel.rs) 对允许并行的调用取得共享锁，对不安全调用取得独占锁；`FuturesOrdered` 让完成时序不改变模型看到的结果顺序。
- [`replace_compacted_history`](https://github.com/openai/codex/blob/2895d82b5e449407712439ba4f89954f3fa0c7e3/codex-rs/core/src/session/mod.rs) 把 replacement history 作为 rollout item 持久化，[`rollout_reconstruction`](https://github.com/openai/codex/blob/2895d82b5e449407712439ba4f89954f3fa0c7e3/codex-rs/core/src/session/rollout_reconstruction.rs) 用它重建恢复/分支视图，而不是把屏幕增量当事实源。

对 yaca 的启示：并发工具必须同时回答“谁能并发”和“结果按什么顺序回送”；压缩结果应是可重建模型视图，不应悄悄抹掉原始事实。

#### 2026-07-19 当前 Codex 定向复核

- [`turn/steer`](https://github.com/openai/codex/blob/b8b61bc692517adcd18622df260f2ddd80635122/codex-rs/app-server/README.md#L1064-L1074) 强制客户端携带 `expectedTurnId`。没有 active turn、ID 不匹配，或 active turn 是 review/manual-compaction 等不接受 same-turn steer 的 kind 时，服务端返回 invalid request，不把迟到输入投给更新的 turn。这验证了 yaca 需要 expected Context generation/turn observation 的 stale-target 技术绑定；“是否允许 stale command 重定向”不是合理的新产品开关。
- [`thread/compact/start`](https://github.com/openai/codex/blob/b8b61bc692517adcd18622df260f2ddd80635122/codex-rs/app-server/README.md#example-trigger-thread-compaction) 立即返回接受结果，再用标准 `turn/*` 和 `item/*` 通知流报告一个 `contextCompaction` item；运行期间 thread 被视为正处于 turn，且同一协议明确 manual-compaction turn 拒绝 `turn/steer`。这不要求 yaca 复制 Codex 的协议，却暴露了 yaca 已出现 `.compact` 承诺而没有 admission、turn kind、cancel、budget、publication 和 recovery owner 的真缺口；三项中只有它需要新增 AL06-39 负责人问题。
- 当模型在同一 response 中产生文本和 tool call 时，[`turn.rs`](https://github.com/openai/codex/blob/b8b61bc692517adcd18622df260f2ddd80635122/codex-rs/core/src/session/turn.rs#L2055-L2143) 对每个 `OutputItemDone` 分别完成消息或建立 tool future，累积 `needs_follow_up`；[`stream_events_utils.rs`](https://github.com/openai/codex/blob/b8b61bc692517adcd18622df260f2ddd80635122/codex-rs/core/src/stream_events_utils.rs#L319-L412) 分别持久非工具 item 与 tool call；响应流收口后，[`turn.rs`](https://github.com/openai/codex/blob/b8b61bc692517adcd18622df260f2ddd80635122/codex-rs/core/src/session/turn.rs#L2478-L2490) 再 drain ordered in-flight tool results。这证明 mixed response 需要 ordered-item/pairing 机制，但 yaca 已由 AL06-37 唯一决定展示、canonical promotion 与下一 model view；它只补协议 fixture 和工具配对证明，不新增 owner 问题。

定向复核的投影结论因而是：`expectedTurnId` 类机制归不可关闭的命令身份与 stale-conflict 证明；mixed text+tool 继续由 AL06-37 拥有产品轴；只有 manual compaction 生命周期提升为 AL06-39。

### OpenClaude

- [`queryLoop`](https://github.com/Gitlawb/openclaude/blob/0effa0f42b6dbc6a4800e19f4b2d8d588269906b/src/query.ts) 使用 [`Terminal`/`Continue`](https://github.com/Gitlawb/openclaude/blob/0effa0f42b6dbc6a4800e19f4b2d8d588269906b/src/query/transitions.ts) 表达完成、最大轮数、tool-failure loop、压缩恢复等不同去向。
- [`StreamingToolExecutor`](https://github.com/Gitlawb/openclaude/blob/0effa0f42b6dbc6a4800e19f4b2d8d588269906b/src/services/tools/StreamingToolExecutor.ts) 可在工具块流完时开始执行，并为取消、兄弟调用失败和 streaming fallback 生成合成结果。该活跃流式路径没有与批处理相同的总并发 cap，而且允许越过仍在执行的并发安全调用，先回送后面已经完成的安全结果；fallback/旧式 [`toolOrchestration.ts`](https://github.com/Gitlawb/openclaude/blob/0effa0f42b6dbc6a4800e19f4b2d8d588269906b/src/services/tools/toolOrchestration.ts) 才是把安全工具分批并默认限制为 10。
- headless 输入队列把普通消息与 `now` 优先级分开；`now` 会 abort 当前操作。工具自身还可声明收到新输入时是 `cancel` 还是 `block`。
- 自动压缩连续失败后进入 circuit breaker/cooldown；会话采用 JSONL 记录和 `parentUuid` 链，恢复代码显式处理未完成 prompt/tool 状态。

对 yaca 的启示：任何工具调用都必须有真实或合成结果；“普通排队”和“send-now”必须是用户可辨认的不同操作。

### CodeWhale

- [`turn_loop.rs`](https://github.com/Hmbown/CodeWhale/blob/a34c43d9cc50e7938b05f2b8bc3fdaef055f448b/crates/tui/src/core/engine/turn_loop.rs) 集中处理 steer、取消、压缩、模型请求和工具步骤；[`dispatch.rs`](https://github.com/Hmbown/CodeWhale/blob/a34c43d9cc50e7938b05f2b8bc3fdaef055f448b/crates/tui/src/core/engine/dispatch.rs) 让只读且声明安全的工具进入并行批次，也允许无需审批/交互的 detached background-start 作为单独例外，完成结果按原 plan index 回填。
- [`StuckGuard`](https://github.com/Hmbown/CodeWhale/blob/a34c43d9cc50e7938b05f2b8bc3fdaef055f448b/crates/tui/src/core/engine/stuck_guard.rs) 同时检测相同动作、相同动作/错误、ABAB 和重复无工具答案，并采用“先警告，再允许改变策略，仍重复才停止”。
- [`RunTerminationReason`](https://github.com/Hmbown/CodeWhale/blob/a34c43d9cc50e7938b05f2b8bc3fdaef055f448b/crates/tui/src/core/runtime_contract/termination.rs) 已定义 resolved、stuck、budget exhausted、approval required 等机器可读结果和验证 receipt。
- 但当前主循环到达最大步骤时 `break`，函数尾部仍返回 `Completed`；typed termination 也尚未成为所有运行出口的唯一事实源。源码中的 checkpoint 保存还存在 fire-and-forget 与“live resume 未自动化”的明确说明。

对 yaca 的启示：定义了枚举不等于状态机已经正确；每个硬上限和错误出口都必须有端到端验收，不能在投影时被误报为完成。

### OpenCode

- [`runLoop`](https://github.com/anomalyco/opencode/blob/901c9e732921891e1fd71eb735ef5e78013f582f/packages/opencode/src/session/prompt.ts) 每一步重新读取当前持久消息，并由 [`SessionRunState`](https://github.com/anomalyco/opencode/blob/901c9e732921891e1fd71eb735ef5e78013f582f/packages/opencode/src/session/run-state.ts) 保证同一 session 复用一个 runner。
- [`processor.ts`](https://github.com/anomalyco/opencode/blob/901c9e732921891e1fd71eb735ef5e78013f582f/packages/opencode/src/session/processor.ts) 把完整 message/part 更新到存储，流式 delta 则作为事件投影；当前 assistant message 最近三个 part 使用相同工具与输入时触发 `doom_loop` 权限询问，这不是跨 turn 的通用检测。默认模型路径在 [`llm.ts`](https://github.com/anomalyco/opencode/blob/901c9e732921891e1fd71eb735ef5e78013f582f/packages/opencode/src/session/llm.ts) 把 provider/tool dispatch 委托给 `streamText`，本仓这一层没有定义 yaca 所需的统一资源互斥键或全局并发上限。
- [`retry.ts`](https://github.com/anomalyco/opencode/blob/901c9e732921891e1fd71eb735ef5e78013f582f/packages/opencode/src/session/retry.ts) 定义退避 schedule，但在该层没有总 retry 次数；`maxSteps` 到达时向模型注入最后一步提示，而不是由 runtime 产生硬终止。
- [`compaction.ts`](https://github.com/anomalyco/opencode/blob/901c9e732921891e1fd71eb735ef5e78013f582f/packages/opencode/src/session/compaction.ts) 和消息过滤器构建压缩后的模型视图，持久的原消息仍可用于其他投影。

对 yaca 的启示：软提示不能代替硬预算；重试、最大步骤、doom-loop 和总墙钟必须由 runtime 收口，不能只期待模型自律。

## 对 yaca 的候选不变量

以下只是根据五个实现归纳出的候选项，需由项目负责人确认：

1. TUI、CLI 和 headless 共用一个 AgentLoop；界面只提交命令并消费事件。
2. turn 只能以 typed terminal outcome 结束，至少区分 completed、waiting-user、cancelled、budget-exhausted、stuck、partial 和 error。
3. 已接受的每个 tool call 都必须有真实或合成 tool result；取消和权限拒绝不是例外。
4. provider 流式 delta 是瞬态 UI 数据；只有完整、校验过的领域事件进入规范历史。
5. transport retry、整次模型重试、压缩恢复和工具重试使用不同预算；另有不可绕过的总次数/时间上限。
6. 工具并发由 capability + 副作用 + 资源互斥键共同决定；模型看到的结果顺序必须确定。
7. 用户输入至少区分 FIFO 下一轮、下一采样 steer、立即取消后发送三种语义，不用一个模糊的“忙时输入”开关代替。
8. 压缩只生成模型视图；原始 durable 事实是否长期保留由上下文生命周期决定，不能被压缩实现顺带决定。
9. 用户输入在首个模型请求前 durable；有外部副作用的工具在执行前记录 operation ID，执行后结果落盘失败必须可识别为“结果未知”。
10. 恢复时不自动重放结果未知的副作用；遗留 running tool、pending approval、retry 和 compaction marker 必须逐类收口。

这些不变量分别映射到 `DESIGN-CHECKLIST.md` 的 `LOOP-*`、`TOOL-*`、`CTX-*`、`COMP-*` 和 `SAFE-*`，确认后才进入 yaca 的正式设计。
