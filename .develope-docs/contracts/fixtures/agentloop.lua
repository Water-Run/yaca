return {
  contract_version = "0.1.0-readiness.1",
  traces = {
    {
      id = "finish-no-doublecheck",
      states = { "Idle", "Preparing", "RequestingModel", "Streaming", "Finalizing", "Idle" },
      controls = { "finish" }, purposes = { "main" }, outcome = "completed", tool_calls = {}, tool_results = {},
    },
    {
      id = "finish-doublecheck-pass",
      states = { "Idle", "Preparing", "RequestingModel", "Streaming", "EvaluatingTermination", "Finalizing", "Idle" },
      controls = { "finish" }, purposes = { "main", "termination-review" }, outcome = "completed", tool_calls = {}, tool_results = {},
    },
    {
      id = "finish-doublecheck-gap-same-turn",
      states = { "Idle", "Preparing", "RequestingModel", "Streaming", "EvaluatingTermination", "RequestingModel", "Streaming", "Finalizing", "Idle" },
      controls = { "finish", "finish" }, purposes = { "main", "termination-review", "main" }, outcome = "completed", same_turn = true, tool_calls = {}, tool_results = {},
    },
    {
      id = "ask-user-then-reply",
      states = { "Idle", "Preparing", "RequestingModel", "Streaming", "WaitingUser", "RequestingModel", "Streaming", "Finalizing", "Idle" },
      controls = { "ask-user", "finish" }, purposes = { "main", "main" }, reported_while_waiting = "waiting_user", outcome = "completed", tool_calls = {}, tool_results = {},
    },
    {
      id = "model-yield-waits",
      states = { "Idle", "Preparing", "RequestingModel", "Streaming", "WaitingUser" },
      controls = {}, purposes = { "main" }, outcome = "waiting_user", tool_calls = {}, tool_results = {},
    },
    {
      id = "typed-refuse",
      states = { "Idle", "Preparing", "RequestingModel", "Streaming", "Finalizing", "Idle" },
      controls = { "refuse" }, purposes = { "main" }, outcome = "refused", tool_calls = {}, tool_results = {},
    },
    {
      id = "permission-deny-produces-synthetic-result",
      states = { "Idle", "Preparing", "RequestingModel", "Streaming", "DispatchingTools", "RequestingModel", "Streaming", "Finalizing", "Idle" },
      controls = { "finish" }, purposes = { "main", "main" }, outcome = "completed",
      tool_calls = { "tool-1" }, tool_results = { { tool_call_id = "tool-1", kind = "synthetic-denied" } },
    },
    {
      id = "approval-reject-produces-synthetic-result",
      states = { "Idle", "Preparing", "RequestingModel", "Streaming", "DispatchingTools", "AwaitingApproval", "DispatchingTools", "RequestingModel", "Streaming", "WaitingUser" },
      controls = {}, purposes = { "main", "main" }, outcome = "waiting_user",
      tool_calls = { "tool-1" }, tool_results = { { tool_call_id = "tool-1", kind = "synthetic-rejected" } },
    },
    {
      id = "cancel-streaming",
      states = { "Idle", "Preparing", "RequestingModel", "Streaming", "Finalizing", "Idle" },
      controls = {}, purposes = { "main" }, outcome = "cancelled", tool_calls = {}, tool_results = {},
    },
    {
      id = "unknown-tool-side-effect",
      states = { "Idle", "Preparing", "RequestingModel", "Streaming", "DispatchingTools", "ExecutingTool", "Finalizing", "Idle" },
      controls = {}, purposes = { "main" }, outcome = "unknown_side_effect",
      tool_calls = { "tool-1" }, tool_results = { { tool_call_id = "tool-1", kind = "unknown" } },
    },
    {
      id = "budget-exhausted",
      states = { "Idle", "Preparing", "RequestingModel", "Streaming", "Finalizing", "Idle" },
      controls = {}, purposes = { "main" }, outcome = "budget_exhausted", tool_calls = {}, tool_results = {},
    },
    {
      id = "stuck-after-warning-and-escape",
      states = { "Idle", "Preparing", "RequestingModel", "Streaming", "Finalizing", "Idle" },
      controls = {}, purposes = { "main" }, outcome = "stuck", durable_warning = true, escape_steps = 1, tool_calls = {}, tool_results = {},
    },
  },
}
