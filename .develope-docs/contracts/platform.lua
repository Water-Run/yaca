return {
  contract_version = "0.1.0-readiness.1",
  decision_refs = { "D-013", "D-014", "D-017", "D-045", "D-057" },

  target_ids = { "win32-x86", "win64-x86_64", "linux-x86_64" },

  composition = {
    entry_module = "main",
    composition_roots = 1,
    business_source_shared_across_targets = true,
    business_code_branches_on_windows_version = false,
  },

  safe_loading = {
    lua_module_allowlist = {
      "backend_linux", "backend_windows", "cli", "clock", "compact", "config",
      "context", "diagnostics", "fs", "index", "ini", "json", "main", "model",
      "network", "path", "permission", "platform", "process", "prompt", "runtime",
      "safety", "session", "terminal", "text", "tools", "tui", "xml",
    },
    planned_lua_module_allowlist = {
      "backend_linux", "backend_windows", "cli", "clock", "compact", "config",
      "context", "diagnostics", "fs", "index", "ini", "json", "main", "model",
      "network", "path", "permission", "platform", "process", "prompt", "runtime",
      "safety", "session", "terminal", "text", "tools", "tui", "xml",
    },
    native_module_allowlist = { "yaca_native", "lxp" },
    lua_search_source = "embedded-release-manifest-only",
    current_working_directory = false,
    environment_lua_path = false,
    environment_lua_cpath = false,
    user_module_directories = false,
    system_module_directories = false,
    dynamic_extension_discovery = false,
    module_top_level_io = false,
    native_dependencies = "absolute-or-target-proven-safe-executable-relative-load",
    proof_required = { "TP-001", "TP-002", "TP-014" },
  },

  ports = {
    path = { "normalize-logical", "resolve-existing", "compare-identity", "encode-context-mirror", "decode-context-mirror" },
    filesystem = { "open-read", "create-new", "stat-identity", "stream-read", "stream-write", "flush-file", "flush-directory", "replace", "rename-no-replace", "delete-verified" },
    process = { "start", "poll", "cancel", "join", "close" },
    network = { "start", "poll", "cancel", "join", "close" },
    terminal = { "start", "poll", "cancel", "join", "close", "restore" },
    clock = { "monotonic-now", "utc-now", "deadline" },
    text = { "strict-utf8-validate", "wide-path-convert", "xml-escape", "terminal-lossy-display-only" },
  },

  target_identity = {
    direct_path_fields = { "logicalPath", "objectKind", "platformIdentity", "size", "rawDigest", "observedAt" },
    context_handle_fields = { "logicalPath", "pathHash", "platformIdentity", "generation", "rawDigest", "writerLease" },
    config_source_fields = { "size", "rawDigest" },
    mtime_or_size_only_is_sufficient = false,
    display_path_is_hash_input = false,
    reverify_before_side_effect = true,
    proof_required = { "TP-010", "TP-011", "TP-012" },
  },

  locks = {
    context_writer_lease = "long-lived-single-writer",
    context_commit_mutex = "short-lived-publish-only",
    config_commit_lock = "independent-short-lived",
    active_writer_allows_second_body_reader = false,
    stale_by_age_only = false,
    external_context_mutation_while_leased = "LockConflict",
    acquisition_order = { "context-writer-lease", "context-commit-mutex", "verified-filesystem-target" },
    proof_required = { "TP-008", "TP-011" },
  },

  event_pump = {
    mutable_domain_threads = 1,
    async_port_methods = { "start", "poll", "cancel", "join", "close" },
    terminal_events_may_drop = false,
    progress_events_may_coalesce = true,
    queues_are_bounded = true,
    proof_required = { "TP-003", "TP-005", "TP-006", "TP-022" },
  },
}
