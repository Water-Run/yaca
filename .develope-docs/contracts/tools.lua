return {
  contract_version = "0.1.0-readiness.1",
  decision_refs = { "D-043", "D-052" },

  capabilities = { "Read", "Write", "Delete", "Shell", "OutsideWorkspace" },
  decisions = { "allow", "confirm", "deny" },
  decision_rank = { allow = 0, confirm = 1, deny = 2 },

  tools = {
    { id = "list", caps = { "Read" }, target_kind = "direct-path", mutates = false, high_risk_review = false },
    { id = "read", caps = { "Read" }, target_kind = "direct-path", mutates = false, high_risk_review = false },
    { id = "search", caps = { "Read" }, target_kind = "direct-path", mutates = false, high_risk_review = false },
    { id = "write", caps = { "Write" }, target_kind = "direct-path", mutates = true, high_risk_review = true },
    { id = "patch", caps = { "Write" }, target_kind = "direct-path", mutates = true, high_risk_review = true },
    { id = "rename", caps = { "Write", "Delete" }, target_kind = "direct-path", mutates = true, high_risk_review = true },
    { id = "delete", caps = { "Delete" }, target_kind = "direct-path", mutates = true, high_risk_review = true },
    { id = "exec", caps = { "Shell" }, target_kind = "opaque-command", mutates = "unknown", high_risk_review = true },
  },

  profiles = {
    { name = "Std", order = 1, Read = "allow", Write = "confirm", Delete = "confirm", Shell = "confirm", OutsideWorkspace = "confirm" },
    { name = "Readonly", order = 2, Read = "allow", Write = "deny", Delete = "deny", Shell = "deny", OutsideWorkspace = "deny" },
  },

  evaluation = {
    fold = "maximum-decision-rank",
    outside_direct_path_adds = "OutsideWorkspace",
    exec_uses_only = "Shell",
    exec_command_is_opaque = true,
    outside_workspace_is_shell_sandbox = false,
    deny_can_be_overridden_by_review_or_human = false,
    review_can_only_maintain_or_tighten = true,
  },

  approval_snapshot = {
    "tool-name-schema-version-registry-digest",
    "canonical-arguments",
    "canonical-target-expected-raw-digest-cwd",
    "permission-name-matrix-digest-config-generation",
    "effective-doublecheck-action-review",
    "workspace-root-identity",
    "operation-id-tool-call-id",
  },

  reserved_tree = {
    name = "__yaca__",
    generic_list_search_mutation = "hard-deny",
    exact_read = "context-and-safety-narrow-gate-only",
  },
}
