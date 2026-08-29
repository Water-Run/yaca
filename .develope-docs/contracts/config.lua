local function field(id, section, key, type_name, default, extra)
  local value = {
    id = id,
    section = section,
    key = key,
    type = type_name,
    default = default,
    secret = false,
    context_override = false,
  }
  if extra then
    for k, v in pairs(extra) do value[k] = v end
  end
  return value
end

return {
  contract_version = "0.1.0-readiness.1",
  schema_version = "0.1.0",
  decision_refs = { "M05-06=A", "M05-17=custom:A", "AL06-50=A", "D-047", "D-048" },

  source_precedence = { "built-in-schema", "main-ini", "context-xml-whitelist" },
  physical_sources = {
    main_ini = "executable-directory/__yaca__/config.ini",
    context_xml = "active-context-xml",
  },
  unknown_section = "error",
  unknown_key = "error",
  duplicate_key = "error",
  invalid_generation = "block-new-main-or-side",

  ini_grammar = {
    encoding = "strict-utf8",
    optional_bom = "one-leading-utf8-bom",
    line_endings_read = { "LF", "CRLF" },
    canonical_newline_escape = "\\n",
    text_value_form = "double-quoted",
    empty_text = "\"\"",
    quoted_escapes = { "\\\\", "\\\"", "\\n", "\\r", "\\t" },
    unknown_escape = "error",
    literal_newline_in_value = "error",
    triple_quote = false,
    continuation_line = false,
    comments = { ";", "#" },
    comments_active = "outside-double-quotes",
    scalar_tokens = "schema-typed-ASCII-bool-number-enum-or-sentinel",
    section_and_key_case_sensitive = true,
    preserve_unmodified_concrete_syntax = true,
  },

  fields = {
    field("General.SchemaVersion", "General", "SchemaVersion", "schema-version", "release-value", { required = true }),
    field("Global.SystemPrompt", "General", "SystemPrompt", "bounded-utf8-text", ""),
    field("General.StartupSelfTest", "General", "StartupSelfTest", "enum:off|stage1|stage2|stage3", "off"),
    field("General.LogLevel", "General", "LogLevel", "enum:error|warn|info|debug|trace", "info", { controls = "discardable-terminal-and-xml-diagnostics-only" }),

    field("TUI.StartupShowSlogan", "TUI", "StartupShowSlogan", "bool", true),
    field("TUI.StartupShowVersion", "TUI", "StartupShowVersion", "bool", true),
    field("TUI.StartupShowWorkDir", "TUI", "StartupShowWorkDir", "bool", true),
    field("TUI.StartupShowDataRoot", "TUI", "StartupShowDataRoot", "bool", false),
    field("TUI.StartupShowConfigStatus", "TUI", "StartupShowConfigStatus", "bool", true),
    field("TUI.StartupShowContext", "TUI", "StartupShowContext", "bool", true),
    field("TUI.StartupShowContextHash", "TUI", "StartupShowContextHash", "bool", true),
    field("TUI.StartupShowModel", "TUI", "StartupShowModel", "bool", true),
    field("TUI.StartupShowPermission", "TUI", "StartupShowPermission", "bool", true),
    field("TUI.StartupShowDoubleCheck", "TUI", "StartupShowDoubleCheck", "bool", true),
    field("TUI.StartupShowStatusHint", "TUI", "StartupShowStatusHint", "bool", true),

    field("Agent.DoubleCheck", "Agent", "DoubleCheck", "bool", true, { context_override = "DoubleCheckOverride" }),
    field("Agent.DoubleCheckGoal", "Agent", "DoubleCheckGoal", "bounded-utf8-text", "", { context_override = "DoubleCheckGoalOverride" }),
    field("Agent.ActionReviewEnabled", "Agent", "ActionReviewEnabled", "bool", true),
    field("Agent.ActionReviewModel", "Agent", "ActionReviewModel", "model-ref-or-empty", ""),
    field("Agent.TerminationReviewModel", "Agent", "TerminationReviewModel", "model-ref-or-empty", ""),
    field("Agent.QueueMaxItems", "Agent", "QueueMaxItems", "int:1..RuntimeMaxQueueItems", 9, { user_tighten_only = true, runtime_limit = "TP-017" }),
    field("Agent.CompactThreshold", "Agent", "CompactThreshold", "float-exclusive:0..1", 0.75),
    field("Agent.MaxTurnModelRequests", "Agent", "MaxTurnModelRequests", "optional-positive-int", "unset", { user_tighten_only = true, runtime_limit = "TP-017" }),
    field("Agent.MaxTurnToolCalls", "Agent", "MaxTurnToolCalls", "optional-positive-int", "unset", { user_tighten_only = true, runtime_limit = "TP-017" }),

    field("Network.FollowProxy", "Network", "FollowProxy", "bool", true),
    field("Network.ProxyUrl", "Network", "ProxyUrl", "url-or-empty", "", { secret_when = "contains-credentials" }),
    field("Network.NoProxy", "Network", "NoProxy", "bounded-host-pattern-list", ""),
    field("Network.CaBundlePath", "Network", "CaBundlePath", "path", "release-ca"),
    field("Network.ConnectTimeoutMs", "Network", "ConnectTimeoutMs", "optional-positive-int", "unset", { user_tighten_only = true, runtime_limit = "TP-006" }),
    field("Network.MaxResponseBytes", "Network", "MaxResponseBytes", "optional-positive-int", "unset", { user_tighten_only = true, runtime_limit = "TP-006" }),

    field("Exec.TimeoutMs", "Exec", "TimeoutMs", "optional-positive-int", "unset", { user_tighten_only = true, runtime_limit = "TP-005" }),
    field("Exec.MaxOutputKB", "Exec", "MaxOutputKB", "optional-positive-int", 1024, { user_tighten_only = true, runtime_limit = "TP-005" }),
    field("Exec.EnvironmentMode", "Exec", "EnvironmentMode", "enum:minimal|inherit_filtered", "minimal"),

    field("Context.AutoNameEveryMainTurns", "Context", "AutoNameEveryMainTurns", "non-negative-int", 10, { zero_means = "disabled", runtime_limit = "TP-017" }),
    field("Context.ListSortBy", "Context", "ListSortBy", "enum:created|updated|name", "updated"),
    field("Context.ListSortDirection", "Context", "ListSortDirection", "enum:ascending|descending", "descending"),
    field("Context.RecentListLimit", "Context", "RecentListLimit", "optional-positive-int", "unset", { user_tighten_only = true, runtime_limit = "TP-012" }),

    field("Permission.*.Description", "Permission.*", "Description", "bounded-utf8-string", ""),
    field("Permission.*.SystemPrompt", "Permission.*", "SystemPrompt", "bounded-utf8-text", ""),
    field("Permission.*.Read", "Permission.*", "Read", "enum:allow|confirm|deny", "required", { required = true }),
    field("Permission.*.Write", "Permission.*", "Write", "enum:allow|confirm|deny", "required", { required = true }),
    field("Permission.*.Delete", "Permission.*", "Delete", "enum:allow|confirm|deny", "required", { required = true }),
    field("Permission.*.Shell", "Permission.*", "Shell", "enum:allow|confirm|deny", "required", { required = true }),
    field("Permission.*.OutsideWorkspace", "Permission.*", "OutsideWorkspace", "enum:allow|confirm|deny", "required", { required = true }),

    field("Model.*.Enabled", "Model.*", "Enabled", "bool", "template-value"),
    field("Model.*.Description", "Model.*", "Description", "bounded-utf8-string", ""),
    field("Model.*.Protocol", "Model.*", "Protocol", "enum:openai-chat|anthropic-messages", "required", { required = true }),
    field("Model.*.Endpoint", "Model.*", "Endpoint", "url", "required-if-enabled"),
    field("Model.*.RemoteModel", "Model.*", "RemoteModel", "bounded-ascii-or-utf8-string", "required-if-enabled"),
    field("Model.*.Key", "Model.*", "Key", "bounded-secret-string", "", { secret = true }),
    field("Model.*.SystemPrompt", "Model.*", "SystemPrompt", "bounded-utf8-text", ""),
    field("Model.*.ContextLength", "Model.*", "ContextLength", "optional-positive-int", "template-value"),
    field("Model.*.MaxOutputTokens", "Model.*", "MaxOutputTokens", "optional-positive-int", "unset", { user_tighten_only = true, runtime_limit = "provider-and-TP-004" }),
    field("Model.*.Streaming", "Model.*", "Streaming", "enum:force|try|off", "try"),
    field("Model.*.RequestTimeoutMs", "Model.*", "RequestTimeoutMs", "optional-positive-int", "unset", { user_tighten_only = true, runtime_limit = "TP-006" }),
    field("Model.*.RetryCount", "Model.*", "RetryCount", "non-negative-int", "runtime-default", { user_tighten_only = true, runtime_limit = "TP-017" }),
    field("Model.*.RetryBaseDelayMs", "Model.*", "RetryBaseDelayMs", "optional-positive-int", "unset", { user_tighten_only = true, runtime_limit = "TP-017" }),
    field("Model.*.ToolsEnabled", "Model.*", "ToolsEnabled", "bool", true),
    field("Model.*.AdapterOptions", "Model.*", "AdapterOptions", "adapter-typed-map", "empty", { secret_by_registered_key = true, runtime_limit = "TP-004" }),
  },

  context_xml_whitelist = {
    { id = "CurrentModel", kind = "selector", source = "Model.*" },
    { id = "CurrentPermission", kind = "selector", source = "Permission.*" },
    { id = "DoubleCheckOverride", kind = "enum:inherit|true|false", source = "Agent.DoubleCheck" },
    { id = "DoubleCheckGoalOverride", kind = "inherit-or-bounded-text", source = "Agent.DoubleCheckGoal" },
    { id = "ContextPrompt", kind = "bounded-utf8-text", source = "context-only" },
    { id = "AutoRenameDisabled", kind = "bool-metadata", source = "context-only" },
  },

  release_permission_profiles = {
    {
      name = "Std",
      order = 1,
      Read = "allow", Write = "confirm", Delete = "confirm", Shell = "confirm", OutsideWorkspace = "confirm",
    },
    {
      name = "Readonly",
      order = 2,
      Read = "allow", Write = "deny", Delete = "deny", Shell = "deny", OutsideWorkspace = "deny",
    },
  },

  prompt_order = { "runtime-purpose", "global", "model", "permission-main-side-only", "context-main-side-only", "user-message" },
  forbidden_field_ids = {
    "Agent.StuckNoProgressRounds",
    "Agent.MaxNoProgressRounds",
    "Context.CompactThresholdOverride",
    "Permission.*.DoubleCheck",
    "Permission.*.Cautious",
    "Network.UseStunnel",
    "Network.DirectHttp",
    "Network.DirectNetwork",
    "Permission.*.SensitiveRead",
    "General.StartupHeader",
    "Context.AutoJumpToDir",
    "Context.ResumeDirectory",
    "Model.*.CustomPrompt",
    "Model.*.CompactionModel",
  },

  stuck_detector = {
    selected = "AL06-50=A",
    source = "versioned-release-manifest",
    proof = "TP-017/TP-022",
    ini_fields = {},
    context_fields = {},
  },

  migration_rules = {
    { source = "Model.*.CustomPrompt", target = "Model.*.SystemPrompt", action = "copy-exact-then-validate-before-delete" },
    { source = "Permission.*.DoubleCheck", target = false, action = "diagnostic-explicit-Agent.DoubleCheck-choice-required" },
    { source = "Permission.Cautious", target = false, action = "diagnostic-explicit-profile-and-session-mapping-required" },
    { source = "Network.UseStunnel", target = false, action = "remove-and-explain-external-stunnel-endpoint-route" },
    { source = "Context.AutoJumpToDir", target = false, action = "remove-no-equivalent" },
    { source = "Context.ResumeDirectory", target = false, action = "remove-no-equivalent" },
    { source = "optional-numeric=false", target = false, action = "diagnostic-explicit-missing-or-value-choice-required" },
  },
}
