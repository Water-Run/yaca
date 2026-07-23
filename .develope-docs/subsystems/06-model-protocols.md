# 06 模型协议适配

状态：候选

## 职责

把内部统一的消息、工具和生成请求转换为已确认的 provider wire profile，并把响应转换回统一事件与结果。OpenAI-compatible 是当前领先的 v0.1 候选；Anthropic 原生协议尚未得到首版承诺，不能因为 README 出现品牌名称就自动进入范围。

## 边界

- HTTP 由 03 号子系统处理。
- JSON 由 04 号子系统处理。
- 模型选择和凭据由 05 号子系统提供。
- Agent 循环只面向内部统一接口，不读取厂商响应细节。

## 设计要求

- 区分传输失败、HTTP 错误、协议错误、模型拒绝和内容截断。
- 工具调用 ID、并行工具调用和结束原因必须规范化。
- 自定义 endpoint 不能绕过秘密保护和超时限制。

## 必须形成的 canonical 协议

最终实现不直接把 provider JSON table 传进 AgentLoop。至少需要：

```text
NormalizedRequest
  local request ID, purpose, Model snapshot,
  public effective config-generation digest / non-secret generation reference
  model-view manifest, Prompt/tool-schema snapshot
  streaming/output limits, bounded protocol options

ProviderEvent
  response-start, text-delta, reasoning-summary-delta
  tool-call-start, tool-arguments-delta, tool-call-complete
  usage-update, response-finish, transport/protocol-error

NormalizedResponse
  ordered content blocks, validated tool calls
  usage, finish reason, refusal/filter/incomplete evidence
```

工具参数只有在完整 response 合法结束、所有 call ID/JSON/schema/数量/大小通过验证且 canonical assistant response durable 后，才交给 AgentLoop 接受。断流前看似闭合的 JSON 不得提前执行。

本地 request/message/tool-call/operation ID 由 yaca 在 XML 内分配；provider 原始 ID 作为证据保存，不能因缺失或重复而成为本地关系身份。

## 结束信号不是 provider finish reason

provider 的正常 `stop` 只表示一次生成结束，不能区分“任务完成”“向用户提问”“部分进展”或“拒绝”。主模型需要版本化、无副作用的 typed control/envelope 表达 `finish`、`ask-user` 等任务意图；普通无工具回复只向用户 yield。Runtime 不搜索自然语言猜结局，`DoubleCheck` 只在明确 finish 后触发。精确 control 形式仍待 `AQ-251`/`AQ-252` 确认。

六个核心 request purpose 是 `main`、`side`、`action-review`、`termination-review`、`compaction` 和 `self-test`；后者必须再带 `phase=capability|semantic`，使 Stage 2 的真实 synthetic probe 与 Stage 3 advisory 各有 request/usage/manifest，Stage 1 不发 Model 请求。另有条件性的 `context-name`：只有 `AutoNameEveryMainTurns>0`、已经 durable 收口的 main-turn 水位达到下一周期，且 Context XML 中 `AutoRenameDisabled` 缺失/`false` 时才能 admission；它不能复用 main/side/compaction 身份。把 marker 从 `true` 取消后，以取消时的 durable 水位建立新 baseline，不立即请求，也不追赶 marker 生效期间错过的周期。每类由 Runtime 强制不同的 tool schema、model view、预算与输出 schema；不能仅在 Prompt 中写“请勿调用工具”。

每个顶层 `main`/`side` turn 在 admission 时绑定一个已完整验证、不可变的 config generation；该 turn 派生的 provider retry、action/termination review、compaction 和其他 child request 都沿用同一 generation、Model/Permission/Prompt/tool-schema snapshot。INI 在活动 turn 中变化不能重写已建立或正在流式传输的请求；下一顶层 turn 是否激活新 generation 由 22 号 Runtime 决定。协议 adapter 不监视配置文件，也不按时间间隔自行刷新。

Stage 3 的 `self-test phase=semantic` 只能使用 Stage 2 已确认可用且由用户纳入范围的 Model。其受控输入可以包含 Permission 的逻辑名称、`Description`、有界 `SystemPrompt` 与确定性 capability matrix，用来识别拼写、命名和语义明显不一致；输出始终是 advisory，不能修改 profile、授予能力，或推翻 Stage 1/2 的确定性结果。

## Capability preflight 与兼容性结果

chat 的 `.model` picker、`.model <selector>` 与 CLI 等价入口只负责把用户输入规范化为同一个 typed `select-model` action；协议层最终只接收已解析的完整 Model logical identity，不知道用户是按方向键、补全、直接名称还是 CLI 参数选中。所有入口必须得到同一个 enabled/valid/capability preflight、endpoint/privacy 提示、兼容性结果和 selection receipt。

Model 切换不得按 INI 物理顺序 fallback，也不得因 picker/补全隐藏 invalid 项就绕过验证。新 Model 何时可在 busy turn 接纳、当前 Context 超出目标窗口时怎样处理，以及跨 endpoint 是否重新确认，仍分别由 AgentLoop/配置/安全 owner 决定；协议层不能以实现方便提前选择。被接纳的新选择只进入后续顶层 turn 的 immutable snapshot，绝不改写在途 request。

## 无可执行工具 Model 的条件资格

`Tools` 字段存在性由 M05-03 独占，main 资格由 M05-26/`MODEL-16` 独占，协议层不能把两者合并成“能返回文本所以能当 Agent”：

- M05-03 A/C 才可能出现 `Tools=off`。若 M05-26 A，它不能用于 main；若选 B，也只有 adapter 原生承载 AL06-02 已选 control carrier 并通过 fixture 时才能用于受限 main chat，需要 Coding 工具闭环的任务在请求前阻断。
- M05-03 B 完全没有 `Tools` 字段，注册 adapter 静态要求 native tool/control schema；M05-26 在该路线强制 `not-applicable`，协议层不得生成隐藏 no-tool-main 分支。
- `side`、review、compaction 与条件 `context-name` 是否可使用某 Model，仍按各自 purpose 实际需要的 role/control/tool schema 验证，不能因“不是 main”就跳过 capability preflight。

## 已确认的跨系统请求类型：终止评估

D-020 与 D-027 共同确认：当前上下文的有效 `DoubleCheck` 开启时，主模型提出正常终止后需要另外发起一次完成复核请求。配置面已合并，但模型层仍必须让这次请求与主生成可区分：

- 请求具有独立 ID 和明确用途，不能伪装成主模型原请求的重试或续流。
- 用量、延迟、结束原因和错误独立归一化，供 AgentLoop、日志和诊断识别。
- 该请求只返回终止判断，不因复用统一生成接口而自动取得工具执行权。
- 评估结果必须关联触发它的主模型终止意图，不能错误应用到另一个 turn 或后续生成。

尚未确认：使用当前模型还是专用模型、发送哪些目标/消息/工具/验证证据、typed verdict schema、无效输出怎样分类，以及 provider 不支持所需能力时如何处理。这些属于 `MODEL-12`，AgentLoop 如何消费结果属于 `LOOP-25`。

## 待讨论

1. v0.1 精确支持的 wire profile、Endpoint/AuthMode、角色扁平化、SSE/tool-call delta 和 error body。
2. typed finish/ask-user/refusal、文本+工具顺序、length continuation 和能力来源优先级。
3. action/termination review 的模型选择、输入范围、Prompt、verdict 格式和错误分类。
