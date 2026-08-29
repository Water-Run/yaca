return {
  contract_version = "0.1.0-readiness.1",
  traces = {
    {
      id = "first-message-before-model",
      events = {
        { seq = 1, type = "turn_started", fields = { "kind", "configGeneration", "modelSnapshot", "permissionSnapshot", "promptSnapshot", "toolRegistrySnapshot" } },
        { seq = 2, type = "user_message", fields = { "messageId", "text", "source" } },
        { seq = 3, type = "model_request", fields = { "requestId", "purpose", "viewManifestRef" } },
      },
    },
    {
      id = "side-effect-barrier-and-pairing",
      events = {
        { seq = 1, type = "turn_started", fields = { "kind", "configGeneration", "modelSnapshot", "permissionSnapshot", "promptSnapshot", "toolRegistrySnapshot" } },
        { seq = 2, type = "user_message", fields = { "messageId", "text", "source" } },
        { seq = 3, type = "model_request", fields = { "requestId", "purpose", "viewManifestRef" } },
        { seq = 4, type = "model_message", fields = { "messageId", "requestId", "role", "status", "body" } },
        { seq = 5, type = "tool_call", fields = { "toolCallId", "requestId", "name", "canonicalArguments" } },
        { seq = 6, type = "permission_decision", fields = { "toolCallId", "capabilities", "decision", "profileSnapshot" } },
        { seq = 7, type = "approval", fields = { "approvalId", "toolCallId", "decision", "snapshotDigest" } },
        { seq = 8, type = "operation_intent", fields = { "operationId", "toolCallId", "kind", "targetIdentity", "expectedDigest" } },
        { seq = 9, type = "operation_result", fields = { "operationId", "status", "evidence" } },
        { seq = 10, type = "tool_result", fields = { "toolCallId", "status", "body", "truncated" } },
        { seq = 11, type = "turn_ended", fields = { "outcome" } },
      },
    },
    {
      id = "unknown-operation-blocks-replay",
      events = {
        { seq = 1, type = "operation_intent", fields = { "operationId", "toolCallId", "kind", "targetIdentity", "expectedDigest" } },
        { seq = 2, type = "unknown_side_effect", fields = { "operationId", "reason", "requiredAction" } },
        { seq = 3, type = "turn_ended", fields = { "outcome" } },
      },
      outcome = "unknown_side_effect",
      auto_replay = false,
    },
  },
}
