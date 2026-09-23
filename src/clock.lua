--[[
Author: WaterRun
Date: 2026-08-29
File: clock.lua
Description: Wraps monotonic and UTC native clock capabilities without fallback.
]]

local M = {}

-- Construct a structured diagnostic without throwing or formatting its optional fields.
--@param code string Stable diagnostic code used by callers to choose recovery behavior.
--@param detail any|nil Optional underlying cause or contextual diagnostic data; retained as supplied.
--@return table New diagnostic record; optional non-nil fields are retained without deep copying.
local function failure(code, detail)
    return { code = code, detail = detail }
end

-- Create a shallow read-only view without copying the backing table.
--@param values table Backing fields retained by reference; the caller owns their stability.
--@param label string|nil Diagnostic label; defaults to "readonly value".
--@return table Empty proxy exposing the backing fields through its locked metatable.
--@ownership Retains values by reference; nested values and the backing table are not frozen.
local function readonly(values, label)
    --@metatable readonly_proxy Forwards reads and iteration; ordinary assignments raise an error.
    --@field __index table Backing values used for missing-key reads.
    --@field __newindex function Rejects ordinary assignments without changing the backing values.
    --@field __pairs function Enumerates the backing table with next.
    --@field __metatable string Hides this metatable behind the fixed "locked" marker.
    return setmetatable({}, {
        __index = values,
        -- Reject a write through the proxy before it can create an ordinary field.
        --@param _ table Proxy receiving the assignment; its contents are not consulted.
        --@param key any Attempted field name included in the diagnostic.
        --@return nil Does not return normally.
        --@error Always raises a read-only assignment error at the caller frame.
        __newindex = function(_, key)
            error((label or "readonly value") .. " cannot be modified: " .. tostring(key), 2)
        end,
        -- Iterate the backing fields instead of the empty proxy table.
        --@param none The proxy argument supplied by pairs is ignored.
        --@return function The standard next iterator.
        --@return table Backing values used as iterator state.
        --@return nil Initial key used to start iteration.
        __pairs = function()
            return next, values, nil
        end,
        __metatable = "locked",
    })
end

-- Admit only nonnegative Lua integers for monotonic ticks and durations.
--@param value any Candidate tick; floating-point numbers are not admitted.
--@return boolean True when value is an integer at least zero.
local function valid_tick(value)
    return math.type(value) == "integer" and value >= 0
end

---Creates a clock service with sticky degradation on monotonic failure.
--@param native table Native port exposing monotonic_now() and utc_now().
--@return table|nil service Immutable clock service.
--@return table|nil err Structured construction failure.
function M.new(native)
    if type(native) ~= "table" or type(native.monotonic_now) ~= "function" or type(native.utc_now) ~= "function" then
        return nil, failure("InvalidClockPort", "monotonic_now and utc_now functions are required")
    end

    local last_tick
    local degraded_error
    local service = {}

    ---Reads a nonnegative monotonic tick and rejects clock regression.
    --@param none No arguments; reads the native clock bound to this service.
    --@return integer|nil tick Current monotonic tick.
    --@return table|nil err Sticky degradation failure.
    --@effect Updates the last accepted tick; a probe failure or regression permanently degrades this service.
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
    --@param none No arguments; reads the native UTC source bound to this service.
    --@return string|nil value Native UTC representation.
    --@return table|nil err Structured read failure.
    function service.utc_now()
        local ok, value = pcall(native.utc_now)
        if not ok or type(value) ~= "string" or value == "" then
            return nil, failure("UtcClockReadFailed", ok and "invalid UTC value" or tostring(value))
        end
        return value
    end

    ---Creates an immutable deadline relative to the monotonic clock.
    --@param duration integer Nonnegative tick duration.
    --@return table|nil deadline Immutable object containing the absolute tick.
    --@return table|nil err Structured validation or clock failure.
    function service.deadline(duration)
        if not valid_tick(duration) then return nil, failure("InvalidDeadline", "duration must be a nonnegative integer") end
        local now, clock_error = service.monotonic_now()
        if not now then return nil, clock_error end
        if duration > math.maxinteger - now then return nil, failure("InvalidDeadline", "deadline overflow") end
        return readonly({ at = now + duration }, "deadline")
    end

    ---Checks whether a monotonic deadline has elapsed.
    --@param deadline table Deadline returned by deadline().
    --@return boolean|nil expired True when the absolute tick has passed.
    --@return table|nil err Structured validation or clock failure.
    function service.expired(deadline)
        if type(deadline) ~= "table" or not valid_tick(deadline.at) then return nil, failure("InvalidDeadline", "deadline.at is required") end
        local now, clock_error = service.monotonic_now()
        if not now then return nil, clock_error end
        return now >= deadline.at
    end

    ---Reports whether monotonic timing remains safe to use.
    --@param none No arguments; inspects cached clock state without probing the native clock.
    --@return string status Either "ok" or "degraded".
    --@return table|nil err Sticky degradation failure, when present.
    function service.status()
        return degraded_error and "degraded" or "ok", degraded_error
    end

    return readonly(service, "clock service")
end

return M
