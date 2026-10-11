--[[
Author: WaterRun
Date: 2026-10-08
File: terminal_adapter_native_smoke.lua
Description: Exercises the production terminal adapter and native raw owner on
an assigned PTY, with explicit forwarding rejection controls and host-observed
mode checkpoints. Consumes no user input or model configuration.
]]

local root, library, acknowledgment, profile = table.unpack(arg)
assert(root and library and acknowledgment and profile)
local native = assert(package.loadlib(library, "luaopen_yaca_native"))()
local text = assert(loadfile(root .. "/src/text.lua", "t", _ENV))()
local environment = {}
for key, value in pairs(_ENV) do environment[key] = value end
--@metatable terminal_smoke_environment Local source bindings with standard global fallback.
--@field __index table Current trusted interpreter globals used for missing keys.
setmetatable(environment, { __index = _ENV })
-- Resolve only the adapter's production text dependency.
--@param name string Dependency requested by terminal.lua.
--@return table The independently loaded production text module.
--@error Raises for an unexpected dependency.
environment.require = function(name)
    assert(name == "text")
    return text
end
environment._G = environment
local terminal = assert(loadfile(root .. "/src/terminal.lua", "t", environment))()
local forwarded = {}
for key, value in pairs(native) do forwarded[key] = value end
local restore_rejections = 0
local close_rejections = 0
if profile == "both" or profile == "joined" or profile == "recover" then
    restore_rejections = 1
end
if profile == "both" or profile == "joined" or profile == "close" then
    close_rejections = 1
end
local restores, closes = 0, 0

-- Forward native restore after the explicitly selected pre-call rejection is consumed.
--@param handle userdata Actual native terminal owner retained by the production adapter.
--@return boolean Actual native status, or false for the one injected rejection.
--@return any Actual native acknowledgment/error, or the fixed structured rejection.
--@effect Counts attempts; successful forwarding calls the actual OS restoration implementation.
forwarded.terminal_restore = function(handle)
    restores = restores + 1
    if restore_rejections > 0 then
        restore_rejections = restore_rejections - 1
        return false, { code = "InjectedRestore", message = "fixed forwarding rejection" }
    end
    return native.terminal_restore(handle)
end

-- Forward native close after one optional rejection while preserving the actual live owner.
--@param handle userdata Actual native owner kept open when this shim rejects before calling C.
--@return boolean Actual native status, or false for the configured pre-call rejection.
--@return any Actual close acknowledgment/error, or the fixed structured rejection.
--@effect Counts attempts; the final successful call actually restores/closes native ownership.
forwarded.terminal_close = function(handle)
    closes = closes + 1
    if close_rejections > 0 then
        close_rejections = close_rejections - 1
        return false, { code = "InjectedClose", message = "fixed forwarding rejection" }
    end
    return native.terminal_close(handle)
end

-- Emit one observable mode checkpoint and wait for the host's private acknowledgment file.
--@param stage string Fixed checkpoint identifying an actual live raw or restored mode.
--@return nil No value after the host has measured the PTY and acknowledged it.
--@effect Writes/flushes stdout and polls only the assigned file for at most five seconds.
--@error Raises if the independent host does not acknowledge the checkpoint in time.
local function checkpoint(stage)
    io.stdout:write("terminal-adapter-stage=", stage, "\n")
    io.stdout:flush()
    local deadline = native.monotonic_now() + 5000
    while native.monotonic_now() < deadline do
        local file = io.open(acknowledgment, "rb")
        if file then file:close(); return end
        native.sleep_ms(5)
    end
    error("PTY checkpoint acknowledgment timed out")
end

local port = assert(terminal.new(forwarded, { mode = "raw", maximum_input_bytes = 32 }))
if profile == "created" then assert(port:restore() and restores == 0) end
port:start(native.monotonic_now())
if profile == "created" then
    assert(port:restore() and restores == 1)
    checkpoint("restored")
    assert(port:close())
elseif profile == "recover" then
    assert(port:close() and restores == 1 and closes == 1)
    checkpoint("restored")
else
    if profile == "joined" then
        assert(port:cancel(native.monotonic_now()))
        local events = port:poll(native.monotonic_now(), 1)
        assert(events[1].outcome == "cancelled")
        assert(port:join().outcome == "cancelled")
    end
    local ok, message = pcall(port.close, port)
    assert(not ok and (message:find("InjectedRestore", 1, true) or message:find("InjectedClose", 1, true)))
    checkpoint(profile == "close" and "restored" or "raw")
    if profile ~= "joined" then assert(#port:poll(native.monotonic_now(), 1) == 0) end
    assert(port:close())
end
assert(port:restore())
io.stdout:write("terminal-adapter-native profile=", profile, " restores=", restores,
    " closes=", closes, " result=PASS\n")
