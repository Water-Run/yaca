return {
  contract_version = "0.1.0-readiness.1",
  decision_refs = { "D-054", "D-064", "D-066" },

  product_slogan = "yaca: Yet Another Coding Agent.",
  prompts = {
    chat = { text = ">>", color = "dim-neutral" },
    approval = { text = "??", color = "yellow" },
    model_repl = { text = "model>", color = "green" },
    config_repl = { text = "config>", color = "cyan" },
    context_repl = { text = "context>", color = "blue" },
    self_test = { text = "test>", color = "magenta" },
  },
  plain_text_uses_same_prompt_text = true,

  input_bindings = {
    { intent = "submit-or-queue", key = "Enter", fallback_action = "queue-add" },
    { intent = "steer", key = "Ctrl+Enter", fallback_action = "steer" },
    { intent = "newline", key = "Shift+Enter", fallback_action = "multiline" },
    { intent = "side", key = "Alt+Enter", fallback_action = "side" },
    { intent = "cancel", key = "Esc", fallback_action = "cancel" },
  },

  input_states = {
    "line-edit",
    "multiline-edit",
    "busy-input",
    "waiting-user-answer",
    "approval-answer",
    "selector",
    "repl-line",
    "closing",
  },
  runtime_state_projection = {
    Idle = "line-edit",
    Preparing = "busy-input",
    RequestingModel = "busy-input",
    Streaming = "busy-input",
    DispatchingTools = "busy-input",
    AwaitingApproval = "approval-answer",
    ExecutingTool = "busy-input",
    EvaluatingAction = "busy-input",
    EvaluatingTermination = "busy-input",
    WaitingUser = "waiting-user-answer",
    Finalizing = "busy-input",
    Closing = "closing",
  },

  renderer_gestures_not_domain_actions = {
    "cursor-left", "cursor-right", "cursor-up", "cursor-down", "scroll-up", "scroll-down", "page-up", "page-down", "focus-next",
  },

  output = {
    startup_lines_independent = true,
    startup_master_switch = false,
    mandatory_prefixes = { "ERROR", "WARNING", "ACTION", "STATUS" },
    context_hash = "16-uppercase-hex",
    queue_id = "#N",
    stdout_is_primary_result = true,
    stderr_is_diagnostics = true,
    renderer = "append-only-transcript-with-optional-current-status-enhancement",
    interactive_gate = "stdin-and-stdout-are-tty-and-machine-not-requested",
    program_chrome = "ASCII-only",
    untrusted_control_bytes = "escape-before-render",
    transcript_fixture = "fixtures/tui-transcripts.lua",
  },

  line_editor = {
    ownership = "yaca-native-or-raw-editor",
    draft_is_runtime_owned = true,
    async_output = "atomically-hide-draft-append-complete-block-redraw-identical-draft",
    character_level_interleave = false,
    cooked_fallback = "coalesce-and-defer-until-safe-line-with-visible-backlog-status",
    plain_mode_semantics_equal = true,
  },

  transcript_blocks = {
    "USER", "ASSISTANT", "TOOL ID", "SIDE ID", "STATUS", "QUEUE ID",
    "STEER ID", "NOTICE", "WARNING", "ERROR ID", "RECOVERY ID",
    "DETAILS ID", "ACTION ID",
  },

  terminal_modes = {
    enhanced = "capability-detected",
    plain_tty = "full-text-command-fallback",
    dumb_or_no_color = "same-ASCII-prompts-no-color",
    non_tty_chat = "reject-interactive-chat",
    windows_xp_ansi_assumed = false,
  },

  proof_required = {
    "TP-003-console-input-event-pump",
    "TP-015-render-and-key-fallback",
  },
}
