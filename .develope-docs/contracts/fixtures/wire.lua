local function wire_case(protocol, id, request_bytes, response_bytes, events, finish_class, control)
  return {
    protocol = protocol,
    id = id,
    provenance = "synthetic-exact-bytes",
    request_bytes = request_bytes,
    response_bytes = response_bytes,
    canonical_events = events,
    finish_class = finish_class,
    control = control or false,
  }
end

local openai_request = [[{"model":"gpt-test","messages":[{"role":"user","content":"hi"}],"stream":true}]]
local anthropic_request = [[{"model":"claude-test","max_tokens":64,"messages":[{"role":"user","content":"hi"}],"stream":true}]]
local anthropic_start = "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"m-stream\"}}\n\n"

return {
  contract_version = "0.1.0-readiness.1",
  provenance = {
    kind = "synthetic-golden",
    recorded_provider_bytes = false,
    target_recording_proof = "TP-015",
    purpose = "freeze-parser-and-adapter-causality-before-implementation",
  },
  cases = {
    wire_case("openai-chat", "nonstream_text_stop", [[{"model":"gpt-test","messages":[{"role":"user","content":"hi"}],"stream":false}]], [[{"id":"r1","choices":[{"message":{"role":"assistant","content":"hello"},"finish_reason":"stop"}]}]], { "response_start", "text_delta", "response_finish" }, "stop"),
    wire_case("openai-chat", "stream_text_then_tools", openai_request, "data: {\"id\":\"r2\",\"choices\":[{\"delta\":{\"content\":\"look\"}}]}\n\ndata: {\"id\":\"r2\",\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"c1\",\"function\":{\"name\":\"read\",\"arguments\":\"{}\"}}]},\"finish_reason\":\"tool_calls\"}]}\n\ndata: [DONE]\n\n", { "response_start", "text_delta", "tool_call_start", "tool_arguments_delta", "tool_call_complete", "response_finish" }, "tool_calls"),
    wire_case("openai-chat", "stream_tool_args_split", openai_request, "data: {\"id\":\"r3\",\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"c2\",\"function\":{\"name\":\"read\",\"arguments\":\"{\\\"pa\"}}]}}]}\n\ndata: {\"id\":\"r3\",\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"th\\\":\\\"a\\\"}\"}}]},\"finish_reason\":\"tool_calls\"}]}\n\n", { "response_start", "tool_call_start", "tool_arguments_delta", "tool_arguments_delta", "tool_call_complete", "response_finish" }, "tool_calls"),
    wire_case("openai-chat", "control_finish", openai_request, "data: {\"id\":\"r4\",\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"ctl1\",\"function\":{\"name\":\"yaca_finish\",\"arguments\":\"{\\\"summary\\\":\\\"done\\\"}\"}}]},\"finish_reason\":\"tool_calls\"}]}\n\n", { "response_start", "control", "response_finish" }, "tool_calls", "finish"),
    wire_case("openai-chat", "control_ask_user", openai_request, "data: {\"id\":\"r5\",\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"ctl2\",\"function\":{\"name\":\"yaca_ask_user\",\"arguments\":\"{\\\"question\\\":\\\"Which file?\\\"}\"}}]},\"finish_reason\":\"tool_calls\"}]}\n\n", { "response_start", "control", "response_finish" }, "tool_calls", "ask-user"),
    wire_case("openai-chat", "control_refuse", openai_request, "data: {\"id\":\"r6\",\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"ctl3\",\"function\":{\"name\":\"yaca_refuse\",\"arguments\":\"{\\\"reason\\\":\\\"unsafe\\\"}\"}}]},\"finish_reason\":\"tool_calls\"}]}\n\n", { "response_start", "control", "response_finish" }, "tool_calls", "refuse"),
    wire_case("openai-chat", "model_yield_no_control", openai_request, "data: {\"id\":\"r7\",\"choices\":[{\"delta\":{\"content\":\"Need more detail.\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n", { "response_start", "text_delta", "response_finish" }, "stop"),
    wire_case("openai-chat", "malformed_sse", openai_request, "data: {broken\n\n", { "response_start", "protocol_error" }, "incomplete"),
    wire_case("openai-chat", "truncated_length", openai_request, "data: {\"id\":\"r8\",\"choices\":[{\"delta\":{\"content\":\"partial\"},\"finish_reason\":\"length\"}]}\n\n", { "response_start", "text_delta", "response_finish" }, "length"),
    wire_case("openai-chat", "content_filter", openai_request, "data: {\"id\":\"r9\",\"choices\":[{\"delta\":{},\"finish_reason\":\"content_filter\"}]}\n\n", { "response_start", "response_finish" }, "content_filter"),
    wire_case("openai-chat", "auth_401_no_retry", openai_request, "HTTP/1.1 401 Unauthorized\r\ncontent-type: application/json\r\n\r\n{\"error\":{\"type\":\"authentication_error\"}}", { "transport_error" }, "incomplete"),
    wire_case("openai-chat", "cancel_mid_stream", openai_request, "data: {\"id\":\"r10\",\"choices\":[{\"delta\":{\"content\":\"one\"}}]}\n\n", { "response_start", "text_delta", "transport_error", "response_finish" }, "cancelled"),

    wire_case("anthropic-messages", "nonstream_text_end_turn", [[{"model":"claude-test","max_tokens":64,"messages":[{"role":"user","content":"hi"}],"stream":false}]], [[{"id":"m1","type":"message","content":[{"type":"text","text":"hello"}],"stop_reason":"end_turn"}]], { "response_start", "text_delta", "response_finish" }, "stop"),
    wire_case("anthropic-messages", "stream_text_tool_use", anthropic_request, "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"m2\"}}\n\nevent: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\nevent: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"look\"}}\n\nevent: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":1,\"content_block\":{\"type\":\"tool_use\",\"id\":\"c1\",\"name\":\"read\",\"input\":{}}}\n\nevent: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"tool_use\"}}\n\n", { "response_start", "text_delta", "tool_call_start", "tool_call_complete", "response_finish" }, "tool_calls"),
    wire_case("anthropic-messages", "tool_input_json_delta", anthropic_request, anthropic_start .. "event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"tool_use\",\"id\":\"c2\",\"name\":\"read\",\"input\":{}}}\n\nevent: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"path\\\"\"}}\n\nevent: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\":\\\"a\\\"}\"}}\n\n", { "response_start", "tool_call_start", "tool_arguments_delta", "tool_arguments_delta", "tool_call_complete", "response_finish" }, "tool_calls"),
    wire_case("anthropic-messages", "control_finish", anthropic_request, anthropic_start .. "event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"tool_use\",\"id\":\"ctl1\",\"name\":\"yaca_finish\",\"input\":{\"summary\":\"done\"}}}\n\nevent: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"tool_use\"}}\n\n", { "response_start", "control", "response_finish" }, "tool_calls", "finish"),
    wire_case("anthropic-messages", "control_ask_user", anthropic_request, anthropic_start .. "event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"tool_use\",\"id\":\"ctl2\",\"name\":\"yaca_ask_user\",\"input\":{\"question\":\"Which file?\"}}}\n\nevent: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"tool_use\"}}\n\n", { "response_start", "control", "response_finish" }, "tool_calls", "ask-user"),
    wire_case("anthropic-messages", "control_refuse", anthropic_request, anthropic_start .. "event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"tool_use\",\"id\":\"ctl3\",\"name\":\"yaca_refuse\",\"input\":{\"reason\":\"unsafe\"}}}\n\nevent: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"tool_use\"}}\n\n", { "response_start", "control", "response_finish" }, "tool_calls", "refuse"),
    wire_case("anthropic-messages", "model_yield_no_control", anthropic_request, "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"m3\"}}\n\nevent: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Need more detail.\"}}\n\nevent: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"}}\n\n", { "response_start", "text_delta", "response_finish" }, "stop"),
    wire_case("anthropic-messages", "malformed_event", anthropic_request, "event: content_block_delta\ndata: {broken\n\n", { "protocol_error" }, "incomplete"),
    wire_case("anthropic-messages", "max_tokens", anthropic_request, anthropic_start .. "event: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"max_tokens\"}}\n\n", { "response_start", "response_finish" }, "length"),
    wire_case("anthropic-messages", "cancel_mid_stream", anthropic_request, anthropic_start .. "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"one\"}}\n\n", { "response_start", "text_delta", "transport_error", "response_finish" }, "cancelled"),

    wire_case("cross", "registry_digest_mismatch", [[{"registry_digest":"old"}]], [[{"error":"registry-digest-mismatch"}]], { "protocol_error" }, "incomplete"),
    wire_case("cross", "oversized_tool_args", [[{"tool_argument_limit":16}]], [[{"arguments":"0123456789abcdefX"}]], { "tool_call_start", "tool_arguments_delta", "protocol_error" }, "incomplete"),
    wire_case("cross", "mixed_text_tool_control_order", [[{"controls":["yaca_finish"]}]], [[{"text":"x","tool":"read","control":"yaca_finish"}]], { "response_start", "text_delta", "tool_call_start", "control", "protocol_error" }, "incomplete"),
  },
}
