--[[
File: line_editor_test.lua
Date: 2026-08-29
Author: WaterRun
Description: Verifies owned-draft redraw and cooked safe-line buffering.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

local function load_module(name, cache)
    cache = cache or {}
    if cache[name] then return cache[name] end
    local environment = { require = function(dependency)
        return load_module(dependency, cache)
    end }
    environment._G = environment
    setmetatable(environment, { __index = _ENV })
    local chunk, load_error = loadfile(
        YACA_TEST_ROOT .. "/src/" .. name .. ".lua",
        "t",
        environment
    )
    A.truthy(chunk, load_error)
    local value = chunk()
    cache[name] = value
    return value
end

local function read_file(relative_path)
    local handle, open_error = io.open(YACA_TEST_ROOT .. "/" .. relative_path, "rb")
    A.truthy(handle, open_error)
    local source = handle:read("a")
    handle:close()
    return source
end

local cache = {}
local terminal = load_module("terminal", cache)
local tui = load_module("tui", cache)

local function capabilities()
    return {
        ansi = false,
        color = false,
        unicode = true,
        keys = {
            Enter = true,
            ["Ctrl+Enter"] = true,
            ["Shift+Enter"] = true,
            ["Alt+Enter"] = true,
            Esc = true,
        },
    }
end

local function renderer(overrides)
    local options = {
        width = 40,
        capabilities = capabilities(),
        maximum_block_bytes = 4096,
        maximum_line_bytes = 2048,
        maximum_id_bytes = 64,
    }
    for key, value in pairs(overrides or {}) do options[key] = value end
    return assert(tui.new(options))
end

local function editor_options(mode, overrides)
    local options = {
        mode = mode,
        focus = "chat",
        maximum_draft_bytes = 512,
        maximum_pending_bytes = 4096,
        maximum_pending_blocks = 8,
    }
    for key, value in pairs(overrides or {}) do options[key] = value end
    return options
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function raw_display(settings)
    settings = settings or {}
    local display = { frames = {}, calls = 0 }
    function display:redraw(frame)
        self.calls = self.calls + 1
        if settings.fail_at == self.calls then
            return false, { code = "BrokenStdout", message = "redraw failed" }
        end
        self.frames[#self.frames + 1] = copy(frame)
        return true
    end
    return display
end

local function cooked_display(settings)
    settings = settings or {}
    local display = { writes = {}, urgent = {}, write_calls = 0 }
    function display:write(bytes)
        self.write_calls = self.write_calls + 1
        if settings.fail_write_at == self.write_calls then
            return false, { code = "BrokenStdout", message = "write failed" }
        end
        self.writes[#self.writes + 1] = bytes
        return #bytes
    end
    function display:write_urgent(request)
        if settings.fail_urgent then
            return false, { code = "BrokenStdout", message = "urgent failed" }
        end
        self.urgent[#self.urgent + 1] = copy(request)
        return true
    end
    return display
end

return {
    name = "integration/line-editor",
    cases = {
        {
            name = "native publish is one hide append redraw transaction with exact draft",
            run = function()
                local display = raw_display()
                local editor = assert(renderer().new_line_editor(
                    display,
                    editor_options("native", { initial_draft = "fix pars" })
                ))
                A.truthy(editor.show())
                A.equal(#display.frames, 1)
                A.falsy(display.frames[1].hide_draft)
                A.equal(display.frames[1].append_bytes, "")
                A.equal(display.frames[1].redraw_bytes, ">> fix pars\n")
                A.equal(display.frames[1].draft_bytes, "fix pars")
                A.equal(display.frames[1].cursor_byte, #"fix pars")

                local published = assert(editor.publish({
                    kind = "assistant",
                    text = "I am checking the parser.",
                    sequence = 7,
                }))
                A.falsy(published.queued)
                A.equal(published.sequence, 7)
                A.equal(#display.frames, 2)
                local frame = display.frames[2]
                A.truthy(frame.hide_draft)
                A.equal(frame.append_bytes, "[ASSISTANT]\nI am checking the parser.\n")
                A.equal(frame.redraw_bytes, ">> fix pars\n")
                A.equal(frame.draft_bytes, "fix pars")
                A.equal(frame.cursor_byte, #"fix pars")
                A.equal(editor.snapshot().draft, "fix pars")
                A.equal(editor.snapshot().last_sequence, 7)

                local transcript = display.frames[1].redraw_bytes
                    .. frame.append_bytes .. frame.redraw_bytes
                A.equal(transcript, read_file("test/golden/tui/stream-redraw"))
            end,
        },
        {
            name = "raw editor changes Unicode only at scalar boundaries",
            run = function()
                local display = raw_display()
                local editor = assert(renderer().new_line_editor(
                    display,
                    editor_options("raw", { initial_draft = "a中b" })
                ))
                A.truthy(editor.show())
                A.equal(editor.snapshot().cursor_byte, #"a中b")
                A.equal(assert(editor.backspace()).draft, "a中")
                A.equal(assert(editor.backspace()).draft, "a")
                A.equal(assert(editor.insert("文")).draft, "a文")
                A.equal(assert(editor.move("left")).cursor_byte, 1)
                A.equal(assert(editor.delete_forward()).draft, "a")
                A.equal(assert(editor.insert("\27[2J")).draft, "a\27[2J")
                A.contains(display.frames[#display.frames].redraw_bytes, "\\x1B[2J")

                local invalid_cursor, cursor_error = editor.set_draft("中文", 1)
                A.falsy(invalid_cursor)
                A.equal(cursor_error.code, "InvalidCursor")
                local invalid_text, text_error = editor.insert(string.char(0xFF))
                A.falsy(invalid_text)
                A.equal(text_error.code, "InvalidDraft")
                local nul, nul_error = editor.insert("\0")
                A.falsy(nul)
                A.equal(nul_error.code, "InvalidDraft")
            end,
        },
        {
            name = "submission lease clears only after explicit accepted resolution",
            run = function()
                local display = raw_display()
                local editor = assert(renderer().new_line_editor(
                    display,
                    editor_options("raw", { initial_draft = "do work" })
                ))
                A.truthy(editor.show())
                local first = assert(editor.prepare_submission("submit-or-queue"))
                A.equal(first.text, "do work")
                A.equal(first.cursor_byte, #"do work")
                local edited, pending_error = editor.insert(" now")
                A.falsy(edited)
                A.equal(pending_error.code, "SubmissionPending")
                local closed, close_error = editor.close()
                A.falsy(closed)
                A.equal(close_error.code, "SubmissionPending")
                A.equal(assert(editor.resolve_submission(first.generation, false)).draft, "do work")

                local second = assert(editor.consume({
                    kind = "user_action",
                    action = "steer",
                }))
                A.equal(second.intent, "steer")
                A.equal(second.text, "do work")
                A.equal(assert(editor.resolve_submission(second.generation, true)).draft, "")
                A.equal(display.frames[#display.frames].redraw_bytes, ">>\n")
                local stale, stale_error = editor.resolve_submission(second.generation, true)
                A.falsy(stale)
                A.equal(stale_error.code, "SubmissionStale")

                A.truthy(editor.consume({
                    kind = "user_action", action = "text", text = "line one",
                }))
                A.truthy(editor.consume({ kind = "user_action", action = "newline" }))
                A.truthy(editor.consume({
                    kind = "user_action", action = "text", text = "line two",
                }))
                A.equal(editor.snapshot().draft, "line one\nline two")
                local cancel = assert(editor.consume({
                    kind = "user_action", action = "cancel",
                }))
                A.equal(cancel.intent, "cancel")
                A.equal(editor.snapshot().draft, "line one\nline two")
            end,
        },
        {
            name = "raw text events preserve split UTF-8 and apply embedded backspace",
            run = function()
                local display = raw_display()
                local editor = assert(renderer().new_line_editor(
                    display,
                    editor_options("raw", { initial_draft = "ab" })
                ))
                A.truthy(editor.show())
                local chinese = "中"
                A.truthy(editor.consume({
                    kind = "user_action", action = "text", text = chinese:sub(1, 1),
                }))
                A.equal(editor.snapshot().draft, "ab")
                A.equal(editor.snapshot().pending_input_bytes, 1)
                A.truthy(editor.consume({
                    kind = "user_action", action = "text", text = chinese:sub(2, 2),
                }))
                A.equal(editor.snapshot().pending_input_bytes, 2)
                A.truthy(editor.consume({
                    kind = "user_action", action = "text", text = chinese:sub(3),
                }))
                A.equal(editor.snapshot().draft, "ab中")
                A.equal(editor.snapshot().pending_input_bytes, 0)

                A.equal(assert(editor.consume({
                    kind = "user_action", action = "text", text = "cd\127e",
                })).draft, "ab中ce")
                A.equal(assert(editor.consume({
                    kind = "user_action", action = "text", text = "\8",
                })).draft, "ab中c")

                A.truthy(editor.consume({
                    kind = "user_action", action = "text", text = chinese:sub(1, 1),
                }))
                local submitted, incomplete_error = editor.prepare_submission("side")
                A.falsy(submitted)
                A.equal(incomplete_error.code, "InputEncodingIncomplete")
                local closed, close_error = editor.close()
                A.falsy(closed)
                A.equal(close_error.code, "IncompleteInput")
                local cancelled = assert(editor.consume({
                    kind = "user_action", action = "cancel",
                }))
                A.equal(cancelled.intent, "cancel")
                A.equal(editor.snapshot().pending_input_bytes, 0)
                A.truthy(editor.close())
            end,
        },
        {
            name = "raw display failure keeps runtime draft and marks display unknown",
            run = function()
                local display = raw_display({ fail_at = 2 })
                local editor = assert(renderer().new_line_editor(
                    display,
                    editor_options("native", { initial_draft = "keep me" })
                ))
                A.truthy(editor.show())
                local published, output_error = editor.publish({
                    kind = "error", id = "NetworkError", text = "failed",
                })
                A.falsy(published)
                A.equal(output_error.code, "BrokenStdout")
                A.equal(editor.snapshot().draft, "keep me")
                A.equal(editor.snapshot().state, "faulted")
                A.truthy(editor.snapshot().display_unknown)
                local closed, close_error = editor.close()
                A.falsy(closed)
                A.equal(close_error.code, "DisplayFailure")
            end,
        },
        {
            name = "cooked editor never owns draft and flushes complete blocks at safe line",
            run = function()
                local display = cooked_display()
                local editor = assert(renderer().new_line_editor(
                    display,
                    editor_options("cooked")
                ))
                A.truthy(editor.show())
                A.deep_equal(display.writes, { ">>\n" })
                A.falsy(editor.snapshot().draft_owned)
                A.falsy(editor.snapshot().draft)
                A.falsy(editor.snapshot().cursor_byte)

                local first = assert(editor.publish({
                    kind = "assistant", text = "first complete block", sequence = 2,
                }))
                local second = assert(editor.publish({
                    kind = "status", text = "second complete block", sequence = 3,
                }))
                A.truthy(first.queued)
                A.truthy(second.queued)
                A.equal(#display.urgent, 1)
                A.equal(display.urgent[1].kind, "urgent-receipt")
                A.equal(display.urgent[1].bytes, "[STATUS] output waiting\n")
                A.truthy(display.urgent[1].preserves_system_draft)
                A.falsy(display.urgent[1].draft)
                A.equal(editor.snapshot().pending_blocks, 2)

                local edited, ownership_error = editor.insert("not visible")
                A.falsy(edited)
                A.equal(ownership_error.code, "DraftNotOwned")
                local closed, pending_error = editor.close()
                A.falsy(closed)
                A.equal(pending_error.code, "PendingOutput")

                local flushed = assert(editor.flush_cooked())
                A.equal(flushed, first.rendered .. second.rendered)
                A.equal(display.writes[2], flushed)
                A.equal(editor.snapshot().pending_blocks, 0)
                A.falsy(editor.snapshot().input_active)
                A.truthy(editor.resume_cooked())
                A.equal(display.writes[3], ">>\n")
                A.truthy(editor.snapshot().input_active)
                A.truthy(editor.close())
            end,
        },
        {
            name = "cooked backlog limits reject whole new blocks without dropping old ones",
            run = function()
                local display = cooked_display()
                local editor = assert(renderer().new_line_editor(
                    display,
                    editor_options("cooked", {
                        maximum_pending_blocks = 1,
                        maximum_pending_bytes = 128,
                    })
                ))
                A.truthy(editor.show())
                local first = assert(editor.publish({ kind = "status", text = "one" }))
                local rejected, backlog_error = editor.publish({
                    kind = "status", text = "two",
                })
                A.falsy(rejected)
                A.equal(backlog_error.code, "OutputBacklogLimit")
                A.equal(editor.snapshot().pending_blocks, 1)
                A.equal(editor.snapshot().pending_bytes, #first.rendered)
                A.equal(#display.urgent, 1)
                A.equal(assert(editor.flush_cooked()), first.rendered)

                local urgent_display = cooked_display({ fail_urgent = true })
                local broken = assert(renderer().new_line_editor(
                    urgent_display,
                    editor_options("cooked")
                ))
                A.truthy(broken.show())
                local queued, urgent_error = broken.publish({ kind = "status", text = "one" })
                A.falsy(queued)
                A.equal(urgent_error.code, "BrokenStdout")
                A.equal(broken.snapshot().state, "faulted")
                A.truthy(broken.snapshot().display_unknown)
            end,
        },
        {
            name = "editor constructors modes cursors and semantic sequence fail closed",
            run = function()
                local display = raw_display()
                local invalid, invalid_error = terminal.new_line_editor(display, {
                    mode = "raw",
                })
                A.falsy(invalid)
                A.equal(invalid_error.code, "InvalidLineEditor")
                local cooked, cooked_error = renderer().new_line_editor(
                    cooked_display(),
                    editor_options("cooked", { initial_draft = "claimed" })
                )
                A.falsy(cooked)
                A.equal(cooked_error.code, "InvalidLineEditor")
                local missing, missing_error = renderer().new_line_editor(
                    {},
                    editor_options("raw")
                )
                A.falsy(missing)
                A.equal(missing_error.code, "InvalidLineEditor")
                local unknown, unknown_error = renderer().new_line_editor(
                    display,
                    editor_options("raw", { other = true })
                )
                A.falsy(unknown)
                A.equal(unknown_error.code, "InvalidLineEditor")

                local editor = assert(renderer().new_line_editor(
                    display,
                    editor_options("raw")
                ))
                A.truthy(editor.show())
                A.truthy(editor.publish({ kind = "status", text = "one", sequence = 4 }))
                local stale, sequence_error = editor.publish({
                    kind = "status", text = "stale", sequence = 4,
                })
                A.falsy(stale)
                A.equal(sequence_error.code, "OutOfOrderViewBlock")
                local invalid_event, event_error = editor.consume({
                    kind = "user_action", action = "unknown",
                })
                A.falsy(invalid_event)
                A.equal(event_error.code, "InvalidInputEvent")
                A.raises(function() editor.extra = true end, "cannot be modified")
            end,
        },
    },
}
