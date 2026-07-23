# 06 模型协议适配

状态：v0.1 provider 范围与 canonical 控制已确认；wire fixture 和具体限额待技术证明

## 职责

把内部统一的消息、工具、typed control 和 request purpose 转换为已注册 provider wire profile，并把响应转换回统一事件与结果。AgentLoop 永远只面对 canonical 接口，不读取厂商 JSON、SSE、finish reason 或错误体细节。

## v0.1 正式协议范围

v0.1 同时完整支持两套 adapter：

- `openai-chat`：OpenAI Chat Completions compatible wire profile；
- `anthropic-messages`：Anthropic Messages wire profile。

`openai-responses` 不进入 v0.1，也不能把一个看似兼容的自定义 endpoint 自动猜成另一 adapter。每个 `Model.<Name>` 是完整 LLM 连接实例，显式选择 adapter，并带 endpoint、远端 model ID、明文 Key、能力、streaming、timeout/retry、输出限制、Description、SystemPrompt 和该 adapter 注册的 typed options。

两套 adapter 必须分别通过 non-stream、stream、native structured tool calling、typed control、usage、refusal/filter、错误、取消、重试边界与资源超限 fixture；不能因为文本回复成功就宣称该 Model 可用于 Coding Agent main。

## 边界

- HTTP、TLS、代理、CA 和传输 retry 由 03 号系统处理。
- JSON/UTF-8/XML 基础能力由 04 号系统处理。
- Model 选择、Prompt 字段和配置 generation 由 05 号系统提供。
- AgentLoop 只消费 `NormalizedRequest`、`ProviderEvent` 和 `NormalizedResponse`。
- adapter 不能新增工具、扩大 Permission、自动切换 Model/provider 或为特殊 purpose 改写 Prompt 继承规则。

## canonical 请求与事件

实现不得把 provider JSON table 直接传给 AgentLoop。统一契约至少包含：

```text
NormalizedRequest
  local request ID, purpose, immutable Model/config snapshot
  PromptBundle + model-view manifest
  canonical tool/control schema snapshot
  streaming, deadlines, retry and hard output limits

ProviderEvent
  response-start, text-delta, reasoning-summary-delta
  tool-call-start, tool-arguments-delta, tool-call-complete
  usage-update, response-finish, transport/protocol-error

NormalizedResponse
  ordered content blocks, validated tool calls / typed control
  usage, canonical finish class, refusal/filter/incomplete evidence
```

本地 request/message/tool-call/operation ID 由 yaca 分配并写入 XML；provider ID 只作为证据。工具参数只有在完整 response 合法结束、call ID/JSON/schema/数量/大小全部验证、canonical assistant response 已 durable 后，才交给 AgentLoop。断流前看似闭合的 JSON 绝不提前执行。

## 统一 Tool Calling 表面

v0.1 的 main tool registry 固定投影 `list/read/search/write/patch/rename/delete/exec`。direct tools 使用严格 typed fields；`exec` 只接收 opaque 原始 command string，并由 Permission 视为宽 `Shell`。

不注册 Web、HTTP、network、clipboard、media、background-job、MCP、plugin 或第三方自定义 tool。模型在 Shell 获准后运行 curl 只是普通 `exec` 副作用，不成为 adapter 的 direct network 能力。OpenAI 与 Anthropic adapter 必须把同一份 canonical schema 映射到各自原生 structured tool calling；不使用自然语言标签或 JSON code block 模拟 tool call。

## 已确认的 typed control

provider 的普通 `stop` 只表示一次生成结束，不能表示任务完成。Runtime 向 main Model 提供版本化、无副作用的 reserved typed controls：

- `finish`：主模型明确声明当前任务结果可以收口；
- `ask-user`：需要用户信息或决定，进入可恢复 waiting-user；
- `refuse`：主模型明确拒绝该请求，并保存理由与 typed refused outcome。

