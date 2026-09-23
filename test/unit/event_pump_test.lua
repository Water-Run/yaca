--[[
Author: WaterRun
Date: 2026-09-23
File: event_pump_test.lua
Description: Verifies bounded event delivery, cancellation, and clock behavior.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()
local manifest = assert(loadfile(YACA_TEST_ROOT .. "/release/manifest.lua", "t", _ENV))()
local loader_module = assert(loadfile(YACA_TEST_ROOT .. "/.tools/check_loader.lua", "t", _ENV))()
local secure_loader = assert(loader_module.new(manifest, YACA_TEST_ROOT))
local runtime = secure_loader:require_lua("runtime")
local clock = secure_loader:require_lua("clock")

local TERMINAL = { completed = true, cancelled = true, failed = true, unknown = true }

local FakePort = {}
FakePort.__index = FakePort

--Constructs the new service used by this suite.
--@param schedule any The schedule supplied to the fake service for this scenario.
--@param cancel_outcome string Configured cancellation outcome.
--@return any observed new value observed by the scenario assertion.
function FakePort.new(schedule, cancel_outcome)
    --@metatable fixture_view Test-owned lookup and mutation contract for the current case.
    return setmetatable({
        schedule = schedule or {},
        cancel_outcome = cancel_outcome or "cancelled",
        cursor = 1,
        started = false,
        cancelled = false,
        terminal = nil,
        cancel_tick = nil,
    }, FakePort)
end

--Simulates the start transition of a fake activity port for this suite.
--@param self table Fixture or port instance receiving this call.
--@param now integer Monotonic timestamp supplied by the fake clock.
--@return boolean accepted Whether start succeeds in the fixture.
function FakePort:start(now)
    A.falsy(self.started)
    self.started, self.started_at = true, now
    return true
end

--Simulates the poll transition of a fake activity port for this suite.
--@param self table Fixture or port instance receiving this call.
--@param now integer Monotonic timestamp supplied by the fake clock.
--@param budget integer|table Resource budget applied by the scenario.
--@return any observed poll value observed by the scenario assertion.
function FakePort:poll(now, budget)
    A.truthy(self.started)
    local events = {}
    if self.cancelled and not self.terminal and now > self.cancel_tick then
        self.terminal = self.cancel_outcome
        events[1] = { kind = "io_terminal", outcome = self.cancel_outcome, at = now }
        return events
    end
    while not self.cancelled and #events < budget do
        local scheduled = self.schedule[self.cursor]
        if not scheduled or scheduled.at > now then break end
        self.cursor = self.cursor + 1
        local event = {}
        for key, value in pairs(scheduled) do if key ~= "at" then event[key] = value end end
        event.at = now
        if event.kind == "io_terminal" then self.terminal = event.outcome end
        events[#events + 1] = event
    end
    return events
end

--Simulates the cancel transition of a fake activity port for this suite.
--@param self table Fixture or port instance receiving this call.
--@param now integer Monotonic timestamp supplied by the fake clock.
--@return boolean accepted Whether cancel succeeds in the fixture.
function FakePort:cancel(now)
    if self.terminal then return false end
    if not self.cancelled then self.cancelled, self.cancel_tick = true, now end
    return true
end

--Simulates the join transition of a fake activity port for this suite.
--@param self table Fixture or port instance receiving this call.
--@return any observed join value observed by the scenario assertion.
function FakePort:join()
    return self.terminal or "unknown"
end

--Simulates the close transition of a fake activity port for this suite.
--@param self table Fixture or port instance receiving this call.
--@return boolean accepted Whether close succeeds in the fixture.
function FakePort:close()
    self.closed = true
    return true
end

--Supplies progress behavior required by this suite.
--@param at any The at supplied to the fake service for this scenario.
--@param key string|integer Lookup key selected by the operation.
--@param value any Candidate whose acceptance or transformation the test checks.
--@return table observed Structured fixture record with at, kind, key, value.
local function progress(at, key, value)
    return { at = at, kind = "io_progress", key = key, value = value }
end

--Supplies terminal behavior required by this suite.
--@param at any The at supplied to the fake service for this scenario.
--@param outcome string Expected terminal outcome.
--@return table observed Structured fixture record with at, kind, outcome.
local function terminal(at, outcome)
    return { at = at, kind = "io_terminal", outcome = outcome }
end

return {
    name = "unit/event-pump",
    cases = {
        {
            name = "bounded pump preserves terminal and durable facts under slow consumption",
            --Verifies bounded pump preserves terminal and durable facts under slow consumption.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify bounded pump preserves terminal and durable facts under slow consumption.
            run = function()
                local network_schedule = {}
                for tick = 1, 24 do network_schedule[#network_schedule + 1] = progress(tick, "stream", "sse-" .. tick) end
                network_schedule[#network_schedule + 1] = terminal(25, "completed")
                local process_schedule = {}
                for tick = 1, 13 do
                    process_schedule[#process_schedule + 1] = progress(tick, "stdout", "out-" .. tick)
                    process_schedule[#process_schedule + 1] = progress(tick, "stderr", "err-" .. tick)
                end
                process_schedule[#process_schedule + 1] = terminal(14, "completed")

                local ports = {
                    console = FakePort.new({
                        { at = 2, kind = "user_action", action = "draft" },
                        { at = 4, kind = "user_action", action = "cancel-network" },
                        terminal(18, "completed"),
                    }),
                    network = FakePort.new(network_schedule),
                    process = FakePort.new(process_schedule),
                    timer = FakePort.new({
                        { at = 3, kind = "timer", key = "deadline", value = "deadline" },
                        { at = 9, kind = "timer", key = "clock-gap", value = "clock-gap" },
                        terminal(10, "completed"),
                    }),
                    xml = FakePort.new({
                        { at = 6, kind = "durable_barrier", value = "generation-published" },
                        terminal(7, "completed"),
                    }),
                }

                local trace, terminal_counts = {}, {}
                local cancel_requested_at, cancel_seen_at
                local pump = assert(runtime.new_event_pump({
                    capacity = 8,
                    per_port_budget = 2,
                    --Records the event callback behavior exercised by the 'bounded pump preserves terminal and durable facts under slow consumption' case.
                    --@param event table Event delivered to the fake runtime.
                    --@param context table Context owner or document under test.
                    --@return nil No value; assertions verify bounded pump preserves terminal and durable facts under slow consumption.
                    on_event = function(event, context)
                        trace[#trace + 1] = event.source .. ":" .. tostring(event.action or event.value or event.outcome)
                        if event.kind == "user_action" and event.action == "cancel-network" then
                            cancel_requested_at = context.now()
                            A.truthy(context.cancel("network"))
                        elseif event.kind == "io_terminal" then
                            terminal_counts[event.source] = (terminal_counts[event.source] or 0) + 1
                            if event.source == "network" then cancel_seen_at = event.at end
                        end
                    end,
                }))
                for _, id in ipairs({ "console", "network", "process", "timer", "xml" }) do pump:register(id, ports[id]) end
                pump:start(0)
                for tick = 1, 32 do
                    local budget = (tick % 3 == 0 or tick == 4 or tick >= 18) and 1 or 0
                    pump:tick(tick, budget)
                end
                pump:drain()

                A.equal(cancel_requested_at, 4)
                A.equal(cancel_seen_at, 5)
                for _, source in ipairs({ "console", "network", "process", "timer", "xml" }) do A.equal(terminal_counts[source], 1, source) end
                local joined = pump:join(40)
                A.equal(joined.network, "cancelled")
                A.equal(joined.process, "completed")
                A.truthy(TERMINAL[joined.console])
                pump:close()
                local stats = pump:stats()
                A.truthy(stats.coalesced > 0)
                A.truthy(stats.peak <= stats.capacity)
                A.equal(stats.cancel_requests, 1)
                A.equal(stats.lifecycle, "closed")
                local joined_trace = table.concat(trace, "\n")
                A.contains(joined_trace, "timer:clock-gap")
                A.contains(joined_trace, "xml:generation-published")
                A.contains(joined_trace, "process:completed")
            end,
        },
        {
            name = "all terminal truths survive without rewriting",
            --Verifies all terminal truths survive without rewriting.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify all terminal truths survive without rewriting.
            run = function()
                local observed = {}
                local pump = assert(runtime.new_event_pump({
                    capacity = 4,
                    per_port_budget = 1,
                    --Records the event callback behavior exercised by the 'all terminal truths survive without rewriting' case.
                    --@param event table Event delivered to the fake runtime.
                    --@return nil No value; assertions verify all terminal truths survive without rewriting.
                    on_event = function(event) observed[event.source] = event.outcome end,
                }))
                for _, outcome in ipairs({ "completed", "cancelled", "failed", "unknown" }) do
                    pump:register(outcome, FakePort.new({ terminal(1, outcome) }))
                end
                pump:start(0)
                pump:tick(1, 4)
                for _, outcome in ipairs({ "completed", "cancelled", "failed", "unknown" }) do A.equal(observed[outcome], outcome) end
                pump:join(2)
                pump:close()
            end,
        },
        {
            name = "queue rejects excess user actions but forces space for durable facts",
            --Verifies all terminal truths survive without rewriting.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify all terminal truths survive without rewriting.
            run = function()
                local observed = {}
                local port = FakePort.new({
                    { at = 1, kind = "user_action", action = "one" },
                    { at = 1, kind = "user_action", action = "two" },
                    { at = 1, kind = "user_action", action = "three" },
                    { at = 1, kind = "durable_barrier", value = "committed" },
                    terminal(2, "completed"),
                })
                local pump = assert(runtime.new_event_pump({
                    capacity = 2,
                    per_port_budget = 2,
                    --Records the event callback behavior exercised by the 'queue rejects excess user actions but forces space for durable facts' case.
                    --@param event table Event delivered to the fake runtime.
                    --@return nil No value; assertions verify all terminal truths survive without rewriting.
                    on_event = function(event) observed[#observed + 1] = event.action or event.value or event.outcome end,
                }))
                pump:register("source", port)
                pump:start(0)
                pump:tick(1, 0)
                pump:tick(1, 0)
                pump:drain()
                pump:tick(2, 1)
                A.equal(pump:stats().rejected_user_actions, 1)
                A.contains(table.concat(observed, ","), "committed")
                pump:join(3)
                pump:close()
            end,
        },
        {
            name = "port schemas budgets terminal uniqueness and reducer ownership are enforced",
            --Verifies port schemas budgets terminal uniqueness and reducer ownership are enforced.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify port schemas budgets terminal uniqueness and reducer ownership are enforced.
            run = function()
                local invalid = assert(runtime.new_event_pump({ capacity = 2, per_port_budget = 1,
                    --Records the event callback behavior exercised by the 'port schemas budgets terminal uniqueness and reducer ownership are enforced' case.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return nil No value; assertions verify port schemas budgets terminal uniqueness and reducer ownership are enforced.
                    on_event = function() end }))
                --Simulates the start transition of a fake activity port for the 'port schemas budgets terminal uniqueness and reducer ownership are enforced' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify port schemas budgets terminal uniqueness and reducer ownership are enforced.
                A.raises(function() invalid:register("bad", {
                    --Simulates the start transition of a fake activity port for the 'port schemas budgets terminal uniqueness and reducer ownership are enforced' case.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return nil No value; assertions verify port schemas budgets terminal uniqueness and reducer ownership are enforced.
                    start = function() end }) end, "omits poll")

                local duplicate = FakePort.new({ terminal(1, "completed"), terminal(1, "completed") })
                local duplicate_pump = assert(runtime.new_event_pump({ capacity = 2, per_port_budget = 2,
                    --Records the event callback behavior exercised by the 'port schemas budgets terminal uniqueness and reducer ownership are enforced' case.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return nil No value; assertions verify port schemas budgets terminal uniqueness and reducer ownership are enforced.
                    on_event = function() end }))
                duplicate_pump:register("duplicate", duplicate)
                duplicate_pump:start(0)
                --Executes the action expected to raise in the 'port schemas budgets terminal uniqueness and reducer ownership are enforced' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify port schemas budgets terminal uniqueness and reducer ownership are enforced.
                A.raises(function() duplicate_pump:tick(1, 0) end, "duplicate terminal")

                local owner_pump
                owner_pump = assert(runtime.new_event_pump({
                    capacity = 1,
                    per_port_budget = 1,
                    --Records the event callback behavior exercised by the 'port schemas budgets terminal uniqueness and reducer ownership are enforced' case.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return nil No value; assertions verify port schemas budgets terminal uniqueness and reducer ownership are enforced.
                    on_event = function() owner_pump:tick(1, 0) end,
                }))
                owner_pump:register("owner", FakePort.new({ { at = 1, kind = "user_action", action = "reenter" } }))
                owner_pump:start(0)
                --Executes the action expected to raise in the 'port schemas budgets terminal uniqueness and reducer ownership are enforced' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify port schemas budgets terminal uniqueness and reducer ownership are enforced.
                A.raises(function() owner_pump:tick(1, 1) end, "not reentrant")
                --Executes the action expected to raise in the 'port schemas budgets terminal uniqueness and reducer ownership are enforced' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify port schemas budgets terminal uniqueness and reducer ownership are enforced.
                A.raises(function() owner_pump:tick(-1, 0) end, "monotonic")

                local retained_context
                local context_pump = assert(runtime.new_event_pump({
                    capacity = 1,
                    per_port_budget = 1,
                    --Records the event callback behavior exercised by the 'port schemas budgets terminal uniqueness and reducer ownership are enforced' case.
                    --@param _ any Unused callback argument supplied by the port.
                    --@param context table Context owner or document under test.
                    --@return nil No value; assertions verify port schemas budgets terminal uniqueness and reducer ownership are enforced.
                    on_event = function(_, context) retained_context = context end,
                }))
                context_pump:register("context", FakePort.new({ { at = 1, kind = "user_action", action = "retain" } }))
                context_pump:start(0)
                context_pump:tick(1, 1)
                --Executes the action expected to raise in the 'port schemas budgets terminal uniqueness and reducer ownership are enforced' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify port schemas budgets terminal uniqueness and reducer ownership are enforced.
                A.raises(function() retained_context.cancel("context") end, "admitted by the event reducer")
                --Executes the action expected to raise in the 'port schemas budgets terminal uniqueness and reducer ownership are enforced' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify port schemas budgets terminal uniqueness and reducer ownership are enforced.
                A.raises(function() retained_context.now = false end, "cannot be modified")

                local excessive = FakePort.new({})
                --Simulates the poll transition of a fake activity port for the 'port schemas budgets terminal uniqueness and reducer ownership are enforced' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return table record Fixture record emitted by the scenario callback.
                excessive.poll = function()
                    return {
                        { kind = "io_progress", key = "one" },
                        { kind = "io_progress", key = "two" },
                    }
                end
                local budget_pump = assert(runtime.new_event_pump({ capacity = 2, per_port_budget = 1,
                    --Records the event callback behavior exercised by the 'port schemas budgets terminal uniqueness and reducer ownership are enforced' case.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return nil No value; assertions verify port schemas budgets terminal uniqueness and reducer ownership are enforced.
                    on_event = function() end }))
                budget_pump:register("excessive", excessive)
                budget_pump:start(0)
                --Executes the action expected to raise in the 'port schemas budgets terminal uniqueness and reducer ownership are enforced' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify port schemas budgets terminal uniqueness and reducer ownership are enforced.
                A.raises(function() budget_pump:tick(1, 0) end, "exceeded its per-tick event budget")
            end,
        },
        {
            name = "join cannot contradict an emitted terminal truth",
            --Verifies join cannot contradict an emitted terminal truth.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify join cannot contradict an emitted terminal truth.
            run = function()
                local port = FakePort.new({ terminal(1, "completed") })
                --Simulates join in the join cannot contradict an emitted terminal truth fixture.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return string text Text emitted by the scenario callback.
                port.join = function() return "failed" end
                local pump = assert(runtime.new_event_pump({ capacity = 1, per_port_budget = 1,
                    --Records the event callback behavior exercised by the 'join cannot contradict an emitted terminal truth' case.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return nil No value; the fake port or test assertion observes this callback's effects.
                    on_event = function() end }))
                pump:register("contradiction", port)
                pump:start(0)
                pump:tick(1, 1)
                --Executes the action expected to raise in the 'join cannot contradict an emitted terminal truth' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; the fake port or test assertion observes this callback's effects.
                A.raises(function() pump:join(2) end, "contradicted its terminal event")
            end,
        },
        {
            name = "clock deadlines use monotonic time and degradation is sticky",
            --Verifies join cannot contradict an emitted terminal truth.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify join cannot contradict an emitted terminal truth.
            run = function()
                local ticks = { 10, 12, 11, 50 }
                local cursor = 0
                local service = assert(clock.new({
                    --Supplies deterministic clock behavior for the 'clock deadlines use monotonic time and degradation is sticky' case.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return any value Callback value consumed by the enclosing scenario assertion.
                    monotonic_now = function()
                        cursor = cursor + 1
                        return ticks[cursor]
                    end,
                    --Supplies deterministic clock behavior for the 'clock deadlines use monotonic time and degradation is sticky' case.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return string text Text emitted by the scenario callback.
                    utc_now = function() return "2026-08-29T08:00:00Z" end,
                }))
                local deadline = assert(service.deadline(5))
                A.equal(deadline.at, 15)
                A.falsy(service.expired(deadline))
                local value, clock_error = service.monotonic_now()
                A.falsy(value)
                A.equal(clock_error.code, "MonotonicClockDegraded")
                A.equal(service.status(), "degraded")
                local again, same_error = service.monotonic_now()
                A.falsy(again)
                A.equal(same_error, clock_error)
                A.equal(cursor, 3)
                A.equal(service.utc_now(), "2026-08-29T08:00:00Z")
                --Executes the action expected to raise in the 'clock deadlines use monotonic time and degradation is sticky' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify join cannot contradict an emitted terminal truth.
                A.raises(function() deadline.at = 99 end, "cannot be modified")
            end,
        },
    },
}
