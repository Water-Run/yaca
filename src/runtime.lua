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

local function integer_at_least(value, minimum)
  return math.type(value) == "integer" and value >= minimum
end

local function traceback(message)
  return debug.traceback(tostring(message), 2)
end

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

local function new_queue(capacity)
  return {
    capacity = capacity,
    items = {},
    peak = 0,
    coalesced = 0,
    rejected_user_actions = 0,
  }
end

local function event_key(event)
  return event.source .. "\0" .. event.kind .. "\0" .. event.key
end

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

  local function require_lifecycle(expected)
    if lifecycle ~= expected then error("event pump lifecycle is " .. lifecycle .. ", expected " .. expected, 3) end
  end

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
    now = function() return current_now end,
  }
  local reducer_context = setmetatable({}, {
    __index = reducer_context_values,
    __newindex = function(_, key) error("event reducer context cannot be modified: " .. tostring(key), 2) end,
    __metatable = "locked",
  })

  local function dispatch_one()
    local event = queue_pop(queue)
    if not event then return false end
    inside_dispatch = true
    local ok, dispatch_error = xpcall(function() on_event(event, reducer_context) end, traceback)
    inside_dispatch = false
    if not ok then error("event reducer failed: " .. tostring(dispatch_error), 3) end
    dispatched = dispatched + 1
    return true
  end

  local function enqueue(event)
    while true do
      local accepted, reason = queue_push(queue, event)
      if accepted or reason == "coalesced" or reason == "user-action-rejected" then return accepted, reason end
      if reason ~= "drain-required" or not dispatch_one() then error("non-droppable event could not obtain bounded queue capacity", 3) end
      forced_dispatches = forced_dispatches + 1
    end
  end

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

  function pump:tick(now, dispatch_budget)
    require_lifecycle("started")
    if inside_tick then error("event pump tick is not reentrant", 2) end
    if not integer_at_least(now, 0) or now < last_now then error("event pump time must be monotonic", 2) end
    dispatch_budget = dispatch_budget == nil and capacity or dispatch_budget
    if not integer_at_least(dispatch_budget, 0) then error("dispatch budget must be a nonnegative integer", 2) end
    inside_tick, current_now, last_now = true, now, now
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

  function pump:drain(limit)
    require_lifecycle("started")
    if inside_tick then error("event pump drain is not reentrant", 2) end
    if limit ~= nil and not integer_at_least(limit, 0) then error("drain limit must be a nonnegative integer", 2) end
    local consumed = 0
    while (limit == nil or consumed < limit) and dispatch_one() do consumed = consumed + 1 end
    return consumed
  end

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

return M
