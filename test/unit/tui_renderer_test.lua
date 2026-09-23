--[[
Author: WaterRun
Date: 2026-09-23
File: tui_renderer_test.lua
Description: Verifies bounded append-only transcript and capability projections.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

--Loads a source module into an isolated per-case environment.
--@param name string Module, Model, or resource name selected by the case.
--@param cache table Per-case module cache preserving isolated imports.
--@return any module Module export loaded in the isolated source environment.
local function load_module(name, cache)
    cache = cache or {}
    if cache[name] then return cache[name] end
    local environment = {
        --Resolves an imported Lua module through the isolated test loader.
        --@param dependency string Source module requested from the isolated loader.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        require = function(dependency)
        return load_module(dependency, cache)
    end }
    environment._G = environment
    --@metatable environment Test-owned lookup and mutation contract for the current case.
    --@field __index any Fallback table or function used for missing fixture keys.
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

--Loads a repository Lua module as a test support value.
--@param relative_path string Repository-relative Lua source path to load.
--@return any module Test support module export loaded from the repository.
local function load_table(relative_path)
    local chunk, load_error = loadfile(YACA_TEST_ROOT .. "/" .. relative_path, "t", _ENV)
    A.truthy(chunk, load_error)
    return chunk()
end

--Reads read file for this test scenario.
--@param relative_path string Repository-relative Lua source path to load.
--@return any bytes Bytes read from the selected fixture file.
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

--Checks assert subset against this test expectation.
--@param expected any Expected value used by the assertion.
--@param actual any Observed value compared by the assertion.
--@param path string File or Context path exercised by the case.
--@return nil No value; the fake port or test assertion observes this callback's effects.
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

--Builds the capabilities values used by this suite.
--@param overrides table|nil Per-case overrides of default fixture behavior.
--@return any observed capabilities value observed by the scenario assertion.
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

--Constructs new renderer for this test scenario.
--@param overrides table|nil Per-case overrides of default fixture behavior.
--@return any created Constructed new renderer fixture value.
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

--Supplies visibility behavior required by this suite.
--@param enabled boolean Whether the selected feature is enabled.
--@return any observed visibility value observed by the scenario assertion.
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

--Supplies startup plain behavior required by this suite.
--@param renderer table Transcript renderer under test.
--@return any observed startup plain value observed by the scenario assertion.
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

--Constructs fixture outputs for this test scenario.
--@param renderer table Transcript renderer under test.
--@return table observed Structured fixture record selected by the exercised branch.
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

--Supplies strip ansi behavior required by this suite.
--@param value any Candidate whose acceptance or transformation the test checks.
--@return any observed strip ansi value observed by the scenario assertion.
local function strip_ansi(value)
    return (value:gsub("\27%[[0-9;]*m", ""))
end

--Checks assert render error against this test expectation.
--@param renderer table Transcript renderer under test.
--@param block table|string Transcript or storage block under test.
--@param expected any Expected value used by the assertion.
--@return any observed assert render error value observed by the scenario assertion.
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
            --Verifies tUI registry exactly enriches the frozen semantic projection.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify tUI registry exactly enriches the frozen semantic projection.
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
                --Executes the action expected to raise in the 'TUI registry exactly enriches the frozen semantic projection' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify tUI registry exactly enriches the frozen semantic projection.
                A.raises(function() renderer.extra = true end, "cannot be modified")
            end,
        },
        {
            name = "all frozen 40-column transcripts match their golden bytes",
            --Verifies all frozen 40-column transcripts match their golden bytes.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify all frozen 40-column transcripts match their golden bytes.
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
            --Verifies all frozen 40-column transcripts match their golden bytes.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify all frozen 40-column transcripts match their golden bytes.
            run = function()
                local renderer = new_renderer()
                local registry = tui.registry()
                for _, kind in ipairs({
                    "user", "assistant", "tool", "ask", "status", "queue", "steer",
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
            --Verifies untrusted controls Unicode controls and forged chrome become visible.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify untrusted controls Unicode controls and forged chrome become visible.
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
            --Verifies basic color changes no semantic text and never trusts input ANSI.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify basic color changes no semantic text and never trusts input ANSI.
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
            --Verifies append writes complete increasing blocks and faults on broken stdout.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify append writes complete increasing blocks and faults on broken stdout.
            run = function()
                local chunks = {}
                local renderer = new_renderer({
                    --Captures writer bytes in the append writes complete increasing blocks and faults on broken stdout scenario.
                    --@param bytes string Byte chunk supplied to the fake I/O port.
                    --@return boolean accepted Whether the fake callback accepts this scenario.
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

                local broken = new_renderer({
                    --Captures writer bytes in the append writes complete increasing blocks and faults on broken stdout scenario.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return boolean accepted Whether the fake callback accepts this scenario.
                    writer = function() return false end })
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
            --Verifies startup fields are independent ordered and cannot recreate a master switch.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify startup fields are independent ordered and cannot recreate a master switch.
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
            --Verifies input capability hints retain every shared text fallback.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify input capability hints retain every shared text fallback.
            run = function()
                local renderer = new_renderer()
                local expected = {
                    ["submit-or-queue"] = { "Enter", true, "queue-add", ".queue <message>" },
                    steer = { "Ctrl+Enter", false, "steer", ".immediate <message>" },
                    newline = { "Shift+Enter", false, "multiline", ".multiline" },
                    ask = { "Alt+Enter", false, "ask", ".ask <message>" },
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
            --Verifies renderer schemas and injected limits fail before truncating facts.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify renderer schemas and injected limits fail before truncating facts.
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
            --Verifies every focus uses the frozen ASCII prompt with safe draft projection.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify every focus uses the frozen ASCII prompt with safe draft projection.
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
