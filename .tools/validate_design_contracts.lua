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

local argv_fixture = load_fixture("argv")
local permission_fixture = load_fixture("permission")
local agentloop_fixture = load_fixture("agentloop")
local model_fixture = load_fixture("model-events")
local context_fixture = load_fixture("context-events")
local config_fixture = load_fixture("config")

local all_versioned = {
  product, config, runtime, actions, tools, model, context, tui, platform, diagnostics, zero_surface,
  argv_fixture, permission_fixture, agentloop_fixture, model_fixture, context_fixture, config_fixture,
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
  for _, allowed_state in ipairs(action.allowed_states or {}) do check(state_set[allowed_state] or special_states[allowed_state], "action " .. action.id .. " references unknown state " .. tostring(allowed_state)) end
end
check(argv_aliases["-dc"] == nil and argv_aliases["-rc"] == nil, "removed conflicting aliases must stay absent")
check(actions.parser and #actions.parser.legacy_aliases == 0, "legacy aliases must be empty")
check(argv_aliases["--self-test"] == "self-test" and argv_aliases["-st"] == "self-test" and argv_aliases["/st"] == "self-test", "self-test aliases drifted")

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

-- Context structural and semantic schema.
exact_set("Context local ids", context.local_ids, {
  "eventSeq", "turnId", "requestId", "attemptId", "messageId", "toolCallId", "operationId", "approvalId", "reviewId", "compactionId",
})
local expected_context_events = {
  "turn_started", "user_message", "model_request", "model_message", "model_control", "model_yield", "tool_call", "permission_decision",
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
local expected_source_modules = { "cli", "compact", "config", "context", "index", "ini", "json", "main", "model", "path", "safety", "session", "text", "tui" }
exact_set("safe Lua module allowlist", platform.safe_loading.lua_module_allowlist, expected_source_modules)
local source_module_files = list_files(root .. "/src", "*.lua")
local source_modules = {}
for _, filename in ipairs(source_module_files) do source_modules[#source_modules + 1] = filename:gsub("%.lua$", "") end
exact_set("src Lua modules", source_modules, expected_source_modules)
check(platform.safe_loading.current_working_directory == false and platform.safe_loading.environment_lua_path == false and platform.safe_loading.environment_lua_cpath == false, "safe loading must exclude cwd and environment module paths")
check(platform.safe_loading.dynamic_extension_discovery == false, "dynamic extension discovery is forbidden")
local forbidden_modules = as_set(zero_surface.forbidden_modules, "zero-surface forbidden modules")
for _, module_id in ipairs(platform.safe_loading.lua_module_allowlist or {}) do check(not forbidden_modules[module_id], "safe module allowlist contains excluded module " .. module_id) end
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
io.stdout:write(string.format("design-contract validation PASS: %d assertions across 11 contracts and 6 fixture sets\n", assertion_count))