文本、工具和 control 可以按 canonical schema 合法组合；adapter 必须保持它们的原顺序和关联。一个完整回复没有任何 control 时保存为 `model-yield` 并进入 waiting-user，不能从自然语言或 provider stop 猜成 completed。`ask-user` 的回答继续同一 turn，一个 Context 同时最多一个普通 Enter 可回答的 pending question。

typed controls 通过 provider 原生结构化能力承载，再归一化为相同内部 envelope。无法无损提供该 envelope 或原生 structured tool calling 的 Model 不能作为完整 main Coding Model；self-test Stage 2 必须实际探测，而不是只相信配置名称。

## request purpose 与 Prompt

正式 purpose 包含 `main`、`side`、`action-review`、`termination-review`、`compaction`、`self-test`，以及条件性的 `context-name`。Stage 2/3 self-test 分别使用 `phase=capability|semantic`；Stage 1 不发 Model 请求。

所有 purpose 按 18 号契约继承 Global 与实际使用 Model 的 SystemPrompt。只有 `main`/`side` 再继承 Permission.SystemPrompt 和 ContextPrompt。review、compaction、self-test、context-name 使用 Runtime 固定 purpose prompt；所需 Permission、Context、配置、历史或 Prompt 内容只进入有边界的 quoted-data 槽，不能取得指令权威。adapter 不因 provider role 限制而静默丢层或重排，无法无损编码时 capability preflight 失败。

每个顶层 `main`/`side` admission 绑定不可变 config generation。该 turn 派生的 retry、tool loop、review 和 compaction 沿用同一 Model/Permission/Prompt/tool-schema snapshot；活动期间 INI 变化不能重写在途 request。

## DoubleCheck request

有效 `DoubleCheck=true` 时，主模型发出 `finish` 后必须发起独立 `termination-review`；finish review 不能由 target 列表或另一个配置字段关闭。高风险动作是否增加 `action-review` 是独立可配置项，`DoubleCheck=false` 时两类 review 都停用。

- 两类 review 默认使用当前 turn Model，也可分别配置 Termination/Action reviewer Model；不能共用一个含混 selector。
- reviewer 跨 endpoint 首次使用前必须按已确认的 endpoint disclosure 规则取得同意。
- review 有独立 request ID、purpose、PromptBundle、usage、错误、hard cap 和与被审对象的稳定关联，不是主请求 retry。
- action verdict 只能维持或收紧 Permission 结果，不能把 `deny` 改成可执行。
- termination verdict 指出明确缺口时回到同一 turn 继续；uncertain、协议失败、超时或达到 review 上限时进入 waiting-user，不能静默当作通过。
- reviewer 没有工具权限；purpose-specific verdict 必须通过版本化 schema，普通 reviewer 文本不能被 Runtime 猜成允许。

`DoubleCheckGoal` 只作为 finish review 的有界目标/验收标准 data；为空时由当前 task facts 构造。它不改变 action approval 或 Permission。

## streaming、结束与错误归一化

OpenAI/Anthropic 的 finish reason、stop reason、content block 和 usage 名称分别映射到 canonical 枚举；provider 正常停止、长度截断、内容过滤、明确拒绝、工具请求、取消和协议不完整必须可区分。任何 canonical response event 到达后，03 号系统不得自动重放整次 request。

adapter 对 header、单 event、累计文本、reasoning summary、tool count、tool arguments、content blocks 和总响应实施不可关闭硬上限。达到上限返回 typed limit/incomplete result，并保持已经 durable 的事实，不把截断内容伪装成完整 assistant message。

## 仍需技术证明

冻结两套 adapter 的精确 API 版本/header、role 映射、stream delta 状态机、reserved control wire schema、usage/error 映射和 fixture corpus；同时证明旧系统 curl 流、取消和大 tool arguments 不会越过内存上限。产品范围不再重开 `openai-chat` vs Anthropic、自然语言 tool calling、direct Web tool 或 provider stop 隐式完成。
