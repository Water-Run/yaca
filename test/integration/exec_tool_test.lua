--[[
Author: WaterRun
Date: 2026-09-23
File: exec_tool_test.lua
Description: Verifies raw exec transport, output, cancellation, and durable barriers.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()
local sha256 = assert(loadfile(
    YACA_TEST_ROOT .. "/test/support/sha256_reference.lua",
    "t",
    _ENV
))()
local direct_harness = assert(loadfile(
    YACA_TEST_ROOT .. "/test/support/direct_filesystem_harness.lua",
    "t",
    _ENV
))()

--Loads a source module into an isolated per-case environment.
--@param name string Module, Model, or resource name selected by the case.
--@param cache table Per-case module cache preserving isolated imports.
--@return any module Module export loaded in the isolated source environment.
local function load_module(name, cache)
    cache = cache or {}
    if cache[name] then return cache[name] end
    local environment = {}
    for key, value in pairs(_ENV) do environment[key] = value end
    --Resolves an imported Lua module through the isolated test loader.
    --@param dependency string Source module requested from the isolated loader.
    --@return any value Callback value consumed by the enclosing scenario assertion.
    environment.require = function(dependency) return load_module(dependency, cache) end
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

--Constructs an incremental SHA-256 port backed by the reference digest.
--@param none No arguments; this closure uses its captured fixture state.
--@return table port Incremental SHA-256 fixture port.
local function hash_port()
    return {
        --Computes or records sha256 start data for this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return table record Fixture record emitted by the scenario callback.
        sha256_start = function() return { parts = {} } end,
        --Computes or records sha256 update data for this suite.
        --@param handle table|integer Fake resource handle whose state is inspected.
        --@param bytes string Byte chunk supplied to the fake I/O port.
        --@return boolean accepted Whether the fake callback accepts this scenario.
        sha256_update = function(handle, bytes)
            handle.parts[#handle.parts + 1] = bytes
            return true
        end,
        --Computes or records sha256 finish data for this suite.
        --@param handle table|integer Fake resource handle whose state is inspected.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        sha256_finish = function(handle)
            return sha256.digest(table.concat(handle.parts))
        end,
        --Computes or records sha256 close data for this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return boolean accepted Whether the fake callback accepts this scenario.
        sha256_close = function() return true end,
    }
end

--Transforms escape data used by this suite.
--@param value any Candidate whose acceptance or transformation the test checks.
--@return string observed escape value observed by the scenario assertion.
local function escape(value)
    --Supplies an assertion callback for this test scenario.
    --@param character string Character emitted or parsed by the fixture.
    --@return number value Callback value consumed by the enclosing scenario assertion.
    return '"' .. value:gsub("[\\\"\0-\31]", function(character)
        local mappings = {
            ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n',
            ['\r'] = '\\r', ['\t'] = '\\t',
        }
        return mappings[character] or string.format("\\u%04x", character:byte())
    end) .. '"'
end

--Transforms encode object data used by this suite.
--@param value any Candidate whose acceptance or transformation the test checks.
--@return string observed Fixture text "{" .. table.concat(output, ",") .. "}".
local function encode_object(value)
    local keys, output = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys)
    for index, key in ipairs(keys) do
        local item = value[key]
        local encoded = type(item) == "string" and escape(item)
            or type(item) == "boolean" and (item and "true" or "false")
            or tostring(item)
        if type(item) == "table" then
            local items = {}
            for i, argument in ipairs(item) do items[i] = escape(argument) end
            encoded = "[" .. table.concat(items, ",") .. "]"
        end
        output[index] = escape(key) .. ":" .. encoded
    end
    return "{" .. table.concat(output, ",") .. "}"
end

--Supplies tool options behavior required by this suite.
--@param none No arguments; this closure uses its captured fixture state.
--@return table observed Structured fixture record selected by the exercised branch.
local function tool_options()
    return {
        maximum_argument_bytes = 65536,
        maximum_path_bytes = 1024,
        maximum_content_bytes = 32768,
        maximum_file_bytes = 32768,
        maximum_result_bytes = 65536,
        maximum_list_depth = 8,
        maximum_page_entries = 16,
        maximum_walk_entries = 128,
        maximum_search_pattern_bytes = 256,
        maximum_search_matches = 64,
        maximum_patch_hunks = 16,
        maximum_patch_lines = 128,
        maximum_line_bytes = 4096,
        maximum_continuations = 8,
        maximum_identifier_bytes = 128,
        filesystem_chunk_bytes = 7,
        create_permissions = 384,
        maximum_json_depth = 24,
        maximum_json_nodes = 4096,
        maximum_number_bytes = 32,
        maximum_exec_output_bytes = 8192,
        maximum_exec_deadline_ms = 60000,
        platform_kind = "posix",
        workspace_path = "/work",
        lua_executable = "/app/yaca",
        reserved_paths = { "/reserved" },
    }
end

--Constructs the suite's isolated runtime fixture and observation ports.
--@param settings table|nil Fixture settings and scenario overrides.
--@return table fixture Constructed fixture service used by this suite.
local function fixture(settings)
    settings = settings or {}
    local modules = {}
    local log = {}
    local fs_native, filesystem_controls = direct_harness.new({
        ["/work"] = { kind = "directory" },
        ["/work/sub"] = { kind = "directory" },
        ["/reserved"] = { kind = "directory" },
        ["/app"] = { kind = "directory" },
        ["/app/yaca"] = "embedded-interpreter-fixture",
    })
    local filesystem = assert(load_module("fs", modules).new(fs_native, {
        maximum_chunk_bytes = 7,
        maximum_lease_bytes = 256,
        maximum_direct_entries = 128,
    }))
    local hashes = hash_port()
    local paths = assert(load_module("path", modules).new(hashes, {
        maximum_path_bytes = 1024,
        maximum_segments = 64,
        maximum_segment_bytes = 255,
        maximum_hash_chunk_bytes = 11,
    }))
    local safety = assert(load_module("safety", modules).new(hashes, {
        maximum_hash_chunk_bytes = 11,
        minimum_scannable_secret_bytes = 8,
    }))
    local secrets = false
    if settings.secret then
        secrets = assert(safety.secret_registry({ {
            id = "exec-canary",
            class = "credential",
            value = settings.secret,
            destinations = { "model-auth" },
        } }))
    end

    local process_native = {
        batches = settings.batches or {},
        result = settings.result or {
            outcome = "completed",
            exit_kind = "exit-code",
            exit_code = 0,
            duration_ms = 9,
            descendants_proven_stopped = true,
        },
        starts = 0,
        cancels = 0,
        closes = 0,
    }
    --Supplies process start behavior required by this suite.
    --@param request table Request delivered to the fake component.
    --@return boolean accepted Whether process start succeeds in the fixture.
    --@return table secondary2 Structured fixture record with id.
    function process_native.process_start(request)
        process_native.starts = process_native.starts + 1
        process_native.request = request
        log[#log + 1] = "process-start"
        return true, { id = process_native.starts }
    end
    --Supplies process poll behavior required by this suite.
    --@param _ any Unused callback argument supplied by the port.
    --@param _ any Unused callback argument supplied by the port.
    --@param budget integer|table Resource budget applied by the scenario.
    --@return boolean accepted Whether process poll succeeds in the fixture.
    --@return any secondary2 Event batch returned by the fixture.
    function process_native.process_poll(_, _, budget)
        local batch = table.remove(process_native.batches, 1) or {}
        A.truthy(#batch <= budget)
        return true, batch
    end
    --Supplies process cancel behavior required by this suite.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether process cancel succeeds in the fixture.
    --@return boolean secondary2 True acknowledgment from the fake port.
    function process_native.process_cancel()
        process_native.cancels = process_native.cancels + 1
        log[#log + 1] = "process-cancel"
        return true, true
    end
    --Supplies process join behavior required by this suite.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether process join succeeds in the fixture.
    --@return any secondary2 Additional status or structured error from the fixture operation.
    function process_native.process_join()
        log[#log + 1] = "process-join"
        return true, process_native.result
    end
    --Supplies process close behavior required by this suite.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether process close succeeds in the fixture.
    --@return boolean secondary2 True acknowledgment from the fake port.
    function process_native.process_close()
        process_native.closes = process_native.closes + 1
        return true, true
    end
    local processes = assert(load_module("process", modules).new(process_native, {
        maximum_output_bytes = 8192,
        maximum_poll_bytes = 1024,
        shell = { kind = "linux", executable = "/bin/sh", fixed_arguments = { "-c" } },
    }))

    local journal = { intents = {}, results = {}, fail_intent = false, fail_result = false }
    --Simulates the commit intent publication step for this suite.
    --@param record table Recorded event or publication under inspection.
    --@param digest string Expected or computed hexadecimal digest.
    --@return boolean accepted Whether commit intent succeeds in the fixture.
    --@return table|any secondary2 Additional status or structured error from the fixture operation.
    function journal.commit_intent(record, digest)
        log[#log + 1] = "intent-durable"
        journal.intents[#journal.intents + 1] = record
        if journal.fail_intent then
            return false, { code = "InjectedIntentFailure", message = "intent failure" }
        end
        return true, digest
    end
    --Simulates the commit result publication step for this suite.
    --@param record table Recorded event or publication under inspection.
    --@param digest string Expected or computed hexadecimal digest.
    --@return boolean accepted Whether commit result succeeds in the fixture.
    --@return table|any secondary2 Additional status or structured error from the fixture operation.
    function journal.commit_result(record, digest)
        log[#log + 1] = "result-durable"
        journal.results[#journal.results + 1] = record
        if journal.fail_result then
            return false, { code = "InjectedResultFailure", message = "result failure" }
        end
        return true, digest
    end
    local operations = assert(load_module("context", modules).new_operation_service({
        safety = safety,
        journal = journal,
    }, {
        maximum_identifier_bytes = 128,
        maximum_evidence_bytes = 131072,
        unresolved_operation_ids = {},
    }))
    local authorization = {
        --Simulates the admit port for this suite.
        --@param call table|integer Recorded call or call ordinal under inspection.
        --@param facts table Platform or file-descriptor facts supplied to the case.
        --@return boolean accepted Whether the fake callback accepts this scenario.
        --@return string secondary2 Fixture text "authority-" .. call.call_digest .. "-" .. facts.durable_intent_digest.
        admit = function(call, facts)
            return true, "authority-" .. call.call_digest .. "-" .. facts.durable_intent_digest
        end,
        --Supplies the reverify observation used by this suite.
        --@param call table|integer Recorded call or call ordinal under inspection.
        --@param facts table Platform or file-descriptor facts supplied to the case.
        --@param digest string Expected or computed hexadecimal digest.
        --@return string text Text emitted by the scenario callback.
        reverify = function(call, facts, digest)
            return digest == "authority-" .. call.call_digest
                .. "-" .. facts.durable_intent_digest
        end,
    }
    local tools = assert(load_module("tools", modules).new({
        filesystem = filesystem,
        path = paths,
        safety = safety,
        secret_registry = secrets,
        authorization = authorization,
        processes = processes,
        operations = operations,
    }, tool_options()))
    return {
        tools = tools,
        filesystem = filesystem_controls,
        process = process_native,
        journal = journal,
        operations = operations,
        log = log,
    }
end

--Supplies exec call behavior required by this suite.
--@param fixture table Test fixture state shared by this helper.
--@param arguments table Argument vector delivered to the fake process.
--@param id string|integer Identity selected for the fake operation.
--@param tool table|string Tool selected for this scenario.
--@return any observed exec call value observed by the scenario assertion.
--@return any secondary2 Authorization token returned by the fixture.
local function exec_call(fixture, arguments, id, tool)
    id = id or "exec"
    local call = assert(fixture.tools:admit_call({
        tool = tool or "exec",
        schema_version = fixture.tools.schema_version,
        registry_digest = fixture.tools.registry_digest,
        provider_call_id = "provider-" .. id,
        tool_call_id = "call-" .. id,
        operation_id = "operation-" .. id,
        canonical_arguments = encode_object(arguments),
    }))
    local action = assert(fixture.tools:permission_action(call))
    assert(fixture.tools:begin_operation(call))
    local token = assert(fixture.tools:authorize(call, {
        permission_snapshot_digest = "permission-v1",
        approval_digest = "approval-v1",
        config_generation = "generation-1",
        workspace_identity = action.workspace_root_identity,
        double_check = true,
        action_review = "approved",
    }))
    return call, token
end

--Supplies policy behavior required by this suite.
--@param overrides table|nil Per-case overrides of default fixture behavior.
--@return any observed Selected fixture value returned by the fixture.
local function policy(overrides)
    local value = {
        config_generation = "generation-1",
        environment_mode = "minimal",
        environment = { PATH = "/bin", CUSTOM = "removed", LUA_PATH = "removed" },
        output_limit_bytes = 16,
        deadline_ms = 1000,
        decoder = "utf-8-strict-candidate",
    }
    for key, item in pairs(overrides or {}) do value[key] = item end
    return value
end

--Supplies drive behavior required by this suite.
--@param port any The port supplied to the fake service for this scenario.
--@param ticks any The ticks supplied to the fake service for this scenario.
--@return any observed drive value observed by the scenario assertion.
--@return any secondary2 Additional status or structured error from the fixture operation.
local function drive(port, ticks)
    ticks = ticks or { 1, 2, 3, 4 }
    assert(port:start(ticks[1]))
    local progress = {}
    local terminal
    for index = 2, #ticks do
        for _, event in ipairs(port:poll(ticks[index], 16)) do
            if event.kind == "io_progress" then progress[#progress + 1] = event end
            if event.kind == "io_terminal" then terminal = event end
        end
        if terminal then break end
    end
    A.truthy(terminal, "exec port did not reach terminal truth")
    local joined = port:join(ticks[#ticks])
    assert(port:close())
    return joined, progress
end

--Supplies index of behavior required by this suite.
--@param values table Candidate values supplied to the fixture operation.
--@param expected any Expected value used by the assertion.
--@return any observed index of value observed by the scenario assertion.
local function index_of(values, expected)
    for index, value in ipairs(values) do
        if value == expected then return index end
    end
end

return {
    name = "integration/exec-tool",
    cases = {
        {
            name = "Lua is a structured builtin with script stdin exact argv and durable process ownership",
            --Verifies lua is a structured builtin with script stdin exact argv and durable process ownership.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify lua is a structured builtin with script stdin exact argv and durable process ownership.
            run = function()
                local f = fixture({ batches = { {
                    { kind = "stdout", bytes = "42\n" },
                    { kind = "terminal", outcome = "completed" },
                } } })
                local code = 'print(6*7) -- " & %PATH% $(touch injected)\n'
                local arguments = { "", "a b", 'quotes " & % ! $ ;', "-e", "中文" }
                local call, token = exec_call(f, {
                    code = code, args = arguments, cwd = "/work/sub",
                }, "embedded", "lua")
                A.truthy(f.tools.capabilities.embedded_lua)
                A.equal(call.tool, "lua")
                A.equal(call.shell_scope, "opaque-uncontained")
                local blocking, blocking_error = f.tools:execute(token)
                A.falsy(blocking)
                A.equal(blocking_error.code, "AsyncExecutionRequired")
                local result = drive(assert(f.tools:execution_port(token,
                    policy({ environment_mode = "inherit_filtered" }))))
                A.equal(f.process.request.mode, "argv")
                A.equal(f.process.request.executable, "/app/yaca")
                A.falsy(f.process.request.command)
                A.falsy(f.process.request.shell)
                A.deep_equal(f.process.request.arguments,
                    { "--lua", "-E", "-", "", "a b", 'quotes " & % ! $ ;', "-e", "中文" })
                A.equal(f.process.request.stdin.bytes, code)
                A.equal(f.process.request.environment_mode, "clean")
                A.falsy(f.process.request.environment.CUSTOM)
                A.falsy(f.process.request.environment.LUA_PATH)
                A.equal(result.tool_result.payload.stdout.text, "42\n")
                A.falsy(result.tool_result.payload.shell)
                A.equal(result.tool_result.payload.environment_mode, "clean")
                A.equal(result.tool_result.payload.stdin, "script-bytes-then-eof")
                A.equal(f.journal.intents[1].kind, "lua")
                A.truthy(index_of(f.log, "intent-durable") < index_of(f.log, "process-start"))
                A.truthy(index_of(f.log, "process-join") < index_of(f.log, "result-durable"))
                A.equal(assert(f.tools:runtime_result(call)).kind, "real-success")
                local replay, replay_error = f.tools:execution_port(token, policy())
                A.falsy(replay)
                A.equal(replay_error.code, "AuthorizationConsumed")
            end,
        },
        {
            name = "Lua rejects unbound executables malformed args and source before any effect",
            --Verifies lua rejects unbound executables malformed args and source before any effect.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify lua rejects unbound executables malformed args and source before any effect.
            run = function()
                local f = fixture()
                for _, canonical in ipairs({
                    '{"code":"print(42)","executable":"/other/lua"}',
                    '{"code":"print(42)","args":{}}',
                    '{"code":"print(42)","args":[4]}',
                    '{"code":"print(42)","args":["a\\u0000b"]}',
                    '{"code":"a\\u0000b"}',
                    '{"code":"print(42)","deadline_ms":0}',
                }) do
                    local call = f.tools:admit_call({
                        tool = "lua", schema_version = f.tools.schema_version,
                        registry_digest = f.tools.registry_digest,
                        provider_call_id = "bad", tool_call_id = "bad", operation_id = "bad",
                        canonical_arguments = canonical,
                    })
                    A.falsy(call, canonical)
                end
                A.equal(#f.journal.intents, 0)
                A.equal(f.process.starts, 0)
            end,
        },
        {
            name = "Lua deadline cancellation and executable replacement retain truthful results",
            --Verifies lua deadline cancellation and executable replacement retain truthful results.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify lua deadline cancellation and executable replacement retain truthful results.
            run = function()
                local timeout = fixture({
                    batches = { {}, { { kind = "terminal", outcome = "cancelled" } } },
                    result = { outcome = "cancelled", exit_kind = "cancelled", duration_ms = 5,
                        descendants_proven_stopped = true },
                })
                local _, token = exec_call(timeout, { code = "while true do end", deadline_ms = 5 },
                    "lua-timeout", "lua")
                local timed = drive(assert(timeout.tools:execution_port(token, policy())), { 10, 11, 15 })
                A.equal(timed.tool_result.outcome, "timeout")
                A.equal(timed.tool_result.error.code, "LuaTimeout")
                A.equal(timeout.process.cancels, 1)
                A.equal(#timeout.journal.results, 1)

                local changed = fixture()
                local _, changed_token = exec_call(changed, { code = "print(42)" }, "changed-lua", "lua")
                local port = assert(changed.tools:execution_port(changed_token, policy()))
                changed.filesystem.add("/app/yaca", "file", "replaced-executable")
                local result = drive(port)
                A.equal(result.tool_result.outcome, "failed")
                A.equal(result.tool_result.error.code, "TargetChanged")
                A.equal(changed.process.starts, 0)
                A.equal(#changed.journal.results, 1)
            end,
        },
        {
            name = "opaque command uses fixed shell closed stdin filtered env and durable ordering",
            --Verifies opaque command uses fixed shell closed stdin filtered env and durable ordering.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify opaque command uses fixed shell closed stdin filtered env and durable ordering.
            run = function()
                local command = "printf '%s' 'a b'; printf warn >&2"
                local f = fixture({
                    batches = {
                        {
                            { kind = "stdout", bytes = "abcd" },
                            { kind = "stderr", bytes = "warn" },
                        },
                        {
                            { kind = "stdout", bytes = "EFGH" },
                            { kind = "terminal", outcome = "completed" },
                        },
                    },
                })
                local call, token = exec_call(f, { command = command, cwd = "/work/sub" })
                local port = assert(f.tools:execution_port(token, policy({
                    environment_mode = "inherit_filtered",
                    output_limit_bytes = 8,
                    environment = {
                        PATH = "/bin", CUSTOM = "kept", LUA_PATH = "removed",
                        CURL_HOME = "removed",
                    },
                })))
                local joined, progress = drive(port)
                A.equal(joined.outcome, "completed")
                local result = joined.tool_result
                A.equal(result.outcome, "success")
                local runtime_result = assert(f.tools:runtime_result(call))
                A.equal(runtime_result.kind, "real-success")
                A.equal(runtime_result.raw_bytes, #runtime_result.body)
                A.equal(runtime_result.progress_identity, result.result_digest)
                A.equal(result.payload.cwd, "/work/sub")
                A.equal(result.payload.stdin, "closed")
                A.equal(result.payload.stdout.text, "abGH")
                A.equal(result.payload.stdout.observed_bytes, 8)
                A.equal(result.payload.stdout.discarded_bytes, 4)
                A.equal(result.payload.stderr.text, "warn")
                A.equal(result.payload.observed_sequences, 3)
                A.equal(f.process.request.command, command)
                A.equal(f.process.request.shell.executable, "/bin/sh")
                A.equal(f.process.request.stdin, "closed")
                A.equal(f.process.request.environment.CUSTOM, "kept")
                A.falsy(f.process.request.environment.LUA_PATH)
                A.falsy(f.process.request.environment.CURL_HOME)
                A.equal(#f.journal.intents, 1)
                A.equal(#f.journal.results, 1)
                A.equal(f.journal.intents[1].operation_id, call.operation_id)
                A.truthy(index_of(f.log, "intent-durable") < index_of(f.log, "process-start"))
                A.truthy(index_of(f.log, "process-join") < index_of(f.log, "result-durable"))
                for _, event in ipairs(progress) do
                    A.falsy(event.bytes)
                    A.equal(event.content, "withheld-until-terminal-secret-scan")
                end
            end,
        },
        {
            name = "binary output is lossless base64 and registered secret across chunks is redacted",
            --Verifies binary output is lossless base64 and registered secret across chunks is redacted.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify binary output is lossless base64 and registered secret across chunks is redacted.
            run = function()
                local binary = fixture({
                    batches = { {
                        { kind = "stdout", bytes = "A\0\255B" },
                        { kind = "terminal", outcome = "completed" },
                    } },
                })
                local _, binary_token = exec_call(binary, { command = "binary" }, "binary")
                local binary_joined = drive(assert(binary.tools:execution_port(
                    binary_token,
                    policy({ output_limit_bytes = 16 })
                )))
                A.equal(binary_joined.tool_result.payload.stdout.representation, "base64")
                A.equal(binary_joined.tool_result.payload.stdout.base64, "QQD/Qg==")
                A.falsy(binary_joined.tool_result.payload.stdout.text)

                local secret = "canary-secret"
                local redacted = fixture({
                    secret = secret,
                    batches = {
                        { { kind = "stdout", bytes = "xxcanary-" } },
                        {
                            { kind = "stdout", bytes = "secretyy" },
                            { kind = "terminal", outcome = "completed" },
                        },
                    },
                })
                local _, secret_token = exec_call(redacted, { command = "show-output" }, "secret")
                local secret_joined, progress = drive(assert(redacted.tools:execution_port(
                    secret_token,
                    policy({ output_limit_bytes = 64 })
                )))
                local channel = secret_joined.tool_result.payload.stdout
                A.equal(channel.representation, "registered-secret-redacted")
                A.falsy(channel.text)
                A.falsy(channel.base64)
                A.falsy(channel.digest)
                A.equal(channel.registered_secret_hits, 1)
                A.falsy(redacted.journal.results[1].tool_body:find(secret, 1, true))
                for _, event in ipairs(progress) do
                    A.falsy(tostring(event.content):find(secret, 1, true))
                end
            end,
        },
        {
            name = "deadline cancellation is timeout and unproven descendants are unknown",
            --Verifies deadline cancellation is timeout and unproven descendants are unknown.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify deadline cancellation is timeout and unproven descendants are unknown.
            run = function()
                local timeout = fixture({
                    batches = {
                        {},
                        { { kind = "terminal", outcome = "cancelled" } },
                    },
                    result = {
                        outcome = "cancelled",
                        exit_kind = "cancelled",
                        duration_ms = 5,
                        descendants_proven_stopped = true,
                    },
                })
                local _, timeout_token = exec_call(timeout, {
                    command = "long-running",
                    deadline_ms = 5,
                }, "timeout")
                local timed = drive(assert(timeout.tools:execution_port(
                    timeout_token,
                    policy({ deadline_ms = 100 })
                )), { 10, 11, 15 })
                A.equal(timeout.process.cancels, 1)
                A.equal(timed.outcome, "cancelled")
                A.equal(timed.tool_result.outcome, "timeout")
                A.equal(timed.tool_result.error.code, "ExecTimeout")

                local unknown = fixture({
                    batches = { { { kind = "terminal", outcome = "completed" } } },
                    result = {
                        outcome = "completed",
                        exit_kind = "exit-code",
                        exit_code = 0,
                        duration_ms = 1,
                        descendants_proven_stopped = false,
                    },
                })
                local _, unknown_token = exec_call(unknown, { command = "detach-attempt" }, "unknown")
                local unsettled = drive(assert(unknown.tools:execution_port(
                    unknown_token,
                    policy()
                )))
                A.equal(unsettled.outcome, "unknown")
                A.equal(unsettled.tool_result.outcome, "unknown")
                A.truthy(unsettled.tool_result.payload.external_effects_unsettled)
                A.equal(unsettled.tool_result.payload.descendant_state, "unknown")
            end,
        },
        {
            name = "cwd replacement after approval closes failed intent without spawning",
            --Verifies cwd replacement after approval closes failed intent without spawning.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify cwd replacement after approval closes failed intent without spawning.
            run = function()
                local f = fixture({
                    batches = { { { kind = "terminal", outcome = "completed" } } },
                })
                local call, token = exec_call(f, {
                    command = "pwd",
                    cwd = "/work/sub",
                }, "cwd-race")
                local port = assert(f.tools:execution_port(token, policy()))
                f.filesystem.add("/work/sub", "directory")
                local joined = drive(port)
                A.equal(joined.outcome, "failed")
                A.equal(joined.tool_result.outcome, "failed")
                A.equal(joined.tool_result.error.code, "TargetChanged")
                A.equal(f.process.starts, 0)
                A.equal(#f.journal.intents, 1)
                A.equal(#f.journal.results, 1)
                A.equal(assert(f.tools:result(call)).result_digest, joined.tool_result.result_digest)
            end,
        },
        {
            name = "result barrier failure exposes no result and blocks every later spawn",
            --Verifies result barrier failure exposes no result and blocks every later spawn.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify result barrier failure exposes no result and blocks every later spawn.
            run = function()
                local f = fixture({
                    batches = { { { kind = "terminal", outcome = "completed" } } },
                })
                local _, token = exec_call(f, { command = "one-effect" }, "barrier-one")
                f.journal.fail_result = true
                local joined = drive(assert(f.tools:execution_port(token, policy())))
                A.equal(joined.outcome, "unknown")
                A.falsy(joined.tool_result)
                A.equal(joined.error.code, "OperationResultDurabilityUnknown")
                A.truthy(f.operations.status().blocked)
                A.equal(f.process.starts, 1)

                local second = assert(f.tools:admit_call({
                    tool = "exec",
                    schema_version = f.tools.schema_version,
                    registry_digest = f.tools.registry_digest,
                    provider_call_id = "provider-barrier-two",
                    tool_call_id = "call-barrier-two",
                    operation_id = "operation-barrier-two",
                    canonical_arguments = encode_object({ command = "two-effect" }),
                }))
                local begun, blocked_error = f.tools:begin_operation(second)
                A.falsy(begun)
                A.equal(blocked_error.code, "OperationBarrierBlocked")
                A.equal(f.process.starts, 1)
                A.equal(#f.journal.results, 1)
            end,
        },
    },
}
