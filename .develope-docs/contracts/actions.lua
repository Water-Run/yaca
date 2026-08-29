local function arg(name, type_name, required, extra)
  local value = { name = name, type = type_name, required = required }
  if extra then for k, v in pairs(extra) do value[k] = v end end
  return value
end

local function argv(long, short, slash, extra)
  local value = { kind = "argv", long = long, short = short, slash = slash }
  if extra then for k, v in pairs(extra) do value[k] = v end end
  return value
end

local function chat(command, key, extra)
  local value = { kind = "chat-line", command = command, key = key }
  if extra then for k, v in pairs(extra) do value[k] = v end end
  return value
end

local function context_repl(command)
  return { kind = "context-repl-line", command = command }
end

return {
  contract_version = "0.1.0-readiness.1",
  decision_refs = { "D-054", "D-061", "D-062", "D-064", "D-065", "D-066", "D-068" },
  parser = {
    canonical_long_prefix = "--",
    end_of_options = "--",
    slash_alias_platform = "windows-only",
    linux_slash_is_path = true,
    long_name_is_documented_name = true,
    legacy_aliases = {},
  },
  exit_classes = {
    success = 0,
    general_error = 1,
    usage = 2,
    invalid_config = 3,
    lock_conflict = 4,
    interaction_required = 5,
    resolver_negative = 6,
    cancelled = 7,
  },

  actions = {
    {
      id = "run-chat", surface = "top", args = { arg("directory", "existing-directory", false, { default = "." }) },
      projections = { argv(false, false, false, { positional = true, default_action = true }) },
      tty = "tty-required", confirm = "none", allowed_states = { "pre-runtime" }, results = { "started", "error" },
    },
    {
      id = "help", surface = "top", args = { arg("topic", "string", false) },
      projections = { argv("--help", "-h", "/h") }, tty = "any", confirm = "none", allowed_states = { "pre-runtime" }, results = { "success", "usage" },
    },
    {
      id = "version", surface = "top", args = {}, projections = { argv("--version", "-v", "/v") },
      tty = "any", confirm = "none", allowed_states = { "pre-runtime" }, results = { "success" },
    },
    {
      id = "self-test", surface = "top", args = {
        arg("through_stage", "enum:1|2|3", false, { default = 1 }),
        arg("list_checks", "bool", false, { default = false }),
        arg("excluded_models", "string-list", false),
        arg("excluded_checks", "check-id-list", false),
        arg("selected_checks", "check-id-list", false),
        arg("online_consent", "bool", false, { spelling = "--i-accept-online-self-test" }),
      },
      projections = { argv("--self-test", "-st", "/st") }, tty = "any", confirm = "online-consent-stage2-plus",
      allowed_states = { "pre-runtime" }, results = { "passed", "partial", "cancelled", "error" },
    },
    {
      id = "model-repl", surface = "top", args = {}, projections = { argv("--model-repl", "-mr", "/mr") },
      tty = "tty-required", confirm = "inside-repl", allowed_states = { "pre-runtime" }, results = { "success", "cancelled", "error" },
    },
    {
      id = "config-repl", surface = "top", args = {}, projections = { argv("--config-repl", "-cfg", "/cfg") },
      tty = "tty-required", confirm = "inside-repl", allowed_states = { "pre-runtime" }, results = { "success", "cancelled", "error" },
    },
    {
      id = "context-repl", surface = "top", args = { arg("view", "enum:recent|full", true) },
      projections = { argv("--context-repl", "-ctx", "/ctx") }, tty = "tty-required", confirm = "inside-repl",
      allowed_states = { "pre-runtime" }, results = { "success", "cancelled", "error" },
    },
    {
      id = "continue", surface = "top", args = { arg("selector", "context-selector", true) },
      projections = { argv("--continue", "-c", "/c") }, tty = "tty-required", confirm = "none",
      allowed_states = { "pre-runtime" }, results = { "started", "not-found", "lock-conflict", "error" },
    },
    {
      id = "export-context", surface = "both", args = { arg("selector", "context-selector", false) },
      projections = { argv("--export", "-ex", "/ex"), context_repl("export <selector?>") }, tty = "any", confirm = "none",
      allowed_states = { "pre-runtime", "Idle", "WaitingUser" }, results = { "success", "not-found", "error" },
    },
    {
      id = "status", surface = "top", args = {}, projections = { argv("--status", "-stt", "/stt") },
      tty = "any", confirm = "none", allowed_states = { "pre-runtime" }, results = { "success", "error" },
    },

    {
      id = "queue-add", surface = "chat", args = { arg("message", "bounded-utf8-text", true) },
      projections = { chat(".queue <message>", "Enter-when-busy", { parse_priority = 20 }) }, tty = "tty-required", confirm = "none",
      allowed_states = { "Idle", "Preparing", "RequestingModel", "Streaming", "DispatchingTools", "AwaitingApproval", "ExecutingTool", "EvaluatingAction", "EvaluatingTermination", "WaitingUser" },
      results = { "started-main", "queued", "queue-full", "error" },
    },
    {
      id = "queue-list", surface = "chat", args = {}, projections = { chat(".queue list", false, { parse_priority = 10 }) },
      tty = "tty-required", confirm = "none", allowed_states = { "Idle", "Preparing", "RequestingModel", "Streaming", "DispatchingTools", "AwaitingApproval", "ExecutingTool", "EvaluatingAction", "EvaluatingTermination", "WaitingUser" }, results = { "success" },
    },
    {
      id = "queue-delete", surface = "chat", args = { arg("queue_id", "queue-id:#N", true) }, projections = { chat(".queue delete <#N>", false, { parse_priority = 10 }) },
      tty = "tty-required", confirm = "none", allowed_states = { "Idle", "Preparing", "RequestingModel", "Streaming", "DispatchingTools", "AwaitingApproval", "ExecutingTool", "EvaluatingAction", "EvaluatingTermination", "WaitingUser" }, results = { "success", "not-found", "error" },
    },
    {
      id = "queue-move", surface = "chat", args = { arg("from", "queue-id:#N", true), arg("to", "queue-position:#N", true) }, projections = { chat(".queue move <from> <to>", false, { parse_priority = 10 }) },
      tty = "tty-required", confirm = "none", allowed_states = { "Idle", "Preparing", "RequestingModel", "Streaming", "DispatchingTools", "AwaitingApproval", "ExecutingTool", "EvaluatingAction", "EvaluatingTermination", "WaitingUser" }, results = { "success", "not-found", "error" },
    },
    {
      id = "queue-edit", surface = "chat", args = { arg("queue_id", "queue-id:#N", true), arg("message", "bounded-utf8-text", true) }, projections = { chat(".queue edit <#N> <message>", false, { parse_priority = 10 }) },
      tty = "tty-required", confirm = "none", allowed_states = { "Idle", "Preparing", "RequestingModel", "Streaming", "DispatchingTools", "AwaitingApproval", "ExecutingTool", "EvaluatingAction", "EvaluatingTermination", "WaitingUser" }, results = { "success", "not-found", "error" },
    },
    {
      id = "queue-clear", surface = "chat", args = {}, projections = { chat(".queue clear", false, { parse_priority = 10 }) },
      tty = "tty-required", confirm = "none", allowed_states = { "Idle", "Preparing", "RequestingModel", "Streaming", "DispatchingTools", "AwaitingApproval", "ExecutingTool", "EvaluatingAction", "EvaluatingTermination", "WaitingUser" }, results = { "success" },
    },
    {
      id = "steer", surface = "chat", args = { arg("message", "bounded-utf8-text", true) }, projections = { chat(".immediate <message>", "Ctrl+Enter") },
      tty = "tty-required", confirm = "none", allowed_states = { "Preparing", "RequestingModel", "Streaming", "DispatchingTools", "AwaitingApproval", "ExecutingTool", "EvaluatingAction", "EvaluatingTermination", "WaitingUser" }, results = { "accepted", "cancel-pending", "unknown-side-effect", "error" },
    },
    {
      id = "side", surface = "chat", args = { arg("message", "bounded-utf8-text", true) }, projections = { chat(".side <message>", "Alt+Enter") },
      tty = "tty-required", confirm = "none", allowed_states = { "Idle", "Preparing", "RequestingModel", "Streaming", "DispatchingTools", "AwaitingApproval", "ExecutingTool", "EvaluatingAction", "EvaluatingTermination", "WaitingUser" }, results = { "accepted", "side-busy", "error" },
    },
    {
      id = "multiline", surface = "chat", args = {}, projections = { chat(".multiline", "Shift+Enter") },
      tty = "tty-required", confirm = "none", allowed_states = { "Idle", "Preparing", "RequestingModel", "Streaming", "DispatchingTools", "AwaitingApproval", "ExecutingTool", "EvaluatingAction", "EvaluatingTermination", "WaitingUser" }, results = { "input-mode-entered", "error" },
    },
    {
      id = "cancel", surface = "chat", args = {}, projections = { chat(".cancel", "Esc") },
      tty = "tty-required", confirm = "none", allowed_states = { "Preparing", "RequestingModel", "Streaming", "DispatchingTools", "AwaitingApproval", "ExecutingTool", "EvaluatingAction", "EvaluatingTermination", "WaitingUser" }, results = { "cancel-requested", "cancelled", "unknown-side-effect", "not-cancellable" },
    },
    {
      id = "cautious", surface = "chat", args = { arg("operation", "enum:status|on|off|toggle|reset", false, { default = "status" }) }, projections = { chat(".cautious [on|off|toggle|reset]", false) },
      tty = "tty-required", confirm = "none", allowed_states = { "Idle", "WaitingUser", "Preparing", "RequestingModel", "Streaming", "DispatchingTools", "AwaitingApproval", "ExecutingTool", "EvaluatingAction", "EvaluatingTermination" }, results = { "success", "next-turn", "error" },
    },
    {
      id = "select-model", surface = "chat", args = { arg("selector", "model-selector", false) }, projections = { chat(".model [selector]", false) },
      tty = "tty-required", confirm = "cross-endpoint-disclosure-if-needed", allowed_states = { "Idle", "WaitingUser", "Preparing", "RequestingModel", "Streaming", "DispatchingTools", "AwaitingApproval", "ExecutingTool", "EvaluatingAction", "EvaluatingTermination" }, results = { "success", "next-turn", "not-found", "error" },
    },
    {
      id = "select-context", surface = "chat", args = { arg("selector", "context-selector", false) }, projections = { chat(".context [selector]", false), context_repl("select <selector>") },
      tty = "tty-required", confirm = "safe-close-current", allowed_states = { "Idle", "WaitingUser" }, results = { "success", "not-found", "lock-conflict", "error" },
    },
    {
      id = "status-chat", surface = "chat", args = {}, projections = { chat(".status", false) }, tty = "tty-required", confirm = "none",
      allowed_states = { "Idle", "Preparing", "RequestingModel", "Streaming", "DispatchingTools", "AwaitingApproval", "ExecutingTool", "EvaluatingAction", "EvaluatingTermination", "WaitingUser", "Finalizing", "Closing" }, results = { "success" },
    },
    {
      id = "help-chat", surface = "chat", args = { arg("topic", "string", false) }, projections = { chat(".help [topic]", false) },
      tty = "tty-required", confirm = "none", allowed_states = { "Idle", "Preparing", "RequestingModel", "Streaming", "DispatchingTools", "AwaitingApproval", "ExecutingTool", "EvaluatingAction", "EvaluatingTermination", "WaitingUser" }, results = { "success", "not-found" },
    },
    {
      id = "details", surface = "chat", args = { arg("error_id", "error-instance-id", false) }, projections = { chat(".details [id]", false) },
      tty = "tty-required", confirm = "none", allowed_states = { "Idle", "Preparing", "RequestingModel", "Streaming", "DispatchingTools", "AwaitingApproval", "ExecutingTool", "EvaluatingAction", "EvaluatingTermination", "WaitingUser" }, results = { "success", "not-found" },
    },
    {
      id = "prompt-edit", surface = "chat", args = { arg("operation", "enum:show|set|clear|edit", false, { default = "show" }), arg("text", "bounded-utf8-text", false) }, projections = { chat(".prompt [show|set|clear|edit] [text]", false) },
      tty = "tty-required", confirm = "editor-if-edit", allowed_states = { "Idle", "WaitingUser", "Preparing", "RequestingModel", "Streaming", "DispatchingTools", "AwaitingApproval", "ExecutingTool", "EvaluatingAction", "EvaluatingTermination" }, results = { "success", "next-turn", "error" },
    },
    {
      id = "compact-manual", surface = "chat", args = {}, projections = { chat(".compact", false) },
      tty = "tty-required", confirm = "none", allowed_states = { "Idle", "WaitingUser" }, results = { "accepted", "no-benefit", "error" },
    },
    {
      id = "quit", surface = "chat", args = {}, projections = { chat(".quit", false) },
      tty = "tty-required", confirm = "none", allowed_states = { "Idle", "Preparing", "RequestingModel", "Streaming", "DispatchingTools", "AwaitingApproval", "ExecutingTool", "EvaluatingAction", "EvaluatingTermination", "WaitingUser", "Finalizing" }, results = { "closing" },
    },

    {
      id = "context-list", surface = "context-repl", args = { arg("view", "enum:recent|full", false, { default = "recent" }) }, projections = { context_repl("list [recent|full]") },
      tty = "tty-required", confirm = "none", allowed_states = { "repl" }, results = { "success", "partial", "error" },
    },
    {
      id = "context-inspect", surface = "context-repl", args = { arg("selector", "context-selector", true) }, projections = { context_repl("inspect <selector>") },
      tty = "tty-required", confirm = "none", allowed_states = { "repl" }, results = { "success", "busy-metadata-only", "not-found", "error" },
    },
    {
      id = "context-search", surface = "context-repl", args = { arg("query", "bounded-utf8-text", true) }, projections = { context_repl("search <query>") },
      tty = "tty-required", confirm = "none", allowed_states = { "repl" }, results = { "success", "partial", "error" },
    },
    {
      id = "context-rename", surface = "context-repl", args = { arg("selector", "context-selector", true), arg("new_name", "context-name", true) }, projections = { context_repl("rename <selector> <new-name>") },
      tty = "tty-required", confirm = "none", allowed_states = { "repl" }, results = { "success", "destination-exists", "lock-conflict", "target-changed", "error" },
    },
    {
      id = "context-rebind", surface = "context-repl", args = { arg("selector", "context-selector", true), arg("target_root", "existing-directory", true) }, projections = { context_repl("rebind <selector> <target-root>") },
      tty = "tty-required", confirm = "human-or-explicit-yes", allowed_states = { "repl" }, results = { "success", "destination-exists", "lock-conflict", "target-changed", "error" },
    },
    {
      id = "context-delete", surface = "context-repl", args = { arg("selector", "context-selector", true), arg("yes", "bool", false, { spelling = "--yes" }) }, projections = { context_repl("delete <selector> [--yes]") },
      tty = "any-with-complete-args", confirm = "human-or-explicit-yes", allowed_states = { "repl", "pre-runtime" }, results = { "success", "lock-conflict", "target-changed", "cancelled", "error" },
    },
    {
      id = "context-set-auto-rename-disabled", surface = "context-repl", args = { arg("selector", "context-selector", true), arg("value", "bool", true) }, projections = { context_repl("set-auto-rename-disabled <selector> <true|false>") },
      tty = "tty-required", confirm = "none", allowed_states = { "repl" }, results = { "success", "lock-conflict", "target-changed", "error" },
    },
    {
      id = "context-import", surface = "context-repl", args = { arg("path", "existing-context-xml-in-place", true) }, projections = { context_repl("import <in-place-xml-path>") },
      tty = "tty-required", confirm = "mapping-and-write-consent", allowed_states = { "repl" }, results = { "validated-readonly", "mapped", "lock-conflict", "error" },
    },
    {
      id = "context-repair", surface = "context-repl", args = { arg("selector", "context-selector", true) }, projections = { context_repl("repair <selector>") },
      tty = "tty-required", confirm = "typed-plan-confirm", allowed_states = { "repl" }, results = { "success", "no-safe-repair", "lock-conflict", "cancelled", "error" },
    },
    {
      id = "context-refresh", surface = "context-repl", args = {}, projections = { context_repl("refresh") },
      tty = "tty-required", confirm = "none", allowed_states = { "repl" }, results = { "success", "partial", "error" },
    },
  },
}
