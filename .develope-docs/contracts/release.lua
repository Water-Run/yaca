return {
  contract_version = "0.1.0-readiness.1",
  release_contract_version = "yaca-release-v0.1.0-readiness.1",
  decision_refs = { "D-003", "D-004", "D-007", "D-009", "D-056", "D-069", "D-070" },

  packaging = {
    luainstaller = { version = "1.3.0", tag = "v1.3.0", commit = "97192d1" },
    targets = { "win32-x86", "win64-x86_64", "linux-x86_64" },
    target_qualification = "independent-full-matrix-before-release",
    source_implementation_may_begin_before_target_qualification = true,
    target_failure_blocks_release = true,
  },

  dependency_lock = {
    lua = {
      version = "5.5.1",
      sha256 = "1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce",
      linkage = "embedded-by-luainstaller",
    },
    expat = {
      version = "2.8.2",
      sha256 = "ef7d1994f533c9e7343d6c19f31064fc8ebbcbcaa144be3812b4f43052a05f4c",
      linkage = "static-into-lxp",
    },
    luaexpat = {
      version = "1.5.2",
      sha256 = "89d83f2141edec31be576425637216928221918fe95dc3854d1b7fd4c627213f",
      linkage = "target-built-lxp-native-module",
    },
    curl = {
      version = "target-lock-before-network-integration",
      linkage = "bundled-executable",
      proof_required = { "TP-006", "TP-007", "TP-029" },
    },
    ca_bundle = {
      version = "target-lock-before-network-integration",
      linkage = "bundled-data",
      proof_required = { "TP-007", "TP-029" },
    },
    yaca_native = {
      version = "same-as-product",
      linkage = "target-built-native-module",
      owns = { "event-wait", "filesystem-primitives", "process", "terminal", "clock", "sha256" },
    },
  },

  shipped_component_allowlist = {
    "launcher+embedded-lua", "yaca-lua-sources", "yaca-native", "lxp+static-expat",
    "curl", "ca-bundle", "Install-script", "README.txt", "LICENSE", "docs",
  },
  build_only_components = { "compiler-toolchain", "cmake", "archive-tool", "test-runner" },
  forbidden_shipped_components = {
    "sqlite3", "jq", "7za", "web-server", "browser-assets", "media-codec",
    "speech-runtime", "remote-controller", "plugin-loader", "mcp-client",
    "telemetry-client", "update-client",
  },

  planned_lua_modules = {
    "backend_linux", "backend_windows", "cli", "clock", "compact", "config",
    "context", "diagnostics", "fs", "index", "ini", "json", "main", "model",
    "network", "path", "permission", "platform", "process", "prompt", "runtime",
    "safety", "session", "terminal", "text", "tools", "tui", "xml",
  },
  initial_skeleton_modules = {
    "cli", "compact", "config", "context", "index", "ini", "json", "main",
    "model", "path", "safety", "session", "text", "tui",
  },

  implementation_candidates = {
    status = "modern-proof-candidates-not-release-frozen",
    may_only_be_consumed_through_injected_manifest = true,
    minimum_scannable_secret_bytes = 8,
    retry = {
      default_count = 2,
      default_base_delay_ms = 500,
      maximum_count = 10,
      exponent = 2,
      maximum_delay_ms = 30000,
      runtime_wait_cap_ms = 60000,
      deterministic_jitter_permille = 100,
      identity = "tp006-modern-candidate-v1",
    },
    redirect_maximum = 3,
  },

  unresolved_release_constants = {
    "all-runtime-hard-caps", "stuck-detector-thresholds", "curl-version-and-hash",
    "CA-version-and-hash", "process-cancel-grace", "event-poll-and-input-latency",
    "Context-size-and-commit-latency", "Catalog-scan-cap", "TUI-output-backlog-cap",
  },

  release_evidence = {
    per_target = { "sha256", "component-license-manifest", "SBOM", "build-summary", "full-test-summary" },
    required_proof_status = "proven-target",
    zero_surface_scan = true,
    clean_machine = true,
  },
}
