--[[
Author: WaterRun
Date: 2026-09-23
File: process_tree_smoke.lua
Description: Real process-tree cancellation after the shell leader exits.
]]

-- Real process-tree cancellation after the shell leader exits.
-- Arguments: source root, native module path, isolated working directory.
local source_root, native_path, scratch = table.unpack(arg)
assert(source_root and native_path and scratch, "three probe paths are required")
package.path = source_root .. "/src/?.lua"
local native = assert(package.loadlib(native_path, "luaopen_yaca_native"))()
local windows = native.platform_identity().os == "windows"
local processes = assert(require("process").new(native, {
    maximum_output_bytes = 65536, maximum_poll_bytes = 4096,
    shell = windows and { kind = "windows", executable = "native-GetSystemDirectoryW/cmd.exe",
        fixed_arguments = { "/d", "/s", "/c" } }
        or { kind = "linux", executable = "/bin/sh", fixed_arguments = { "-c" } },
}))

--Computes run in process tree smoke.
--@param seconds any The seconds supplied to this scenario's fixture operation.
--@param cancel_after any The cancel after supplied to this scenario's fixture operation.
--@return any observed run value observed by the scenario assertion.
local function run(seconds, cancel_after)
    -- Both children have their own finite limit, including on a broken build.
    local command = windows
        and ('start "" /b "%SystemRoot%\\System32\\ping.exe" -n ' .. (seconds + 1) .. ' 127.0.0.1 > nul')
        or ('/bin/sleep ' .. seconds .. ' &')
    local port = assert(processes.new_port({
        command = command, cwd = scratch, environment = {}, environment_mode = "minimal",
        output_limit_bytes = 65536,
    }))
    local start = native.monotonic_now()
    assert(port:start(start))
    local terminal, cancelled = false, false
    while not terminal do
        local now = native.monotonic_now()
        assert(now - start < 7000, "process tree exceeded the probe deadline")
        for _, event in ipairs(port:poll(now, 16)) do
            if event.kind == "io_terminal" then terminal = true end
        end
        if cancel_after and not cancelled and now - start >= cancel_after then
            assert(port:cancel(now), "cancel refused while the child remained alive")
            cancelled = true
        end
        if not terminal then native.sleep_ms(5) end
    end
    local result = port:join(native.monotonic_now())
    assert(port:close())
    assert(result.descendants_proven_stopped, "managed descendants did not stop")
    local elapsed = native.monotonic_now() - start
    if cancel_after then
        assert(cancelled and result.outcome == "cancelled", "cancellation outcome was lost")
        assert(elapsed < 2000, "cancellation waited for the child's natural exit")
    else
        assert(result.outcome == "completed" and elapsed >= 500,
            "completion ignored a child still running after the shell exited")
    end
    return elapsed
end

local cancelled_ms, completed_ms = run(5, 500), run(1)
print("process-tree=PASS cases=2 platform=" .. (windows and "windows" or "linux")
    .. " cancelled_ms=" .. cancelled_ms .. " completed_ms=" .. completed_ms)
