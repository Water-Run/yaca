local failures = {}
local assertion_count = 0
local notes = {}

local function check(condition, message)
  assertion_count = assertion_count + 1
  if not condition then failures[#failures + 1] = message end
end

local function note(message)
  notes[#notes + 1] = message
end

local script = (arg[0] or ""):gsub("\\", "/")
local root = script:match("^(.*)/%.tools/[^/]+$")
if not root or root == "" then root = "." end
local contract_dir = root .. "/.develope-docs/contracts"
local fixture_dir = contract_dir .. "/fixtures"

local function load_table(path)
  local chunk, load_error = loadfile(path)
  check(chunk ~= nil, "cannot load " .. path .. ": " .. tostring(load_error))
  if not chunk then return {} end
  local ok, value = pcall(chunk)
  check(ok, "contract raised while loading " .. path .. ": " .. tostring(value))
  check(ok and type(value) == "table", "contract did not return a table: " .. path)
  if not ok or type(value) ~= "table" then return {} end
  return value
end

local function load_contract(name)
  return load_table(contract_dir .. "/" .. name .. ".lua")
end

local function load_fixture(name)
  return load_table(fixture_dir .. "/" .. name .. ".lua")
end

local function value_list(records, key)
  local result = {}
  for _, record in ipairs(records or {}) do result[#result + 1] = key and record[key] or record end
  return result
end

local function as_set(values, label)
  local result = {}
  for _, value in ipairs(values or {}) do
    check(type(value) == "string" and value ~= "", label .. " contains a non-string or empty value")
    check(result[value] == nil, label .. " contains duplicate value " .. tostring(value))
    result[value] = true
  end
  return result
end

local function exact_set(label, actual_values, expected_values)
  local actual = as_set(actual_values, label)
  local expected = as_set(expected_values, label .. " expected")
  for value in pairs(expected) do check(actual[value], label .. " is missing " .. value) end
  for value in pairs(actual) do check(expected[value], label .. " has unexpected value " .. value) end
end

local function index_by(records, key, label)
  local result = {}
  for _, record in ipairs(records or {}) do
    local value = record[key]
    check(type(value) == "string" and value ~= "", label .. " record has invalid " .. key)
    check(result[value] == nil, label .. " has duplicate " .. tostring(value))
    result[value] = record
  end
  return result
end

local function list_has(values, wanted)
  for _, value in ipairs(values or {}) do if value == wanted then return true end end
  return false
end

local function maps_equal(label, left, right)
  for key, value in pairs(left or {}) do check(right and right[key] == value, label .. " differs at " .. tostring(key)) end
  for key, value in pairs(right or {}) do check(left and left[key] == value, label .. " has unexpected/mismatched " .. tostring(key)) end
end

local function read_all(path)
  local handle, open_error = io.open(path, "rb")
  check(handle ~= nil, "cannot read " .. path .. ": " .. tostring(open_error))
  if not handle then return "" end
  local bytes = handle:read("a")
  handle:close()
  return bytes
end

local function shell_quote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function command_ok(command)
  local ok = os.execute(command)
  return ok == true
end

local function sha256_bytes(value)
  local pipe = io.popen("printf %s " .. shell_quote(value) .. " | sha256sum", "r")
  check(pipe ~= nil, "cannot run sha256sum")
  if not pipe then return nil end
  local line = pipe:read("l") or ""
  pipe:close()
  return line:match("^([0-9a-f]+)")
end

local function json_syntax_ok(value)
  local python = "import json,sys; json.load(sys.stdin)"
  return command_ok("printf %s " .. shell_quote(value) .. " | python3 -c " .. shell_quote(python) .. " >/dev/null 2>&1")
end

local function keys_of(value)
  local result = {}
  for key in pairs(value or {}) do result[#result + 1] = key end
  return result
end

local function list_files(directory, name_pattern)
  local command = "find " .. shell_quote(directory) .. " -maxdepth 1 -type f -name " .. shell_quote(name_pattern) .. " -printf '%f\\n' 2>/dev/null"
  local pipe = io.popen(command, "r")
  check(pipe ~= nil, "cannot enumerate " .. directory)
  if not pipe then return {} end
  local result = {}
  for line in pipe:lines() do result[#result + 1] = line end
  pipe:close()
  table.sort(result)
  return result
end

local product = load_contract("product")
local config = load_contract("config")
local runtime = load_contract("runtime")
local actions = load_contract("actions")
local tools = load_contract("tools")
local model = load_contract("model")
local context = load_contract("context")
local tui = load_contract("tui")
local platform = load_contract("platform")
local diagnostics = load_contract("diagnostics")
local zero_surface = load_contract("zero_surface")
local formats = load_contract("formats")
local transport = load_contract("transport")
local prompts = load_contract("prompts")
local release = load_contract("release")
local readiness = load_contract("readiness")

local argv_fixture = load_fixture("argv")
local permission_fixture = load_fixture("permission")
local agentloop_fixture = load_fixture("agentloop")
local model_fixture = load_fixture("model-events")
local context_fixture = load_fixture("context-events")
local config_fixture = load_fixture("config")
local path_fixture = load_fixture("path")
local formats_fixture = load_fixture("formats")
local transport_fixture = load_fixture("transport")
local prompts_fixture = load_fixture("prompts")
local tui_fixture = load_fixture("tui-transcripts")
local wire_fixture = load_fixture("wire")
local proof_manifest = load_table(root .. "/.develope-docs/proofs/modern-2026-08-29/manifest.lua")

local all_versioned = {
  product, config, runtime, actions, tools, model, context, tui, platform, diagnostics, zero_surface,
  formats, transport, prompts, release, readiness,
  argv_fixture, permission_fixture, agentloop_fixture, model_fixture, context_fixture, config_fixture,
  path_fixture, formats_fixture, transport_fixture, prompts_fixture, tui_fixture, wire_fixture,
}
for index, value in ipairs(all_versioned) do
  check(value.contract_version == "0.1.0-readiness.1", "contract/fixture " .. index .. " has a mismatched contract version")
end

-- Product and release shape.
exact_set("release target ids", value_list(product.release_targets, "id"), { "win32-x86", "win64-x86_64", "linux-x86_64" })
exact_set("platform target ids", platform.target_ids, value_list(product.release_targets, "id"))
exact_set("durable fact sources", product.product and product.product.durable_fact_sources or {}, { "main-ini", "context-xml" })
exact_set("product journeys", value_list(product.journeys, "id"), {
  "download-install-bootstrap", "configure-and-self-test", "new-context-main-turn",
  "continue-and-manage-context", "cancel-exit-crash-recovery", "release-qualification",
})
for _, target in ipairs(product.release_targets or {}) do
  check(target.qualification == "independent-full-matrix", "target " .. tostring(target.id) .. " is not independently qualified")
  check(list_has(target.required_root_entries, target.executable), "target " .. tostring(target.id) .. " package omits its executable")
  check(list_has(target.required_root_entries, target.installer), "target " .. tostring(target.id) .. " package omits its installer")
end
check(product.package_invariants and product.package_invariants.system_lua_dependency == false, "release must not depend on system Lua")
check(product.package_invariants and product.package_invariants.data_root == "executable-directory/__yaca__", "data root must remain executable-adjacent")

-- Release lock, proof pins and implementation module boundary.
exact_set("release packaging targets", release.packaging and release.packaging.targets or {}, value_list(product.release_targets, "id"))
check(release.packaging and release.packaging.luainstaller and release.packaging.luainstaller.version == "1.3.0", "luainstaller version must remain 1.3.0")
check(release.packaging and release.packaging.luainstaller and release.packaging.luainstaller.tag == "v1.3.0" and release.packaging.luainstaller.commit == "97192d1", "luainstaller tag/commit drifted")
check(release.packaging and release.packaging.source_implementation_may_begin_before_target_qualification == true, "source implementation must not be circularly blocked by final qualification")
check(release.packaging and release.packaging.target_failure_blocks_release == true, "target qualification failure must block release")
for _, name in ipairs({ "lua", "expat", "luaexpat" }) do
  local locked = release.dependency_lock and release.dependency_lock[name]
  local proven = proof_manifest.source_pins and proof_manifest.source_pins[name]
  check(locked and proven and locked.version == proven.version, name .. " release/proof version drifted")
  check(locked and proven and locked.sha256 == proven.sha256, name .. " release/proof SHA-256 drifted")
end
exact_set("planned Lua module allowlist", release.planned_lua_modules, platform.safe_loading and platform.safe_loading.planned_lua_module_allowlist or {})
exact_set("release Lua module allowlist", release.planned_lua_modules, platform.safe_loading and platform.safe_loading.lua_module_allowlist or {})
exact_set("native module allowlist", platform.safe_loading and platform.safe_loading.native_module_allowlist or {}, { "yaca_native", "lxp" })
local tp006
for _, proof in ipairs(proof_manifest.proofs or {}) do if proof.id == "TP-006" then tp006 = proof end end
check(tp006 ~= nil, "proof manifest omits TP-006 candidate evidence")
check(release.implementation_candidates and tp006 and release.implementation_candidates.minimum_scannable_secret_bytes == tp006.candidates_not_release_frozen.minimum_scannable_secret_bytes, "minimum scannable secret candidate drifted")
check(release.implementation_candidates and release.implementation_candidates.retry and tp006 and release.implementation_candidates.retry.identity == tp006.candidates_not_release_frozen.retry_manifest, "retry candidate identity drifted")
check(release.implementation_candidates and release.implementation_candidates.status == "modern-proof-candidates-not-release-frozen", "implementation candidates must not be marked release-frozen")

-- Phase-separated readiness and executable implementation graph.
check(readiness.gates and readiness.gates.A and readiness.gates.A.status == "passed", "Gate A must be explicitly audited passed")
check(readiness.gates and readiness.gates.B and readiness.gates.B.status == "passed", "Gate B must be explicitly planned passed")
check(readiness.gates and readiness.gates.R and readiness.gates.R.status == "closed" and readiness.gates.R.release_authorized == false, "Release Gate R must remain closed")
exact_set("release-gate pending targets", readiness.gates and readiness.gates.R and readiness.gates.R.pending_targets or {}, value_list(product.release_targets, "id"))
check(readiness.source_start and readiness.source_start.authorized_after_this_contract_and_validators_commit == true, "source-start authorization is not explicit")
local implementation_phase = readiness.source_start and readiness.source_start.implementation_phase
local implementation_phase_set = as_set(readiness.source_start and readiness.source_start.allowed_implementation_phases or {}, "implementation phases")
check(implementation_phase_set[implementation_phase], "source implementation phase is invalid")
check(readiness.source_start and readiness.source_start.source_is_currently_skeleton_only == (implementation_phase == "pre-coding"), "skeleton flag disagrees with implementation phase")
check(readiness.source_start and readiness.source_start.release_is_not_authorized == true, "source/release phase boundary drifted")
local transition_by_from = {}
for _, transition in ipairs(readiness.source_start and readiness.source_start.transitions or {}) do
  check(implementation_phase_set[transition.from] and implementation_phase_set[transition.to], "implementation transition has an invalid phase")
  check(transition_by_from[transition.from] == nil, "implementation phase has multiple transitions: " .. tostring(transition.from))
  transition_by_from[transition.from] = transition
end
local expected_gate_ids = {}
for index = 1, 16 do expected_gate_ids[#expected_gate_ids + 1] = string.format("AR-P0-%02d", index) end
for index = 1, 12 do expected_gate_ids[#expected_gate_ids + 1] = string.format("AR-P1-%02d", index) end
exact_set("Gate A audit item ids", value_list(readiness.gate_a_items, "id"), expected_gate_ids)
local readiness_task_by_id = index_by(readiness.tasks, "id", "implementation tasks")
for _, transition in pairs(transition_by_from) do check(readiness_task_by_id[transition.task] ~= nil, "implementation transition routes to unknown task: " .. tostring(transition.task)) end
for _, item in ipairs(readiness.gate_a_items or {}) do
  check(item.status == "plan-ready" or item.status == "qualification-bound", "Gate A item has invalid phase status: " .. tostring(item.id))
  check(type(item.artifact) == "string" and item.artifact ~= "", "Gate A item has no authority artifact: " .. tostring(item.id))
  check(type(item.proof) == "string" and item.proof ~= "", "Gate A item has no proof disposition: " .. tostring(item.id))
  check(readiness_task_by_id[item.implementation_task] ~= nil, "Gate A item has no implementation task: " .. tostring(item.id))
  check(type(item.hard_gate) == "string" and item.hard_gate ~= "", "Gate A item has no hard gate: " .. tostring(item.id))
end
local expected_milestones = {}
for index = 0, 10 do expected_milestones[#expected_milestones + 1] = "M" .. index end
exact_set("implementation milestone ids", value_list(readiness.milestones, "id"), expected_milestones)
local milestone_by_id = index_by(readiness.milestones, "id", "implementation milestones")
local milestone_task_ids = {}
for _, milestone in ipairs(readiness.milestones or {}) do
  check(type(milestone.name) == "string" and milestone.name ~= "", "implementation milestone has no name: " .. tostring(milestone.id))
  for _, task_id in ipairs(milestone.tasks or {}) do
    check(milestone_task_ids[task_id] == nil, "implementation task appears in multiple milestones: " .. tostring(task_id))
    milestone_task_ids[task_id] = true
    check(readiness_task_by_id[task_id] ~= nil, "milestone references unknown task: " .. tostring(task_id))
  end
end
local planned_module_coverage = {}
for _, implementation_task in ipairs(readiness.tasks or {}) do
  check(milestone_by_id[implementation_task.milestone] ~= nil, "task references unknown milestone: " .. tostring(implementation_task.id))
  check(milestone_task_ids[implementation_task.id] == true, "task is absent from milestone task list: " .. tostring(implementation_task.id))
  check(type(implementation_task.files) == "table" and #implementation_task.files > 0, "task has no file boundary: " .. tostring(implementation_task.id))
  check(type(implementation_task.tests) == "table" and #implementation_task.tests > 0, "task has no test boundary: " .. tostring(implementation_task.id))
  check(type(implementation_task.commit) == "string" and implementation_task.commit:match("^[a-z]+: "), "task has no conventional commit boundary: " .. tostring(implementation_task.id))
  local task_number = tonumber(implementation_task.id:match("^C(%d+)$"))
  check(task_number ~= nil, "invalid task id: " .. tostring(implementation_task.id))
  for _, dependency_id in ipairs(implementation_task.depends or {}) do
    local dependency = readiness_task_by_id[dependency_id]
    check(dependency ~= nil, "task has unknown dependency: " .. tostring(implementation_task.id) .. " -> " .. tostring(dependency_id))
    local dependency_number = tonumber(tostring(dependency_id):match("^C(%d+)$"))
    check(task_number and dependency_number and dependency_number < task_number, "task dependency is cyclic or forward: " .. tostring(implementation_task.id) .. " -> " .. tostring(dependency_id))
  end
  for _, file in ipairs(implementation_task.files or {}) do
    local module_id = file:match("^src/([a-z_]+)%.lua$")
    if module_id then planned_module_coverage[module_id] = true end
  end
end
exact_set("implementation task ids", keys_of(readiness_task_by_id), (function()
  local result = {}
  for index = 1, 34 do result[#result + 1] = string.format("C%02d", index) end
  return result
end)())
for _, module_id in ipairs(release.planned_lua_modules or {}) do check(planned_module_coverage[module_id], "implementation plan does not own src/" .. module_id .. ".lua") end
check(readiness.gates.B.first_task == "C01" and readiness.source_start.first_task == "C01", "first coding task must be C01")

-- Exact configuration catalog and selected-decision conflict repairs.
local expected_config_fields = {
  "General.SchemaVersion", "Global.SystemPrompt", "General.StartupSelfTest", "General.LogLevel",
  "TUI.StartupShowSlogan", "TUI.StartupShowVersion", "TUI.StartupShowWorkDir", "TUI.StartupShowDataRoot",
  "TUI.StartupShowConfigStatus", "TUI.StartupShowContext", "TUI.StartupShowContextHash", "TUI.StartupShowModel",
  "TUI.StartupShowPermission", "TUI.StartupShowDoubleCheck", "TUI.StartupShowStatusHint",
  "Agent.DoubleCheck", "Agent.DoubleCheckGoal", "Agent.ActionReviewEnabled", "Agent.ActionReviewModel",
  "Agent.TerminationReviewModel", "Agent.QueueMaxItems", "Agent.CompactThreshold", "Agent.MaxTurnModelRequests", "Agent.MaxTurnToolCalls",
  "Network.FollowProxy", "Network.ProxyUrl", "Network.NoProxy", "Network.CaBundlePath", "Network.ConnectTimeoutMs", "Network.MaxResponseBytes",
  "Exec.TimeoutMs", "Exec.MaxOutputKB", "Exec.EnvironmentMode",
  "Context.AutoNameEveryMainTurns", "Context.ListSortBy", "Context.ListSortDirection", "Context.RecentListLimit",
  "Permission.*.Description", "Permission.*.SystemPrompt", "Permission.*.Read", "Permission.*.Write", "Permission.*.Delete", "Permission.*.Shell", "Permission.*.OutsideWorkspace",
  "Model.*.Enabled", "Model.*.Description", "Model.*.Protocol", "Model.*.Endpoint", "Model.*.RemoteModel", "Model.*.Key", "Model.*.SystemPrompt",
  "Model.*.ContextLength", "Model.*.MaxOutputTokens", "Model.*.Streaming", "Model.*.RequestTimeoutMs", "Model.*.RetryCount", "Model.*.RetryBaseDelayMs",
  "Model.*.ToolsEnabled", "Model.*.AdapterOptions",
}
local config_by_id = index_by(config.fields, "id", "config fields")
exact_set("config field ids", value_list(config.fields, "id"), expected_config_fields)
local physical_keys = {}
for _, field in ipairs(config.fields or {}) do
  local physical = tostring(field.section) .. "." .. tostring(field.key)
  check(not physical_keys[physical], "duplicate physical config field " .. physical)
  physical_keys[physical] = true
end
check(config_by_id["Global.SystemPrompt"] and config_by_id["Global.SystemPrompt"].section == "General" and config_by_id["Global.SystemPrompt"].key == "SystemPrompt", "Global.SystemPrompt must map to physical General.SystemPrompt")
check(config_by_id["General.LogLevel"] ~= nil, "selected M05-17 requires General.LogLevel")
check(config_by_id["Agent.StuckNoProgressRounds"] == nil, "AL06-50=A forbids Agent.StuckNoProgressRounds")
check(config_by_id["Context.CompactThresholdOverride"] == nil, "M05-06=A forbids Context.CompactThresholdOverride")
check(config_by_id["Agent.CompactThreshold"] and config_by_id["Agent.CompactThreshold"].context_override == false, "CompactThreshold must be INI-only")
exact_set("Context XML whitelist", value_list(config.context_xml_whitelist, "id"), {
  "CurrentModel", "CurrentPermission", "DoubleCheckOverride", "DoubleCheckGoalOverride", "ContextPrompt", "AutoRenameDisabled",
})
for _, forbidden in ipairs(config.forbidden_field_ids or {}) do check(config_by_id[forbidden] == nil, "forbidden config field is active: " .. forbidden) end
check(config.stuck_detector and #config.stuck_detector.ini_fields == 0 and #config.stuck_detector.context_fields == 0, "stuck thresholds must have zero INI/XML fields")
check(config.ini_grammar and config.ini_grammar.text_value_form == "double-quoted" and config.ini_grammar.canonical_newline_escape == "\\n", "M05-07=A requires quoted text with canonical newline escape")
check(config.ini_grammar and config.ini_grammar.triple_quote == false and config.ini_grammar.continuation_line == false, "INI grammar must not accept alternate multiline dialects")

-- Canonical format, path/hash and carrier vectors.
check(formats.utf8 and formats.utf8.replacement_on_error == false and formats.utf8.normalization == "none-preserve-exact-scalar-sequence", "UTF-8 must be strict and normalization-free")
check(formats.sha256 and formats.sha256.algorithm == "SHA-256", "canonical digest algorithm must be SHA-256")
check(formats.sha256 and formats.sha256.context_hash and formats.sha256.context_hash.output == "16-uppercase-hex", "Context hash shape drifted")
check(formats.sha256 and formats.sha256.context_hash and formats.sha256.context_hash.aliases_after_path_change == false, "path changes must not retain hash aliases")
check(formats.json and formats.json.profile == "RFC-8259-strict-subset" and formats.json.duplicate_object_key == "error-before-schema-use", "strict JSON profile drifted")
check(formats.sse and formats.sse.eof_with_unterminated_event == "protocol-error-incomplete", "unterminated SSE must fail incomplete")
check(formats.xml and formats.xml.dtd == "hard-reject-registered-callback" and formats.xml.external_entity == "hard-reject-without-open", "XML entity boundary drifted")

exact_set("path hash vector ids", value_list(path_fixture.hash_vectors, "id"), {
  "windows-drive-lower", "windows-drive-case-preserved", "posix-root", "windows-unc", "rename-invalidates-old", "rebind-invalidates-old",
})
local path_hashes = {}
for _, vector in ipairs(path_fixture.hash_vectors or {}) do
  local digest = sha256_bytes(vector.logical_path)
  check(digest == vector.full_sha256, "path hash full digest drifted: " .. tostring(vector.id))
  check(vector.context_hash == (digest and digest:sub(1, 16):upper()), "path Context hash extraction drifted: " .. tostring(vector.id))
  check(type(vector.context_hash) == "string" and vector.context_hash:match("^[0-9A-F]+$") and #vector.context_hash == 16, "path Context hash shape invalid: " .. tostring(vector.id))
  check(path_hashes[vector.context_hash] == nil, "path fixture accidentally collides: " .. tostring(vector.id))
  path_hashes[vector.context_hash] = true
end
local path_case_by_id = index_by(path_fixture.codec_cases, "id", "path codec cases")
check(path_case_by_id["drive"] and path_case_by_id["drive"].logical_path == "/C/work/a.xml", "drive codec fixture drifted")
check(path_case_by_id["unc"] and path_case_by_id["unc"].logical_path == "/UNC/server/share/t.xml", "UNC codec fixture drifted")
check(path_case_by_id["dotdot-escape"] and path_case_by_id["dotdot-escape"].error_id == "PathEscapesWorkspace", "path escape fixture must fail closed")
for _, case in ipairs(path_fixture.selector_cases or {}) do
  if case.kind == "hash" then
    check(#case.token == 16 and case.token:match("^[0-9A-Fa-f]+$") ~= nil, "hash selector fixture has invalid source shape")
    check(case.canonical == case.token:upper(), "hash selector fixture normalization drifted")
  else
    check(not (#case.token == 16 and case.token:match("^[0-9A-Fa-f]+$")), "name selector fixture accidentally has hash shape")
  end
end

exact_set("UTF-8 fixture ids", value_list(formats_fixture.utf8_cases, "id"), {
  "ascii", "cjk", "highest-scalar", "overlong", "truncated", "isolated-continuation", "surrogate", "above-maximum",
})
for _, case in ipairs(formats_fixture.utf8_cases or {}) do
  local ok, length = pcall(utf8.len, case.bytes)
  local valid = ok and length ~= nil
  check(valid == case.valid, "UTF-8 fixture oracle mismatch: " .. tostring(case.id))
end
exact_set("JSON fixture ids", value_list(formats_fixture.json_cases, "id"), {
  "object", "array", "paired-surrogate", "top-string", "duplicate-key", "bom", "nan", "unpaired-surrogate", "control",
})
for _, case in ipairs(formats_fixture.json_cases or {}) do
  check(type(case.bytes) == "string" and #case.bytes > 0, "JSON fixture has no exact bytes: " .. tostring(case.id))
  check(case.valid == true or (case.valid == false and type(case.error) == "string"), "JSON fixture lacks a deterministic result: " .. tostring(case.id))
end
exact_set("SSE fixture ids", value_list(formats_fixture.sse_cases, "id"), { "one-data", "multi-data-crlf", "comments-and-unknown", "retry-ignored", "unterminated", "bom" })
for _, case in ipairs(formats_fixture.sse_cases or {}) do
  check(type(case.bytes) == "string" and #case.bytes > 0, "SSE fixture has no exact bytes: " .. tostring(case.id))
  if case.valid then check(type(case.dispatch) == "table" and #case.dispatch > 0, "valid SSE fixture has no dispatch: " .. tostring(case.id)) end
end
local xml_case_by_id = index_by(formats_fixture.xml_text_cases, "id", "XML text carrier cases")
check(xml_case_by_id["cr-forces-binary-carrier"] and xml_case_by_id["cr-forces-binary-carrier"].representation == "base64", "XML CR must use typed base64 to preserve bytes")
check(xml_case_by_id["binary-nul"] and xml_case_by_id["binary-nul"].representation == "base64", "XML NUL must use typed base64")
check(xml_case_by_id["invalid-utf8"] and xml_case_by_id["invalid-utf8"].representation == "base64", "invalid UTF-8 must use typed base64")
check(xml_case_by_id["present-empty"] and xml_case_by_id["present-empty"].present == true, "present empty XML value drifted")
check(xml_case_by_id["missing"] and xml_case_by_id["missing"].present == false, "missing XML value drifted")

-- Runtime state and transition truth.
local expected_states = {
  "Idle", "Preparing", "RequestingModel", "Streaming", "DispatchingTools", "AwaitingApproval",
  "ExecutingTool", "EvaluatingAction", "EvaluatingTermination", "WaitingUser", "Finalizing", "Closing",
}
local expected_outcomes = {
  "completed", "waiting_user", "refused", "cancelled", "budget_exhausted", "stuck", "partial", "error", "unknown_side_effect",
}
local expected_identities = {
  "Process", "ActiveContext", "Turn", "LogicalRequest", "Attempt", "ToolCall", "Operation", "QueueItem", "ConfigGeneration",
}
exact_set("runtime states", runtime.states, expected_states)
exact_set("runtime outcomes", runtime.outcomes, expected_outcomes)
exact_set("runtime identities", runtime.identities, expected_identities)
exact_set("runtime controls", value_list(runtime.controls, "id"), { "finish", "ask-user", "refuse" })
local state_set = as_set(runtime.states, "runtime state set")
local outcome_set = as_set(runtime.outcomes, "runtime outcome set")
local transition_pairs = {}
for _, transition in ipairs(runtime.transitions or {}) do
  check(state_set[transition.from], "transition has unknown source state " .. tostring(transition.from))
  check(state_set[transition.to], "transition has unknown target state " .. tostring(transition.to))
  local key = tostring(transition.from) .. "\0" .. tostring(transition.to)
  transition_pairs[key] = true
end
check(runtime.stuck_detector and #runtime.stuck_detector.user_config_fields == 0 and #runtime.stuck_detector.context_override_fields == 0, "runtime stuck detector must not expose user thresholds")
check(runtime.hard_caps and runtime.hard_caps.unlimited_sentinel == false and runtime.hard_caps.user_may_only_tighten == true, "runtime hard caps must be mandatory and tighten-only")

-- Semantic actions and all local command-line projections.
local expected_actions = {
  "run-chat", "help", "version", "self-test", "model-repl", "config-repl", "context-repl", "continue", "export-context", "status",
  "queue-add", "queue-list", "queue-delete", "queue-move", "queue-edit", "queue-clear", "steer", "side", "multiline", "cancel", "cautious",
  "select-model", "select-context", "status-chat", "help-chat", "details", "prompt-edit", "compact-manual", "quit",
  "context-list", "context-inspect", "context-search", "context-rename", "context-rebind", "context-delete",
  "context-set-auto-rename-disabled", "context-import", "context-repair", "context-refresh",
}
local action_by_id = index_by(actions.actions, "id", "actions")
exact_set("semantic action ids", value_list(actions.actions, "id"), expected_actions)
maps_equal("exit classes actions/diagnostics", actions.exit_classes, diagnostics.exit_classes)
local argv_aliases, chat_commands, context_commands = {}, {}, {}
local special_states = { ["pre-runtime"] = true, repl = true }
for _, action in ipairs(actions.actions or {}) do
  check(type(action.projections) == "table" and #action.projections > 0, "action has no projection: " .. tostring(action.id))
  local has_local_line = false
  local arg_names = {}
  for _, argument in ipairs(action.args or {}) do
    check(not arg_names[argument.name], "action " .. action.id .. " repeats argument " .. tostring(argument.name))
    arg_names[argument.name] = true
  end
  for _, projection in ipairs(action.projections or {}) do
    check(projection.kind == "argv" or projection.kind == "chat-line" or projection.kind == "context-repl-line", "unknown projection kind on " .. action.id)
    if projection.kind == "argv" then
      has_local_line = true
      for _, alias in ipairs({ projection.long, projection.short, projection.slash }) do
        if alias then
          check(not argv_aliases[alias], "argv alias collision: " .. tostring(alias))
          argv_aliases[alias] = action.id
        end
      end
      if projection.short and projection.slash then check(projection.slash == "/" .. projection.short:sub(2), "slash alias must share the short-name stem for " .. action.id) end
    elseif projection.kind == "chat-line" then
      has_local_line = true
      check(not chat_commands[projection.command], "duplicate chat command " .. tostring(projection.command))
      chat_commands[projection.command] = action.id
      check(not projection.command:find("%.immidiate", 1, false), "legacy .immidiate is registered")
    elseif projection.kind == "context-repl-line" then
      has_local_line = true
      check(not context_commands[projection.command], "duplicate context REPL command " .. tostring(projection.command))
      context_commands[projection.command] = action.id
    end
  end
  check(has_local_line, "action has no local CLI projection: " .. action.id)
  if action.tty == "any" then
    check(action.id == "help" or action.id == "version" or action.id == "self-test", "TU-13 permits non-TTY only for help/version/static self-test: " .. action.id)
    if action.id == "self-test" then check(action.non_tty == "through-stage-1-offline-only", "non-TTY self-test must remain offline Stage 1") else check(action.non_tty == "allowed", "non-TTY static action lacks explicit admission: " .. action.id) end
  end
  for _, allowed_state in ipairs(action.allowed_states or {}) do check(state_set[allowed_state] or special_states[allowed_state], "action " .. action.id .. " references unknown state " .. tostring(allowed_state)) end
end
check(argv_aliases["-dc"] == nil and argv_aliases["-rc"] == nil, "removed conflicting aliases must stay absent")
check(actions.parser and #actions.parser.legacy_aliases == 0, "legacy aliases must be empty")
check(argv_aliases["--self-test"] == "self-test" and argv_aliases["-st"] == "self-test" and argv_aliases["/st"] == "self-test", "self-test aliases drifted")
exact_set("global argv modifiers", actions.parser and actions.parser.global_modifiers or {}, { "--machine" })
check(actions.parser and actions.parser.machine_modifier_consumes_primary_action == false, "--machine must remain a modifier")
exact_set("machine-supported actions", actions.machine_output and actions.machine_output.supported_actions or {}, { "help", "version", "self-test" })
check(actions.machine_output and actions.machine_output.selection == "explicit-double-dash-machine-only-never-by-redirection", "redirection must not implicitly select machine output")
exact_set("single machine record fields", actions.machine_output and actions.machine_output.single_result and actions.machine_output.single_result.required_fields or {}, { "schema_version", "kind", "outcome" })
exact_set("stream machine record fields", actions.machine_output and actions.machine_output.stream and actions.machine_output.stream.required_fields or {}, { "schema_version", "kind", "sequence", "final" })
exact_set("final machine record fields", actions.machine_output and actions.machine_output.stream and actions.machine_output.stream.final_record_requires or {}, { "outcome" })
check(actions.machine_output and actions.machine_output.ansi == false and actions.machine_output.stdin == "never-read-in-v0.1", "machine mode must have no ANSI or stdin ownership")
local fd_case_by_id = index_by(actions.fd_mode_matrix and actions.fd_mode_matrix.cases or {}, "id", "fd mode cases")
exact_set("fd capability facts", actions.fd_mode_matrix and actions.fd_mode_matrix.facts or {}, { "stdin_is_tty", "stdout_is_tty", "stderr_is_tty", "machine_requested" })
check(fd_case_by_id.interactive and fd_case_by_id.interactive.result == "human-interactive", "interactive fd gate drifted")
check(fd_case_by_id["interactive-stdout-redirected"] and fd_case_by_id["interactive-stdout-redirected"].result == "TtyRequired", "redirected interactive stdout must fail closed")
check(fd_case_by_id["machine-supported"] and fd_case_by_id["machine-supported"].result == "machine-json-or-jsonl", "explicit machine fd projection drifted")
check(fd_case_by_id["machine-unsupported"] and fd_case_by_id["machine-unsupported"].result == "UsageError", "unsupported machine action must be a usage error")

-- TUI is a projection of the same runtime/action contracts.
local tui_state_keys = {}
for state, input_state in pairs(tui.runtime_state_projection or {}) do
  tui_state_keys[#tui_state_keys + 1] = state
  check(list_has(tui.input_states, input_state), "TUI maps " .. state .. " to unknown input state " .. tostring(input_state))
end
exact_set("TUI runtime state projection", tui_state_keys, runtime.states)
for _, binding in ipairs(tui.input_bindings or {}) do check(action_by_id[binding.fallback_action] ~= nil, "TUI fallback references unknown action " .. tostring(binding.fallback_action)) end
check(tui.prompts and tui.prompts.chat.text == ">>" and tui.prompts.approval.text == "??", "canonical TUI prompts drifted")
check(tui.output and tui.output.startup_master_switch == false, "TUI must not add a startup master switch")
check(tui.output and tui.output.interactive_gate == "stdin-and-stdout-are-tty-and-machine-not-requested", "TUI interactive gate drifted")
check(tui.output and tui.output.program_chrome == "ASCII-only" and tui.output.untrusted_control_bytes == "escape-before-render", "TUI chrome/injection boundary drifted")
check(tui.line_editor and tui.line_editor.draft_is_runtime_owned == true and tui.line_editor.character_level_interleave == false, "TUI must own and protect the draft")
check(tui.line_editor and tui.line_editor.plain_mode_semantics_equal == true, "plain TUI must retain domain semantics")
check(tui.terminal_modes and tui.terminal_modes.windows_xp_ansi_assumed == false, "Windows XP must not assume ANSI")
exact_set("TUI transcript ids", value_list(tui_fixture.transcripts, "id"), { "startup-plain", "stream-redraw", "approval", "error", "compaction", "plain-backlog" })
check(tui_fixture.width == 40, "TUI narrow transcript width must remain 40")
for _, transcript in ipairs(tui_fixture.transcripts or {}) do
  check(type(transcript.lines) == "table" and #transcript.lines > 0, "TUI transcript has no lines: " .. tostring(transcript.id))
  for line_number, line in ipairs(transcript.lines or {}) do
    check(type(line) == "string" and line:match("^[%z\1-\127]*$") ~= nil, "TUI fixture chrome must be ASCII: " .. tostring(transcript.id) .. "/" .. line_number)
    check(#line <= tui_fixture.width, "TUI fixture exceeds 40 columns: " .. tostring(transcript.id) .. "/" .. line_number)
  end
  if transcript.draft_before then check(transcript.draft_after == transcript.draft_before, "TUI redraw changed draft: " .. tostring(transcript.id)) end
end

-- Tool and permission matrix, including executable fixtures.
exact_set("tool ids", value_list(tools.tools, "id"), { "list", "read", "search", "write", "patch", "rename", "delete", "exec" })
exact_set("permission capabilities", tools.capabilities, { "Read", "Write", "Delete", "Shell", "OutsideWorkspace" })
exact_set("permission decisions", tools.decisions, { "allow", "confirm", "deny" })
local tool_by_id = index_by(tools.tools, "id", "tools")
local capability_set = as_set(tools.capabilities, "capability set")
for _, tool in ipairs(tools.tools or {}) do for _, capability in ipairs(tool.caps or {}) do check(capability_set[capability], "tool " .. tool.id .. " uses unknown capability " .. tostring(capability)) end end
local profile_by_name = index_by(tools.profiles, "name", "tool permission profiles")
local config_profile_by_name = index_by(config.release_permission_profiles, "name", "config permission profiles")
exact_set("release permission profile names", value_list(tools.profiles, "name"), { "Std", "Readonly" })
for name, profile in pairs(profile_by_name) do
  local config_profile = config_profile_by_name[name]
  check(config_profile ~= nil, "config omits permission profile " .. name)
  for _, capability in ipairs(tools.capabilities or {}) do check(config_profile and config_profile[capability] == profile[capability], "profile matrix drift for " .. name .. "." .. capability) end
end
local function evaluate_permission(profile_name, tool_name, outside)
  local profile = profile_by_name[profile_name]
  local tool = tool_by_id[tool_name]
  if not profile or not tool then return nil end
  local required = {}
  for _, capability in ipairs(tool.caps or {}) do required[#required + 1] = capability end
  if outside and tool.target_kind == "direct-path" then required[#required + 1] = "OutsideWorkspace" end
  local winner, winner_rank = "allow", tools.decision_rank.allow
  for _, capability in ipairs(required) do
    local decision = profile[capability]
    local rank = tools.decision_rank[decision]
    if rank and rank > winner_rank then winner, winner_rank = decision, rank end
  end
  return winner
end
for _, case in ipairs(permission_fixture.cases or {}) do
  check(evaluate_permission(case.profile, case.tool, case.outside) == case.expected, "permission fixture failed: " .. tostring(case.id))
end

-- Canonical Model schema and Runtime control crosswalk.
exact_set("model protocols", value_list(model.protocols, "id"), { "openai-chat", "anthropic-messages" })
exact_set("model purposes", model.purposes, { "main", "side", "action-review", "termination-review", "compaction", "self-test", "context-name" })
exact_set("model event kinds", value_list(model.event_kinds, "id"), {
  "response_start", "text_delta", "reasoning_summary_delta", "tool_call_start", "tool_arguments_delta", "tool_call_complete",
  "control", "usage_update", "response_finish", "transport_error", "protocol_error",
})
exact_set("model finish classes", model.finish_classes, { "stop", "length", "content_filter", "refusal", "tool_calls", "cancelled", "incomplete" })
exact_set("model controls", value_list(model.controls, "id"), value_list(runtime.controls, "id"))
local model_event_by_id = index_by(model.event_kinds, "id", "model events")
local model_control_by_id = index_by(model.controls, "id", "model controls")
local runtime_control_by_id = index_by(runtime.controls, "id", "runtime controls")
for id, control in pairs(model_control_by_id) do
  local runtime_control = runtime_control_by_id[id]
  exact_set("control required payload " .. id, control.required_payload, runtime_control and runtime_control.required_payload or {})
  exact_set("control optional payload " .. id, control.optional_payload, runtime_control and runtime_control.optional_payload or {})
  check(control.wire_name == (runtime_control and runtime_control.wire_name), "model/runtime control wire name drifted: " .. id)
  check(control.carrier == "native-provider-tool-or-function", "control must use provider-native tool/function carrier: " .. id)
end
check(model.execution_gate and model.execution_gate.streaming_arguments_executable == false, "streaming tool arguments must never execute")
for _, case in ipairs(model_fixture.cases or {}) do
  for _, event_id in ipairs(case.events or {}) do check(model_event_by_id[event_id] ~= nil, "model fixture " .. case.id .. " references unknown event " .. tostring(event_id)) end
  check(list_has(model.finish_classes, case.finish_class), "model fixture " .. case.id .. " references unknown finish class")
  if case.control then check(model_control_by_id[case.control] ~= nil, "model fixture " .. case.id .. " references unknown control") end
  if case.runtime_result then
    check(outcome_set[case.runtime_result] or case.runtime_result == "completed-proposed", "model fixture " .. case.id .. " references unknown runtime result")
  end
end

-- Prompt bundle, native controls and exact synthetic provider-wire profiles.
exact_set("prompt purpose ids", keys_of(prompts.purposes), model.purposes)
exact_set("prompt segment order", prompts.segment_order, { "runtime-purpose", "global", "model", "permission", "context", "user-message" })
check(type(prompts.runtime_contract) == "string" and prompts.runtime_contract:find("Never claim that an unobserved operation succeeded", 1, true) ~= nil, "runtime prompt must preserve evidence honesty")
local prompt_control_by_id = index_by(prompts.control_functions, "canonical_id", "prompt controls")
exact_set("prompt control ids", value_list(prompts.control_functions, "canonical_id"), value_list(runtime.controls, "id"))
for id, runtime_control in pairs(runtime_control_by_id) do
  local prompt_control = prompt_control_by_id[id]
  check(prompt_control and prompt_control.wire_name == runtime_control.wire_name, "prompt/runtime control wire name drifted: " .. id)
  check(prompt_control and prompt_control.schema and prompt_control.schema.additionalProperties == false, "prompt control must reject unknown properties: " .. id)
  exact_set("prompt control required " .. id, prompt_control and prompt_control.schema and prompt_control.schema.required or {}, runtime_control.required_payload)
  exact_set("prompt control properties " .. id, prompt_control and prompt_control.schema and keys_of(prompt_control.schema.properties) or {}, (function()
    local result = {}
    for _, key in ipairs(runtime_control.required_payload or {}) do result[#result + 1] = key end
    for _, key in ipairs(runtime_control.optional_payload or {}) do result[#result + 1] = key end
    return result
  end)())
end
check(prompts.invariants and prompts.invariants.maximum_controls_per_response == 1 and prompts.invariants.control_with_executable_tool_call == "protocol-error-zero-executable-calls", "prompt control conflict handling drifted")
local prompt_fixture_by_id = index_by(prompts_fixture.purpose_cases, "id", "prompt purpose fixtures")
exact_set("prompt fixture purposes", value_list(prompts_fixture.purpose_cases, "id"), model.purposes)
exact_set("main prompt controls", prompt_fixture_by_id.main and prompt_fixture_by_id.main.controls or {}, { "yaca_finish", "yaca_ask_user", "yaca_refuse" })
for purpose, prompt in pairs(prompts.purposes or {}) do
  check(type(prompt.text) == "string" and #prompt.text > #prompts.runtime_contract, "purpose prompt has no exact purpose instruction: " .. purpose)
  if purpose ~= "main" then check(prompt.controls == "inert-observation-only" or type(prompt.controls) == "table" and #prompt.controls == 0, "non-main purpose unexpectedly has active controls: " .. purpose) end
end
local control_fixture_by_id = index_by(prompts_fixture.control_cases, "id", "prompt control fixtures")
for id, control in pairs(prompt_control_by_id) do
  local fixture = control_fixture_by_id[id]
  check(fixture and fixture.wire_name == control.wire_name, "prompt control fixture wire name drifted: " .. id)
  exact_set("prompt fixture required " .. id, fixture and fixture.required or {}, runtime_control_by_id[id].required_payload)
  exact_set("prompt fixture optional " .. id, fixture and fixture.optional or {}, runtime_control_by_id[id].optional_payload)
end
for _, protocol in ipairs(model.protocols or {}) do
  check(protocol.synthetic_fixture == true, "wire profile must identify synthetic fixture: " .. protocol.id)
  check(protocol.recorded_target_proof == "TP-015", "wire profile must retain target recording proof: " .. protocol.id)
  check(not protocol.exact_wire_profile:find("TP-004", 1, true), "wire profile incorrectly points to console proof: " .. protocol.id)
end
check(wire_fixture.provenance and wire_fixture.provenance.recorded_provider_bytes == false and wire_fixture.provenance.target_recording_proof == "TP-015", "synthetic wire fixture must not claim recorded target bytes")
local wire_seen = {}
for _, case in ipairs(wire_fixture.cases or {}) do
  local key = tostring(case.protocol) .. "\0" .. tostring(case.id)
  check(wire_seen[key] == nil, "duplicate wire fixture " .. key:gsub("\0", "/"))
  wire_seen[key] = true
  check(case.provenance == "synthetic-exact-bytes", "wire fixture provenance drifted: " .. tostring(case.id))
  check(type(case.request_bytes) == "string" and #case.request_bytes > 0, "wire fixture has no request bytes: " .. tostring(case.id))
  check(type(case.response_bytes) == "string" and #case.response_bytes > 0, "wire fixture has no response bytes: " .. tostring(case.id))
  check(json_syntax_ok(case.request_bytes), "wire fixture request is not valid JSON: " .. tostring(case.protocol) .. "/" .. tostring(case.id))
  if not case.id:find("malformed", 1, true) then
    if case.id:find("nonstream", 1, true) == 1 or case.protocol == "cross" then
      check(json_syntax_ok(case.response_bytes), "wire fixture response is not valid JSON: " .. tostring(case.protocol) .. "/" .. tostring(case.id))
    elseif case.id == "auth_401_no_retry" then
      local body = case.response_bytes:match("\r\n\r\n(.*)$")
      check(body and json_syntax_ok(body), "wire HTTP error body is not valid JSON: " .. tostring(case.id))
    else
      local data_lines = 0
      for line in (case.response_bytes .. "\n"):gmatch("(.-)\r?\n") do
        local data = line:match("^data:%s?(.*)$")
        if data and data ~= "[DONE]" then
          data_lines = data_lines + 1
          check(json_syntax_ok(data), "wire SSE data is not valid JSON: " .. tostring(case.protocol) .. "/" .. tostring(case.id) .. "/" .. data_lines)
        end
      end
      check(data_lines > 0, "wire SSE fixture has no data records: " .. tostring(case.protocol) .. "/" .. tostring(case.id))
    end
  end
  for _, event_id in ipairs(case.canonical_events or {}) do check(model_event_by_id[event_id] ~= nil, "wire fixture has unknown canonical event: " .. tostring(case.id) .. "/" .. tostring(event_id)) end
  check(list_has(model.finish_classes, case.finish_class), "wire fixture has unknown finish class: " .. tostring(case.id))
  if case.control then
    local control = model_control_by_id[case.control]
    check(control ~= nil, "wire fixture has unknown control: " .. tostring(case.id))
    check(control and case.response_bytes:find(control.wire_name, 1, true) ~= nil, "wire fixture does not carry native control name: " .. tostring(case.id))
  end
end
for protocol_id, inventory in pairs(model.wire_fixture_inventory or {}) do
  local fixture_protocol = protocol_id == "cross" and "cross" or protocol_id
  for _, case_id in ipairs(inventory or {}) do check(wire_seen[fixture_protocol .. "\0" .. case_id], "wire fixture inventory is missing " .. fixture_protocol .. "/" .. case_id) end
end
for key in pairs(wire_seen) do
  local protocol_id, case_id = key:match("^(.-)\0(.*)$")
  local inventory = model.wire_fixture_inventory and model.wire_fixture_inventory[protocol_id]
  check(inventory and list_has(inventory, case_id), "wire fixture is not declared in model inventory: " .. key:gsub("\0", "/"))
end

-- AgentLoop golden traces are legal transitions with paired accepted calls.
local purpose_set = as_set(model.purposes, "model purpose set")
local control_set = as_set(value_list(runtime.controls, "id"), "runtime control set")
for _, trace in ipairs(agentloop_fixture.traces or {}) do
  for index = 1, #trace.states - 1 do
    local key = trace.states[index] .. "\0" .. trace.states[index + 1]
    check(transition_pairs[key], "agentloop fixture " .. trace.id .. " has illegal transition " .. trace.states[index] .. " -> " .. trace.states[index + 1])
  end
  check(outcome_set[trace.outcome], "agentloop fixture " .. trace.id .. " has unknown outcome")
  if trace.states[#trace.states] == "WaitingUser" then check(trace.outcome == "waiting_user", "WaitingUser trace must report waiting_user: " .. trace.id) end
  for _, purpose in ipairs(trace.purposes or {}) do check(purpose_set[purpose], "agentloop fixture " .. trace.id .. " has unknown purpose " .. tostring(purpose)) end
  for _, control in ipairs(trace.controls or {}) do check(control_set[control], "agentloop fixture " .. trace.id .. " has unknown control " .. tostring(control)) end
  local result_count = {}
  for _, result in ipairs(trace.tool_results or {}) do result_count[result.tool_call_id] = (result_count[result.tool_call_id] or 0) + 1 end
  for _, call_id in ipairs(trace.tool_calls or {}) do check(result_count[call_id] == 1, "agentloop fixture " .. trace.id .. " does not pair tool call " .. call_id .. " exactly once") end
end

-- Process/network transport is one cancellable AsyncPort family.
exact_set("transport AsyncPort methods", transport.async_port_methods, platform.event_pump and platform.event_pump.async_port_methods or {})
exact_set("process port methods", platform.ports and platform.ports.process or {}, transport.async_port_methods)
exact_set("network port methods", platform.ports and platform.ports.network or {}, transport.async_port_methods)
exact_set("transport terminal outcomes", transport.terminal_outcomes, { "completed", "cancelled", "failed", "unknown" })
check(transport.process and transport.process.foreground_only == true and transport.process.interactive == false and transport.process.pty == false and transport.process.tracked_background == false and transport.process.detached == false, "process execution boundary drifted")
check(transport.process and transport.process.stdin == "closed-before-user-code-runs", "raw exec stdin must remain closed")
exact_set("Windows shell arguments", transport.process and transport.process.shell and transport.process.shell.windows.fixed_arguments or {}, { "/d", "/s", "/c" })
exact_set("Linux shell arguments", transport.process and transport.process.shell and transport.process.shell.linux.fixed_arguments or {}, { "-c" })
check(transport.process and transport.process.shell and transport.process.shell.linux.executable == "/bin/sh", "Linux raw shell must be /bin/sh")
check(transport.curl and transport.curl.fixed_argv and transport.curl.fixed_argv[1] == "--disable", "curl must disable default config first")
exact_set("curl fixed argv", transport.curl and transport.curl.fixed_argv or {}, { "--disable", "--silent", "--show-error", "--no-buffer", "--config", "-" })
check(transport.curl and transport.curl.config_carrier == "anonymous-stdin-pipe" and transport.curl.secret_in_argv == false and transport.curl.secret_in_environment == false, "curl secret carrier drifted")
check(transport.curl and transport.curl.curl_builtin_retry == 0 and transport.curl.curl_automatic_redirect == false, "curl must not own retry/redirect")
check(transport.http and transport.http.retry and transport.http.retry.owner == "Runtime-not-curl" and transport.http.retry.model_switch == false and transport.http.retry.active_config_reload == false, "Runtime retry snapshot boundary drifted")
exact_set("retry-eligible causes", transport.http and transport.http.retry and transport.http.retry.eligible_before_canonical_event or {}, { "dns", "connect", "tls-before-body", "http-429", "http-503" })
exact_set("retry-ineligible causes", transport.http and transport.http.retry and transport.http.retry.never_eligible or {}, { "auth-4xx", "ordinary-4xx", "protocol", "content-refusal", "cancel", "outcome-unknown" })
check(transport.secret_scanner and transport.secret_scanner.constants_source == "release-manifest", "secret scanner constants must come from release manifest")
exact_set("transport environment fixture ids", value_list(transport_fixture.environment_cases, "id"), { "minimal", "inherit-filtered" })
local always_removed = as_set(transport.process and transport.process.environment and transport.process.environment.always_remove_names or {}, "always-removed environment names")
for _, case in ipairs(transport_fixture.environment_cases or {}) do
  for _, name in ipairs(case.removed or {}) do
    if name ~= "HTTP_PROXY" then check(always_removed[name] or case.mode == "minimal", "environment fixture removes undeclared inherited name: " .. tostring(name)) end
  end
end
local retry_eligible = as_set(transport.http and transport.http.retry and transport.http.retry.eligible_before_canonical_event or {}, "retry eligible set")
for _, case in ipairs(transport_fixture.retry_cases or {}) do
  local expected = case.canonical_events == 0 and retry_eligible[case.cause] == true
  check(case.automatic == expected, "transport retry fixture drifted: " .. tostring(case.id))
  check(case.maximum_attempts == (case.automatic and release.implementation_candidates.retry.default_count + 1 or 1), "transport retry attempt cap drifted: " .. tostring(case.id))
end
exact_set("transport redirect fixture ids", value_list(transport_fixture.redirect_cases, "id"), { "same-origin-307", "same-origin-308-effective-port", "cross-origin", "downgrade", "status-302" })
for _, case in ipairs(transport_fixture.redirect_cases or {}) do
  if case.automatic then
    check((case.status == 307 or case.status == 308) and case.key_reused == true, "automatic redirect fixture is not safe: " .. tostring(case.id))
  else
    check(case.key_reused == false, "rejected redirect reused a key: " .. tostring(case.id))
  end
end
for _, case in ipairs(transport_fixture.shell_cases or {}) do
  check(case.stdin == "closed", "shell fixture must close stdin: " .. tostring(case.target))
  if case.target == "linux" then exact_set("Linux shell fixture args", case.fixed_arguments, transport.process.shell.linux.fixed_arguments) end
  if case.target == "windows" then exact_set("Windows shell fixture args", case.fixed_arguments, transport.process.shell.windows.fixed_arguments) end
end

-- Context structural and semantic schema.
exact_set("Context local ids", context.local_ids, {
  "eventSeq", "turnId", "requestId", "attemptId", "messageId", "toolCallId", "operationId", "approvalId", "reviewId", "compactionId", "queueItemId",
})
local expected_context_events = {
  "turn_started", "user_message", "queue_item", "model_request", "model_message", "model_control", "model_yield", "tool_call", "permission_decision",
  "approval", "operation_intent", "operation_result", "tool_result", "action_review", "termination_review", "turn_ended", "cancel", "steer",
  "compaction", "model_view_published", "session_override", "rename", "rebind", "auto_name", "config_generation_ref", "warning",
  "unknown_side_effect", "import_mapping",
}
exact_set("Context event types", value_list(context.event_types, "id"), expected_context_events)
local context_event_by_id = index_by(context.event_types, "id", "Context event types")
check(context.invariants and context.invariants.workspace_root_element == false and context.invariants.secret_elements == false, "Context must contain neither root authority nor registered secrets")
check(context.invariants and context.invariants.operation_intent_without_result_recovers_as_unknown == true and context.invariants.unknown_operation_auto_replay == false, "Context unknown-operation recovery drifted")
local rng_bytes = read_all(contract_dir .. "/context.rng")
for _, event_id in ipairs(expected_context_events) do check(rng_bytes:find("<value>" .. event_id .. "</value>", 1, true) ~= nil, "context.rng omits event type " .. event_id) end
for _, forbidden in ipairs(context.forbidden_elements or {}) do check(rng_bytes:find("name=\"" .. forbidden .. "\"", 1, true) == nil, "context.rng contains forbidden element " .. forbidden) end
for _, trace in ipairs(context_fixture.traces or {}) do
  local event_positions = {}
  for index, event in ipairs(trace.events or {}) do
    check(event.seq == index, "Context fixture " .. trace.id .. " has non-contiguous seq at " .. index)
    local schema = context_event_by_id[event.type]
    check(schema ~= nil, "Context fixture " .. trace.id .. " has unknown event " .. tostring(event.type))
    local fields = as_set(event.fields, "Context fixture fields " .. trace.id .. "/" .. tostring(event.type))
    local allowed = {}
    if schema then
      for _, field in ipairs(schema.required or {}) do allowed[field] = true; check(fields[field], "Context fixture " .. trace.id .. " event " .. event.type .. " omits required field " .. field) end
      for _, field in ipairs(schema.optional or {}) do allowed[field] = true end
      for field in pairs(fields) do check(allowed[field], "Context fixture " .. trace.id .. " event " .. event.type .. " has unknown field " .. field) end
    end
    event_positions[event.type] = event_positions[event.type] or index
  end
  if event_positions.user_message and event_positions.model_request then check(event_positions.user_message < event_positions.model_request, "Context fixture sends Model request before durable user input: " .. trace.id) end
  if trace.outcome then check(outcome_set[trace.outcome], "Context fixture has unknown outcome " .. tostring(trace.outcome)) end
end

-- Safe loading and zero-surface intersections.
local expected_source_modules = release.planned_lua_modules
exact_set("safe Lua module allowlist", platform.safe_loading.lua_module_allowlist, expected_source_modules)
local source_module_files = list_files(root .. "/src", "*.lua")
local source_modules = {}
for _, filename in ipairs(source_module_files) do source_modules[#source_modules + 1] = filename:gsub("%.lua$", "") end
if implementation_phase == "pre-coding" then
  exact_set("pre-coding src Lua modules", source_modules, release.initial_skeleton_modules)
elseif implementation_phase == "implementing" then
  local allowed_source_modules = as_set(expected_source_modules, "allowed implementation source modules")
  for _, module_id in ipairs(source_modules) do check(allowed_source_modules[module_id], "implementation source inventory contains an unplanned module " .. module_id) end
elseif implementation_phase == "implemented-unqualified" then
  exact_set("implemented src Lua modules", source_modules, expected_source_modules)
end
check(platform.safe_loading.current_working_directory == false and platform.safe_loading.environment_lua_path == false and platform.safe_loading.environment_lua_cpath == false, "safe loading must exclude cwd and environment module paths")
check(platform.safe_loading.dynamic_extension_discovery == false, "dynamic extension discovery is forbidden")
local forbidden_modules = as_set(zero_surface.forbidden_modules, "zero-surface forbidden modules")
for _, module_id in ipairs(platform.safe_loading.lua_module_allowlist or {}) do check(not forbidden_modules[module_id], "safe module allowlist contains excluded module " .. module_id) end
for _, module_id in ipairs(release.planned_lua_modules or {}) do check(not forbidden_modules[module_id], "planned module allowlist contains excluded module " .. module_id) end
local forbidden_actions = as_set(zero_surface.forbidden_action_ids, "zero-surface forbidden actions")
for id in pairs(action_by_id) do check(not forbidden_actions[id], "action registry contains excluded action " .. id) end
local forbidden_config = as_set(zero_surface.forbidden_config_field_ids, "zero-surface forbidden config")
for id in pairs(config_by_id) do check(not forbidden_config[id], "config catalog contains excluded field " .. id) end
local forbidden_purposes = as_set(zero_surface.forbidden_model_purposes, "zero-surface forbidden purposes")
for _, purpose in ipairs(model.purposes or {}) do check(not forbidden_purposes[purpose], "model schema contains excluded purpose " .. purpose) end
local web_files = list_files(root .. "/web", "*")
exact_set("web directory files", web_files, zero_surface.web_directory_allowed_files)

-- Stable diagnostics and staged self-test dependency graph.
local severity_set = as_set(diagnostics.severities, "diagnostic severities")
local error_by_id = index_by(diagnostics.errors, "id", "diagnostic errors")
local expected_error_ids = {
  "UsageError", "ConfigMissing", "ConfigInvalid", "ConfigChanged", "ModelUnavailable", "PermissionUnavailable", "TtyRequired",
  "OnlineConsentRequired", "NotFound", "HashCollision", "MatchedUnavailable", "ScanIncomplete", "ScanLimit", "TargetChanged",
  "OpenConflict", "DestinationExists", "LockConflict", "UnsupportedPath", "UnsupportedObject", "PathEscapesWorkspace", "PermissionDenied",
  "ApprovalRequired", "ApprovalStale", "ToolSchemaInvalid", "ToolFailed", "ToolCancelled", "ToolUnknown", "ProcessTimeout", "NetworkError",
  "ProtocolError", "StorageError", "ContextCorrupt", "ContextVersionUnsupported", "ContextHardLimit", "ContextStale", "BudgetExhausted",
  "Stuck", "Cancelled", "InternalError",
}
exact_set("stable error ids", value_list(diagnostics.errors, "id"), expected_error_ids)
for _, record in ipairs(diagnostics.errors or {}) do
  check(severity_set[record.severity], "error " .. record.id .. " has unknown severity")
  check(diagnostics.exit_classes[record.exit_class] ~= nil, "error " .. record.id .. " has unknown exit class")
  check(type(record.summary) == "string" and record.summary:match("^[%z\1-\127]*$") ~= nil, "error summary must be English/ASCII: " .. record.id)
end
local check_by_id = index_by(diagnostics.self_test and diagnostics.self_test.checks or {}, "id", "self-test checks")
check(#diagnostics.self_test.stages == 3 and diagnostics.self_test.stages[1] == 1 and diagnostics.self_test.stages[2] == 2 and diagnostics.self_test.stages[3] == 3, "self-test stages must be exactly 1,2,3")
for _, record in ipairs(diagnostics.self_test.checks or {}) do
  check(record.stage == 1 or record.stage == 2 or record.stage == 3, "self-test check has invalid stage " .. record.id)
  if record.stage == 1 then check(record.online == false, "Stage 1 check must be offline: " .. record.id) end
  if record.stage >= 2 then check(record.online == true, "Stage 2/3 check must declare online use: " .. record.id) end
  for _, dependency_id in ipairs(record.dependencies or {}) do
    local dependency = check_by_id[dependency_id]
    check(dependency ~= nil, "self-test check " .. record.id .. " has unknown dependency " .. dependency_id)
    check(not dependency or dependency.stage <= record.stage, "self-test check " .. record.id .. " depends on a later stage")
  end
end
check(diagnostics.persistence and diagnostics.persistence.standalone_log_file == false and diagnostics.persistence.standalone_diagnostic_xml == false and diagnostics.persistence.background_spool == false, "diagnostics must not create a third durable fact source")

-- Parser/config fixtures reference canonical actions and stable errors.
for _, case in ipairs(argv_fixture.cases or {}) do
  if case.expected_action then check(action_by_id[case.expected_action] ~= nil, "argv fixture " .. case.id .. " references unknown action") end
  if case.expected_error then check(error_by_id[case.expected_error] ~= nil, "argv fixture " .. case.id .. " references unknown error") end
end
for _, case in ipairs(config_fixture.cases or {}) do
  if case.valid and case.field_ids then for _, id in ipairs(case.field_ids) do check(config_by_id[id] ~= nil, "valid config fixture " .. case.id .. " references unknown field " .. id) end end
  if case.valid and case.field_id then check(config_by_id[case.field_id] ~= nil, "valid config fixture " .. case.id .. " references unknown field " .. case.field_id) end
  if not case.valid then
    check(config_by_id[case.field_id] == nil or case.value == "above-runtime", "invalid config fixture unexpectedly names a normal accepted value: " .. case.id)
    check(error_by_id[case.expected_error] ~= nil, "invalid config fixture " .. case.id .. " references unknown error")
  end
end
check(config_by_id["Model.*.Key"] and config_by_id["Model.*.Key"].secret == true, "Model Key must stay in the secret registry")
local function decode_quoted_text(encoded)
  if type(encoded) ~= "string" or #encoded < 2 or encoded:sub(1, 1) ~= "\"" or encoded:sub(-1) ~= "\"" then return nil end
  local body = encoded:sub(2, -2)
  if body:find("\n", 1, true) or body:find("\r", 1, true) then return nil end
  local result, index = {}, 1
  local replacements = { ["\\"] = "\\", ["\""] = "\"", n = "\n", r = "\r", t = "\t" }
  while index <= #body do
    local character = body:sub(index, index)
    if character ~= "\\" then
      if character == "\"" then return nil end
      result[#result + 1] = character
      index = index + 1
    else
      local escape = body:sub(index + 1, index + 1)
      local replacement = replacements[escape]
      if not replacement then return nil end
      result[#result + 1] = replacement
      index = index + 2
    end
  end
  return table.concat(result)
end
for _, vector in ipairs(config_fixture.string_vectors or {}) do
  local decoded = decode_quoted_text(vector.encoded)
  if vector.valid then check(decoded == vector.decoded, "INI string vector failed: " .. vector.id) else check(decoded == nil, "invalid INI string vector was accepted: " .. vector.id) end
end
local migration_by_source = index_by(config.migration_rules, "source", "config migration rules")
for _, case in ipairs(config_fixture.migration_cases or {}) do
  local rule = migration_by_source[case.source]
  check(rule ~= nil, "migration fixture has no rule: " .. case.id)
  check(rule and rule.action == case.expected_action, "migration fixture action drifted: " .. case.id)
end

-- External structural proof available on the development host.
if command_ok("command -v xmllint >/dev/null 2>&1") then
  local command = "xmllint --noout --relaxng " .. shell_quote(contract_dir .. "/context.rng") .. " " .. shell_quote(fixture_dir .. "/context-minimal.xml") .. " >/dev/null 2>&1"
  check(command_ok(command), "minimal Context XML does not validate against context.rng")
else
  note("xmllint unavailable; skipped external Relax NG validation")
end

if #failures > 0 then
  io.stderr:write(string.format("design-contract validation FAILED: %d failure(s), %d assertion(s)\n", #failures, assertion_count))
  for _, message in ipairs(failures) do io.stderr:write("- " .. message .. "\n") end
  os.exit(1)
end

for _, message in ipairs(notes) do io.stdout:write("NOTE: " .. message .. "\n") end
io.stdout:write(string.format("design-contract validation PASS: %d assertions across 16 contracts and 12 fixture sets\n", assertion_count))
