return {
  contract_version = "0.1.0-readiness.1",
  purpose_cases = {
    { id = "main", layers = { "runtime-purpose", "global", "model", "permission", "context", "user-message" }, tools = "registered", controls = { "yaca_finish", "yaca_ask_user", "yaca_refuse" } },
    { id = "side", layers = { "runtime-purpose", "global", "model", "permission", "context", "user-message" }, tools = "none", controls = {} },
    { id = "action-review", layers = { "runtime-purpose", "global", "model", "permission-quoted", "context-quoted", "proposed-action-quoted", "evidence-quoted" }, tools = "none", controls = {} },
    { id = "termination-review", layers = { "runtime-purpose", "global", "model", "double-check-goal-quoted", "context-quoted", "candidate-report-quoted", "evidence-quoted" }, tools = "none", controls = {} },
    { id = "compaction", layers = { "runtime-purpose", "global", "model", "model-view-input" }, tools = "none", controls = {} },
    { id = "self-test", layers = { "runtime-purpose", "global", "model", "synthetic-observation" }, tools = "inert", controls = {} },
    { id = "context-name", layers = { "runtime-purpose", "global", "model", "committed-facts" }, tools = "none", controls = {} },
  },
  control_cases = {
    { id = "finish", wire_name = "yaca_finish", required = {}, optional = { "summary" } },
    { id = "ask-user", wire_name = "yaca_ask_user", required = { "question" }, optional = {} },
    { id = "refuse", wire_name = "yaca_refuse", required = { "reason" }, optional = {} },
  },
}
