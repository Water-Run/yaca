return {
  contract_version = "0.1.0-readiness.1",
  width = 40,
  transcripts = {
    {
      id = "startup-plain", mode = "plain-tty",
      lines = {
        "yaca: Yet Another Coding Agent.",
        "version: 0.1.0",
        "work directory: C:\\Work\\demo",
        "config: valid",
        "context: new (not saved)",
        "model: Work",
        "permission: Std",
        "double check: on",
        "Run .status for details.",
        ">>",
      },
    },
    {
      id = "stream-redraw", mode = "native-editor",
      draft_before = "fix pars",
      lines = {
        ">> fix pars",
        "[ASSISTANT]",
        "I am checking the parser.",
        ">> fix pars",
      },
      draft_after = "fix pars",
      rule = "hide-output-redraw-draft-atomically",
    },
    {
      id = "approval", mode = "plain-tty",
      lines = {
        "[ACTION op-7]",
        "exec: make test",
        "cwd: C:\\Work\\demo",
        "allow 7 | deny 7 | details 7",
        "default: deny",
        "??",
      },
    },
    {
      id = "error", mode = "dumb-no-color",
      lines = {
        "[ERROR NetworkError]",
        "Model request failed.",
        "No automatic replay is safe.",
        "Run .details NetworkError.",
        ">>",
      },
    },
    {
      id = "compaction", mode = "plain-tty",
      lines = {
        "[STATUS]",
        "Compacting model view.",
        "[STATUS]",
        "Model view compacted.",
        ">>",
      },
    },
    {
      id = "plain-backlog", mode = "cooked-tty",
      draft_before = "keep this draft",
      lines = {
        ">> keep this draft",
        "[STATUS] output waiting",
        ">> keep this draft",
      },
      draft_after = "keep this draft",
      rule = "defer-output-until-safe-line",
    },
  },
}
