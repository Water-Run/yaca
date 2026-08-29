--[[
File: terminal.lua
Date: 2026-08-29
Author: WaterRun
Description: Wraps terminal input and restoration as a bounded AsyncPort.
]]

local M = {}

local REQUIRED_NATIVE_METHODS = {
    "terminal_start",
    "terminal_poll",
    "terminal_cancel",
    "terminal_join",
    "terminal_close",
    "terminal_restore",
}

local TERMINAL_OUTCOMES = {
    completed = true,
    cancelled = true,
    failed = true,
    unknown = true,
}

local INPUT_INTENTS = {
    ["submit-or-queue"] = true,
    steer = true,
    newline = true,
    side = true,
    cancel = true,
    text = true,
    eof = true,
}

local function failure(code, message)
    return { code = code, message = message }
end

local function valid_integer(value, minimum)
    return math.type(value) == "integer" and value >= minimum
end

local function typed_native_error(value, operation)
    if type(value) == "table"
        and type(value.code) == "string"
        and value.code ~= ""
        and type(value.message) == "string"
        and value.message ~= ""
    then
        return value
    end
    return failure(
        "NativeContract",
        "native terminal returned an invalid " .. operation .. " error"
    )
end

local function call_native(native, method, ...)
    local called, ok, value = pcall(native[method], ...)
    if not called then
        return false, failure("NativeFailure", "native terminal call raised an exception")
    end
    if ok == true then return true, value end
    if ok == false then return false, typed_native_error(value, method) end
    return false, failure("NativeContract", "native terminal returned an invalid status")
end

local function raise_native(native_error, level)
    error(native_error.code .. ": " .. native_error.message, (level or 1) + 1)
end

