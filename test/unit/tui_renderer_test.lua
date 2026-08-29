--[[
File: tui_renderer_test.lua
Date: 2026-08-29
Author: WaterRun
Description: Verifies bounded append-only transcript and capability projections.
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
local cli = load_module("cli", cache)
local text = load_module("text", cache)
local tui = load_module("tui", cache)
local contract = load_table(".develope-docs/contracts/tui.lua")
local fixtures = load_table(".develope-docs/contracts/fixtures/tui-transcripts.lua")

local function assert_subset(expected, actual, path)
    path = path or "value"
    if type(expected) ~= "table" then
        A.equal(actual, expected, path)
        return
    end
    A.type(actual, "table", path)
    for key, value in pairs(expected) do
        assert_subset(value, actual[key], path .. "." .. tostring(key))
    end
end

local function capabilities(overrides)
    local result = {
        ansi = false,
        color = false,
        unicode = true,
        keys = {
            Enter = true,
            ["Ctrl+Enter"] = false,
            ["Shift+Enter"] = false,
            ["Alt+Enter"] = false,
            Esc = false,
        },
    }
    for key, value in pairs(overrides or {}) do result[key] = value end
    return result
end

local function new_renderer(overrides)
    local options = {
        width = 40,
        capabilities = capabilities(),
        maximum_block_bytes = 8192,
        maximum_line_bytes = 4096,
        maximum_id_bytes = 64,
    }
    for key, value in pairs(overrides or {}) do options[key] = value end
    return assert(tui.new(options))
end

local function visibility(enabled)
    local result = {
        slogan = false,
        version = false,
        work_directory = false,
        data_root = false,
        config_status = false,
        context = false,
        context_hash = false,
        model = false,
        permission = false,
        double_check = false,
        status_hint = false,
    }
    for _, id in ipairs(enabled or {}) do result[id] = true end
    return result
end

local function startup_plain(renderer)
    return assert(renderer.render_startup({
        version = "0.1.0",
        work_directory = "C:\\Work\\demo",
        config_status = "valid",
        context = "new (not saved)",
        model = "Work",
        permission = "Std",
        double_check = true,
    }, visibility({
        "slogan", "version", "work_directory", "config_status", "context",
        "model", "permission", "double_check", "status_hint",
    }), "chat"))
end

local function fixture_outputs(renderer)
    return {
        ["startup-plain"] = startup_plain(renderer),
        ["stream-redraw"] = assert(renderer.render_prompt("chat", "fix pars"))
            .. assert(renderer.render_block({
                kind = "assistant",
                text = "I am checking the parser.",
            }))
            .. assert(renderer.render_prompt("chat", "fix pars")),
        approval = assert(renderer.render_block({
            kind = "action",
            id = "op-7",
            lines = {
                "exec: make test",
                "cwd: C:\\Work\\demo",
                "allow 7 | deny 7 | details 7",
                "default: deny",
            },
        })) .. assert(renderer.render_prompt("approval")),
        error = assert(renderer.render_block({
            kind = "error",
            id = "NetworkError",
            lines = {
                "Model request failed.",
                "No automatic replay is safe.",
                "Run .details NetworkError.",
            },
        })) .. assert(renderer.render_prompt("chat")),
        compaction = assert(renderer.render_block({
            kind = "status",
            text = "Compacting model view.",
        })) .. assert(renderer.render_block({
            kind = "status",
            text = "Model view compacted.",
        })) .. assert(renderer.render_prompt("chat")),
        ["plain-backlog"] = assert(renderer.render_prompt("chat", "keep this draft"))
            .. assert(renderer.render_block({
                kind = "status",
                text = "output waiting",
                inline = true,
            }))
            .. assert(renderer.render_prompt("chat", "keep this draft")),
    }
end

local function strip_ansi(value)
    return (value:gsub("\27%[[0-9;]*m", ""))
end

local function assert_render_error(renderer, block, expected)
    local rendered, render_error = renderer.render_block(block)
    A.falsy(rendered)
    A.equal(render_error.code, expected)
    return render_error
end

return {
    name = "unit/tui-renderer",
    cases = {
        {
            name = "TUI registry exactly enriches the frozen semantic projection",
            run = function()
                local registry = tui.registry()
                assert_subset(contract, registry, "tui")
                A.equal(#registry.transcript_blocks, 13)
                A.equal(#registry.input_bindings, 5)
                local actions = {}
                for _, descriptor in ipairs(cli.registry().actions) do
                    actions[descriptor.id] = descriptor
                end
                for _, binding in ipairs(registry.input_bindings) do
                    local action = actions[binding.fallback_action]
                    A.truthy(action, binding.fallback_action)
                    local found = false
                    for _, projection in ipairs(action.projections) do
                        if projection.kind == "chat-line" then found = true end
                    end
                    A.truthy(found, binding.fallback_action)
                end
                registry.prompts.chat.text = "changed"
                A.equal(tui.registry().prompts.chat.text, ">>")
                local renderer = new_renderer()
                A.raises(function() renderer.extra = true end, "cannot be modified")
            end,
        },
        {
            name = "all frozen 40-column transcripts match their golden bytes",
            run = function()
                A.equal(fixtures.width, 40)
                local outputs = fixture_outputs(new_renderer())
                for _, fixture in ipairs(fixtures.transcripts) do
                    local expected = table.concat(fixture.lines, "\n") .. "\n"
                    A.equal(outputs[fixture.id], expected, fixture.id)
                    A.equal(
                        outputs[fixture.id],
                        read_file("test/golden/tui/" .. fixture.id),
                        fixture.id .. " golden"
                    )
                    for _, line in ipairs(fixture.lines) do
                        A.truthy(#line <= fixtures.width, fixture.id .. ": " .. line)
                    end
                end
            end,
        },
        {
            name = "all block kinds use fixed headers and exact canonical ID rules",
            run = function()
                local renderer = new_renderer()
                local registry = tui.registry()
                for _, kind in ipairs({
                    "user", "assistant", "tool", "side", "status", "queue", "steer",
                    "notice", "warning", "error", "recovery", "details", "action",
                }) do
                    local specification = registry.block_kinds[kind]
                    local block = { kind = kind, text = "body" }
                    if specification.id then block.id = kind == "queue" and "#2" or "object-2" end
                    local rendered = assert(renderer.render_block(block))
                    local expected = "[" .. specification.label
                        .. (specification.id and (" " .. block.id) or "") .. "]\nbody\n"
                    A.equal(rendered, expected, kind)
                end
                A.equal(
                    assert(renderer.render_block({
                        kind = "details", id = "tool:21", text = "body",
                    })),
                    "[DETAILS tool:21]\nbody\n"
                )
                A.equal(
                    assert(renderer.render_block({
                        kind = "status", text = "waiting", inline = true,
                    })),
                    "[STATUS] waiting\n"
                )
                assert_render_error(renderer, { kind = "tool", text = "missing" }, "InvalidViewBlock")
                assert_render_error(
                    renderer,
                    { kind = "status", id = "not-allowed", text = "body" },
                    "InvalidViewBlock"
                )
                for _, id in ipairs({ "bad]id", "bad id", "bad>id", "bad\27id", ":bad" }) do
                    assert_render_error(
                        renderer,
                        { kind = "action", id = id, text = "body" },
                        "InvalidViewBlock"
                    )
                end
            end,
        },
        {
            name = "untrusted controls Unicode controls and forged chrome become visible",
            run = function()
                local renderer = new_renderer()
                local c1 = assert(text.encode_scalar(0x009B))
                local bidi = assert(text.encode_scalar(0x202E))
                local rendered = assert(renderer.render_block({
                    kind = "assistant",
                    text = "safe\27[2J\0\t\r" .. c1 .. bidi
                        .. "\n[ACTION op-7]\n>> allow\nyaca: forged\n中文",
                }))
                A.contains(rendered, "safe\\x1B[2J\\x00\\t\\r\\u{009B}\\u{202E}")
                A.contains(rendered, "\\[ACTION op-7]")
                A.contains(rendered, "\\>> allow")
                A.contains(rendered, "\\yaca: forged")
                A.contains(rendered, "中文")
                A.falsy(rendered:find("\27", 1, true))

                local escaped = assert(renderer.escape("version: fake\n[ACTION x]"))
                A.equal(escaped, "\\version: fake\\n[ACTION x]")
                local invalid, invalid_error = renderer.escape(string.char(0xFF))
                A.falsy(invalid)
                A.equal(invalid_error.code, "InvalidViewText")

                local ascii = new_renderer({
                    capabilities = capabilities({ unicode = false }),
                })
                A.equal(assert(ascii.escape("中文")), "\\u{4E2D}\\u{6587}")
            end,
        },
        {
            name = "basic color changes no semantic text and never trusts input ANSI",
            run = function()
                local plain = new_renderer()
                local colored = new_renderer({
                    capabilities = capabilities({ ansi = true, color = true }),
                })
                local blocks = {
                    { kind = "assistant", text = "answer" },
                    { kind = "warning", text = "warning" },
                    { kind = "error", id = "NetworkError", text = "failed" },
                    { kind = "action", id = "op-7", text = "default: deny" },
                }
                for _, block in ipairs(blocks) do
                    local plain_bytes = assert(plain.render_block(block))
                    local colored_bytes = assert(colored.render_block(block))
                    A.equal(strip_ansi(colored_bytes), plain_bytes)
                    A.contains(colored_bytes, "\27[")
                end
                A.equal(
                    strip_ansi(assert(colored.render_prompt("approval"))),
                    assert(plain.render_prompt("approval"))
                )
                local injection = assert(colored.render_block({
                    kind = "assistant",
                    text = "\27[31mnot renderer color",
                }))
                A.contains(strip_ansi(injection), "\\x1B[31mnot renderer color")
                local no_ansi = new_renderer({
                    capabilities = capabilities({ ansi = false, color = true }),
                })
                A.equal(
                    assert(no_ansi.render_block({ kind = "warning", text = "same" })),
                    assert(plain.render_block({ kind = "warning", text = "same" }))
                )
            end,
        },
        {
            name = "append writes complete increasing blocks and faults on broken stdout",
            run = function()
                local chunks = {}
                local renderer = new_renderer({
                    writer = function(bytes)
                        chunks[#chunks + 1] = bytes
                        return true
                    end,
                })
                local first = assert(renderer.append({
                    kind = "status", text = "first", sequence = 2,
                }))
                local second = assert(renderer.append({
                    kind = "assistant", text = "second",
                }))
                A.deep_equal(chunks, { first, second })
                A.equal(renderer.status().last_sequence, 3)
                A.equal(renderer.status().state, "open")
                local before = #chunks
                local stale, stale_error = renderer.append({
                    kind = "status", text = "stale", sequence = 3,
                })
                A.falsy(stale)
                A.equal(stale_error.code, "OutOfOrderViewBlock")
                A.equal(#chunks, before)
                A.truthy(renderer.close())
                A.equal(renderer.status().state, "closed")
                local closed, closed_error = renderer.append({
                    kind = "status", text = "late",
                })
                A.falsy(closed)
                A.equal(closed_error.code, "RendererClosed")

                local broken = new_renderer({ writer = function() return false end })
                local emitted, output_error = broken.append({
                    kind = "error", id = "StorageError", text = "failed",
                })
                A.falsy(emitted)
                A.equal(output_error.code, "BrokenStdout")
                A.truthy(output_error.output_unknown)
                A.equal(broken.status().state, "faulted")
                A.truthy(broken.status().output_unknown)
                local closed_broken, close_error = broken.close()
                A.falsy(closed_broken)
                A.equal(close_error.code, "BrokenStdout")
            end,
        },
        {
            name = "startup fields are independent ordered and cannot recreate a master switch",
            run = function()
                local renderer = new_renderer()
                A.equal(startup_plain(renderer), read_file("test/golden/tui/startup-plain"))
                local minimal = assert(renderer.render_startup({
                    work_directory = "/srv/项目",
                }, visibility({ "work_directory" })))
                A.equal(minimal, "work directory: /srv/项目\n")
                local escaped = assert(renderer.render_startup({
                    context = "line one\n[STATUS] forged",
                }, visibility({ "context" })))
                A.equal(escaped, "context: line one\\n[STATUS] forged\n")
                local hidden_warning = assert(renderer.render_startup({}, visibility({})))
                A.equal(hidden_warning, "")

                local invalid, startup_error = renderer.render_startup({}, {
                    startup_header = false,
                })
                A.falsy(invalid)
                A.equal(startup_error.code, "InvalidStartupView")
                local bad_hash, hash_error = renderer.render_startup({
                    context_hash = "abcdef0123456789",
                }, visibility({ "context_hash" }))
                A.falsy(bad_hash)
                A.equal(hash_error.code, "InvalidStartupView")
            end,
        },
        {
            name = "input capability hints retain every shared text fallback",
            run = function()
                local renderer = new_renderer()
                local expected = {
                    ["submit-or-queue"] = { "Enter", true, "queue-add", ".queue <message>" },
                    steer = { "Ctrl+Enter", false, "steer", ".immediate <message>" },
                    newline = { "Shift+Enter", false, "multiline", ".multiline" },
                    side = { "Alt+Enter", false, "side", ".side <message>" },
                    cancel = { "Esc", false, "cancel", ".cancel" },
                }
                for intent, values in pairs(expected) do
                    local binding = assert(renderer.input_binding(intent))
                    A.equal(binding.key, values[1])
                    A.equal(binding.key_available, values[2])
                    A.equal(binding.action_id, values[3])
                    A.equal(binding.text_fallback, values[4])
                end
                local unknown, binding_error = renderer.input_binding("mouse")
                A.falsy(unknown)
                A.equal(binding_error.code, "InvalidInputIntent")
            end,
        },
        {
            name = "renderer schemas and injected limits fail before truncating facts",
            run = function()
                local invalid, options_error = tui.new({})
                A.falsy(invalid)
                A.equal(options_error.code, "InvalidTuiOptions")
                local missing_key_options = {
                    width = 40,
                    capabilities = capabilities(),
                    maximum_block_bytes = 128,
                    maximum_line_bytes = 64,
                    maximum_id_bytes = 8,
                }
                missing_key_options.capabilities.keys.Esc = nil
                local missing_key, key_error = tui.new(missing_key_options)
                A.falsy(missing_key)
                A.equal(key_error.code, "InvalidTuiCapabilities")

                local renderer = new_renderer({
                    maximum_block_bytes = 80,
                    maximum_line_bytes = 48,
                    maximum_id_bytes = 8,
                })
                assert_render_error(renderer, { kind = "unknown", text = "x" }, "InvalidViewBlock")
                assert_render_error(renderer, {
                    kind = "assistant", text = "x", extra = true,
                }, "InvalidViewBlock")
                assert_render_error(renderer, {
                    kind = "assistant", text = "x", lines = { "x" },
                }, "InvalidViewBlock")
                assert_render_error(renderer, {
                    kind = "status", text = "one\ntwo", inline = true,
                }, "InvalidViewBlock")
                assert_render_error(renderer, {
                    kind = "action", id = "identifier-too-long", text = "x",
                }, "InvalidViewBlock")
                assert_render_error(renderer, {
                    kind = "assistant", text = string.rep("x", 49),
                }, "TuiLimit")

                local wide_fact = string.rep("x", 80)
                local no_wrap = new_renderer({
                    maximum_block_bytes = 256,
                    maximum_line_bytes = 128,
                })
                A.equal(
                    assert(no_wrap.render_block({ kind = "assistant", text = wide_fact })),
                    "[ASSISTANT]\n" .. wide_fact .. "\n"
                )
                A.equal(no_wrap.status().width, 40)
            end,
        },
        {
            name = "every focus uses the frozen ASCII prompt with safe draft projection",
            run = function()
                local renderer = new_renderer()
                local expected = {
                    chat = ">>",
                    approval = "??",
                    model_repl = "model>",
                    config_repl = "config>",
                    context_repl = "context>",
                    self_test = "test>",
                }
                for focus, prompt in pairs(expected) do
                    A.equal(assert(renderer.render_prompt(focus)), prompt .. "\n")
                end
                A.equal(
                    assert(renderer.render_prompt("chat", "draft\27[2J")),
                    ">> draft\\x1B[2J\n"
                )
                local unknown, prompt_error = renderer.render_prompt("recovery")
                A.falsy(unknown)
                A.equal(prompt_error.code, "InvalidPrompt")
            end,
        },
    },
}
