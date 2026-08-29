--[[
File: terminal_transcript_test.lua
Date: 2026-08-29
Author: WaterRun
Description: Runs deterministic terminal-profile transcripts without claiming target proof.
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

local function load_table(relative_path)
    local chunk, load_error = loadfile(YACA_TEST_ROOT .. "/" .. relative_path, "t", _ENV)
    A.truthy(chunk, load_error)
    return chunk()
end

local function read_file(relative_path)
    local handle, open_error = io.open(YACA_TEST_ROOT .. "/" .. relative_path, "rb")
    A.truthy(handle, open_error)
    local source = handle:read("a")
    handle:close()
    return source
end

local cache = {}
local tui = load_module("tui", cache)
local manifest = load_table("release/manifest.lua")

local function capabilities(profile)
    return {
        ansi = false,
        color = false,
        unicode = profile.unicode,
        keys = {
            Enter = true,
            ["Ctrl+Enter"] = profile.enhanced_keys,
            ["Shift+Enter"] = profile.enhanced_keys,
            ["Alt+Enter"] = profile.enhanced_keys,
            Esc = profile.enhanced_keys,
        },
    }
end

local function renderer(profile)
    return assert(tui.new({
        width = 40,
        capabilities = capabilities(profile),
        maximum_block_bytes = 4096,
        maximum_line_bytes = 2048,
        maximum_id_bytes = 64,
    }))
end

local function editor_options(mode, draft)
    return {
        mode = mode,
        focus = "chat",
        maximum_draft_bytes = 512,
        maximum_pending_bytes = 4096,
        maximum_pending_blocks = 8,
        initial_draft = draft,
    }
end

local function atomic_display()
    local display = { frames = {}, transcript = "" }
    function display:redraw(frame)
        self.frames[#self.frames + 1] = frame
        if frame.append_bytes == "" then
            self.transcript = self.transcript .. frame.redraw_bytes
        else
            self.transcript = self.transcript .. frame.append_bytes .. frame.redraw_bytes
        end
        return true
    end
    return display
end

local function cooked_display(system_draft)
    local display = {
        system_draft = system_draft,
        transcript = "",
        urgent_requests = {},
        flushed = {},
    }
    function display:write(bytes)
        if bytes == ">>\n" then
            self.transcript = self.transcript .. ">> " .. self.system_draft .. "\n"
        else
            self.transcript = self.transcript .. bytes
            self.flushed[#self.flushed + 1] = bytes
        end
        return #bytes
    end
    function display:write_urgent(request)
        self.urgent_requests[#self.urgent_requests + 1] = request
        self.transcript = self.transcript .. request.bytes
            .. ">> " .. self.system_draft .. "\n"
        return true
    end
    return display
end

local OWNED_PROFILES = {
    {
        id = "windows-xp-native-synthetic",
        target = "win32-x86",
        mode = "native",
        unicode = false,
        enhanced_keys = true,
    },
    {
        id = "windows-7-native-synthetic",
        target = "win64-x86_64",
        mode = "native",
        unicode = true,
        enhanced_keys = true,
    },
    {
        id = "centos-7-raw-synthetic",
        target = "linux-x86_64",
        mode = "raw",
        unicode = true,
        enhanced_keys = true,
    },
}

local COOKED_PROFILES = {
    {
        id = "windows-xp-cooked-synthetic",
        target = "win32-x86",
        mode = "cooked",
        unicode = false,
        enhanced_keys = false,
    },
    {
        id = "term-dumb-synthetic",
        target = "linux-x86_64",
        mode = "cooked",
        unicode = true,
        enhanced_keys = false,
    },
    {
        id = "ssh-canonical-synthetic",
        target = "linux-x86_64",
        mode = "cooked",
        unicode = true,
        enhanced_keys = false,
    },
}

return {
    name = "qualification/terminal-transcript",
    cases = {
        {
            name = "native and raw profiles atomically restore the exact frozen draft",
            run = function()
                local golden = read_file("test/golden/tui/stream-redraw")
                for _, profile in ipairs(OWNED_PROFILES) do
                    local display = atomic_display()
                    local editor = assert(renderer(profile).new_line_editor(
                        display,
                        editor_options(profile.mode, "fix pars")
                    ))
                    A.truthy(editor.show(), profile.id)
                    local published = assert(editor.publish({
                        kind = "assistant",
                        text = "I am checking the parser.",
                    }))
                    A.falsy(published.queued, profile.id)
                    A.equal(display.transcript, golden, profile.id)
                    A.equal(#display.frames, 2, profile.id)
                    A.falsy(display.frames[1].hide_draft, profile.id)
                    A.truthy(display.frames[2].hide_draft, profile.id)
                    A.equal(display.frames[2].draft_bytes, "fix pars", profile.id)
                    A.equal(display.frames[2].cursor_byte, #"fix pars", profile.id)
                    A.equal(
                        display.frames[2].append_bytes,
                        "[ASSISTANT]\nI am checking the parser.\n",
                        profile.id
                    )
                    A.falsy(display.transcript:find("\27", 1, true), profile.id)
                    A.equal(editor.snapshot().draft, "fix pars", profile.id)
                    A.equal(editor.snapshot().mode, profile.mode, profile.id)
                end
            end,
        },
        {
            name = "cooked and SSH profiles expose backlog without claiming host draft ownership",
            run = function()
                local golden = read_file("test/golden/tui/plain-backlog")
                for _, profile in ipairs(COOKED_PROFILES) do
                    local display = cooked_display("keep this draft")
                    local editor = assert(renderer(profile).new_line_editor(
                        display,
                        editor_options(profile.mode)
                    ))
                    A.truthy(editor.show(), profile.id)
                    local queued = assert(editor.publish({
                        kind = "assistant",
                        text = "deferred complete output",
                    }))
                    A.truthy(queued.queued, profile.id)
                    A.equal(display.transcript, golden, profile.id)
                    A.equal(#display.urgent_requests, 1, profile.id)
                    A.truthy(
                        display.urgent_requests[1].preserves_system_draft,
                        profile.id
                    )
                    A.falsy(display.urgent_requests[1].draft_bytes, profile.id)
                    A.falsy(editor.snapshot().draft_owned, profile.id)
                    A.falsy(editor.snapshot().draft, profile.id)
                    A.equal(editor.snapshot().pending_blocks, 1, profile.id)
                    local flushed = assert(editor.flush_cooked())
                    A.equal(flushed, queued.rendered, profile.id)
                    A.equal(editor.snapshot().pending_blocks, 0, profile.id)
                end
            end,
        },
        {
            name = "every terminal profile keeps fixed text fallbacks and pending target status",
            run = function()
                local expected_fallbacks = {
                    ["submit-or-queue"] = ".queue <message>",
                    steer = ".immediate <message>",
                    newline = ".multiline",
                    side = ".side <message>",
                    cancel = ".cancel",
                }
                for _, profiles in ipairs({ OWNED_PROFILES, COOKED_PROFILES }) do
                    for _, profile in ipairs(profiles) do
                        local view = renderer(profile)
                        for intent, fallback in pairs(expected_fallbacks) do
                            local binding = assert(view.input_binding(intent))
                            A.equal(binding.text_fallback, fallback, profile.id .. ":" .. intent)
                            if intent ~= "submit-or-queue" then
                                A.equal(
                                    binding.key_available,
                                    profile.enhanced_keys,
                                    profile.id .. ":" .. intent
                                )
                            end
                        end
                    end
                end

                local targets = {}
                for _, target in ipairs(manifest.targets) do
                    targets[target.id] = target.qualification
                end
                A.equal(targets["win32-x86"], "pending")
                A.equal(targets["win64-x86_64"], "pending")
                A.equal(targets["linux-x86_64"], "pending")
                A.falsy(manifest.release_authorized)
                A.equal(manifest.release_state, "unqualified")
            end,
        },
    },
}
