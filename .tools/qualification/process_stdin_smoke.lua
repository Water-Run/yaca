--[[
Author: WaterRun
Date: 2026-09-23
File: process_stdin_smoke.lua
Description: Real pipe backpressure, independent of the Agent/model network.
]]

-- Real pipe backpressure, independent of the Agent/model network.
local root, library, interpreter, scratch = table.unpack(arg)
assert(root and library and interpreter and scratch)
package.path = root .. "/src/?.lua"
local native = assert(package.loadlib(library, "luaopen_yaca_native"))()
local windows = native.platform_identity().os == "windows"
local processes = assert(require("process").new(native, {
    maximum_output_bytes = 65536, maximum_poll_bytes = 4096, maximum_stdin_bytes = 1048576,
    shell = windows and { kind = "windows", executable = "native-GetSystemDirectoryW/cmd.exe",
        fixed_arguments = { "/d", "/s", "/c" } }
        or { kind = "linux", executable = "/bin/sh", fixed_arguments = { "-c" } },
}))
--Computes run in process stdin smoke.
--@param executable any The executable supplied to this scenario's fixture operation.
--@param arguments table Argument vector delivered to the fake process.
--@param cancel any The cancel supplied to this scenario's fixture operation.
--@return any observed run value observed by the scenario assertion.
local function run(executable, arguments, cancel)
    local port = assert(processes.new_component_port({ executable = executable,
        arguments = arguments, cwd = scratch, environment = {},
        stdin_bytes = string.rep("x", 1048576), output_limit_bytes = 65536 }))
    local started = native.monotonic_now()
    assert(port:start(started))
    assert(native.monotonic_now() - started < 500, "input blocked the native start")
    local done, cancelled = false, false
    repeat
        local now = native.monotonic_now()
        if cancel and not cancelled and now - started > 50 then
            assert(port:cancel(now)); cancelled = true
        end
        for _, event in ipairs(port:poll(now, 16)) do
            if event.kind == "io_terminal" then done = true end
        end
        assert(now - started < 5000, "pipe activity exceeded its deadline")
        if not done then native.sleep_ms(2) end
    until done
    local result = assert(port:join(native.monotonic_now()))
    assert(port:close())
    assert(result.descendants_proven_stopped)
    assert(result.outcome == (cancel and "cancelled" or "completed"), result.outcome)
    return result
end
run(windows and (assert(os.getenv("SystemRoot")) .. "/System32/ping.exe") or "/bin/sleep",
    windows and { "-n", "6", "127.0.0.1" } or { "5" }, true)
local code = "io.write(string.rep('O',131072)); io.stdout:flush(); "
    .. "assert(#io.read('a')==1048576); print('stdin=PASS')"
local arguments = { "-E", "-e", code }
if windows or not interpreter:match("/lua$") then table.insert(arguments, 1, "--lua") end
local result = run(interpreter, arguments, false)
assert(result.exit_code == 0)
assert(result.stdout_observed_bytes >= 131072)
print("process-stdin=PASS cases=2 platform=" .. (windows and "windows" or "linux"))
