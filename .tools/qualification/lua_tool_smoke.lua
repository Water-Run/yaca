--[[
Author: WaterRun
Date: 2026-09-23
File: lua_tool_smoke.lua
Description: Real native-process checks for the embedded lua tool. No model or credentials.
]]

-- Real native-process checks for the embedded lua tool. No model or credentials.
-- Arguments: repository/source root, native module, interpreter payload, scratch directory.
-- The caller creates scratch/reserved and supplies a disposable scratch directory.
local source_root, native_path, executable, scratch = table.unpack(arg)
assert(source_root and native_path and executable and scratch, "four probe paths are required")
local plain_assert = assert
--Computes assert in lua tool smoke.
--@param value any Candidate value supplied to the fixture operation.
--@param message string|table Message delivered through the fake port.
--@return any observed assert value observed by the scenario assertion.
local function assert(value, message)
    if type(message) == "table" then
        message = tostring(message.code) .. ": " .. tostring(message.message or message.detail)
    end
    return plain_assert(value, message)
end
package.path = source_root .. "/src/?.lua"
local native = assert(package.loadlib(native_path, "luaopen_yaca_native"))()
local windows = native.platform_identity().os == "windows"
local fs = assert(require("fs").new(native, {
    maximum_chunk_bytes = 65536, maximum_lease_bytes = 256, maximum_direct_entries = 256,
}))
local paths = assert(require("path").new(native, {
    maximum_path_bytes = 32768, maximum_segments = 256, maximum_segment_bytes = 255,
    maximum_hash_chunk_bytes = 32768,
}))
local safety = assert(require("safety").new(native, {
    maximum_hash_chunk_bytes = 65536, minimum_scannable_secret_bytes = 8,
}))
local processes = assert(require("process").new(native, {
    maximum_output_bytes = 65536, maximum_poll_bytes = 4096, maximum_stdin_bytes = 32768,
    maximum_arguments = 128, maximum_argument_bytes = 65536,
    shell = windows and { kind = "windows", executable = "native-GetSystemDirectoryW/cmd.exe",
        fixed_arguments = { "/d", "/s", "/c" } }
        or { kind = "linux", executable = "/bin/sh", fixed_arguments = { "-c" } },
}))
local intents, results = 0, 0
local operations = assert(require("context").new_operation_service({
    safety = safety,
    journal = {
        --Exercises commit intent in the lua tool smoke fixture.
        --@param _ any Unused callback argument supplied by the port.
        --@param digest string Expected or computed hexadecimal digest.
        --@return boolean accepted Whether the fake callback accepts this scenario.
        --@return any secondary2 Computed digest returned by the fixture.
        commit_intent = function(_, digest) intents = intents + 1; return true, digest end,
        --Exercises commit result in the lua tool smoke fixture.
        --@param _ any Unused callback argument supplied by the port.
        --@param digest string Expected or computed hexadecimal digest.
        --@return boolean accepted Whether the fake callback accepts this scenario.
        --@return any secondary2 Computed digest returned by the fixture.
        commit_result = function(_, digest) results = results + 1; return true, digest end,
    },
}, { maximum_identifier_bytes = 256, maximum_evidence_bytes = 131072, unresolved_operation_ids = {} }))
local tools = assert(require("tools").new({
    filesystem = fs, path = paths, safety = safety, secret_registry = false,
    processes = processes, operations = operations,
    authorization = {
        --Exercises admit in the lua tool smoke fixture.
        --@param call table|integer Recorded call or call ordinal under inspection.
        --@return boolean accepted Whether the fake callback accepts this scenario.
        --@return any secondary2 Additional status or structured error from the fixture operation.
        admit = function(call) return true, call.call_digest end,
        --Exercises reverify in the lua tool smoke fixture.
        --@param call table|integer Recorded call or call ordinal under inspection.
        --@param _ any Unused callback argument supplied by the port.
        --@param digest string Expected or computed hexadecimal digest.
        --@return any value Value emitted by the scenario callback for the current assertion.
        reverify = function(call, _, digest) return call.call_digest == digest end,
    },
}, {
    maximum_argument_bytes = 65536, maximum_path_bytes = 32768, maximum_content_bytes = 32768,
    maximum_file_bytes = 65536, maximum_result_bytes = 131072, maximum_list_depth = 8,
    maximum_page_entries = 64, maximum_walk_entries = 256, maximum_search_pattern_bytes = 256,
    maximum_search_matches = 64, maximum_patch_hunks = 16, maximum_patch_lines = 128,
    maximum_line_bytes = 4096, maximum_continuations = 8, maximum_identifier_bytes = 256,
    filesystem_chunk_bytes = 4096, create_permissions = 384, maximum_json_depth = 24,
    maximum_json_nodes = 4096, maximum_number_bytes = 32, maximum_exec_output_bytes = 65536,
    maximum_exec_deadline_ms = 10000, platform_kind = windows and "windows" or "posix",
    workspace_path = scratch, reserved_paths = { scratch .. "/reserved" }, lua_executable = executable,
}))
--Quotes one argument for the shell command used by lua tool smoke.
--@param value any Candidate value supplied to the fixture operation.
--@return string observed quote value observed by the scenario assertion.
local function quote(value)
    --Supplies an assertion callback for the lua tool smoke scenario.
    --@param c any The c supplied to this scenario's fixture operation.
    --@return number value Value emitted by the scenario callback for the current assertion.
    return '"' .. value:gsub('[\\"%z\1-\31]', function(c)
        local escapes = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r',
            ['\t'] = '\\t', ['\b'] = '\\b', ['\f'] = '\\f' }
        return escapes[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end
local serial = 0
--Computes run in lua tool smoke.
--@param code string|integer Expected error or exit code.
--@param args any The args supplied to this scenario's fixture operation.
--@param deadline any The deadline supplied to this scenario's fixture operation.
--@param cancel_after any The cancel after supplied to this scenario's fixture operation.
--@param cap any The cap supplied to this scenario's fixture operation.
--@return any observed run value observed by the scenario assertion.
local function run(code, args, deadline, cancel_after, cap)
    serial = serial + 1
    local encoded = {}
    for i, value in ipairs(args or {}) do encoded[i] = quote(value) end
    local call = assert(tools:admit_call({
        tool = "lua", schema_version = tools.schema_version, registry_digest = tools.registry_digest,
        provider_call_id = "probe-" .. serial, tool_call_id = "call-" .. serial,
        operation_id = "operation-" .. serial,
        canonical_arguments = '{"args":[' .. table.concat(encoded, ",") .. '],"code":' .. quote(code)
            .. ',"deadline_ms":' .. tostring(deadline or 5000) .. '}',
    }))
    local action = assert(tools:permission_action(call))
    assert(tools:begin_operation(call))
    local token = assert(tools:authorize(call, {
        permission_snapshot_digest = "probe", approval_digest = "probe",
        config_generation = "probe", workspace_identity = action.workspace_root_identity,
        double_check = false, action_review = "not-required",
    }))
    local port = assert(tools:execution_port(token, {
        config_generation = "probe", environment_mode = "minimal", environment = {},
        output_limit_bytes = cap or 65536, deadline_ms = 10000, decoder = "utf-8-strict-candidate",
    }))
    local started = native.monotonic_now()
    assert(port:start(started))
    local terminal, cancelled = false, false
    while not terminal do
        local now = native.monotonic_now()
        assert(now - started < 15000, "native Lua probe exceeded its outer deadline")
        if cancel_after and not cancelled and now - started >= cancel_after then
            assert(type(port:cancel(now)) == "boolean")
            cancelled = true
        end
        for _, event in ipairs(port:poll(now, 16)) do
            if event.kind == "io_terminal" then terminal = true end
        end
        if not terminal then native.sleep_ms(1) end
    end
    local joined = port:join(native.monotonic_now() + 1000)
    assert(port:close())
    assert(joined.tool_result, "Lua did not produce a canonical result")
    assert(joined.tool_result.payload.descendants_proven_stopped, "Lua descendants remain unknown")
    assert(intents == serial and results == serial, "intent/result did not pair")
    return joined.tool_result
end

local source = '-- ' .. string.rep("x", 20000) .. [[

assert(arg[1] == "" and arg[2] == "a b" and arg[3] == "中文🙂")
assert(arg[4] == '" & %PATH% ! $ ;' and arg[5] == '-e')
assert(select('#', ...) == 5)
assert(package.loaded.main == nil and package.loaded.config == nil)
assert(io.read('a') == '')
local f = assert(io.open('lua-roundtrip.bin', 'wb'))
assert(f:write('A\0B')); assert(f:close())
f = assert(io.open('lua-roundtrip.bin', 'rb'))
assert(f:read('a') == 'A\0B'); assert(f:close())
assert(os.remove('lua-roundtrip.bin'))
print('lua-tool-ok')
]]
local result = run(source, { "", "a b", "中文🙂", '" & %PATH% ! $ ;', "-e" })
assert(result.payload.exit_code == 0, result.payload.stderr.text)
assert(result.payload.stdout.text:gsub("\r\n", "\n") == "lua-tool-ok\n")
assert(run("os.exit(37)").payload.exit_code == 37)
local syntax = run("local =")
assert(syntax.payload.exit_code == 1 and syntax.payload.stderr.text:find("expected", 1, true))
local runtime_error = run("error('lua-smoke-error')")
assert(runtime_error.payload.exit_code == 1 and runtime_error.payload.stderr.text:find("lua-smoke-error", 1, true))
assert(run("while true do end", nil, 200).outcome == "timeout")
assert(run("while true do end", nil, 5000, 50).outcome == "cancelled")
local flood = run("io.write(string.rep('x', 1048576))", nil, 5000, nil, 1024)
assert(flood.payload.exit_code == 0 and flood.payload.stdout.observed_bytes == 1048576)
assert(flood.payload.stdout.discarded_bytes > 0)
print("lua-tool-native=PASS cases=7 platform=" .. (windows and "windows" or "linux"))
