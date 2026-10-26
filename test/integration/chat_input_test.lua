--[[
Author: WaterRun
Date: 2026-10-26
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
    local f = { inputs = {}, writes = {}, frames = {}, now = 0, restored = false, closed = false, columns = 40 }
    local native = {}
    -- Observe the current fixture width without changing input state.
    --@param none Uses the fixture's display profile and mutable width.
    --@return table Native-style display facts.
    function native.terminal_display_info() return { kind = kind or "ansi", columns = f.columns } end
    -- Record native console frames without interpreting them as ANSI output.
    --@param frame table Captured append/prefix/suffix text and erase flag.
    --@return boolean True after acceptance, false for injected output failure.
    --@return boolean|table Native acknowledgment or a typed sink error.
    --@effect Retains a frame only on successful output.
    function native.console_redraw(frame)
        if f.fail_output then return false, { code = "BrokenStdout", message = "fixture output failed" } end
        f.frames[#f.frames + 1] = frame
        return true, true
    end
    -- Retain the actual native request for automatic mode-selection assertions.
    --@param request table Mode, byte cap and editor flags from the production adapter.
    --@return boolean True for a successful fixture start.
    --@return table Stable fake handle.
    function native.terminal_start(request) f.request = request; return true, f end
    -- Deliver queued native observations within the requested budget or a cancellation outcome.
    --@param handle table Stable fake handle.
    --@param now integer Monotonic test tick.
    --@param budget integer Native observation budget, always positive here.
    --@return boolean True after reading the fixture queue.
    --@return table At most budget ordered observations.
    --@effect Removes only the queued input chunks returned in this batch.
    function native.terminal_poll(handle, now, budget)
        A.equal(handle, f)
        if f.cancelled then return true, { { kind = "terminal", outcome = "cancelled" } } end
        local events = {}
        while #events < budget and #f.inputs > 0 do
            local bytes = table.remove(f.inputs, 1)
            events[#events + 1] = type(bytes) == "table" and bytes
                or { kind = "action", intent = "text", text = bytes }
        end
        return true, events
    end
    -- Mark this fixture's input owner cancelled.
    --@param handle table Stable fake handle.
    --@param now integer Cancellation tick.
    --@return boolean True native call status.
    --@return boolean True cancellation acknowledgment.
    --@effect Enables the fixture's terminal outcome on the next poll.
    function native.terminal_cancel(handle, now) f.cancelled = true; return true, true end
    -- Discard the fixture's asynchronous paste without cancelling its input owner.
    --@param handle table Stable fake handle.
    --@return boolean True native call status.
    --@return boolean True discard acknowledgment.
    --@effect Counts discard requests for innermost cancellation assertions.
    function native.terminal_discard_paste(handle) f.discards = (f.discards or 0) + 1; return true, true end
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
            name = "delayed paste preserves following edits and Enter while output continues",
            -- A clipboard barrier must yield to model output and replay keys only after the complete value.
            --@param none Supplies a split native paste transaction and one-event output budgets.
            --@return nil Assertions require exact paste/edit/submission order and a preserved draft around output.
            run = function()
                local f = fixture("console")
                feed(f, "pre")
                f.inputs = { { kind = "action", intent = "paste-start" }, "X",
                    { kind = "action", intent = "submit-or-queue" } }
                A.equal(#feed(f, ""), 0)
                f.display:output("model continues\n")
                A.equal(f.frames[#f.frames].prefix, ">> pre")
                f.inputs = { { kind = "action", intent = "paste", text = "中\n" } }
                local events = feed(f, "", 1)
                A.equal(#events, 2); A.equal(events[1].text, "pre中\nX")
                A.equal(events[2].action, "submit-or-queue")
                close(f)
            end,
        },
        {
            name = "cancel pending paste discards queued Enter before cancelling model work",
            -- The first Ctrl-C cancels the paste and draft; a subsequent Ctrl-C can cancel the active model.
            --@param none Supplies a pending paste, queued partial command, Enter and two separate cancels.
            --@return nil Assertions require no partial submission and exactly one explicit paste discard.
            run = function()
                local f = fixture("console")
                feed(f, "pre")
                f.inputs = { { kind = "action", intent = "paste-start" }, "tail",
                    { kind = "action", intent = "submit-or-queue" }, "\3" }
                A.equal(#feed(f, ""), 0)
                A.equal(f.discards, 1); A.equal(f.cancelled, nil)
                A.equal(f.frames[#f.frames].prefix, ">> ")
                local events = feed(f, "\3")
                A.equal(#events, 1); A.equal(events[1].action, "cancel")
                close(f)
            end,
        },
        {
            name = "rejected paste drops queued submission and preserves the earlier draft",
            -- A failed clipboard read must not let a queued Enter submit a command with missing paste text.
            --@param none Rejects a paste after a preexisting draft and an immediate Enter.
            --@return nil Assertions require a notice, preserved input and successful fresh typing afterward.
            run = function()
                local f = fixture("console")
                feed(f, "pre")
                f.inputs = { { kind = "action", intent = "paste-start" }, "tail",
                    { kind = "action", intent = "submit-or-queue" }, { kind = "action", intent = "paste-rejected" } }
                A.equal(#feed(f, ""), 0)
                A.equal(f.frames[#f.frames].prefix, ">> pre")
                A.truthy(f.frames[#f.frames].append:find("Clipboard text", 1, true))
                local events = feed(f, "ok\r", 2)
                A.equal(events[1].text, "preok"); A.equal(events[2].action, "submit-or-queue")
                close(f)
            end,
        },
        {
            name = "immediate clipboard rejection discards keys from the same native batch",
            -- Busy clipboard admission and a deadline observed before key polling must not submit a missing paste.
            --@param none Supplies rejection followed immediately by native text and Enter in the fetched batch.
            --@return nil Assertions require no submission and retention of only the earlier draft.
            run = function()
                local f = fixture("console")
                feed(f, "pre")
                f.inputs = { { kind = "action", intent = "paste-rejected" }, "tail",
                    { kind = "action", intent = "submit-or-queue" } }
                A.equal(#feed(f, ""), 0)
                A.equal(f.frames[#f.frames].prefix, ">> pre")
                close(f)
            end,
        },
        {
            name = "clipboard rejection preserves a terminal outcome in the fetched batch",
            -- Dropping keys after failed paste must not consume the input owner's only terminal fact.
            --@param none Supplies immediate rejection, an unsafe Enter and completed input truth together.
            --@return nil Assertions require exactly the terminal event and normal owner cleanup.
            run = function()
                local f = fixture("console")
                f.inputs = { { kind = "action", intent = "paste-rejected" },
                    { kind = "action", intent = "submit-or-queue" }, { kind = "terminal", outcome = "completed" } }
                local events = feed(f, "", 2)
                A.equal(#events, 1); A.equal(events[1].kind, "io_terminal"); A.equal(events[1].outcome, "completed")
                f.port:restore(); f.port:close(); A.truthy(f.closed)
            end,
        },
        {
            name = "pending paste key queue stays bounded before submission",
            -- Overflow must discard the pending native read and fail before any partial Enter is dispatched.
            --@param none Buffers more than the admitted cap behind an unresolved clipboard barrier.
            --@return nil Assertions require a typed input-limit failure and independent cleanup.
            run = function()
                local f = fixture("console")
                f.inputs = { { kind = "action", intent = "paste-start" }, string.rep("x", 200), string.rep("y", 100) }
                local ok, err = pcall(feed, f, "")
                A.equal(ok, false); A.truthy(tostring(err):find("InputLimit", 1, true))
                A.equal(f.discards, 1)
                close(f)
            end,
        },
        {
            name = "batched native text Enter and paste preserve ordering under a one-event budget",
            -- Native key batching must not submit an empty draft or merge the next line into the first.
            --@param none Queues two submissions with text, paste and native Enter boundaries in one native batch.
            --@return nil Assertions require exact ordered text/submission pairs with no extra event.
            run = function()
                local f = fixture("console")
                f.inputs = { "a", "b", { kind = "action", intent = "submit-or-queue" },
                    "c", { kind = "action", intent = "paste", text = "d\ne" },
                    { kind = "action", intent = "submit-or-queue" } }
                local events = feed(f, "", 1)
                A.equal(#events, 4)
                A.equal(events[1].text, "ab")
                A.equal(events[2].action, "submit-or-queue")
                A.equal(events[3].text, "cd\ne")
                A.equal(events[4].action, "submit-or-queue")
                close(f)
            end,
        },
        {
            name = "native console input uses shared drafts and semantic Enter without ANSI output",
            -- A Windows native Enter event must submit the owned draft rather than an empty coordinator line.
            --@param none Types, pastes, renders asynchronous output and submits through a console profile.
            --@return nil Assertions require exact literal paste, preserved draft and native-only frames.
            run = function()
                local f = fixture("console")
                A.equal(#feed(f, ".sta\t"), 0)
                A.equal(f.frames[#f.frames].prefix, ">> .status")
                f.display:output("answer\n")
                A.equal(f.frames[#f.frames].append, "answer\n")
                A.equal(f.frames[#f.frames].prefix, ">> .status")
                f.inputs[#f.inputs + 1] = { kind = "action", intent = "submit-or-queue" }
                local events = f.port:poll(20, 2)
                A.equal(events[1].text, ".status")
                A.equal(events[2].action, "submit-or-queue")
                f.inputs[#f.inputs + 1] = { kind = "action", intent = "paste", text = ".ask one\n\27[201~two" }
                A.equal(#f.port:poll(21, 2), 0)
                f.inputs[#f.inputs + 1] = { kind = "action", intent = "submit-or-queue" }
                events = f.port:poll(22, 2)
                A.equal(events[1].text, ".ask one\n\27[201~two")
                A.equal(#f.writes, 0)
                close(f)
                A.equal(#f.writes, 0)
            end,
        },
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
