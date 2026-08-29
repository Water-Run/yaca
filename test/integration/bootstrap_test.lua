--[[
File: bootstrap_test.lua
Date: 2026-08-29
Author: WaterRun
Description: Verifies offline bootstrap routing, Agent gates, and bare-draft behavior.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

local function load_module(name, cache)
    cache = cache or {}
    if cache[name] then return cache[name] end
    local environment = { require = function(dependency)
        return load_module(dependency, cache)
    end }
    environment._G = environment
    setmetatable(environment, { __index = _ENV })
    local chunk, load_error = loadfile(
        YACA_TEST_ROOT .. "/src/" .. name .. ".lua",
        "t",
        environment
    )
    A.truthy(chunk, load_error)
    local value = chunk()
    cache[name] = value
    return value
end

local function load_table(relative_path)
    local chunk, load_error = loadfile(YACA_TEST_ROOT .. "/" .. relative_path, "t", _ENV)
    A.truthy(chunk, load_error)
    return chunk()
end

local cache = {}
local config = load_module("config", cache)
local main = load_module("main", cache)
local sha256 = load_table("test/support/sha256_reference.lua")
local fake_filesystem = load_table("test/support/fake_filesystem.lua")

local CONFIG_PATH = "/release/__yaca__/config.ini"

local function hash_port()
    local port = {}

    function port.sha256_start()
        return { parts = {}, finished = false, closed = false }
    end

    function port.sha256_update(handle, bytes)
        assert(not handle.finished and not handle.closed)
        handle.parts[#handle.parts + 1] = bytes
        return true
    end

    function port.sha256_finish(handle)
        assert(not handle.finished and not handle.closed)
        handle.finished = true
        return sha256.digest(table.concat(handle.parts))
    end

    function port.sha256_close(handle)
        assert(not handle.closed)
        handle.closed = true
        return true
    end

    return port
end

local function config_options()
    return {
        schema_version = "0.1.0",
        release_ca_path = "/release/cacert.pem",
        ini_limits = {
            maximum_bytes = 65536,
            maximum_lines = 512,
            maximum_line_bytes = 4096,
            maximum_value_bytes = 16384,
        },
        hard_limits = {
            queue_items = 64,
            turn_model_requests = 64,
            turn_tool_calls = 256,
            connect_timeout_ms = 120000,
            response_bytes = 16777216,
            exec_timeout_ms = 3600000,
            exec_output_kb = 8192,
            auto_name_turns = 100000,
            recent_contexts = 10000,
            model_context_tokens = 2000000,
            model_output_tokens = 131072,
            request_timeout_ms = 3600000,
            retry_count = 10,
            retry_base_delay_ms = 60000,
        },
        runtime_defaults = { retry_count = 2 },
        maximum_text_bytes = 16384,
        maximum_name_bytes = 128,
        maximum_adapter_options_bytes = 4096,
        maximum_hash_chunk_bytes = 11,
        minimum_scannable_secret_bytes = 8,
    }
end

local function valid_source(settings)
    settings = settings or {}
    local model_sections = {}
    if settings.disabled_first then
        model_sections[#model_sections + 1] = table.concat({
            "[Model.Disabled]",
            "Enabled = false",
            "Protocol = openai-chat",
            "",
        }, "\n")
    end
    model_sections[#model_sections + 1] = table.concat({
        "[Model.Primary]",
        "Enabled = true",
        "Protocol = openai-chat",
        "Endpoint = \"https://api.example/v1/chat\"",
        "RemoteModel = \"remote-main\"",
        "Key = \"bootstrap-secret\"",
        "",
    }, "\n")
    return table.concat({
        "[General]",
        "SchemaVersion = 0.1.0",
        "StartupSelfTest = " .. (settings.startup_self_test or "off"),
        "",
        "[Permission.Std]",
        "Read = allow",
        "Write = confirm",
        "Delete = confirm",
        "Shell = confirm",
        "OutsideWorkspace = confirm",
        "",
        table.concat(model_sections, "\n"),
    }, "\n")
end

local function application(source)
    local initial = source and { [CONFIG_PATH] = source } or {}
    local filesystem, filesystem_controls = fake_filesystem.new(initial, 23)
    local config_service = assert(config.new({
        sha256 = hash_port(),
        filesystem = filesystem,
    }, config_options()))
    local calls = {
        platform = 0,
        config = 0,
        workspace = 0,
        stage1 = 0,
        management = 0,
        network = 0,
        catalog = 0,
        agent = 0,
        stage1_outcome = "passed",
        stage1_online_requests = 0,
    }
    local counted_config = {}
    function counted_config.reload_file(path)
        calls.config = calls.config + 1
        return config_service.reload_file(path)
    end
    setmetatable(counted_config, { __index = config_service })

    local platform = {}
    function platform.identity()
        calls.platform = calls.platform + 1
        return {
            os = "linux",
            arch = "x86_64",
            target = "linux-x86_64",
            supported = true,
        }
    end

    local workspace = {}
    function workspace.inspect(requested)
        calls.workspace = calls.workspace + 1
        return {
            path = requested == "." and "/workspace" or requested,
            enterable = true,
            identity = { object = "workspace-1" },
        }
    end

    local stage1 = { online = false }
    function stage1.run(request)
        calls.stage1 = calls.stage1 + 1
        calls.catalog = calls.catalog + 1
        calls.last_stage1 = request
        return {
            outcome = calls.stage1_outcome,
            online_requests = calls.stage1_online_requests,
            check_count = 15,
        }
    end

    local management = { online = false }
    function management.run(request)
        calls.management = calls.management + 1
        calls.last_management = request
        if request.action == "context-repl" then calls.catalog = calls.catalog + 1 end
        return {
            outcome = "success",
            action = request.action,
            config_error = request.config_error and request.config_error.code or false,
        }
    end

    local app = assert(main.new({
        platform = platform,
        config = counted_config,
        workspace = workspace,
        stage1 = stage1,
        management = management,
        network = { request = function() calls.network = calls.network + 1 end },
        context_catalog = { scan = function() calls.catalog = calls.catalog + 1 end },
        agent = { start = function() calls.agent = calls.agent + 1 end },
    }, {
        product_name = "yaca",
        product_version = "0.1.0-dev",
        release_target = "linux-x86_64",
        config_path = CONFIG_PATH,
        maximum_draft_bytes = 4096,
    }))
    return app, calls, filesystem_controls
end

return {
    name = "integration/bootstrap",
    cases = {
        {
            name = "construction help and version perform no probes reads scans or network",
            run = function()
                local app, calls = application(nil)
                A.deep_equal(app.status(), {
                    lifecycle = "constructed",
                    active_draft = false,
                    platform_checked = false,
                })
                local help = assert(app.dispatch({ id = "help" }))
                local version = assert(app.dispatch({ id = "version", machine = true }))
                A.equal(help.outcome, "success")
                A.equal(version.version, "0.1.0-dev")
                A.equal(calls.platform, 0)
                A.equal(calls.config, 0)
                A.equal(calls.workspace, 0)
                A.equal(calls.stage1, 0)
                A.equal(calls.management, 0)
                A.equal(calls.catalog, 0)
                A.equal(calls.network, 0)
                A.equal(calls.agent, 0)
            end,
        },
        {
            name = "all management routes remain available with missing or invalid config",
            run = function()
                local app, calls = application(nil)
                local config_result = assert(app.dispatch({ id = "config-repl" }))
                A.equal(config_result.config_error, "ConfigMissing")
                A.equal(calls.management, 1)
                A.equal(calls.catalog, 0)
                A.equal(calls.network, 0)
                assert(app.dispatch({ id = "context-repl", view = "recent" }))
                A.equal(calls.catalog, 1)
                A.equal(calls.network, 0)

                app, calls = application("[General]\nUnknown = true\n")
                local model_result = assert(app.dispatch({ id = "model-repl" }))
                A.equal(model_result.config_error, "ConfigInvalid")
                A.equal(calls.management, 1)
                A.equal(calls.network, 0)
                A.equal(calls.agent, 0)
            end,
        },
        {
            name = "Stage 1 runs offline even when the main configuration is invalid",
            run = function()
                local app, calls = application("[General]\nUnknown = true\n")
                local result = assert(app.dispatch({
                    id = "self-test",
                    through_stage = 1,
                }))
                A.equal(result.outcome, "passed")
                A.equal(calls.stage1, 1)
                A.equal(calls.last_stage1.config_error.code, "ConfigInvalid")
                A.equal(calls.catalog, 1)
                A.equal(calls.network, 0)
                A.equal(calls.agent, 0)

                local online, online_error = app.dispatch({
                    id = "self-test",
                    through_stage = 2,
                })
                A.falsy(online)
                A.equal(online_error.code, "OnlineConsentRequired")
                A.equal(calls.network, 0)

                online, online_error = app.dispatch({
                    id = "self-test",
                    through_stage = 2,
                    online_consent = true,
                })
                A.falsy(online)
                A.equal(online_error.code, "SelfTestStageUnavailable")
                A.equal(calls.network, 0)
            end,
        },
        {
            name = "Stage 1 rejects any handler that reports an online request",
            run = function()
                local app, calls = application(valid_source())
                calls.stage1_online_requests = 1
                local result, result_error = app.dispatch({ id = "self-test" })
                A.falsy(result)
                A.equal(result_error.code, "Stage1Contract")
                A.equal(calls.network, 0)
            end,
        },
        {
            name = "chat is blocked by missing invalid or selected-unavailable Model config",
            run = function()
                local cases = {
                    { false, "ConfigMissing" },
                    { "[General]\nUnknown = true\n", "ConfigInvalid" },
                    { valid_source({ disabled_first = true }), "ModelUnavailable" },
                }
                for _, case in ipairs(cases) do
                    local app, calls = application(case[1])
                    local result, result_error = app.dispatch({ id = "run-chat" })
                    A.falsy(result)
                    A.equal(result_error.code, case[2])
                    A.equal(calls.network, 0)
                    A.equal(calls.catalog, 0)
                    A.equal(calls.agent, 0)
                    A.equal(calls.stage1, 0)
                end
            end,
        },
        {
            name = "bare chat creates only a bounded not-saved draft and never scans history",
            run = function()
                local app, calls, filesystem = application(valid_source())
                local result = assert(app.dispatch({ id = "run-chat" }))
                A.equal(result.outcome, "ready")
                A.equal(result.status.lifecycle, "not-saved")
                A.falsy(result.status.durable)
                A.equal(result.status.display_name, "not saved")
                A.equal(result.status.workspace, "/workspace")
                A.equal(calls.config, 1)
                A.equal(calls.workspace, 1)
                A.equal(calls.catalog, 0)
                A.equal(calls.network, 0)
                A.equal(calls.agent, 0)
                A.equal(calls.stage1, 0)
                A.falsy(A.render(result.status):find("bootstrap-secret", 1, true))
                A.falsy(table.concat(filesystem.operations, "|"):find(
                    "CONTEXT",
                    1,
                    true
                ))

                local updated = assert(result.draft.update({
                    permission = "Std",
                    double_check = false,
                    context_prompt = "draft-only preference",
                }))
                A.equal(updated.double_check, false)
                A.equal(updated.context_prompt, "draft-only preference")
                local rejected, reject_error = result.draft.update({
                    context_prompt = "bootstrap-secret",
                })
                A.falsy(rejected)
                A.equal(reject_error.code, "RegisteredSecret")
                rejected, reject_error = result.draft.update({
                    context_prompt = string.rep("x", 4096),
                })
                A.falsy(rejected)
                A.equal(reject_error.code, "DraftLimit")
                local accepted, accept_error = result.draft.begin_main("do work")
                A.falsy(accepted)
                A.equal(accept_error.code, "ContextPublicationUnavailable")
                A.equal(calls.network, 0)
                A.equal(calls.agent, 0)
                A.truthy(app.close())
                A.equal(result.draft.status().lifecycle, "closed")
            end,
        },
        {
            name = "configured startup checks run Stage 1 but never imply online consent",
            run = function()
                local app, calls = application(valid_source({ startup_self_test = "stage1" }))
                local result = assert(app.dispatch({ id = "run-chat" }))
                A.equal(result.outcome, "ready")
                A.equal(calls.stage1, 1)
                A.equal(calls.catalog, 1)
                A.equal(calls.network, 0)

                app, calls = application(valid_source({ startup_self_test = "stage1" }))
                calls.stage1_outcome = "partial"
                result, result_error = app.dispatch({ id = "run-chat" })
                A.falsy(result)
                A.equal(result_error.code, "StartupSelfTestFailed")
                A.equal(calls.network, 0)

                app, calls = application(valid_source({ startup_self_test = "stage2" }))
                result, result_error = app.dispatch({ id = "run-chat" })
                A.falsy(result)
                A.equal(result_error.code, "OnlineConsentRequired")
                A.equal(calls.stage1, 1)
                A.equal(calls.network, 0)
            end,
        },
        {
            name = "invalid requests and online-declared bootstrap ports fail before dispatch",
            run = function()
                local app, calls = application(valid_source())
                local result, result_error = app.dispatch({
                    id = "run-chat",
                    surprise = true,
                })
                A.falsy(result)
                A.equal(result_error.code, "UsageError")
                A.equal(calls.platform, 0)
                A.equal(calls.config, 0)

                local invalid, invalid_error = main.new({
                    platform = { identity = function() return {} end },
                    config = { reload_file = function() return nil end },
                    workspace = { inspect = function() return nil end },
                    stage1 = { online = true, run = function() return {} end },
                    management = { online = false, run = function() return {} end },
                }, {
                    product_name = "yaca",
                    product_version = "0.1.0-dev",
                    release_target = "linux-x86_64",
                    config_path = CONFIG_PATH,
                    maximum_draft_bytes = 4096,
                })
                A.falsy(invalid)
                A.equal(invalid_error.code, "InvalidBootstrapComponents")
            end,
        },
    },
}
