--[[
File: main.lua
Date: 2026-08-29
Author: WaterRun
Description: Routes the offline bootstrap lifecycle from the unique composition root.
]]

local session = require("session")

local M = {}

local BOOTSTRAP_ACTIONS = {
    ["config-repl"] = true,
    ["model-repl"] = true,
    ["context-repl"] = true,
}

local function failure(code, message, next_action)
    local result = { code = code, message = message }
    if next_action ~= nil then result.next_action = next_action end
    return result
end

local function readonly(values, label)
    return setmetatable({}, {
        __index = values,
        __newindex = function(_, key)
            error((label or "readonly value") .. " cannot be modified: " .. tostring(key), 2)
        end,
        __pairs = function()
            return next, values, nil
        end,
        __len = function()
            return #values
        end,
        __metatable = "locked",
    })
end

local function freeze(value, visiting, label)
    if type(value) ~= "table" then return value end
    visiting = visiting or {}
    if visiting[value] then return nil end
    visiting[value] = true
    local copy = {}
    for key, item in pairs(value) do
        local frozen = freeze(item, visiting, label)
        if frozen == nil and type(item) == "table" then
            visiting[value] = nil
            return nil
        end
        copy[key] = frozen
    end
    visiting[value] = nil
    return readonly(copy, label)
end

local function valid_integer(value, minimum)
    return math.type(value) == "integer" and value >= minimum
end

local function dense_string_array(values)
    if type(values) ~= "table" then return false end
    local count = 0
    for key in pairs(values) do
        if math.type(key) ~= "integer" or key < 1 then return false end
        count = count + 1
    end
    for index = 1, count do
        local value = values[index]
        if type(value) ~= "string" or value == "" or value:find("\0", 1, true) then
            return false
        end
    end
    return true
end

local function copy_plain(value, visiting)
    local value_type = type(value)
    if value_type == "nil" or value_type == "string" or value_type == "boolean" then
        return value, true
    end
    if value_type == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return nil, false end
        return value, true
    end
    if value_type ~= "table" then return nil, false end
    visiting = visiting or {}
    if visiting[value] then return nil, false end
    visiting[value] = true
    local copy = {}
    for key, item in pairs(value) do
        if type(key) ~= "string" and math.type(key) ~= "integer" then
            visiting[value] = nil
            return nil, false
        end
        local copied, copied_ok = copy_plain(item, visiting)
        if not copied_ok then
            visiting[value] = nil
            return nil, false
        end
        copy[key] = copied
    end
    visiting[value] = nil
    return copy, true
end

local function valid_absolute_path(value)
    if type(value) ~= "string" or value == "" or value:find("\0", 1, true) then return false end
    local normalized = value:gsub("\\", "/")
    return normalized:sub(1, 1) == "/"
        or normalized:match("^[A-Za-z]:/") ~= nil
        or normalized:match("^//[^/]+/[^/]+") ~= nil
end

local function validate_components(components)
    if type(components) ~= "table" then
        return nil, failure("InvalidBootstrapComponents", "bootstrap components are required")
    end
    local allowed = {
        platform = true,
        config = true,
        workspace = true,
        self_test = true,
        management = true,
        network = true,
        context_catalog = true,
        agent = true,
    }
    for key in pairs(components) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure(
                "InvalidBootstrapComponents",
                "bootstrap components contain an unknown field"
            )
        end
    end
    if type(components.platform) ~= "table"
        or type(components.platform.identity) ~= "function"
        or type(components.config) ~= "table"
        or type(components.config.reload_file) ~= "function"
        or type(components.workspace) ~= "table"
        or type(components.workspace.inspect) ~= "function"
    then
        return nil, failure(
            "InvalidBootstrapComponents",
            "platform, config, and workspace services are incomplete"
        )
    end
    if type(components.self_test) ~= "table"
        or components.self_test.online ~= "explicit-current-invocation-only"
        or components.self_test.auto_fix ~= false
        or type(components.self_test.run) ~= "function"
    then
        return nil, failure(
            "InvalidBootstrapComponents",
            "self-test must declare explicit-consent online and no-auto-fix semantics"
        )
    end
    if type(components.management) ~= "table"
        or components.management.online ~= false
        or type(components.management.run) ~= "function"
    then
        return nil, failure(
            "InvalidBootstrapComponents",
            "management must declare an offline run method"
        )
    end
    return components
