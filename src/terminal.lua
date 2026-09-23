--[[
Author: WaterRun
Date: 2026-09-23
File: terminal.lua
Description: Wraps terminal input and restoration as a bounded AsyncPort.
]]

local text = require("text")

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
    ask = true,
    cancel = true,
    text = true,
    eof = true,
}

-- Construct a structured diagnostic without throwing or formatting its optional fields.
--@param code string Stable diagnostic code used by callers to choose recovery behavior.
--@param message string Human-readable summary supplied by the failing operation.
--@param extra table|nil Additional diagnostic fields copied after code/message and allowed to override them.
--@return table New diagnostic record; optional non-nil fields are retained without deep copying.
local function failure(code, message, extra)
    local result = { code = code, message = message }
    for key, value in pairs(extra or {}) do result[key] = value end
    return result
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

-- Check the Lua integer subtype and the caller's inclusive lower bound.
--@param value any Candidate value; floats and non-numeric values are rejected.
--@param minimum integer Inclusive minimum accepted by this check.
--@return boolean True only for an integer at least minimum.
local function valid_integer(value, minimum)
    return math.type(value) == "integer" and value >= minimum
end

-- Preserve a valid native terminal diagnostic or replace a malformed one.
--@param value any Error returned by a native terminal method.
--@param operation string Native method name for fallback context.
--@return table err Structured terminal diagnostic.
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

-- Invoke one native terminal method under exception and status containment.
--@param native table Native terminal port.
--@param method string Selected native method name.
--@param ... any Arguments forwarded to the method in order.
--@return boolean ok True only for a native true status.
--@return any value Native result or structured failure.
--@effect Invokes native terminal state or input operations.
local function call_native(native, method, ...)
    local called, ok, value = pcall(native[method], ...)
    if not called then
        return false, failure("NativeFailure", "native terminal call raised an exception")
    end
    if ok == true then return true, value end
    if ok == false then return false, typed_native_error(value, method) end
    return false, failure("NativeContract", "native terminal returned an invalid status")
end

-- Raise a typed terminal diagnostic at the chosen public caller frame.
--@param native_error table Diagnostic with code and message.
--@param level integer|nil Caller-frame offset; defaults to one.
--@return nil Does not return normally.
--@error Always raises the formatted terminal failure.
local function raise_native(native_error, level)
    error(native_error.code .. ": " .. native_error.message, (level or 1) + 1)
end

