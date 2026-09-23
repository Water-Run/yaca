--[[
Author: WaterRun
Date: 2026-09-23
File: fake_native.lua
Description: Provides deterministic native-port fakes for unit tests.
]]

local M = {}

--Supplies copy table behavior required by this suite.
--@param value any Candidate whose acceptance or transformation the test checks.
--@return any observed copy table value observed by the scenario assertion.
local function copy_table(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = item end
    return result
end

---Creates a deterministic platform native-port fake and call counter.
--@param response table|function|nil Fixed identity or per-call response producer.
--@param probe_error any Optional error returned when response is nil.
--@return table port Fake port exposing platform_identity() and call_count().
function M.platform(response, probe_error)
    local calls = 0
    local port = {}

    --Simulates platform identity in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return any|nil outcome Simulated platform identity outcome returned to the component.
    --@return any|nil secondary2 Probe diagnostic returned by the fixture.
    function port.platform_identity()
        calls = calls + 1
        if type(response) == "function" then return response(calls) end
        if response == nil then return nil, probe_error end
        return copy_table(response)
    end

    --Simulates call count in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return any outcome Simulated call count outcome returned to the component.
    function port.call_count()
        return calls
    end

    return port
end

return M
