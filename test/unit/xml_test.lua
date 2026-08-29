--[[
File: xml_test.lua
Date: 2026-08-29
Author: WaterRun
Description: Verifies bounded XML streaming, security callbacks, and byte carriers.
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

local xml = load_module("xml")
local fake_lxp = load_table("test/support/fake_lxp.lua")
local fixtures = load_table(".develope-docs/contracts/fixtures/formats.lua")

local function scripted_dispatch(document, callbacks)
    if document == "simple" then
        callbacks.XmlDecl(nil, "1.0", "UTF-8")
        callbacks.StartElement(nil, "Root", { id = "one", [1] = "id" })
        callbacks.CharacterData(nil, "a")
        callbacks.CharacterData(nil, "b")
        callbacks.StartElement(nil, "Child", {})
        callbacks.EndElement(nil, "Child")
        callbacks.CharacterData(nil, "tail")
        callbacks.EndElement(nil, "Root")
    elseif document == "dtd" then
        callbacks.StartDoctypeDecl(nil, "Root", nil, nil, true)
    elseif document == "entity" then
        callbacks.EntityDecl(nil, "name", false, "value")
    elseif document == "external" then
        callbacks.ExternalEntityRef(nil, {}, nil, "file:///secret", nil)
    elseif document == "pi" then
        callbacks.ProcessingInstruction(nil, "unsafe", "data")
    elseif document == "encoding" then
        callbacks.XmlDecl(nil, "1.0", "ISO-8859-1")
    elseif document == "deep" then
        for index = 1, 5 do callbacks.StartElement(nil, "N" .. index, {}) end
        for index = 5, 1, -1 do callbacks.EndElement(nil, "N" .. index) end
    elseif document == "attributes" then
        callbacks.StartElement(nil, "Root", { a = "1", b = "2", c = "3" })
        callbacks.EndElement(nil, "Root")
    elseif document == "large-text" then
        callbacks.StartElement(nil, "Root", {})
        callbacks.CharacterData(nil, "abc")
        callbacks.CharacterData(nil, "def")
        callbacks.EndElement(nil, "Root")
    elseif document == "many-elements" then
        callbacks.StartElement(nil, "Root", {})
        callbacks.StartElement(nil, "One", {})
        callbacks.EndElement(nil, "One")
        callbacks.StartElement(nil, "Two", {})
        callbacks.EndElement(nil, "Two")
        callbacks.EndElement(nil, "Root")
    elseif document == "many-events" then
        callbacks.StartElement(nil, "Facts", {})
        for _ = 1, 3 do
            callbacks.StartElement(nil, "Event", {})
            callbacks.EndElement(nil, "Event")
        end
        callbacks.EndElement(nil, "Facts")
    elseif document == "large-carrier" then
        callbacks.StartElement(nil, "Field", { rawBytes = "99" })
        callbacks.EndElement(nil, "Field")
    elseif document == "syntax" then
        return false, "mismatched tag", 2, 7, 19
    else
        error("unknown fake XML scenario: " .. document)
    end
    return true
end

local function options(dispatch, overrides)
    local lxp = fake_lxp(dispatch or scripted_dispatch)
    local result = {
        lxp = lxp,
        maximum_bytes = 4096,
        maximum_depth = 16,
        maximum_elements = 128,
        maximum_attributes_per_element = 8,
        maximum_text_node_bytes = 1024,
        maximum_total_text_bytes = 2048,
        maximum_sax_events = 512,
        maximum_context_events = 64,
        maximum_carrier_bytes = 1024,
        maximum_chunk_bytes = 3,
    }
    for key, value in pairs(overrides or {}) do result[key] = value end
    return result, lxp
end

local function codec(overrides, dispatch)
    local candidate, lxp = options(dispatch, overrides)
    return assert(xml.new(candidate)), lxp
end

return {
    name = "unit/xml",
    cases = {
        {
            name = "format fixtures select lossless text base64 and missing carriers",
            run = function()
                local service = codec()
                for _, case in ipairs(fixtures.xml_text_cases) do
                    local carrier = assert(xml.carrier(case.bytes))
                    local info = assert(xml.carrier_info(carrier))
                    if case.present == false then
                        A.falsy(info.present, case.id)
                        A.equal(info.representation, "missing", case.id)
                    else
                        A.truthy(info.present, case.id)
                        A.equal(info.representation, case.representation, case.id)
                        A.equal(info.encoded, case.encoded, case.id)
                        A.equal(assert(xml.carrier_bytes(carrier)), case.bytes, case.id)
                        local parsed_content = info.representation == "text"
                            and case.bytes
                            or info.encoded
                        local decoded = assert(service.decode_carrier(
                            info.representation,
                            parsed_content,
                            info.raw_bytes
                        ))
                        A.equal(assert(xml.carrier_bytes(decoded)), case.bytes, case.id)
                    end
                end
                local forced = assert(xml.binary("plain"))
                A.equal(xml.carrier_info(forced).representation, "base64")
                A.equal(xml.carrier_info(forced).encoded, "cGxhaW4=")
                A.falsy(xml.carrier_bytes(xml.missing))
            end,
        },
        {
            name = "base64 decoder is strict canonical and byte-count aware",
            run = function()
                local service = codec()
                local valid = assert(service.decode_carrier("base64", "AAECAw==", 4))
                A.equal(assert(xml.carrier_bytes(valid)), "\0\1\2\3")
                local cases = {
                    { "A", "base64-length" },
                    { "A===", "base64-character" },
                    { "Zh==", "base64-pad-bits" },
                    { "Zm9=", "base64-pad-bits" },
                    { "Zg==AAAA", "base64-padding" },
                    { "Zg=Z", "base64-padding" },
                    { "Zg==\n", "base64-length" },
                }
                for _, case in ipairs(cases) do
                    local carrier, decode_error = service.decode_carrier("base64", case[1])
                    A.falsy(carrier)
                    A.equal(decode_error.reason, case[2])
                end
                local mismatch, mismatch_error = service.decode_carrier("base64", "Zg==", 2)
                A.falsy(mismatch)
                A.equal(mismatch_error.code, "InvalidXmlCarrier")
            end,
        },
        {
            name = "reader merges native text callbacks and reports stable element paths",
            run = function()
                local service, lxp = codec()
                local events = {}
                local reader = assert(service.new_reader({
                    start_element = function(name, attributes, path)
                        events[#events + 1] = "start:" .. path .. ":" .. (attributes.id or "")
                    end,
                    text = function(value, path)
                        events[#events + 1] = "text:" .. path .. ":" .. value
                    end,
                    end_element = function(_, path)
                        events[#events + 1] = "end:" .. path
                    end,
                }))
                A.truthy(reader.feed("si"))
                A.truthy(reader.feed("mple"))
                local stats = assert(reader.finish())
                A.deep_equal(events, {
                    "start:/Root:one",
                    "text:/Root:ab",
                    "start:/Root/Child:",
                    "end:/Root/Child",
                    "text:/Root:tail",
                    "end:/Root",
                })
                A.equal(stats.elements, 2)
                A.equal(stats.maximum_depth_observed, 2)
                A.equal(stats.external_entity_opens, 0)
                A.truthy(lxp.observations.maximum_chunk_bytes <= 3)
                A.equal(lxp.observations.merge_character_data, false)
                A.falsy(reader.feed("later"))
            end,
        },
        {
            name = "DTD entities external reads processing instructions and encodings reject",
            run = function()
                local service = codec()
                local cases = {
                    { "dtd", "XmlSecurity", "dtd" },
                    { "entity", "XmlSecurity", "entity" },
                    { "external", "XmlSecurity", "external-entity" },
                    { "pi", "XmlSecurity", "processing-instruction" },
                    { "encoding", "XmlSyntax", "encoding" },
                }
                for _, case in ipairs(cases) do
                    local stats, parse_error = service.parse(case[1])
                    A.falsy(stats)
                    A.equal(parse_error.code, case[2])
                    A.equal(parse_error.reason, case[3])
                    A.truthy(parse_error.path)
                end
            end,
        },
        {
            name = "reader enforces every structural and byte release limit",
            run = function()
                local cases = {
                    { "deep", { maximum_depth = 4 }, "depth" },
                    { "attributes", { maximum_attributes_per_element = 2 }, "attributes" },
                    { "large-text", { maximum_text_node_bytes = 5 }, "text-node" },
                    { "large-text", { maximum_total_text_bytes = 5 }, "total-text" },
                    { "many-elements", { maximum_elements = 2 }, "elements" },
                    { "many-events", { maximum_context_events = 2 }, "events" },
                    { "large-carrier", { maximum_carrier_bytes = 8 }, "carrier" },
                    { "simple", { maximum_sax_events = 3 }, "sax-events" },
                    { "simple", { maximum_bytes = 5, maximum_chunk_bytes = 2 }, "bytes" },
                }
                for _, case in ipairs(cases) do
                    local overrides = case[2]
                    if overrides.maximum_bytes then
                        overrides.maximum_text_node_bytes = 5
                        overrides.maximum_total_text_bytes = 5
                        overrides.maximum_carrier_bytes = 5
                    end
                    local service = codec(overrides)
                    local stats, parse_error = service.parse(case[1])
                    A.falsy(stats, case[1])
                    A.equal(parse_error.code, "XmlLimit", case[1])
                    A.equal(parse_error.reason, case[3], case[1])
                end
            end,
        },
        {
            name = "well-formed and consumer failures keep typed positions",
            run = function()
                local service = codec()
                local stats, parse_error = service.parse("syntax")
                A.falsy(stats)
                A.equal(parse_error.code, "XmlSyntax")
                A.equal(parse_error.reason, "well-formed")
                A.equal(parse_error.line, 2)
                A.equal(parse_error.column, 7)
                A.equal(parse_error.offset, 19)

                local consumed, consumer_error = service.parse("simple", {
                    start_element = function() return false, "schema rejected element" end,
                })
                A.falsy(consumed)
                A.equal(consumer_error.code, "XmlConsumer")
                A.equal(consumer_error.message, "schema rejected element")
            end,
        },
        {
            name = "writer emits fixed names ordered attributes escapes and typed carriers",
            run = function()
                local service = codec()
                local output = {}
                local writer = assert(service.new_writer(function(bytes)
                    output[#output + 1] = bytes
                end))
                A.truthy(writer.declaration())
                A.truthy(writer.start_element("Root", {
                    { name = "first", value = "a<&>\"'" },
                    { name = "second", value = "two" },
                }))
                A.truthy(writer.start_element("Text"))
                A.truthy(writer.text("a<&>\"'"))
                A.truthy(writer.end_element("Text"))
                A.truthy(writer.start_element("Field", {
                    { name = "representation", value = "base64" },
                    { name = "rawBytes", value = "3" },
                }))
                A.truthy(writer.carrier(assert(xml.binary("a\0b"))))
                A.truthy(writer.end_element("Field"))
                A.truthy(writer.empty_element("Empty"))
                A.truthy(writer.end_element("Root"))
                local stats = assert(writer.finish())
                A.equal(table.concat(output), table.concat({
                    '<?xml version="1.0" encoding="UTF-8"?>\n',
                    '<Root first="a&lt;&amp;&gt;&quot;&apos;" second="two">',
                    "<Text>a&lt;&amp;&gt;&quot;&apos;</Text>",
                    '<Field representation="base64" rawBytes="3">YQBi</Field>',
                    "<Empty/>",
                    "</Root>",
                }))
                A.equal(stats.elements, 4)
                A.equal(stats.maximum_depth_observed, 2)
            end,
        },
        {
            name = "writer rejects ambiguous names text sequences attributes and sink failures",
            run = function()
                local service = codec()
                local writer = assert(service.new_writer(function() end))
                A.falsy(writer.start_element("Root"))
                A.truthy(writer.declaration())
                A.falsy(writer.start_element("x:name"))
                local duplicate, duplicate_error = writer.start_element("Root", {
                    { name = "a", value = "1" },
                    { name = "a", value = "2" },
                })
                A.falsy(duplicate)
                A.equal(duplicate_error.code, "InvalidXmlAttributes")
                A.truthy(writer.start_element("Root"))
                A.falsy(writer.text("a\rb"))
                A.falsy(writer.text("a\0b"))
                A.falsy(writer.end_element("Wrong"))
                A.truthy(writer.end_element("Root"))
                A.truthy(writer.finish())
                A.falsy(writer.empty_element("Later"))

                local sink_writer = assert(service.new_writer(function()
                    return false, "disk full"
                end))
                local emitted, sink_error = sink_writer.declaration()
                A.falsy(emitted)
                A.equal(sink_error.code, "XmlSinkFailure")
                A.equal(sink_error.message, "disk full")
            end,
        },
        {
            name = "dependency identity options carrier caps and services fail closed",
            run = function()
                local candidate = options()
                candidate.lxp._EXPAT_VERSION = "expat_2.8.1"
                local service, dependency_error = xml.new(candidate)
                A.falsy(service)
                A.equal(dependency_error.code, "XmlDependencyMismatch")

                local unknown = options()
                unknown.surprise = true
                local invalid, options_error = xml.new(unknown)
                A.falsy(invalid)
                A.equal(options_error.code, "InvalidXmlOptions")

                local bounded = codec({ maximum_carrier_bytes = 2 })
                local carrier, carrier_error = bounded.decode_carrier("base64", "YWJj", 3)
                A.falsy(carrier)
                A.equal(carrier_error.reason, "carrier")
                A.raises(function() bounded.limits.maximum_depth = 99 end, "cannot be modified")
                A.falsy(bounded.new_reader({ unknown = function() end }))
                A.falsy(bounded.new_writer({}))
            end,
        },
    },
}
