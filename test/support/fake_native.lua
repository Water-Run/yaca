--[[
File: fake_native.lua
Date: 2026-08-29
Author: WaterRun
Description: Provides deterministic native-port fakes for unit tests.
]]

local M = {}

local function copy_table(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = item end
    return result
end

---Creates a deterministic platform native-port fake and call counter.
-- @param response table|function|nil Fixed identity or per-call response producer.
-- @param probe_error any Optional error returned when response is nil.
-- @return table port Fake port exposing platform_identity() and call_count().
function M.platform(response, probe_error)
    local calls = 0
    local port = {}

    function port.platform_identity()
        calls = calls + 1
        if type(response) == "function" then return response(calls) end
        if response == nil then return nil, probe_error end
        return copy_table(response)
    end

    function port.call_count()
        return calls
    end

    return port
end

return M
