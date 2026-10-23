--[[
Author: WaterRun
Date: 2026-10-23
File: chat_input_test.lua
Description: Checks production chat input selection, editing, bounded submission, paste and draft-preserving output.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

-- Load terminal and its sole text dependency in one isolated module environment.
--@param none Uses the test runner's repository root.
--@return table Fresh terminal module with no native resources.
--@error Raises if a source cannot load or an unexpected dependency appears.
local function load_terminal()
    local environment = {}
    for key, value in pairs(_ENV) do environment[key] = value end
    --@metatable chat_test_environment Resolves standard globals through the test sandbox without writing to it.
    --@field __index table Existing isolated test environment used for inherited globals.
    setmetatable(environment, { __index = _ENV })
    local text = assert(loadfile(YACA_TEST_ROOT .. "/src/text.lua", "t", _ENV))()
    -- Return the fixed text implementation to the terminal module.
    --@param name string Requested dependency name.
    --@return table Production text module.
    --@error Raises for dependencies outside this fixture's module boundary.
    environment.require = function(name) assert(name == "text"); return text end
    return assert(loadfile(YACA_TEST_ROOT .. "/src/terminal.lua", "t", environment))()
end

-- Construct a chat port with queued native byte observations and a recording output sink.
--@param kind string|nil Native display kind; defaults to ansi, cooked exercises fallback.
--@return table Fixture containing port, display, writes, native inputs and lifecycle observations.
--@error Raises on construction or initial native admission failure.
local function fixture(kind)
    local f = { inputs = {}, writes = {}, now = 0, restored = false, closed = false, columns = 40 }
    local native = {}
    -- Observe the current fixture width without changing input state.
    --@param none Uses the fixture's display profile and mutable width.
    --@return table Native-style display facts.
    function native.terminal_display_info() return { kind = kind or "ansi", columns = f.columns } end
    -- Retain the actual native request for automatic mode-selection assertions.
    --@param request table Mode, byte cap and editor flags from the production adapter.
    --@return boolean True for a successful fixture start.
    --@return table Stable fake handle.
    function native.terminal_start(request) f.request = request; return true, f end
    -- Deliver one queued text chunk or the settled cancellation outcome.
    --@param handle table Stable fake handle.
    --@param now integer Monotonic test tick.
    --@param budget integer Native observation budget, always positive here.
    --@return boolean True after reading the fixture queue.
    --@return table Zero or one observation.
    --@effect Removes at most one queued input chunk.
    function native.terminal_poll(handle, now, budget)
        A.equal(handle, f)
        if f.cancelled then return true, { { kind = "terminal", outcome = "cancelled" } } end
        local bytes = table.remove(f.inputs, 1)
        return true, bytes and { { kind = "action", intent = "text", text = bytes } } or {}
    end
    -- Mark this fixture's input owner cancelled.
    --@param handle table Stable fake handle.
    --@param now integer Cancellation tick.
    --@return boolean True native call status.
    --@return boolean True cancellation acknowledgment.
    --@effect Enables the fixture's terminal outcome on the next poll.
    function native.terminal_cancel(handle, now) f.cancelled = true; return true, true end
    -- Join only the fixture owner whose cancellation was requested.
    --@param handle table Stable fake handle.
    --@param deadline integer Monotonic join deadline.
    --@return boolean True native call status.
    --@return table Settled cancellation outcome.
    function native.terminal_join(handle, deadline) return true, { outcome = "cancelled" } end
    -- Record native restoration independently of the display writer.
    --@param handle table Stable fake handle.
    --@return boolean True native call status.
    --@return boolean True restoration acknowledgment.
    --@effect Marks the fixture's terminal modes restored.
    function native.terminal_restore(handle) f.restored = true; return true, true end
    -- Release the fake input owner.
    --@param handle table Stable fake handle.
    --@return boolean True native call status.
    --@return boolean True close acknowledgment.
    --@effect Marks the fixture closed and restored.
    function native.terminal_close(handle) f.closed = true; f.restored = true; return true, true end
    local terminal = load_terminal()
    f.port, f.error, f.display = terminal.new_chat(native, {
        maximum_input_bytes = 256, completion_words = ".status\n.stop\n.help",
        -- Collect one complete output frame or inject a sink failure.
        --@param bytes string Frame accepted by the production editor.
        --@return boolean True on success, false when output failure is injected.
        --@effect Appends frame bytes only on success.
        writer = function(bytes)
            if f.fail_output then return false end
            f.writes[#f.writes + 1] = bytes
            return true
        end,
        -- Resolve candidates from a fixed two-way ambiguous command catalog.
        --@param prefix string Draft prefix submitted to completion.
        --@return table Sorted candidates whose prefixes match.
        complete = function(prefix)
            local matches = {}
            for _, value in ipairs({ ".help", ".status", ".stop" }) do
                if value:sub(1, #prefix) == prefix then matches[#matches + 1] = value end
            end
            return matches
        end,
    })
    A.truthy(f.port, f.error and f.error.message)
    f.port:start(0)
    if f.display then f.display:prompt(">> ") end
    return f
end

-- Feed one raw chunk and collect a bounded number of subsequent semantic events.
--@param f table Chat input fixture.
--@param bytes string Raw input bytes, possibly a split escape or UTF-8 sequence.
--@param budget integer|nil Per-poll semantic event cap; defaults to one.
--@return table Collected events in their actual delivery order.
--@effect Advances the fake clock and drains the queued input through the production port.
local function feed(f, bytes, budget)
    for offset = 1, #bytes, f.request.maximum_input_bytes do
        f.inputs[#f.inputs + 1] = bytes:sub(offset, offset + f.request.maximum_input_bytes - 1)
    end
    local events = {}
    for _ = 1, 8 do
        f.now = f.now + 1
        local batch = f.port:poll(f.now, budget or 1)
        A.truthy(#batch <= (budget or 1))
        for _, event in ipairs(batch) do events[#events + 1] = event end
    end
    return events
end

-- Close a started fixture through the normal cancellation and join protocol.
--@param f table Chat fixture retaining one started native handle.
--@return nil No result; assertions verify release and display reset.
--@effect Cancels, polls, joins, restores and closes the owned fixture port.
local function close(f)
    f.port:cancel(f.now)
    f.port:poll(f.now, 4)
    f.port:join(f.now + 100)
    f.port:restore()
    f.port:close()
    A.truthy(f.restored)
    A.truthy(f.closed)
end

return {
    name = "integration/chat-input",
    cases = {
        {
            name = "automatic raw editing completes commands and recalls history without duplicate submissions",
            -- Exercise editing through native byte observations with a one-event dispatch budget.
            --@param none Starts a capable terminal and sends completion, recall and middle insertion.
            --@return nil Assertions require exact submitted text and default raw/editor mode.
            run = function()
                local f = fixture()
                A.equal(f.request.mode, "raw")
                A.equal(f.request.editor_mode, true)
                local events = feed(f, ".staX\127\t\r\n")
                A.equal(#events, 2)
                A.equal(events[1].text, ".status")
                A.equal(events[2].action, "submit-or-queue")
                events = feed(f, "\27[A\r")
                A.equal(events[1].text, ".status")
                events = feed(f, "ab\27[D中\27[C\r")
                A.equal(events[1].text, "a中b")
                close(f)
            end,
        },
        {
            name = "asynchronous output preserves UTF-8 draft and cursor and cannot submit it",
            -- Hold a draft in the middle while model output arrives.
            --@param none Splits a Unicode scalar across native reads, then inserts at a retained cursor.
            --@return nil Assertions require zero premature actions and the exact final submission.
            run = function()
                local f = fixture()
                A.equal(#feed(f, "a\228"), 0)
                A.equal(#feed(f, "\184\173b\27[D"), 0)
                f.display:output("[ASSISTANT]\nbackground output\n")
                A.contains(f.writes[#f.writes], "background output\n>> a中")
                local events = feed(f, "X\r")
                A.equal(events[1].text, "a中Xb")
                close(f)
            end,
        },
        {
            name = "bracketed paste keeps embedded Enter Escape and backspace as data until submission",
            -- Pasted bytes must not turn embedded commands into interactive actions.
            --@param none Splits both paste markers and UTF-8 before the final user Enter.
            --@return nil Assertions require a single exact submitted draft and no earlier actions.
            run = function()
                local f = fixture()
                A.equal(#feed(f, "\27[20"), 0)
                A.equal(#feed(f, "0~.quit\n中\8\27[A\t\27[20"), 0)
                A.equal(#feed(f, "1~"), 0)
                local events = feed(f, "\r")
                A.equal(#events, 2)
                A.equal(events[1].text, ".quit\n中\8\27[A\t")
                close(f)
            end,
        },
        {
            name = "ambiguous completion is visible and Ctrl-C clears input before cancelling the agent",
            -- Completion feedback must not execute a command or discard the draft.
            --@param none Uses .st ambiguity and two successive cancellation gestures.
            --@return nil Assertions require candidate output, cleared input, then one cancel action.
            run = function()
                local f = fixture()
                A.equal(#feed(f, ".st\t"), 0)
                A.contains(table.concat(f.writes), ".status  .stop\n")
                A.equal(#feed(f, "\3"), 0)
                local events = feed(f, "\3")
                A.equal(events[1].action, "cancel")
                A.equal(#events, 1)
                close(f)
            end,
        },
        {
            name = "oversized paste is rejected without submitting a partial command or closing the session",
            -- The byte cap must protect the session without turning a truncated paste into an action.
            --@param none Pastes a command-shaped draft above the fixture limit, then submits a valid command.
            --@return nil Assertions require a visible rejection and only the later exact command text.
            run = function()
                local f = fixture()
                A.equal(#feed(f, "\27[200~.quit " .. string.rep("x", 300) .. "\n.status\27[201~"), 0)
                A.contains(table.concat(f.writes), "Input was rejected (DraftLimit)")
                local events = feed(f, ".help\r")
                A.equal(#events, 2)
                A.equal(events[1].text, ".help")
                close(f)
            end,
        },
        {
            name = "unsupported terminals retain cooked input and output failure still restores native state",
            -- Automatic enhancement must preserve the ordinary fallback and cleanup ownership.
            --@param none Uses a cooked profile and a separate enhanced profile with a failing stdout sink.
            --@return nil Assertions require no ANSI output for fallback and native close after sink failure.
            run = function()
                local plain = fixture("cooked")
                A.falsy(plain.display)
                A.equal(plain.request.mode, "cooked")
                A.equal(#plain.writes, 0)
                close(plain)
                local enhanced = fixture()
                enhanced.fail_output = true
                local ok = pcall(enhanced.port.close, enhanced.port)
                A.equal(ok, false)
                A.equal(enhanced.closed, true)
                A.equal(enhanced.restored, true)
                enhanced.fail_output = false
                A.truthy(enhanced.port:close())
                local writes = #enhanced.writes
                A.equal(pcall(enhanced.display.output, enhanced.display, "late output\n"), false)
                A.equal(#enhanced.writes, writes)
            end,
        },
    },
}
