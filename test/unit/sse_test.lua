--[[
File: sse_test.lua
Date: 2026-08-29
Author: WaterRun
Description: Verifies bounded exact Server-Sent Events parsing.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

local function load_module(name, cache)
    cache = cache or {}
    if cache[name] then return cache[name] end
    local environment = {}
    for key, value in pairs(_ENV) do environment[key] = value end
    environment.require = function(dependency)
        return load_module(dependency, cache)
    end
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

local function parser(network, overrides)
    local options = {
        maximum_line_bytes = 256,
        maximum_event_bytes = 1024,
        maximum_buffered_bytes = 2048,
        maximum_events_per_push = 32,
    }
    for key, value in pairs(overrides or {}) do options[key] = value end
    return assert(network.new_sse_parser(options))
end

local function collect(network, chunks, options)
    local instance = parser(network, options)
    local events = {}
    for _, chunk in ipairs(chunks) do
        local produced, parse_error = instance:push(chunk)
        if not produced then return nil, parse_error end
        for _, event in ipairs(produced) do events[#events + 1] = event end
    end
    local produced, finish_error = instance:finish()
    if not produced then return nil, finish_error end
    for _, event in ipairs(produced) do events[#events + 1] = event end
    return events
end

local function data_values(events)
    local result = {}
    for index, event in ipairs(events) do result[index] = event.data end
    return result
end

return {
    name = "unit/sse",
    cases = {
        {
            name = "frozen SSE corpus is invariant at every byte split",
            run = function()
                local network = load_module("network")
                local fixtures = assert(loadfile(
                    YACA_TEST_ROOT .. "/.develope-docs/contracts/fixtures/formats.lua",
                    "t",
                    _ENV
                ))().sse_cases
                for _, fixture in ipairs(fixtures) do
                    for split = 0, #fixture.bytes do
                        local events, parse_error = collect(network, {
                            fixture.bytes:sub(1, split),
                            fixture.bytes:sub(split + 1),
                        })
                        if fixture.valid then
                            A.truthy(events, fixture.id .. " split " .. tostring(split))
                            A.deep_equal(data_values(events), fixture.dispatch)
                        else
                            A.falsy(events, fixture.id .. " split " .. tostring(split))
                            if fixture.error == "bom" then
                                A.equal(parse_error.code, "SseBom")
                            else
                                A.equal(parse_error.code, "SseIncomplete")
                            end
                        end
                    end
                end
            end,
        },
        {
            name = "LF CRLF and CR preserve event data and diagnostic id semantics",
            run = function()
                local network = load_module("network")
                local bytes = table.concat({
                    ": comment\r",
                    "unknown: ignored\n",
                    "id: first\r\n",
                    "event: custom\r",
                    "retry: 1\n",
                    "data: one\r\n",
                    "data:two\r",
                    "\r",
                    "data:\n\n",
                    "id: bad\0id\n",
                    "data: last\n\n",
                })
                local events = assert(collect(network, { bytes }))
                A.equal(#events, 3)
                A.equal(events[1].event, "custom")
                A.equal(events[1].data, "one\ntwo")
                A.equal(events[1].id, "first")
                A.equal(events[2].event, "message")
                A.equal(events[2].data, "")
                A.equal(events[2].id, "first")
                A.equal(events[3].data, "last")
                A.equal(events[3].id, "first")
                A.raises(function() events[1].data = "changed" end, "cannot be modified")
            end,
        },
        {
            name = "CRLF and multibyte scalars survive one-byte chunking",
            run = function()
                local network = load_module("network")
                local bytes = "event: 路径\r\ndata: 你\r\ndata: 好\r\n\r\n"
                local chunks = {}
                for index = 1, #bytes do chunks[index] = bytes:sub(index, index) end
                local events = assert(collect(network, chunks))
                A.equal(#events, 1)
                A.equal(events[1].event, "路径")
                A.equal(events[1].data, "你\n好")
            end,
        },
        {
            name = "BOM invalid UTF-8 and EOF never synthesize a partial event",
            run = function()
                local network = load_module("network")
                local bom = string.char(0xEF, 0xBB, 0xBF)
                local instance = parser(network)
                A.deep_equal(assert(instance:push(bom:sub(1, 1))), {})
                A.deep_equal(assert(instance:push(bom:sub(2, 2))), {})
                local events, parse_error = instance:push(bom:sub(3) .. "data: x\n\n")
                A.falsy(events)
                A.equal(parse_error.code, "SseBom")
                A.equal(select(1, instance:status()), "failed")
                local repeated, repeated_error = instance:push("data: ignored\n\n")
                A.falsy(repeated)
                A.equal(repeated_error.code, "SseBom")

                local invalid = parser(network)
                local invalid_events, invalid_error = invalid:push(
                    "data: " .. string.char(0xC0, 0xAF) .. "\n\n"
                )
                A.falsy(invalid_events)
                A.equal(invalid_error.code, "SseUtf8")

                local incomplete = parser(network)
                A.deep_equal(assert(incomplete:push("data: partial\n")), {})
                local final_events, final_error = incomplete:finish()
                A.falsy(final_events)
                A.equal(final_error.code, "SseIncomplete")

                local empty = parser(network)
                A.deep_equal(assert(empty:finish()), {})
            end,
        },
        {
            name = "line event buffer and output limits fail sticky and bounded",
            run = function()
                local network = load_module("network")
                local line = parser(network, {
                    maximum_line_bytes = 4,
                    maximum_event_bytes = 8,
                    maximum_buffered_bytes = 12,
                })
                local line_events, line_error = line:push("data:")
                A.falsy(line_events)
                A.equal(line_error.code, "SseLineLimit")

                local event = parser(network, {
                    maximum_line_bytes = 8,
                    maximum_event_bytes = 8,
                    maximum_buffered_bytes = 16,
                })
                local event_events, event_error = event:push("data: x\ndata: y\n")
                A.falsy(event_events)
                A.equal(event_error.code, "SseEventLimit")

                local buffer = parser(network, {
                    maximum_line_bytes = 8,
                    maximum_event_bytes = 8,
                    maximum_buffered_bytes = 8,
                })
                local buffer_events, buffer_error = buffer:push("123456789")
                A.falsy(buffer_events)
                A.equal(buffer_error.code, "SseBufferLimit")

                local output = parser(network, { maximum_events_per_push = 1 })
                local output_events, output_error = output:push("data: 1\n\ndata: 2\n\n")
                A.falsy(output_events)
                A.equal(output_error.code, "SseOutputLimit")
            end,
        },
        {
            name = "constructor and lifecycle reject ambiguous limits and reuse",
            run = function()
                local network = load_module("network")
                local rejected, option_error = network.new_sse_parser({
                    maximum_line_bytes = 10,
                    maximum_event_bytes = 20,
                    maximum_buffered_bytes = 10,
                    maximum_events_per_push = 1,
                })
                A.falsy(rejected)
                A.equal(option_error.code, "InvalidSseOptions")
                local instance = parser(network)
                A.deep_equal(assert(instance:push("data: ok\n\n"))[1].data, "ok")
                A.deep_equal(assert(instance:finish()), {})
                local reused, state_error = instance:push("")
                A.falsy(reused)
                A.equal(state_error.code, "SseState")
            end,
        },
    },
}
