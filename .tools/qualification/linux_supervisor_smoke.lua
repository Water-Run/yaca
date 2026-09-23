--[[
Author: WaterRun
Date: 2026-09-23
File: linux_supervisor_smoke.lua
Description: Actual Linux descendants, pipe backpressure, GC, and failed supervision.
]]

-- Actual Linux descendants, pipe backpressure, GC, and failed supervision.
-- Every test child has a finite lifetime, including against a broken build.
local root, library, scratch, mode = table.unpack(arg)
assert(root and library and scratch)
package.path = root .. "/src/?.lua"
local native = assert(package.loadlib(library, "luaopen_yaca_native"))()
local processes = assert(require("process").new(native, {
    maximum_output_bytes = 65536, maximum_poll_bytes = 4096,
    maximum_stdin_bytes = 1048576,
    shell = { kind = "linux", executable = "/bin/sh", fixed_arguments = { "-c" } },
}))
--Computes shell in linux supervisor smoke.
--@param command string|table Command delivered to the fake executor.
--@return any observed shell value observed by the scenario assertion.
local function shell(command)
    return assert(processes.new_port({ command = command, cwd = scratch,
        environment = {}, environment_mode = "minimal", output_limit_bytes = 65536 }))
end
--Computes pid in linux supervisor smoke.
--@param name string Module, Model, or resource name selected by the case.
--@return any|nil observed Selected fixture value when available; nil otherwise.
local function pid(name)
    local file = io.open(scratch .. "/" .. name, "r")
    if not file then return nil end
    local value = assert(file:read("a")):match("^(%d+)%s*$")
    file:close()
    return value
end
--Computes alive in linux supervisor smoke.
--@param value any Candidate value supplied to the fixture operation.
--@return boolean|number observed alive value observed by the scenario assertion.
local function alive(value)
    local file = io.open("/proc/" .. assert(value) .. "/stat", "r")
    if not file then return false end
    local stat = file:read("a"); file:close()
    return stat:match("%) ([A-Z]) ") ~= "Z"
end
--Computes wait for pid in linux supervisor smoke.
--@param name string Module, Model, or resource name selected by the case.
--@return any observed Selected fixture value returned by the fixture.
local function wait_for_pid(name)
    local deadline = native.monotonic_now() + 1000
    repeat
        local value = pid(name)
        if value then return value end
        native.sleep_ms(5)
    until native.monotonic_now() > deadline
    error("child did not publish its PID: " .. name)
end
--Computes settle in linux supervisor smoke.
--@param port any The port supplied to this scenario's fixture operation.
--@param cancelled any The cancelled supplied to this scenario's fixture operation.
--@param minimum_ms any The minimum ms supplied to this scenario's fixture operation.
--@param expected any Expected value used by the assertion.
--@return any observed settle value observed by the scenario assertion.
local function settle(port, cancelled, minimum_ms, expected)
    local start = native.monotonic_now()
    if cancelled then assert(port:cancel(start)) end
    local done = false
    repeat
        for _, event in ipairs(port:poll(native.monotonic_now(), 16)) do
            if event.kind == "io_terminal" then done = true end
        end
        assert(native.monotonic_now() - start < 2000, "activity did not settle promptly")
        if not done then native.sleep_ms(5) end
    until done
    local result = assert(port:join(native.monotonic_now()))
    assert(port:close())
    assert(native.monotonic_now() - start >= (minimum_ms or 0))
    assert(result.outcome == (expected or (cancelled and "cancelled" or "completed")), result.outcome)
    assert(result.descendants_proven_stopped == (expected ~= "unknown"))
    return result
end
--Computes escaped in linux supervisor smoke.
--@param name string Module, Model, or resource name selected by the case.
--@param seconds any The seconds supplied to this scenario's fixture operation.
--@return any observed escaped value observed by the scenario assertion.
local function escaped(name, seconds)
    assert(not pid(name), "scratch file already exists")
    -- The first shell exits, the detached shell forks, then its parent exits.
    return shell("/usr/bin/setsid /bin/sh -c '/bin/sh -c "
        .. "'\"'\"'echo $$ > " .. name .. "; exec /bin/sleep " .. seconds
        .. "'\"'\"' > /dev/null 2>&1 &' > /dev/null 2>&1 &")
end

if mode == "parent-death" then
    local port = escaped("parent-death.pid", 5)
    assert(port:start(native.monotonic_now()))
    print("ready=" .. wait_for_pid("parent-death.pid")); io.stdout:flush()
    while true do native.sleep_ms(10) end
end

local port = escaped("cancel.pid", 5)
assert(port:start(native.monotonic_now()))
local child = wait_for_pid("cancel.pid")
assert(alive(child)); settle(port, true); assert(not alive(child))

port = escaped("natural.pid", 1)
assert(port:start(native.monotonic_now()))
child = wait_for_pid("natural.pid")
assert(alive(child)); settle(port, false, 500); assert(not alive(child))

port = assert(processes.new_component_port({ executable = "/bin/sh",
    arguments = { "-c", "/bin/sleep 5" }, cwd = scratch, environment = {},
    stdin_bytes = string.rep("x", 1048576), output_limit_bytes = 65536 }))
local started = native.monotonic_now()
assert(port:start(started))
assert(native.monotonic_now() - started < 500, "stdin backpressure blocked start")
settle(port, true)

port = escaped("gc.pid", 5)
assert(port:start(native.monotonic_now()))
child = wait_for_pid("gc.pid")
port = nil; collectgarbage("collect"); assert(not alive(child), "GC left a child running")

port = shell('kill -KILL "$PPID"; /bin/sleep 1')
assert(port:start(native.monotonic_now()))
settle(port, false, 0, "unknown")

port = shell("exit 37")
assert(port:start(native.monotonic_now()))
assert(settle(port, false, 0, "failed").exit_code == 37)
print("linux-supervisor=PASS cases=6")
