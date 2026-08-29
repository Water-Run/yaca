--[[
File: terminal.lua
Date: 2026-08-29
Author: WaterRun
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
    side = true,
    cancel = true,
    text = true,
    eof = true,
}

local function failure(code, message, extra)
    local result = { code = code, message = message }
    for key, value in pairs(extra or {}) do result[key] = value end
    return result
end

local function readonly(values, label)
    return setmetatable({}, {
        __index = values,
        __newindex = function(_, key)
            error((label or "readonly value") .. " cannot be modified: " .. tostring(key), 2)
        end,
        __pairs = function()
            return next, values, nil
        end,
        __metatable = "locked",
    })
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

local EDITOR_MODES = { native = true, raw = true, cooked = true }
local SUBMISSION_INTENTS = {
    ["submit-or-queue"] = true,
    steer = true,
    side = true,
}

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

local function invalid_stream_utf8(reason, offset)
    return failure("InvalidDraft", "terminal input must be strict NUL-free UTF-8", {
        reason = reason,
        offset = offset,
    })
end

-- Validates every complete scalar and separates only a syntactically possible
-- trailing partial scalar. POSIX reads may split UTF-8 at any byte boundary;
-- incomplete bytes must never enter the canonical draft or its display form.
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

local function scalar_width(first)
    if first <= 0x7F then return 1 end
    if first <= 0xDF then return 2 end
    if first <= 0xEF then return 3 end
    return 4
end

local function cursor_is_boundary(value, cursor)
    if not valid_integer(cursor, 0) or cursor > #value then return false end
    if cursor == #value then return true end
    local following = value:byte(cursor + 1)
    return following < 0x80 or following > 0xBF
end

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

local function typed_display_error(value, operation)
    if type(value) == "table"
        and type(value.code) == "string" and value.code ~= ""
        and type(value.message) == "string" and value.message ~= ""
    then
        return value
    end
    return failure("DisplayFailure", "terminal display failed during " .. operation)
end

local function display_call(display, method, payload, byte_count)
    local called, result, display_error = pcall(display[method], display, payload)
    if not called then
        return nil, failure("DisplayFailure", "terminal display raised during " .. method)
    end
    if result == true or (byte_count and result == byte_count) then return true end
    return nil, typed_display_error(display_error, method)
end

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
-- @param display table Atomic-redraw or cooked-write display port.
-- @param options table Explicit mode, callbacks, draft, and hard limits.
-- @return table|nil editor Immutable line-editor facade.
-- @return table|nil err Structured construction failure.
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

    local function redraw_after_edit()
        if not shown then return true end
        return atomic_redraw("")
    end

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

    local function commit_draft(next_draft, next_cursor)
        draft = next_draft
        cursor = next_cursor
        generation = generation + 1
        local redrawn, redraw_error = redraw_after_edit()
        if not redrawn then return nil, redraw_error end
        return editor.snapshot()
    end

    ---Shows the initial prompt without inventing terminal control sequences.
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
    function editor.backspace()
        local editable, editable_error = require_editable()
        if not editable then return nil, editable_error end
        if cursor == 0 then return editor.snapshot() end
        local previous = previous_cursor(draft, cursor)
        local next_draft = draft:sub(1, previous) .. draft:sub(cursor + 1)
        return commit_draft(next_draft, previous)
    end

    ---Deletes the following Unicode scalar without byte splitting.
    function editor.delete_forward()
        local editable, editable_error = require_editable()
        if not editable then return nil, editable_error end
        if cursor == #draft then return editor.snapshot() end
        local following = next_cursor(draft, cursor)
        local next_draft = draft:sub(1, cursor) .. draft:sub(following + 1)
        return commit_draft(next_draft, cursor)
    end

    ---Moves the owned cursor by scalar or to a draft boundary.
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
