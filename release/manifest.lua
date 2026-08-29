return {
  schema_version = "yaca-release-manifest-v0.1.0",
  product_version = "0.1.0-dev",
  release_state = "unqualified",
  release_authorized = false,

  layout = {
    lua_directory = "src",
    native_directory = "native",
    data_directory = "__yaca__",
    evidence_directory = "release/evidence",
  },

  lua_modules = {
    "backend_linux", "backend_windows", "cli", "clock", "compact", "config",
    "context", "diagnostics", "fs", "index", "ini", "json", "main", "model",
    "network", "path", "permission", "platform", "process", "prompt", "runtime",
    "safety", "session", "terminal", "text", "tools", "tui", "xml",
  },
  native_modules = { "yaca_native", "lxp" },
  native_module_filenames = {
    ["win32-x86"] = { yaca_native = "yaca_native.dll", lxp = "lxp.dll" },
    ["win64-x86_64"] = { yaca_native = "yaca_native.dll", lxp = "lxp.dll" },
    ["linux-x86_64"] = { yaca_native = "yaca_native.so", lxp = "lxp.so" },
  },

  load_policy = {
    source = "absolute-release-root-only",
    current_working_directory = false,
    lua_path = false,
    lua_cpath = false,
    lua_init = false,
    user_directories = false,
    system_directories = false,
    dynamic_extension_discovery = false,
  },

  targets = {
    { id = "win32-x86", os = "windows", arch = "x86", qualification = "pending" },
    { id = "win64-x86_64", os = "windows", arch = "x86_64", qualification = "pending" },
    { id = "linux-x86_64", os = "linux", arch = "x86_64", qualification = "pending" },
  },

  dependencies = {
    luainstaller = { version = "1.3.0", tag = "v1.3.0", commit = "97192d1", status = "source-pinned" },
    lua = { version = "5.5.1", sha256 = "1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce", status = "source-pinned" },
    expat = { version = "2.8.2", sha256 = "ef7d1994f533c9e7343d6c19f31064fc8ebbcbcaa144be3812b4f43052a05f4c", status = "source-pinned" },
    luaexpat = { version = "1.5.2", sha256 = "89d83f2141edec31be576425637216928221918fe95dc3854d1b7fd4c627213f", status = "source-pinned" },
    curl = { version = "target-lock-before-network-integration", status = "target-lock-pending" },
    ca_bundle = { version = "target-lock-before-network-integration", status = "target-lock-pending" },
    yaca_native = { version = "same-as-product", status = "implementation-pending" },
  },

  implementation_candidates = {
    status = "modern-proof-candidates-not-release-frozen",
    minimum_scannable_secret_bytes = 8,
    redirect_maximum = 3,
    retry = {
      identity = "tp006-modern-candidate-v1",
      default_count = 2,
      default_base_delay_ms = 500,
      maximum_count = 10,
      exponent = 2,
      maximum_delay_ms = 30000,
      runtime_wait_cap_ms = 60000,
      deterministic_jitter_permille = 100,
    },
  },

  unresolved_release_constants = {
    "all-runtime-hard-caps", "stuck-detector-thresholds", "curl-version-and-hash",
    "CA-version-and-hash", "process-cancel-grace", "event-poll-and-input-latency",
    "Context-size-and-commit-latency", "Catalog-scan-cap", "TUI-output-backlog-cap",
  },
}
