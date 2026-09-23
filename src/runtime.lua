--[[
Author: WaterRun
Date: 2026-09-23
File: runtime.lua
Description: Owns the bounded single-threaded event pump and runtime primitives.
]]

local M = {}

local REQUIRED_PORT_METHODS = { "start", "poll", "cancel", "join", "close" }
local EVENT_KINDS = {
    user_action = true,
    io_progress = true,
    io_terminal = true,
    timer = true,
    durable_barrier = true,
}
local TERMINAL_OUTCOMES = {
    completed = true,
    cancelled = true,
    failed = true,
    unknown = true,
}
local EVENT_PRIORITY = {
    io_terminal = 1,
    durable_barrier = 1,
    user_action = 2,
    timer = 3,
    io_progress = 4,
}

local AGENT_STATES = {
    Idle = true,
    Preparing = true,
    RequestingModel = true,
    Streaming = true,
    DispatchingTools = true,
    AwaitingApproval = true,
    ExecutingTool = true,
    EvaluatingAction = true,
    EvaluatingTermination = true,
    WaitingUser = true,
    Finalizing = true,
    Closing = true,
}
local TURN_OUTCOMES = {
    completed = true,
    waiting_user = true,
    refused = true,
    cancelled = true,
    budget_exhausted = true,
    stuck = true,
    partial = true,
    error = true,
    unknown_side_effect = true,
}
local RUNTIME_ABORT_OUTCOMES = {
    cancelled = true,
    budget_exhausted = true,
    stuck = true,
    partial = true,
    error = true,
    unknown_side_effect = true,
}
local CONTROL_NAMES = { finish = true, ["ask-user"] = true, refuse = true }
local SESSION_OVERRIDE_NAMES = {
    CurrentModel = true,
    CurrentPermission = true,
    DoubleCheckOverride = true,
    DoubleCheckGoalOverride = true,
    ContextPrompt = true,
}
local TOOL_RESULT_KINDS = {
    ["real-success"] = "ok",
    ["real-failed"] = "error",
    ["real-cancelled"] = "cancelled",
    unknown = "unknown",
    ["synthetic-denied"] = "skipped",
    ["synthetic-rejected"] = "skipped",
    ["synthetic-review-denied"] = "skipped",
    ["synthetic-admission-error"] = "error",
    ["skipped-after-failure"] = "skipped",
    ["skipped-after-unknown"] = "skipped",
    ["skipped-by-cancel"] = "skipped",
    ["skipped-by-steer"] = "skipped",
    ["skipped-budget-exhausted"] = "skipped",
    ["skipped-stuck-escape"] = "skipped",
}
local SIDE_EFFECTING_TOOLS = {
    write = true, patch = true, rename = true, delete = true, exec = true, lua = true,
}
local PAUSED_AGENT_STATES = {
    Idle = true,
    WaitingUser = true,
    AwaitingApproval = true,
    Closing = true,
}
local AGENT_TRANSITIONS = {
    Idle = { Preparing = true, Closing = true },
    Preparing = {
        RequestingModel = true, WaitingUser = true,
        Finalizing = true, Closing = true,
    },
    RequestingModel = {
        Streaming = true, Preparing = true, Finalizing = true, Closing = true,
    },
    Streaming = {
        Preparing = true, DispatchingTools = true, WaitingUser = true,
        EvaluatingTermination = true, Finalizing = true, Closing = true,
    },
    DispatchingTools = {
        AwaitingApproval = true, ExecutingTool = true, EvaluatingAction = true,
        Preparing = true, RequestingModel = true, Finalizing = true, Closing = true,
    },
    AwaitingApproval = {
        ExecutingTool = true, DispatchingTools = true, WaitingUser = true,
        Preparing = true, Finalizing = true, Closing = true,
    },
    ExecutingTool = {
        DispatchingTools = true, RequestingModel = true,
        Preparing = true, Finalizing = true, Closing = true,
    },
    EvaluatingAction = {
        AwaitingApproval = true, ExecutingTool = true,
        DispatchingTools = true, WaitingUser = true,
        Preparing = true, Finalizing = true, Closing = true,
    },
    EvaluatingTermination = {
        Preparing = true, RequestingModel = true, WaitingUser = true,
        Finalizing = true, Closing = true,
    },
    WaitingUser = {
        Preparing = true, RequestingModel = true,
        AwaitingApproval = true, EvaluatingAction = true,
        EvaluatingTermination = true, Finalizing = true, Closing = true,
    },
    Finalizing = { Idle = true, Closing = true },
    Closing = {},
}

---Checks whether a value is an integer at or above a hard lower bound.
--@param value any Candidate integer.
--@param minimum integer Inclusive lower bound.
--@return boolean valid Whether the value satisfies the bound.
local function integer_at_least(value, minimum)
    return math.type(value) == "integer" and value >= minimum
end

-- Construct a structured diagnostic without throwing or formatting its optional fields.
--@param code string Stable diagnostic code used by callers to choose recovery behavior.
--@param message string Human-readable summary supplied by the failing operation.
--@param detail any|nil Optional underlying cause or contextual diagnostic data; retained as supplied.
--@return table New diagnostic record; optional non-nil fields are retained without deep copying.
local function failure(code, message, detail)
    local result = { code = code, message = message }
    if detail ~= nil then result.detail = detail end
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
    --@field __len function Reports the backing table sequence length.
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
        -- Forward sequence-length queries to the backing table.
        --@param none The proxy operand supplied by Lua is ignored.
        --@return integer Length of the backing sequence under the Lua length operator.
        __len = function()
            return #values
        end,
        __metatable = "locked",
    })
end

---Copies nested runtime state into read-only proxies while rejecting cycles.
--@param value any Value to freeze.
--@param visiting table|nil Ancestor set for recursive calls.
--@param label string|nil Read-only proxy diagnostic label.
--@return any|nil frozen Read-only copy, or nil for a cyclic table.
local function freeze(value, visiting, label)
    if type(value) ~= "table" then return value end
    visiting = visiting or {}
    if visiting[value] then return nil end
    visiting[value] = true
    local copy = {}
    for key, item in pairs(value) do
        local frozen = freeze(item, visiting, label)
        if frozen == nil and type(item) == "table" then
            visiting[value] = nil
            return nil
        end
        copy[key] = frozen
    end
    visiting[value] = nil
    return readonly(copy, label)
end

-- Copy the contiguous array prefix while retaining element references.
--@param values table|nil Sequence copied with ipairs; nil is treated as empty.
--@return table New sequence containing the original element values through the first hole.
--@ownership Copies the outer table only; nested objects retain their original owners.
local function copy_array(values)
    local result = {}
    for index, value in ipairs(values or {}) do result[index] = value end
    return result
end

-- Count a dense one-based array while rejecting holes and extra key kinds.
--@param values any Candidate table; every key must belong to the sequence 1 through count.
--@return integer|nil Sequence length, including zero for an empty table; nil for an invalid shape.
local function dense_count(values)
    if type(values) ~= "table" then return nil end
    local count = 0
    for key in pairs(values) do
        if math.type(key) ~= "integer" or key < 1 then return nil end
        count = count + 1
    end
    for index = 1, count do if values[index] == nil then return nil end end
    return count
end

---Rejects unknown or non-string keys in a typed runtime record.
--@param value any Candidate record.
--@param allowed table Set of admitted string field names.
--@return boolean exact Whether every field belongs to the allowed set.
local function exact_fields(value, allowed)
    if type(value) ~= "table" then return false end
    for key in pairs(value) do
        if type(key) ~= "string" or not allowed[key] then return false end
    end
    return true
end

---Checks bounded NUL-free runtime text and the empty-string policy.
--@param value any Candidate text.
--@param maximum integer Maximum encoded byte length.
--@param empty boolean Whether empty text is allowed.
--@return boolean valid Whether the text meets runtime bounds.
local function valid_runtime_text(value, maximum, empty)
    return type(value) == "string"
        and (empty or value ~= "")
        and #value <= maximum
        and not value:find("\0", 1, true)
end

---Checks a bounded canonical runtime identifier.
--@param value any Candidate identifier.
--@param maximum integer Maximum encoded byte length.
--@return boolean valid Whether the identifier is accepted.
local function valid_runtime_id(value, maximum)
    return valid_runtime_text(value, maximum, false)
        and value:match("^[A-Za-z0-9][A-Za-z0-9._:-]*$") ~= nil
end

---Formats an event-pump callback failure with its Lua stack.
--@param message any Thrown callback value.
--@return string trace Failure text with caller stack.
local function traceback(message)
    return debug.traceback(tostring(message), 2)
end

---Validates a port event and binds its source to the registered port.
--@param port_id string Registered AsyncPort identifier.
--@param event table Candidate event emitted by that port.
--@return table event Validated shallow copy with canonical source.
--@error Raises for malformed, spoofed, or contradictory port events.
local function validate_event(port_id, event)
    if type(event) ~= "table" then error("AsyncPort " .. port_id .. " emitted a non-table event", 3) end
    if event.source ~= nil and event.source ~= port_id then error("AsyncPort " .. port_id .. " spoofed event source", 3) end
    if not EVENT_KINDS[event.kind] then error("AsyncPort " .. port_id .. " emitted unknown event kind " .. tostring(event.kind), 3) end
    if (event.kind == "io_progress" or event.kind == "timer") and (type(event.key) ~= "string" or event.key == "") then
        error("AsyncPort " .. port_id .. " emitted coalescible event without key", 3)
    end
    if event.kind == "io_terminal" and not TERMINAL_OUTCOMES[event.outcome] then
        error("AsyncPort " .. port_id .. " emitted invalid terminal outcome " .. tostring(event.outcome), 3)
    end
    local copy = {}
    for key, value in pairs(event) do copy[key] = value end
    copy.source = port_id
    return copy
end

---Initializes a bounded priority event queue and admission counters.
--@param capacity integer Maximum queued event count.
--@return table queue Mutable queue owned by its pump.
local function new_queue(capacity)
    return {
        capacity = capacity,
        items = {},
        peak = 0,
        coalesced = 0,
        rejected_user_actions = 0,
    }
end

---Builds a collision-free source/kind/key identity for coalescible events.
--@param event table Progress or timer event with source and key.
--@return string key Composite queue identity.
local function event_key(event)
    return event.source .. "\0" .. event.kind .. "\0" .. event.key
end

---Evicts the oldest progress event to admit a non-droppable event.
--@param queue table Mutable bounded event queue.
--@return boolean removed Whether a progress event was evicted.
local function remove_first_progress(queue)
    for index, event in ipairs(queue.items) do
        if event.kind == "io_progress" then
            table.remove(queue.items, index)
            queue.coalesced = queue.coalesced + 1
            return true
        end
    end
    return false
end