end

local function validate_options(options)
    if type(options) ~= "table" then
        return nil, failure("InvalidBootstrapOptions", "bootstrap options are required")
    end
    local allowed = {
        product_name = true,
        product_version = true,
        release_target = true,
        config_path = true,
        maximum_draft_bytes = true,
    }
    for key in pairs(options) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure(
                "InvalidBootstrapOptions",
                "bootstrap options contain an unknown field"
            )
        end
    end
    if type(options.product_name) ~= "string" or options.product_name == ""
        or type(options.product_version) ~= "string" or options.product_version == ""
        or type(options.release_target) ~= "string" or options.release_target == ""
        or not valid_absolute_path(options.config_path)
        or not valid_integer(options.maximum_draft_bytes, 1)
    then
        return nil, failure("InvalidBootstrapOptions", "bootstrap options are incomplete")
    end
    return options
end

local function validate_request(request)
    if type(request) ~= "table" or type(request.id) ~= "string" or request.id == "" then
        return nil, failure("UsageError", "a semantic action id is required")
    end
    local fields = {
        help = { id = true, topic = true, machine = true },
        version = { id = true, machine = true },
        ["self-test"] = {
            id = true,
            through_stage = true,
            list_checks = true,
            excluded_models = true,
            excluded_checks = true,
            selected_checks = true,
            online_consent = true,
            machine = true,
        },
        ["config-repl"] = { id = true },
        ["model-repl"] = { id = true },
        ["context-repl"] = { id = true, view = true },
        ["run-chat"] = { id = true, directory = true },
    }
    local allowed = fields[request.id]
    if not allowed then return nil, failure("UsageError", "semantic action is unsupported") end
    for key in pairs(request) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure("UsageError", "semantic action contains an unknown field")
        end
    end
    if request.machine ~= nil and type(request.machine) ~= "boolean" then
        return nil, failure("UsageError", "machine modifier must be boolean")
    end
    if request.id == "help" and request.topic ~= nil and type(request.topic) ~= "string" then
        return nil, failure("UsageError", "help topic must be a string")
    end
    if request.id == "self-test" then
        local stage = request.through_stage or 1
        if not valid_integer(stage, 1) or stage > 3 then
            return nil, failure("UsageError", "self-test stage must be 1, 2, or 3")
        end
        if request.online_consent ~= nil and type(request.online_consent) ~= "boolean" then
            return nil, failure("UsageError", "online consent must be boolean")
        end
        if request.list_checks ~= nil and type(request.list_checks) ~= "boolean" then
            return nil, failure("UsageError", "self-test list flag must be boolean")
        end
        for _, name in ipairs({
            "excluded_models", "excluded_checks", "selected_checks",
        }) do
            if request[name] ~= nil and not dense_string_array(request[name]) then
                return nil, failure("UsageError", "self-test filters must be string arrays")
            end
        end
    end
    if request.id == "run-chat"
        and request.directory ~= nil
        and type(request.directory) ~= "string"
    then
        return nil, failure("UsageError", "chat directory must be a string")
    end
    return request
end

local function normalize_config_error(config_error)
    if type(config_error) ~= "table" then
        return failure("ConfigInvalid", "the main configuration could not be loaded")
    end
    if config_error.code == "NotFound" then
        return failure(
            "ConfigMissing",
            "the main configuration is missing",
            "Run config-repl or model-repl."
        )
    end
    if config_error.code == "ConfigInvalid" then return config_error end
    return failure(
        "ConfigInvalid",
        "the main configuration could not be loaded",
        "Run config-repl or Stage 1 self-test."
    )
end

