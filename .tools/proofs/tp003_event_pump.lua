-- TP-003 modern-host proof: deterministic bounded event pump and fake ports.
--
-- This is deliberately disposable proof code, not a product implementation.

local assertions = 0

local function check(value, message)
  assertions = assertions + 1
  if not value then
    error(("assertion %d failed: %s"):format(assertions, message), 2)
  end
end

local function equal(actual, expected, message)
  check(actual == expected, ("%s (expected=%s actual=%s)"):format(
    message,
    tostring(expected),
    tostring(actual)
  ))
end

local REQUIRED_METHODS = { "start", "poll", "cancel", "join", "close" }
local TERMINAL = {
  completed = true,
  cancelled = true,
  failed = true,
  unknown = true,
}

local FakePort = {}
FakePort.__index = FakePort

function FakePort.new(name, schedule, cancel_truth)
  return setmetatable({
    name = name,
    schedule = schedule,
    cancel_truth = cancel_truth or "cancelled",
    started = false,
    cancelled = false,
    closed = false,
    joined = false,
    cursor = 1,
    terminal_emitted = false,
    cancel_tick = nil,
  }, FakePort)
end

function FakePort:start(now)
  check(not self.started, self.name .. " starts once")
  self.started = true
  self.started_at = now
  return true
end