local function validate_observation(observation, maximum_input_bytes)
    if type(observation) ~= "table" or observation.source ~= nil then
        return nil, failure("NativeContract", "native terminal observation is invalid")
    end
    if observation.kind == "action" and INPUT_INTENTS[observation.intent] then
        if observation.text ~= nil
            and (type(observation.text) ~= "string"
                or #observation.text > maximum_input_bytes)
        then
            return nil, failure("NativeContract", "native terminal action text is invalid")
        end
        if observation.intent == "text" and observation.text == nil then
            return nil, failure("NativeContract", "native terminal text action omits bytes")
        end
        if observation.intent ~= "text" and observation.text ~= nil then
            return nil, failure("NativeContract", "native terminal non-text action carries bytes")
        end
        return observation
    end
    if observation.kind == "terminal" and TERMINAL_OUTCOMES[observation.outcome] then
        return observation
    end
    return nil, failure("NativeContract", "native terminal observation kind is invalid")
end

---Creates a restorable terminal AsyncPort.
-- The adapter never assumes ANSI support. Native capability probing selects raw
-- or cooked input, while both modes emit the same semantic action vocabulary.
-- @param native table Native terminal implementation.
-- @param options table Terminal mode request and fixed input byte cap.
-- @return table|nil port AsyncPort with an additional restore method.
-- @return table|nil err Structured construction failure.
function M.new(native, options)
    if type(native) ~= "table" then
        return nil, failure("InvalidTerminalPort", "native terminal port is required")
    end
    for _, method in ipairs(REQUIRED_NATIVE_METHODS) do
        if type(native[method]) ~= "function" then
            return nil, failure("InvalidTerminalPort", "native terminal omits " .. method)
        end
    end
    options = options or {}
    local maximum_input_bytes = options.maximum_input_bytes
    if not valid_integer(maximum_input_bytes, 1) then
        return nil, failure("InvalidTerminalLimit", "maximum_input_bytes is required")
    end
    local requested_mode = options.mode or "auto"
    if requested_mode ~= "auto" and requested_mode ~= "raw" and requested_mode ~= "cooked" then
        return nil, failure("InvalidTerminalMode", "terminal mode must be auto, raw, or cooked")
    end

    local state = "created"
    local handle
    local terminal_outcome
    local restored = false
    local port = {}

    ---Starts terminal input without claiming unsupported key combinations.
    -- @param now integer Current monotonic tick.
    -- @return boolean started True after native mode admission.
    function port:start(now)
        if state ~= "created" then error("terminal port is " .. state, 2) end
        if not valid_integer(now, 0) then error("terminal start time is invalid", 2) end
        local ok, value = call_native(native, "terminal_start", {
            mode = requested_mode,
            maximum_input_bytes = maximum_input_bytes,
            started_at = now,
        })
        if not ok then raise_native(value, 1) end
        if value == nil then
            raise_native(failure("NativeContract", "native terminal returned no handle"), 1)
        end
        handle, state = value, "started"
        return true
    end

    ---Polls a bounded array of semantic input or terminal events.
    -- @param now integer Current monotonic tick.
    -- @param budget integer Maximum returned observations.
    -- @return table events AsyncPort event array.
    function port:poll(now, budget)
        if state ~= "started" then error("terminal port is " .. state, 2) end
        if terminal_outcome then return {} end
        if not valid_integer(now, 0) or not valid_integer(budget, 0) then
            error("terminal poll arguments are invalid", 2)
        end
        local ok, observations = call_native(native, "terminal_poll", handle, now, budget)
        if not ok then raise_native(observations, 1) end
        if type(observations) ~= "table" then
            raise_native(failure("NativeContract", "native terminal poll returned no array"), 1)
        end
        local event_count = 0
        for key in pairs(observations) do
            if math.type(key) ~= "integer" or key < 1 then
                raise_native(failure("NativeContract", "native terminal poll returned a map"), 1)
            end
            event_count = event_count + 1
        end
        if event_count > budget then
            raise_native(failure("NativeContract", "native terminal exceeded poll budget"), 1)
        end
        local events = {}
        for index = 1, event_count do
            local observation, observation_error = validate_observation(
                observations[index],
                maximum_input_bytes
            )
            if not observation then raise_native(observation_error, 1) end
            if terminal_outcome then
                raise_native(failure("NativeContract", "terminal emitted data after terminal"), 1)
            end
            if observation.kind == "terminal" then
                terminal_outcome = observation.outcome
                events[#events + 1] = {
                    kind = "io_terminal",
                    outcome = observation.outcome,
                }
            else
                events[#events + 1] = {
                    kind = "user_action",
                    action = observation.intent,
                    text = observation.text,
                }
            end
        end
        return events
    end

    ---Requests input cancellation without fabricating a terminal outcome.
    -- @param now integer Current monotonic tick.
    -- @return boolean accepted Whether the native request was admitted.
    function port:cancel(now)
        if state ~= "started" then error("terminal port is " .. state, 2) end
        if terminal_outcome then return false end
        if not valid_integer(now, 0) then error("terminal cancel time is invalid", 2) end
        local ok, value = call_native(native, "terminal_cancel", handle, now)
        if not ok then raise_native(value, 1) end
        if type(value) ~= "boolean" then
            raise_native(failure("NativeContract", "native terminal cancel result is invalid"), 1)
        end
        return value
    end

    ---Joins terminal input and validates its typed terminal result.
    -- @param deadline integer|nil Absolute monotonic deadline.
    -- @return table result Table containing the terminal outcome.
    function port:join(deadline)
        if state ~= "started" then error("terminal port is " .. state, 2) end
        if deadline ~= nil and not valid_integer(deadline, 0) then
            error("terminal join deadline is invalid", 2)
        end
        local ok, value = call_native(native, "terminal_join", handle, deadline)
        if not ok then raise_native(value, 1) end
        if type(value) ~= "table" or not TERMINAL_OUTCOMES[value.outcome] then
            raise_native(failure("NativeContract", "native terminal join result is invalid"), 1)
        end
        if terminal_outcome and terminal_outcome ~= value.outcome then
            raise_native(failure("NativeContract", "terminal join contradicted terminal event"), 1)
        end
        terminal_outcome = value.outcome
        state = "joined"
        return { outcome = value.outcome }
    end

    ---Restores input modes using an idempotent best-effort native primitive.
    -- @return boolean restored True after native restoration succeeds.
    function port:restore()
        if restored then return true end
        if state == "created" then
            restored = true
            return true
        end
        if state == "closed" then error("terminal port is closed", 2) end
        local ok, value = call_native(native, "terminal_restore", handle)
        if not ok then raise_native(value, 1) end
        restored = true
        return true
    end

    ---Restores terminal state and then releases the native handle.
    -- @return boolean closed True after both operations succeed.
    function port:close()
        if state ~= "started" and state ~= "joined" then
            error("terminal port is " .. state, 2)
        end
        local restore_error
        if not restored then
            local restored_ok, restored_value = call_native(native, "terminal_restore", handle)
            if restored_ok then
                restored = true
            else
                restore_error = restored_value
            end
        end
        local close_ok, close_value = call_native(native, "terminal_close", handle)
        state = "closed"
        if restore_error then raise_native(restore_error, 1) end
        if not close_ok then raise_native(close_value, 1) end
        return true
    end

    return port
end

return M
