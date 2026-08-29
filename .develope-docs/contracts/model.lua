return {
  contract_version = "0.1.0-readiness.1",
  schema_version = "0.1.0",
  decision_refs = { "D-050", "D-051" },

  protocols = {
    {
      id = "openai-chat",
      canonical_endpoint_shape = "/v1/chat/completions",
      exact_wire_profile = "TP-004-recorded-provider-profile",
      proof_required = true,
    },
    {
      id = "anthropic-messages",
      canonical_endpoint_shape = "/v1/messages",
      exact_wire_profile = "TP-004-recorded-provider-profile",
      proof_required = true,
    },
  },

  purposes = {
    "main",
    "side",
    "action-review",
    "termination-review",
    "compaction",
    "self-test",
    "context-name",
  },

  normalized_request = {
    required = {
      "request_id",
      "purpose",
      "model_ref",
      "config_generation",
      "prompt_bundle",
      "model_view_manifest",
      "tool_registry",
      "controls_schema",
      "streaming",
      "limits",
      "retry_policy",
    },
    secret_fields = {},
    forbidden_fields = { "key", "authorization", "proxy_credentials", "private_source_digest" },
  },

  event_kinds = {
    { id = "response_start", required = { "request_id", "provider_response_id" }, transient = false },
    { id = "text_delta", required = { "request_id", "text" }, transient = true },
    { id = "reasoning_summary_delta", required = { "request_id", "text" }, transient = true },
    { id = "tool_call_start", required = { "request_id", "local_tool_call_id", "name" }, transient = false },
    { id = "tool_arguments_delta", required = { "request_id", "local_tool_call_id", "bytes" }, transient = true, executable = false },
    { id = "tool_call_complete", required = { "request_id", "local_tool_call_id", "name", "canonical_arguments" }, transient = false, schema_validated = true },
    { id = "control", required = { "request_id", "control", "payload" }, transient = false },
    { id = "usage_update", required = { "request_id" }, optional = { "input", "output", "total" }, transient = false },
    { id = "response_finish", required = { "request_id", "finish_class" }, transient = false },
    { id = "transport_error", required = { "request_id", "error_id", "retryable" }, transient = false },
    { id = "protocol_error", required = { "request_id", "error_id" }, transient = false },
  },

  finish_classes = {
    "stop",
    "length",
    "content_filter",
    "refusal",
    "tool_calls",
    "cancelled",
    "incomplete",
  },

  controls = {
    { id = "finish", required_payload = {}, optional_payload = { "summary" }, runtime_state = "EvaluatingTermination-or-Finalizing", runtime_outcome = "completed-proposed" },
    { id = "ask-user", required_payload = { "question" }, optional_payload = {}, runtime_state = "WaitingUser", runtime_outcome = "waiting_user" },
    { id = "refuse", required_payload = { "reason" }, optional_payload = {}, runtime_state = "Finalizing", runtime_outcome = "refused" },
  },

  normalized_response = {
    required = { "content_blocks", "tool_calls", "finish_class", "incomplete" },
    optional = { "control", "usage" },
    content_block_kinds = { "text", "tool_call", "control" },
    maximum_primary_controls = 1,
    conflicting_controls = "protocol-error-fail-closed",
  },

  execution_gate = {
    response_complete_and_valid = true,
    tool_schema_valid = true,
    assistant_and_control_durable = true,
    streaming_arguments_executable = false,
  },

  streaming = {
    modes = { "force", "try", "off" },
    force_may_fallback = false,
    try_fallback_max = 1,
    try_fallback_only_before_first_canonical_event = true,
  },

  wire_fixture_inventory = {
    ["openai-chat"] = {
      "nonstream_text_stop", "stream_text_then_tools", "stream_tool_args_split",
      "control_finish", "control_ask_user", "control_refuse", "model_yield_no_control",
      "malformed_sse", "truncated_length", "content_filter", "auth_401_no_retry", "cancel_mid_stream",
    },
    ["anthropic-messages"] = {
      "nonstream_text_end_turn", "stream_text_tool_use", "tool_input_json_delta",
      "control_finish", "control_ask_user", "control_refuse", "model_yield_no_control",
      "malformed_event", "max_tokens", "cancel_mid_stream",
    },
    cross = { "registry_digest_mismatch", "oversized_tool_args", "mixed_text_tool_control_order" },
  },
}
