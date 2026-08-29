return {
  contract_version = "0.1.0-readiness.1",
  decision_refs = { "D-044", "D-045", "D-055", "D-056", "D-058" },

  forbidden_modules = {
    "web", "image", "audio", "transcription", "tts", "remote", "headless", "daemon",
    "mcp", "plugin", "hook", "skills-runtime", "subagent", "context-branch", "telemetry",
    "diagnostic-upload", "updater", "direct-http-tool", "undo", "backup", "restore", "plan-state",
  },
  forbidden_action_ids = {
    "serve-web", "listen", "daemon", "remote-control", "headless-run", "image-input", "audio-input",
    "transcribe", "speak", "telemetry", "diagnostic-upload", "check-update", "download-update",
    "install-update", "undo", "restore", "branch-context", "plan", "execute-plan", "direct-http",
  },
  forbidden_config_field_ids = {
    "Web.Enabled", "Web.Listen", "Media.Image", "Media.Audio", "Media.Transcription", "Media.TTS",
    "Remote.Enabled", "Headless.Enabled", "MCP.Enabled", "Plugin.Path", "Telemetry.Enabled",
    "Diagnostic.Upload", "Update.Endpoint", "Network.DirectHttp", "Network.DirectNetwork",
    "Permission.*.SensitiveRead", "Context.WorkspaceRoots", "Context.Branch", "Context.Undo",
    "Context.Backup", "Context.Restore", "Agent.PlanState",
  },
  forbidden_context_elements = {
    "WorkspaceRoots", "Branch", "Undo", "Backup", "Restore", "PlanArtifact", "TelemetryReceipt", "UpdateManifest",
  },
  forbidden_model_purposes = { "transcription", "tts", "image", "audio", "telemetry", "update", "remote-control" },
  forbidden_long_term_files = {
    "wal", "event-sidecar", "index-database", "standalone-log", "standalone-diagnostic-xml",
    "telemetry-spool", "update-manifest", "backup-history", "trash", "archive",
  },
  forbidden_package_components = {
    "http-listener", "browser-assets", "media-codec", "speech-runtime", "remote-controller",
    "plugin-loader", "mcp-client", "telemetry-client", "update-client",
  },

  design_reservations = {
    { id = "yaca-web", location = ".develope-docs/web-tracks", implementation_authorized = false },
    { id = "yaca-ie6", location = ".develope-docs/web-tracks", implementation_authorized = false },
  },
  web_directory_allowed_files = { "README.md" },
}
