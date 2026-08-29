--[[
File: config_test.lua
Date: 2026-08-29
Author: WaterRun
Description: Verifies the complete typed catalog, limits, secrets, and generations.
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
local sha256 = load_table("test/support/sha256_reference.lua")
local contract = load_table(".develope-docs/contracts/config.lua")
local fixtures = load_table(".develope-docs/contracts/fixtures/config.lua")

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

local function options(overrides)
    local result = {
        schema_version = "0.1.0",
        release_ca_path = "/opt/yaca/bin/cacert.pem",
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
        maximum_hash_chunk_bytes = 7,
        minimum_scannable_secret_bytes = 8,
        adapter_option_schemas = {
            ["openai-chat"] = {
                PublicMode = { type = "string" },
                SecretHeader = { type = "string", secret = true },
                IntegerMode = { type = "integer" },
            },
        },
    }
    for key, value in pairs(overrides or {}) do result[key] = value end
    return result
end

local function source(extra)
    extra = extra or {}
    return table.concat({
        "; exact source bytes are hashed privately",
        "[General]",
        "SchemaVersion = 0.1.0",
        "SystemPrompt = \"global\\nrule\"",
        "LogLevel = " .. (extra.log_level or "info"),
        "",
        "[Agent]",
        "QueueMaxItems = " .. (extra.queue_max or "9"),
        extra.agent_extra or "",
        "",
        "[Permission.Std]",
        "Description = \"Standard\"",
        "Read = allow",
        "Write = confirm",
        "Delete = confirm",
        "Shell = confirm",
        "OutsideWorkspace = confirm",
        "",
        "[Permission.Readonly]",
        "Read = allow",
        "Write = deny",
        "Delete = deny",
        "Shell = deny",
        "OutsideWorkspace = deny",
        "",
        "[Model.Primary]",
        "Enabled = true",
        "Protocol = openai-chat",
        "Endpoint = \"" .. (extra.endpoint or "https://api.example/v1/chat") .. "\"",
        "RemoteModel = \"remote-main\"",
        "Key = \"" .. (extra.key or "canary-secret") .. "\"",
        extra.model_extra or "",
        "",
        "[Model.Disabled]",
        "Enabled = false",
        "Protocol = anthropic-messages",
        "",
    }, "\n")
end

local function codec(option_overrides)
    return assert(config.new({ sha256 = hash_port() }, options(option_overrides)))
end

local function by_source(advice)
    local result = {}
    for _, item in ipairs(advice) do result[item.source] = item.action end
    return result
end

return {
    name = "unit/config",
    cases = {
        {
            name = "runtime catalog is exactly the frozen complete field catalog",
            run = function()
                local service = codec()
                A.equal(#service.catalog, #contract.fields)
                for index, expected in ipairs(contract.fields) do
                    local actual = service.catalog[index]
                    A.equal(actual.id, expected.id, tostring(index))
                    A.equal(actual.section, expected.section, expected.id)
                    A.equal(actual.key, expected.key, expected.id)
                    A.equal(actual.secret, expected.secret, expected.id)
                    A.equal(actual.required, expected.required == true, expected.id)
                end
                A.raises(function() service.catalog[1].key = "Changed" end, "cannot be modified")
                A.falsy(service.target_atomic_write_qualified)
            end,
        },
        {
            name = "minimal complete INI receives typed defaults and physical-order selectors",
            run = function()
                local generation = assert(codec().parse(source()))
                A.equal(generation.id, "config-generation-1")
                A.equal(generation.general.schema_version, "0.1.0")
                A.equal(generation.general.system_prompt, "global\nrule")
                A.equal(generation.general.startup_self_test, "off")
                A.equal(generation.tui.startup_show_slogan, true)
                A.equal(generation.tui.startup_show_data_root, false)
                A.equal(generation.agent.queue_max_items, 9)
                A.equal(generation.agent.compact_threshold, 0.75)
                A.equal(generation.network.ca_bundle_path, "/opt/yaca/bin/cacert.pem")
                A.equal(generation.exec.max_output_kb, 1024)
                A.equal(generation.context.auto_name_every_main_turns, 10)
                A.equal(generation.models.Primary.retry_count, 2)
                A.equal(generation.default_model, "Primary")
                A.equal(generation.default_permission, "Std")
                A.equal(generation.current_model, "Primary")
                A.equal(generation.current_permission, "Std")
                A.truthy(generation.agent_ready)
                A.equal(assert(generation.get("Agent", "QueueMaxItems")), 9)
                local optional, optional_error = generation.get(
                    "Agent",
                    "MaxTurnToolCalls"
                )
                A.falsy(optional)
                A.falsy(optional_error)
                A.raises(function() generation.agent.queue_max_items = 1 end,
                    "cannot be modified")
                A.raises(function() generation.models.Primary.enabled = false end,
                    "cannot be modified")
            end,
        },
        {
            name = "registered secrets stay private and use exact destinations",
            run = function()
                local service = codec()
                local generation = assert(service.parse(source({
                    endpoint = "http://api.example/v1/chat",
                })))
                A.equal(generation.models.Primary.key_configured, true)
                local hidden, hidden_error = generation.get("Model.Primary", "Key")
                A.falsy(hidden)
                A.equal(hidden_error.code, "RegisteredSecret")
                A.equal(
                    assert(generation.reveal_secret(
                        "Model.Primary.Key",
                        "model-auth:Primary"
                    )),
                    "canary-secret"
                )
                local denied, denied_error = generation.reveal_secret(
                    "Model.Primary.Key",
                    "ordinary-error"
                )
                A.falsy(denied)
                A.equal(denied_error.code, "SecretDestinationDenied")
                local hits = assert(generation.scan_registered_secrets("xcanary-secrety"))
                A.equal(#hits, 1)
                A.equal(hits[1].id, "Model.Primary.Key")
                A.falsy(A.render(generation):find("canary-secret", 1, true))
                A.equal(generation.warnings[1].code, "PlainHttpCredential")
            end,
        },
        {
            name = "conditional proxy and adapter secrets are typed registry entries",
            run = function()
                local extra = table.concat({
                    "AdapterOptions = \"{\\\"IntegerMode\\\":3,",
                    "\\\"PublicMode\\\":\\\"fast\\\",",
                    "\\\"SecretHeader\\\":\\\"adapter-secret\\\"}\"",
                })
                local candidate = source({ model_extra = extra }):gsub(
                    "%[Agent%]",
                    "[Network]\nProxyUrl = \"https://user:pass@proxy.example\"\n\n[Agent]",
                    1
                )
                local generation = assert(codec().parse(candidate))
                A.falsy(generation.network.proxy_url)
                A.truthy(generation.network.proxy_url_configured)
                A.equal(generation.models.Primary.adapter_options.PublicMode, "fast")
                A.equal(generation.models.Primary.adapter_options.IntegerMode, 3)
                A.truthy(
                    generation.models.Primary.adapter_options.SecretHeader.registered_secret
                )
                A.equal(
                    assert(generation.reveal_secret("Network.ProxyUrl", "network-proxy")),
                    "https://user:pass@proxy.example"
                )
                A.equal(
                    assert(generation.reveal_secret(
                        "Model.Primary.AdapterOptions.SecretHeader",
                        "model-adapter:Primary:SecretHeader"
                    )),
                    "adapter-secret"
                )
            end,
        },
        {
            name = "context whitelist creates a new immutable effective snapshot",
            run = function()
                local service = codec()
                local generation = assert(service.parse(source(), {
                    CurrentModel = "Disabled",
                    CurrentPermission = "Readonly",
                    DoubleCheckOverride = false,
                    DoubleCheckGoalOverride = "review exact result",
                    ContextPrompt = "context rule",
                    AutoRenameDisabled = true,
                }))
                A.equal(generation.current_model, "Disabled")
                A.equal(generation.current_permission, "Readonly")
                A.equal(generation.effective_double_check, false)
                A.equal(generation.effective_double_check_goal, "review exact result")
                A.equal(generation.context_prompt, "context rule")
                A.truthy(generation.auto_rename_disabled)
                A.falsy(generation.agent_ready)
                A.equal(generation.agent_block_reason, "SelectedModelUnavailable")
                local invalid, invalid_error = service.parse(source(), { Endpoint = "bad" })
                A.falsy(invalid)
                A.equal(invalid_error.reason, "context-override-unknown")
                A.falsy(service.parse(source(), { CurrentPermission = "Missing" }))
            end,
        },
        {
            name = "reload reuses exact bindings and invalid changes fail closed",
            run = function()
                local service = codec()
                local first = assert(service.reload(source()))
                A.equal(service.reload(source()), first)
                local second = assert(service.reload(source({ log_level = "debug" })))
                A.truthy(second ~= first)
                A.equal(second.id, "config-generation-2")
                A.equal(second.general.log_level, "debug")
                local invalid, invalid_error = service.reload(source({ queue_max = "65" }))
                A.falsy(invalid)
                A.equal(invalid_error.code, "ConfigInvalid")
                A.equal(invalid_error.reason, "integer-limit")
                A.equal(service.current(), second)
                local third = assert(service.reload(source({ log_level = "debug" }), {
                    CurrentPermission = "Readonly",
                }))
                A.equal(third.id, "config-generation-3")
                A.equal(service.current(), third)
            end,
        },
        {
            name = "unknown fields duplicates types references and limits fail closed",
            run = function()
                local service = codec()
                local cases = {
                    {
                        source():gsub("QueueMaxItems = 9", "QueueMaxItems = 9\nUnknownLimit = 1"),
                        "ini",
                    },
                    { source() .. "\n[General]\nLogLevel = debug\n", "duplicate-section" },
                    { source({ queue_max = "0" }), "integer-limit" },
                    { source({ queue_max = "65" }), "integer-limit" },
                    { source():gsub("SchemaVersion = 0.1.0", "SchemaVersion = 0.2.0"),
                        "schema-version" },
                    { source({ agent_extra = "ActionReviewModel = \"Missing\"" }),
                        "reviewer-model" },
                    { source({ endpoint = "https://user:pass@api.example/v1/chat" }),
                        "endpoint-credentials" },
                    { source():gsub("Enabled = true", "Enabled = false", 1),
                        "enabled-model-missing" },
                    { source({ model_extra = "MaxOutputTokens = false" }),
                        "numeric-false-migration" },
                    { source():gsub(
                        "SystemPrompt = \"global\\nrule\"",
                        "SystemPrompt = \"canary-secret\"",
                        1
                    ), "registered-secret-cross-field" },
                    { source():gsub(
                        "%[Agent%]",
                        "[Network]\nNoProxy = \"good,,bad\"\n\n[Agent]",
                        1
                    ), "host-pattern-list" },
                }
                for _, case in ipairs(cases) do
                    local generation, generation_error = service.parse(case[1])
                    A.falsy(generation, case[2])
                    A.equal(generation_error.code, "ConfigInvalid", case[2])
                    A.equal(generation_error.reason, case[2], case[2])
                end
            end,
        },
        {
            name = "every frozen migration fixture maps to one value-free action",
            run = function()
                local service = codec()
                local legacy = table.concat({
                    "[Model.Old]",
                    "CustomPrompt = \"do not project this value\"",
                    "MaxOutputTokens = false",
                    "[Permission.Legacy]",
                    "DoubleCheck = true",
                    "[Permission.Cautious]",
                    "Read = allow",
                    "[Network]",
                    "UseStunnel = true",
                    "[Context]",
                    "AutoJumpToDir = true",
                    "ResumeDirectory = true",
                }, "\n")
                local indexed = by_source(service.migration_advice(legacy))
                for _, case in ipairs(fixtures.migration_cases) do
                    A.equal(indexed[case.source], case.expected_action, case.id)
                end
                A.falsy(A.render(indexed):find("do not project this value", 1, true))
            end,
        },
        {
            name = "construction rejects incomplete Runtime limits and malformed schemas",
            run = function()
                local invalid = options()
                invalid.hard_limits = { queue_items = 64 }
                local service, service_error = config.new({ sha256 = hash_port() }, invalid)
                A.falsy(service)
                A.equal(service_error.code, "InvalidConfigOptions")

                invalid = options()
                invalid.hard_limits.queue_items = 8
                A.falsy(config.new({ sha256 = hash_port() }, invalid))

                invalid = options()
                invalid.adapter_option_schemas["openai-chat"].Bad = { type = "table" }
                A.falsy(config.new({ sha256 = hash_port() }, invalid))

                local service = codec()
                A.raises(function() service.schema_version = "changed" end,
                    "cannot be modified")
            end,
        },
    },
}
