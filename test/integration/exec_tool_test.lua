--[[
File: exec_tool_test.lua
Date: 2026-08-29
Author: WaterRun
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

local function load_module(name, cache)
    cache = cache or {}
    if cache[name] then return cache[name] end
    local environment = {}
    for key, value in pairs(_ENV) do environment[key] = value end
    environment.require = function(dependency) return load_module(dependency, cache) end
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

local function hash_port()
    return {
        sha256_start = function() return { parts = {} } end,
        sha256_update = function(handle, bytes)
            handle.parts[#handle.parts + 1] = bytes
            return true
        end,
        sha256_finish = function(handle)
            return sha256.digest(table.concat(handle.parts))
        end,
        sha256_close = function() return true end,
    }
end

local function escape(value)
    return '"' .. value:gsub("[\\\"\0-\31]", function(character)
        local mappings = {
            ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n',
            ['\r'] = '\\r', ['\t'] = '\\t',
        }
        return mappings[character] or string.format("\\u%04x", character:byte())
    end) .. '"'
end

local function encode_object(value)
    local keys, output = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys)
    for index, key in ipairs(keys) do
        local item = value[key]
        local encoded = type(item) == "string" and escape(item)
            or type(item) == "boolean" and (item and "true" or "false")
            or tostring(item)
        output[index] = escape(key) .. ":" .. encoded
    end
    return "{" .. table.concat(output, ",") .. "}"
end

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
        reserved_paths = { "/reserved" },
    }
end

local function fixture(settings)
    settings = settings or {}
    local modules = {}
    local log = {}
    local fs_native, filesystem_controls = direct_harness.new({
        ["/work"] = { kind = "directory" },
        ["/work/sub"] = { kind = "directory" },
        ["/reserved"] = { kind = "directory" },
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
    function process_native.process_start(request)
        process_native.starts = process_native.starts + 1
        process_native.request = request
        log[#log + 1] = "process-start"
        return true, { id = process_native.starts }
    end
    function process_native.process_poll(_, _, budget)
        local batch = table.remove(process_native.batches, 1) or {}
        A.truthy(#batch <= budget)
        return true, batch
    end
    function process_native.process_cancel()
        process_native.cancels = process_native.cancels + 1
        log[#log + 1] = "process-cancel"
        return true, true
    end
    function process_native.process_join()
        log[#log + 1] = "process-join"
        return true, process_native.result
    end
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
    function journal.commit_intent(record, digest)
        log[#log + 1] = "intent-durable"
        journal.intents[#journal.intents + 1] = record
        if journal.fail_intent then
            return false, { code = "InjectedIntentFailure", message = "intent failure" }
        end
        return true, digest
    end
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
        admit = function(call, facts)
            return true, "authority-" .. call.call_digest .. "-" .. facts.durable_intent_digest
        end,
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

local function exec_call(fixture, arguments, id)
    id = id or "exec"
    local call = assert(fixture.tools:admit_call({
        tool = "exec",
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

local function index_of(values, expected)
    for index, value in ipairs(values) do
        if value == expected then return index end
    end
end

return {
    name = "integration/exec-tool",
    cases = {
        {
            name = "opaque command uses fixed shell closed stdin filtered env and durable ordering",
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
