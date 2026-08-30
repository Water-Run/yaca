--[[
File: prove_native_component.lua
Date: 2026-08-30
Author: WaterRun
Description: Proves the production native structured-argv and stdin carrier.
]]

local root = assert(arg[1], "repository root is required")
local native_path = assert(arg[2], "native module path is required")
local probe_path = assert(arg[3], "component probe path is required")

package.path = root .. "/src/?.lua"
local open_native = assert(package.loadlib(native_path, "luaopen_yaca_native"))
local native = open_native()
local identity = native.platform_identity()
local process = require("process")

local shell = identity.os == "windows" and {
    kind = "windows",
    executable = "native-GetSystemDirectoryW/cmd.exe",
    fixed_arguments = { "/d", "/s", "/c" },
} or {
    kind = "linux",
    executable = "/bin/sh",
    fixed_arguments = { "-c" },
}

local service = assert(process.new(native, {
    maximum_output_bytes = 65536,
    maximum_poll_bytes = 4096,
    maximum_stdin_bytes = 4096,
    maximum_arguments = 16,
    maximum_argument_bytes = 4096,
    shell = shell,
}))

local function assert_native_rejects(request, expected_code)
    local ok, value = native.process_start(request)
    assert(ok == false, "malformed native component request was accepted")
    assert(type(value) == "table" and value.code == expected_code, "wrong native rejection")
end

local malformed_base = {
    mode = "argv",
    executable = probe_path,
    arguments = {},
    cwd = root,
    environment = {},
    stdin = { kind = "bytes", bytes = "", carrier = "anonymous-pipe" },
    started_at = native.monotonic_now(),
}
local numeric_mode = {}
for key, value in pairs(malformed_base) do numeric_mode[key] = value end
numeric_mode.mode = 1
assert_native_rejects(numeric_mode, "InvalidProcessMode")
local numeric_argument = {}
for key, value in pairs(malformed_base) do numeric_argument[key] = value end
numeric_argument.arguments = { 1 }
assert_native_rejects(numeric_argument, "InvalidArguments")
local numeric_stdin = {}
for key, value in pairs(malformed_base) do numeric_stdin[key] = value end
numeric_stdin.stdin = { kind = "bytes", bytes = 1, carrier = "anonymous-pipe" }
assert_native_rejects(numeric_stdin, "InvalidComponent")

local values = {
    "space value",
    "quote\"backslash\\tail\\",
    "meta&|<>^%!",
    "",
}
local stdin_bytes = "\0line\r\n" .. string.char(0xff) .. "tail"
local port = assert(service.new_component_port({
    executable = probe_path,
    arguments = values,
    cwd = root,
    environment = {},
    stdin_bytes = stdin_bytes,
    output_limit_bytes = 65536,
}))

local function hex(bytes)
    return (bytes:gsub(".", function(byte)
        return string.format("%02x", byte:byte())
    end))
end

local function run_to_terminal(active_port, label)
    assert(active_port:start(native.monotonic_now()))
    local terminal = false
    local polls = 0
    while not terminal do
        polls = polls + 1
        assert(polls <= 10000, label .. " did not reach a bounded terminal state")
        for _, event in ipairs(active_port:poll(native.monotonic_now(), 16)) do
            if event.kind == "io_terminal" then terminal = true end
        end
        if not terminal then native.sleep_ms(1) end
    end
    return active_port:join(native.monotonic_now() + 1000)
end

local result = run_to_terminal(port, "component")
assert(result.outcome == "completed", "component did not complete")
assert(result.exit_kind == "exit-code" and result.exit_code == 0, "component exit failed")
assert(result.descendants_proven_stopped, "component descendants are not terminal")
assert(not result.stdout_truncated and not result.stderr_truncated, "component output truncated")
assert(result.stderr == "", "component wrote a diagnostic")

local expected = { "argc=" .. tostring(#values + 1) }
for index, value in ipairs(values) do
    expected[#expected + 1] = "arg" .. tostring(index) .. "=" .. hex(value)
end
expected[#expected + 1] = "stdin=" .. hex(stdin_bytes)
expected = table.concat(expected, "\n") .. "\n"
assert(result.stdout == expected, "component argv/stdin bytes changed")
assert(port:close())

local shell_command = identity.os == "windows" and "echo shell-ok" or "printf shell-ok"
local shell_port = assert(service.new_port({
    command = shell_command,
    cwd = root,
    output_limit_bytes = 4096,
}))
local shell_result = run_to_terminal(shell_port, "shell")
assert(shell_result.outcome == "completed", "fixed platform shell did not complete")
assert(shell_result.stdout:find("shell-ok", 1, true), "fixed platform shell output changed")
assert(shell_port:close())

io.stdout:write("native-component=PASS\n")
io.stdout:write("platform=", identity.os, "-", identity.arch, "\n")
io.stdout:write("shell-bypassed=true\n")
io.stdout:write("stdin-carrier=anonymous-pipe\n")
io.stdout:write("argv-cases=space,quote,backslash,cmd-meta,empty\n")
io.stdout:write("malformed-native-requests=rejected\n")
io.stdout:write("fixed-shell=PASS\n")
