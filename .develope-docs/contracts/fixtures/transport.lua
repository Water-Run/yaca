return {
  contract_version = "0.1.0-readiness.1",
  environment_cases = {
    { id = "minimal", mode = "minimal", source = { "PATH", "HOME", "LUA_PATH", "HTTP_PROXY" }, kept = { "PATH", "HOME" }, removed = { "LUA_PATH", "HTTP_PROXY" } },
    { id = "inherit-filtered", mode = "inherit_filtered", source = { "PATH", "LANG", "LUA_INIT", "CURL_HOME", "CUSTOM" }, kept = { "PATH", "LANG", "CUSTOM" }, removed = { "LUA_INIT", "CURL_HOME" } },
  },
  retry_cases = {
    { id = "dns-before-event", cause = "dns", canonical_events = 0, automatic = true, maximum_attempts = 3 },
    { id = "connect-before-event", cause = "connect", canonical_events = 0, automatic = true, maximum_attempts = 3 },
    { id = "http-429-before-event", cause = "http-429", canonical_events = 0, automatic = true, maximum_attempts = 3 },
    { id = "http-503-before-event", cause = "http-503", canonical_events = 0, automatic = true, maximum_attempts = 3 },
    { id = "event-observed", cause = "connect", canonical_events = 1, automatic = false, maximum_attempts = 1 },
    { id = "tls-verification", cause = "tls-verification", canonical_events = 0, automatic = false, maximum_attempts = 1 },
    { id = "auth", cause = "auth-4xx", canonical_events = 0, automatic = false, maximum_attempts = 1 },
    { id = "protocol", cause = "protocol", canonical_events = 0, automatic = false, maximum_attempts = 1 },
    { id = "cancel", cause = "cancel", canonical_events = 0, automatic = false, maximum_attempts = 1 },
    { id = "unknown", cause = "outcome-unknown", canonical_events = 0, automatic = false, maximum_attempts = 1 },
  },
  redirect_cases = {
    { id = "same-origin-307", status = 307, from = "https://api.example/v1", to = "https://api.example/v2", automatic = true, key_reused = true },
    { id = "same-origin-308-effective-port", status = 308, from = "https://api.example:443/v1", to = "https://api.example/v2", automatic = true, key_reused = true },
    { id = "cross-origin", status = 307, from = "https://api.example/v1", to = "https://other.example/v2", automatic = false, key_reused = false },
    { id = "downgrade", status = 308, from = "https://api.example/v1", to = "http://api.example/v2", automatic = false, key_reused = false },
    { id = "status-302", status = 302, from = "https://api.example/v1", to = "https://api.example/v2", automatic = false, key_reused = false },
  },
  shell_cases = {
    { target = "windows", executable = "cmd.exe", fixed_arguments = { "/d", "/s", "/c" }, stdin = "closed" },
    { target = "linux", executable = "/bin/sh", fixed_arguments = { "-c" }, stdin = "closed" },
  },
}