-- Admit one native action or terminal outcome without source provenance.
--@param observation any Candidate native observation record.
--@param maximum_input_bytes integer Maximum text bytes in one action.
--@return table|nil admitted Original validated observation.
--@return table|nil err Structured action, text, or outcome contract failure.
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
--@param native table Native terminal implementation.
--@param options table Terminal mode request and fixed input byte cap.
--@return table|nil port AsyncPort with an additional restore method.
--@return table|nil err Structured construction failure.
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
    local pending_batch = {}
    local pending_batch_index = 1
    local pending_text = false
    local pending_text_offset = 1
    local skip_leading_lf = false
    local port = {}

    -- Validate and copy one bounded native observation batch before projection.
    --@param observations table Candidate dense native observation sequence.
    --@param budget integer Maximum observation count for this poll.
    --@return table|nil copied Independent ordered action/terminal records.
    --@return table|nil err Structured shape, budget, or event failure.
    local function copy_observations(observations, budget)
        local event_count = 0
        for key in pairs(observations) do
            if math.type(key) ~= "integer" or key < 1 then
                return nil, failure("NativeContract", "native terminal poll returned a map")
            end
            event_count = event_count + 1
        end
        if event_count > budget then
            return nil, failure("NativeContract", "native terminal exceeded poll budget")
        end
        local copied = {}
        local terminal_seen = false
        for index = 1, event_count do
            local observation, observation_error = validate_observation(
                observations[index],
                maximum_input_bytes
            )
            if not observation then return nil, observation_error end
            if terminal_seen then
                return nil, failure("NativeContract", "terminal emitted data after terminal")
            end
            copied[index] = observation.kind == "terminal" and {
                kind = "terminal",
                outcome = observation.outcome,
            } or {
                kind = "action",
                intent = observation.intent,
                text = observation.text,
            }
            terminal_seen = observation.kind == "terminal"
        end
        return copied
    end

    -- Begin splitting a native text action while folding a prior CRLF boundary.
    --@param value string Exact native text action bytes.
    --@return nil No result; pending text cursor is reset.
    --@effect Replaces pending_text and may skip one leading LF after a prior CR.
    local function begin_pending_text(value)
        pending_text = value
        pending_text_offset = 1
        if skip_leading_lf then
            if value:sub(1, 1) == "\n" then pending_text_offset = 2 end
            skip_leading_lf = false
        end
    end

    -- Extract one text, submit, or cancel event from a buffered text action.
    --@param none Uses the captured pending text and CRLF state.
    --@return table|nil event Next semantic user_action, or nil when exhausted.
    --@effect Advances the pending text cursor and CRLF fold flag.
    local function next_pending_text_event()
        while pending_text do
            if pending_text_offset > #pending_text then
                pending_text = false
                pending_text_offset = 1
                return nil
            end
            local start = pending_text_offset
            while pending_text_offset <= #pending_text do
                local byte = pending_text:byte(pending_text_offset)
                local lone_escape = byte == 0x1B
                    and pending_text_offset == #pending_text
                if byte == 0x0D or byte == 0x0A or lone_escape then break end
                pending_text_offset = pending_text_offset + 1
            end
            if pending_text_offset > start then
                return {
                    kind = "user_action",
                    action = "text",
                    text = pending_text:sub(start, pending_text_offset - 1),
                }
            end
            local byte = pending_text:byte(pending_text_offset)
            if byte == 0x1B then
                pending_text_offset = pending_text_offset + 1
                return { kind = "user_action", action = "cancel" }
            end
            pending_text_offset = pending_text_offset + 1
            if byte == 0x0D then
                if pending_text:sub(pending_text_offset, pending_text_offset) == "\n" then
                    pending_text_offset = pending_text_offset + 1
                elseif pending_text_offset > #pending_text then
                    skip_leading_lf = true
                end
            end
            return { kind = "user_action", action = "submit-or-queue" }
        end
        return nil
    end

    -- Project buffered native observations into at most budget semantic events.
    --@param events table Mutable event prefix from the current poll.
    --@param budget integer Maximum total returned event count.
    --@return table events Same sequence after pending observations are drained.
    --@effect Advances pending text/batch state and records terminal_outcome.
    local function drain_pending(events, budget)
        while #events < budget do
            local text_event = next_pending_text_event()
            if text_event then
                events[#events + 1] = text_event
            else
                local observation = pending_batch[pending_batch_index]
                if not observation then
                    pending_batch = {}
                    pending_batch_index = 1
                    break
                end
                pending_batch_index = pending_batch_index + 1
                if observation.kind == "action" and observation.intent == "text" then
                    begin_pending_text(observation.text)
                else
                    skip_leading_lf = false
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
            end
        end
        return events
    end

    ---Starts terminal input without claiming unsupported key combinations.
    --@param self table Terminal AsyncPort owning the captured lifecycle state.
    --@param now integer Current monotonic tick.
    --@return boolean started True after native mode admission.
    --@error Raises for invalid state/time or native start failure.
    --@effect Starts native terminal input and takes ownership of its handle.
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
    --@param self table Started terminal AsyncPort.
    --@param now integer Current monotonic tick.
    --@param budget integer Maximum returned observations.
    --@return table events AsyncPort event array.
    --@error Raises for invalid state/arguments or native observation contract failure.
    --@effect Polls native input and advances buffered text/terminal state.
    function port:poll(now, budget)
        if state ~= "started" then error("terminal port is " .. state, 2) end
        if terminal_outcome then return {} end
        if not valid_integer(now, 0) or not valid_integer(budget, 0)
            or budget > maximum_input_bytes
        then
            error("terminal poll arguments are invalid", 2)
        end
        local events = drain_pending({}, budget)
        if #events == budget or budget == 0 or terminal_outcome then return events end
        local remaining = budget - #events
        local ok, observations = call_native(
            native,
            "terminal_poll",
            handle,
            now,
            remaining
        )
        if not ok then raise_native(observations, 1) end
        if type(observations) ~= "table" then
            raise_native(failure("NativeContract", "native terminal poll returned no array"), 1)
        end
        local copied, copy_error = copy_observations(observations, remaining)
        if not copied then raise_native(copy_error, 1) end
        pending_batch = copied
        pending_batch_index = 1
        return drain_pending(events, budget)
    end

    ---Requests input cancellation without fabricating a terminal outcome.
    --@param self table Started terminal AsyncPort.
    --@param now integer Current monotonic tick.
    --@return boolean accepted Whether the native request was admitted.
    --@error Raises for invalid state/time or native cancellation failure.
    --@effect Requests native input cancellation.
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
    --@param self table Started terminal AsyncPort.
    --@param deadline integer|nil Absolute monotonic deadline.
    --@return table result Table containing the terminal outcome.
    --@error Raises for invalid state/deadline or native contract failure.
    --@effect Waits for the terminal and transitions the port to joined.
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
    --@param self table Terminal AsyncPort before close.
    --@return boolean restored True after native restoration succeeds.
    --@error Raises for a closed port or native restoration failure.
    --@effect Attempts native terminal mode restoration once until successful.
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
    --@param self table Started or joined terminal AsyncPort.
    --@return boolean closed True after both operations succeed.
    --@error Raises for invalid state or either native restore/close failure.
    --@effect Attempts restoration, closes the handle, and marks state closed.
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

local EDITOR_MODES = { native = true, raw = true, cooked = true }
local SUBMISSION_INTENTS = {
    ["submit-or-queue"] = true,
    steer = true,
    ask = true,
}

-- Admit a bounded strict UTF-8 draft without NUL bytes.
--@param value any Candidate draft bytes.
--@param maximum_bytes integer Inclusive draft byte cap.
--@return string|nil draft Exact admitted bytes.
--@return table|nil err Structured type, limit, or text failure.
local function valid_draft(value, maximum_bytes)
    if type(value) ~= "string" then
        return nil, failure("InvalidDraft", "line-editor draft must be a byte string")
    end
    if #value > maximum_bytes then
        return nil, failure("DraftLimit", "line-editor draft exceeds its byte limit")
    end
    local carrier, carrier_error = text.text(value)
    if not carrier then
        return nil, failure("InvalidDraft", "line-editor draft must be strict NUL-free UTF-8", {
            reason = carrier_error.code,
        })
    end
    return value
end

-- Create a located failure for malformed streamed terminal input.
--@param reason string Machine-readable UTF-8 rejection reason.
--@param offset integer One-based offset in the current joined input bytes.
--@return table err New InvalidDraft diagnostic.
local function invalid_stream_utf8(reason, offset)
    return failure("InvalidDraft", "terminal input must be strict NUL-free UTF-8", {
        reason = reason,
        offset = offset,
    })
end

-- Validates every complete scalar and separates only a syntactically possible
-- trailing partial scalar. POSIX reads may split UTF-8 at any byte boundary;
-- incomplete bytes must never enter the canonical draft or its display form.
--@param value string Buffered previous suffix followed by the new input bytes.
--@return string|nil complete Prefix containing only complete valid scalars.
--@return string|table suffix_or_err Possible trailing partial scalar, or structured failure.
local function split_stream_utf8(value)
    local index = 1
    while index <= #value do
        local first = value:byte(index)
        if first == 0 then
            return nil, invalid_stream_utf8("nul", index)
        end
        if first <= 0x7F then
            index = index + 1
        else
            local width
            local second_min, second_max = 0x80, 0xBF
            if first >= 0xC2 and first <= 0xDF then
                width = 2
            elseif first >= 0xE0 and first <= 0xEF then
                width = 3
                if first == 0xE0 then second_min = 0xA0 end
                if first == 0xED then second_max = 0x9F end
            elseif first >= 0xF0 and first <= 0xF4 then
                width = 4
                if first == 0xF0 then second_min = 0x90 end
                if first == 0xF4 then second_max = 0x8F end
            elseif first >= 0x80 and first <= 0xBF then
                return nil, invalid_stream_utf8("isolated-continuation", index)
            elseif first == 0xC0 or first == 0xC1 then
                return nil, invalid_stream_utf8("overlong", index)
            else
                return nil, invalid_stream_utf8("invalid-leading-byte", index)
            end

            local available = #value - index + 1
            local inspected = math.min(available, width)
            for relative = 2, inspected do
                local byte = value:byte(index + relative - 1)
                local minimum = relative == 2 and second_min or 0x80
                local maximum = relative == 2 and second_max or 0xBF
                if byte < minimum or byte > maximum then
                    local reason = "invalid-continuation"
                    if relative == 2 and first == 0xE0 and byte < minimum then
                        reason = "overlong"
                    elseif relative == 2 and first == 0xED and byte > maximum then
                        reason = "surrogate"
                    elseif relative == 2 and first == 0xF0 and byte < minimum then
                        reason = "overlong"
                    elseif relative == 2 and first == 0xF4 and byte > maximum then
                        reason = "above-maximum"
                    end
                    return nil, invalid_stream_utf8(reason, index + relative - 1)
                end
            end
            if available < width then
                return value:sub(1, index - 1), value:sub(index)
            end
            index = index + width
        end
    end
    return value, ""
end

-- Return UTF-8 scalar width from an already validated leading byte.
--@param first integer First byte of a valid UTF-8 scalar.
--@return integer width One through four bytes.
local function scalar_width(first)
    if first <= 0x7F then return 1 end
    if first <= 0xDF then return 2 end
    if first <= 0xEF then return 3 end
    return 4
end

-- Check a zero-based draft byte cursor without splitting a UTF-8 scalar.
--@param value string Admitted strict UTF-8 draft.
--@param cursor any Candidate zero-based byte offset.
--@return boolean boundary Whether the cursor is within and at a scalar boundary.
local function cursor_is_boundary(value, cursor)
    if not valid_integer(cursor, 0) or cursor > #value then return false end
    if cursor == #value then return true end
    local following = value:byte(cursor + 1)
    return following < 0x80 or following > 0xBF
end

-- Find the zero-based boundary before one complete UTF-8 scalar.
--@param value string Admitted strict UTF-8 draft.
--@param cursor integer Current zero-based scalar boundary.
--@return integer previous Previous boundary, or zero at the start.
local function previous_cursor(value, cursor)
    if cursor == 0 then return 0 end
    local byte_index = cursor
    while byte_index > 1 do
        local byte = value:byte(byte_index)
        if byte < 0x80 or byte > 0xBF then break end
        byte_index = byte_index - 1
    end
    return byte_index - 1
end

-- Find the zero-based boundary after one complete UTF-8 scalar.
--@param value string Admitted strict UTF-8 draft.
--@param cursor integer Current zero-based scalar boundary.
--@return integer following Next boundary, or byte length at the end.
local function next_cursor(value, cursor)
    if cursor == #value then return cursor end
    local byte_index = cursor + 2
    while byte_index <= #value do
        local byte = value:byte(byte_index)
        if byte < 0x80 or byte > 0xBF then break end
        byte_index = byte_index + 1
    end
    return byte_index - 1
end

-- Preserve a typed display error or replace a malformed one.
--@param value any Error returned by a terminal display method.
--@param operation string Display method name for fallback context.
--@return table err Structured display diagnostic.
local function typed_display_error(value, operation)
    if type(value) == "table"
        and type(value.code) == "string" and value.code ~= ""
        and type(value.message) == "string" and value.message ~= ""
    then
        return value
    end
    return failure("DisplayFailure", "terminal display failed during " .. operation)
end

-- Call a display method and require complete acceptance of the payload.
--@param display table Terminal display port.
--@param method string Selected display method name.
--@param payload any Draft frame, urgent receipt, or complete output bytes.
--@param byte_count integer|nil Exact byte count accepted as a success result.
--@return boolean|nil accepted True after full display acceptance.
--@return table|nil err Structured exception, partial, or native display failure.
--@effect Calls the display; output may be externally partial on failure.
local function display_call(display, method, payload, byte_count)
    local called, result, display_error = pcall(display[method], display, payload)
    if not called then
        return nil, failure("DisplayFailure", "terminal display raised during " .. method)
    end
    if result == true or (byte_count and result == byte_count) then return true end
    return nil, typed_display_error(display_error, method)
end

-- Admit one owned-draft or cooked editor and its display requirements.
--@param display table Candidate redraw/write display port.
--@param options table Mode, byte caps, prompt callback, and optional initial draft.
--@return table|nil admitted Independent editor configuration.
--@return table|nil err Structured mode, display, draft, cursor, or limit failure.
local function validate_editor_options(display, options)
    if type(display) ~= "table" then
        return nil, failure("InvalidLineEditor", "terminal display port is required")
    end
    if type(options) ~= "table" then
        return nil, failure("InvalidLineEditor", "line-editor options are required")
    end
    local allowed = {
        mode = true,
        maximum_draft_bytes = true,
        maximum_pending_bytes = true,
        maximum_pending_blocks = true,
        initial_draft = true,
        initial_cursor_byte = true,
        render_prompt = true,
        backlog_notice = true,
    }
    for key in pairs(options) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure("InvalidLineEditor", "line-editor options contain an unknown field")
        end
    end
    if not EDITOR_MODES[options.mode] then
        return nil, failure("InvalidLineEditor", "line-editor mode must be native, raw, or cooked")
    end
    if not valid_integer(options.maximum_draft_bytes, 1)
        or not valid_integer(options.maximum_pending_bytes, 1)
        or not valid_integer(options.maximum_pending_blocks, 1)
    then
        return nil, failure("InvalidLineEditor", "line-editor hard limits are required")
    end
    if type(options.render_prompt) ~= "function"
        or type(options.backlog_notice) ~= "string"
        or options.backlog_notice == ""
    then
        return nil, failure("InvalidLineEditor", "prompt and backlog renderers are required")
    end
    if options.mode == "cooked" then
        if type(display.write) ~= "function" or type(display.write_urgent) ~= "function" then
            return nil, failure(
                "InvalidLineEditor",
                "cooked display must provide write and write_urgent"
            )
        end
        if options.initial_draft ~= nil and options.initial_draft ~= "" then
            return nil, failure(
                "InvalidLineEditor",
                "cooked editor cannot claim ownership of a system draft"
            )
        end
        if options.initial_cursor_byte ~= nil and options.initial_cursor_byte ~= 0 then
            return nil, failure(
                "InvalidLineEditor",
                "cooked editor cannot claim ownership of a system cursor"
            )
        end
        return {
            mode = options.mode,
            maximum_draft_bytes = options.maximum_draft_bytes,
            maximum_pending_bytes = options.maximum_pending_bytes,
            maximum_pending_blocks = options.maximum_pending_blocks,
            render_prompt = options.render_prompt,
            backlog_notice = options.backlog_notice,
            initial_draft = false,
            initial_cursor_byte = false,
        }
    end
    if type(display.redraw) ~= "function" then
        return nil, failure("InvalidLineEditor", "owned-draft display must provide atomic redraw")
    end
    local draft, draft_error = valid_draft(
        options.initial_draft or "",
        options.maximum_draft_bytes
    )
    if not draft then return nil, draft_error end
    local cursor = options.initial_cursor_byte
    if cursor == nil then cursor = #draft end
    if not cursor_is_boundary(draft, cursor) then
        return nil, failure("InvalidLineEditor", "initial cursor is not a UTF-8 boundary")
    end
    return {
        mode = options.mode,
        maximum_draft_bytes = options.maximum_draft_bytes,
        maximum_pending_bytes = options.maximum_pending_bytes,
        maximum_pending_blocks = options.maximum_pending_blocks,
        render_prompt = options.render_prompt,
        backlog_notice = options.backlog_notice,
        initial_draft = draft,
        initial_cursor_byte = cursor,
    }
end

---Creates a draft-safe display editor without owning domain action state.
-- Native/raw modes own exact UTF-8 draft bytes. Their display port receives one
-- atomic redraw request containing hide, complete append, and exact redraw
-- facts. Cooked mode never receives or reports the host line-editor draft; it
-- queues complete output blocks and flushes them only at a caller-declared safe
-- line after emitting one bounded backlog receipt.
--@param display table Atomic-redraw or cooked-write display port.
--@param options table Explicit mode, callbacks, draft, and hard limits.
--@return table|nil editor Immutable line-editor facade.
--@return table|nil err Structured construction failure.
function M.new_line_editor(display, options)
    local admitted, options_error = validate_editor_options(display, options)
    if not admitted then return nil, options_error end

    local owns_draft = admitted.mode ~= "cooked"
    local draft = admitted.initial_draft
    local cursor = admitted.initial_cursor_byte
    local generation = 1
    local active_submission
    local pending = {}
    local pending_bytes = 0
    local backlog_visible = false
    local input_active = false
    local shown = false
    local state = "open"
    local display_unknown = false
    local pending_input = ""
    local editor = {}

    -- Render the current prompt through a contained caller callback.
    --@param none Uses the captured prompt callback and current draft.
    --@return string|nil prompt Complete prompt bytes.
    --@return table|nil err Structured callback or result-shape failure.
    --@effect Invokes the injected prompt renderer.
    local function prompt_bytes()
        local called, rendered, render_error = pcall(
            admitted.render_prompt,
            owns_draft and draft or false
        )
        if not called then
            return nil, failure("PromptRenderFailure", "prompt renderer raised an exception")
        end
        if type(rendered) ~= "string" then
            if type(render_error) == "table" then return nil, render_error end
            return nil, failure("PromptRenderFailure", "prompt renderer returned invalid bytes")
        end
        return rendered
    end

    -- Replace an owned draft frame while atomically appending complete output.
    --@param append_bytes string Optional complete output block, empty for edit redraw.
    --@return boolean|nil redrawn True after the display accepts the frame.
    --@return table|nil err Structured prompt or display failure.
    --@effect Calls display.redraw and faults editor state on uncertain output.
    local function atomic_redraw(append_bytes)
        local prompt, prompt_error = prompt_bytes()
        if not prompt then
            state = "faulted"
            return nil, prompt_error
        end
        local frame = {
            kind = "draft-frame",
            mode = admitted.mode,
            hide_draft = shown,
            append_bytes = append_bytes,
            redraw_bytes = prompt,
            draft_bytes = draft,
            cursor_byte = cursor,
            generation = generation,
        }
        local redrawn, redraw_error = display_call(display, "redraw", frame)
        if not redrawn then
            state = "faulted"
            display_unknown = true
            return nil, redraw_error
        end
        shown = true
        input_active = true
        return true
    end

    -- Redraw an already visible owned draft after its bytes or cursor change.
    --@param none Uses current editor visibility and draft state.
    --@return boolean|nil redrawn True when hidden or after successful redraw.
    --@return table|nil err Structured prompt or display failure.
    --@effect May invoke one atomic display redraw.
    local function redraw_after_edit()
        if not shown then return true end
        return atomic_redraw("")
    end

    -- Guard mutations of the owned draft against pending input and submission.
    --@param allow_pending_input boolean|nil Whether a partial UTF-8 suffix is allowed.
    --@return boolean|nil editable True for an open owned draft without conflict.
    --@return table|nil err Structured mode, state, submission, or encoding failure.
    local function require_editable(allow_pending_input)
        if state ~= "open" then
            return nil, failure("EditorClosed", "line editor is " .. state)
        end
        if not owns_draft then
            return nil, failure("DraftNotOwned", "cooked input draft belongs to the host editor")
        end
        if active_submission then
            return nil, failure("SubmissionPending", "draft has an unresolved submission snapshot")
        end
        if pending_input ~= "" and not allow_pending_input then
            return nil, failure(
                "InputEncodingIncomplete",
                "terminal input ends inside a UTF-8 scalar"
            )
        end
        return true
    end

    -- Adopt exact next draft bytes and cursor, then redraw if visible.
    --@param next_draft string Strict UTF-8 replacement draft.
    --@param next_cursor integer Zero-based scalar boundary in next_draft.
    --@return table|nil snapshot Immutable editor facts after successful redraw.
    --@return table|nil err Structured prompt or display failure.
    --@effect Mutates draft/cursor/generation before redraw; redraw failure faults the editor.
    local function commit_draft(next_draft, next_cursor)
        draft = next_draft
        cursor = next_cursor
        generation = generation + 1
        local redrawn, redraw_error = redraw_after_edit()
        if not redrawn then return nil, redraw_error end
        return editor.snapshot()
    end

    ---Shows the initial prompt without inventing terminal control sequences.
    --@param none Uses the captured editor and display.
    --@return boolean|nil shown True after the initial prompt is visible.
    --@return table|nil err Structured editor, renderer, or display failure.
    --@effect Draws the first prompt and marks input active on success.
    function editor.show()
        if state ~= "open" then return nil, failure("EditorClosed", "line editor is " .. state) end
        if shown then return true end
        if owns_draft then return atomic_redraw("") end
        local prompt, prompt_error = prompt_bytes()
        if not prompt then state = "faulted" return nil, prompt_error end
        local written, write_error = display_call(display, "write", prompt, #prompt)
        if not written then
            state = "faulted"
            display_unknown = true
            return nil, write_error
        end
        shown = true
        input_active = true
        return true
    end

    ---Replaces an owned draft at an exact UTF-8 byte boundary.
    --@param value string Strict UTF-8 replacement draft.
    --@param cursor_byte integer|nil Optional zero-based scalar boundary.
    --@return table|nil snapshot Immutable updated editor state.
    --@return table|nil err Structured edit, cursor, or display failure.
    --@effect Commits and may redraw the owned draft.
    function editor.set_draft(value, cursor_byte)
        local editable, editable_error = require_editable()
        if not editable then return nil, editable_error end
        local next_draft, draft_error = valid_draft(value, admitted.maximum_draft_bytes)
        if not next_draft then return nil, draft_error end
        local next_cursor = cursor_byte
        if next_cursor == nil then next_cursor = #next_draft end
        if not cursor_is_boundary(next_draft, next_cursor) then
            return nil, failure("InvalidCursor", "cursor is not a UTF-8 boundary")
        end
        return commit_draft(next_draft, next_cursor)
    end

    ---Inserts exact strict UTF-8 bytes at the owned cursor.
    --@param value string Strict UTF-8 text to insert.
    --@return table|nil snapshot Immutable updated editor state.
    --@return table|nil err Structured edit, size, or display failure.
    --@effect Commits and may redraw the owned draft.
    function editor.insert(value)
        local editable, editable_error = require_editable()
        if not editable then return nil, editable_error end
        local inserted, inserted_error = valid_draft(value, admitted.maximum_draft_bytes)
        if not inserted then return nil, inserted_error end
        if #draft + #inserted > admitted.maximum_draft_bytes then
            return nil, failure("DraftLimit", "line-editor draft exceeds its byte limit")
        end
        local next_draft = draft:sub(1, cursor) .. inserted .. draft:sub(cursor + 1)
        return commit_draft(next_draft, cursor + #inserted)
    end

    ---Deletes the previous Unicode scalar without byte splitting.
    --@param none Uses the captured draft and cursor.
    --@return table|nil snapshot Immutable updated or unchanged editor state.
    --@return table|nil err Structured edit or display failure.
    --@effect May commit and redraw the owned draft.
    function editor.backspace()
        local editable, editable_error = require_editable()
        if not editable then return nil, editable_error end
        if cursor == 0 then return editor.snapshot() end
        local previous = previous_cursor(draft, cursor)
        local next_draft = draft:sub(1, previous) .. draft:sub(cursor + 1)
        return commit_draft(next_draft, previous)
    end

    ---Deletes the following Unicode scalar without byte splitting.
    --@param none Uses the captured draft and cursor.
    --@return table|nil snapshot Immutable updated or unchanged editor state.
    --@return table|nil err Structured edit or display failure.
    --@effect May commit and redraw the owned draft.
    function editor.delete_forward()
        local editable, editable_error = require_editable()
        if not editable then return nil, editable_error end
        if cursor == #draft then return editor.snapshot() end
        local following = next_cursor(draft, cursor)
        local next_draft = draft:sub(1, cursor) .. draft:sub(following + 1)
        return commit_draft(next_draft, cursor)
    end

    ---Moves the owned cursor by scalar or to a draft boundary.
    --@param direction string left, right, home, or end.
    --@return table|nil snapshot Immutable updated or unchanged editor state.
    --@return table|nil err Structured gesture or display failure.
    --@effect Updates the cursor/generation and may redraw the draft.
    function editor.move(direction)
        local editable, editable_error = require_editable()
        if not editable then return nil, editable_error end
        local next_value
        if direction == "left" then
            next_value = previous_cursor(draft, cursor)
        elseif direction == "right" then
            next_value = next_cursor(draft, cursor)
        elseif direction == "home" then
            next_value = 0
        elseif direction == "end" then
            next_value = #draft
        else
            return nil, failure("InvalidGesture", "cursor direction is unsupported")
        end
        if next_value == cursor then return editor.snapshot() end
        cursor = next_value
        generation = generation + 1
        local redrawn, redraw_error = redraw_after_edit()
        if not redrawn then return nil, redraw_error end
        return editor.snapshot()
    end

    ---Creates an immutable submission lease without clearing the draft.
    --@param intent string Registered submission action.
    --@return table|nil submission Immutable draft and generation lease.
    --@return table|nil err Structured editor or intent failure.
    --@effect Records one active submission pending domain resolution.
    function editor.prepare_submission(intent)
        local editable, editable_error = require_editable()
        if not editable then return nil, editable_error end
        if not SUBMISSION_INTENTS[intent] then
            return nil, failure("InvalidInputIntent", "submission intent is unsupported")
        end
        active_submission = {
            generation = generation,
            intent = intent,
            text = draft,
            cursor_byte = cursor,
        }
        return readonly(active_submission, "line-editor submission")
    end

    ---Resolves a submission lease; rejection preserves the exact draft.
    --@param submission_generation integer Exact leased draft generation.
    --@param accepted boolean Whether the domain accepted the submission.
    --@return table|nil snapshot Immutable updated editor state.
    --@return table|nil err Structured stale, result, or display failure.
    --@effect Clears active submission; accepted submissions clear and redraw the draft.
    function editor.resolve_submission(submission_generation, accepted)
        if state ~= "open" then return nil, failure("EditorClosed", "line editor is " .. state) end
        if not active_submission or submission_generation ~= active_submission.generation then
            return nil, failure("SubmissionStale", "submission snapshot is absent or stale")
        end
        if type(accepted) ~= "boolean" then
            return nil, failure("InvalidSubmissionResult", "accepted must be boolean")
        end
        active_submission = nil
        if not accepted then return editor.snapshot() end
        draft, cursor = "", 0
        generation = generation + 1
        local redrawn, redraw_error = redraw_after_edit()
        if not redrawn then return nil, redraw_error end
        return editor.snapshot()
    end

    -- Validate streamed UTF-8, apply text/backspace scalars, and retain a partial suffix.
    --@param bytes string Newly received raw text action bytes.
    --@return table|nil snapshot Immutable updated or unchanged editor state.
    --@return table|nil err Structured encoding, size, editor, or display failure.
    --@effect Updates pending_input and may commit/redraw the owned draft.
    local function consume_text_bytes(bytes)
        local editable, editable_error = require_editable(true)
        if not editable then return nil, editable_error end
        local complete, suffix_or_error = split_stream_utf8(pending_input .. bytes)
        if not complete then return nil, suffix_or_error end
        local suffix = suffix_or_error
        local next_draft, next_cursor = draft, cursor
        local index = 1
        while index <= #complete do
            local first = complete:byte(index)
            if first == 0x08 or first == 0x7F then
                if next_cursor > 0 then
                    local previous = previous_cursor(next_draft, next_cursor)
                    next_draft = next_draft:sub(1, previous)
                        .. next_draft:sub(next_cursor + 1)
                    next_cursor = previous
                end
                index = index + 1
            else
                local width = scalar_width(first)
                if #next_draft + width > admitted.maximum_draft_bytes then
                    return nil, failure(
                        "DraftLimit",
                        "line-editor draft exceeds its byte limit"
                    )
                end
                local scalar = complete:sub(index, index + width - 1)
                next_draft = next_draft:sub(1, next_cursor)
                    .. scalar .. next_draft:sub(next_cursor + 1)
                next_cursor = next_cursor + width
                index = index + width
            end
        end
        if #next_draft + #suffix > admitted.maximum_draft_bytes then
            return nil, failure("DraftLimit", "line-editor draft exceeds its byte limit")
        end
        pending_input = suffix
        if next_draft == draft and next_cursor == cursor then return editor.snapshot() end
        return commit_draft(next_draft, next_cursor)
    end

    ---Consumes a normalized terminal input event without executing an action.
    --@param event table Normalized user_action event with optional text bytes.
    --@return table|nil result Editor snapshot, submission, or cancel intent.
    --@return table|nil err Structured input, mode, encoding, or display failure.
    --@effect Updates owned draft or submission state, never executes the domain action.
    function editor.consume(event)
        if type(event) ~= "table" or event.kind ~= "user_action"
            or type(event.action) ~= "string"
        then
            return nil, failure("InvalidInputEvent", "line editor requires a user_action event")
        end
        if not owns_draft then
            return nil, failure(
                "DraftNotOwned",
                "cooked user input must be delivered by the host line adapter"
            )
        end
        if event.action == "text" then
            if type(event.text) ~= "string" then
                return nil, failure("InvalidInputEvent", "text action omits bytes")
            end
            return consume_text_bytes(event.text)
        end
        if event.text ~= nil then
            return nil, failure("InvalidInputEvent", "non-text input action carries bytes")
        end
        if event.action == "newline" then return editor.insert("\n") end
        if SUBMISSION_INTENTS[event.action] then
            return editor.prepare_submission(event.action)
        end
        if event.action == "cancel" then
            pending_input = ""
            return readonly({ intent = "cancel", generation = generation }, "cancel intent")
        end
        return nil, failure("InvalidInputEvent", "input action is unsupported by the editor")
    end

    ---Publishes one complete rendered block without character interleaving.
    --@param output_bytes string Complete validated semantic block bytes.
    --@return table|nil receipt Immutable queued flag and byte count.
    --@return table|nil err Structured editor, backlog, or display failure.
    --@effect Atomically redraws owned draft or queues/writes cooked output.
    function editor.publish(output_bytes)
        if state ~= "open" then return nil, failure("EditorClosed", "line editor is " .. state) end
        if type(output_bytes) ~= "string" or output_bytes == "" then
            return nil, failure("InvalidRenderedBlock", "rendered block bytes are required")
        end
        if owns_draft then
            local published, publish_error = atomic_redraw(output_bytes)
            if not published then return nil, publish_error end
            return readonly({ queued = false, bytes = #output_bytes }, "published block")
        end
        if not input_active then
            local written, write_error = display_call(
                display,
                "write",
                output_bytes,
                #output_bytes
            )
            if not written then
                state = "faulted"
                display_unknown = true
                return nil, write_error
            end
            return readonly({ queued = false, bytes = #output_bytes }, "published block")
        end
        if #pending >= admitted.maximum_pending_blocks
            or pending_bytes + #output_bytes > admitted.maximum_pending_bytes
        then
            return nil, failure(
                "OutputBacklogLimit",
                "cooked output backlog cannot admit another complete block"
            )
        end
        pending[#pending + 1] = output_bytes
        pending_bytes = pending_bytes + #output_bytes
        if not backlog_visible then
            local request = {
                kind = "urgent-receipt",
                bytes = admitted.backlog_notice,
                preserves_system_draft = true,
            }
            local visible, visible_error = display_call(display, "write_urgent", request)
            if not visible then
                state = "faulted"
                display_unknown = true
                return nil, visible_error
            end
            backlog_visible = true
        end
        return readonly({ queued = true, bytes = #output_bytes }, "queued block")
    end

    ---Flushes every queued cooked block after the caller declares a safe line.
    --@param none Uses the captured cooked editor backlog.
    --@return string|nil bytes Flushed complete blocks, possibly empty.
    --@return table|nil err Structured mode, state, or display failure.
    --@effect Writes and clears the cooked backlog on success.
    function editor.flush_cooked()
        if state ~= "open" then return nil, failure("EditorClosed", "line editor is " .. state) end
        if owns_draft then
            return nil, failure("InvalidEditorMode", "owned-draft editor has no cooked backlog")
        end
        input_active = false
        if #pending == 0 then
            backlog_visible = false
            return ""
        end
        local bytes = table.concat(pending)
        local written, write_error = display_call(display, "write", bytes, #bytes)
        if not written then
            state = "faulted"
            display_unknown = true
            return nil, write_error
        end
        pending = {}
        pending_bytes = 0
        backlog_visible = false
        return bytes
    end

    ---Starts the next cooked input line after a safe flush.
    --@param none Uses the captured cooked editor state.
    --@return boolean|nil resumed True after the prompt is visible or already active.
    --@return table|nil err Structured mode, backlog, or display failure.
    --@effect May write a prompt and mark input active.
    function editor.resume_cooked()
        if state ~= "open" then return nil, failure("EditorClosed", "line editor is " .. state) end
        if owns_draft then
            return nil, failure("InvalidEditorMode", "owned-draft editor does not resume cooked input")
        end
        if input_active then return true end
        if #pending ~= 0 then
            return nil, failure("PendingOutput", "cooked output must be flushed before input resumes")
        end
        local prompt, prompt_error = prompt_bytes()
        if not prompt then state = "faulted" return nil, prompt_error end
        local written, write_error = display_call(display, "write", prompt, #prompt)
        if not written then
            state = "faulted"
            display_unknown = true
            return nil, write_error
        end
        shown = true
        input_active = true
        return true
    end

    ---Returns exact ownership, cursor, and bounded backlog facts.
    --@param none Uses the captured editor state.
    --@return table snapshot Immutable draft ownership and backlog facts.
    function editor.snapshot()
        return readonly({
            state = state,
            mode = admitted.mode,
            draft_owned = owns_draft,
            draft = owns_draft and draft or false,
            cursor_byte = owns_draft and cursor or false,
            generation = owns_draft and generation or false,
            pending_input_bytes = owns_draft and #pending_input or false,
            submission_pending = active_submission ~= nil,
            pending_blocks = #pending,
            pending_bytes = pending_bytes,
            backlog_visible = backlog_visible,
            input_active = input_active,
            display_unknown = display_unknown,
        }, "line-editor snapshot")
    end

    ---Closes only after all cooked output is accounted for.
    --@param none Uses the captured editor state.
    --@return boolean|nil closed True after a clean close or if already closed.
    --@return table|nil err Structured pending output/input or uncertain display failure.
    --@effect Marks an open editor closed after all obligations are settled.
    function editor.close()
        if state == "closed" then return true end
        if state == "faulted" then
            return nil, failure("DisplayFailure", "line editor display state is unknown", {
                display_unknown = display_unknown,
            })
        end
        if #pending ~= 0 then
            return nil, failure("PendingOutput", "line editor cannot discard queued output")
        end
        if active_submission then
            return nil, failure(
                "SubmissionPending",
                "line editor cannot close with an unresolved submission snapshot"
            )
        end
        if pending_input ~= "" then
            return nil, failure(
                "IncompleteInput",
                "line editor cannot close inside a UTF-8 scalar"
            )
        end
        state = "closed"
        return true
    end

    return readonly(editor, "line editor")
end

return M
