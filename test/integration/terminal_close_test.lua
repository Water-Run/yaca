--[[
Author: WaterRun
Date: 2026-10-08
File: terminal_close_test.lua
Description: Verifies terminal adapter close/restore acknowledgment, retained
ownership after native failure and recovery through the same started or joined port.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

-- Load the production terminal adapter with only its fixed text dependency.
--@param none Uses the runner's repository root and standard per-case environment.
--@return table Fresh production terminal module with independent port closures.
--@effect Reads the maintained text.lua and terminal.lua source files.
--@error Raises on source load failure or an unexpected dependency.
local function load_terminal()
    local text = assert(loadfile(YACA_TEST_ROOT .. "/src/text.lua", "t", _ENV))()
    local environment = {}
    for key, value in pairs(_ENV) do environment[key] = value end
    --@metatable terminal_close_environment Resolves inherited runner globals while keeping adapter globals and require local to this copy.
    --@field __index table Original per-case environment used for missing standard functions and runner globals.
    setmetatable(environment, { __index = _ENV })
    -- Resolve only the adapter's text dependency inside the copied environment.
    --@param name string Required module name from the production adapter.
    --@return table The already loaded production text module.
    --@error Raises if the adapter introduces an unbound dependency.
    environment.require = function(name)
        assert(name == "text", "unexpected terminal dependency")
        return text
    end
    environment._G = environment
    return assert(loadfile(YACA_TEST_ROOT .. "/src/terminal.lua", "t", environment))()
end

-- Consume one explicit native result while preserving its exact status/acknowledgment.
--@param results table Mutable sequence of result records; an empty sequence defaults to true/true.
--@return any Exact first status, including malformed values when a fixture requests them.
--@return any Exact acknowledgment/error, including nil for a malformed success acknowledgment.
--@effect Removes the first configured result from the caller-owned fixture sequence.
--@error Raises the fixed native fixture exception when the selected record has throw=true.
local function next_native_result(results)
    local result = table.remove(results, 1) or { ok = true, value = true }
    if result.throw then error("fixed native terminal exception", 0) end
    return result.ok, result.value
end

-- Build a narrow native double retaining actual ownership truth independently of the Lua port state.
--@param restore_results table|nil Restore response sequence, consumed in order; defaults to successful acknowledgments.
--@param close_results table|nil Close response sequence, consumed in order; defaults to successful acknowledgments.
--@param start_now boolean|nil False leaves the adapter created for lifecycle checks; otherwise starts it at tick one.
--@return table Production terminal port constructed against the native double.
--@return table Mutable observations of calls and native restored/closed truth.
--@ownership Each fixture owns its one stable native handle and response queues; failures leave that handle open.
local function new_fixture(restore_results, close_results, start_now)
    restore_results = restore_results or {}
    close_results = close_results or {}
    --@class terminal_close_fixture Native ownership and call observations for one adapter lifecycle.
    --@field handle table Stable opaque native owner returned on start.
    --@field restore_calls integer Number of actual native restoration invocations.
    --@field close_calls integer Number of actual native close invocations.
    --@field poll_calls integer Number of actual native polls used to verify retained usability.
    --@field restored boolean Whether a true/true native restore or close established restored truth.
    --@field closed boolean Whether a true/true native close released ownership.
    --@field cancelled boolean Whether the native double accepted cancellation and can supply its terminal fact.
    local fixture = {
        handle = {}, restore_calls = 0, close_calls = 0, poll_calls = 0,
        restored = false, closed = false, cancelled = false,
    }
    local native = {}

    -- Admit the adapter's request and return the single stable native owner.
    --@param request table Actual mode and byte-limit request from the production adapter.
    --@return boolean True for this bounded fixture's valid startup.
    --@return table Fixture-owned opaque handle retained by the adapter.
    native.terminal_start = function(request)
        A.equal(request.maximum_input_bytes, 32)
        return true, fixture.handle
    end

    -- Return a text observation only while the native owner is actually open.
    --@param handle table Borrowed handle returned by this fixture's start.
    --@param now integer Tick supplied by the production adapter.
    --@param budget integer Positive native event budget supplied by the adapter.
    --@return boolean True when the owner and requested poll are valid.
    --@return table One text action while active, or one cancelled fact after an accepted cancellation.
    --@effect Increments poll_calls without changing native ownership.
    native.terminal_poll = function(handle, now, budget)
        A.equal(handle, fixture.handle)
        A.falsy(fixture.closed)
        A.truthy(math.type(now) == "integer" and budget >= 1)
        fixture.poll_calls = fixture.poll_calls + 1
        if fixture.cancelled then return true, { { kind = "terminal", outcome = "cancelled" } } end
        return true, { { kind = "action", intent = "text", text = "k" } }
    end

    -- Acknowledge a cancellation request without claiming that the owner is closed.
    --@param handle table Borrowed live fixture handle.
    --@param now integer Valid adapter tick; this fixture does not use the value.
    --@return boolean True native status.
    --@return boolean True request acknowledgment, not a close acknowledgment.
    --@effect Sets the double's cancellation truth for a later poll.
    native.terminal_cancel = function(handle, now)
        A.equal(handle, fixture.handle)
        A.falsy(fixture.closed)
        A.equal(math.type(now), "integer")
        fixture.cancelled = true
        return true, true
    end

    -- Supply completed terminal truth so joined-state close retry can be exercised.
    --@param handle table Borrowed open fixture owner.
    --@param deadline integer|nil Adapter deadline, allowed to be omitted.
    --@return boolean True native status.
    --@return table Completed outcome without releasing the handle.
    native.terminal_join = function(handle, deadline)
        A.equal(handle, fixture.handle)
        A.falsy(fixture.closed)
        A.truthy(deadline == nil or math.type(deadline) == "integer")
        return true, { outcome = "completed" }
    end

    -- Consume one restoration outcome and update native truth only after true/true.
    --@param handle table Borrowed open fixture owner retained across rejected attempts.
    --@return any Configured native status.
    --@return any Configured acknowledgment or diagnostic.
    --@effect Increments restore_calls; successful acknowledgment establishes restored=true.
    --@error Raises the configured fixed exception before changing restored truth.
    native.terminal_restore = function(handle)
        A.equal(handle, fixture.handle)
        A.falsy(fixture.closed)
        fixture.restore_calls = fixture.restore_calls + 1
        local ok, value = next_native_result(restore_results)
        if ok == true and value == true then fixture.restored = true end
        return ok, value
    end

    -- Consume one close outcome; the native contract restores and closes together on true/true.
    --@param handle table Borrowed fixture owner that remains open on rejection or malformed acknowledgment.
    --@return any Configured native status.
    --@return any Configured close acknowledgment or diagnostic.
    --@effect Increments close_calls; only true/true sets restored=true and closed=true.
    --@error Raises the configured fixed exception while retaining ownership.
    native.terminal_close = function(handle)
        A.equal(handle, fixture.handle)
        A.falsy(fixture.closed)
        fixture.close_calls = fixture.close_calls + 1
        local ok, value = next_native_result(close_results)
        if ok == true and value == true then
            fixture.restored, fixture.closed = true, true
        end
        return ok, value
    end

    local port = assert(load_terminal().new(native, { mode = "raw", maximum_input_bytes = 32 }))
    if start_now ~= false then port:start(1) end
    return port, fixture
end

-- Require a protected operation to raise the expected typed diagnostic.
--@param method function Actual adapter method invoked under pcall.
--@param port table Adapter owning the started/joined terminal.
--@param code string Required error code at the public adapter boundary.
--@return nil No value; assertions verify an actual rejection and its code.
local function expect_failure(method, port, code)
    local ok, value = pcall(method, port)
    A.falsy(ok)
    A.contains(value, code)
end

return {
    name = "integration/terminal-close",
    cases = {
        {
            name = "restore before start does not skip later native restoration",
            -- Verify restoration of an unstarted port does not describe a later native input generation.
            --@param none Uses a created port before starting its actual fixture owner.
            --@return nil No value; checks that post-start restore invokes native exactly once.
            run = function()
                local port, f = new_fixture(nil, nil, false)
                A.truthy(port:restore())
                A.equal(f.restore_calls, 0)
                port:start(1)
                A.truthy(port:restore())
                A.truthy(f.restored)
                A.equal(f.restore_calls, 1)
                A.truthy(port:close())
            end,
        },
        {
            name = "failed close preserves started owner and permits retry",
            -- Verify rejected close retains ownership while restored input is left unread until cleanup retries.
            --@param none Uses a fresh fixture with one explicit native close rejection.
            --@return nil No value; checks no read from restored input, exact call counts and final release.
            run = function()
                local port, f = new_fixture({}, {
                    { ok = false, value = { code = "CloseRejected", message = "fixed close rejection" } },
                })
                expect_failure(port.close, port, "CloseRejected")
                A.falsy(f.closed)
                A.deep_equal(port:poll(2, 1), {})
                A.equal(f.poll_calls, 0)
                A.truthy(port:close())
                A.truthy(f.closed)
                A.equal(f.restore_calls, 1)
                A.equal(f.close_calls, 2)
            end,
        },
        {
            name = "restored port skips new input but preserves accepted cancellation truth",
            -- Verify restoration never polls a now-blocking input, while cancellation still reaches its native terminal fact.
            --@param none Uses one actual adapter with a native double retaining cancellation truth separately.
            --@return nil No value; checks no pre-cancel read and one post-cancel terminal observation.
            run = function()
                local port, f = new_fixture()
                A.truthy(port:restore())
                A.deep_equal(port:poll(2, 1), {})
                A.equal(f.poll_calls, 0)
                A.truthy(port:cancel(3))
                A.deep_equal(port:poll(4, 1), { { kind = "io_terminal", outcome = "cancelled" } })
                A.equal(f.poll_calls, 1)
                A.truthy(port:close())
            end,
        },
        {
            name = "failed restore and close preserve joined owner for retry",
            -- Verify a joined adapter retains its native owner after both cleanup attempts fail.
            --@param none Uses a fresh fixture with one restore and one close rejection.
            --@return nil No value; checks the original diagnostic and second cleanup's real success.
            run = function()
                local port, f = new_fixture({
                    { ok = false, value = { code = "RestoreRejected", message = "fixed restore rejection" } },
                }, {
                    { ok = false, value = { code = "CloseRejected", message = "fixed close rejection" } },
                })
                A.equal(port:join(2).outcome, "completed")
                expect_failure(port.close, port, "RestoreRejected")
                A.falsy(f.closed)
                A.truthy(port:close())
                A.truthy(f.closed and f.restored)
                A.equal(f.restore_calls, 2)
                A.equal(f.close_calls, 2)
            end,
        },
        {
            name = "native close recovery supersedes an earlier restore rejection",
            -- Verify native close's acknowledged restoration makes the completed cleanup successful.
            --@param none Uses one restore rejection followed by true/true native close.
            --@return nil No value; checks actual closed/restored truth and idempotent restore afterward.
            run = function()
                local port, f = new_fixture({
                    { ok = false, value = { code = "RestoreRejected", message = "fixed restore rejection" } },
                })
                A.truthy(port:close())
                A.truthy(f.closed and f.restored)
                A.truthy(port:restore())
                A.equal(f.restore_calls, 1)
                A.equal(f.close_calls, 1)
            end,
        },
        {
            name = "restore rejects malformed success acknowledgment and remains retryable",
            -- Verify false, nil and table acknowledgments do not establish native restoration truth.
            --@param none Iterates three explicit malformed true-status acknowledgment records.
            --@return nil No value; checks typed rejection and a second actual restoration for every record.
            run = function()
                for _, result in ipairs({ { ok = true, value = false }, { ok = true }, { ok = true, value = {} } }) do
                    local port, f = new_fixture({ result })
                    expect_failure(port.restore, port, "NativeContract")
                    A.falsy(f.restored)
                    A.truthy(port:restore())
                    A.equal(f.restore_calls, 2)
                    A.truthy(port:close())
                end
            end,
        },
        {
            name = "close rejects malformed success acknowledgment and retains owner",
            -- Verify malformed native close acknowledgments cannot mark an open owner closed.
            --@param none Iterates false, nil and table acknowledgments after a valid restore.
            --@return nil No value; checks typed rejection and same-owner close retry without duplicate restore.
            run = function()
                for _, result in ipairs({ { ok = true, value = false }, { ok = true }, { ok = true, value = {} } }) do
                    local port, f = new_fixture({}, { result })
                    expect_failure(port.close, port, "NativeContract")
                    A.falsy(f.closed)
                    A.truthy(port:close())
                    A.equal(f.close_calls, 2)
                    A.equal(f.restore_calls, 1)
                end
            end,
        },
        {
            name = "native close exception preserves ownership until retry",
            -- Verify contained native exceptions do not consume the adapter lifecycle state.
            --@param none Uses one thrown native close exception before a valid close acknowledgment.
            --@return nil No value; checks exception classification and actual final close.
            run = function()
                local port, f = new_fixture({}, { { throw = true } })
                expect_failure(port.close, port, "NativeFailure")
                A.falsy(f.closed)
                A.truthy(port:close())
                A.equal(f.close_calls, 2)
                A.equal(f.restore_calls, 1)
            end,
        },
        {
            name = "restore exception followed by close failure permits both operations to retry",
            -- Verify failed restoration is attempted again when the native close also retains ownership.
            --@param none Uses one restoration exception and one typed close rejection.
            --@return nil No value; checks primary failure preservation and second full cleanup.
            run = function()
                local port, f = new_fixture({ { throw = true } }, {
                    { ok = false, value = { code = "CloseRejected", message = "fixed close rejection" } },
                })
                expect_failure(port.close, port, "NativeFailure")
                A.falsy(f.closed or f.restored)
                A.truthy(port:close())
                A.equal(f.restore_calls, 2)
                A.equal(f.close_calls, 2)
            end,
        },
        {
            name = "acknowledged close recovers from malformed restore acknowledgment",
            -- Verify the actual native close can establish restored/closed truth after a bad preliminary acknowledgment.
            --@param none Uses a true/nil restore response followed by true/true close.
            --@return nil No value; checks final truth and one native invocation per cleanup stage.
            run = function()
                local port, f = new_fixture({ { ok = true } })
                A.truthy(port:close())
                A.truthy(f.closed and f.restored)
                A.equal(f.restore_calls, 1)
                A.equal(f.close_calls, 1)
            end,
        },
    },
}
