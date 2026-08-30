--[[
File: config_generation_test.lua
Date: 2026-08-29
Author: WaterRun
Description: Verifies stale-bound configuration drafts and atomic publication order.
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

local config = load_module("config")
local sha256 = load_table("test/support/sha256_reference.lua")
local fake_filesystem = load_table("test/support/fake_filesystem.lua")

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

local function options()
    return {
        schema_version = "0.1.0",
        release_ca_path = "/opt/yaca/cacert.pem",
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

local function source(log_level, extra_agent)
    return table.concat({
        "; preserve this comment",
        "[General]",
        "SchemaVersion = 0.1.0",
        "LogLevel = " .. (log_level or "info"),
        "",
        "[Agent]",
        "QueueMaxItems = 9",
        extra_agent or "",
        "",
        "[Permission.Std]",
        "Read = allow",
        "Write = confirm",
        "Delete = confirm",
        "Shell = confirm",
        "OutsideWorkspace = confirm",
        "",
        "[Model.Primary]",
        "Enabled = true",
        "Protocol = openai-chat",
        "Endpoint = \"https://api.example/v1/chat\"",
        "RemoteModel = \"remote-main\"",
        "Key = \"original-secret\"",
        "",
    }, "\n")
end

local function codec(filesystem)
    return assert(config.new({
        sha256 = hash_port(),
        filesystem = filesystem,
    }, options()))
end

local CONFIG_PATH = "/data/config.ini"
local TEMP_PATH = "/data/config.ini.yaca-tmp"

local function setup_sections(key)
    return {
        {
            name = "General",
            values = { SchemaVersion = "0.1.0", StartupSelfTest = "off" },
        },
        {
            name = "Permission.Std",
            values = {
                Read = "allow",
                Write = "confirm",
                Delete = "confirm",
                Shell = "confirm",
                OutsideWorkspace = "confirm",
            },
        },
        {
            name = "Model.Primary",
            values = {
                Enabled = true,
                Protocol = "openai-chat",
                Endpoint = "https://api.example/v1/chat",
                RemoteModel = "remote-main",
                Key = key,
            },
        },
    }
end

return {
    name = "integration/config-generation",
    cases = {
        {
            name = "existing edits recheck base write validate replace and flush directory",
            run = function()
                local filesystem, controls = fake_filesystem.new({
                    [CONFIG_PATH] = source(),
                }, 19)
                local service = codec(filesystem)
                local draft = assert(service.begin_edit(CONFIG_PATH))
                local edited = assert(service.edit_draft(draft, {
                    { section = "General", key = "LogLevel", value = "debug" },
                    { section = "Model.Primary", key = "Key", value = "new-secret-value" },
                }))
                local preview = assert(service.draft_generation(edited))
                A.equal(preview.general.log_level, "debug")
                A.equal(
                    assert(preview.reveal_secret(
                        "Model.Primary.Key",
                        "model-auth:Primary"
                    )),
                    "new-secret-value"
                )
                local generation = assert(service.commit_draft(edited, TEMP_PATH))
                A.equal(generation.general.log_level, "debug")
                A.equal(service.current(), generation)
                A.contains(controls.bytes(CONFIG_PATH), "; preserve this comment")
                A.contains(controls.bytes(CONFIG_PATH), "LogLevel = debug")
                A.contains(controls.bytes(CONFIG_PATH), "Key = \"new-secret-value\"")
                A.falsy(controls.exists(TEMP_PATH))
                A.equal(controls.permissions(CONFIG_PATH), 384)
                A.equal(controls.created_permissions[TEMP_PATH], 384)
                local operations = table.concat(controls.operations, "|")
                A.contains(operations, "create:" .. TEMP_PATH)
                A.contains(operations, "flush-file")
                A.contains(operations, "replace")
                A.contains(operations, "flush-directory:/data")
            end,
        },
        {
            name = "external replacement makes a draft stale before any temporary write",
            run = function()
                local filesystem, controls = fake_filesystem.new({
                    [CONFIG_PATH] = source(),
                })
                local service = codec(filesystem)
                local draft = assert(service.begin_edit(CONFIG_PATH))
                local edited = assert(service.edit_draft(draft, {
                    { section = "General", key = "LogLevel", value = "debug" },
                }))
                controls.external_replace(CONFIG_PATH, source("warn"))
                local generation, commit_error = service.commit_draft(edited, TEMP_PATH)
                A.falsy(generation)
                A.equal(commit_error.code, "ConfigStale")
                A.contains(controls.bytes(CONFIG_PATH), "LogLevel = warn")
                A.falsy(controls.exists(TEMP_PATH))
                A.falsy(table.concat(controls.operations, "|"):find(
                    "create:" .. TEMP_PATH,
                    1,
                    true
                ))
            end,
        },
        {
            name = "temporary corruption and replace failure preserve the old target",
            run = function()
                local filesystem, controls = fake_filesystem.new({
                    [CONFIG_PATH] = source(),
                })
                local service = codec(filesystem)
                local draft = assert(service.edit_draft(
                    assert(service.begin_edit(CONFIG_PATH)),
                    { { section = "General", key = "LogLevel", value = "debug" } }
                ))
                controls.faults.corrupt_after_write_close = true
                local generation, commit_error = service.commit_draft(draft, TEMP_PATH)
                A.falsy(generation)
                A.equal(commit_error.code, "ConfigTemporaryMismatch")
                A.contains(controls.bytes(CONFIG_PATH), "LogLevel = info")
                A.falsy(controls.exists(TEMP_PATH))

                draft = assert(service.edit_draft(
                    assert(service.begin_edit(CONFIG_PATH)),
                    { { section = "General", key = "LogLevel", value = "warn" } }
                ))
                controls.faults.replace = true
                generation, commit_error = service.commit_draft(draft, TEMP_PATH)
                A.falsy(generation)
                A.equal(commit_error.code, "InjectedReplace")
                A.contains(controls.bytes(CONFIG_PATH), "LogLevel = info")
                A.falsy(controls.exists(TEMP_PATH))
            end,
        },
        {
            name = "structural unset uses canonical fallback and remains fully validated",
            run = function()
                local filesystem, controls = fake_filesystem.new({
                    [CONFIG_PATH] = source("info", "MaxTurnToolCalls = 8"),
                })
                local service = codec(filesystem)
                local edited = assert(service.edit_draft(
                    assert(service.begin_edit(CONFIG_PATH)),
                    {
                        {
                            section = "Agent",
                            key = "MaxTurnToolCalls",
                            value = service.unset,
                        },
                    }
                ))
                local preview = assert(service.draft_generation(edited))
                A.falsy(preview.agent.max_turn_tool_calls)
                assert(service.commit_draft(edited, TEMP_PATH))
                A.falsy(controls.bytes(CONFIG_PATH):find("MaxTurnToolCalls", 1, true))
                A.falsy(controls.bytes(CONFIG_PATH):find("preserve this comment", 1, true))
            end,
        },
        {
            name = "new config is no-replace and directory-flush failure is typed unknown",
            run = function()
                local filesystem, controls = fake_filesystem.new()
                local service = codec(filesystem)
                local draft = assert(service.begin_new(CONFIG_PATH, source()))
                local generation = assert(service.commit_draft(draft, TEMP_PATH))
                A.equal(generation.current_model, "Primary")
                A.truthy(controls.exists(CONFIG_PATH))
                A.equal(controls.permissions(CONFIG_PATH), 384)
                A.contains(table.concat(controls.operations, "|"), "rename-no-replace")

                controls.external_replace(CONFIG_PATH, source("warn"))
                local conflict, conflict_error = service.begin_new(CONFIG_PATH, source())
                A.falsy(conflict)
                A.equal(conflict_error.code, "ConfigConflict")

                local second_path = "/data/second.ini"
                local second_temp = "/data/second.ini.yaca-tmp"
                local second = assert(service.begin_new(second_path, source("debug")))
                controls.faults.flush_directory = true
                local unknown, unknown_error = service.commit_draft(second, second_temp)
                A.falsy(unknown)
                A.equal(unknown_error.code, "ConfigPublishUnknown")
                A.contains(controls.bytes(second_path), "LogLevel = debug")
                A.falsy(controls.exists(second_temp))
            end,
        },
        {
            name = "typed first setup and exact template repair publish no secret projection",
            run = function()
                local filesystem, controls = fake_filesystem.new()
                local service = codec(filesystem)
                local draft = assert(service.begin_new_values(
                    CONFIG_PATH,
                    setup_sections("first-secret")
                ))
                local preview = assert(service.draft_generation(draft))
                A.truthy(preview.models.Primary.key_configured)
                A.falsy(preview.models.Primary.key)
                A.equal(assert(preview.reveal_secret(
                    "Model.Primary.Key",
                    "model-auth:Primary"
                )), "first-secret")
                assert(service.commit_draft(draft, TEMP_PATH))
                A.contains(controls.bytes(CONFIG_PATH), "Key = \"first-secret\"")

                local repair_path = "/data/repair.ini"
                local repair_temp = "/data/repair.ini.yaca-tmp"
                local repair_source = table.concat({
                    "[General]",
                    "SchemaVersion = 0.1.0",
                    "",
                    "[Permission.Std]",
                    "Read = allow",
                    "Write = confirm",
                    "Delete = confirm",
                    "Shell = confirm",
                    "OutsideWorkspace = confirm",
                    "",
                    "[Model.Primary]",
                    "Enabled = false",
                    "Protocol = openai-chat",
                    "",
                }, "\n")
                controls.external_replace(repair_path, repair_source)
                local repair = assert(service.begin_exact_repair_values(
                    repair_path,
                    repair_source,
                    setup_sections("repair-secret")
                ))
                assert(service.commit_draft(repair, repair_temp))
                A.contains(controls.bytes(repair_path), "Key = \"repair-secret\"")

                controls.external_replace(repair_path, repair_source .. "; user edit\n")
                local mismatched, mismatch_error = service.begin_exact_repair_values(
                    repair_path,
                    repair_source,
                    setup_sections("must-not-publish")
                )
                A.falsy(mismatched)
                A.equal(mismatch_error.code, "ConfigRepairMismatch")
                A.contains(controls.bytes(repair_path), "; user edit")
            end,
        },
    },
}