function FakePort:poll(now, budget)
  check(self.started, self.name .. " poll after start")
  check(not self.closed, self.name .. " poll before close")
  local result = {}

  if self.cancelled and not self.terminal_emitted and now > self.cancel_tick then
    self.terminal_emitted = true
    result[#result + 1] = {
      source = self.name,
      kind = "terminal",
      outcome = self.cancel_truth,
      at = now,
    }
    return result
  end

  while not self.cancelled and #result < budget do
    local item = self.schedule[self.cursor]
    if not item or item.at > now then
      break
    end
    self.cursor = self.cursor + 1
    local event = {
      source = self.name,
      kind = item.kind,
      value = item.value,
      outcome = item.outcome,
      at = now,
      key = item.key,
    }
    if event.kind == "terminal" then
      check(not self.terminal_emitted, self.name .. " has one terminal event")
      self.terminal_emitted = true
    end
    result[#result + 1] = event
  end
  return result
end

function FakePort:cancel(now)
  check(self.started, self.name .. " cancel after start")
  if self.terminal_emitted then
    return false
  end
  if not self.cancelled then
    self.cancelled = true
    self.cancel_tick = now
  end
  return true
end

function FakePort:join()
  self.joined = true
  if self.terminal_emitted then
    return self.cancelled and self.cancel_truth or "completed"
  end
  return "unknown"
end

function FakePort:close()
  self.closed = true
  return true
end

local function progress(at, value, key)
  return { at = at, kind = "progress", value = value, key = key }
end

local function domain(at, value)
  return { at = at, kind = "domain", value = value }
end

local function terminal(at, outcome)
  return { at = at, kind = "terminal", outcome = outcome }
end

local Queue = {}
Queue.__index = Queue

function Queue.new(capacity)
  return setmetatable({
    capacity = capacity,
    items = {},
    peak = 0,
    coalesced = 0,
  }, Queue)
end

local function event_key(event)
  return event.source .. ":" .. (event.key or event.kind)
end

function Queue:_remove_first_progress()
  for i, event in ipairs(self.items) do
    if event.kind == "progress" then
      table.remove(self.items, i)
      self.coalesced = self.coalesced + 1
      return true
    end
  end
  return false
end

function Queue:push(event)
  if event.kind == "progress" then
    local key = event_key(event)
    for i, queued in ipairs(self.items) do
      if queued.kind == "progress" and event_key(queued) == key then
        self.items[i] = event
        self.coalesced = self.coalesced + 1
        return true
      end
    end
  end

  if #self.items == self.capacity then
    if event.kind == "progress" then
      self.coalesced = self.coalesced + 1
      return false
    end
    check(self:_remove_first_progress(), "terminal/domain event has reserved capacity")
  end

  self.items[#self.items + 1] = event
  if #self.items > self.peak then
    self.peak = #self.items
  end
  check(#self.items <= self.capacity, "event queue stays bounded")
  return true
end

function Queue:pop_control_first()
  for i, event in ipairs(self.items) do
    if event.source == "console" and event.value == "cancel-network" then
      return table.remove(self.items, i)
    end
  end
  for i, event in ipairs(self.items) do
    if event.kind == "terminal" then
      return table.remove(self.items, i)
    end
  end
  for i, event in ipairs(self.items) do
    if event.kind ~= "progress" then
      return table.remove(self.items, i)
    end
  end
  return table.remove(self.items, 1)
end

local function contains(list, wanted)
  for _, value in ipairs(list) do
    if value == wanted then
      return true
    end
  end
  return false
end

local function event_pump_scenario()
  local network_schedule = {}
  for tick = 1, 24 do
    network_schedule[#network_schedule + 1] = progress(tick, "sse-" .. tick, "stream")
  end
  network_schedule[#network_schedule + 1] = terminal(25, "completed")

  local process_schedule = {}
  for tick = 1, 13 do
    process_schedule[#process_schedule + 1] = progress(tick, "stdout-" .. tick, "stdout")
    process_schedule[#process_schedule + 1] = progress(tick, "stderr-" .. tick, "stderr")
  end
  process_schedule[#process_schedule + 1] = terminal(14, "completed")

  local ports = {
    FakePort.new("console", {
      domain(2, "draft"),
      domain(4, "cancel-network"),
      terminal(18, "completed"),
    }),
    FakePort.new("network", network_schedule),
    FakePort.new("process", process_schedule),
    FakePort.new("timer", {
      domain(3, "deadline"),
      domain(9, "clock-gap"),
      terminal(10, "completed"),
    }),
    FakePort.new("xml-commit", {
      domain(6, "generation-published"),
      terminal(7, "completed"),
    }),
  }

  for _, port in ipairs(ports) do
    for _, method in ipairs(REQUIRED_METHODS) do
      equal(type(port[method]), "function", port.name .. " exposes " .. method)
    end
    port:start(0)
  end

  local queue = Queue.new(8)
  local trace = {}
  local terminal_counts = {}
  local cancel_seen_at
  local cancel_requested_at
  local domain_owner = "pump"

  local function reduce(event, owner)
    equal(owner, domain_owner, "only pump mutates domain state")
    trace[#trace + 1] = event.source .. ":" .. (event.value or event.outcome or event.kind)
    if event.kind == "terminal" then
      check(TERMINAL[event.outcome], "terminal outcome is typed")
      terminal_counts[event.source] = (terminal_counts[event.source] or 0) + 1
      if event.source == "network" then
        cancel_seen_at = event.at
      end
    elseif event.source == "console" and event.value == "cancel-network" then
      cancel_requested_at = event.at
      check(ports[2]:cancel(event.at), "network cancel admitted")
    end
  end

  for tick = 1, 32 do
    -- Round-robin with a fixed per-source budget. No source may monopolize a tick.
    for _, port in ipairs(ports) do
      for _, event in ipairs(port:poll(tick, 2)) do
        queue:push(event)
      end
    end

    -- A deliberately slow renderer/domain consumer creates backpressure.
    -- Control/domain/terminal events are selected before coalescible progress.
    if tick % 3 == 0 or tick == 4 or tick >= 18 then
      local event = queue:pop_control_first()
      if event then
        reduce(event, "pump")
      end
    end
  end

  while #queue.items > 0 do
    reduce(queue:pop_control_first(), "pump")
  end

  equal(cancel_requested_at, 4, "busy input observed at scheduled tick")
  equal(cancel_seen_at, 5, "cancel terminal truth observed one tick later")
  for _, source in ipairs({ "console", "network", "process", "timer", "xml-commit" }) do
    equal(terminal_counts[source], 1, source .. " terminal event is unique and not dropped")
  end
  check(contains(trace, "timer:clock-gap"), "clock gap becomes an explicit domain event")
  check(contains(trace, "xml-commit:generation-published"), "XML completion is not starved")
  check(contains(trace, "process:completed"), "slow process reaches its terminal event")
  check(queue.coalesced > 0, "slow consumer causes explicit progress coalescing")
  check(queue.peak <= queue.capacity, "queue peak respects capacity")

  for _, port in ipairs(ports) do
    local joined = port:join()
    check(TERMINAL[joined], port.name .. " join returns terminal truth")
    port:close()
    check(port.closed, port.name .. " closes")
  end

  return {
    peak = queue.peak,
    capacity = queue.capacity,
    coalesced = queue.coalesced,
    cancel_latency = cancel_seen_at - cancel_requested_at,
  }
end

local function terminal_truth_scenario()
  local expected = { "completed", "cancelled", "failed", "unknown" }
  local observed = {}
  for index, outcome in ipairs(expected) do
    local port = FakePort.new("truth-" .. outcome, { terminal(1, outcome) })
    port:start(0)
    local events = port:poll(1, 2)
    equal(#events, 1, outcome .. " produces one event")
    equal(events[1].outcome, outcome, outcome .. " is not rewritten")
    observed[index] = events[1].outcome
    port:close()
  end
  equal(table.concat(observed, ","), table.concat(expected, ","), "all terminal truths survive")
  return table.concat(observed, ",")
end

local function context_name_scenario()
  local scheduler = {
    interval = 2,
    waterline = 0,
    baseline = 0,
    marker = nil,
    queued = 0,
    started = 0,
    cost = 0,
    inflight = false,
    cancelled = 0,
    joined_on_exit = 0,
    priorities = { main = 1, side = 2, review = 3, ["context-name"] = 4 },
  }

  local function due()
    return scheduler.interval > 0
      and scheduler.marker ~= true
      and scheduler.waterline - scheduler.baseline >= scheduler.interval
  end

  local function commit_main()
    scheduler.waterline = scheduler.waterline + 1
    if scheduler.inflight then
      scheduler.inflight = false
      scheduler.cancelled = scheduler.cancelled + 1
      scheduler.baseline = scheduler.waterline
    elseif due() then
      scheduler.queued = 1
    end
  end

  local function set_marker(value)
    local was_true = scheduler.marker == true
    scheduler.marker = value
    if was_true and value ~= true then
      scheduler.baseline = scheduler.waterline
      scheduler.queued = 0
    elseif value == true then
      scheduler.queued = 0
      if scheduler.inflight then
        scheduler.inflight = false
        scheduler.cancelled = scheduler.cancelled + 1
      end
    end
  end

  local function dispatch(ready)
    if scheduler.queued == 0 then
      return nil
    end
    for _, higher in ipairs({ "main", "side", "review" }) do
      if ready[higher] then
        return higher
      end
    end
    scheduler.queued = 0
    scheduler.inflight = true
    scheduler.started = scheduler.started + 1
    scheduler.cost = scheduler.cost + 1
    return "context-name"
  end

  -- marker missing behaves as enabled.
  commit_main()
  equal(scheduler.queued, 0, "missing marker waits for interval")
  commit_main()
  equal(scheduler.queued, 1, "missing marker admits at durable waterline")
  equal(dispatch({ main = true }), "main", "context-name never preempts main")
  equal(scheduler.queued, 1, "low-priority work remains queued")
  equal(dispatch({ side = true }), "side", "context-name never preempts side")
  equal(dispatch({ review = true }), "review", "context-name never preempts review")
  equal(dispatch({}), "context-name", "context-name starts only when higher priorities are absent")

  -- New durable main work cancels an in-flight naming request and creates a baseline.
  commit_main()
  equal(scheduler.cancelled, 1, "new main cancels in-flight naming")
  equal(scheduler.baseline, scheduler.waterline, "cancel creates a new baseline")
  equal(scheduler.queued, 0, "cancel does not immediately requeue")

  -- A true marker is zero queue and zero cost even across many intervals.
  set_marker(true)
  local cost_before_disabled = scheduler.cost
  for _ = 1, 7 do
    commit_main()
  end
  equal(scheduler.queued, 0, "true marker creates zero queued naming work")
  equal(scheduler.cost, cost_before_disabled, "true marker creates zero naming cost")
  local disabled_cost = scheduler.cost - cost_before_disabled

  -- Removing the marker establishes a fresh baseline; it never catches up.
  set_marker(false)
  equal(scheduler.baseline, scheduler.waterline, "marker removal establishes fresh baseline")
  commit_main()
  equal(scheduler.queued, 0, "first post-enable main does not catch up")
  commit_main()
  equal(scheduler.queued, 1, "new full interval admits naming")
  equal(dispatch({}), "context-name", "false marker permits naming")

  -- Exit cancels but deliberately does not join low-priority naming.
  if scheduler.inflight then
    scheduler.inflight = false
    scheduler.cancelled = scheduler.cancelled + 1
  end
  equal(scheduler.joined_on_exit, 0, "exit does not wait for context-name join")
  check(not scheduler.inflight, "no ghost naming request after exit")

  return {
    started = scheduler.started,
    cancelled = scheduler.cancelled,
    disabled_cost = disabled_cost,
    joined_on_exit = scheduler.joined_on_exit,
  }
end

local function zero_surface_scenario()
  local registered = {
    "console-input",
    "curl-stdout",
    "curl-stderr",
    "tool-process",
    "timer",
    "xml-commit",
    "context-name",
  }
  local forbidden = {
    "web", "listener", "remote", "image", "audio", "capture", "codec",
    "transcription", "speech", "telemetry", "upload", "update", "second-context",
    "root-list", "root-alias", "root-selector",
  }
  local hits = 0
  for _, worker in ipairs(registered) do
    local lowered = worker:lower()
    for _, token in ipairs(forbidden) do
      if lowered:find(token, 1, true) then
        hits = hits + 1
      end
    end
  end
  equal(hits, 0, "excluded worker/queue registry stays empty")
  return #registered, hits
end

local pump = event_pump_scenario()
local truths = terminal_truth_scenario()
local naming = context_name_scenario()
local registered, excluded = zero_surface_scenario()

print("proof=TP-003")
print("scope=modern-host-deterministic-fake-ports")
print("lua=" .. _VERSION)
print(("queue_peak=%d/%d"):format(pump.peak, pump.capacity))
print("progress_coalesced=" .. pump.coalesced)
print("cancel_latency_ticks=" .. pump.cancel_latency)
print("terminal_outcomes=" .. truths)
print(("context_name=started:%d,cancelled:%d,disabled_cost:%d,exit_joins:%d"):format(
  naming.started,
  naming.cancelled,
  naming.disabled_cost,
  naming.joined_on_exit
))
print(("worker_registry=registered:%d,excluded_hits:%d"):format(registered, excluded))
print("assertions=" .. assertions)
print("status=PASS")