---Creates the side-effect-free application composition root.
-- No component method is called until dispatch receives an explicit semantic
-- action. Bootstrap-safe routes never receive the optional network/agent ports.
-- @param components table Injected platform/config/workspace/offline handlers.
-- @param options table Product identity, config path, target, and draft cap.
-- @return table|nil application Immutable application facade.
-- @return table|nil err Structured construction failure.
function M.new(components, options)
    local admitted_components, components_error = validate_components(components)
    if not admitted_components then return nil, components_error end
    local admitted, options_error = validate_options(options)
    if not admitted then return nil, options_error end

    local platform_attempted = false
    local platform_identity
    local platform_error
    local active_draft
    local lifecycle = "constructed"
    local application = {}

    local function check_platform()
        if platform_attempted then return platform_identity, platform_error end
        platform_attempted = true
        local called, identity, identity_error = pcall(admitted_components.platform.identity)
        if not called or not identity then
            platform_error = failure(
                "PlatformMismatch",
                "release platform identity could not be validated"
            )
            return nil, platform_error
        end
        if identity.supported ~= true or identity.target ~= admitted.release_target then
            platform_error = failure(
                "PlatformMismatch",
                "the executable does not match the observed release target"
            )
            return nil, platform_error
        end
        platform_identity = identity
        return identity
    end

    local function load_config()
        local called, generation, config_error = pcall(
            admitted_components.config.reload_file,
            admitted.config_path
        )
        if not called then
            return nil, failure("ConfigInvalid", "configuration loading raised an exception")
        end
        if not generation then return nil, normalize_config_error(config_error) end
        return generation
    end

    local function self_test_snapshot(identity, generation, config_error)
        local config_snapshot
        local models = {}
        local snapshot_id = "self-test-config-unavailable"
        if generation then
            if type(generation.id) ~= "string"
                or type(generation.model_order) ~= "table"
                or type(generation.models) ~= "table"
            then
                return nil, failure(
                    "SelfTestSnapshotInvalid",
                    "configuration generation cannot be projected for self-test"
                )
            end
            snapshot_id = generation.id
            config_snapshot = {
                available = true,
                generation = {
                    id = generation.id,
                    schema_version = generation.schema_version,
                    general = generation.general,
                    tui = generation.tui,
                    agent = generation.agent,
                    network = generation.network,
                    exec = generation.exec,
                    context = generation.context,
                    permissions = generation.permissions,
                    permission_order = generation.permission_order,
                    models = generation.models,
                    model_order = generation.model_order,
                    current_model = generation.current_model,
                    current_permission = generation.current_permission,
                    default_model = generation.default_model,
                    default_permission = generation.default_permission,
                    effective_double_check = generation.effective_double_check,
                    effective_double_check_goal = generation.effective_double_check_goal,
                    context_prompt = generation.context_prompt,
                    auto_rename_disabled = generation.auto_rename_disabled,
                    agent_ready = generation.agent_ready,
                    agent_block_reason = generation.agent_block_reason or false,
                    warnings = generation.warnings,
                },
            }
            local count = 0
            for index, name in ipairs(generation.model_order) do
                count = count + 1
                if index ~= count or type(name) ~= "string" or name == "" then
                    return nil, failure(
                        "SelfTestSnapshotInvalid",
                        "configuration Model order is invalid"
                    )
                end
                local model = generation.models[name]
                if type(model) ~= "table" then
                    return nil, failure(
                        "SelfTestSnapshotInvalid",
                        "configuration Model snapshot is missing"
                    )
                end
                if model.enabled == true then
                    if type(model.endpoint) ~= "string" or model.endpoint == "" then
                        return nil, failure(
                            "SelfTestSnapshotInvalid",
                            "enabled Model endpoint is unavailable"
                        )
                    end
                    models[#models + 1] = {
                        id = name,
                        endpoint = model.endpoint,
                        snapshot_id = generation.id .. ":model:" .. tostring(index),
                    }
                end
            end
            for key in pairs(generation.model_order) do
                if math.type(key) ~= "integer" or key < 1 or key > count then
                    return nil, failure(
                        "SelfTestSnapshotInvalid",
                        "configuration Model order is not dense"
                    )
                end
            end
        else
            config_snapshot = {
                available = false,
                error = {
                    code = config_error and config_error.code or "ConfigInvalid",
                    message = config_error and config_error.message
                        or "configuration is unavailable",
                },
            }
        end
        local raw_snapshot = {
            product = {
                name = admitted.product_name,
                version = admitted.product_version,
                release_target = admitted.release_target,
            },
            platform = {
                os = identity.os,
                arch = identity.arch,
                target = identity.target,
                supported = identity.supported,
            },
            config_path = admitted.config_path,
            config = config_snapshot,
        }
        local copied_snapshot, copied_ok = copy_plain(raw_snapshot, {})
        local copied_models, models_ok = copy_plain(models, {})
        if not copied_ok or not models_ok then
            return nil, failure(
                "SelfTestSnapshotInvalid",
                "self-test snapshot contains a non-data value or cycle"
            )
        end
        local snapshot = freeze(copied_snapshot, {}, "self-test configuration snapshot")
        local frozen_models = freeze(copied_models, {}, "self-test Model snapshots")
        if not snapshot or not frozen_models then
            return nil, failure("SelfTestSnapshotInvalid", "self-test snapshot cannot be frozen")
        end
        return {
            snapshot_id = snapshot_id,
            snapshot = snapshot,
            models = frozen_models,
        }
    end

    local function run_self_test(mode, request, identity, generation, config_error)
        local projection, projection_error = self_test_snapshot(
            identity,
            generation,
            config_error
        )
        if not projection then return nil, projection_error end
        local specification = freeze({
            mode = mode,
            through_stage = request.through_stage or 1,
            list_checks = request.list_checks == true,
            online_consent = request.online_consent == true,
            excluded_models = request.excluded_models or {},
            excluded_checks = request.excluded_checks or {},
            selected_checks = request.selected_checks or {},
            snapshot_id = projection.snapshot_id,
            snapshot = projection.snapshot,
            models = projection.models,
        }, {}, "self-test run specification")
        if not specification then
            return nil, failure("SelfTestSnapshotInvalid", "self-test request contains a cycle")
        end
        local called, result, run_error = pcall(
            admitted_components.self_test.run,
            admitted_components.self_test,
            specification
        )
        if not called then
            return nil, failure("SelfTestFailed", "self-test runner raised an exception")
        end
        if result == nil then
            if type(run_error) == "table" and type(run_error.code) == "string" then
                return nil, run_error
            end
            return nil, failure("SelfTestFailed", "self-test runner returned no result")
        end
        local outcomes = { passed = true, partial = true, cancelled = true, error = true }
        local through_stage = request.through_stage or 1
        if type(result) ~= "table"
            or result.kind ~= "self-test"
            or not outcomes[result.outcome]
            or not valid_integer(result.online_requests, 0)
            or result.auto_fixes ~= 0
            or not valid_integer(result.completed_stage, 0)
            or result.completed_stage > through_stage
            or (through_stage == 1 and result.online_requests ~= 0)
        then
            return nil, failure("SelfTestContract", "self-test runner violated its result contract")
        end
        local frozen = freeze(result, {}, "self-test result")
        if not frozen then
            return nil, failure("SelfTestContract", "self-test result contains a cycle")
        end
        return frozen
    end

    local function dispatch_self_test(request)
        local identity, identity_error = check_platform()
        if not identity then return nil, identity_error end
        local through_stage = request.through_stage or 1
        if through_stage >= 2 and request.list_checks ~= true
            and request.online_consent ~= true
        then
            return nil, failure(
                "OnlineConsentRequired",
                "online self-test requires explicit current-invocation consent"
            )
        end
        local generation, config_error = load_config()
        return run_self_test("explicit", request, identity, generation, config_error)
    end

    local function dispatch_management(request)
        local identity, identity_error = check_platform()
        if not identity then return nil, identity_error end
        local generation, config_error = load_config()
        local context = readonly({
            action = request.id,
            request = request,
            release_target = admitted.release_target,
            config_path = admitted.config_path,
            config_service = admitted_components.config,
            config_generation = generation or false,
            config_error = config_error or false,
            online = false,
        }, "bootstrap management request")
        local called, result = pcall(admitted_components.management.run, context)
        if not called or type(result) ~= "table" or type(result.outcome) ~= "string" then
            return nil, failure(
                "ManagementFailed",
                "bootstrap management returned an invalid result"
            )
        end
        local frozen = freeze(result, {}, "bootstrap management result")
        if not frozen then
            return nil, failure("ManagementFailed", "management result contains a cycle")
        end
        return frozen
    end

    local function run_startup_self_test(generation)
        local requested = generation.general.startup_self_test
        if requested == "off" then return true end
        local stage_by_name = { stage1 = 1, stage2 = 2, stage3 = 3 }
        local through_stage = stage_by_name[requested]
        if not through_stage then
            return nil, failure("StartupSelfTestFailed", "startup self-test setting is invalid")
        end
        if through_stage >= 2 then
            return nil, failure(
                "OnlineConsentRequired",
                "startup online self-test requires visible current-invocation consent"
            )
        end
        local identity, identity_error = check_platform()
        if not identity then return nil, identity_error end
        local result, stage_error = run_self_test("startup", {
            through_stage = through_stage,
            list_checks = false,
            online_consent = false,
            excluded_models = {},
            excluded_checks = {},
            selected_checks = {},
        }, identity, generation)
        if not result then return nil, stage_error end
        if result.outcome ~= "passed" then
            return nil, failure(
                "StartupSelfTestFailed",
                "required startup self-test did not pass"
            )
        end
        return true
    end

    local function dispatch_chat(request)
        if active_draft then
            return nil, failure("SessionActive", "this process already owns an active chat")
        end
        local identity, identity_error = check_platform()
        if not identity then return nil, identity_error end
        local called, workspace, workspace_error = pcall(
            admitted_components.workspace.inspect,
            request.directory or "."
        )
        if not called or not workspace then
            return nil, workspace_error or failure(
                "InvalidWorkspace",
                "the requested workspace could not be inspected"
            )
        end
        local generation, config_error = load_config()
        if not generation then return nil, config_error end
        if generation.agent_ready ~= true then
            return nil, failure(
                "ModelUnavailable",
                "the selected Model cannot start the coding Agent"
            )
        end
        local self_test_ok, self_test_error = run_startup_self_test(generation)
        if not self_test_ok then return nil, self_test_error end
        local draft, draft_error = session.new_draft(generation, workspace, {
            maximum_draft_bytes = admitted.maximum_draft_bytes,
        })
        if not draft then return nil, draft_error end
        active_draft = draft
        lifecycle = "draft-ready"
        return readonly({
            kind = "run-chat",
            outcome = "ready",
            draft = draft,
            status = draft.status(),
        }, "chat bootstrap result")
    end

    ---Dispatches one already-normalized semantic action.
    -- Parsing argv and rendering human/machine output are later adapters.
    function application.dispatch(request)
        if lifecycle == "closed" then
            return nil, failure("ApplicationClosed", "the application lifecycle is closed")
        end
        local admitted_request, request_error = validate_request(request)
        if not admitted_request then return nil, request_error end
        if request.id == "help" then
            return readonly({
                kind = "help",
                outcome = "success",
                topic = request.topic or false,
                product = admitted.product_name,
                bootstrap_actions = readonly({
                    "help", "version", "self-test", "config-repl", "model-repl",
                    "context-repl", "run-chat",
                }, "bootstrap action names"),
            }, "help bootstrap result")
        end
        if request.id == "version" then
            return readonly({
                kind = "version",
                outcome = "success",
                product = admitted.product_name,
                version = admitted.product_version,
                release_target = admitted.release_target,
            }, "version bootstrap result")
        end
        if request.id == "self-test" then return dispatch_self_test(request) end
        if BOOTSTRAP_ACTIONS[request.id] then return dispatch_management(request) end
        return dispatch_chat(request)
    end

    ---Returns lifecycle facts without loading config or scanning Contexts.
    function application.status()
        return readonly({
            lifecycle = lifecycle,
            active_draft = active_draft and active_draft.status() or false,
            platform_checked = platform_attempted,
        }, "application status")
    end

    ---Closes the current in-memory draft and prevents further dispatch.
    function application.close()
        if lifecycle == "closed" then return false end
        if active_draft then active_draft.close() end
        active_draft = nil
        lifecycle = "closed"
        return true
    end

    application.product_name = admitted.product_name
    application.product_version = admitted.product_version
    application.release_target = admitted.release_target
    return readonly(application, "application composition root")
end

return M
