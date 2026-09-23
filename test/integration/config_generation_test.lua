--[[
Author: WaterRun
Date: 2026-09-23
File: config_generation_test.lua
Description: Verifies stale-bound configuration drafts and atomic publication order.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

--Loads a source module into an isolated per-case environment.
--@param name string Module, Model, or resource name selected by the case.
--@param cache table Per-case module cache preserving isolated imports.
--@return any module Module export loaded in the isolated source environment.
local function load_module(name, cache)
    cache = cache or {}
    if cache[name] then return cache[name] end
    local environment = {
        --Resolves an imported Lua module through the isolated test loader.
        --@param dependency string Source module requested from the isolated loader.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        require = function(dependency)
        return load_module(dependency, cache)
    end }
    environment._G = environment
    --@metatable environment Test-owned lookup and mutation contract for the current case.
    --@field __index any Fallback table or function used for missing fixture keys.
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

--Loads a repository Lua module as a test support value.
--@param relative_path string Repository-relative Lua source path to load.
--@return any module Test support module export loaded from the repository.
local function load_table(relative_path)
    local chunk, load_error = loadfile(YACA_TEST_ROOT .. "/" .. relative_path, "t", _ENV)
    A.truthy(chunk, load_error)
    return chunk()
end

local config = load_module("config")
local sha256 = load_table("test/support/sha256_reference.lua")
local fake_filesystem = load_table("test/support/fake_filesystem.lua")

--Constructs an incremental SHA-256 port backed by the reference digest.
--@param none No arguments; this closure uses its captured fixture state.
--@return any port Incremental SHA-256 fixture port.
local function hash_port()
    local port = {}

    --Starts a fake incremental SHA-256 handle.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return table handle New incremental SHA-256 fixture handle.
    function port.sha256_start()
        return { parts = {}, finished = false, closed = false }
    end

    --Adds bytes to the fake incremental SHA-256 handle.
    --@param handle table|integer Fake resource handle whose state is inspected.
    --@param bytes string Byte chunk supplied to the fake I/O port.
    --@return boolean accepted Whether the fixture accepted the byte chunk.
    function port.sha256_update(handle, bytes)
        assert(not handle.finished and not handle.closed)
        handle.parts[#handle.parts + 1] = bytes
        return true
    end

    --Finalizes the fake SHA-256 handle using the reference digest.
    --@param handle table|integer Fake resource handle whose state is inspected.
    --@return any digest Hexadecimal digest of the accumulated fixture bytes.
    function port.sha256_finish(handle)
        assert(not handle.finished and not handle.closed)
        handle.finished = true
        return sha256.digest(table.concat(handle.parts))
    end

    --Closes the fake SHA-256 handle and records its state.
    --@param handle table|integer Fake resource handle whose state is inspected.
    --@return boolean closed Whether the fixture handle was closed.
    function port.sha256_close(handle)
        assert(not handle.closed)
        handle.closed = true
        return true
    end

    return port
end

--Builds validated options for this suite's component fixture.
--@param none No arguments; this closure uses its captured fixture state.
--@return table options options used to configure the component under test.
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

--Supplies source behavior required by this suite.
--@param log_level any The log level supplied to the fake service for this scenario.
--@param extra_agent any The extra agent supplied to the fake service for this scenario.
--@return any observed source value observed by the scenario assertion.
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

--Constructs the codec service used by this suite.
--@param filesystem table Fake filesystem whose operations are observed.
--@return any fixture Constructed codec service used by this suite.
local function codec(filesystem)
    return assert(config.new({
        sha256 = hash_port(),
        filesystem = filesystem,
    }, options()))
end

local CONFIG_PATH = "/data/config.ini"
local TEMP_PATH = "/data/config.ini.yaca-tmp"

--Supplies setup sections behavior required by this suite.
--@param key string|integer Lookup key selected by the operation.
--@return table observed Structured fixture record selected by the exercised branch.
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
            name = "configuration publication accepts final write time observed after close",
            -- Publish actual INI bytes through the editor while the fixture finalizes timestamps at close.
            --@param none No arguments.
            --@return nil Assertions complete without returning a value.
            --@effect Creates and replaces files only in the isolated fixture.
            run = function()
                local filesystem, controls = fake_filesystem.new({ [CONFIG_PATH] = source() })
                controls.close_updates_modified = true
                local service = codec(filesystem)
                local draft = assert(service.begin_edit(CONFIG_PATH))
                draft = assert(service.edit_draft(draft, {
                    { section = "General", key = "LogLevel", value = "debug" },
                }))
                assert(service.commit_draft(draft, TEMP_PATH))
                A.contains(controls.bytes(CONFIG_PATH), "LogLevel = debug")
                A.falsy(controls.exists(TEMP_PATH))
            end,
        },
        {
            name = "failed temporary write leaves a foreign path replacement untouched",
            -- Exercise cleanup immediately after create when another object occupies the temporary path.
            --@param none No arguments.
            --@return nil Assertions complete without returning a value.
            --@effect Mutates only fake configuration files and an injected write port.
            run = function()
                local filesystem, controls = fake_filesystem.new({ [CONFIG_PATH] = source() })
                -- Replace the temporary path after the original creation handle was bound.
                --@param handle table Original temporary write handle.
                --@param bytes string Proposed bounded INI bytes rejected by this fixture.
                --@return boolean False because the write is deliberately rejected.
                --@return table InjectedWrite diagnostic returned to the editor.
                --@effect Replaces the fixture temporary path with a different file object.
                filesystem.stream_write = function(handle, bytes)
                    A.truthy(handle)
                    A.truthy(bytes)
                    controls.external_replace(TEMP_PATH, "foreign config")
                    return false, { code = "InjectedWrite", message = "fixture write failure" }
                end
                local service = codec(filesystem)
                local draft = assert(service.edit_draft(
                    assert(service.begin_edit(CONFIG_PATH)),
                    { { section = "General", key = "LogLevel", value = "debug" } }
                ))
                local published, problem = service.commit_draft(draft, TEMP_PATH)
                A.falsy(published)
                A.equal(problem.code, "InjectedWrite")
                A.equal(controls.bytes(TEMP_PATH), "foreign config")
                A.equal(controls.bytes(CONFIG_PATH), source())
            end,
        },
        {
            name = "same-byte temporary replacement after readback remains foreign",
            -- Replace the path on the second read with a same-byte but different-object file.
            --@param none No arguments.
            --@return nil Assertions complete without returning a value.
            --@effect Mutates only fake configuration files and an injected read port.
            run = function()
                local filesystem, controls = fake_filesystem.new({ [CONFIG_PATH] = source() })
                local original_open = filesystem.open_read
                local temporary_opens = 0
                local foreign_identity
                -- Preserve first post-close verification, then replace before the editor's second read.
                --@param path string Absolute path requested by the configuration reader.
                --@return boolean Whether the original fake port opened that path.
                --@return table Handle or structured fake-port error.
                --@effect Replaces the temporary on its second read while retaining identical bytes.
                filesystem.open_read = function(path)
                    if path == TEMP_PATH then
                        temporary_opens = temporary_opens + 1
                        if temporary_opens == 2 then
                            controls.external_replace(TEMP_PATH, controls.bytes(TEMP_PATH))
                            foreign_identity = controls.identity(TEMP_PATH)
                        end
                    end
                    return original_open(path)
                end
                local service = codec(filesystem)
                local draft = assert(service.edit_draft(
                    assert(service.begin_edit(CONFIG_PATH)),
                    { { section = "General", key = "LogLevel", value = "debug" } }
                ))
                local published, problem = service.commit_draft(draft, TEMP_PATH)
                A.falsy(published)
                A.equal(problem.code, "ConfigTemporaryMismatch")
                A.equal(temporary_opens, 2)
                A.equal(controls.identity(TEMP_PATH).object, foreign_identity.object)
                A.contains(controls.bytes(TEMP_PATH), "LogLevel = debug")
                A.equal(controls.bytes(CONFIG_PATH), source())
            end,
        },
        {
            name = "configuration admission guard rechecks before publication and cleans rejected temporaries",
            --Verifies configuration admission guard rechecks before publication and cleans rejected temporaries.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify configuration admission guard rechecks before publication and cleans rejected temporaries.
            run = function()
                for _, rejection in ipairs({ "first", "second", "throw", "source-change", "none" }) do
                    local filesystem, controls = fake_filesystem.new({ [CONFIG_PATH] = source() })
                    local service = codec(filesystem)
                    local draft = assert(service.begin_edit(CONFIG_PATH))
                    draft = assert(service.edit_draft(draft, {
                        { section = "General", key = "LogLevel", value = "debug" },
                    }))
                    local calls = 0
                    --Supplies an assertion callback for the configuration admission guard rechecks before publication and cleans rejected temporaries scenario.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return boolean|nil value Callback value consumed by the enclosing scenario assertion.
                    --@return table|nil secondary2 Typed error record with code ReferenceChanged.
                    local published, publish_error = service.commit_draft(draft, TEMP_PATH, function()
                        calls = calls + 1
                        if rejection == "throw" then error("private guard detail") end
                        if (rejection == "first" and calls == 1) or (rejection == "second" and calls == 2) then
                            return nil, { code = "ReferenceChanged", message = "reference changed" }
                        end
                        if rejection == "source-change" and calls == 2 then
                            controls.external_replace(CONFIG_PATH, source("warn"))
                        end
                        return true
                    end)
                    A.falsy(controls.exists(TEMP_PATH))
                    if rejection == "none" then
                        A.truthy(published)
                        A.equal(calls, 2)
                        A.contains(controls.bytes(CONFIG_PATH), "LogLevel = debug")
                    else
                        A.falsy(published)
                        A.equal(publish_error.code, rejection == "throw" and "ConfigPreconditionFailed"
                            or rejection == "source-change" and "ConfigStale" or "ReferenceChanged")
                        A.equal(controls.bytes(CONFIG_PATH), rejection == "source-change" and source("warn") or source())
                        if rejection == "first" or rejection == "throw" then
                            A.falsy(table.concat(controls.operations, "|"):find("create:", 1, true))
                        end
                        A.truthy(service.draft_generation(draft))
                    end
                end
            end,
        },
        {
            name = "Model add rename and move share one exact configuration transaction",
            --Verifies model add rename and move share one exact configuration transaction.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify model add rename and move share one exact configuration transaction.
            run = function()
                local original = source():gsub("%[Agent%]",
                    '[Agent]\nActionReviewModel = "Primary"', 1)
                    :gsub("%[Model.Primary%]", " [ Model.Primary ] ; retained model header", 1)
                local filesystem, controls = fake_filesystem.new({ [CONFIG_PATH] = original })
                local service = codec(filesystem)
                local base = assert(service.begin_edit(CONFIG_PATH))
                local draft = assert(service.add_model(base, "团队", {
                    Enabled = true, Protocol = "openai-chat", Endpoint = "https://new.example/chat",
                    RemoteModel = "new-model", ContextLength = 128000, MaxOutputTokens = 4096,
                }))
                A.falsy(assert(service.draft_generation(draft)).models["团队"].key_configured)
                draft = assert(service.manage_model(draft, "rename", "Primary", "Renamed"))
                draft = assert(service.manage_model(draft, "move", "团队", 1))
                local generation = assert(service.draft_generation(draft))
                A.deep_equal(generation.model_order, { "团队", "Renamed" })
                A.equal(generation.current_model, "团队")
                A.equal(generation.get("Agent", "ActionReviewModel"), "Renamed")
                A.equal(controls.bytes(CONFIG_PATH), original)
                assert(service.commit_draft(draft, TEMP_PATH))
                local published = controls.bytes(CONFIG_PATH)
                A.contains(published, 'ActionReviewModel = "Renamed"')
                A.contains(published, " [ Model.Renamed ] ; retained model header")
                A.contains(published, 'Key = "original-secret"')
                A.truthy(published:find("Model.团队", 1, true) < published:find("Model.Renamed", 1, true))
                A.equal(assert(service.draft_generation(base)).current_model, "Primary")
            end,
        },
        {
            name = "Model deletion preserves validity and never remaps external Context selectors",
            --Verifies model deletion preserves validity and never remaps external Context selectors.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify model deletion preserves validity and never remaps external Context selectors.
            run = function()
                local filesystem, controls = fake_filesystem.new({ [CONFIG_PATH] = source() })
                local service = codec(filesystem)
                local draft = assert(service.begin_edit(CONFIG_PATH))
                A.falsy(service.manage_model(draft, "delete", "Primary"))
                draft = assert(service.add_model(draft, "Disabled", { Enabled = false, Protocol = "openai-chat" }))
                A.falsy(service.manage_model(draft, "delete", "Primary"))
                draft = assert(service.add_model(draft, "Other", {
                    Enabled = true, Protocol = "openai-chat", Endpoint = "https://other.example/chat",
                    RemoteModel = "other-model",
                }))
                draft = assert(service.manage_model(draft, "delete", "Primary"))
                A.falsy(assert(service.draft_generation(draft)).agent_ready)
                assert(service.commit_draft(draft, TEMP_PATH))
                A.falsy(service.reload_file(CONFIG_PATH, { CurrentModel = "Primary" }))
                A.falsy(controls.bytes(CONFIG_PATH):find("original-secret", 1, true))
                draft = assert(service.begin_edit(CONFIG_PATH))
                draft = assert(service.manage_model(draft, "move", "Other", 1))
                A.truthy(assert(service.draft_generation(draft)).agent_ready)
            end,
        },
        {
            name = "Model management refuses case-fold collisions invalid operations and stale publications",
            --Verifies model management refuses case-fold collisions invalid operations and stale publications.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify model management refuses case-fold collisions invalid operations and stale publications.
            run = function()
                local filesystem, controls = fake_filesystem.new({ [CONFIG_PATH] = source() })
                local service = codec(filesystem)
                local base = assert(service.begin_edit(CONFIG_PATH))
                A.falsy(service.add_model(base, "pRIMARY", { Enabled = false, Protocol = "openai-chat" }))
                A.falsy(service.add_model(base, "New", { Enabled = false, Protocol = "openai-chat", Unknown = true }))
                A.falsy(service.manage_model(base, "clone", "Primary", "New"))
                A.falsy(service.manage_model(base, "move", "Primary", 2))
                A.falsy(service.manage_model({}, "rename", "Primary", "New"))
                local renamed = assert(service.manage_model(base, "rename", "Primary", "New"))
                controls.external_replace(CONFIG_PATH, source())
                local published, publish_error = service.commit_draft(renamed, TEMP_PATH)
                A.falsy(published)
                A.equal(publish_error.code, "ConfigStale")
                A.falsy(table.concat(controls.operations, "|"):find("create:", 1, true))
                A.falsy(service.reload(source() .. '[Model.primary]\nEnabled = false\nProtocol = openai-chat\n'))
            end,
        },
        {
            name = "invalid INI repair preserves exact untouched bytes and hides every source value",
            --Verifies invalid INI repair preserves exact untouched bytes and hides every source value.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify invalid INI repair preserves exact untouched bytes and hides every source value.
            run = function()
                local valid = "\239\187\191" .. source():gsub("\n", "\r\n")
                local original = valid .. '; private-comment-value\r\nUnknown = "unknown-secret"\r\n'
                local filesystem, controls = fake_filesystem.new({ [CONFIG_PATH] = original })
                local service = codec(filesystem)
                local base = assert(service.begin_repair(CONFIG_PATH))
                local status = assert(service.repair_status(base))
                A.falsy(status.valid)
                local display = A.render(status)
                for _, secret in ipairs({ "original-secret", "unknown-secret", "private-comment-value",
                    "api.example", "remote-main", "Primary" }) do
                    A.falsy(display:find(secret, 1, true))
                end
                local repaired = assert(service.edit_repair(base, "delete", status.lines))
                A.truthy(assert(service.repair_status(repaired)).valid)
                A.equal(controls.bytes(CONFIG_PATH), original)
                A.falsy(table.concat(controls.operations, "|"):find("create:", 1, true))
                assert(service.commit_repair(repaired, TEMP_PATH))
                A.equal(controls.bytes(CONFIG_PATH), valid .. '; private-comment-value\r\n')
                A.equal(controls.permissions(CONFIG_PATH), 384)
                A.falsy(service.repair_status(repaired))
                A.falsy(service.commit_repair(repaired, TEMP_PATH))
                A.falsy(service.begin_repair(CONFIG_PATH))
            end,
        },
        {
            name = "repair supports multiple invalid intermediate lines but writes only a complete valid candidate",
            --Verifies repair supports multiple invalid intermediate lines but writes only a complete valid candidate.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify repair supports multiple invalid intermediate lines but writes only a complete valid candidate.
            run = function()
                local original = source() .. '[Model.Primary]\nKey = "replacement-secret"\n'
                local filesystem, controls = fake_filesystem.new({ [CONFIG_PATH] = original })
                local service = codec(filesystem)
                local draft = assert(service.begin_repair(CONFIG_PATH))
                local count = assert(service.repair_status(draft)).lines
                draft = assert(service.edit_repair(draft, "delete", count - 1))
                A.falsy(assert(service.repair_status(draft)).valid)
                A.falsy(service.commit_repair(draft, TEMP_PATH))
                A.falsy(table.concat(controls.operations, "|"):find("create:", 1, true))
                draft = assert(service.edit_repair(draft, "delete", count - 1))
                draft = assert(service.edit_repair(draft, "insert", 1, "; explicit new comment"))
                assert(service.commit_repair(draft, TEMP_PATH))
                A.equal(controls.bytes(CONFIG_PATH), "; explicit new comment\n" .. source())
            end,
        },
        {
            name = "repair fixes invalid encoding and retains mixed endings and missing final newline",
            --Verifies repair fixes invalid encoding and retains mixed endings and missing final newline.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify repair fixes invalid encoding and retains mixed endings and missing final newline.
            run = function()
                local original = source() .. "\255broken\r"
                local filesystem, controls = fake_filesystem.new({ [CONFIG_PATH] = original })
                local service = codec(filesystem)
                local draft = assert(service.begin_repair(CONFIG_PATH))
                local count = assert(service.repair_status(draft)).lines
                draft = assert(service.edit_repair(draft, "replace", count, "; repaired"))
                draft = assert(service.edit_repair(draft, "insert", count + 1, "; appended"))
                assert(service.commit_repair(draft, TEMP_PATH))
                A.equal(controls.bytes(CONFIG_PATH), source() .. "; repaired\n; appended")
            end,
        },
        {
            name = "repair rejects forged handles external edits and same-byte file replacement before writing",
            --Verifies repair fixes invalid encoding and retains mixed endings and missing final newline.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify repair fixes invalid encoding and retains mixed endings and missing final newline.
            run = function()
                for _, method in ipairs({ "external_write", "external_replace" }) do
                    local original = source() .. "broken\n"
                    local filesystem, controls = fake_filesystem.new({ [CONFIG_PATH] = original })
                    local service = codec(filesystem)
                    local base = assert(service.begin_repair(CONFIG_PATH))
                    A.falsy(service.repair_status({}))
                    A.falsy(codec(filesystem).repair_status(base))
                    local draft = assert(service.edit_repair(base, "delete", assert(service.repair_status(base)).lines))
                    controls[method](CONFIG_PATH, method == "external_replace" and original or original .. "; external\n")
                    local committed, commit_error = service.commit_repair(draft, TEMP_PATH)
                    A.falsy(committed)
                    A.equal(commit_error.code, "ConfigStale")
                    A.falsy(table.concat(controls.operations, "|"):find("create:", 1, true))
                end
            end,
        },
        {
            name = "repair bounds edits and input without changing its original private draft",
            --Verifies repair bounds edits and input without changing its original private draft.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify repair bounds edits and input without changing its original private draft.
            run = function()
                local filesystem = fake_filesystem.new({ [CONFIG_PATH] = source() .. "broken\n" })
                local service = codec(filesystem)
                local base = assert(service.begin_repair(CONFIG_PATH))
                local count = assert(service.repair_status(base)).lines
                for _, value in ipairs({ "line\nextra", "bad\0", "bad\255", string.rep("x", 65537) }) do
                    A.falsy(service.edit_repair(base, "replace", count, value))
                end
                A.falsy(service.edit_repair(base, "replace", 0, "x"))
                A.falsy(service.edit_repair(base, "delete", count + 1))
                A.falsy(service.edit_repair(base, "delete", count, "discarded-secret"))
                A.falsy(service.repair_status(base, 1000000))
                local draft = base
                for _ = 1, 256 do
                    draft = assert(service.edit_repair(draft, "replace", count, "; repair"))
                end
                A.falsy(service.edit_repair(draft, "replace", count, "; another"))
                A.equal(#assert(service.repair_status(base)).edits, 0)
                --Executes the action expected to raise in the 'repair bounds edits and input without changing its original private draft' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify repair bounds edits and input without changing its original private draft.
                A.raises(function() assert(service.repair_status(base)).rows[1].label = "changed" end)
            end,
        },
        {
            name = "repair reuses temporary validation retries known failures and consumes uncertain publication",
            --Verifies repair reuses temporary validation retries known failures and consumes uncertain publication.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify repair reuses temporary validation retries known failures and consumes uncertain publication.
            run = function()
                for _, fault in ipairs({ "write", "corrupt_after_write_close", "replace", "flush_directory" }) do
                    local original = source() .. "broken\n"
                    local filesystem, controls = fake_filesystem.new({ [CONFIG_PATH] = original })
                    local service = codec(filesystem)
                    local draft = assert(service.begin_repair(CONFIG_PATH))
                    draft = assert(service.edit_repair(draft, "delete", assert(service.repair_status(draft)).lines))
                    controls.faults[fault] = true
                    local committed, commit_error = service.commit_repair(draft, TEMP_PATH)
                    A.falsy(committed)
                    A.falsy(controls.exists(TEMP_PATH))
                    if fault == "flush_directory" then
                        A.equal(commit_error.code, "ConfigPublishUnknown")
                        A.equal(controls.bytes(CONFIG_PATH), source())
                        A.falsy(service.commit_repair(draft, TEMP_PATH))
                    else
                        A.equal(controls.bytes(CONFIG_PATH), original)
                        controls.faults[fault] = false
                        assert(service.commit_repair(draft, TEMP_PATH))
                    end
                end
            end,
        },
        {
            name = "config editor field projection hides secret-capable values and validates literal inputs",
            --Verifies config editor field projection hides secret-capable values and validates literal inputs.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify config editor field projection hides secret-capable values and validates literal inputs.
            run = function()
                local original = source():gsub("%[Agent%]",
                    '[Network]\nProxyUrl = "https://user:proxy-secret@proxy.example"\n[Agent]', 1)
                local filesystem, controls = fake_filesystem.new({ [CONFIG_PATH] = original })
                local service = codec(filesystem)
                local base = assert(service.begin_edit(CONFIG_PATH))
                local sections = assert(service.draft_sections(base))
                A.equal(sections[1], "General")
                A.equal(sections[#sections], "Model.Primary")
                --Supplies row behavior required by the 'config editor field projection hides secret-capable values and validates literal inputs' case.
                --@param draft table Private draft under test.
                --@param section string INI section selected for the operation.
                --@param key string|integer Lookup key selected by the operation.
                --@return any observed row value observed by the scenario assertion.
                local function row(draft, section, key)
                    for _, field in ipairs(assert(service.draft_fields(draft, section))) do
                        if field.key == key then return field end
                    end
                    error("field is missing")
                end
                for _, item in ipairs({ { "Model.Primary", "Key" }, { "Model.Primary", "AdapterOptions" }, { "Network", "ProxyUrl" } }) do
                    local field = row(base, item[1], item[2])
                    A.truthy(field.hidden)
                    A.falsy(field.has_value)
                    A.falsy(field.value)
                end
                local all = A.render(service.draft_fields(base, "Network")) .. A.render(service.draft_fields(base, "Model.Primary"))
                A.falsy(all:find("original-secret", 1, true))
                A.falsy(all:find("proxy-secret", 1, true))
                --Executes the action expected to raise in the 'config editor field projection hides secret-capable values and validates literal inputs' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify config editor field projection hides secret-capable values and validates literal inputs.
                A.raises(function() sections[1] = "Changed" end, "cannot be modified")
                local draft = assert(service.edit_draft_value(base, "General", "SystemPrompt", '"line\\nnext \\\"quote\\\""'))
                A.equal(row(draft, "General", "SystemPrompt").value, 'line\nnext "quote"')
                draft = assert(service.edit_draft_value(draft, "TUI", "StartupShowVersion", "false"))
                A.equal(row(draft, "TUI", "StartupShowVersion").value, false)
                draft = assert(service.edit_draft_value(draft, "Agent", "QueueMaxItems", "4"))
                A.equal(row(draft, "Agent", "QueueMaxItems").value, 4)
                for _, value in ipairs({ '"raw\nphysical"', '"original-secret"', '"bad\\escape"', '"ok"\nLogLevel = trace', '"bad\0"' }) do
                    A.falsy(service.edit_draft_value(draft, "General", "SystemPrompt", value))
                end
                A.falsy(service.edit_draft_value(draft, "Agent", "QueueMaxItems", "999999"))
                A.falsy(service.edit_draft_value(draft, "TUI", "StartupShowVersion", '"false"'))
                A.falsy(service.draft_fields(draft, "Model.Missing"))
                A.falsy(service.edit_draft_value(draft, "General", "Unknown", "1"))
                A.equal(controls.bytes(CONFIG_PATH), original)
                assert(service.commit_draft(draft, TEMP_PATH))
                A.contains(controls.bytes(CONFIG_PATH), "; preserve this comment")
                A.contains(controls.bytes(CONFIG_PATH), "[TUI]")
                A.equal(assert(service.current()).agent.queue_max_items, 4)
                A.falsy(service.draft_fields(draft, "General"))
            end,
        },
        {
            name = "existing edits recheck base write validate replace and flush directory",
            --Verifies existing edits recheck base write validate replace and flush directory.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify existing edits recheck base write validate replace and flush directory.
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
            --Verifies external replacement makes a draft stale before any temporary write.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify external replacement makes a draft stale before any temporary write.
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
            --Verifies temporary corruption and replace failure preserve the old target.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify temporary corruption and replace failure preserve the old target.
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
            name = "structural unset preserves comments and remains fully validated",
            --Verifies structural unset preserves comments and remains fully validated.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify structural unset preserves comments and remains fully validated.
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
                A.contains(controls.bytes(CONFIG_PATH), "preserve this comment")
            end,
        },
        {
            name = "new config is no-replace and directory-flush failure is typed unknown",
            --Verifies new config is no-replace and directory-flush failure is typed unknown.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify new config is no-replace and directory-flush failure is typed unknown.
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
            --Verifies typed first setup and exact template repair publish no secret projection.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify typed first setup and exact template repair publish no secret projection.
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
