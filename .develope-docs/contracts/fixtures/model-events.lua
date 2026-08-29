return {
  contract_version = "0.1.0-readiness.1",
  cases = {
    {
      id = "text-stop-is-model-yield-not-completed",
      events = { "response_start", "text_delta", "response_finish" },
      finish_class = "stop", control = false, execute_tools = false, runtime_result = "waiting_user",
    },
    {
      id = "stream-tool-arguments-execute-only-after-complete",
      events = { "response_start", "tool_call_start", "tool_arguments_delta", "tool_arguments_delta", "tool_call_complete", "response_finish" },
      finish_class = "tool_calls", control = false, execute_tools = true, execute_after_event = "tool_call_complete-and-response-durable",
    },
    {
      id = "typed-finish",
      events = { "response_start", "control", "response_finish" },
      finish_class = "stop", control = "finish", execute_tools = false, runtime_result = "completed-proposed",
    },
    {
      id = "typed-ask-user",
      events = { "response_start", "text_delta", "control", "response_finish" },
      finish_class = "stop", control = "ask-user", execute_tools = false, runtime_result = "waiting_user",
    },
    {
      id = "typed-refuse",
      events = { "response_start", "control", "response_finish" },
      finish_class = "refusal", control = "refuse", execute_tools = false, runtime_result = "refused",
    },
    {
      id = "malformed-stream",
      events = { "response_start", "text_delta", "protocol_error" },
      finish_class = "incomplete", control = false, execute_tools = false, runtime_result = "error",
    },
    {
      id = "cancel-mid-stream",
      events = { "response_start", "text_delta", "transport_error", "response_finish" },
      finish_class = "cancelled", control = false, execute_tools = false, runtime_result = "cancelled",
    },
    {
      id = "length-is-not-completed",
      events = { "response_start", "text_delta", "response_finish" },
      finish_class = "length", control = false, execute_tools = false, runtime_result = "waiting_user",
    },
  },
}
