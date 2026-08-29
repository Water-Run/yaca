return {
  contract_version = "0.1.0-readiness.1",
  cases = {
    { id = "std-read-inside", profile = "Std", tool = "read", outside = false, expected = "allow" },
    { id = "std-read-outside", profile = "Std", tool = "read", outside = true, expected = "confirm" },
    { id = "readonly-read-inside", profile = "Readonly", tool = "read", outside = false, expected = "allow" },
    { id = "readonly-read-outside", profile = "Readonly", tool = "read", outside = true, expected = "deny" },
    { id = "std-write-inside", profile = "Std", tool = "write", outside = false, expected = "confirm" },
    { id = "readonly-write-inside", profile = "Readonly", tool = "write", outside = false, expected = "deny" },
    { id = "std-rename-inside", profile = "Std", tool = "rename", outside = false, expected = "confirm" },
    { id = "readonly-rename-inside", profile = "Readonly", tool = "rename", outside = false, expected = "deny" },
    { id = "std-exec-opaque", profile = "Std", tool = "exec", outside = true, expected = "confirm", note = "OutsideWorkspace does not pretend to sandbox shell" },
    { id = "readonly-exec-opaque", profile = "Readonly", tool = "exec", outside = true, expected = "deny" },
  },
}
