# W2-C Canonical Model request / event schema

更新日期：2026-08-29

状态：**canonical 规格侧已冻结**；机读真源与 synthetic crosswalk fixtures 为 [`contracts/model.lua`](contracts/model.lua) 和 [`contracts/fixtures/model-events.lua`](contracts/fixtures/model-events.lua)。协议产品选择已冻结为 `openai-chat` + `anthropic-messages`（D-050）；exact wire 仍由 TP-004 录制，**不** 重开产品分叉。

关联：[`subsystems/06-model-protocols.md`](subsystems/06-model-protocols.md)、[`subsystems/09-agent-session.md`](subsystems/09-agent-session.md) W1-A。

AgentLoop **只** 见本节 canonical 形状；禁止把 vendor JSON 直接传入领域层。

## 1. NormalizedRequest

| 字段 | 类型/说明 |
| --- | --- |
| `request_id` | 本地 LogicalRequest id |
| `purpose` | `main` \| `side` \| `action-review` \| `termination-review` \| `compaction` \| `self-test` \| `context-name` |
| `model_ref` | Model logical name + non-secret snapshot（endpoint/protocol/remote id/caps digest；**无 Key**） |
| `config_generation` | public effective digest only |
| `prompt_bundle` | ordered components with source tags（Global/Model[/Permission/Context]/purpose fixed） |
| `model_view_manifest` | digest + fact seq range（from Context） |
| `tool_registry` | names + schema versions + registry digest；purpose 无工具时为空 |
| `controls_schema` | versioned finish/ask-user/refuse envelope |
| `streaming` | force \| try \| off（from Model） |
| `limits` | deadlines, max output, hard caps snapshot |
| `retry_policy` | expanded from Model RetryCount/base + runtime manifest |

## 2. ModelEvent（流式泵事件）

按到达顺序投递；可截断但不得乱序执行工具。

| `kind` | 载荷要点 |
| --- | --- |
| `response_start` | provider ids（审计） |
| `text_delta` | transient 文本块 |
| `reasoning_summary_delta` | 可选；有界；不单独当 assistant 正文 |
| `tool_call_start` | local_tool_call_id；name |
| `tool_arguments_delta` | 仅缓冲；**不**执行 |
| `tool_call_complete` | 完整 JSON args 校验后才闭合 |
| `control` | finish \| ask-user \| refuse + payload |
| `usage_update` | input/output/total if any；missing 允许 |
| `response_finish` | canonical finish_class |
| `transport_error` | typed network/timeout/cancel |
| `protocol_error` | 畸形 JSON/SSE/schema |

### finish_class（canonical）

| class | 含义 |
| --- | --- |
| `stop` | 正常生成结束（**≠** task completed） |
| `length` | 长度截断 |
| `content_filter` | 过滤 |
| `refusal` | 明确拒绝（可与 control refuse 并存） |
| `tool_calls` | 以工具批结束 |
| `cancelled` | 本地/传输取消 |
| `incomplete` | 协议不完整/断流 |

## 3. NormalizedResponse（收口）

完整 response 合法结束后构建：

| 字段 | 说明 |
| --- | --- |
| `content_blocks` | 有序：text / tool_call / control |
| `tool_calls` | validated；local ids 已分配 |
| `control` | optional 单一主 control；冲突 fail-closed |
| `usage` | optional |
| `finish_class` | 上表 |
| `incomplete` | bool + reason |

**工具执行门槛：** response 完整合法 + tool schema 通过 + assistant/control 已 durable **后** 才 admission 工具。流式 args 闭合前绝不执行。

## 4. Typed control envelope（canonical）

| control | 必填载荷 | → AgentLoop |
| --- | --- | --- |
| `finish` | optional summary fields | finish / termination-review 路径 |
| `ask-user` | question text | WaitingUser |
| `refuse` | reason text | refused |

无 control 的完整普通回复 → `model-yield` → WaitingUser。  
禁止从自然语言或 `finish_class=stop` 猜 completed。

Wire：各 adapter 用 **原生 structured** 能力承载 control（tool-like 或官方 structured output）；**禁止** 仅靠 markdown 代码块模拟。

## 5. Dual-protocol mapping notes

### openai-chat

| Wire 概念 | Canonical |
| --- | --- |
| messages[] roles | prompt_bundle + view 投影 |
| tools / tool_calls | tool_registry / tool_call_* events |
| stream chunks delta.content | text_delta |
| stream tool_calls deltas | tool_arguments_delta → complete |
| finish_reason stop/length/content_filter/tool_calls | finish_class |
| usage | usage_update |
| HTTP 4xx/5xx / SSE 畸形 | transport/protocol_error |

### anthropic-messages

| Wire 概念 | Canonical |
| --- | --- |
| system + messages | prompt 分层投影（system 不静默丢层） |
| tools / tool_use blocks | tool_call_* |
| content block text / input_json_delta | text_delta / tool_arguments_delta |
| stop_reason end_turn/max_tokens/tool_use | finish_class |
| usage | usage_update |
| error body | transport/protocol_error |

两套 adapter 必须能：

- 同一 content 批中交错 text + tools + control 且 **保持顺序**  
- 重复/缺失 tool call id → protocol_error 或安全拒绝执行  
- streaming force 不可静默降级；try 仅在首个 canonical event 前证明不支持时降一次  

## 6. Fixture inventory（占位目录）

实现阶段建立；现只冻结清单：

```text
tests/fixtures/model/
  openai-chat/
    nonstream_text_stop/
    stream_text_then_tools/
    stream_tool_args_split/
    control_finish/
    control_ask_user/
    control_refuse/
    model_yield_no_control/
    malformed_sse/
    truncated_length/
    content_filter/
    auth_401_no_retry/
    cancel_mid_stream/
  anthropic-messages/
    nonstream_text_end_turn/
    stream_text_tool_use/
    tool_input_json_delta/
    control_finish/
    control_ask_user/
    control_refuse/
    model_yield_no_control/
    malformed_event/
    max_tokens/
    cancel_mid_stream/
  cross/
    registry_digest_mismatch/
    oversized_tool_args/
    mixed_text_tool_control_order/
```

每条至少断言：事件序、是否执行工具、NormalizedResponse.control、finish_class。

## 7. 与 self-test

Stage 2 必须对每个 enabled Model 实际跑通：auth、stream 或 off、tool schema round-trip、至少一种 control。  
Stage 1 不发 Model 请求。

## 8. W2-C 完成度

- [x] NormalizedRequest / ModelEvent / NormalizedResponse  
- [x] control 与 finish_class  
- [x] 双协议映射要点  
- [x] fixture 清单占位  
- [x] canonical event/control/finish machine schema 与 synthetic fixtures
- [ ] 精确 HTTP header/API 版本表（TP / 录制）  
- [ ] 金标录制字节 fixture  
