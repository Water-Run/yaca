-- Synthetic exact-byte archive for C21. This is deliberately not TP-015 evidence.
return {
    schema_version = "yaca-provider-wire-archive-v0.1.0",
    source = ".develope-docs/contracts/fixtures/wire.lua",
    provenance = "synthetic-exact-bytes",
    recorded_provider_bytes = false,
    target_proof = {
        id = "TP-015",
        status = "pending-target-recording",
        qualifies_release = false,
    },
    inventory = {
        ["openai-chat"] = {
            "nonstream_text_stop", "stream_text_then_tools", "stream_tool_args_split",
            "control_finish", "control_ask_user", "control_refuse",
            "model_yield_no_control", "malformed_sse", "truncated_length",
            "content_filter", "auth_401_no_retry", "cancel_mid_stream",
        },
        ["anthropic-messages"] = {
            "nonstream_text_end_turn", "stream_text_tool_use", "tool_input_json_delta",
            "control_finish", "control_ask_user", "control_refuse",
            "model_yield_no_control", "malformed_event", "max_tokens", "cancel_mid_stream",
        },
        cross = {
            "registry_digest_mismatch", "oversized_tool_args",
            "mixed_text_tool_control_order",
        },
    },
}