---Admits an event, coalescing progress or refusing low-priority overflow.
--@param queue table Mutable bounded event queue.
--@param event table Validated port event.
--@return boolean accepted Whether the event entered or replaced a queue slot.
--@return string|nil reason Coalesced, rejected, or drain-required reason.
local function queue_push(queue, event)
    if event.kind == "io_progress" or event.kind == "timer" then
        local key = event_key(event)
        for index, queued in ipairs(queue.items) do
            if (queued.kind == "io_progress" or queued.kind == "timer") and event_key(queued) == key then
                queue.items[index] = event
                queue.coalesced = queue.coalesced + 1
                return true
            end
        end
    end

    if #queue.items == queue.capacity then
        if event.kind == "io_progress" then
            queue.coalesced = queue.coalesced + 1
            return false, "coalesced"
        end
        if event.kind == "user_action" then
            queue.rejected_user_actions = queue.rejected_user_actions + 1
            return false, "user-action-rejected"
        end
        if not remove_first_progress(queue) then return false, "drain-required" end
    end

    queue.items[#queue.items + 1] = event
    if #queue.items > queue.peak then queue.peak = #queue.items end
    return true
end

---Removes the highest-priority pending event, preserving ties by arrival.
--@param queue table Mutable bounded event queue.
--@return table|nil event Next event or nil when empty.
local function queue_pop(queue)
    local selected_index, selected_priority
    for index, event in ipairs(queue.items) do
        local priority = EVENT_PRIORITY[event.kind]
        if not selected_priority or priority < selected_priority then
            selected_index, selected_priority = index, priority
        end
    end
    if not selected_index then return nil end
    return table.remove(queue.items, selected_index)
end

---Creates a bounded, single-threaded AsyncPort event pump.
--@param options table Queue capacity, poll budget, and reducer callback.
--@return table|nil pump Event-pump instance when options are valid.
--@return string|nil err Configuration error when construction fails.
function M.new_event_pump(options)
    options = options or {}
    local capacity = options.capacity
    local per_port_budget = options.per_port_budget
    local on_event = options.on_event
    if not integer_at_least(capacity, 1) then return nil, "event queue capacity must be a positive integer" end
    if not integer_at_least(per_port_budget, 1) or per_port_budget > capacity then
        return nil, "per-port poll budget must be a positive integer no larger than capacity"
    end
    if type(on_event) ~= "function" then return nil, "event reducer callback is required" end

    local queue = new_queue(capacity)
    local ports, port_by_id = {}, {}
    local terminal_seen = {}
    local lifecycle = "created"
    local current_now, last_now
    local inside_tick, inside_dispatch = false, false
    local dispatched, forced_dispatches, cancel_requests = 0, 0, 0
    local pump = {}

    ---Requires the pump to be in one exact lifecycle state.
    --@param expected string Required lifecycle state.
    --@return nil Returns only while the state matches.
    --@error Raises on a lifecycle mismatch.
    local function require_lifecycle(expected)
        if lifecycle ~= expected then error("event pump lifecycle is " .. lifecycle .. ", expected " .. expected, 3) end
    end

    ---Forwards reducer-admitted cancellation to one unfinished AsyncPort.
    --@param port_id string Registered port identifier.
    --@return boolean cancelled Port cancellation acknowledgement.
    --@error Raises outside dispatch or on port contract failure.
    local function cancel_port(port_id)
        if not inside_dispatch then error("port cancellation must be admitted by the event reducer", 3) end
        local registration = port_by_id[port_id]
        if not registration then error("unknown AsyncPort " .. tostring(port_id), 3) end
        if terminal_seen[port_id] then return false end
        cancel_requests = cancel_requests + 1
        local ok, result = pcall(registration.port.cancel, registration.port, current_now)
        if not ok then error("AsyncPort " .. port_id .. " cancel failed: " .. tostring(result), 3) end
        return result
    end

    local reducer_context_values = {
        cancel = cancel_port,
        -- Expose the current pump tick to the reducer without probing the clock again.
        --@param none No arguments; reads the tick already captured by the pump.
        --@return integer|nil Current tick, or nil before the first clock observation.
        now = function() return current_now end,
    }
    --@metatable reducer_context Read-only reducer access to admitted cancellation and the current pump tick.
    --@field __index table Captured cancel and now functions; their state remains owned by the pump.
    --@field __newindex function Rejects ordinary writes to the reducer facade.
    --@field __metatable string Fixed locked marker hiding the actual metatable.
    local reducer_context = setmetatable({}, {
        __index = reducer_context_values,
        -- Reject attempts to alter the reducer's admitted control surface.
        --@param _ table Reducer facade receiving the write; its contents are not consulted.
        --@param key any Attempted field name included in the diagnostic.
        --@return nil Does not return normally.
        --@error Always raises a reducer-context mutation error at the caller frame.
        __newindex = function(_, key)
            error("event reducer context cannot be modified: " .. tostring(key), 2)
        end,
        __metatable = "locked",
    })

    ---Dispatches one queued event through the reducer with guarded state.
    --@param none No arguments.
    --@return boolean dispatched Whether an event was available and delivered.
    local function dispatch_one()
        local event = queue_pop(queue)
        if not event then return false end
        inside_dispatch = true
        ---Invokes the reducer with its read-only cancellation context.
        --@param none No callback arguments; captures the selected event.
        --@return nil Reducer side effects are handled by the enclosing pump.
        local ok, dispatch_error = xpcall(function() on_event(event, reducer_context) end, traceback)
        inside_dispatch = false
        if not ok then error("event reducer failed: " .. tostring(dispatch_error), 3) end
        dispatched = dispatched + 1
        return true
    end

    ---Admits a non-droppable event by dispatching queued work if necessary.
    --@param event table Validated event to enqueue.
    --@return boolean accepted Whether the event entered the queue.
    --@return string|nil reason Coalesced or rejected reason when applicable.
    local function enqueue(event)
        while true do
            local accepted, reason = queue_push(queue, event)
            if accepted or reason == "coalesced" or reason == "user-action-rejected" then return accepted, reason end
            if reason ~= "drain-required" or not dispatch_one() then error("non-droppable event could not obtain bounded queue capacity", 3) end
            forced_dispatches = forced_dispatches + 1
        end
    end

    ---Registers one five-method AsyncPort before the pump starts.
    --@param self table Event pump instance.
    --@param port_id string Stable event source identifier.
    --@param port table AsyncPort implementation.
    --@return boolean registered True when registration succeeds.
    function pump:register(port_id, port)
        require_lifecycle("created")
        if type(port_id) ~= "string" or port_id == "" or port_id:find("\0", 1, true) then error("AsyncPort id must be a nonempty NUL-free string", 2) end
        if port_by_id[port_id] then error("duplicate AsyncPort " .. port_id, 2) end
        if type(port) ~= "table" then error("AsyncPort " .. port_id .. " must be a table", 2) end
        for _, method in ipairs(REQUIRED_PORT_METHODS) do
            if type(port[method]) ~= "function" then error("AsyncPort " .. port_id .. " omits " .. method, 2) end
        end
        local registration = { id = port_id, port = port }
        ports[#ports + 1] = registration
        port_by_id[port_id] = registration
        return true
    end

    ---Starts all registered ports in registration order.
    --@param self table Event pump instance.
    --@param now integer Current monotonic tick.
    --@return boolean started True after every port starts.
    function pump:start(now)
        require_lifecycle("created")
        if not integer_at_least(now, 0) then error("event pump time must be a nonnegative integer", 2) end
        current_now, last_now = now, now
        local started = {}
        for _, registration in ipairs(ports) do
            local ok, result = pcall(registration.port.start, registration.port, now)
            if not ok or result == false then
                for index = #started, 1, -1 do pcall(started[index].port.close, started[index].port) end
                lifecycle = "closed"
                error("AsyncPort " .. registration.id .. " start failed: " .. tostring(result), 2)
            end
            started[#started + 1] = registration
        end
        lifecycle = "started"
        return true
    end

    ---Polls each live port once and dispatches a bounded number of events.
    --@param self table Event pump instance.
    --@param now integer Current monotonic tick.
    --@param dispatch_budget integer|nil Maximum normal dispatches this tick.
    --@return integer consumed Number of normally dispatched events.
    function pump:tick(now, dispatch_budget)
        require_lifecycle("started")
        if inside_tick then error("event pump tick is not reentrant", 2) end
        if not integer_at_least(now, 0) or now < last_now then error("event pump time must be monotonic", 2) end
        dispatch_budget = dispatch_budget == nil and capacity or dispatch_budget
        if not integer_at_least(dispatch_budget, 0) then error("dispatch budget must be a nonnegative integer", 2) end
        inside_tick, current_now, last_now = true, now, now
        ---Polls ports, validates their events, and drains the dispatch budget.
        --@param none No arguments; captures the current tick and budget.
        --@return integer consumed Number of normally dispatched events.
        local ok, result = xpcall(function()
            for _, registration in ipairs(ports) do
                if not terminal_seen[registration.id] then
                    local poll_ok, events = pcall(registration.port.poll, registration.port, now, per_port_budget)
                    if not poll_ok then error("AsyncPort " .. registration.id .. " poll failed: " .. tostring(events), 0) end
                    if type(events) ~= "table" then error("AsyncPort " .. registration.id .. " poll must return an event array", 0) end
                    local event_count = 0
                    for key in pairs(events) do
                        if math.type(key) ~= "integer" or key < 1 then error("AsyncPort " .. registration.id .. " poll returned a non-array event key", 0) end
                        event_count = event_count + 1
                    end
                    for index = 1, event_count do
                        if events[index] == nil then error("AsyncPort " .. registration.id .. " poll returned a sparse event array", 0) end
                    end
                    if event_count > per_port_budget then error("AsyncPort " .. registration.id .. " exceeded its per-tick event budget", 0) end
                    for _, raw_event in ipairs(events) do
                        local event = validate_event(registration.id, raw_event)
                        if terminal_seen[registration.id] then
                            if event.kind == "io_terminal" then error("AsyncPort " .. registration.id .. " emitted duplicate terminal event", 0) end
                            error("AsyncPort " .. registration.id .. " emitted an event after its terminal event", 0)
                        end
                        if event.kind == "io_terminal" then
                            local accepted = enqueue(event)
                            if not accepted then error("AsyncPort " .. registration.id .. " terminal event was not admitted", 0) end
                            terminal_seen[registration.id] = event.outcome
                        else
                            enqueue(event)
                        end
                    end
                end
            end
            local consumed = 0
            while consumed < dispatch_budget and dispatch_one() do consumed = consumed + 1 end
            return consumed
        end, traceback)
        inside_tick = false
        if not ok then error(result, 2) end
        return result
    end

    ---Dispatches already queued events without polling ports.
    --@param self table Event pump instance.
    --@param limit integer|nil Maximum events, or nil to empty the queue.
    --@return integer consumed Number of dispatched events.
    function pump:drain(limit)
        require_lifecycle("started")
        if inside_tick then error("event pump drain is not reentrant", 2) end
        if limit ~= nil and not integer_at_least(limit, 0) then error("drain limit must be a nonnegative integer", 2) end
        local consumed = 0
        while (limit == nil or consumed < limit) and dispatch_one() do consumed = consumed + 1 end
        return consumed
    end

    ---Joins every port and validates its terminal outcome.
    --@param self table Event pump instance.
    --@param deadline integer|nil Native-port deadline representation.
    --@return table outcomes Terminal outcome keyed by port identifier.
    function pump:join(deadline)
        require_lifecycle("started")
        local outcomes = {}
        for _, registration in ipairs(ports) do
            local ok, result = pcall(registration.port.join, registration.port, deadline)
            if not ok then error("AsyncPort " .. registration.id .. " join failed: " .. tostring(result), 2) end
            local outcome = type(result) == "table" and result.outcome or result
            if not TERMINAL_OUTCOMES[outcome] then error("AsyncPort " .. registration.id .. " join returned invalid terminal outcome " .. tostring(outcome), 2) end
            if terminal_seen[registration.id] and terminal_seen[registration.id] ~= outcome then
                error("AsyncPort " .. registration.id .. " join contradicted its terminal event", 2)
            end
            outcomes[registration.id] = outcome
        end
        lifecycle = "joined"
        return outcomes
    end

    ---Closes all ports in reverse registration order.
    --@param self table Event pump instance.
    --@return boolean closed True after all close calls succeed.
    function pump:close()
        if lifecycle ~= "started" and lifecycle ~= "joined" then error("event pump lifecycle is " .. lifecycle .. ", expected started or joined", 2) end
        local first_error
        for index = #ports, 1, -1 do
            local registration = ports[index]
            local ok, close_error = pcall(registration.port.close, registration.port)
            if not ok and not first_error then first_error = "AsyncPort " .. registration.id .. " close failed: " .. tostring(close_error) end
        end
        lifecycle = "closed"
        if first_error then error(first_error, 2) end
        return true
    end

    ---Returns a snapshot of queue, lifecycle, and admission counters.
    --@param self table Event pump instance.
    --@return table stats Mutable snapshot detached from pump state.
    function pump:stats()
        return {
            lifecycle = lifecycle,
            capacity = capacity,
            queued = #queue.items,
            peak = queue.peak,
            coalesced = queue.coalesced,
            rejected_user_actions = queue.rejected_user_actions,
            dispatched = dispatched,
            forced_dispatches = forced_dispatches,
            cancel_requests = cancel_requests,
            registered_ports = #ports,
        }
    end

    return pump
end

local AGENT_HARD_CAP_FIELDS = {
    active_time_ms = true,
    model_requests = true,
    tool_calls = true,
    reviews = true,
    steps = true,
    message_bytes = true,
    result_bytes = true,
}
local STUCK_FIELDS = {
    snapshot_id = true,
    exact_repeat = true,
    same_error = true,
    abab_cycle = true,
    semantic_no_progress = true,
    runtime_maximum = true,
}
local LANE_FIELDS = {
    queue_maximum = true,
    ask_active_time_ms = true,
    ask_response_bytes = true,
    ask_snapshot_id = true,
}
local INITIAL_SERIAL_FIELDS = {
    turn = true,
    message = true,
    request = true,
    tool = true,
    operation = true,
    queue = true,
    queue_display = true,
    ask = true,
}

---Validates and snapshots AgentLoop caps, serials, lanes, and stuck thresholds.
--@param options table Candidate runtime options and durable startup waterlines.
--@return table|nil options Normalized immutable-by-convention runtime options.
--@return table|nil err Structured option failure.
local function validate_agent_options(options)
    if type(options) ~= "table" then
        return nil, failure("InvalidAgentOptions", "AgentLoop limits are required")
    end
    if not exact_fields(options, {
        hard_caps = true, stuck = true, initial_sequence = true,
        maximum_identifier_bytes = true, hard_cap_snapshot_id = true,
        initial_context_generation = true, lanes = true,
        automatic_compaction = true, initial_serials = true,
        initial_view_manifest_ref = true,
    }) then
        return nil, failure("InvalidAgentOptions", "AgentLoop options are ambiguous")
    end
    if not exact_fields(options.hard_caps, AGENT_HARD_CAP_FIELDS)
        or not exact_fields(options.stuck, STUCK_FIELDS)
        or not exact_fields(options.lanes, LANE_FIELDS)
        or not exact_fields(options.initial_serials, INITIAL_SERIAL_FIELDS)
        or not integer_at_least(options.initial_sequence, 0)
        or not integer_at_least(options.initial_context_generation, 1)
        or not integer_at_least(options.maximum_identifier_bytes, 16)
        or type(options.automatic_compaction) ~= "boolean"
        or (options.initial_view_manifest_ref ~= false
            and not valid_runtime_text(
                options.initial_view_manifest_ref,
                options.hard_caps.message_bytes,
                false
            ))
        or not valid_runtime_id(
            options.hard_cap_snapshot_id,
            options.maximum_identifier_bytes
        )
    then
        return nil, failure("InvalidAgentOptions", "AgentLoop option shape is invalid")
    end
    for name in pairs(INITIAL_SERIAL_FIELDS) do
        if not integer_at_least(options.initial_serials[name], 0) then
            return nil, failure(
                "InvalidAgentOptions",
                "AgentLoop initial serials must be nonnegative"
            )
        end
    end
    if not integer_at_least(options.lanes.queue_maximum, 1)
        or not integer_at_least(options.lanes.ask_active_time_ms, 1)
        or not integer_at_least(options.lanes.ask_response_bytes, 1)
        or not valid_runtime_id(
            options.lanes.ask_snapshot_id,
            options.maximum_identifier_bytes
        )
    then
        return nil, failure("InvalidAgentOptions", "busy-lane hard caps are invalid")
    end
    for name in pairs(AGENT_HARD_CAP_FIELDS) do
        if not integer_at_least(options.hard_caps[name], 1) then
            return nil, failure("InvalidAgentOptions", "AgentLoop hard caps must be positive")
        end
    end
    local maximum = options.stuck.runtime_maximum
    if not integer_at_least(maximum, 1)
        or not valid_runtime_id(options.stuck.snapshot_id, options.maximum_identifier_bytes)
    then
        return nil, failure("InvalidAgentOptions", "stuck detector snapshot is invalid")
    end
    for _, name in ipairs({
        "exact_repeat", "same_error", "abab_cycle", "semantic_no_progress",
    }) do
        local value = options.stuck[name]
        if not integer_at_least(value, 1) or value > maximum then
            return nil, failure(
                "InvalidAgentOptions",
                "stuck detector thresholds must be bounded and nonzero"
            )
        end
    end
    local copy = {
        hard_caps = {},
        stuck = {},
        initial_sequence = options.initial_sequence,
        initial_context_generation = options.initial_context_generation,
        maximum_identifier_bytes = options.maximum_identifier_bytes,
        hard_cap_snapshot_id = options.hard_cap_snapshot_id,
        automatic_compaction = options.automatic_compaction,
        initial_view_manifest_ref = options.initial_view_manifest_ref,
        initial_serials = {},
        lanes = {},
    }
    for name in pairs(AGENT_HARD_CAP_FIELDS) do copy.hard_caps[name] = options.hard_caps[name] end
    for name in pairs(STUCK_FIELDS) do copy.stuck[name] = options.stuck[name] end
    for name in pairs(LANE_FIELDS) do copy.lanes[name] = options.lanes[name] end
    for name in pairs(INITIAL_SERIAL_FIELDS) do
        copy.initial_serials[name] = options.initial_serials[name]
    end
    local runtime_snapshot = {
        "yaca-runtime-snapshot-v1",
        "hard=" .. copy.hard_cap_snapshot_id,
    }
    for _, name in ipairs({
        "active_time_ms", "model_requests", "tool_calls", "reviews", "steps",
        "message_bytes", "result_bytes",
    }) do
        runtime_snapshot[#runtime_snapshot + 1] = name .. "=" .. tostring(copy.hard_caps[name])
    end
    runtime_snapshot[#runtime_snapshot + 1] = "stuck=" .. copy.stuck.snapshot_id
    for _, name in ipairs({
        "exact_repeat", "same_error", "abab_cycle", "semantic_no_progress",
        "runtime_maximum",
    }) do
        runtime_snapshot[#runtime_snapshot + 1] = name .. "=" .. tostring(copy.stuck[name])
    end
    runtime_snapshot[#runtime_snapshot + 1] = "lanes=" .. copy.lanes.ask_snapshot_id
    for _, name in ipairs({
        "queue_maximum", "ask_active_time_ms", "ask_response_bytes",
    }) do
        runtime_snapshot[#runtime_snapshot + 1] = name .. "=" .. tostring(copy.lanes[name])
    end
    runtime_snapshot[#runtime_snapshot + 1] = "automatic_compaction="
        .. tostring(copy.automatic_compaction)
    copy.runtime_snapshot = table.concat(runtime_snapshot, ";")
    if #copy.runtime_snapshot > copy.hard_caps.message_bytes then
        return nil, failure(
            "InvalidAgentOptions",
            "canonical Runtime snapshot exceeds the message hard cap"
        )
    end
    return copy
end

---Checks each required AgentLoop I/O port and optional lane contract.
--@param ports table Candidate clock, journal, Model, Tool, review, and view ports.
--@return table|nil ports Admitted port record.
--@return table|nil err Structured missing-port failure.
local function validate_agent_ports(ports)
    if type(ports) ~= "table" or not exact_fields(ports, {
        clock = true, journal = true, model = true, tools = true, reviews = true,
        snapshots = true, ask = true, views = true,
    }) then
        return nil, failure("InvalidAgentPorts", "AgentLoop ports are required and unambiguous")
    end
    if type(ports.clock) ~= "table" or type(ports.clock.now) ~= "function"
        or type(ports.journal) ~= "table" or type(ports.journal.commit) ~= "function"
        or type(ports.model) ~= "table"
        or type(ports.model.start) ~= "function"
        or type(ports.model.cancel) ~= "function"
        or type(ports.tools) ~= "table"
        or type(ports.tools.admit) ~= "function"
        or type(ports.tools.start) ~= "function"
        or type(ports.tools.cancel) ~= "function"
        or (ports.reviews ~= false and (
            type(ports.reviews) ~= "table"
            or type(ports.reviews.start) ~= "function"
            or type(ports.reviews.cancel) ~= "function"
        ))
        or (ports.snapshots ~= false and (
            type(ports.snapshots) ~= "table"
            or type(ports.snapshots.capture) ~= "function"
        ))
        or (ports.ask ~= false and (
            type(ports.ask) ~= "table"
            or type(ports.ask.start) ~= "function"
            or type(ports.ask.cancel) ~= "function"
        ))
        or (ports.views ~= false and (
            type(ports.views) ~= "table"
            or type(ports.views.prepare) ~= "function"
        ))
    then
        return nil, failure("InvalidAgentPorts", "AgentLoop port contract is incomplete")
    end
    return ports
end

---Validates a main-turn input and its frozen configuration snapshots.
--@param input table Candidate user message and selection snapshots.
--@param limits table Admitted runtime hard caps and identifier bounds.
--@return table|nil admitted Detached input record.
--@return table|nil err Structured turn-input failure.
local function validate_turn_input(input, limits)
    local allowed = {
        text = true, source = true, config_generation = true,
        model_snapshot = true, permission_snapshot = true,
        prompt_snapshot = true, tool_registry_snapshot = true,
        view_manifest_ref = true, double_check = true,
        context_generation = true,
        model_request_limit = true, tool_call_limit = true, queue_limit = true,
    }
    if not exact_fields(input, allowed)
        or not valid_runtime_text(input.text, limits.hard_caps.message_bytes, false)
        or not valid_runtime_id(input.source, limits.maximum_identifier_bytes)
        or not valid_runtime_id(input.config_generation, limits.maximum_identifier_bytes)
        or not valid_runtime_text(input.model_snapshot, limits.hard_caps.message_bytes, false)
        or not valid_runtime_text(input.permission_snapshot, limits.hard_caps.message_bytes, false)
        or not valid_runtime_text(input.prompt_snapshot, limits.hard_caps.message_bytes, false)
        or not valid_runtime_text(input.tool_registry_snapshot, limits.hard_caps.message_bytes, false)
        or not valid_runtime_text(input.view_manifest_ref, limits.hard_caps.message_bytes, false)
        or type(input.double_check) ~= "boolean"
        or not integer_at_least(input.context_generation, 1)
        or not integer_at_least(input.model_request_limit, 1)
        or input.model_request_limit > limits.hard_caps.model_requests
        or not integer_at_least(input.tool_call_limit, 1)
        or input.tool_call_limit > limits.hard_caps.tool_calls
        or not integer_at_least(input.queue_limit, 1)
        or input.queue_limit > limits.lanes.queue_maximum
    then
        return nil, failure("InvalidTurnInput", "main input or its frozen snapshot is invalid")
    end
    local admitted = {}
    for key, value in pairs(input) do admitted[key] = value end
    return admitted
end

---Checks typed finish, ask-user, or refuse Model control payloads.
--@param control table Candidate normalized Model control envelope.
--@param maximum integer Maximum payload text bytes.
--@return boolean|nil valid True when the envelope is coherent.
--@return string|nil reason Invalid envelope or payload class.
local function validate_control(control, maximum)
    if not exact_fields(control, { control = true, payload = true })
        or not CONTROL_NAMES[control.control]
        or type(control.payload) ~= "table"
    then
        return nil, "control-envelope"
    end
    if control.control == "finish" then
        if not exact_fields(control.payload, { summary = true })
            or (control.payload.summary ~= nil
                and not valid_runtime_text(control.payload.summary, maximum, true))
        then return nil, "finish-payload" end
    elseif control.control == "ask-user" then
        if not exact_fields(control.payload, { question = true })
            or not valid_runtime_text(control.payload.question, maximum, false)
        then return nil, "ask-user-payload" end
    elseif control.control == "refuse" then
        if not exact_fields(control.payload, { reason = true })
            or not valid_runtime_text(control.payload.reason, maximum, false)
        then return nil, "refuse-payload" end
    end
    return true
end

---Checks a canonical Model response and executable tool-call batch.
--@param wrapper table Canonical response, digest, progress identity, and normalized body.
--@param limits table Runtime hard caps and identifier bounds.
--@return table|nil response Validated original response wrapper.
--@return table|nil err Structured shape or contradiction failure.
local function validate_model_response(wrapper, limits)
    if not exact_fields(wrapper, {
        request_id = true, canonical_body = true, canonical_digest = true,
        progress_identity = true, normalized = true,
    })
        or not valid_runtime_id(wrapper.request_id, limits.maximum_identifier_bytes)
        or not valid_runtime_text(wrapper.canonical_body, limits.hard_caps.message_bytes, true)
        or not valid_runtime_text(wrapper.canonical_digest, limits.hard_caps.message_bytes, false)
        or not valid_runtime_text(wrapper.progress_identity, limits.hard_caps.message_bytes, false)
    then
        return nil, failure("InvalidModelResponse", "canonical response wrapper is invalid")
    end
    local response = wrapper.normalized
    if not exact_fields(response, {
        content_blocks = true, tool_calls = true, finish_class = true,
        incomplete = true, tool_calls_validated = true,
        execution_admitted = true, control = true, usage = true,
        incomplete_reason = true,
    })
        or dense_count(response.content_blocks) == nil
        or dense_count(response.tool_calls) == nil
        or type(response.finish_class) ~= "string"
        or type(response.incomplete) ~= "boolean"
        or type(response.tool_calls_validated) ~= "boolean"
        or response.execution_admitted ~= false
    then
        return nil, failure("InvalidModelResponse", "normalized response shape is invalid")
    end
    if response.incomplete_reason ~= nil
        and not valid_runtime_text(response.incomplete_reason, limits.hard_caps.message_bytes, false)
    then
        return nil, failure("InvalidModelResponse", "response failure identity is invalid")
    end
    if response.control ~= nil then
        local valid, reason = validate_control(response.control, limits.hard_caps.message_bytes)
        if not valid then
            return nil, failure("InvalidModelControl", "typed control is malformed", reason)
        end
    end
    local provider_ids = {}
    for _, call in ipairs(response.tool_calls) do
        if not exact_fields(call, {
            local_tool_call_id = true, name = true, canonical_arguments = true,
            provider_tool_call_id = true,
        })
            or not valid_runtime_text(call.local_tool_call_id, limits.hard_caps.message_bytes, false)
            or not valid_runtime_id(call.name, limits.maximum_identifier_bytes)
            or not valid_runtime_text(call.canonical_arguments, limits.hard_caps.message_bytes, false)
            or not valid_runtime_text(call.provider_tool_call_id, limits.hard_caps.message_bytes, true)
            or provider_ids[call.local_tool_call_id]
        then
            return nil, failure("InvalidModelResponse", "tool call batch is invalid")
        end
        provider_ids[call.local_tool_call_id] = true
    end
    if response.incomplete and (#response.tool_calls > 0 or response.control ~= nil)
        or (#response.tool_calls > 0 and (
            response.control ~= nil
            or response.tool_calls_validated ~= true
            or response.finish_class ~= "tool_calls"
        ))
        or (response.control ~= nil and #response.tool_calls > 0)
    then
        return nil, failure("InvalidModelResponse", "response completion facts contradict")
    end
    return wrapper
end

---Checks a canonical Tool outcome and its byte/effect evidence.
--@param result table Candidate normalized Tool result.
--@param limits table Runtime result and identifier limits.
--@return table|nil result Validated original Tool result.
--@return table|nil err Structured shape or contradiction failure.
local function validate_tool_result(result, limits)
    if not exact_fields(result, {
        kind = true, body = true, truncated = true, raw_bytes = true,
        digest = true, error_id = true, external_effects_unsettled = true,
        progress_identity = true,
    })
        or not TOOL_RESULT_KINDS[result.kind]
        or not valid_runtime_text(result.body, limits.hard_caps.result_bytes, true)
        or type(result.truncated) ~= "boolean"
        or not integer_at_least(result.raw_bytes, 0)
        or (result.digest ~= false
            and not valid_runtime_text(result.digest, limits.hard_caps.result_bytes, false))
        or (result.error_id ~= false
            and not valid_runtime_id(result.error_id, limits.maximum_identifier_bytes))
        or type(result.external_effects_unsettled) ~= "boolean"
        or (result.progress_identity ~= false
            and not valid_runtime_text(
                result.progress_identity,
                limits.hard_caps.result_bytes,
                false
            ))
    then
        return nil, failure("InvalidToolResult", "canonical tool result is invalid")
    end
    if result.raw_bytes < #result.body
        or (TOOL_RESULT_KINDS[result.kind] == "unknown"
            and result.external_effects_unsettled ~= true)
        or (result.external_effects_unsettled
            and TOOL_RESULT_KINDS[result.kind] ~= "unknown")
    then
        return nil, failure("InvalidToolResult", "tool result evidence contradicts its outcome")
    end
    return result
end

---Builds a bounded local Tool result for an admission or policy refusal.
--@param kind string Canonical synthetic outcome kind.
--@param reason any Refusal reason embedded in bounded text.
--@return table result Normalized Tool result without external effects.
local function synthetic_result(kind, reason)
    local body = "synthetic:" .. kind .. ":" .. tostring(reason or "")
    local raw_bytes = #body
    if #body > 2048 then
        body = body:sub(1, 2048)
        -- Reasons are UTF-8 text; keep the bounded synthetic body valid.
        while utf8.len(body) == nil do body = body:sub(1, -2) end
    end
    return {
        kind = kind,
        body = body,
        truncated = #body < raw_bytes,
        raw_bytes = raw_bytes,
        digest = false,
        error_id = false,
        external_effects_unsettled = false,
        progress_identity = false,
    }
end

---Creates the typed, single-owner AgentLoop state machine.
-- Ports perform only narrow I/O. The loop will not start a Model, reviewer, or
-- tool effect until the causal Context batch receives an exact durable receipt.
--@param ports table Monotonic clock, Context journal, Model, Tool, review ports.
--@param options table Versioned hard-cap and stuck-threshold snapshots.
--@return table|nil loop AgentLoop facade.
--@return table|nil err Structured construction failure.
function M.new_agent_loop(ports, options)
    local admitted_ports, ports_error = validate_agent_ports(ports)
    if not admitted_ports then return nil, ports_error end
    local limits, options_error = validate_agent_options(options)
    if not limits then return nil, options_error end

    local state = "Idle"
    local closing = false
    local halted = false
    local halt_error
    local sequence = limits.initial_sequence
    local context_generation = limits.initial_context_generation
    local barrier_serial = 0
    local turn_serial = limits.initial_serials.turn
    local message_serial = limits.initial_serials.message
    local request_serial = limits.initial_serials.request
    local tool_serial = limits.initial_serials.tool
    local operation_serial = limits.initial_serials.operation
    local last_clock
    local turn
    local last_turn
    local active_request
    local active_review
    local active_tool
    local pending
    local pending_steer
    local queue_items = {}
    local current_queue_limit = limits.lanes.queue_maximum
    local queue_serial = limits.initial_serials.queue
    local queue_display_serial = limits.initial_serials.queue_display
    local ask_serial = limits.initial_serials.ask
    local restored_view_manifest_ref = limits.initial_view_manifest_ref
    local ask
    local ask_history = {}
    local compaction_gate
    local compaction_preflight_serial = 0
    local pending_model_preflight
    local loop = {}
    local request_model
    local start_model_request
    local start_review_request
    local dispatch_next
    local accept_result
    local skip_remaining
    local start_main
    local auto_start_queue
    local inject_steer

    ---Returns the active or most recently completed turn trace.
    --@param none No arguments.
    --@return table|nil trace Current or last turn trace.
    local function current_trace()
        return turn and turn.trace or (last_turn and last_turn.trace)
    end

    ---Returns the active Model-view manifest reference across turn boundaries.
    --@param none No arguments.
    --@return string|false ref Current or restored manifest reference.
    local function current_manifest_ref()
        local current = turn or last_turn
        return current and current.active_view_manifest_ref
            or restored_view_manifest_ref
    end

    ---Advances the AgentLoop only along an admitted state-machine edge.
    --@param next_state string Destination Agent state.
    --@return nil Records the transition in the active trace.
    --@error Raises for an illegal transition.
    local function transition(next_state)
        if not AGENT_STATES[next_state] or not AGENT_TRANSITIONS[state][next_state] then
            error("illegal AgentLoop transition " .. state .. " -> " .. tostring(next_state), 3)
        end
        state = next_state
        if turn then turn.trace.states[#turn.trace.states + 1] = next_state end
    end

    ---Reads a monotonic tick and charges active turn time outside paused states.
    --@param none No arguments.
    --@return integer|nil now Current monotonic tick.
    --@return table|nil err Structured clock failure.
    local function clock_now()
        local called, value = pcall(admitted_ports.clock.now)
        if not called or not integer_at_least(value, 0)
            or (last_clock ~= nil and value < last_clock)
        then
            return nil, failure("MonotonicClockFailure", "AgentLoop monotonic clock failed")
        end
        if turn and last_clock ~= nil and not PAUSED_AGENT_STATES[state] then
            turn.counters.active_time_ms = turn.counters.active_time_ms + value - last_clock
        end
        last_clock = value
        return value
    end

    ---Halts the loop after loss of an exact durable Context barrier.
    --@param reason string Internal barrier failure identity.
    --@param detail any|nil Underlying receipt or port failure.
    --@return nil No new activity is admitted.
    --@return table err Persistent durability failure.
    local function durability_failure(reason, detail)
        halted = true
        halt_error = failure(
            "AgentDurabilityFailure",
            "AgentLoop lost its durable Context barrier",
            detail or reason
        )
        if turn and state == "Idle" then
            -- The first input never crossed admission, so no durable turn
            -- exists to finalize. The process is still fail-stop.
            turn = nil
        elseif turn and state ~= "Finalizing" and state ~= "Closing" then
            transition("Finalizing")
        end
        return nil, halt_error
    end

    ---Commits a sequenced Fact batch and verifies the exact journal receipt.
    --@param events table Dense semantic event batch.
    --@return table|nil receipt Exact durable Context receipt.
    --@return table|nil err Capacity refusal or fail-stop durability error.
    local function commit_events(events)
        if halted then return nil, halt_error end
        local count = dense_count(events)
        if count == nil or count < 1 then
            return durability_failure("invalid-event-batch")
        end
        barrier_serial = barrier_serial + 1
        local barrier_id = (turn and turn.id or "runtime")
            .. ":barrier:" .. tostring(barrier_serial)
        local first_sequence = sequence + 1
        local records = {}
        for index, event in ipairs(events) do
            if not exact_fields(event, { type = true, fields = true, turn_id = true })
                or not valid_runtime_id(event.type, limits.maximum_identifier_bytes)
                or type(event.fields) ~= "table"
            then
                return durability_failure("invalid-event")
            end
            local event_turn_id = event.turn_id
            if event_turn_id == nil then event_turn_id = turn and turn.id or false end
            if event_turn_id ~= false
                and not valid_runtime_id(event_turn_id, limits.maximum_identifier_bytes)
            then
                return durability_failure("invalid-event-turn")
            end
            records[index] = {
                seq = sequence + index,
                type = event.type,
                turn_id = event_turn_id,
                fields = event.fields,
            }
        end
        local batch = freeze({
            barrier_id = barrier_id,
            first_sequence = first_sequence,
            last_sequence = sequence + count,
            event_count = count,
            expected_context_generation = context_generation,
            events = records,
        }, nil, "durable AgentLoop batch")
        if not batch then return durability_failure("cyclic-event") end
        local called, committed, receipt = pcall(admitted_ports.journal.commit, batch)
        if called and committed ~= true and type(receipt) == "table"
            and receipt.code == "ContextCapacity" and receipt.publication_started == false
        then
            return nil, receipt
        end
        if not called or committed ~= true or type(receipt) ~= "table"
            or receipt.barrier_id ~= barrier_id
            or receipt.first_sequence ~= first_sequence
            or receipt.last_sequence ~= sequence + count
            or receipt.event_count ~= count
            or receipt.binding ~= batch
            or not integer_at_least(receipt.previous_context_generation, context_generation)
            or not integer_at_least(
                receipt.context_generation,
                receipt.previous_context_generation + 1
            )
        then
            local detail = called and receipt or committed
            return durability_failure("commit-not-exact", detail)
        end
        sequence = sequence + count
        context_generation = receipt.context_generation
        if turn then
            turn.trace.durable_barriers[#turn.trace.durable_barriers + 1] = barrier_id
        end
        return receipt
    end

    -- A production Tool adapter may cross the operation intent/result barrier
    -- inside tools.start so it can prove intent durability before the actual
    -- side effect. Adopt that exact publication receipt into AgentLoop's local
    -- waterline; no event is replayed and no second Context writer exists.
    --@param receipt table External operation journal receipt.
    --@param expected_count integer Expected number of exact Facts.
    --@param validator function Checks each bound Fact against active call state.
    --@param failure_domain string|nil Domain prefix for fail-stop diagnostics.
    --@return boolean|nil adopted True after local waterline advances.
    --@return table|nil err Persistent durability failure.
    local function adopt_external_receipt(
        receipt,
        expected_count,
        validator,
        failure_domain
    )
        failure_domain = failure_domain or "external-operation"
        if halted then return nil, halt_error end
        local batch = type(receipt) == "table" and receipt.binding or nil
        local event_count = type(batch) == "table" and dense_count(batch.events) or nil
        if type(receipt) ~= "table"
            or type(batch) ~= "table"
            or event_count ~= expected_count
            or receipt.event_count ~= expected_count
            or receipt.barrier_id ~= batch.barrier_id
            or receipt.first_sequence ~= sequence + 1
            or receipt.first_sequence ~= batch.first_sequence
            or receipt.last_sequence ~= sequence + expected_count
            or receipt.last_sequence ~= batch.last_sequence
            or batch.event_count ~= expected_count
            or batch.expected_context_generation ~= context_generation
            or receipt.previous_context_generation ~= context_generation
            or receipt.context_generation ~= context_generation + 1
        then
            return durability_failure(failure_domain .. "-receipt")
        end
        for index, event in ipairs(batch.events) do
            if not exact_fields(event, {
                seq = true, type = true, turn_id = true, fields = true,
            })
                or event.seq ~= sequence + index
                or type(event.type) ~= "string"
                or type(event.fields) ~= "table"
                or not validator(event, index)
            then
                return durability_failure(failure_domain .. "-event")
            end
        end
        sequence = receipt.last_sequence
        context_generation = receipt.context_generation
        if turn then
            turn.trace.durable_barriers[#turn.trace.durable_barriers + 1]
                = receipt.barrier_id
        end
        return true
    end

    ---Adopts a side-effecting Tool's durable intent before execution resumes.
    --@param call table Active Tool call and operation identity.
    --@param receipt table|false|nil Optional exact intent receipt.
    --@return boolean|nil adopted True when no receipt or one exact intent is accepted.
    --@return table|nil err Persistent durability failure.
    local function adopt_operation_intent(call, receipt)
        if receipt == nil or receipt == false then return true end
        if not call.side_effecting then
            return durability_failure("unexpected-operation-intent")
        end
        ---Checks the external intent Fact against the admitted Tool call.
        --@param event table Durable operation-intent Fact.
        --@return boolean matches Whether the Fact binds the active call exactly.
        return adopt_external_receipt(receipt, 1, function(event)
            local fields = event.fields
            return event.type == "operation_intent"
                and event.turn_id == turn.id
                and exact_fields(fields, {
                    operationId = true, toolCallId = true, kind = true,
                    targetIdentity = true, expectedDigest = true,
                })
                and fields.operationId == call.public.operation_id
                and fields.toolCallId == call.id
                and fields.kind == call.public.name
                and valid_runtime_text(
                    fields.targetIdentity,
                    limits.hard_caps.result_bytes,
                    false
                )
                and valid_runtime_text(
                    fields.expectedDigest,
                    limits.hard_caps.result_bytes,
                    false
                )
        end)
    end

    ---Returns the active turn identity used by busy-lane observations.
    --@param none No arguments.
    --@return string|false turn_id Active turn ID or false when idle.
    local function observed_turn_id()
        return turn and turn.id or false
    end

    ---Rejects stale queue, Ask, or steer actions against current Context/turn state.
    --@param candidate table Busy-lane action with observed generation and turn.
    --@return boolean|nil valid True when both observations match.
    --@return table|nil err Structured invalid or stale observation.
    local function validate_lane_observation(candidate)
        if not integer_at_least(candidate.expected_context_generation, 1)
            or (candidate.expected_turn_id ~= false
                and not valid_runtime_id(
                    candidate.expected_turn_id,
                    limits.maximum_identifier_bytes
                ))
        then
            return nil, failure(
                "InvalidLaneObservation",
                "busy-lane action requires an exact Context and turn observation"
            )
        end
        if candidate.expected_context_generation ~= context_generation
            or candidate.expected_turn_id ~= observed_turn_id()
        then
            return nil, failure(
                "StaleLaneObservation",
                "busy-lane action observed stale Context or main-turn state",
                {
                    expected_context_generation = context_generation,
                    expected_turn_id = observed_turn_id(),
                }
            )
        end
        return true
    end

    ---Captures a fresh immutable top-level turn configuration snapshot.
    --@param kind string Main or queued turn kind.
    --@param text_value string Accepted user text.
    --@param source string User input source identity.
    --@param cause string|false|nil Queue or Ask continuation cause.
    --@return table|nil snapshot Validated current-generation snapshot.
    --@return table|nil err Structured port or binding failure.
    local function capture_snapshot(kind, text_value, source, cause)
        if admitted_ports.snapshots == false then
            return nil, failure(
                "SnapshotUnavailable",
                "a fresh top-level turn snapshot cannot be captured"
            )
        end
        local specification = freeze({
            kind = kind,
            text = text_value,
            source = source,
            context_generation = context_generation,
            active_turn_id = observed_turn_id(),
            cause = cause or false,
        }, nil, "turn snapshot request")
        local called, candidate, capture_error = pcall(
            admitted_ports.snapshots.capture,
            specification
        )
        if not called or candidate == nil or candidate == false then
            return nil, failure(
                "SnapshotCaptureFailure",
                "the current immutable turn snapshot could not be captured",
                called and capture_error or candidate
            )
        end
        local snapshot, snapshot_error = validate_turn_input(candidate, limits)
        if not snapshot then return nil, snapshot_error end
        if snapshot.text ~= text_value or snapshot.source ~= source
            or snapshot.context_generation ~= context_generation
        then
            return nil, failure(
                "SnapshotBindingMismatch",
                "captured turn snapshot does not bind the accepted input and Context generation"
            )
        end
        return snapshot
    end

    ---Finds a queued user item by durable item ID.
    --@param queue_item_id string Durable queue item identity.
    --@return integer|nil index One-based queue index.
    --@return table|nil item Matching mutable queue item.
    local function queue_index(queue_item_id)
        for index, item in ipairs(queue_items) do
            if item.id == queue_item_id then return index, item end
        end
        return nil
    end

    ---Resets human display numbering after the durable queue empties.
    --@param none No arguments.
    --@return nil Updates the display serial when the queue is empty.
    local function reset_queue_display_if_empty()
        if #queue_items == 0 then queue_display_serial = 0 end
    end

    ---Projects a queue item into a detached public status record.
    --@param item table Internal queued user item.
    --@return table public_item Public ID, display number, text, and source.
    local function public_queue_item(item)
        return {
            queue_item_id = item.id,
            display_id = item.display_id,
            text = item.text,
            source = item.source,
            ask_id = item.ask_id or false,
        }
    end

    ---Builds the durable Fact for one queue mutation.
    --@param item table Internal queued user item.
    --@param action string Enqueue, edit, reorder, drop, or clear action.
    --@param extra table|nil Optional destination or reason fields.
    --@return table event Semantic queue-item Fact ready for commit.
    local function queue_event(item, action, extra)
        local fields = {
            queueItemId = item.id,
            displayId = item.display_id,
            action = action,
            text = item.text,
        }
        if item.ask_id then fields.askId = item.ask_id end
        if extra then
            if extra.before_queue_item_id then
                fields.beforeQueueItemId = extra.before_queue_item_id
            end
            if extra.reason then fields.reason = extra.reason end
        end
        return { type = "queue_item", fields = fields, turn_id = false }
    end

    ---Marks one terminal outcome and snapshots its final counters and trace.
    --@param outcome string Durable turn terminal outcome.
    --@return table snapshot Final turn identity, counters, trace, and view.
    local function final_snapshot(outcome)
        turn.outcome = outcome
        turn.reported_outcome = outcome
        turn.outcome_durable = true
        turn.trace.outcome = outcome
        return {
            id = turn.id,
            outcome = outcome,
            counters = turn.counters,
            trace = turn.trace,
            active_view_manifest_ref = turn.active_view_manifest_ref,
        }
    end

    ---Commits a unique terminal turn Fact and starts queued work when allowed.
    --@param outcome string Terminal outcome class.
    --@param reason string|nil Bounded human-readable terminal reason.
    --@param error_id string|nil Structured error identity.
    --@return table|nil result Immutable final turn outcome.
    --@return table|nil err Structured validation, capacity, or durability failure.
    local function finalize(outcome, reason, error_id)
        if not TURN_OUTCOMES[outcome] or outcome == "waiting_user" then
            return nil, failure("InvalidTurnOutcome", "turn terminal outcome is invalid")
        end
        if not turn or turn.outcome_durable then
            return nil, failure("TurnAlreadyFinalized", "turn already has its unique outcome")
        end
        if state ~= "Finalizing" then transition("Finalizing") end
        local fields = { outcome = outcome }
        if valid_runtime_text(reason, limits.hard_caps.message_bytes, false) then
            fields.reason = reason
        end
        if error_id ~= nil then
            if not valid_runtime_id(error_id, limits.maximum_identifier_bytes) then
                return nil, failure("InvalidErrorIdentity", "turn error identity is invalid")
            end
            fields.errorId = error_id
        end
        local receipt, commit_error = commit_events({ { type = "turn_ended", fields = fields } })
        if not receipt then return nil, commit_error end
        local snapshot = final_snapshot(outcome)
        active_request, active_review, active_tool, pending = nil, nil, nil, nil
        pending_model_preflight = nil
        pending_steer = nil
        if closing then transition("Closing") else transition("Idle") end
        last_turn = snapshot
        turn = nil
        local result = {
            outcome = outcome,
            turn_id = snapshot.id,
            last_durable_sequence = sequence,
        }
        if outcome == "completed" and not closing and #queue_items > 0 then
            local started, start_error = auto_start_queue()
            if started then
                result.auto_started_queue_item = started.queue_item_id
                result.next_turn_id = started.turn_id
            elseif start_error then
                result.queue_paused_error = start_error.code
            end
            result.last_durable_sequence = sequence
        end
        return assert(freeze(result, nil, "turn outcome"))
    end

    ---Converts a pre-publication capacity refusal into a durable terminal turn.
    --@param error_value table Original event or view preparation failure.
    --@return table|nil result Budget-exhausted turn outcome.
    --@return table|nil err Original or settlement failure.
    local function capacity_exhausted(error_value)
        if not error_value or error_value.code ~= "ContextCapacity" then return nil, error_value end
        if turn.call_cursor <= #turn.calls then
            local skipped, skip_error = skip_remaining("skipped-after-failure", "ContextCapacity")
            if not skipped then return nil, skip_error end
        end
        return finalize("budget_exhausted", "Context capacity exhausted; start a new Context",
            "ContextCapacity")
    end

    ---Finds the first hard-cap limit that would block the next activity.
    --@param prospective string Model or review activity kind.
    --@return string|nil reason Exhausted budget dimension, if any.
    local function budget_reason(prospective)
        if turn.counters.active_time_ms >= limits.hard_caps.active_time_ms then
            return "active-time"
        end
        if prospective == "model" then
            if turn.counters.model_requests >= turn.snapshot.model_request_limit then
                return "model-requests"
            end
            if turn.counters.steps >= limits.hard_caps.steps then return "steps" end
        elseif prospective == "review" then
            if turn.counters.model_requests >= turn.snapshot.model_request_limit then
                return "model-requests"
            end
            if turn.counters.reviews >= limits.hard_caps.reviews then return "reviews" end
            if turn.counters.steps >= limits.hard_caps.steps then return "steps" end
        end
        return nil
    end

    ---Starts an external activity through a guarded port call.
    --@param port table Model, Tool, or review port.
    --@param method string Port method to invoke.
    --@param specification table Immutable activity request.
    --@param label string Failure-domain label.
    --@return any|nil handle Started activity handle.
    --@return table|nil err Structured start failure.
    local function start_effect(port, method, specification, label)
        local called, handle, start_error = pcall(port[method], specification)
        if not called or handle == nil or handle == false then
            return nil, failure(
                label .. "StartFailure",
                label .. " activity could not be started",
                called and start_error or handle
            )
        end
        return handle
    end

    ---Prepares and durably publishes the exact Model view before a request.
    --@param none No arguments.
    --@return string|nil manifest_ref Current published view digest.
    --@return table|nil err Capacity or durability failure.
    local function prepare_model_view()
        if admitted_ports.views == false then return turn.active_view_manifest_ref end
        local observation = freeze({
            expected_context_generation = context_generation,
            expected_last_sequence = sequence,
            current_manifest_ref = turn.active_view_manifest_ref,
        }, nil, "model view observation")
        local called, prepared, prepare_error = pcall(
            admitted_ports.views.prepare,
            observation
        )
        if called and not prepared and type(prepare_error) == "table"
            and prepare_error.code == "ModelViewLimit"
        then
            return nil, { code = "ContextCapacity", publication_started = false,
                message = "Context model view exceeds its byte limit; start a new Context" }
        end
        if not called or not exact_fields(prepared, {
            digest = true,
            first_sequence = true,
            last_sequence = true,
            changed = true,
            replaces_manifest_ref = true,
            compaction_id = true,
            view_context_generation = true,
            binding = true,
        })
            or not valid_runtime_text(
                prepared.digest,
                limits.hard_caps.message_bytes,
                false
            )
            or not integer_at_least(prepared.first_sequence, 0)
            or not integer_at_least(prepared.last_sequence, 0)
            or prepared.first_sequence > prepared.last_sequence
            or (prepared.first_sequence == 0 and prepared.last_sequence ~= 0)
            or type(prepared.changed) ~= "boolean"
            or prepared.replaces_manifest_ref ~= turn.active_view_manifest_ref
            or (prepared.compaction_id ~= nil
                and prepared.compaction_id ~= false
                and not valid_runtime_id(
                    prepared.compaction_id,
                    limits.maximum_identifier_bytes
                ))
            or (prepared.view_context_generation ~= nil
                and not integer_at_least(prepared.view_context_generation, 1))
            or (prepared.compaction_id ~= nil
                and prepared.compaction_id ~= false
                and prepared.view_context_generation == nil)
            or prepared.binding ~= observation
        then
            return durability_failure(
                "model-view-prepare",
                called and (prepare_error or prepared) or "view-prepare-exception"
            )
        end
        if not prepared.changed then
            if prepared.digest ~= turn.active_view_manifest_ref
                or prepared.last_sequence ~= sequence
            then
                return durability_failure("model-view-stale")
            end
            return prepared.digest
        end
        if prepared.digest == turn.active_view_manifest_ref
            or prepared.last_sequence ~= sequence
        then
            return durability_failure("model-view-not-advanced")
        end
        local fields = {
            manifestDigest = prepared.digest,
            firstEventSeq = tostring(prepared.first_sequence),
            lastEventSeq = tostring(prepared.last_sequence),
            replacesManifestDigest = prepared.replaces_manifest_ref,
        }
        if prepared.compaction_id ~= nil and prepared.compaction_id ~= false then
            fields.compactionId = prepared.compaction_id
            fields.viewContextGeneration = tostring(prepared.view_context_generation)
        end
        local receipt, commit_error = commit_events({ {
            type = "model_view_published",
            fields = fields,
        } })
        if not receipt then return nil, commit_error end
        turn.active_view_manifest_ref = prepared.digest
        return prepared.digest
    end

    ---Creates an automatic-compaction preflight for a pending Model request.
    --@param kind string Deferred request kind.
    --@param purpose string Model request purpose.
    --@param payload table|nil Frozen continuation data.
    --@return table|nil admission Immutable preflight admission.
    --@return table|nil err Structured duplicate or invalid binding failure.
    local function defer_model_request(kind, purpose, payload)
        if pending_model_preflight then
            return nil, failure(
                "CompactionPreflightBusy",
                "one Model request already awaits automatic compaction"
            )
        end
        compaction_preflight_serial = compaction_preflight_serial + 1
        local preflight_id = turn.id .. ":compaction-preflight:"
            .. tostring(compaction_preflight_serial)
        local frozen_payload = freeze(payload or false, nil, "deferred Model request")
        if frozen_payload == nil then
            return nil, failure(
                "InvalidCompactionPreflight",
                "deferred Model request binding contains a cycle"
            )
        end
        pending_model_preflight = {
            id = preflight_id,
            kind = kind,
            purpose = purpose,
            payload = frozen_payload,
            settlement = false,
        }
        return readonly({
            state = state,
            request_id = false,
            compaction_preflight_id = preflight_id,
            automatic_compaction = true,
        }, "automatic compaction preflight admission")
    end

    ---Commits a Model request and starts its external activity after view publication.
    --@param purpose string Main, escape, or continuation request purpose.
    --@param continuation table|false|nil Continuation evidence for the Model port.
    --@return table|nil admission Immutable active-request admission or terminal outcome.
    --@return table|nil err Structured capacity, start, or durability failure.
    start_model_request = function(purpose, continuation)
        if compaction_gate then
            return nil, failure(
                "CompactionBusy",
                "a main Model request cannot start while compaction owns the Context lane"
            )
        end
        local reason = budget_reason("model")
        if reason then return finalize("budget_exhausted", reason, "AgentBudgetExhausted") end
        request_serial = request_serial + 1
        local request_id = turn.id .. ":request:" .. tostring(request_serial)
        local view_manifest_ref, view_error = prepare_model_view()
        if not view_manifest_ref then return capacity_exhausted(view_error) end
        local fields = {
            requestId = request_id,
            purpose = purpose,
            viewManifestRef = view_manifest_ref,
        }
        local receipt, commit_error = commit_events({ { type = "model_request", fields = fields } })
        if not receipt then return capacity_exhausted(commit_error) end
        turn.counters.model_requests = turn.counters.model_requests + 1
        turn.counters.steps = turn.counters.steps + 1
        turn.trace.purposes[#turn.trace.purposes + 1] = purpose
        if state ~= "RequestingModel" then transition("RequestingModel") end
        local progress_identity = turn.detector.last_progress ~= false
            and turn.detector.last_progress
            or "turn-baseline:" .. turn.snapshot.view_manifest_ref
        local specification = freeze({
            request_id = request_id,
            turn_id = turn.id,
            purpose = purpose,
            continuation = continuation or false,
            view_manifest_ref = view_manifest_ref,
            progress_identity = progress_identity,
        }, nil, "model request")
        local handle, start_error = start_effect(
            admitted_ports.model,
            "start",
            specification,
            "Model"
        )
        if not handle then return finalize("error", start_error.message, start_error.code) end
        active_request = { id = request_id, handle = handle, purpose = purpose }
        return readonly({ state = state, request_id = request_id }, "model admission")
    end

    ---Checks Model budget and optionally defers admission for compaction preflight.
    --@param purpose string Main or escape request purpose.
    --@param continuation table|false|nil Continuation evidence.
    --@return table|nil admission Model request, preflight, or terminal outcome.
    --@return table|nil err Structured admission failure.
    request_model = function(purpose, continuation)
        local reason = budget_reason("model")
        if reason then return finalize("budget_exhausted", reason, "AgentBudgetExhausted") end
        if limits.automatic_compaction then
            if state ~= "Preparing" then transition("Preparing") end
            return defer_model_request("main", purpose, {
                continuation = continuation or false,
            })
        end
        return start_model_request(purpose, continuation)
    end

    ---Commits and starts one no-tool action or termination review request.
    --@param kind string Action or termination review kind.
    --@param binding table Exact action or finish binding.
    --@return table|nil admission Review request or waiting-user outcome.
    --@return table|nil err Structured capacity, start, or durability failure.
    start_review_request = function(kind, binding)
        if compaction_gate then
            return nil, failure(
                "CompactionBusy",
                "a review Model request cannot start while compaction owns the Context lane"
            )
        end
        if admitted_ports.reviews == false then
            transition("WaitingUser")
            turn.reported_outcome = "waiting_user"
            pending.review_unavailable = true
            return readonly({ state = state, outcome = "waiting_user" }, "review unavailable")
        end
        local reason = budget_reason("review")
        if reason then
            transition("WaitingUser")
            turn.reported_outcome = "waiting_user"
            pending.review_budget_exhausted = true
            return readonly({ state = state, outcome = "waiting_user" }, "review budget")
        end
        request_serial = request_serial + 1
        local request_id = turn.id .. ":request:" .. tostring(request_serial)
        local purpose = kind == "termination" and "termination-review" or "action-review"
        local view_manifest_ref, view_error = prepare_model_view()
        if not view_manifest_ref then return capacity_exhausted(view_error) end
        local receipt, commit_error = commit_events({ {
            type = "model_request",
            fields = {
                requestId = request_id,
                purpose = purpose,
                viewManifestRef = view_manifest_ref,
            },
        } })
        if not receipt then return capacity_exhausted(commit_error) end
        turn.counters.model_requests = turn.counters.model_requests + 1
        turn.counters.reviews = turn.counters.reviews + 1
        turn.counters.steps = turn.counters.steps + 1
        turn.trace.purposes[#turn.trace.purposes + 1] = purpose
        local specification = freeze({
            request_id = request_id,
            turn_id = turn.id,
            purpose = purpose,
            binding = binding,
            model_snapshot = turn.snapshot.model_snapshot,
            config_generation = turn.snapshot.config_generation,
            view_manifest_ref = view_manifest_ref,
            no_tools = true,
        }, nil, "review request")
        local handle, start_error = start_effect(
            admitted_ports.reviews,
            "start",
            specification,
            "Review"
        )
        if not handle then return finalize("error", start_error.message, start_error.code) end
        active_review = { id = request_id, handle = handle, kind = kind, binding = binding }
        return readonly({ state = state, request_id = request_id }, "review admission")
    end

    ---Routes review admission through availability, budget, and compaction checks.
    --@param kind string Action or termination review kind.
    --@param binding table Exact action or finish binding.
    --@return table|nil admission Review, preflight, or waiting-user outcome.
    --@return table|nil err Structured admission failure.
    local function begin_review(kind, binding)
        if admitted_ports.reviews == false then
            transition("WaitingUser")
            turn.reported_outcome = "waiting_user"
            pending.review_unavailable = true
            return readonly({ state = state, outcome = "waiting_user" }, "review unavailable")
        end
        local reason = budget_reason("review")
        if reason then
            transition("WaitingUser")
            turn.reported_outcome = "waiting_user"
            pending.review_budget_exhausted = true
            return readonly({ state = state, outcome = "waiting_user" }, "review budget")
        end
        local purpose = kind == "termination" and "termination-review" or "action-review"
        if limits.automatic_compaction then
            return defer_model_request("review", purpose, {
                review_kind = kind,
                binding = binding,
            })
        end
        return start_review_request(kind, binding)
    end

    ---Tracks repeated actions/errors and emits one durable stuck warning before escape.
    --@param signature string Canonical action or error signature.
    --@param error_signature string|false|nil Error identity when relevant.
    --@param progress_identity string Canonical progress identity.
    --@return string|nil action Continue, escape, or stuck decision.
    --@return string|table|nil detail Trigger identity or structured commit failure.
    local function record_detector(signature, error_signature, progress_identity)
        local detector = turn.detector
        local same = detector.last_signature == signature
        detector.exact_repeat = same and detector.exact_repeat + 1 or 1
        detector.last_signature = signature

        if error_signature then
            detector.same_error = detector.last_error == error_signature
                and detector.same_error + 1 or 1
            detector.last_error = error_signature
        end

        detector.signatures[#detector.signatures + 1] = signature
        if #detector.signatures > 4 then table.remove(detector.signatures, 1) end
        if #detector.signatures == 4
            and detector.signatures[1] == detector.signatures[3]
            and detector.signatures[2] == detector.signatures[4]
            and detector.signatures[1] ~= detector.signatures[2]
        then
            detector.abab_cycle = detector.abab_cycle + 1
        else
            detector.abab_cycle = 0
        end

        detector.semantic_no_progress = detector.last_progress == progress_identity
            and detector.semantic_no_progress + 1 or 1
        detector.last_progress = progress_identity

        local triggered
        for _, row in ipairs({
            { "exact-repeat", detector.exact_repeat, limits.stuck.exact_repeat },
            { "same-error", detector.same_error, limits.stuck.same_error },
            { "abab-cycle", detector.abab_cycle, limits.stuck.abab_cycle },
            {
                "semantic-no-progress",
                detector.semantic_no_progress,
                limits.stuck.semantic_no_progress,
            },
        }) do
            if row[2] >= row[3] then triggered = row[1]; break end
        end
        if not triggered then return "continue" end
        if detector.escape_active then return "stuck", triggered end
        local receipt, commit_error = commit_events({ {
            type = "warning",
            fields = {
                errorId = "AgentStuckWarning",
                summary = "stuck detector threshold reached: " .. triggered,
                causeId = limits.stuck.snapshot_id,
            },
        } })
        if not receipt then return nil, commit_error end
        detector.warning_durable = true
        detector.escape_active = true
        detector.warning_progress = progress_identity
        turn.trace.durable_warning = true
        turn.trace.escape_steps = 1
        detector.exact_repeat = 0
        detector.same_error = 0
        detector.abab_cycle = 0
        detector.semantic_no_progress = 0
        detector.signatures = {}
        return "escape", triggered
    end

    ---Decides whether a post-escape response made semantic progress.
    --@param progress_identity string New canonical progress identity.
    --@return boolean still_stuck Whether the escape remained on the same progress state.
    local function detector_after_escape(progress_identity)
        local detector = turn.detector
        if not detector.escape_active then return false end
        if detector.warning_progress ~= progress_identity then
            detector.escape_active = false
            detector.warning_progress = false
            detector.exact_repeat = 0
            detector.same_error = 0
            detector.abab_cycle = 0
            detector.semantic_no_progress = 0
            detector.signatures = {}
            detector.last_progress = progress_identity
            return false
        end
        return true
    end

    ---Pairs one accepted Tool call with exactly one durable result Fact.
    --@param call table Accepted Tool call state.
    --@param result table Canonical Tool result.
    --@param external_receipt table|false|nil Optional operation/result journal receipt.
    --@return boolean|nil paired True after exact result publication.
    --@return table|nil err Structured duplicate, invalid, or durability failure.
    local function pair_result(call, result, external_receipt)
        if call.result ~= nil then
            return nil, failure("DuplicateToolResult", "accepted tool call already has a result")
        end
        local valid, result_error = validate_tool_result(result, limits)
        if not valid then return nil, result_error end
        local status = TOOL_RESULT_KINDS[result.kind]
        local fields = {
            toolCallId = call.id,
            status = status,
            body = result.body,
            truncated = result.truncated,
            rawBytes = tostring(result.raw_bytes),
        }
        fields.truncated = tostring(result.truncated)
        if result.digest ~= false then fields.digest = result.digest end
        if result.error_id ~= false then fields.errorId = result.error_id end
        if external_receipt ~= nil and external_receipt ~= false then
            if not call.side_effecting then
                return durability_failure("unexpected-operation-result")
            end
            local adopted, adopt_error = adopt_external_receipt(
                external_receipt,
                2,
                ---Checks the two external operation/result Facts against the active Tool call.
                --@param event table Durable operation or Tool result Fact.
                --@param index integer One-based position within the paired receipt.
                --@return boolean matches Whether the Fact exactly binds the Tool outcome.
                function(event, index)
                    local durable = event.fields
                    if event.turn_id ~= turn.id then return false end
                    if index == 1 then
                        return event.type == "operation_result"
                            and exact_fields(durable, {
                                operationId = true, status = true,
                                evidence = true, errorId = true,
                            })
                            and durable.operationId == call.public.operation_id
                            and durable.status == status
                            and valid_runtime_text(
                                durable.evidence,
                                limits.hard_caps.result_bytes,
                                false
                            )
                    end
                    return event.type == "tool_result"
                        and exact_fields(durable, {
                            toolCallId = true, status = true, body = true,
                            truncated = true, rawBytes = true,
                            digest = true, errorId = true,
                        })
                        and durable.toolCallId == call.id
                        and durable.status == status
                        and durable.body == result.body
                        and durable.truncated == tostring(result.truncated)
                        and durable.rawBytes == tostring(result.raw_bytes)
                        and durable.digest == (result.digest ~= false
                            and result.digest or nil)
                        and durable.errorId == (result.error_id ~= false
                            and result.error_id or nil)
                end
            )
            if not adopted then return nil, adopt_error end
        else
            local receipt, commit_error = commit_events({ {
                type = "tool_result",
                fields = fields,
            } })
            if not receipt then return nil, commit_error end
        end
        call.result = result
        turn.trace.tool_results[#turn.trace.tool_results + 1] = {
            tool_call_id = call.id,
            kind = result.kind,
        }
        return true
    end

    ---Publishes synthetic results for every unstarted Tool call in the batch.
    --@param kind string Synthetic skip outcome kind.
    --@param reason string Skip cause recorded in each result.
    --@return boolean|nil skipped True after all remaining calls are settled.
    --@return table|nil err Structured result or durability failure.
    skip_remaining = function(kind, reason)
        for index = turn.call_cursor, #turn.calls do
            local call = turn.calls[index]
            if call.result == nil then
                local paired, pair_error = pair_result(call, synthetic_result(kind, reason))
                if not paired then return nil, pair_error end
            end
        end
        turn.call_cursor = #turn.calls + 1
        return true
    end

    ---Clears active Tool state and requests a follow-up Model response.
    --@param after_failure string|false|nil Failure identity for continuation.
    --@return table|nil admission Next Model request or terminal outcome.
    --@return table|nil err Structured settlement or request failure.
    local function complete_batch(after_failure)
        active_tool, pending = nil, nil
        if after_failure then
            local skipped, skip_error = skip_remaining("skipped-after-failure", after_failure)
            if not skipped then return nil, skip_error end
        end
        return request_model("main", after_failure and { tool_failure = after_failure } or nil)
    end

    ---Injects a durable user steer after any active external activity settles.
    --@param none No arguments.
    --@return table|nil admission New Model request or terminal outcome.
    --@return table|nil err Structured pending-activity or durability failure.
    inject_steer = function()
        if not pending_steer or not turn then
            return nil, failure("NoPendingSteer", "no durable steer awaits injection")
        end
        if active_tool or active_request or active_review then
            return nil, failure("SteerActivityPending", "steer awaits the active activity result")
        end
        if turn.call_cursor <= #turn.calls then
            if state ~= "DispatchingTools" then transition("DispatchingTools") end
            local skipped, skip_error = skip_remaining(
                "skipped-by-steer",
                pending_steer.message_id
            )
            if not skipped then return nil, skip_error end
        end
        local steering = pending_steer
        pending_steer = nil
        pending = nil
        turn.reported_outcome = false
        if state ~= "Preparing" then transition("Preparing") end
        return request_model("main", {
            steer_message_id = steering.message_id,
            ask_id = steering.ask_id or false,
        })
    end

    ---Accepts a Tool outcome, settles remaining calls, and advances the turn.
    --@param result table Canonical Tool result.
    --@param external_receipt table|false|nil Optional paired operation receipt.
    --@return table|nil result Next activity admission or terminal outcome.
    --@return table|nil err Structured result or durability failure.
    accept_result = function(result, external_receipt)
        if state ~= "ExecutingTool" or not active_tool then
            return nil, failure("NoExecutingTool", "no foreground tool awaits a result")
        end
        local call = active_tool.call
        local paired, pair_error = pair_result(call, result, external_receipt)
        if not paired then return nil, pair_error end
        active_tool = nil
        turn.call_cursor = turn.call_cursor + 1
        if pending_steer then
            if turn.call_cursor <= #turn.calls then
                transition("DispatchingTools")
                local skipped, skip_error = skip_remaining(
                    "skipped-by-steer",
                    pending_steer.message_id
                )
                if not skipped then return nil, skip_error end
            end
            return inject_steer()
        end
        local status = TOOL_RESULT_KINDS[result.kind]
        if result.progress_identity ~= false then
            turn.detector.last_progress = result.progress_identity
            turn.detector.semantic_no_progress = 0
            if turn.detector.escape_active
                and turn.detector.warning_progress ~= result.progress_identity
            then
                turn.detector.escape_active = false
                turn.detector.warning_progress = false
            end
        end
        if status == "ok" then
            turn.detector.same_error = 0
            turn.detector.last_error = false
        end
        if status == "unknown" then
            if turn.call_cursor <= #turn.calls then
                transition("DispatchingTools")
                local skipped, skip_error = skip_remaining(
                    "skipped-after-unknown",
                    result.error_id ~= false and result.error_id or "unknown"
                )
                if not skipped then return nil, skip_error end
            end
            return finalize(
                call.side_effecting and "unknown_side_effect" or "error",
                "tool outcome is unknown",
                result.error_id ~= false and result.error_id or "ToolOutcomeUnknown"
            )
        end
        if status == "cancelled" and turn.cancel_pending then
            if turn.call_cursor <= #turn.calls then
                transition("DispatchingTools")
                local skipped, skip_error = skip_remaining("skipped-by-cancel", "turn-cancel")
                if not skipped then return nil, skip_error end
            end
            local outcome = turn.cancel_outcome or "cancelled"
            return finalize(
                outcome,
                turn.cancel_reason or "cancelled",
                outcome == "budget_exhausted" and "AgentBudgetExhausted"
                    or "AgentCancelled"
            )
        end
        if status ~= "ok" then
            if turn.call_cursor <= #turn.calls then transition("DispatchingTools") end
            local error_signature = result.error_id ~= false
                and result.error_id or result.kind
            local progress_identity = result.progress_identity ~= false
                and result.progress_identity
                or turn.detector.last_progress
                or "no-canonical-progress"
            local detector_action, detector_reason = record_detector(
                "tool-error:" .. error_signature,
                error_signature,
                progress_identity
            )
            if not detector_action then return nil, detector_reason end
            if detector_action == "escape" then
                local skipped, skip_error = skip_remaining(
                    "skipped-stuck-escape",
                    detector_reason
                )
                if not skipped then return nil, skip_error end
                return request_model("main", {
                    stuck_escape = true,
                    detector = detector_reason,
                })
            elseif detector_action == "stuck" then
                local skipped, skip_error = skip_remaining(
                    "skipped-stuck-escape",
                    detector_reason
                )
                if not skipped then return nil, skip_error end
                return finalize("stuck", detector_reason, "AgentStuck")
            end
            return complete_batch(result.error_id ~= false and result.error_id or result.kind)
        end
        if turn.call_cursor <= #turn.calls then
            transition("DispatchingTools")
            return dispatch_next()
        end
        return complete_batch(false)
    end

    ---Starts one admitted Tool call and handles immediate or asynchronous results.
    --@param call table Accepted Tool call state.
    --@param admission table Permission and capability decision.
    --@return table|nil activity Active Tool admission or immediate next outcome.
    --@return table|nil err Structured start or durability failure.
    local function start_tool(call, admission)
        transition("ExecutingTool")
        local specification = freeze({
            turn_id = turn.id,
            call = call.public,
            admission = admission,
        }, nil, "tool execution")
        local called, started, start_error = pcall(
            admitted_ports.tools.start,
            specification
        )
        if not called or type(started) ~= "table"
            or (started.kind ~= "complete" and started.kind ~= "async")
        then
            local result_kind = call.side_effecting and "unknown" or "synthetic-admission-error"
            local result = synthetic_result(result_kind, "tool-start-contract")
            if result_kind == "unknown" then
                result.external_effects_unsettled = true
                result.error_id = "ToolStartUnknown"
            else
                result.error_id = "ToolStartFailure"
            end
            active_tool = { call = call, handle = false }
            return accept_result(result)
        end
        local adopted, adoption_error = adopt_operation_intent(
            call,
            started.intent_receipt
        )
        if not adopted then return nil, adoption_error end
        active_tool = { call = call, handle = started.handle or false }
        if started.kind == "complete" then
            if started.result == nil then
                local invalid = synthetic_result(
                    call.side_effecting and "unknown" or "synthetic-admission-error",
                    "missing-tool-result"
                )
                invalid.error_id = call.side_effecting
                    and "ToolResultUnknown" or "InvalidToolResult"
                invalid.external_effects_unsettled = call.side_effecting
                return accept_result(invalid)
            end
            return accept_result(started.result, started.result_receipt)
        end
        if started.handle == nil or started.handle == false then
            local invalid = synthetic_result(
                call.side_effecting and "unknown" or "synthetic-admission-error",
                "missing-tool-handle"
            )
            invalid.error_id = call.side_effecting and "ToolStartUnknown" or "ToolStartFailure"
            invalid.external_effects_unsettled = call.side_effecting
            return accept_result(invalid)
        end
        return readonly({ state = state, tool_call_id = call.id }, "tool activity")
    end

    ---Admits the next unpaired Tool call through permission and review policy.
    --@param none No arguments.
    --@return table|nil activity Tool, approval, review, or next Model admission.
    --@return table|nil err Structured policy or durability failure.
    dispatch_next = function()
        while turn.call_cursor <= #turn.calls do
            local call = turn.calls[turn.call_cursor]
            if call.result ~= nil then
                turn.call_cursor = turn.call_cursor + 1
            else
                local called, admission, admission_error = pcall(
                    admitted_ports.tools.admit,
                    call.public
                )
                if not called or not exact_fields(admission, {
                    decision = true, capabilities = true,
                    permission_snapshot_digest = true, reason = true,
                    token = true, after_review = true,
                })
                    or (admission.decision ~= "allow"
                        and admission.decision ~= "deny"
                        and admission.decision ~= "confirm"
                        and admission.decision ~= "review")
                    or not valid_runtime_text(
                        admission.capabilities,
                        limits.hard_caps.message_bytes,
                        true
                    )
                    or not valid_runtime_text(
                        admission.permission_snapshot_digest,
                        limits.hard_caps.message_bytes,
                        false
                    )
                    or not valid_runtime_text(
                        admission.reason,
                        limits.hard_caps.message_bytes,
                        true
                    )
                    or (admission.after_review ~= false
                        and admission.after_review ~= "allow"
                        and admission.after_review ~= "confirm")
                    or (admission.decision == "review"
                        and admission.after_review == false)
                then
                    local result = synthetic_result(
                        "synthetic-admission-error",
                        called and "invalid-admission" or "admission-raised"
                    )
                    result.error_id = "ToolAdmissionFailure"
                    local paired, pair_error = pair_result(call, result)
                    if not paired then return nil, pair_error end
                    turn.call_cursor = turn.call_cursor + 1
                    local skipped, skip_error = skip_remaining(
                        "skipped-after-failure",
                        "ToolAdmissionFailure"
                    )
                    if not skipped then return nil, skip_error end
                    return finalize("error", "tool admission contract failed", "ToolAdmissionFailure")
                end
                local receipt, commit_error = commit_events({ {
                    type = "permission_decision",
                    fields = {
                        toolCallId = call.id,
                        capabilities = admission.capabilities,
                        -- Review is a Runtime phase, not a Permission verdict.
                        -- Preserve the base capability decision in the XML.
                        decision = admission.decision == "review"
                            and admission.after_review or admission.decision,
                        profileSnapshot = admission.permission_snapshot_digest,
                    },
                } })
                if not receipt then return nil, commit_error end
                call.admission = admission
                if admission.decision == "deny" then
                    local paired, pair_error = pair_result(
                        call,
                        synthetic_result("synthetic-denied", admission.reason)
                    )
                    if not paired then return nil, pair_error end
                    turn.call_cursor = turn.call_cursor + 1
                    return complete_batch("permission-denied")
                elseif admission.decision == "confirm" then
                    pending = { kind = "approval", call = call, admission = admission }
                    transition("AwaitingApproval")
                    return readonly({ state = state, tool_call_id = call.id }, "approval wait")
                elseif admission.decision == "review" then
                    pending = { kind = "action-review", call = call, admission = admission }
                    transition("EvaluatingAction")
                    return begin_review("action", call.public)
                else
                    return start_tool(call, admission)
                end
            end
        end
        return complete_batch(false)
    end

    ---Assigns durable local IDs to a validated Model Tool-call batch.
    --@param response table Canonical validated Model response wrapper.
    --@return table calls Mutable accepted Tool call states.
    --@return table events Durable tool_call Facts for the batch.
    local function register_calls(response)
        local calls = {}
        local events = {}
        for index, candidate in ipairs(response.normalized.tool_calls) do
            tool_serial = tool_serial + 1
            operation_serial = operation_serial + 1
            local id = turn.id .. ":tool:" .. tostring(tool_serial)
            local public = {
                tool_call_id = id,
                operation_id = turn.id .. ":operation:" .. tostring(operation_serial),
                adapter_call_id = candidate.local_tool_call_id,
                provider_call_id = candidate.provider_tool_call_id,
                name = candidate.name,
                canonical_arguments = candidate.canonical_arguments,
                side_effecting = SIDE_EFFECTING_TOOLS[candidate.name] == true,
            }
            local call = {
                id = id,
                public = assert(freeze(public, nil, "accepted tool call")),
                side_effecting = public.side_effecting,
                result = nil,
                admission = nil,
            }
            calls[index] = call
            events[#events + 1] = {
                type = "tool_call",
                fields = {
                    toolCallId = id,
                    requestId = active_request.id,
                    name = candidate.name,
                    canonicalArguments = candidate.canonical_arguments,
                    providerCallId = candidate.provider_tool_call_id,
                },
            }
        end
        return calls, events
    end

    ---Builds Model message, Tool-call, and control/yield Facts atomically.
    --@param wrapper table Canonical Model response wrapper.
    --@param message_id string New durable assistant message identity.
    --@param calls table Accepted Tool call states.
    --@param call_events table Tool-call Facts from registration.
    --@return table events Semantic response Fact batch.
    local function response_events(wrapper, message_id, calls, call_events)
        local normalized = wrapper.normalized
        local events = { {
            type = "model_message",
            fields = {
                messageId = message_id,
                requestId = active_request.id,
                role = "assistant",
                status = normalized.incomplete and "interrupted" or "complete",
                body = wrapper.canonical_body,
                rawBytes = tostring(#wrapper.canonical_body),
                digest = wrapper.canonical_digest,
            },
        } }
        for _, event in ipairs(call_events) do events[#events + 1] = event end
        if normalized.control ~= nil then
            events[#events + 1] = {
                type = "model_control",
                fields = {
                    requestId = active_request.id,
                    control = normalized.control.control,
                    payload = wrapper.canonical_body,
                },
            }
        elseif #calls == 0 and not normalized.incomplete then
            events[#events + 1] = {
                type = "model_yield",
                fields = { requestId = active_request.id, messageId = message_id },
            }
        end
        return events
    end

    ---Applies a typed finish, ask-user, or refuse control after publication.
    --@param control table Validated Model control envelope.
    --@param request_id string Durable Model request identity.
    --@param message_id string Durable assistant message identity.
    --@return table|nil outcome Terminal or waiting/review admission.
    --@return table|nil err Structured review or durability failure.
    local function process_control(control, request_id, message_id)
        turn.trace.controls[#turn.trace.controls + 1] = control.control
        if control.control == "finish" then
            if turn.finish_after_review_gap then
                turn.finish_after_review_gap = false
                return finalize("completed", control.payload.summary or "")
            end
            if turn.snapshot.double_check then
                transition("EvaluatingTermination")
                pending = {
                    kind = "termination-review",
                    request_id = request_id,
                    message_id = message_id,
                }
                return begin_review("termination", {
                    request_id = request_id,
                    message_id = message_id,
                })
            end
            return finalize("completed", control.payload.summary or "")
        elseif control.control == "ask-user" then
            transition("WaitingUser")
            turn.reported_outcome = "waiting_user"
            pending = {
                kind = "ask-user",
                message_id = message_id,
                question = control.payload.question,
            }
            return readonly({
                state = state,
                outcome = "waiting_user",
                question = control.payload.question,
            }, "waiting outcome")
        end
        return finalize("refused", control.payload.reason)
    end

    ---Creates private counters, trace, detector, and view for a main turn.
    --@param snapshot table Captured immutable turn configuration.
    --@param turn_id string New durable turn identity.
    --@return table turn Mutable active AgentLoop turn state.
    local function initialize_main_turn(snapshot, turn_id)
        return {
            id = turn_id,
            snapshot = snapshot,
            counters = {
                active_time_ms = 0,
                model_requests = 0,
                tool_calls = 0,
                reviews = 0,
                steps = 0,
            },
            trace = {
                states = { "Idle" }, purposes = {}, controls = {},
                tool_calls = {}, tool_results = {}, durable_barriers = {},
                durable_warning = false, escape_steps = 0,
                outcome = false,
            },
            calls = {},
            call_cursor = 1,
            detector = {
                snapshot_id = limits.stuck.snapshot_id,
                last_signature = false,
                last_error = false,
                last_progress = false,
                exact_repeat = 0,
                same_error = 0,
                abab_cycle = 0,
                semantic_no_progress = 0,
                signatures = {},
                warning_durable = false,
                escape_active = false,
                warning_progress = false,
            },
            cancel_pending = false,
            cancel_reason = false,
            cancel_outcome = false,
            outcome = false,
            outcome_durable = false,
            reported_outcome = false,
            active_view_manifest_ref = snapshot.view_manifest_ref,
        }
    end

    ---Publishes a new user turn and starts its first Model request.
    --@param input table Captured main-turn input and configuration snapshot.
    --@param cause table|false|nil Queue or Ask continuation cause.
    --@return table|nil admission First Model request or terminal outcome.
    --@return table|nil err Structured stale, capacity, or durability failure.
    start_main = function(input, cause)
        if halted then return nil, halt_error end
        if compaction_gate then
            return nil, failure(
                "CompactionBusy",
                "a main turn cannot start while compaction owns the Context lane"
            )
        end
        if state ~= "Idle" then return nil, failure("AgentBusy", "a main turn is already active") end
        local snapshot, input_error = validate_turn_input(input, limits)
        if not snapshot then return nil, input_error end
        if snapshot.context_generation ~= context_generation then
            return nil, failure(
                "StaleContextObservation",
                "main input observed a different Context generation"
            )
        end
        local now, clock_error = clock_now()
        if not now then return nil, clock_error end
        turn_serial = turn_serial + 1
        message_serial = message_serial + 1
        local turn_id = "turn-" .. tostring(turn_serial)
        local message_id = turn_id .. ":message:" .. tostring(message_serial)
        turn = initialize_main_turn(snapshot, turn_id)
        current_queue_limit = snapshot.queue_limit
        local turn_fields = {
            kind = "main",
            configGeneration = snapshot.config_generation,
            modelSnapshot = snapshot.model_snapshot,
            permissionSnapshot = snapshot.permission_snapshot,
            promptSnapshot = snapshot.prompt_snapshot,
            toolRegistrySnapshot = snapshot.tool_registry_snapshot,
            runtimeSnapshot = limits.runtime_snapshot,
            contextDocumentGeneration = tostring(snapshot.context_generation),
        }
        local events = {}
        if cause and cause.queue_item then
            turn_fields.queueItemId = cause.queue_item.id
            events[#events + 1] = queue_event(cause.queue_item, "consume", {
                reason = "started-as-next-main-turn",
            })
        end
        if cause and cause.continues_response_id then
            turn_fields.continuesResponseId = cause.continues_response_id
        end
        if cause and cause.supersedes_response_id then
            turn_fields.supersedesResponseId = cause.supersedes_response_id
        end
        events[#events + 1] = {
            type = "turn_started",
            turn_id = turn_id,
            fields = turn_fields,
        }
        events[#events + 1] = {
            type = "user_message",
            turn_id = turn_id,
            fields = { messageId = message_id, text = snapshot.text, source = snapshot.source },
        }
        local receipt, commit_error = commit_events(events)
        if not receipt then
            if commit_error and commit_error.code == "ContextCapacity" then turn = nil end
            return nil, commit_error
        end
        if cause and cause.queue_item then
            local index = queue_index(cause.queue_item.id)
            if not index then
                return durability_failure("queue-consume-binding-lost")
            end
            table.remove(queue_items, index)
            reset_queue_display_if_empty()
        end
        transition("Preparing")
        local admitted, request_error = request_model("main", cause and {
            queue_item_id = cause.queue_item and cause.queue_item.id or false,
            continues_response_id = cause.continues_response_id or false,
            supersedes_response_id = cause.supersedes_response_id or false,
        } or nil)
        if not admitted then return nil, request_error end
        return assert(freeze({
            state = admitted.state or state,
            request_id = admitted.request_id or false,
            turn_id = turn_id,
            queue_item_id = cause and cause.queue_item and cause.queue_item.id or false,
        }, nil, "main turn admission"))
    end

    ---Adopts one already-durable Session override and its matching Model-view
    -- publication. The turn snapshot remains immutable; only the Runtime
    -- waterline and the view used by later Model requests advance.
    --@param self table AgentLoop instance.
    --@param record table Session override identity and new view binding.
    --@param receipt table Exact external Context publication receipt.
    --@return table|nil status Adopted Runtime waterline.
    --@return table|nil err Persistent durability or binding failure.
    function loop:adopt_session_override(record, receipt)
        if halted then return nil, halt_error end
        if closing or state == "Closing" or compaction_gate
            or pending_model_preflight ~= nil
        then
            return durability_failure("external-session-override-busy")
        end
        if not exact_fields(record, {
            kind = true,
            name = true,
            old_value_digest = true,
            new_value_digest = true,
            effective_at = true,
            replaces_manifest_digest = true,
            manifest_digest = true,
            compaction_id = true,
            view_context_generation = true,
        })
            or record.kind ~= "session-override"
            or not SESSION_OVERRIDE_NAMES[record.name]
            or not valid_runtime_text(
                record.old_value_digest,
                limits.hard_caps.message_bytes,
                false
            )
            or not valid_runtime_text(
                record.new_value_digest,
                limits.hard_caps.message_bytes,
                false
            )
            or record.old_value_digest == record.new_value_digest
            or record.effective_at ~= "next-turn"
            or not valid_runtime_text(
                record.replaces_manifest_digest,
                limits.hard_caps.message_bytes,
                false
            )
            or record.replaces_manifest_digest ~= current_manifest_ref()
            or not valid_runtime_text(
                record.manifest_digest,
                limits.hard_caps.message_bytes,
                false
            )
            or record.manifest_digest == record.replaces_manifest_digest
            or not integer_at_least(record.view_context_generation, 1)
            or (record.compaction_id ~= false
                and not valid_runtime_id(
                    record.compaction_id,
                    limits.maximum_identifier_bytes
                ))
        then
            return durability_failure("external-session-override-identity")
        end

        local batch = type(receipt) == "table" and receipt.binding or nil
        local first_sequence = type(receipt) == "table"
            and receipt.first_sequence or nil
        ---Matches Session override and Model-view Facts to the external record.
        --@param event table One published Fact.
        --@param index integer One-based position in the external batch.
        --@return boolean matches Whether the Fact is exact for this Session change.
        local function matches(event, index)
            if event.turn_id ~= false then return false end
            local fields = event.fields
            if index == 1 then
                return event.type == "session_override"
                    and exact_fields(fields, {
                        name = true,
                        oldValueDigest = true,
                        newValueDigest = true,
                        effectiveAt = true,
                    })
                    and fields.name == record.name
                    and fields.oldValueDigest == record.old_value_digest
                    and fields.newValueDigest == record.new_value_digest
                    and fields.effectiveAt == record.effective_at
            end
            local expected = {
                manifestDigest = true,
                firstEventSeq = true,
                lastEventSeq = true,
                replacesManifestDigest = true,
            }
            if record.compaction_id ~= false then
                expected.compactionId = true
                expected.viewContextGeneration = true
            end
            return index == 2
                and event.type == "model_view_published"
                and exact_fields(fields, expected)
                and fields.manifestDigest == record.manifest_digest
                and fields.firstEventSeq == "1"
                and fields.lastEventSeq == tostring(first_sequence)
                and fields.replacesManifestDigest
                    == record.replaces_manifest_digest
                and (record.compaction_id == false
                    or (fields.compactionId == record.compaction_id
                        and fields.viewContextGeneration
                            == tostring(record.view_context_generation)))
        end
        local adopted, adoption_error = adopt_external_receipt(
            receipt,
            2,
            matches,
            "external-session-override"
        )
        if not adopted then return nil, adoption_error end
        if type(batch) ~= "table"
            or batch.events[2].fields.manifestDigest ~= record.manifest_digest
        then
            return durability_failure("external-session-override-manifest")
        end
        if turn then
            turn.active_view_manifest_ref = record.manifest_digest
        elseif last_turn then
            last_turn.active_view_manifest_ref = record.manifest_digest
        else
            restored_view_manifest_ref = record.manifest_digest
        end
        return readonly({
            context_generation = context_generation,
            last_sequence = sequence,
            manifest_digest = current_manifest_ref(),
            effective_at = record.effective_at,
        }, "adopted Session override receipt")
    end

    ---Stops admission after the owned Context file fails revalidation.
    -- This never records a new event against the stale file or changes paths.
    --@param self table AgentLoop instance.
    --@return nil No further Agent activity is admitted.
    --@return table err Persistent Context durability failure.
    function loop:fail_context_observation()
        if halted then return nil, halt_error end
        return durability_failure("active-context-stale")
    end

    ---Halts the Runtime when the Session writer returned an ambiguous outcome
    -- or receipt adoption raised after publication may have crossed storage.
    --@param self table AgentLoop instance.
    --@param reason string Stable ambiguity identity.
    --@return nil Runtime remains halted.
    --@return table err Structured fail-stop durability failure.
    function loop:fail_session_override_barrier(reason)
        if halted then return nil, halt_error end
        if not valid_runtime_id(reason, limits.maximum_identifier_bytes) then
            return nil, failure(
                "InvalidSessionBarrierFailure",
                "ambiguous Session barrier reason is invalid"
            )
        end
        return durability_failure("external-session-override-" .. reason)
    end

    ---Opens the exclusive external compaction lane at the exact Runtime
    -- waterline. Journal receipts may advance that waterline only while this
    -- gate is active; ordinary Agent effects remain unavailable until finish.
    --@param self table AgentLoop instance.
    --@param command table Mode, preflight ID, and exact waterline observation.
    --@return table|nil admission Immutable compaction lane admission.
    --@return table|nil err Structured busy or stale-binding failure.
    function loop:begin_compaction(command)
        if halted then return nil, halt_error end
        if not exact_fields(command, {
            mode = true,
            preflight_id = true,
            expected_context_generation = true,
            expected_last_sequence = true,
            expected_manifest_digest = true,
        })
            or (command.mode ~= "manual" and command.mode ~= "automatic")
            or (command.preflight_id ~= false
                and not valid_runtime_id(
                    command.preflight_id,
                    limits.maximum_identifier_bytes
                ))
            or not integer_at_least(command.expected_context_generation, 1)
            or not integer_at_least(command.expected_last_sequence, 0)
            or not valid_runtime_text(
                command.expected_manifest_digest,
                limits.hard_caps.message_bytes,
                false
            )
        then
            return nil, failure(
                "InvalidCompactionAdmission",
                "compaction admission binding is invalid"
            )
        end
        local manual_paused = command.mode == "manual"
            and command.preflight_id == false
            and (state == "Idle" or state == "WaitingUser")
        local automatic_deferred = command.mode == "automatic"
            and pending_model_preflight ~= nil
            and pending_model_preflight.settlement == false
            and command.preflight_id == pending_model_preflight.id
        if compaction_gate
            or (not manual_paused and not automatic_deferred)
            or active_request ~= nil
            or active_review ~= nil
            or active_tool ~= nil
            or ask ~= nil
        then
            return nil, failure(
                command.mode == "manual"
                    and "ManualCompactionBusy" or "CompactionBusy",
                "compaction requires a paused Agent with no active effect"
            )
        end
        if command.expected_context_generation ~= context_generation
            or command.expected_last_sequence ~= sequence
            or command.expected_manifest_digest ~= current_manifest_ref()
        then
            return nil, failure(
                "StaleCompactionAdmission",
                "compaction admission does not bind the Runtime waterline"
            )
        end
        compaction_gate = {
            mode = command.mode,
            preflight_id = command.preflight_id,
            opened_state = state,
            opened_context_generation = context_generation,
            opened_sequence = sequence,
            opened_manifest_digest = command.expected_manifest_digest,
            phase = "opened",
            compaction_id = false,
            request_id = false,
            attempt = 0,
            published_compaction_id = false,
            published_manifest_digest = false,
        }
        return readonly({
            state = state,
            mode = command.mode,
            preflight_id = command.preflight_id,
            context_generation = context_generation,
            last_sequence = sequence,
            manifest_digest = command.expected_manifest_digest,
        }, "Runtime compaction admission")
    end

    ---Adopts one exact Context replacement committed by the compaction
    -- journal. This is the same external-receipt pattern used for Tool
    -- operation intent/result, but only compaction event shapes are admitted.
    --@param self table AgentLoop instance.
    --@param record table Typed compaction journal operation.
    --@param receipt table Exact external Context publication receipt.
    --@return table|nil status Adopted waterline and manifest.
    --@return table|nil err Structured admission or durability failure.
    function loop:adopt_compaction_receipt(record, receipt)
        if halted then return nil, halt_error end
        if not compaction_gate or type(record) ~= "table" then
            return nil, failure(
                "CompactionAdmissionMissing",
                "durable compaction receipt has no active Runtime gate"
            )
        end
        if not valid_runtime_id(
                record.compaction_id,
                limits.maximum_identifier_bytes
            )
            or record.expected_context_generation ~= context_generation
            or record.expected_manifest_digest
                ~= compaction_gate.opened_manifest_digest
            or (compaction_gate.compaction_id ~= false
                and compaction_gate.compaction_id ~= record.compaction_id)
        then
            return durability_failure("external-compaction-identity")
        end
        local phase = compaction_gate.phase
        local next_phase
        if record.kind == "compaction-request" then
            if (phase ~= "opened" and phase ~= "retry")
                or record.mode ~= compaction_gate.mode
                or not valid_runtime_id(
                    record.request_id,
                    limits.maximum_identifier_bytes
                )
                or not integer_at_least(record.attempt, 1)
                or record.attempt ~= compaction_gate.attempt + 1
            then
                return durability_failure("external-compaction-order")
            end
            next_phase = "request"
        elseif record.kind == "compaction-response" then
            if phase ~= "request"
                or record.request_id ~= compaction_gate.request_id
                or record.attempt ~= compaction_gate.attempt
            then
                return durability_failure("external-compaction-order")
            end
            next_phase = "response"
        elseif record.kind == "compaction-rejection" then
            if (phase ~= "request" and phase ~= "response")
                or record.request_id ~= compaction_gate.request_id
                or record.attempt ~= compaction_gate.attempt
                or type(record.terminal) ~= "boolean"
            then
                return durability_failure("external-compaction-order")
            end
            next_phase = record.terminal and "terminal-rejected" or "retry"
        elseif record.kind == "compaction-cancel-request" then
            if phase ~= "request"
                or record.request_id ~= compaction_gate.request_id
            then
                return durability_failure("external-compaction-order")
            end
            next_phase = "cancelling"
        elseif record.kind == "compaction-cancel-result" then
            if phase ~= "cancelling"
                or record.request_id ~= compaction_gate.request_id
                or (record.outcome ~= "cancelled" and record.outcome ~= "unknown")
            then
                return durability_failure("external-compaction-order")
            end
            next_phase = record.outcome == "cancelled"
                and "cancelled" or "cancel-unknown"
        elseif record.kind == "compaction-publication" then
            if phase ~= "response"
                or record.request_id ~= compaction_gate.request_id
                or type(record.manifest) ~= "table"
                or not valid_runtime_text(
                    record.manifest.digest,
                    limits.hard_caps.message_bytes,
                    false
                )
            then
                return durability_failure("external-compaction-order")
            end
            next_phase = "published"
        else
            return durability_failure("external-compaction-kind")
        end
        local batch = type(receipt) == "table" and receipt.binding or nil
        local count = type(batch) == "table" and dense_count(batch.events) or nil
        if not integer_at_least(count, 1) or count > 4 then
            return durability_failure("external-compaction-receipt-count")
        end
        local prior_manifest = current_manifest_ref()
        ---Checks a compaction Fact against the active phase and journal record.
        --@param event table One externally committed Fact.
        --@param index integer One-based Fact position in the batch.
        --@return boolean matches Whether the Fact matches the active compaction.
        local function matches(event, index)
            if event.turn_id ~= nil and event.turn_id ~= false then return false end
            local fields = event.fields
            if type(fields) ~= "table" then return false end
            if record.kind == "compaction-request" then
                return count == 1 and index == 1
                    and event.type == "model_request"
                    and fields.requestId == record.request_id
                    and fields.purpose == "compaction"
                    and fields.viewManifestRef == record.expected_manifest_digest
                    and fields.attemptId == tostring(record.attempt)
                    and fields.compactionId == record.compaction_id
                    and fields.compactionMode == record.mode
                    and fields.sourceFirstSeq == tostring(record.source_first_seq)
                    and fields.sourceLastSeq == tostring(record.source_last_seq)
                    and fields.sourceDigest == record.source_digest
                    and fields.configSnapshot == record.config_snapshot
                    and fields.modelSnapshot == record.model_snapshot_digest
                    and fields.promptSnapshot == record.prompt_bundle_digest
                    and fields.manifestSnapshot == record.manifest_snapshot_id
                    and fields.viewContextGeneration
                        == tostring(record.expected_context_generation)
            end
            if record.kind == "compaction-response" then
                return count == 1 and index == 1
                    and event.type == "model_message"
                    and fields.requestId == record.request_id
                    and fields.status == "complete"
                    and fields.body == record.canonical_body
                    and fields.digest == record.canonical_digest
            end
            if record.kind == "compaction-rejection" then
                if index == 1 then
                    return event.type == "model_message"
                        and fields.requestId == record.request_id
                        and fields.status == "interrupted"
                end
                if index == 2 then
                    return event.type == "warning"
                        and fields.errorId == record.error_code
                        and fields.causeId == record.compaction_id
                end
                return record.terminal == true and index == 3 and count == 3
                    and event.type == "compaction"
                    and fields.compactionId == record.compaction_id
                    and fields.status == "error"
                    and fields.sourceDigest == record.source_digest
                    and fields.requestId == record.request_id
                    and fields.attemptId == tostring(record.attempt)
                    and fields.compactionMode == compaction_gate.mode
                    and fields.automaticFailure
                        == (compaction_gate.mode == "automatic" and "true" or "false")
            end
            if record.kind == "compaction-cancel-request" then
                return count == 1 and index == 1 and event.type == "cancel"
                    and fields.targetKind == "compaction-request"
                    and fields.targetId == record.request_id
                    and fields.reason == record.reason
                    and fields.result == "pending"
            end
            if record.kind == "compaction-cancel-result" then
                if index == 1 then
                    return event.type == "cancel"
                        and fields.targetKind == "compaction-request"
                        and fields.targetId == record.request_id
                        and fields.reason == record.reason
                        and fields.result == record.outcome
                end
                return count == 2 and index == 2 and event.type == "compaction"
                    and fields.compactionId == record.compaction_id
                    and fields.sourceDigest == record.source_digest
                    and fields.status == (record.outcome == "cancelled"
                        and "cancelled" or "error")
                    and fields.requestId == record.request_id
                    and fields.attemptId == tostring(compaction_gate.attempt)
                    and fields.compactionMode == compaction_gate.mode
                    and fields.automaticFailure == (
                        compaction_gate.mode == "automatic"
                            and (record.reason == "compaction-active-time"
                                or record.reason
                                    == "compaction-process-recovery")
                        and "true" or "false"
                    )
            end
            if record.kind == "compaction-publication" then
                if index == 1 then
                    return count == 2 and event.type == "compaction"
                        and fields.compactionId == record.compaction_id
                        and fields.status == "ok"
                        and fields.summaryDigest == record.summary_digest
                        and fields.manifestDigest == record.manifest.digest
                        and fields.requestId == record.request_id
                        and fields.attemptId == tostring(compaction_gate.attempt)
                        and fields.compactionMode == compaction_gate.mode
                        and fields.automaticFailure == "false"
                end
                return index == 2 and event.type == "model_view_published"
                    and fields.compactionId == record.compaction_id
                    and fields.manifestDigest == record.manifest.digest
                    and fields.replacesManifestDigest
                        == record.expected_manifest_digest
            end
            if record.kind == "summary-correction" then
                return count == 1 and index == 1 and event.type == "warning"
                    and fields.errorId == record.correction_id
                    and fields.causeId == record.compaction_id
                    and fields.summary == record.text
            end
            return false
        end
        local adopted, adoption_error = adopt_external_receipt(
            receipt,
            count,
            matches,
            "external-compaction"
        )
        if not adopted then return nil, adoption_error end
        if compaction_gate.compaction_id == false then
            compaction_gate.compaction_id = record.compaction_id
        end
        if record.kind == "compaction-request" then
            compaction_gate.request_id = record.request_id
            compaction_gate.attempt = record.attempt
        end
        compaction_gate.phase = next_phase
        for _, event in ipairs(batch.events) do
            if event.type == "model_view_published" then
                local fields = event.fields
                if compaction_gate.published_compaction_id ~= false
                    or fields.replacesManifestDigest ~= prior_manifest
                    or not valid_runtime_text(
                        fields.manifestDigest,
                        limits.hard_caps.message_bytes,
                        false
                    )
                then
                    return durability_failure("external-compaction-manifest")
                end
                if turn then
                    turn.active_view_manifest_ref = fields.manifestDigest
                elseif last_turn then
                    last_turn.active_view_manifest_ref = fields.manifestDigest
                else
                    restored_view_manifest_ref = fields.manifestDigest
                end
                prior_manifest = fields.manifestDigest
                compaction_gate.published_compaction_id = record.compaction_id
                compaction_gate.published_manifest_digest = fields.manifestDigest
            end
        end
        return readonly({
            context_generation = context_generation,
            last_sequence = sequence,
            manifest_digest = current_manifest_ref(),
        }, "adopted compaction receipt")
    end

    ---Halts the Runtime when the external compaction writer cannot prove whether
    -- its attempted durable barrier was accepted. Continuing would let the
    -- in-memory waterline diverge from Context, so this path is intentionally
    -- fail-stop and cannot be cleared by a normal compaction settlement.
    --@param self table AgentLoop instance.
    --@param reason string Stable compaction ambiguity identity.
    --@return nil Runtime remains halted.
    --@return table err Structured fail-stop durability failure.
    function loop:fail_compaction_barrier(reason)
        if halted then return nil, halt_error end
        if not compaction_gate
            or not valid_runtime_id(reason, limits.maximum_identifier_bytes)
        then
            return nil, failure(
                "CompactionAdmissionMissing",
                "an ambiguous compaction barrier has no active Runtime gate"
            )
        end
        return durability_failure("external-compaction-" .. reason)
    end

    ---Closes the external compaction lane only after its owner proves the
    -- current Runtime waterline and active manifest. No outcome is inferred
    -- from rendered STATUS text.
    --@param self table AgentLoop instance.
    --@param command table Exact compaction settlement and observed waterline.
    --@return table|nil settlement Immutable closed-lane outcome.
    --@return table|nil err Structured mismatch or durability failure.
    function loop:finish_compaction(command)
        if halted then return nil, halt_error end
        local outcomes = {
            completed = true,
            no_op = true,
            fits = true,
            suppressed = true,
            waiting_user = true,
            cancelled = true,
            unknown = true,
        }
        local command_table = type(command) == "table"
        local published = compaction_gate
            and compaction_gate.published_compaction_id ~= false
        local completed_exactly = compaction_gate
            and command_table
            and command.outcome == "completed"
            and published
            and command.compaction_id == compaction_gate.published_compaction_id
            and command.expected_manifest_digest
                == compaction_gate.published_manifest_digest
            and command.expected_manifest_digest
                ~= compaction_gate.opened_manifest_digest
        local retained_exactly = compaction_gate
            and command_table
            and command.outcome ~= "completed"
            and not published
            and command.expected_manifest_digest
                == compaction_gate.opened_manifest_digest
        local phase_exact = compaction_gate and command_table and (
            (command.outcome == "completed"
                and compaction_gate.phase == "published")
            or ((command.outcome == "no_op"
                    or command.outcome == "fits"
                    or command.outcome == "suppressed")
                and compaction_gate.phase == "opened"
                and command.compaction_id == false)
            or (command.outcome == "waiting_user"
                and ((compaction_gate.phase == "opened"
                        and command.compaction_id == false)
                    or (compaction_gate.phase == "terminal-rejected"
                        and command.compaction_id == compaction_gate.compaction_id)))
            or (command.outcome == "cancelled"
                and compaction_gate.phase == "cancelled"
                and command.compaction_id == compaction_gate.compaction_id)
            or (command.outcome == "unknown"
                and ((compaction_gate.phase == "opened"
                        and command.compaction_id == false)
                    or (compaction_gate.phase == "cancel-unknown"
                        and command.compaction_id == compaction_gate.compaction_id)))
        )
        if not compaction_gate
            or not exact_fields(command, {
                outcome = true,
                compaction_id = true,
                expected_context_generation = true,
                expected_last_sequence = true,
                expected_manifest_digest = true,
            })
            or not outcomes[command.outcome]
            or (command.compaction_id ~= false
                and not valid_runtime_id(
                    command.compaction_id,
                    limits.maximum_identifier_bytes
                ))
            or command.expected_context_generation ~= context_generation
            or command.expected_last_sequence ~= sequence
            or command.expected_manifest_digest ~= current_manifest_ref()
            or (not completed_exactly and not retained_exactly)
            or not phase_exact
        then
            return nil, failure(
                "CompactionSettlementMismatch",
                "compaction settlement does not bind the Runtime waterline"
            )
        end
        local mode = compaction_gate.mode
        local preflight_id = compaction_gate.preflight_id
        compaction_gate = nil
        local settlement = readonly({
            outcome = command.outcome,
            compaction_id = command.compaction_id,
            mode = mode,
            preflight_id = preflight_id,
            state = state,
            context_generation = context_generation,
            last_sequence = sequence,
            manifest_digest = command.expected_manifest_digest,
        }, "Runtime compaction settlement")
        if mode == "automatic" then
            if not pending_model_preflight
                or pending_model_preflight.id ~= preflight_id
                or pending_model_preflight.settlement ~= false
            then
                return durability_failure("automatic-compaction-preflight-binding")
            end
            pending_model_preflight.settlement = settlement
        end
        return settlement
    end

    ---Resolves exactly one deferred main/review request after the automatic
    -- compaction owner has either settled its Runtime lane or proved that the
    -- configured automatic path is disabled and the existing view may proceed.
    ---Resolves a deferred Model or review request after compaction settles.
    --@param self table AgentLoop instance.
    --@param command table Preflight outcome and exact settled waterline.
    --@return table|nil admission Model/review request or waiting-user outcome.
    --@return table|nil err Structured stale or mismatched settlement.
    function loop:resolve_compaction_preflight(command)
        if halted then return nil, halt_error end
        if compaction_gate or not pending_model_preflight then
            return nil, failure(
                "CompactionPreflightMissing",
                "no settled automatic compaction preflight awaits resolution"
            )
        end
        local deferred = pending_model_preflight
        local outcomes = {
            completed = true, fits = true, no_op = true,
            suppressed = true, waiting_user = true,
            cancelled = true, unknown = true,
        }
        if not exact_fields(command, {
            preflight_id = true,
            outcome = true,
            compaction_id = true,
            expected_context_generation = true,
            expected_last_sequence = true,
            expected_manifest_digest = true,
            settlement = true,
        })
            or command.preflight_id ~= deferred.id
            or not outcomes[command.outcome]
            or (command.compaction_id ~= false
                and not valid_runtime_id(
                    command.compaction_id,
                    limits.maximum_identifier_bytes
                ))
            or command.expected_context_generation ~= context_generation
            or command.expected_last_sequence ~= sequence
            or command.expected_manifest_digest ~= current_manifest_ref()
        then
            return nil, failure(
                "CompactionPreflightMismatch",
                "automatic compaction resolution does not bind the deferred request"
            )
        end
        if deferred.settlement ~= false then
            local settled = deferred.settlement
            if command.settlement ~= settled
                or settled.mode ~= "automatic"
                or settled.preflight_id ~= deferred.id
                or settled.outcome ~= command.outcome
                or settled.compaction_id ~= command.compaction_id
                or settled.context_generation ~= context_generation
                or settled.last_sequence ~= sequence
                or settled.manifest_digest ~= current_manifest_ref()
            then
                return nil, failure(
                    "CompactionPreflightMismatch",
                    "automatic compaction settlement is stale or substituted"
                )
            end
        elseif command.settlement ~= false
            or command.outcome ~= "fits"
            or command.compaction_id ~= false
        then
            return nil, failure(
                "CompactionPreflightMismatch",
                "only a disabled automatic path may proceed without a Runtime settlement"
            )
        end

        pending_model_preflight = nil
        if command.outcome == "completed"
            or command.outcome == "fits"
            or command.outcome == "no_op"
        then
            if deferred.kind == "main" then
                return start_model_request(
                    deferred.purpose,
                    deferred.payload.continuation ~= false
                        and deferred.payload.continuation or nil
                )
            end
            return start_review_request(
                deferred.payload.review_kind,
                deferred.payload.binding
            )
        end

        local interrupted_pending = pending
        if state ~= "WaitingUser" then transition("WaitingUser") end
        turn.reported_outcome = "waiting_user"
        pending = {
            kind = "compaction-preflight",
            preflight_id = deferred.id,
            request_kind = deferred.kind,
            purpose = deferred.purpose,
            outcome = command.outcome,
        }
        if deferred.kind == "review"
            and type(interrupted_pending) == "table"
            and interrupted_pending.call ~= nil
        then
            -- Cancellation must still synthesize the exactly-one result for
            -- a Tool call whose action review never crossed Model admission.
            pending.call = interrupted_pending.call
        end
        return readonly({
            state = state,
            outcome = "waiting_user",
            compaction_outcome = command.outcome,
            preflight_id = deferred.id,
        }, "blocked automatic compaction preflight")
    end

    ---Accepts a new main message only after its complete turn snapshot validates.
    --@param self table AgentLoop instance.
    --@param input table Main input and immutable selection snapshots.
    --@return table|nil admission New turn and Model request admission.
    --@return table|nil err Structured input, capacity, or durability failure.
    function loop:begin_main(input)
        return start_main(input, nil)
    end

    ---Adopts the first turn already committed by session publication. This
    -- starts with the next model_request barrier and never duplicates the
    -- durable turn_started or user_message Facts.
    --@param self table Fresh idle AgentLoop instance.
    --@param handoff table Published turn binding and captured input.
    --@return table|nil admission First Model request for the published turn.
    --@return table|nil err Structured stale or invalid handoff failure.
    function loop:resume_published_main(handoff)
        if halted then return nil, halt_error end
        if state ~= "Idle" or turn ~= nil or last_turn ~= nil
            or turn_serial ~= 0 or message_serial ~= 0
        then
            return nil, failure(
                "AgentBusy",
                "published first-turn handoff requires a fresh idle AgentLoop"
            )
        end
        if not exact_fields(handoff, { input = true, binding = true }) then
            return nil, failure(
                "InvalidPublishedTurn",
                "published first-turn handoff is ambiguous"
            )
        end
        local snapshot, input_error = validate_turn_input(handoff.input, limits)
        if not snapshot then return nil, input_error end
        local binding = handoff.binding
        if not exact_fields(binding, {
            first_sequence = true,
            last_sequence = true,
            context_generation = true,
            turn_id = true,
            message_id = true,
            text = true,
            source = true,
            config_snapshot = true,
            model_snapshot = true,
            permission_snapshot = true,
            prompt_snapshot = true,
            tool_registry_snapshot = true,
            view_manifest_snapshot = true,
            model_request_limit = true,
            tool_call_limit = true,
            queue_limit = true,
        })
            or binding.first_sequence ~= 1
            or binding.last_sequence ~= sequence
            or sequence ~= 2
            or binding.context_generation ~= context_generation
            or binding.turn_id ~= "turn-1"
            or binding.message_id ~= "turn-1:message:1"
            or binding.text ~= snapshot.text
            or binding.source ~= snapshot.source
            or binding.config_snapshot ~= snapshot.config_generation
            or binding.model_snapshot ~= snapshot.model_snapshot
            or binding.permission_snapshot ~= snapshot.permission_snapshot
            or binding.prompt_snapshot ~= snapshot.prompt_snapshot
            or binding.tool_registry_snapshot ~= snapshot.tool_registry_snapshot
            or binding.view_manifest_snapshot ~= snapshot.view_manifest_ref
            or binding.model_request_limit ~= snapshot.model_request_limit
            or binding.tool_call_limit ~= snapshot.tool_call_limit
            or binding.queue_limit ~= snapshot.queue_limit
            or snapshot.context_generation ~= context_generation
        then
            return nil, failure(
                "PublishedTurnMismatch",
                "published first-turn handoff does not bind the current AgentLoop"
            )
        end
        local now, clock_error = clock_now()
        if not now then return nil, clock_error end
        turn_serial = 1
        message_serial = 1
        turn = initialize_main_turn(snapshot, binding.turn_id)
        current_queue_limit = snapshot.queue_limit
        turn.trace.durable_barriers[1] = "turn-1:initial-publication"
        transition("Preparing")
        local admitted, request_error = request_model("main")
        if not admitted then return nil, request_error end
        return assert(freeze({
            state = admitted.state,
            request_id = admitted.request_id or false,
            turn_id = binding.turn_id,
            queue_item_id = false,
        }, nil, "published main turn admission"))
    end

    ---Captures and admits a fresh main snapshot from an exact idle observation.
    --@param self table AgentLoop instance.
    --@param command table User text, source, and observed Context/turn state.
    --@return table|nil admission New turn and Model request admission.
    --@return table|nil err Structured stale or capture failure.
    function loop:submit_main(command)
        if halted then return nil, halt_error end
        if not exact_fields(command, {
            text = true, source = true,
            expected_context_generation = true, expected_turn_id = true,
        }) then
            return nil, failure("InvalidMainSubmission", "main submission is ambiguous")
        end
        local observed, observation_error = validate_lane_observation(command)
        if not observed then return nil, observation_error end
        if state ~= "Idle" then return nil, failure("AgentBusy", "main submission requires idle") end
        if not valid_runtime_text(command.text, limits.hard_caps.message_bytes, false)
            or not valid_runtime_id(command.source, limits.maximum_identifier_bytes)
        then
            return nil, failure("InvalidMainSubmission", "main input is invalid")
        end
        local snapshot, snapshot_error = capture_snapshot(
            "main",
            command.text,
            command.source,
            { kind = "direct-main" }
        )
        if not snapshot then return nil, snapshot_error end
        return start_main(snapshot, nil)
    end

    ---Checks queue action fields and its exact busy-lane observation.
    --@param command table Candidate queue mutation.
    --@param allowed table Set of admitted action fields.
    --@return boolean|nil valid True when shape and observation match.
    --@return table|nil err Structured invalid or stale action failure.
    local function validate_queue_mutation(command, allowed)
        if not exact_fields(command, allowed) then
            return nil, failure("InvalidQueueAction", "queue action contains unknown fields")
        end
        return validate_lane_observation(command)
    end

    ---Durably enqueues one bounded future main input without freezing its turn snapshot.
    --@param self table AgentLoop instance.
    --@param command table Text, source, and exact Context/turn observation.
    --@return table|nil admission New durable queue item identity.
    --@return table|nil err Structured capacity, stale, or durability failure.
    function loop:enqueue(command)
        if halted then return nil, halt_error end
        if closing or state == "Closing" then
            return nil, failure("SessionClosing", "queue admission is closed")
        end
        local valid, valid_error = validate_queue_mutation(command, {
            text = true, source = true, ask_id = true,
            expected_context_generation = true, expected_turn_id = true,
        })
        if not valid then return nil, valid_error end
        if not valid_runtime_text(command.text, limits.hard_caps.message_bytes, false)
            or not valid_runtime_id(command.source, limits.maximum_identifier_bytes)
            or (command.ask_id ~= nil
                and not valid_runtime_id(command.ask_id, limits.maximum_identifier_bytes))
        then
            return nil, failure("InvalidQueueAction", "queued input is invalid")
        end
        if #queue_items >= current_queue_limit then
            return nil, failure(
                "QueueFull",
                "queue hard limit reached; the new draft was not consumed",
                { preserved_text = command.text, maximum = current_queue_limit }
            )
        end
        queue_serial = queue_serial + 1
        queue_display_serial = queue_display_serial + 1
        local item = {
            id = "queue-item-" .. tostring(queue_serial),
            display_id = "#" .. tostring(queue_display_serial),
            text = command.text,
            source = command.source,
            ask_id = command.ask_id,
        }
        local receipt, commit_error = commit_events({ queue_event(item, "enqueue") })
        if not receipt then return nil, commit_error end
        queue_items[#queue_items + 1] = item
        return assert(freeze({
            accepted = true,
            queue_item_id = item.id,
            display_id = item.display_id,
            position = #queue_items,
            queued = #queue_items,
            context_generation = context_generation,
        }, nil, "queue admission"))
    end

    ---Returns the ordered queue projection without changing Context state.
    --@param self table AgentLoop instance.
    --@return table projection Immutable ordered queue status.
    function loop:list_queue()
        local items = {}
        for index, item in ipairs(queue_items) do
            items[index] = public_queue_item(item)
            items[index].position = index
        end
        return assert(freeze({
            items = items,
            count = #items,
            maximum = current_queue_limit,
            context_generation = context_generation,
        }, nil, "queue projection"))
    end

    ---Appends a queue tombstone and removes only the exactly observed item.
    --@param self table AgentLoop instance.
    --@param command table Queue item ID, reason, and exact observation.
    --@return table|nil result Durable drop outcome.
    --@return table|nil err Structured stale or durability failure.
    function loop:drop_queue(command)
        if halted then return nil, halt_error end
        local valid, valid_error = validate_queue_mutation(command, {
            queue_item_id = true, reason = true,
            expected_context_generation = true, expected_turn_id = true,
        })
        if not valid then return nil, valid_error end
        if not valid_runtime_id(command.queue_item_id, limits.maximum_identifier_bytes)
            or not valid_runtime_text(command.reason, limits.hard_caps.message_bytes, true)
        then
            return nil, failure("InvalidQueueAction", "queue drop binding is invalid")
        end
        local index, item = queue_index(command.queue_item_id)
        if not index then return nil, failure("QueueItemMissing", "queue item is not active") end
        local receipt, commit_error = commit_events({ queue_event(item, "drop", {
            reason = command.reason ~= "" and command.reason or "user-drop",
        }) })
        if not receipt then return nil, commit_error end
        table.remove(queue_items, index)
        reset_queue_display_if_empty()
        return assert(freeze({
            dropped = item.id,
            queued = #queue_items,
            context_generation = context_generation,
        }, nil, "queue drop"))
    end

    ---Appends an amendment while preserving the queue-item identity and position.
    --@param self table AgentLoop instance.
    --@param command table Queue item ID, replacement text, and observation.
    --@return table|nil result Durable edit outcome.
    --@return table|nil err Structured stale or durability failure.
    function loop:edit_queue(command)
        if halted then return nil, halt_error end
        local valid, valid_error = validate_queue_mutation(command, {
            queue_item_id = true, text = true,
            expected_context_generation = true, expected_turn_id = true,
        })
        if not valid then return nil, valid_error end
        if not valid_runtime_id(command.queue_item_id, limits.maximum_identifier_bytes)
            or not valid_runtime_text(command.text, limits.hard_caps.message_bytes, false)
        then
            return nil, failure("InvalidQueueAction", "queue edit is invalid")
        end
        local index, item = queue_index(command.queue_item_id)
        if not index then return nil, failure("QueueItemMissing", "queue item is not active") end
        local amended = {
            id = item.id, display_id = item.display_id, text = command.text,
            source = item.source, ask_id = item.ask_id,
        }
        local receipt, commit_error = commit_events({ queue_event(amended, "edit") })
        if not receipt then return nil, commit_error end
        item.text = command.text
        return assert(freeze({
            edited = item.id,
            position = index,
            context_generation = context_generation,
        }, nil, "queue edit"))
    end

    ---Appends a reorder amendment and moves the item before another item or to the end.
    --@param self table AgentLoop instance.
    --@param command table Item ID, destination ID, and exact observation.
    --@return table|nil result Durable reorder outcome.
    --@return table|nil err Structured stale or durability failure.
    function loop:reorder_queue(command)
        if halted then return nil, halt_error end
        local valid, valid_error = validate_queue_mutation(command, {
            queue_item_id = true, before_queue_item_id = true,
            expected_context_generation = true, expected_turn_id = true,
        })
        if not valid then return nil, valid_error end
        if not valid_runtime_id(command.queue_item_id, limits.maximum_identifier_bytes)
            or (command.before_queue_item_id ~= false
                and not valid_runtime_id(
                    command.before_queue_item_id,
                    limits.maximum_identifier_bytes
                ))
            or command.before_queue_item_id == command.queue_item_id
        then
            return nil, failure("InvalidQueueAction", "queue reorder binding is invalid")
        end
        local index, item = queue_index(command.queue_item_id)
        if not index then return nil, failure("QueueItemMissing", "queue item is not active") end
        if command.before_queue_item_id ~= false
            and not queue_index(command.before_queue_item_id)
        then
            return nil, failure("QueueItemMissing", "queue reorder target is not active")
        end
        local receipt, commit_error = commit_events({ queue_event(item, "move", {
            before_queue_item_id = command.before_queue_item_id ~= false
                and command.before_queue_item_id or nil,
            reason = command.before_queue_item_id == false and "move-to-end" or nil,
        }) })
        if not receipt then return nil, commit_error end
        table.remove(queue_items, index)
        local destination = #queue_items + 1
        if command.before_queue_item_id ~= false then
            destination = assert(queue_index(command.before_queue_item_id))
        end
        table.insert(queue_items, destination, item)
        return assert(freeze({
            moved = item.id,
            position = destination,
            context_generation = context_generation,
        }, nil, "queue reorder"))
    end

    ---Appends one tombstone per active item and clears the bounded queue atomically.
    --@param self table AgentLoop instance.
    --@param command table Clear reason and exact Context/turn observation.
    --@return table|nil result Durable clear outcome.
    --@return table|nil err Structured stale or durability failure.
    function loop:clear_queue(command)
        if halted then return nil, halt_error end
        local valid, valid_error = validate_queue_mutation(command, {
            reason = true, expected_context_generation = true, expected_turn_id = true,
        })
        if not valid then return nil, valid_error end
        if not valid_runtime_text(command.reason, limits.hard_caps.message_bytes, true) then
            return nil, failure("InvalidQueueAction", "queue clear reason is invalid")
        end
        if #queue_items == 0 then
            return assert(freeze({
                cleared = 0,
                context_generation = context_generation,
            }, nil, "empty queue clear"))
        end
        local events = {}
        for _, item in ipairs(queue_items) do
            events[#events + 1] = queue_event(item, "drop", {
                reason = command.reason ~= "" and command.reason or "user-clear",
            })
        end
        local receipt, commit_error = commit_events(events)
        if not receipt then return nil, commit_error end
        local cleared = #queue_items
        queue_items = {}
        reset_queue_display_if_empty()
        return assert(freeze({
            cleared = cleared,
            context_generation = context_generation,
        }, nil, "queue clear"))
    end

    ---Captures a fresh snapshot and starts the oldest queue item while idle.
    --@param none No arguments.
    --@return table|false|nil admission Started queue item, false if unavailable.
    --@return table|nil err Structured snapshot or start failure.
    auto_start_queue = function()
        if halted then return nil, halt_error end
        if state ~= "Idle" or closing or #queue_items == 0 then return false end
        local item = queue_items[1]
        local snapshot, snapshot_error = capture_snapshot(
            "main",
            item.text,
            item.source,
            { kind = "queue", queue_item_id = item.id }
        )
        if not snapshot then return nil, snapshot_error end
        local admitted, admission_error = start_main(snapshot, { queue_item = item })
        if not admitted then return nil, admission_error end
        return assert(freeze({
            queue_item_id = item.id,
            turn_id = admitted.turn_id,
            request_id = admitted.request_id,
        }, nil, "queued main admission"))
    end

    ---Explicitly consumes the oldest queue item from a durable idle observation.
    --@param self table AgentLoop instance.
    --@param command table Exact Context/turn observation.
    --@return table|nil admission Started queued main turn.
    --@return table|nil err Structured stale or capture failure.
    function loop:run_next(command)
        if halted then return nil, halt_error end
        if not exact_fields(command, {
            expected_context_generation = true, expected_turn_id = true,
        }) then
            return nil, failure("InvalidQueueAction", "run-next action is ambiguous")
        end
        local valid, valid_error = validate_lane_observation(command)
        if not valid then return nil, valid_error end
        if state ~= "Idle" then return nil, failure("AgentBusy", "run-next requires idle main") end
        if #queue_items == 0 then return nil, failure("QueueEmpty", "no queue item is active") end
        return auto_start_queue()
    end

    ---Commits the terminal Fact for one no-tool Ask and retains its result.
    --@param outcome string Ask terminal outcome.
    --@param reason string|nil Human-readable terminal reason.
    --@param error_id string|nil Structured Ask error identity.
    --@param response table|nil Canonical direct response to retain.
    --@return table|nil result Immutable Ask outcome.
    --@return table|nil err Structured commit or missing-Ask failure.
    local function finish_ask(outcome, reason, error_id, response)
        if not ask then return nil, failure("NoAskTurn", "no ask turn is active") end
        local fields = { outcome = outcome }
        if valid_runtime_text(reason, limits.hard_caps.message_bytes, false) then
            fields.reason = reason
        end
        if error_id then fields.errorId = error_id end
        local receipt, commit_error = commit_events({ {
            type = "turn_ended",
            turn_id = ask.id,
            fields = fields,
        } })
        if not receipt then return nil, commit_error end
        local completed = ask
        completed.outcome = outcome
        completed.reason = reason or false
        completed.error_id = error_id or false
        completed.response = response or false
        completed.handle = false
        ask_history[completed.id] = completed
        ask = nil
        return assert(freeze({
            ask_id = completed.id,
            outcome = outcome,
            response_id = response and response.message_id or false,
            context_generation = context_generation,
        }, nil, "ask turn outcome"))
    end

    ---Starts one no-tool ask turn from a fresh durable snapshot.
    --@param self table AgentLoop instance.
    --@param command table Ask text, source, and exact busy-lane observation.
    --@return table|nil admission Active Ask request or terminal outcome.
    --@return table|nil err Structured snapshot, start, or durability failure.
    function loop:start_ask(command)
        if halted then return nil, halt_error end
        if closing or state == "Closing" then
            return nil, failure("SessionClosing", "ask admission is closed")
        end
        if admitted_ports.ask == false then
            return nil, failure("AskUnavailable", "ask request transport is unavailable")
        end
        if not exact_fields(command, {
            text = true, source = true,
            expected_context_generation = true, expected_turn_id = true,
        }) then
            return nil, failure("InvalidAskAction", "ask action is ambiguous")
        end
        local observed, observation_error = validate_lane_observation(command)
        if not observed then return nil, observation_error end
        if not valid_runtime_text(command.text, limits.lanes.ask_response_bytes, false)
            or not valid_runtime_id(command.source, limits.maximum_identifier_bytes)
        then
            return nil, failure("InvalidAskAction", "ask input is invalid")
        end
        if ask then
            return nil, failure(
                "AskBusy",
                "one ask turn is already active; the new draft was not consumed",
                { preserved_text = command.text, active_ask_id = ask.id }
            )
        end
        local snapshot, snapshot_error = capture_snapshot(
            "ask",
            command.text,
            command.source,
            { kind = "ask" }
        )
        if not snapshot then return nil, snapshot_error end
        local now, clock_error = clock_now()
        if not now then return nil, clock_error end
        ask_serial = ask_serial + 1
        turn_serial = turn_serial + 1
        message_serial = message_serial + 1
        request_serial = request_serial + 1
        local ask_id = "ask-" .. tostring(ask_serial)
        local message_id = ask_id .. ":message:" .. tostring(message_serial)
        local request_id = ask_id .. ":request:" .. tostring(request_serial)
        local candidate = {
            id = ask_id,
            snapshot = snapshot,
            message_id = message_id,
            request_id = request_id,
            started_at = now,
            canonical_event_seen = false,
            cancel_pending = false,
            handle = false,
        }
        local receipt, commit_error = commit_events({
            {
                type = "turn_started",
                turn_id = ask_id,
                fields = {
                    kind = "ask",
                    configGeneration = snapshot.config_generation,
                    modelSnapshot = snapshot.model_snapshot,
                    permissionSnapshot = snapshot.permission_snapshot,
                    promptSnapshot = snapshot.prompt_snapshot,
                    toolRegistrySnapshot = snapshot.tool_registry_snapshot,
                    runtimeSnapshot = limits.runtime_snapshot,
                    contextDocumentGeneration = tostring(snapshot.context_generation),
                },
            },
            {
                type = "user_message",
                turn_id = ask_id,
                fields = {
                    messageId = message_id,
                    text = snapshot.text,
                    source = snapshot.source,
                },
            },
            {
                type = "model_request",
                turn_id = ask_id,
                fields = {
                    requestId = request_id,
                    purpose = "ask",
                    viewManifestRef = snapshot.view_manifest_ref,
                },
            },
        })
        if not receipt then return nil, commit_error end
        ask = candidate
        local specification = freeze({
            ask_id = ask_id,
            turn_id = ask_id,
            request_id = request_id,
            purpose = "ask",
            view_manifest_ref = snapshot.view_manifest_ref,
            no_tools = true,
            active_time_cap_ms = limits.lanes.ask_active_time_ms,
            response_byte_cap = limits.lanes.ask_response_bytes,
            budget_snapshot_id = limits.lanes.ask_snapshot_id,
        }, nil, "ask request")
        local handle, start_error = start_effect(
            admitted_ports.ask,
            "start",
            specification,
            "Ask"
        )
        if not handle then
            return finish_ask("error", start_error.message, start_error.code)
        end
        ask.handle = handle
        return assert(freeze({
            state = "active",
            ask_id = ask_id,
            request_id = request_id,
            context_generation = context_generation,
        }, nil, "ask admission"))
    end

    ---Marks a canonical provider event for the independently active ask request.
    --@param self table AgentLoop instance.
    --@param ask_id string Active Ask turn identity.
    --@param request_id string Active Ask Model request identity.
    --@return table|nil status Canonical event observation.
    --@return table|nil err Structured stale or clock failure.
    function loop:accept_ask_event(ask_id, request_id)
        if halted then return nil, halt_error end
        if not ask or ask.id ~= ask_id or ask.request_id ~= request_id then
            return nil, failure("StaleAskResponse", "ask provider event is stale")
        end
        local now, clock_error = clock_now()
        if not now then return nil, clock_error end
        ask.canonical_event_seen = true
        return assert(freeze({
            ask_id = ask.id,
            request_id = ask.request_id,
            canonical_event_seen = true,
            automatic_replay = false,
        }, nil, "canonical ask event"))
    end

    ---Accepts one bounded canonical direct response and terminates the ask turn.
    --@param self table AgentLoop instance.
    --@param ask_id string Active Ask turn identity.
    --@param wrapper table Canonical Model response wrapper.
    --@return table|nil outcome Immutable completed or error Ask result.
    --@return table|nil err Structured stale, clock, or durability failure.
    function loop:accept_ask_response(ask_id, wrapper)
        if halted then return nil, halt_error end
        if not ask or ask.id ~= ask_id then
            return nil, failure("StaleAskResponse", "ask response is stale")
        end
        local now, clock_error = clock_now()
        if not now then return nil, clock_error end
        if now - ask.started_at >= limits.lanes.ask_active_time_ms then
            return finish_ask("budget_exhausted", "ask-active-time", "AskBudgetExhausted")
        end
        local admitted, response_error = validate_model_response(wrapper, limits)
        if not admitted then
            return finish_ask("error", response_error.message, response_error.code)
        end
        if wrapper.request_id ~= ask.request_id then
            return nil, failure("StaleAskResponse", "ask response request binding is stale")
        end
        if #wrapper.canonical_body > limits.lanes.ask_response_bytes
            or #wrapper.normalized.tool_calls ~= 0
            or wrapper.normalized.control ~= nil
        then
            return finish_ask(
                "error",
                "ask response violated its no-tool direct-response envelope",
                "InvalidAskResponse"
            )
        end
        message_serial = message_serial + 1
        local response_message_id = ask.id .. ":message:" .. tostring(message_serial)
        local outcome = "completed"
        local error_id
        if wrapper.normalized.incomplete then
            outcome = wrapper.normalized.finish_class == "cancelled" and "cancelled" or "error"
            error_id = outcome == "cancelled" and "AskCancelled" or "AskResponseIncomplete"
        end
        local receipt, commit_error = commit_events({ {
            type = "model_message",
            turn_id = ask.id,
            fields = {
                messageId = response_message_id,
                requestId = ask.request_id,
                role = "assistant",
                status = wrapper.normalized.incomplete and "interrupted" or "complete",
                body = wrapper.canonical_body,
                rawBytes = tostring(#wrapper.canonical_body),
                digest = wrapper.canonical_digest,
            },
        } })
        if not receipt then return nil, commit_error end
        return finish_ask(
            outcome,
            wrapper.normalized.incomplete_reason or "ask-response",
            error_id,
            {
                message_id = response_message_id,
                body = wrapper.canonical_body,
                digest = wrapper.canonical_digest,
            }
        )
    end

    ---Cancels the exact active ask without redirecting a stale command.
    --@param self table AgentLoop instance.
    --@param command table Ask ID, reason, and exact busy-lane observation.
    --@return table|nil result Pending cancellation or terminal Ask outcome.
    --@return table|nil err Structured stale or durability failure.
    function loop:cancel_ask(command)
        if halted then return nil, halt_error end
        if not exact_fields(command, {
            ask_id = true, reason = true,
            expected_context_generation = true, expected_turn_id = true,
        }) then
            return nil, failure("InvalidAskAction", "ask cancellation is ambiguous")
        end
        local observed, observation_error = validate_lane_observation(command)
        if not observed then return nil, observation_error end
        if not valid_runtime_id(command.ask_id, limits.maximum_identifier_bytes)
            or not valid_runtime_text(command.reason, limits.hard_caps.message_bytes, false)
        then
            return nil, failure("InvalidAskAction", "ask cancellation binding is invalid")
        end
        if not ask or ask.id ~= command.ask_id then
            return nil, failure("NoAskTurn", "the observed ask turn is not active")
        end
        local receipt, commit_error = commit_events({ {
            type = "cancel",
            turn_id = ask.id,
            fields = {
                targetKind = "LogicalRequest",
                targetId = ask.request_id,
                reason = command.reason,
                result = "requested",
            },
        } })
        if not receipt then
            pcall(admitted_ports.ask.cancel, ask.handle, command.reason)
            return nil, commit_error
        end
        local called, result = pcall(
            admitted_ports.ask.cancel,
            ask.handle,
            command.reason
        )
        if not called or type(result) ~= "table"
            or (result.outcome ~= "cancelled"
                and result.outcome ~= "pending"
                and result.outcome ~= "unknown")
        then
            return finish_ask("error", "ask cancel result is unknown", "AskCancelUnknown")
        end
        if result.result ~= nil then
            return self:accept_ask_response(ask.id, result.result)
        end
        if result.outcome == "pending" then
            ask.cancel_pending = true
            ask.cancel_reason = command.reason
            return assert(freeze({
                ask_id = ask.id,
                cancel_pending = true,
                context_generation = context_generation,
            }, nil, "pending ask cancellation"))
        end
        if result.outcome == "unknown" then
            return finish_ask("error", "ask cancel result is unknown", "AskCancelUnknown")
        end
        return finish_ask("cancelled", command.reason, "AskCancelled")
    end

    ---Settles the terminal fact of an asynchronously cancelled ask request.
    --@param self table AgentLoop instance.
    --@param settlement table Exact Ask/request IDs and observed cancel outcome.
    --@return table|nil outcome Terminal Ask result.
    --@return table|nil err Structured stale or invalid settlement.
    function loop:settle_ask_cancel(settlement)
        if halted then return nil, halt_error end
        if not ask or not ask.cancel_pending then
            return nil, failure("NoPendingAskCancel", "no ask cancellation awaits settlement")
        end
        if not exact_fields(settlement, {
            ask_id = true, request_id = true, outcome = true, response = true,
        })
            or settlement.ask_id ~= ask.id
            or settlement.request_id ~= ask.request_id
            or (settlement.response ~= nil and type(settlement.response) ~= "table")
            or (settlement.outcome ~= "cancelled"
                and settlement.outcome ~= "unknown"
                and settlement.outcome ~= "completed")
        then
            return nil, failure("InvalidAskSettlement", "ask settlement binding is invalid")
        end
        if settlement.response ~= nil then
            return self:accept_ask_response(ask.id, settlement.response)
        end
        if settlement.outcome == "completed" then
            return nil, failure(
                "InvalidAskSettlement",
                "completed ask settlement requires its canonical response"
            )
        end
        if settlement.outcome == "unknown" then
            return finish_ask("error", "ask cancel result is unknown", "AskCancelUnknown")
        end
        return finish_ask(
            "cancelled",
            ask.cancel_reason or "ask-cancelled",
            "AskCancelled"
        )
    end

    ---Returns a retained completed ask result for an explicit ask-use action.
    --@param self table AgentLoop instance.
    --@param ask_id string Completed Ask turn identity.
    --@return table|nil result Immutable retained Ask outcome and response.
    --@return table|nil err Structured missing or invalid Ask identity.
    function loop:ask_result(ask_id)
        if not valid_runtime_id(ask_id, limits.maximum_identifier_bytes) then
            return nil, failure("InvalidAskAction", "ask identity is invalid")
        end
        local completed = ask_history[ask_id]
        if not completed then return nil, failure("AskResultMissing", "ask result is unavailable") end
        return assert(freeze({
            ask_id = completed.id,
            outcome = completed.outcome,
            response = completed.response,
        }, nil, "retained ask result"))
    end

    ---Durably steers the active main turn and preempts only at a factual safe point.
    --@param self table AgentLoop instance.
    --@param command table User steer text, source, and exact lane observation.
    --@return table|nil result Pending cancel or next Model admission.
    --@return table|nil err Structured stale, cancel, or durability failure.
    function loop:steer(command)
        if halted then return nil, halt_error end
        if not exact_fields(command, {
            text = true, source = true, ask_id = true,
            expected_context_generation = true, expected_turn_id = true,
        }) then
            return nil, failure("InvalidSteer", "steer action is ambiguous")
        end
        local observed, observation_error = validate_lane_observation(command)
        if not observed then return nil, observation_error end
        if not turn or state == "Idle" or state == "Finalizing" or state == "Closing" then
            return nil, failure("NoMainTurn", "steer requires an active main turn")
        end
        if pending_steer then
            return nil, failure("SteerBusy", "a durable steer already awaits its safe point")
        end
        if not valid_runtime_text(command.text, limits.hard_caps.message_bytes, false)
            or not valid_runtime_id(command.source, limits.maximum_identifier_bytes)
            or (command.ask_id ~= nil
                and not valid_runtime_id(command.ask_id, limits.maximum_identifier_bytes))
            or (command.ask_id ~= nil and not ask_history[command.ask_id])
        then
            return nil, failure("InvalidSteer", "steer input or ask reference is invalid")
        end
        local now, clock_error = clock_now()
        if not now then return nil, clock_error end
        message_serial = message_serial + 1
        local message_id = turn.id .. ":message:" .. tostring(message_serial)
        local steer_fields = {
            messageId = message_id,
            targetTurnId = turn.id,
            summary = command.text,
        }
        if command.ask_id then steer_fields.askId = command.ask_id end
        local events = { {
            type = "steer",
            fields = steer_fields,
        } }
        local target_kind, target_id
        if active_tool then
            target_kind, target_id = "ToolCall", active_tool.call.id
        elseif active_review then
            target_kind, target_id = "LogicalRequest", active_review.id
        elseif active_request then
            target_kind, target_id = "LogicalRequest", active_request.id
        end
        if target_id then
            events[#events + 1] = {
                type = "cancel",
                fields = {
                    targetKind = target_kind,
                    targetId = target_id,
                    reason = "steer:" .. message_id,
                    result = "requested",
                },
            }
        end
        local receipt, commit_error = commit_events(events)
        if not receipt then return nil, commit_error end
        pending_steer = {
            message_id = message_id,
            text = command.text,
            source = command.source,
            ask_id = command.ask_id,
            activity_id = target_id or false,
        }

        local port, handle
        if active_tool then
            port, handle = admitted_ports.tools, active_tool.handle
        elseif active_review then
            port, handle = admitted_ports.reviews, active_review.handle
        elseif active_request then
            port, handle = admitted_ports.model, active_request.handle
        end
        if not port or handle == false or handle == nil then
            active_request, active_review = nil, nil
            return inject_steer()
        end
        local called, result = pcall(port.cancel, handle, "steer:" .. message_id)
        if not called or type(result) ~= "table"
            or (result.outcome ~= "cancelled"
                and result.outcome ~= "pending"
                and result.outcome ~= "unknown")
        then
            result = { outcome = "unknown" }
        end
        if active_tool then
            if result.result ~= nil then return accept_result(result.result) end
            if result.outcome == "pending" then
                return assert(freeze({
                    state = state,
                    steer_message_id = message_id,
                    activity_pending = true,
                }, nil, "pending tool steer"))
            end
            local result_kind = result.outcome == "unknown"
                and "unknown" or "real-cancelled"
            local settled = synthetic_result(result_kind, "steer:" .. message_id)
            settled.error_id = result.outcome == "unknown"
                and "ToolCancelUnknown" or "ToolSteered"
            settled.external_effects_unsettled = result.outcome == "unknown"
            return accept_result(settled)
        end
        if result.outcome == "pending" or result.outcome == "unknown" then
            return assert(freeze({
                state = state,
                steer_message_id = message_id,
                activity_pending = true,
                cancel_outcome = result.outcome,
            }, nil, "pending request steer"))
        end
        active_request, active_review = nil, nil
        return inject_steer()
    end

    ---Settles a provider-confirmed request/review cancellation for a pending steer.
    --@param self table AgentLoop instance.
    --@param settlement table Activity ID and confirmed cancellation outcome.
    --@return table|nil admission Injected steer Model request.
    --@return table|nil err Structured stale or invalid settlement.
    function loop:settle_steer_cancel(settlement)
        if halted then return nil, halt_error end
        if not pending_steer or active_tool
            or (not active_request and not active_review)
        then
            return nil, failure("NoPendingSteer", "no request/review steer cancellation is pending")
        end
        if not exact_fields(settlement, { activity_id = true, outcome = true })
            or settlement.activity_id ~= pending_steer.activity_id
            or (settlement.outcome ~= "cancelled" and settlement.outcome ~= "unknown")
        then
            return nil, failure("InvalidSteerSettlement", "steer settlement binding is invalid")
        end
        active_request, active_review = nil, nil
        return inject_steer()
    end

    ---Explicitly authorizes one completed ask result into queue or steer.
    --@param self table AgentLoop instance.
    --@param command table Ask ID, target lane, and exact Context observation.
    --@return table|nil result Durable queue or steer result.
    --@return table|nil err Structured invalid or stale Ask use.
    function loop:use_ask(command)
        if halted then return nil, halt_error end
        if not exact_fields(command, {
            ask_id = true, lane = true,
            expected_context_generation = true, expected_turn_id = true,
        }) then
            return nil, failure("InvalidAskUse", "ask-use action is ambiguous")
        end
        local observed, observation_error = validate_lane_observation(command)
        if not observed then return nil, observation_error end
        if not valid_runtime_id(command.ask_id, limits.maximum_identifier_bytes)
            or (command.lane ~= "queue" and command.lane ~= "steer")
        then
            return nil, failure("InvalidAskUse", "ask-use binding or target lane is invalid")
        end
        local completed = ask_history[command.ask_id]
        if not completed or completed.outcome ~= "completed" or not completed.response then
            return nil, failure("AskResultMissing", "only a completed ask response can be used")
        end
        local body = completed.response.body
        if not valid_runtime_text(body, limits.hard_caps.message_bytes, false) then
            return nil, failure("AskResultLimit", "ask result exceeds the main-message limit")
        end
        local action = {
            text = body,
            source = "ask-use",
            ask_id = command.ask_id,
            expected_context_generation = command.expected_context_generation,
            expected_turn_id = command.expected_turn_id,
        }
        if command.lane == "queue" then return self:enqueue(action) end
        return self:steer(action)
    end

    ---Closes a complete model-yield and creates an explicitly causal new turn.
    --@param self table AgentLoop instance.
    --@param command table Yield ID, action, new input, and exact observation.
    --@return table|nil result Old partial outcome and new turn admission.
    --@return table|nil err Structured stale, capture, or durability failure.
    function loop:resolve_yield(command)
        if halted then return nil, halt_error end
        if not exact_fields(command, {
            response_id = true, action = true, text = true, source = true,
            expected_context_generation = true, expected_turn_id = true,
        }) then
            return nil, failure("InvalidYieldResolution", "response resolution is ambiguous")
        end
        local observed, observation_error = validate_lane_observation(command)
        if not observed then return nil, observation_error end
        if state ~= "WaitingUser" or not pending or pending.kind ~= "model-yield" then
            return nil, failure("NoModelYield", "no complete model response awaits resolution")
        end
        if command.response_id ~= pending.message_id
            or (command.action ~= "continue" and command.action ~= "supersede")
            or not valid_runtime_text(command.text, limits.hard_caps.message_bytes, false)
            or not valid_runtime_id(command.source, limits.maximum_identifier_bytes)
        then
            return nil, failure("InvalidYieldResolution", "response resolution binding is invalid")
        end
        if admitted_ports.snapshots == false then
            return nil, failure(
                "SnapshotUnavailable",
                "a response resolution cannot create its required fresh turn snapshot"
            )
        end
        local response_id = pending.message_id
        local old_turn_id = turn.id
        local terminal, terminal_error = finalize(
            "partial",
            command.action == "continue"
                and "continued-in-new-turn" or "superseded-by-new-input"
        )
        if not terminal then return nil, terminal_error end
        local snapshot, snapshot_error = capture_snapshot(
            "main",
            command.text,
            command.source,
            {
                kind = "model-yield-resolution",
                action = command.action,
                response_id = response_id,
            }
        )
        if not snapshot then
            return nil, failure(
                snapshot_error.code,
                snapshot_error.message,
                {
                    old_turn_id = old_turn_id,
                    old_turn_outcome = "partial",
                    response_id = response_id,
                    cause = snapshot_error.detail,
                }
            )
        end
        local cause = command.action == "continue"
            and { continues_response_id = response_id }
            or { supersedes_response_id = response_id }
        local admitted, admission_error = start_main(snapshot, cause)
        if not admitted then return nil, admission_error end
        return assert(freeze({
            action = command.action,
            response_id = response_id,
            previous_turn_id = old_turn_id,
            previous_outcome = "partial",
            turn_id = admitted.turn_id,
            request_id = admitted.request_id,
            context_generation = context_generation,
        }, nil, "model-yield resolution"))
    end

    ---Accepts one complete canonical adapter response for the active request.
    --@param self table AgentLoop instance.
    --@param wrapper table Canonical response bound to the active Model request.
    --@return table|nil result Tool/review/Model admission or turn outcome.
    --@return table|nil err Structured stale, invalid, or durability failure.
    function loop:accept_model_response(wrapper)
        if halted then return nil, halt_error end
        if state ~= "RequestingModel" and state ~= "Streaming" then
            return nil, failure("NoModelRequest", "no main Model request awaits a response")
        end
        local now, clock_error = clock_now()
        if not now then return nil, clock_error end
        if turn.counters.active_time_ms >= limits.hard_caps.active_time_ms then
            return finalize("budget_exhausted", "active-time", "AgentBudgetExhausted")
        end
        local admitted, response_error = validate_model_response(wrapper, limits)
        if not admitted then
            if state == "RequestingModel" then transition("Streaming") end
            return finalize("error", response_error.message, response_error.code)
        end
        if wrapper.request_id ~= active_request.id then
            return nil, failure("StaleModelResponse", "response does not bind the active request")
        end
        if state == "RequestingModel" then transition("Streaming") end
        message_serial = message_serial + 1
        local message_id = turn.id .. ":message:" .. tostring(message_serial)
        local calls, call_events = register_calls(wrapper)
        local events = response_events(wrapper, message_id, calls, call_events)
        local receipt, commit_error = commit_events(events)
        if not receipt then return nil, commit_error end
        local request_id = active_request.id
        active_request = nil

        if pending_steer then
            if #calls > 0 then
                turn.calls = calls
                turn.call_cursor = 1
                turn.counters.tool_calls = turn.counters.tool_calls + #calls
                turn.counters.steps = turn.counters.steps + #calls
                for _, call_value in ipairs(calls) do
                    turn.trace.tool_calls[#turn.trace.tool_calls + 1] = call_value.id
                end
                transition("DispatchingTools")
                local skipped, skip_error = skip_remaining(
                    "skipped-by-steer",
                    pending_steer.message_id
                )
                if not skipped then return nil, skip_error end
            end
            return inject_steer()
        end
        if wrapper.normalized.incomplete then
            local outcome = wrapper.normalized.finish_class == "cancelled"
                and "cancelled" or "error"
            return finalize(
                outcome,
                wrapper.normalized.incomplete_reason or "incomplete-model-response",
                outcome == "cancelled" and "AgentCancelled" or "ModelResponseIncomplete"
            )
        end
        if turn.cancel_pending then
            if #calls > 0 then
                turn.calls = calls
                turn.call_cursor = 1
                turn.counters.tool_calls = turn.counters.tool_calls + #calls
                turn.counters.steps = turn.counters.steps + #calls
                for _, call_value in ipairs(calls) do
                    turn.trace.tool_calls[#turn.trace.tool_calls + 1] = call_value.id
                end
                transition("DispatchingTools")
                local skipped, skip_error = skip_remaining(
                    "skipped-by-cancel",
                    turn.cancel_reason or "cancelled"
                )
                if not skipped then return nil, skip_error end
            end
            local cancel_outcome = turn.cancel_outcome or "cancelled"
            return finalize(
                cancel_outcome,
                turn.cancel_reason or "cancelled",
                cancel_outcome == "budget_exhausted" and "AgentBudgetExhausted"
                    or "AgentCancelled"
            )
        end
        if wrapper.normalized.control ~= nil then
            return process_control(wrapper.normalized.control, request_id, message_id)
        end
        if #calls == 0 then
            transition("WaitingUser")
            turn.reported_outcome = "waiting_user"
            pending = { kind = "model-yield", message_id = message_id }
            return readonly({
                state = state,
                outcome = "waiting_user",
                response_id = message_id,
            }, "model yield")
        end

        turn.calls = calls
        turn.call_cursor = 1
        turn.counters.tool_calls = turn.counters.tool_calls + #calls
        turn.counters.steps = turn.counters.steps + #calls
        for _, call in ipairs(calls) do
            turn.trace.tool_calls[#turn.trace.tool_calls + 1] = call.id
        end
        transition("DispatchingTools")
        if turn.counters.tool_calls > turn.snapshot.tool_call_limit
            or turn.counters.steps > limits.hard_caps.steps
        then
            local skipped, skip_error = skip_remaining(
                "skipped-budget-exhausted",
                "tool-call-cap"
            )
            if not skipped then return nil, skip_error end
            return finalize("budget_exhausted", "tool-calls", "AgentBudgetExhausted")
        end
        if detector_after_escape(wrapper.progress_identity) then
            local skipped, skip_error = skip_remaining(
                "skipped-stuck-escape",
                "escape-made-no-progress"
            )
            if not skipped then return nil, skip_error end
            return finalize("stuck", "escape step made no canonical progress", "AgentStuck")
        end
        local detector_action, detector_reason = record_detector(
            wrapper.canonical_digest,
            false,
            wrapper.progress_identity
        )
        if not detector_action then return nil, detector_reason end
        if detector_action == "escape" then
            local skipped, skip_error = skip_remaining(
                "skipped-stuck-escape",
                detector_reason
            )
            if not skipped then return nil, skip_error end
            return request_model("main", {
                stuck_escape = true,
                detector = detector_reason,
            })
        elseif detector_action == "stuck" then
            local skipped, skip_error = skip_remaining(
                "skipped-stuck-escape",
                detector_reason
            )
            if not skipped then return nil, skip_error end
            return finalize("stuck", detector_reason, "AgentStuck")
        end
        return dispatch_next()
    end

    ---Marks the first canonical provider event without treating a delta as a message.
    -- This transition is deliberately transient, but it permanently forbids a
    -- coordinator from classifying the active request as pre-canonical retryable.
    --@param self table AgentLoop instance.
    --@param request_id string Active Model request identity.
    --@return table|nil status Canonical-event observation.
    --@return table|nil err Structured stale or clock failure.
    function loop:accept_model_event(request_id)
        if halted then return nil, halt_error end
        if state ~= "RequestingModel" and state ~= "Streaming" then
            return nil, failure("NoModelRequest", "no main Model request is active")
        end
        if not active_request or request_id ~= active_request.id then
            return nil, failure("StaleModelResponse", "provider event is stale")
        end
        local now, clock_error = clock_now()
        if not now then return nil, clock_error end
        active_request.canonical_event_seen = true
        if state == "RequestingModel" then transition("Streaming") end
        return readonly({
            state = state,
            request_id = request_id,
            canonical_event_seen = true,
            automatic_replay = false,
        }, "canonical Model event")
    end

    ---Accepts the terminal result of an asynchronous foreground tool.
    --@param self table AgentLoop instance.
    --@param result table Canonical Tool result.
    --@param external_receipt table|false|nil Optional paired operation receipt.
    --@return table|nil transition Next activity or terminal outcome.
    --@return table|nil err Structured clock, result, or durability failure.
    function loop:accept_tool_result(result, external_receipt)
        if halted then return nil, halt_error end
        local now, clock_error = clock_now()
        if not now then return nil, clock_error end
        return accept_result(result, external_receipt)
    end

    ---Resolves the exact pending approval without granting a broader action.
    --@param self table AgentLoop instance.
    --@param decision table Typed approval, rejection, or deferral binding.
    --@return table|nil transition Tool, Model, or waiting-user admission.
    --@return table|nil err Structured invalid, stale, or durability failure.
    function loop:resolve_approval(decision)
        if halted then return nil, halt_error end
        if (state ~= "AwaitingApproval" and state ~= "WaitingUser")
            or not pending or pending.kind ~= "approval"
        then
            return nil, failure("NoPendingApproval", "no exact tool approval is pending")
        end
        local now, clock_error = clock_now()
        if not now then return nil, clock_error end
        if not exact_fields(decision, {
            decision = true, approval_id = true,
            snapshot_digest = true, approval_digest = true,
        })
            or (decision.decision ~= "approve"
                and decision.decision ~= "reject"
                and decision.decision ~= "defer")
            or not valid_runtime_id(decision.approval_id, limits.maximum_identifier_bytes)
            or not valid_runtime_text(
                decision.snapshot_digest,
                limits.hard_caps.message_bytes,
                false
            )
            or not valid_runtime_text(
                decision.approval_digest,
                limits.hard_caps.message_bytes,
                decision.decision ~= "approve"
            )
        then
            return nil, failure("InvalidApproval", "approval decision or binding is invalid")
        end
        local approval = pending
        local receipt, commit_error = commit_events({ {
            type = "approval",
            fields = {
                approvalId = decision.approval_id,
                toolCallId = approval.call.id,
                decision = decision.decision,
                snapshotDigest = decision.snapshot_digest,
                operationId = approval.call.public.operation_id,
            },
        } })
        if not receipt then return nil, commit_error end
        if decision.decision == "defer" then
            if state ~= "WaitingUser" then transition("WaitingUser") end
            turn.reported_outcome = "waiting_user"
            return readonly({ state = state, outcome = "waiting_user" }, "deferred approval")
        end
        if state == "WaitingUser" then transition("AwaitingApproval") end
        pending = nil
        turn.reported_outcome = false
        if decision.decision == "reject" then
            transition("DispatchingTools")
            local paired, pair_error = pair_result(
                approval.call,
                synthetic_result("synthetic-rejected", "approval-rejected")
            )
            if not paired then return nil, pair_error end
            turn.call_cursor = turn.call_cursor + 1
            return complete_batch("approval-rejected")
        end
        local admitted = {}
        for key, value in pairs(approval.admission) do admitted[key] = value end
        admitted.approval_digest = decision.approval_digest
        return start_tool(approval.call, admitted)
    end

    ---Applies a durable action-review verdict; reviewers can only pass or tighten.
    --@param self table AgentLoop instance.
    --@param verdict table Typed action review bound to the exact Tool call.
    --@return table|nil transition Tool, approval, Model, or waiting-user result.
    --@return table|nil err Structured invalid or durability failure.
    function loop:resolve_action_review(verdict)
        if halted then return nil, halt_error end
        if (state ~= "EvaluatingAction" and state ~= "WaitingUser")
            or not pending or pending.kind ~= "action-review"
        then
            return nil, failure("NoActionReview", "no action review is pending")
        end
        local now, clock_error = clock_now()
        if not now then return nil, clock_error end
        if not exact_fields(verdict, {
            verdict = true, review_id = true, binding_digest = true, reason = true,
        })
            or (verdict.verdict ~= "pass" and verdict.verdict ~= "tighten"
                and verdict.verdict ~= "deny" and verdict.verdict ~= "uncertain")
            or not valid_runtime_id(verdict.review_id, limits.maximum_identifier_bytes)
            or not valid_runtime_text(
                verdict.binding_digest,
                limits.hard_caps.message_bytes,
                false
            )
            or not valid_runtime_text(verdict.reason, limits.hard_caps.message_bytes, true)
        then
            return nil, failure("InvalidReviewVerdict", "action-review verdict is invalid")
        end
        local review = pending
        local receipt, commit_error = commit_events({ {
            type = "action_review",
            fields = {
                reviewId = verdict.review_id,
                toolCallId = review.call.id,
                verdict = verdict.verdict,
                bindingDigest = verdict.binding_digest,
                reason = verdict.reason,
            },
        } })
        if not receipt then return nil, commit_error end
        active_review = nil
        if pending_steer then return inject_steer() end
        if verdict.verdict == "uncertain" then
            if state ~= "WaitingUser" then transition("WaitingUser") end
            turn.reported_outcome = "waiting_user"
            return readonly({ state = state, outcome = "waiting_user" }, "uncertain review")
        end
        if state == "WaitingUser" then transition("EvaluatingAction") end
        pending = nil
        turn.reported_outcome = false
        if verdict.verdict == "deny" then
            transition("DispatchingTools")
            local paired, pair_error = pair_result(
                review.call,
                synthetic_result("synthetic-review-denied", verdict.reason)
            )
            if not paired then return nil, pair_error end
            turn.call_cursor = turn.call_cursor + 1
            return complete_batch("action-review-denied")
        end
        local admission = {}
        for key, value in pairs(review.admission) do admission[key] = value end
        admission.review_verdict = verdict.verdict
        if review.admission.after_review == "confirm" then
            pending = { kind = "approval", call = review.call, admission = admission }
            transition("AwaitingApproval")
            return readonly({ state = state, tool_call_id = review.call.id }, "approval wait")
        end
        return start_tool(review.call, admission)
    end

    ---Applies a durable typed termination-review verdict.
    --@param self table AgentLoop instance.
    --@param verdict table Typed finish review and optional gap evidence.
    --@return table|nil transition Completed, follow-up Model, or waiting-user result.
    --@return table|nil err Structured invalid or durability failure.
    function loop:resolve_termination_review(verdict)
        if halted then return nil, halt_error end
        if (state ~= "EvaluatingTermination" and state ~= "WaitingUser")
            or not pending or pending.kind ~= "termination-review"
        then
            return nil, failure("NoTerminationReview", "no finish review is pending")
        end
        local now, clock_error = clock_now()
        if not now then return nil, clock_error end
        if not exact_fields(verdict, {
            verdict = true, review_id = true, binding_digest = true,
            gap = true, reason = true,
        })
            or (verdict.verdict ~= "pass" and verdict.verdict ~= "gap"
                and verdict.verdict ~= "uncertain")
            or not valid_runtime_id(verdict.review_id, limits.maximum_identifier_bytes)
            or not valid_runtime_text(
                verdict.binding_digest,
                limits.hard_caps.message_bytes,
                false
            )
            or not valid_runtime_text(verdict.gap, limits.hard_caps.message_bytes, true)
            or not valid_runtime_text(verdict.reason, limits.hard_caps.message_bytes, true)
            or (verdict.verdict == "gap" and verdict.gap == "")
        then
            return nil, failure("InvalidReviewVerdict", "termination verdict is invalid")
        end
        local review = pending
        local receipt, commit_error = commit_events({ {
            type = "termination_review",
            fields = {
                reviewId = verdict.review_id,
                requestId = review.request_id,
                verdict = verdict.verdict,
                bindingDigest = verdict.binding_digest,
                gap = verdict.gap,
                reason = verdict.reason,
            },
        } })
        if not receipt then return nil, commit_error end
        active_review, pending = nil, nil
        if pending_steer then return inject_steer() end
        if state == "WaitingUser" and verdict.verdict ~= "uncertain" then
            transition("EvaluatingTermination")
        end
        if verdict.verdict == "pass" then return finalize("completed", verdict.reason) end
        if verdict.verdict == "gap" then
            turn.finish_after_review_gap = true
            return request_model("main", {
                termination_review_gap = verdict.gap,
                review_id = verdict.review_id,
            })
        end
        transition("WaitingUser")
        turn.reported_outcome = "waiting_user"
        pending = {
            kind = "termination-review",
            request_id = review.request_id,
            message_id = review.message_id,
        }
        return readonly({ state = state, outcome = "waiting_user" }, "uncertain review")
    end

    ---Durably attaches a user answer to an ask-user or uncertain-review slot.
    --@param self table AgentLoop instance.
    --@param text_value string User reply text.
    --@param source string User input source identity.
    --@return table|nil admission Follow-up Model request.
    --@return table|nil err Structured invalid state or durability failure.
    function loop:reply(text_value, source)
        if halted then return nil, halt_error end
        if state ~= "WaitingUser" or not pending then
            return nil, failure("NoPendingQuestion", "the turn is not waiting for an answer")
        end
        if pending.kind == "model-yield" then
            return nil, failure(
                "ExplicitContinuationRequired",
                "a complete model yield cannot be resumed by guessing from ordinary input"
            )
        end
        if pending.kind == "approval" then
            return nil, failure("ApprovalDecisionRequired", "approval requires a typed decision")
        end
        if pending.kind == "action-review" then
            return nil, failure(
                "ReviewResolutionRequired",
                "an accepted action requires a typed review verdict before continuation"
            )
        end
        if not valid_runtime_text(text_value, limits.hard_caps.message_bytes, false)
            or not valid_runtime_id(source, limits.maximum_identifier_bytes)
        then
            return nil, failure("InvalidUserReply", "user reply is invalid")
        end
        local now, clock_error = clock_now()
        if not now then return nil, clock_error end
        message_serial = message_serial + 1
        local message_id = turn.id .. ":message:" .. tostring(message_serial)
        local fields = { messageId = message_id, text = text_value, source = source }
        if pending.message_id then fields.replyToMessageId = pending.message_id end
        local receipt, commit_error = commit_events({ { type = "user_message", fields = fields } })
        if not receipt then return nil, commit_error end
        turn.reported_outcome = false
        pending = nil
        turn.detector.semantic_no_progress = 0
        turn.detector.last_progress = "user-message:" .. message_id
        return request_model("main", { user_reply = message_id })
    end

    ---Requests cancellation from the innermost active external activity.
    --@param reason string Durable cancellation reason.
    --@return string outcome Cancelled, pending, or unknown.
    --@return table|nil result Canonical terminal Tool result if supplied.
    local function cancel_activity(reason)
        local port, handle
        if active_tool then
            port, handle = admitted_ports.tools, active_tool.handle
        elseif active_review then
            port, handle = admitted_ports.reviews, active_review.handle
        elseif active_request then
            port, handle = admitted_ports.model, active_request.handle
        end
        if not port or handle == false or handle == nil then return "cancelled" end
        local called, result = pcall(port.cancel, handle, reason)
        if not called or type(result) ~= "table"
            or (result.outcome ~= "cancelled"
                and result.outcome ~= "pending"
                and result.outcome ~= "unknown")
        then return "unknown" end
        return result.outcome, result.result
    end

    ---Cancels the innermost activity; accepted calls remain exactly paired.
    --@param self table AgentLoop instance.
    --@param reason string Bounded cancellation reason.
    --@return table|nil outcome Pending cancellation or terminal turn result.
    --@return table|nil err Structured state, clock, or durability failure.
    function loop:cancel(reason)
        if halted then return nil, halt_error end
        if compaction_gate then
            return nil, failure(
                "CompactionBusy",
                "the compaction owner must settle its own cancellation"
            )
        end
        if state == "Idle" or state == "Closing" or state == "Finalizing" then
            return nil, failure("NothingToCancel", "no cancellable main turn is active")
        end
        if not valid_runtime_text(reason, limits.hard_caps.message_bytes, false) then
            return nil, failure("InvalidCancel", "cancel reason is invalid")
        end
        local now, clock_error = clock_now()
        if not now then return nil, clock_error end
        local target_kind = active_tool and "ToolCall"
            or (active_review and "LogicalRequest")
            or (active_request and "LogicalRequest")
            or "Turn"
        local target_id = active_tool and active_tool.call.id
            or (active_review and active_review.id)
            or (active_request and active_request.id)
            or turn.id
        local receipt, commit_error = commit_events({ {
            type = "cancel",
            fields = {
                targetKind = target_kind,
                targetId = target_id,
                reason = reason,
                result = "requested",
            },
        } })
        if not receipt then
            -- Cancellation is the sole safety action still attempted after a
            -- journal failure; no new request or tool effect is admitted.
            cancel_activity(reason)
            return nil, commit_error
        end
        turn.cancel_pending = true
        turn.cancel_reason = reason
        turn.cancel_outcome = turn.cancel_outcome or "cancelled"
        if state == "AwaitingApproval" or state == "DispatchingTools"
            or state == "EvaluatingAction"
            or (state == "WaitingUser" and pending and pending.call)
        then
            if state == "EvaluatingAction" and active_review then
                cancel_activity(reason)
                active_review = nil
            end
            if state ~= "DispatchingTools" and state ~= "WaitingUser" then
                transition("DispatchingTools")
            end
            if turn.call_cursor <= #turn.calls then
                local call = turn.calls[turn.call_cursor]
                if call.result == nil then
                    local paired, pair_error = pair_result(
                        call,
                        synthetic_result("skipped-by-cancel", reason)
                    )
                    if not paired then return nil, pair_error end
                    turn.call_cursor = turn.call_cursor + 1
                end
                local skipped, skip_error = skip_remaining("skipped-by-cancel", reason)
                if not skipped then return nil, skip_error end
            end
            return finalize(turn.cancel_outcome, reason,
                turn.cancel_outcome == "budget_exhausted"
                    and "AgentBudgetExhausted" or "AgentCancelled")
        end
        if state == "WaitingUser" or state == "Preparing" then
            return finalize(turn.cancel_outcome, reason,
                turn.cancel_outcome == "budget_exhausted"
                    and "AgentBudgetExhausted" or "AgentCancelled")
        end
        local outcome, terminal_result = cancel_activity(reason)
        if active_tool and terminal_result ~= nil then return accept_result(terminal_result) end
        if outcome == "pending" then
            return readonly({ state = state, cancel_pending = true }, "pending cancellation")
        end
        if active_tool then
            local result = synthetic_result(
                outcome == "unknown" and "unknown" or "real-cancelled",
                reason
            )
            result.error_id = outcome == "unknown" and "ToolCancelUnknown" or "AgentCancelled"
            result.external_effects_unsettled = outcome == "unknown"
            return accept_result(result)
        end
        return finalize(turn.cancel_outcome, reason,
            turn.cancel_outcome == "budget_exhausted"
                and "AgentBudgetExhausted" or "AgentCancelled")
    end

    ---Terminates on a typed Runtime fact; completed/refused remain control-only.
    --@param self table AgentLoop instance.
    --@param outcome string Admitted runtime-abort outcome.
    --@param reason string|nil Human-readable terminal reason.
    --@param error_id string|nil Structured error identity.
    --@return table|nil result Durable terminal turn outcome.
    --@return table|nil err Structured invalid or durability failure.
    function loop:abort(outcome, reason, error_id)
        if halted then return nil, halt_error end
        if not turn or not RUNTIME_ABORT_OUTCOMES[outcome] then
            return nil, failure("InvalidRuntimeAbort", "runtime abort outcome is invalid")
        end
        if active_tool or turn.call_cursor <= #turn.calls then
            return nil, failure(
                "UnpairedToolCalls",
                "runtime abort cannot bypass accepted tool-call results"
            )
        end
        local now, clock_error = clock_now()
        if not now then return nil, clock_error end
        return finalize(outcome, reason, error_id)
    end

    ---Checks the active-time hard cap without admitting another activity.
    --@param self table AgentLoop instance.
    --@return table|nil status Tick snapshot or terminal outcome.
    --@return table|nil err Structured clock or cancellation failure.
    function loop:tick()
        if halted then return nil, halt_error end
        local now, clock_error = clock_now()
        if not now then return nil, clock_error end
        if ask and not ask.cancel_pending
            and now - ask.started_at >= limits.lanes.ask_active_time_ms
        then
            local cancelled, cancel_error = self:cancel_ask({
                ask_id = ask.id,
                reason = "ask-active-time-budget",
                expected_context_generation = context_generation,
                expected_turn_id = observed_turn_id(),
            })
            if not cancelled then return nil, cancel_error end
        end
        if turn and not PAUSED_AGENT_STATES[state]
            and turn.counters.active_time_ms >= limits.hard_caps.active_time_ms
        then
            if active_tool then
                turn.cancel_outcome = "budget_exhausted"
                return self:cancel("active-time-budget")
            end
            return finalize("budget_exhausted", "active-time", "AgentBudgetExhausted")
        end
        return readonly({ state = state, now = now }, "AgentLoop tick")
    end

    ---Closes admission and uses the same cancellation/finalization path.
    --@param self table AgentLoop instance.
    --@param reason string|nil Close and cancellation reason.
    --@return boolean|nil closed True after closing, false when already closed.
    --@return table|nil err Structured pending compaction or settlement failure.
    function loop:close(reason)
        if state == "Closing" then return false end
        if compaction_gate then
            return nil, failure(
                "CompactionBusy",
                "compaction must settle before the AgentLoop can close"
            )
        end
        closing = true
        reason = reason or "close"
        if ask then
            local cancelled, cancel_error = self:cancel_ask({
                ask_id = ask.id,
                reason = reason,
                expected_context_generation = context_generation,
                expected_turn_id = observed_turn_id(),
            })
            if not cancelled and not halted then return nil, cancel_error end
        end
        if #queue_items > 0 and not halted then
            local cleared, clear_error = self:clear_queue({
                reason = reason,
                expected_context_generation = context_generation,
                expected_turn_id = observed_turn_id(),
            })
            if not cleared then return nil, clear_error end
        end
        if state == "Idle" then
            transition("Closing")
            return true
        end
        if state == "Finalizing" or halted then
            if state ~= "Closing" and AGENT_TRANSITIONS[state].Closing then transition("Closing") end
            return true
        end
        local closed, close_error = self:cancel(reason)
        if not closed and state ~= "Closing" then return nil, close_error end
        return true
    end

    ---Returns a detached immutable projection; waiting is reportable, not terminal.
    --@param self table AgentLoop instance.
    --@return table status Immutable counters, lanes, queue, Ask, and trace snapshot.
    function loop:status()
        local active_turn = turn
        local counters = active_turn and active_turn.counters
            or (last_turn and last_turn.counters)
            or {
                active_time_ms = 0, model_requests = 0,
                tool_calls = 0, reviews = 0, steps = 0,
            }
        local trace = current_trace() or {
            states = { "Idle" }, purposes = {}, controls = {},
            tool_calls = {}, tool_results = {}, durable_barriers = {},
            durable_warning = false, escape_steps = 0, outcome = false,
        }
        local reported_outcome
        local reportable
        if active_turn then
            reported_outcome = active_turn.reported_outcome or false
            reportable = reported_outcome == "waiting_user"
        else
            reported_outcome = last_turn and last_turn.outcome or false
            reportable = last_turn ~= nil
        end
        local queue_projection = {}
        for index, item in ipairs(queue_items) do
            queue_projection[index] = public_queue_item(item)
            queue_projection[index].position = index
        end
        local ask_history_count = 0
        for _ in pairs(ask_history) do ask_history_count = ask_history_count + 1 end
        return assert(freeze({
            state = state,
            turn_id = active_turn and active_turn.id or false,
            active_request_id = active_request and active_request.id or false,
            active_tool_call_id = active_tool and active_tool.call.id or false,
            active_tool_adapter_call_id = active_tool
                and active_tool.call.public.adapter_call_id or false,
            pending_kind = pending and pending.kind or false,
            pending_tool_call_id = pending and pending.kind == "approval"
                and pending.call.id or false,
            pending_operation_id = pending and pending.kind == "approval"
                and pending.call.public.operation_id or false,
            pending_review_verdict = pending and pending.kind == "approval"
                and pending.admission.review_verdict or false,
            pending_question = pending and pending.kind == "ask-user"
                and pending.question or false,
            pending_response_id = pending and pending.kind == "model-yield"
                and pending.message_id or false,
            reported_outcome = reported_outcome,
            last_outcome = last_turn and last_turn.outcome or false,
            outcome_durable = active_turn ~= nil
                and active_turn.outcome_durable
                or (active_turn == nil and last_turn ~= nil),
            halted = halted,
            reportable = not halted and reportable,
            last_durable_sequence = sequence,
            context_generation = context_generation,
            active_view_manifest_ref = current_manifest_ref(),
            compaction_state = compaction_gate and "active" or "idle",
            compaction_mode = compaction_gate and compaction_gate.mode or false,
            compaction_phase = compaction_gate and compaction_gate.phase or false,
            compaction_preflight_state = pending_model_preflight
                and (pending_model_preflight.settlement ~= false
                    and "settled" or "pending")
                or (pending and pending.kind == "compaction-preflight"
                    and "blocked" or "idle"),
            compaction_preflight_id = pending_model_preflight
                and pending_model_preflight.id
                or (pending and pending.kind == "compaction-preflight"
                    and pending.preflight_id or false),
            compaction_preflight_purpose = pending_model_preflight
                and pending_model_preflight.purpose
                or (pending and pending.kind == "compaction-preflight"
                    and pending.purpose or false),
            counters = counters,
            trace = trace,
            hard_cap_snapshot_id = limits.hard_cap_snapshot_id,
            stuck_snapshot_id = limits.stuck.snapshot_id,
            runtime_snapshot = limits.runtime_snapshot,
            auto_replay = false,
            concurrent_tools = active_tool and 1 or 0,
            queue = queue_projection,
            queue_count = #queue_projection,
            queue_maximum = current_queue_limit,
            pending_steer_message_id = pending_steer and pending_steer.message_id or false,
            ask_state = ask and (ask.cancel_pending and "cancelling" or "active") or "idle",
            active_ask_id = ask and ask.id or false,
            active_ask_request_id = ask and ask.request_id or false,
            ask_history_count = ask_history_count,
            ask_budget_snapshot_id = limits.lanes.ask_snapshot_id,
        }, nil, "AgentLoop status"))
    end

    loop.capabilities = assert(freeze({
        states = AGENT_STATES,
        outcomes = TURN_OUTCOMES,
        controls = CONTROL_NAMES,
        single_owner = true,
        concurrent_tools_maximum = 1,
        accepted_call_results = "exactly-one-real-or-synthetic",
        provider_stop_means_completed = false,
        natural_language_done_means_finish = false,
        durable_before_effect = true,
        precommitted_first_turn = true,
        no_auto_replay = true,
        queue_actions = {
            enqueue = true, list = true, drop = true,
            edit = true, reorder = true, clear = true,
        },
        queue_autostart_outcome = "completed",
        steer_same_turn = true,
        ask_concurrency_maximum = 1,
        ask_tools = false,
        ask_use_lanes = { queue = true, steer = true },
        external_session_override_receipts = true,
        external_session_override_fail_stop = true,
        external_compaction_receipts = true,
        automatic_compaction_preflight = limits.automatic_compaction,
    }, nil, "AgentLoop capabilities"))
    return readonly(loop, "AgentLoop")
end

local DRIVER_OPTION_FIELDS = {
    model_poll_events = true,
    tool_poll_events = true,
    review_poll_events = true,
    maximum_output_events = true,
}

---Validates activity-driver ports and bounded per-step poll/output limits.
--@param ports table AgentLoop and Model/Tool/review/Ask activity ports.
--@param options table Poll event and output event limits.
--@return table|nil admitted Validated driver dependencies.
--@return table|nil err Structured driver contract failure.
local function validate_agent_driver(ports, options)
    if type(ports) ~= "table" or not exact_fields(ports, {
        loop = true,
        model = true,
        tools = true,
        reviews = true,
        ask = true,
        clock = true,
    })
        or type(ports.loop) ~= "table"
        or type(ports.loop.status) ~= "function"
        or type(ports.loop.tick) ~= "function"
        or type(ports.loop.accept_model_event) ~= "function"
        or type(ports.loop.accept_model_response) ~= "function"
        or type(ports.loop.accept_tool_result) ~= "function"
        or type(ports.loop.resolve_action_review) ~= "function"
        or type(ports.loop.resolve_termination_review) ~= "function"
        or (ports.ask ~= false and (
            type(ports.loop.accept_ask_event) ~= "function"
            or type(ports.loop.accept_ask_response) ~= "function"
        ))
        or type(ports.model) ~= "table"
        or type(ports.model.poll) ~= "function"
        or type(ports.tools) ~= "table"
        or type(ports.tools.poll) ~= "function"
        or (ports.reviews ~= false and (
            type(ports.reviews) ~= "table"
            or type(ports.reviews.poll) ~= "function"
        ))
        or (ports.ask ~= false and (
            type(ports.ask) ~= "table"
            or type(ports.ask.poll) ~= "function"
        ))
        or type(ports.clock) ~= "table"
        or type(ports.clock.now) ~= "function"
        or type(options) ~= "table"
        or not exact_fields(options, DRIVER_OPTION_FIELDS)
        or not integer_at_least(options.model_poll_events, 1)
        or not integer_at_least(options.tool_poll_events, 1)
        or not integer_at_least(options.review_poll_events, 1)
        or not integer_at_least(options.maximum_output_events, 1)
        or options.maximum_output_events < math.max(
            options.model_poll_events,
            options.tool_poll_events + 1,
            options.review_poll_events
        ) + (ports.ask == false and 0 or options.model_poll_events)
    then
        return nil, failure(
            "InvalidAgentDriver",
            "Agent activity driver ports or limits are incomplete"
        )
    end
    return { ports = ports, options = options }
end

---Calls a typed AgentLoop reducer and normalizes failures from exceptions.
--@param target table AgentLoop facade.
--@param method string Reducer method name.
--@param ... any Method arguments after the implicit receiver.
--@return any|nil result Accepted reducer transition.
--@return table|nil err Structured rejection or exception failure.
local function driver_call(target, method, ...)
    local called, result, call_error = pcall(target[method], target, ...)
    if not called then
        return nil, failure(
            "AgentDriverFailure",
            "AgentLoop activity reduction raised an exception",
            method
        )
    end
    if result == nil or result == false then
        return nil, call_error or failure(
            "AgentDriverFailure",
            "AgentLoop rejected an activity fact",
            method
        )
    end
    return result
end

---Drives canonical main Model, ask Model, Tool, and review activities into one
-- AgentLoop owner.
-- The driver never interprets Model text or operation effects; it only maps
-- already-normalized activity facts to the corresponding typed Runtime method.
--@param ports table AgentLoop and normalized activity ports.
--@param options table Bounded poll and output event limits.
--@return table|nil service Read-only activity driver.
--@return table|nil err Structured port or option failure.
function M.new_agent_activity_driver(ports, options)
    local admitted, admission_error = validate_agent_driver(ports, options)
    if not admitted then return nil, admission_error end
    local last_now
    local steps = 0
    local service = {}

    ---Reads a monotonic driver tick before polling Tool activity.
    --@param none No arguments.
    --@return integer|nil now Current monotonic tick.
    --@return table|nil err Structured clock failure.
    local function now()
        local called, value = pcall(admitted.ports.clock.now)
        if not called or not integer_at_least(value, 0)
            or (last_now ~= nil and value < last_now)
        then
            return nil, failure(
                "MonotonicClockFailure",
                "Agent activity driver clock failed"
            )
        end
        last_now = value
        return value
    end

    ---Appends one visible activity event within the driver output cap.
    --@param output table Mutable per-step event array.
    --@param event table Normalized activity or Runtime transition event.
    --@return boolean|nil appended True when output remains bounded.
    --@return table|nil err Structured output-limit failure.
    local function append(output, event)
        if #output >= admitted.options.maximum_output_events then
            return nil, failure(
                "AgentDriverOutputLimit",
                "Agent activity driver output exceeded its bounded queue"
            )
        end
        output[#output + 1] = event
        return true
    end

    ---Polls main Model events and reduces canonical facts into AgentLoop.
    --@param output table Mutable per-step visible event array.
    --@return boolean|nil progressed Whether the Model emitted any events.
    --@return table|nil err Structured port or reducer failure.
    local function model_step(output)
        local batch, poll_error = admitted.ports.model.poll(
            admitted.options.model_poll_events
        )
        if dense_count(batch) == nil then
            return nil, poll_error or failure(
                "ModelActivityContract",
                "Model activity returned an invalid batch"
            )
        end
        for _, event in ipairs(batch) do
            if type(event) ~= "table" or type(event.kind) ~= "string" then
                return nil, failure(
                    "ModelActivityContract",
                    "Model activity event is invalid"
                )
            elseif event.kind == "canonical-event" then
                local reduced, reduce_error = driver_call(
                    admitted.ports.loop,
                    "accept_model_event",
                    event.request_id
                )
                if not reduced then return nil, reduce_error end
            elseif event.kind == "adapter-event" then
                local appended, append_error = append(output, {
                    kind = "model-event",
                    request_id = event.request_id,
                    event = event.event,
                })
                if not appended then return nil, append_error end
            elseif event.kind == "response" then
                local reduced, reduce_error = driver_call(
                    admitted.ports.loop,
                    "accept_model_response",
                    event.wrapper
                )
                if not reduced then return nil, reduce_error end
                local appended, append_error = append(output, {
                    kind = "runtime-transition",
                    cause = "model-response",
                    request_id = event.request_id,
                    result = reduced,
                })
                if not appended then return nil, append_error end
            else
                return nil, failure(
                    "ModelActivityContract",
                    "Model activity returned an unknown event"
                )
            end
        end
        return #batch > 0
    end

    ---Polls the independent no-tool Ask Model lane and reduces its facts.
    --@param output table Mutable per-step visible event array.
    --@param observed table Pre-step AgentLoop status with active Ask ID.
    --@return boolean|nil progressed Whether Ask emitted any events.
    --@return table|nil err Structured port or reducer failure.
    local function ask_step(output, observed)
        local batch, poll_error = admitted.ports.ask.poll(
            admitted.options.model_poll_events
        )
        if dense_count(batch) == nil then
            return nil, poll_error or failure(
                "AskActivityContract",
                "ask Model activity returned an invalid batch"
            )
        end
        for _, event in ipairs(batch) do
            if type(event) ~= "table" or type(event.kind) ~= "string" then
                return nil, failure(
                    "AskActivityContract",
                    "ask Model activity event is invalid"
                )
            elseif event.kind == "canonical-event" then
                local reduced, reduce_error = driver_call(
                    admitted.ports.loop,
                    "accept_ask_event",
                    observed.active_ask_id,
                    event.request_id
                )
                if not reduced then return nil, reduce_error end
            elseif event.kind == "adapter-event" then
                local appended, append_error = append(output, {
                    kind = "ask-model-event",
                    ask_id = observed.active_ask_id,
                    request_id = event.request_id,
                    event = event.event,
                })
                if not appended then return nil, append_error end
            elseif event.kind == "response" then
                local reduced, reduce_error = driver_call(
                    admitted.ports.loop,
                    "accept_ask_response",
                    observed.active_ask_id,
                    event.wrapper
                )
                if not reduced then return nil, reduce_error end
                local appended, append_error = append(output, {
                    kind = "runtime-transition",
                    cause = "ask-response",
                    ask_id = observed.active_ask_id,
                    request_id = event.request_id,
                    result = reduced,
                })
                if not appended then return nil, append_error end
            else
                return nil, failure(
                    "AskActivityContract",
                    "ask Model activity returned an unknown event"
                )
            end
        end
        return #batch > 0
    end

    ---Polls foreground Tool progress and accepts its terminal settlement.
    --@param output table Mutable per-step visible event array.
    --@return boolean|nil progressed Whether Tool progress or settlement appeared.
    --@return table|nil err Structured port or reducer failure.
    local function tool_step(output)
        local observed_now, clock_error = now()
        if not observed_now then return nil, clock_error end
        local observed = admitted.ports.loop:status()
        local events, settlement = admitted.ports.tools.poll(
            observed_now,
            admitted.options.tool_poll_events
        )
        if dense_count(events) == nil or settlement == nil then
            return nil, failure(
                "ToolActivityContract",
                "Tool activity returned an invalid poll result",
                settlement or events
            )
        end
        for _, event in ipairs(events) do
            local appended, append_error = append(output, {
                kind = "tool-event",
                tool_call_id = observed.active_tool_call_id,
                adapter_call_id = observed.active_tool_adapter_call_id,
                event = event,
            })
            if not appended then return nil, append_error end
        end
        if settlement ~= false then
            if type(settlement) ~= "table" or type(settlement.result) ~= "table"
                or (settlement.result_receipt ~= false
                    and type(settlement.result_receipt) ~= "table")
            then
                return nil, failure(
                    "ToolActivityContract",
                    "Tool settlement is incomplete"
                )
            end
            local reduced, reduce_error = driver_call(
                admitted.ports.loop,
                "accept_tool_result",
                settlement.result,
                settlement.result_receipt
            )
            if not reduced then return nil, reduce_error end
            local appended, append_error = append(output, {
                kind = "runtime-transition",
                cause = "tool-result",
                result = reduced,
            })
            if not appended then return nil, append_error end
        end
        return #events > 0 or settlement ~= false
    end

    ---Polls action/termination review verdicts and applies typed reductions.
    --@param output table Mutable per-step visible event array.
    --@return boolean|nil progressed Whether review emitted a verdict.
    --@return table|nil err Structured port or reducer failure.
    local function review_step(output)
        if admitted.ports.reviews == false then
            return nil, failure(
                "ReviewActivityUnavailable",
                "AgentLoop is evaluating a review without a review activity port"
            )
        end
        local batch, poll_error = admitted.ports.reviews.poll(
            admitted.options.review_poll_events
        )
        if dense_count(batch) == nil then
            return nil, poll_error or failure(
                "ReviewActivityContract",
                "review activity returned an invalid batch"
            )
        end
        for _, event in ipairs(batch) do
            if type(event) ~= "table" or event.kind ~= "verdict"
                or (event.purpose ~= "action-review"
                    and event.purpose ~= "termination-review")
                or type(event.verdict) ~= "table"
            then
                return nil, failure(
                    "ReviewActivityContract",
                    "review activity returned an invalid verdict"
                )
            end
            local method = event.purpose == "action-review"
                and "resolve_action_review"
                or "resolve_termination_review"
            local reduced, reduce_error = driver_call(
                admitted.ports.loop,
                method,
                event.verdict
            )
            if not reduced then return nil, reduce_error end
            local appended, append_error = append(output, {
                kind = "runtime-transition",
                cause = event.purpose,
                request_id = event.request_id,
                result = reduced,
            })
            if not appended then return nil, append_error end
        end
        return #batch > 0
    end

    ---Advances one bounded Agent activity tick across foreground and Ask lanes.
    --@param none No arguments.
    --@return table|nil result Immutable event, status, progress, and step snapshot.
    --@return table|nil err Structured activity or reducer failure.
    function service.step()
        local ticked, tick_error = driver_call(admitted.ports.loop, "tick")
        if not ticked then return nil, tick_error end
        local before = admitted.ports.loop:status()
        if type(before) ~= "table" or type(before.state) ~= "string" then
            return nil, failure("AgentDriverFailure", "AgentLoop status is invalid")
        end
        local output = {}
        local progressed = false
        local lane_progress, lane_error
        if before.state == "RequestingModel" or before.state == "Streaming" then
            lane_progress, lane_error = model_step(output)
        elseif before.state == "ExecutingTool" then
            lane_progress, lane_error = tool_step(output)
        elseif (before.compaction_preflight_state == nil
                or before.compaction_preflight_state == "idle")
            and (before.state == "EvaluatingAction"
                or before.state == "EvaluatingTermination")
        then
            lane_progress, lane_error = review_step(output)
        else
            lane_progress = false
        end
        if lane_progress == nil then return nil, lane_error end
        progressed = lane_progress
        if admitted.ports.ask ~= false
            and (before.ask_state == "active" or before.ask_state == "cancelling")
        then
            local ask_progress, ask_error = ask_step(output, before)
            if ask_progress == nil then return nil, ask_error end
            progressed = progressed or ask_progress
        end
        steps = steps + 1
        local after = admitted.ports.loop:status()
        return assert(freeze({
            events = output,
            status = after,
            progressed = progressed or after.state ~= before.state,
            step = steps,
        }, nil, "Agent activity driver step"))
    end

    ---Returns the driver step counter and current AgentLoop projection.
    --@param none No arguments.
    --@return table status Immutable driver and AgentLoop status.
    function service.status()
        return assert(freeze({
            steps = steps,
            last_now = last_now or false,
            loop = admitted.ports.loop:status(),
        }, nil, "Agent activity driver status"))
    end

    return readonly(service, "Agent activity driver")
end

return M
