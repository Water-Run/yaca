--[[
File: clock.lua
Date: 2026-08-29
Author: WaterRun
Description: Wraps monotonic and UTC native clock capabilities without fallback.
]]

local M = {}

local function failure(code, detail)
    return { code = code, detail = detail }
end

local function readonly(values, label)
    return setmetatable({}, {
        __index = values,
        __newindex = function(_, key) error((label or "readonly value") .. " cannot be modified: " .. tostring(key), 2) end,
        __pairs = function() return next, values, nil end,
        __metatable = "locked",
    })
end

local function valid_tick(value)
    return math.type(value) == "integer" and value >= 0
end

---Creates a clock service with sticky degradation on monotonic failure.
---@param native table Native port exposing monotonic_now() and utc_now().
---@return table|nil service Immutable clock service.
---@return table|nil err Structured construction failure.
function M.new(native)
    if type(native) ~= "table" or type(native.monotonic_now) ~= "function" or type(native.utc_now) ~= "function" then
        return nil, failure("InvalidClockPort", "monotonic_now and utc_now functions are required")
    end

    local last_tick
    local degraded_error
    local service = {}

    ---Reads a nonnegative monotonic tick and rejects clock regression.
    ---@return integer|nil tick Current monotonic tick.
    ---@return table|nil err Sticky degradation failure.
    function service.monotonic_now()
        if degraded_error then return nil, degraded_error end
        local ok, tick = pcall(native.monotonic_now)
        if not ok or not valid_tick(tick) then
            degraded_error = failure("MonotonicClockDegraded", ok and "invalid monotonic tick" or tostring(tick))
            return nil, degraded_error
        end
        if last_tick and tick < last_tick then
            degraded_error = failure("MonotonicClockDegraded", "monotonic clock regressed")
            return nil, degraded_error
        end
        last_tick = tick
        return tick
    end

    ---Reads UTC display/audit time without affecting deadline safety.
    ---@return string|nil value Native UTC representation.
    ---@return table|nil err Structured read failure.
    function service.utc_now()
        local ok, value = pcall(native.utc_now)
        if not ok or type(value) ~= "string" or value == "" then
            return nil, failure("UtcClockReadFailed", ok and "invalid UTC value" or tostring(value))
        end
        return value
    end

    ---Creates an immutable deadline relative to the monotonic clock.
    ---@param duration integer Nonnegative tick duration.
    ---@return table|nil deadline Immutable object containing the absolute tick.
    ---@return table|nil err Structured validation or clock failure.
    function service.deadline(duration)
        if not valid_tick(duration) then return nil, failure("InvalidDeadline", "duration must be a nonnegative integer") end
        local now, clock_error = service.monotonic_now()
        if not now then return nil, clock_error end
        if duration > math.maxinteger - now then return nil, failure("InvalidDeadline", "deadline overflow") end
        return readonly({ at = now + duration }, "deadline")
    end

    ---Checks whether a monotonic deadline has elapsed.
    ---@param deadline table Deadline returned by deadline().
    ---@return boolean|nil expired True when the absolute tick has passed.
    ---@return table|nil err Structured validation or clock failure.
    function service.expired(deadline)
        if type(deadline) ~= "table" or not valid_tick(deadline.at) then return nil, failure("InvalidDeadline", "deadline.at is required") end
        local now, clock_error = service.monotonic_now()
        if not now then return nil, clock_error end
        return now >= deadline.at
    end

    ---Reports whether monotonic timing remains safe to use.
    ---@return string status Either "ok" or "degraded".
    ---@return table|nil err Sticky degradation failure, when present.
    function service.status()
        return degraded_error and "degraded" or "ok", degraded_error
    end

    return readonly(service, "clock service")
end

return M
