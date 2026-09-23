# MiniMax Code、ZCode、DeepSeek Harness 源码对照

阅读日期：2026-09-22。目的：使 yaca 的通用 AgentLoop 简洁、鲁棒，改善任务闭环与故障处理。
通过官方仓库确认项目身份后，浅克隆源码并读取下列固定提交的实现与部分测试。
未运行这三个项目的完整测试，未引入其代码或运行时依赖。

## 阅读范围

| 项目 | 本次读取的 HEAD | 范围 |
| --- | --- | --- |
| [MiniMax-AI/minimax-code](https://github.com/MiniMax-AI/minimax-code/tree/e7d809d5899db9f192ec48b9ed1f555558dfb6bf) | `e7d809d5899db9f192ec48b9ed1f555558dfb6bf` | vendored pi loop、上层 turn runner、工具输出预算、context manager、loop tests |
| [zai-org/ZCode](https://github.com/zai-org/ZCode/tree/872ad960de7ec172591f7e1952f7849229f94521) | `872ad960de7ec172591f7e1952f7849229f94521` | `apps/zcode-cli` 的真实 runtime turn loop、model stream runner/retry、取消快照 |
| [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness/tree/ddefc45fbc7f8e46dd73185e68295696d1297887) | `ddefc45fbc7f8e46dd73185e68295696d1297887` | agent-loop、assistant-stream、tool scheduler、llm-retry、cancel/request-freeze tests |

这里的 ZCode 是 `zai-org/ZCode`，不是同名的其他 CLI。
结论只针对这些源码快照；上游默认分支后续变化需重新核对。
此前的[五项目研究](agent-loop-reference-study.md)继续作为历史资料。

## MiniMax Code：借鉴清晰的循环边界和结果预算

实际循环在 vendored pi-mono 的
[`agent-loop.ts`](https://github.com/MiniMax-AI/minimax-code/blob/e7d809d5899db9f192ec48b9ed1f555558dfb6bf/third_party/pi-mono/packages/agent/src/agent-loop.ts)。
`runLoop` 区分本轮 tool/steering 与停止后的 follow-up；请求前执行 context transform，
再通过 `convertToLlm` 转成 provider 消息。它提供 `prepareNextTurn`、stop 和 tool hooks，
因此不能把“循环文件可读”理解成“没有外围语义”。

`executeToolCallsSequential` 在完成/取消一个工具后，为剩余未执行调用生成明确的错误结果。
对应的
[`agent-loop.test.ts`](https://github.com/MiniMax-AI/minimax-code/blob/e7d809d5899db9f192ec48b9ed1f555558dfb6bf/third_party/pi-mono/packages/agent/test/agent-loop.test.ts)
检查串行/并发选择、源顺序结果、工具批结束后输入注入以及停止后不执行后续工具。
**yaca 采用：**继续串行，把取消前已启动与尚未启动调用分别收尾，保持 call/result 配对；
不为使用这条经验引入并发工具池和 hook runtime。

[`tool-output-budget.ts`](https://github.com/MiniMax-AI/minimax-code/blob/e7d809d5899db9f192ec48b9ed1f555558dfb6bf/packages/agent-extension/src/tool-output-budget.ts)
按字节处理超大文本结果；只有当前 turn 存在 `read` 工具才用可恢复 artifact receipt 替换。
artifact 写入失败时退回有截断声明的头尾预览，观察回调失败不覆盖主结果。
**yaca 采用：**结果必须有界、说明范围、给出下一次精确读取方式。
先沿用范围 read/search 和有界 exec 输出，不照搬独立 artifact 持久化体系；
尤其不先完整读入数 GB 日志再做截断。

[`provider-budget.ts`](https://github.com/MiniMax-AI/minimax-code/blob/e7d809d5899db9f192ec48b9ed1f555558dfb6bf/packages/agent-modules/context-manager/src/provider-budget.ts)
把输入容量与输出预留一起计算；
[`token-estimator.ts`](https://github.com/MiniMax-AI/minimax-code/blob/e7d809d5899db9f192ec48b9ed1f555558dfb6bf/packages/agent-modules/context-manager/src/token-estimator.ts)
尝试用成功响应的 usage 校准前缀，只估计尾部，并在有限范围内使用 tokenizer。
**yaca 采用：**先诊断短中文任务过早压缩的原因，再校准估算；usage 只能对应同一模型、
同一消息前缀与 schema，不能沿用到已变化的请求。暂不增加 tokenizer 依赖。

## ZCode：借鉴重试边界、取消快照和配置接纳时机

顺着生产调用阅读
[`turn.ts`](https://github.com/zai-org/ZCode/blob/872ad960de7ec172591f7e1952f7849229f94521/apps/zcode-cli/packages/core/src/runtime/methods/turn.ts)
和
[`turn-loop.ts`](https://github.com/zai-org/ZCode/blob/872ad960de7ec172591f7e1952f7849229f94521/apps/zcode-cli/packages/core/src/runtime/methods/turn-loop.ts)，
而不是只看 `TurnMachine` 的枚举。`executeTurnCommand` 在第一个异步等待前固定
模型选择/输出样式；循环边界处理输入、压缩和重复填满上下文的保护。
**yaca 采用：**已有 immutable ConfigGeneration 应保留；压缩失败、快速重新填满、
重复工具无进展需要各自可观测且共享总预算。不要导入 workflow、MCP、todo 等分支。

[`stream-retry-boundary.ts`](https://github.com/zai-org/ZCode/blob/872ad960de7ec172591f7e1952f7849229f94521/apps/zcode-cli/packages/adapters/src/model/stream-retry-boundary.ts)
和实际使用它的
[`runner-stream.ts`](https://github.com/zai-org/ZCode/blob/872ad960de7ec172591f7e1952f7849229f94521/apps/zcode-cli/packages/adapters/src/model/runner-stream.ts)
把可暂存的前奏事件与已交付边界分开：空文本/reasoning delta 和尚未完成的工具输入
可以处在前奏里，越过提交边界后不再走透明 adapter retry；compact 的边界更严格。
**yaca 采用：**把首事件前失败、文本前缀后失败、半截工具参数、完整工具调用后的断线
做成不同用例，检查其现有 canonical-event 门禁。不能只用“HTTP 失败”统一重试。

[`runner-retry.ts`](https://github.com/zai-org/ZCode/blob/872ad960de7ec172591f7e1952f7849229f94521/apps/zcode-cli/packages/adapters/src/model/runner-retry.ts)
保留错误来源，处理 Retry-After、指数退避/jitter 和可取消等待。
但
[`retry-policy.ts`](https://github.com/zai-org/ZCode/blob/872ad960de7ec172591f7e1952f7849229f94521/apps/zcode-cli/packages/adapters/src/model/retry-policy.ts)
默认最多 10 次重试，且
[`retry-budget.ts`](https://github.com/zai-org/ZCode/blob/872ad960de7ec172591f7e1952f7849229f94521/apps/zcode-cli/packages/adapters/src/model/retry-budget.ts)
另外支持 unbounded。
**yaca 选择：**保留分层归因与可取消退避，继续由自己的有限次数和总截止时间约束等待；
不采用“永远再试一次”的策略。错误应尽快变成用户能处理的信息。

[`cancelled-stream-persistence.ts`](https://github.com/zai-org/ZCode/blob/872ad960de7ec172591f7e1952f7849229f94521/apps/zcode-cli/packages/core/src/runtime/methods/cancelled-stream-persistence.ts)
专门处理取消时已收到的文本/reasoning，工具由终态路径处理。
**yaca 采用：**用户已见前缀与工具事实分开；如果保留部分输出，必须标记 interrupted，
不能把半条 tool 参数提升为可以执行的命令。是否扩展当前 XML 记录先核对 schema。

## DeepSeek Harness：借鉴事实先行与取消后收拢

[`agent.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/core/agent-loop/src/agent.ts)
把 turn/step、输入接纳、request preparation、工具调用与 terminal reason 放在一个 driver 中。
同一 step 的 retry 仅第一次追加已接受 user messages；请求从 session 事实构建并冻结。
max-tokens 是保留的终态原因，之后正常的一步不能把它掩盖。
[`request-freeze.spec.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/core/agent-loop/tests/request-freeze.spec.ts)
还检查从恢复图采用的消息对象在请求边界冻结。
**yaca 采用：**保持 Session/Runtime 单一事实源，不在重试时重复追加用户输入，
完成、截断、取消、预算不足严格区分。

[`assistant-stream.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/core/agent-loop/src/assistant-stream.ts)
的 `settle` 先 append 对应事实再发 committed terminal frame；append 失败则发 abandoned。
**yaca 采用：**UI 终态晚于可核实的 Context publication receipt，显示成功不能跑在保存之前。
上游 `session.append` 的实际持久性依赖其组合/存储实现；不能用其方法名证明 yaca 在
FAT32 或拔盘场景的落盘保证。

[`tool-calls.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/core/agent-loop/src/tool-calls.ts)
区分 exclusive barrier 与 bounded pool，取消时停止补充任务、等待已启动工具，
再为未启动调用记结果；调度内部失败则不虚构已经得到工具结果。
[`cancel.spec.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/core/agent-loop/tests/cancel.spec.ts)
覆盖 idle 取消不误伤下次输入、队列处理和等待空闲；
[`tool-calls.spec.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/core/agent-loop/tests/tool-calls.spec.ts)
检查调度错误后停止启动并收拢已开始工作。
**yaca 采用：**照此检查串行场景的取消落点和真实 Windows 进程树；没有必要引入并发池。

[`llm-retry/src/index.ts`](https://github.com/deepseek-ai/deepseek-harness/blob/ddefc45fbc7f8e46dd73185e68295696d1297887/packages/llm/llm-retry/src/index.ts)
将 scheduled retry 记录在等待前，等待可取消，另有 normal/always 策略。
**yaca 选择：**状态可解释、等待可取消，重试策略继续放在已有网络/模型接缝内。
不引入 Cordis 插件内核、可卸载服务图或无界 always 重试。

## 对 yaca 的具体落点

| 检查点 | 已有 yaca 接缝 | 下一步需要的证据 |
| --- | --- | --- |
| 请求与工具严格配对 | `runtime.lua`、`session.lua`、fault/agentloop 与 operation_outcome tests | 每个取消落点与 real-process 退出，不只模拟事件 |
| 流式重试 | `network.lua:new_retry_controller`、`model.lua`、fault/network_retry tests | 首 canonical event 前后断线、代理缓冲与畸形 SSE |
| 配置冻结 | `config.lua`、main/Session admission、config_generation tests | 模型/代理/Key 编辑不会跨越当前 turn |
| 输出与压缩预算 | `tools.lua`、`process.lua`、`compact.lua` | 大日志、中文、小模型窗口、慢 USB 上的内存/写入成本 |
| 发布后呈现终态 | Context publication receipt、Agent activity driver | 工具成功后保存失败必须 unknown/fail-stop，不能显示 completed |
| 取消与下一任务 | terminal/process AsyncPort、Runtime cancel | 旧 Windows 子进程树、阻塞 DNS、解释器无限循环、取消后再发输入 |

这些是对 yaca 已有设计的审计与有选择的改进建议。核心简洁的衡量标准是：
一个状态有一个 owner、一种事实有一种发布路径、异常出口可解释且可验收。
不以照搬上游包结构或减少必要的副作用保护来衡量简洁。
