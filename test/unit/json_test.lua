--[[
File: json_test.lua
Date: 2026-08-29
Author: WaterRun
Description: Verifies strict bounded JSON parsing and deterministic writing.
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

local json = load_module("json")
local fixtures = load_table(".develope-docs/contracts/fixtures/formats.lua")

local function limits(overrides)
    local result = {
        maximum_bytes = 4096,
        maximum_depth = 16,
        maximum_nodes = 256,
        maximum_string_bytes = 1024,
        maximum_number_bytes = 128,
    }
    for key, value in pairs(overrides or {}) do result[key] = value end
    return result
end

local function codec(overrides)
    return assert(json.new(limits(overrides)))
end

return {
    name = "unit/json",
    cases = {
        {
            name = "contract fixtures distinguish every accepted and rejected profile",
            run = function()
                local service = codec()
                local expected_reason = {
                    ["top-string"] = "top-level",
                    ["duplicate-key"] = "duplicate-key",
                    bom = "bom",
                    nan = "number",
                    ["unpaired-surrogate"] = "surrogate",
                    control = "unescaped-control",
                }
                for _, case in ipairs(fixtures.json_cases) do
                    local value, parse_error = service.parse(case.bytes)
                    if case.valid then
                        A.truthy(value, case.id)
                        A.equal(json.kind(value), case.top_level)
                    else
                        A.falsy(value, case.id)
                        A.equal(parse_error.reason, expected_reason[case.id], case.id)
                    end
                end
            end,
        },
        {
            name = "objects arrays null and numbers retain explicit unambiguous kinds",
            run = function()
                local service = codec()
                local value = assert(service.parse(
                    [[{"emptyObject":{},"emptyArray":[],"n":null,"f":false,"z":-0,"e":1e2}]]
                ))
                A.equal(json.kind(value), "object")
                A.equal(json.kind(value.emptyObject), "object")
                A.equal(json.kind(value.emptyArray), "array")
                A.equal(json.kind(value.n), "null")
                A.equal(json.kind(value.f), "boolean")
                A.equal(json.kind(value.z), "number")
                A.equal(json.number_lexeme(value.z), "-0")
                A.equal(json.number_lexeme(value.e), "1e2")
                A.equal(service.write(value),
                    [[{"e":1e2,"emptyArray":[],"emptyObject":{},"f":false,"n":null,"z":-0}]]
                )
            end,
        },
        {
            name = "number grammar rejects prefixes nonfinite values and incomplete forms",
            run = function()
                local service = codec()
                local valid = {
                    "0", "-0", "10", "-10", "0.0", "1.25", "1e2", "1E+2", "1e-2",
                }
                local numbers = {}
                for index, lexeme in ipairs(valid) do
                    numbers[index] = assert(json.number(lexeme))
                end
                local array = assert(json.array(numbers))
                A.equal(
                    service.write(array),
                    "[" .. table.concat(valid, ",") .. "]"
                )
                local parsed = assert(service.parse(service.write(array)))
                for index, lexeme in ipairs(valid) do
                    A.equal(json.number_lexeme(parsed[index]), lexeme)
                end

                for _, source in ipairs({
                    "[01]", "[-01]", "[1.]", "[1e]", "[+1]", "[-]",
                    "[NaN]", "[Infinity]", "[-Infinity]",
                }) do
                    local value, parse_error = service.parse(source)
                    A.falsy(value, source)
                    A.truthy(
                        parse_error.reason == "number"
                            or parse_error.reason == "array-delimiter",
                        source .. ": " .. A.render(parse_error)
                    )
                end
                for _, lexeme in ipairs({ "01", "1.", "+1", "NaN", "Infinity" }) do
                    local number, number_error = json.number(lexeme)
                    A.falsy(number)
                    A.equal(number_error.code, "InvalidJsonNumber")
                end
            end,
        },
        {
            name = "strings enforce controls escapes and paired surrogate decoding",
            run = function()
                local service = codec()
                local value = assert(service.parse(
                    [[{"emoji":"\uD83D\uDE00","escaped":"\"\\\/\b\f\n\r\t\u0000"}]]
                ))
                A.equal(value.emoji, assert(load_module("text").encode_scalar(0x1F600)))
                A.equal(value.escaped, "\"\\/\b\f\n\r\t\0")
                A.equal(
                    service.write(value),
                    "{\"emoji\":\"😀\",\"escaped\":\"\\\"\\\\/\\b\\f\\n\\r\\t\\u0000\"}"
                )
                for _, source in ipairs({
                    [[{"x":"\uD800"}]],
                    [[{"x":"\uDC00"}]],
                    [[{"x":"\uD800\u0041"}]],
                    [[{"x":"\q"}]],
                    "{\"x\":\"\1\"}",
                }) do
                    local parsed = service.parse(source)
                    A.falsy(parsed, source)
                end
                local duplicate, duplicate_error = service.parse(
                    [[{"a":1,"\u0061":2}]]
                )
                A.falsy(duplicate)
                A.equal(duplicate_error.reason, "duplicate-key")
            end,
        },
        {
            name = "writer sorts UTF-8 keys and emits only required lowercase escapes",
            run = function()
                local service = codec()
                local object = assert(json.object({
                    ["é"] = "non-ascii",
                    a = "quote\" slash/ back\\",
                    A = "\0\1\b\f\n\r\t",
                }))
                local encoded = assert(service.write(object))
                A.equal(
                    encoded,
                    "{\"A\":\"\\u0000\\u0001\\b\\f\\n\\r\\t\","
                        .. "\"a\":\"quote\\\" slash/ back\\\\\","
                        .. "\"é\":\"non-ascii\"}"
                )
                A.falsy(encoded:find("\\/", 1, true))
                A.falsy(encoded:find("\\u00E9", 1, true))
                A.equal(service.write(assert(service.parse(encoded))), encoded)
            end,
        },
        {
            name = "parser and writer enforce every injected hard limit",
            run = function()
                local too_many_bytes = codec({ maximum_bytes = 8, maximum_string_bytes = 8,
                    maximum_number_bytes = 8 })
                local value, limit_error = too_many_bytes.parse("[\"123456\"]")
                A.falsy(value)
                A.equal(limit_error.code, "JsonLimit")

                local depth_codec = codec({ maximum_depth = 2 })
                A.truthy(depth_codec.parse("[[0]]"))
                local deep, depth_error = depth_codec.parse("[[[0]]]")
                A.falsy(deep)
                A.equal(depth_error.reason, "depth")

                local node_codec = codec({ maximum_nodes = 3 })
                A.truthy(node_codec.parse("[1,2]"))
                local nodes, node_error = node_codec.parse("[1,2,3]")
                A.falsy(nodes)
                A.equal(node_error.reason, "nodes")

                local string_codec = codec({ maximum_string_bytes = 3 })
                local long_string, string_error = string_codec.parse("[\"abcd\"]")
                A.falsy(long_string)
                A.equal(string_error.reason, "string-bytes")

                local number_codec = codec({ maximum_number_bytes = 3 })
                local long_number, number_error = number_codec.parse("[1234]")
                A.falsy(long_number)
                A.equal(number_error.reason, "number-bytes")

                local deepest = assert(json.array({}))
                local middle = assert(json.array({ deepest }))
                local nested = assert(json.array({ middle }))
                local output, output_error = depth_codec.write(nested)
                A.falsy(output)
                A.equal(output_error.code, "JsonLimit")
                A.raises(function() depth_codec.limits.maximum_depth = 99 end, "cannot be modified")
            end,
        },
        {
            name = "writer rejects ambiguous Lua values cycles and malformed containers",
            run = function()
                local service = codec()
                local raw_number = assert(json.object({ n = 1 / 0 }))
                local encoded, value_error = service.write(raw_number)
                A.falsy(encoded)
                A.equal(value_error.code, "InvalidJsonValue")

                local cyclic = assert(json.array({}))
                cyclic[1] = cyclic
                local cycle_output, cycle_error = service.write(cyclic)
                A.falsy(cycle_output)
                A.equal(cycle_error.code, "JsonCycle")

                local sparse = assert(json.array({ "a", "b" }))
                sparse[4] = "d"
                local sparse_output, sparse_error = service.write(sparse)
                A.falsy(sparse_output)
                A.equal(sparse_error.code, "InvalidJsonArray")

                local object = assert(json.object({ a = true }))
                object[1] = false
                local object_output, object_error = service.write(object)
                A.falsy(object_output)
                A.equal(object_error.code, "InvalidJsonObject")

                local invalid_utf8 = assert(json.array({ string.char(0xFF) }))
                local invalid_output, utf8_error = service.write(invalid_utf8)
                A.falsy(invalid_output)
                A.equal(utf8_error.code, "InvalidUtf8")

                local top_output, top_error = service.write("text")
                A.falsy(top_output)
                A.equal(top_error.code, "JsonTopLevel")
            end,
        },
        {
            name = "codec rejects BOM invalid UTF-8 trailing data and unknown limit fields",
            run = function()
                local service = codec()
                local bom, bom_error = service.parse("\239\187\191{}")
                A.falsy(bom)
                A.equal(bom_error.reason, "bom")
                local invalid, utf8_error = service.parse("[\"\255\"]")
                A.falsy(invalid)
                A.equal(utf8_error.code, "InvalidUtf8")
                local trailing, trailing_error = service.parse("{} []")
                A.falsy(trailing)
                A.equal(trailing_error.reason, "trailing-data")
                local unknown, limits_error = json.new({
                    maximum_bytes = 10,
                    maximum_depth = 2,
                    maximum_nodes = 2,
                    maximum_string_bytes = 5,
                    maximum_number_bytes = 5,
                    permissive = true,
                })
                A.falsy(unknown)
                A.equal(limits_error.code, "InvalidJsonLimits")
            end,
        },
    },
}
