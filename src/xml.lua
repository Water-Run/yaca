--[[
File: xml.lua
Date: 2026-08-29
Author: WaterRun
Description: Provides a bounded LuaExpat reader and narrow streaming XML writer.
]]

local text = require("text")

local M = {}

local carrier_states = setmetatable({}, { __mode = "k" })
local ABORT_MARKER = "yaca-xml-reader-abort"
local BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local BASE64_REVERSE = {}
for index = 1, #BASE64 do BASE64_REVERSE[BASE64:byte(index)] = index - 1 end

local function failure(code, message, reason, path, line, column, offset)
    local result = { code = code, message = message }
    if reason ~= nil then result.reason = reason end
    if path ~= nil then result.path = path end
    if line ~= nil then result.line = line end
    if column ~= nil then result.column = column end
    if offset ~= nil then result.offset = offset end
    return result
end

local function readonly(values, label)
    return setmetatable({}, {
        __index = values,
        __newindex = function(_, key)
            error((label or "readonly value") .. " cannot be modified: " .. tostring(key), 2)
        end,
        __pairs = function()
            return next, values, nil
        end,
        __metatable = "locked",
    })
end

local function valid_integer(value, minimum)
    return math.type(value) == "integer" and value >= minimum
end

local function dense_array_length(values)
    if type(values) ~= "table" then return nil end
    local count = 0
    for key in pairs(values) do
        if math.type(key) ~= "integer" or key < 1 then return nil end
        count = count + 1
    end
    for index = 1, count do
        if values[index] == nil then return nil end
    end
    return count
end

local function encode_base64(value)
    local output = {}
    local index = 1
    while index <= #value do
        local first = value:byte(index)
        local second = value:byte(index + 1)
        local third = value:byte(index + 2)
        local packed = first * 0x10000 + (second or 0) * 0x100 + (third or 0)
        local a = (packed // 0x40000) % 64
        local b = (packed // 0x1000) % 64
        local c = (packed // 0x40) % 64
        local d = packed % 64
        output[#output + 1] = BASE64:sub(a + 1, a + 1)
        output[#output + 1] = BASE64:sub(b + 1, b + 1)
        output[#output + 1] = second and BASE64:sub(c + 1, c + 1) or "="
        output[#output + 1] = third and BASE64:sub(d + 1, d + 1) or "="
        index = index + 3
    end
    return table.concat(output)
end

local function escaped_xml(value)
    return (value
        :gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
        :gsub("\"", "&quot;")
        :gsub("'", "&apos;"))
end

local function decode_base64(value)
    if type(value) ~= "string" or #value % 4 ~= 0 then
        return nil, failure("InvalidXmlCarrier", "base64 length is invalid", "base64-length")
    end
    local output = {}
    for index = 1, #value, 4 do
        local first, second, third, fourth = value:byte(index, index + 3)
        local a = BASE64_REVERSE[first]
        local b = BASE64_REVERSE[second]
        local c = third == 0x3D and 0 or BASE64_REVERSE[third]
        local d = fourth == 0x3D and 0 or BASE64_REVERSE[fourth]
        if a == nil or b == nil or c == nil or d == nil then
            return nil, failure(
                "InvalidXmlCarrier",
                "base64 contains a forbidden character",
                "base64-character"
            )
        end
        local final_group = index + 3 == #value
        if first == 0x3D or second == 0x3D
            or (third == 0x3D and fourth ~= 0x3D)
            or ((third == 0x3D or fourth == 0x3D) and not final_group)
        then
            return nil, failure("InvalidXmlCarrier", "base64 padding is invalid", "base64-padding")
        end
        if third == 0x3D and b % 16 ~= 0 then
            return nil, failure(
                "InvalidXmlCarrier",
                "base64 pad bits are non-zero",
                "base64-pad-bits"
            )
        end
        if fourth == 0x3D and third ~= 0x3D and c % 4 ~= 0 then
            return nil, failure(
                "InvalidXmlCarrier",
                "base64 pad bits are non-zero",
                "base64-pad-bits"
            )
        end
        local packed = a * 0x40000 + b * 0x1000 + c * 0x40 + d
        output[#output + 1] = string.char((packed // 0x10000) % 0x100)
        if third ~= 0x3D then
            output[#output + 1] = string.char((packed // 0x100) % 0x100)
        end
        if fourth ~= 0x3D then output[#output + 1] = string.char(packed % 0x100) end
    end
    return table.concat(output)
end

local function new_carrier(present, representation, bytes)
    local values = {
        present = present,
        representation = representation,
        bytes = bytes,
        raw_bytes = bytes and #bytes or nil,
    }
    local carrier = readonly(values, "XML carrier")
    carrier_states[carrier] = values
    return carrier
end

M.missing = new_carrier(false, "missing", nil)

---Creates a lossless XML text/base64 carrier, retaining missing separately.
-- Strict XML-1.0-safe, CR-free UTF-8 uses text; all other exact bytes use
-- standard padded base64. Invalid UTF-8 is therefore never replaced.
-- @param bytes string|nil Exact bytes, or nil for a missing field.
-- @return table|nil carrier Immutable typed carrier.
-- @return table|nil err Structured input failure.
function M.carrier(bytes)
    if bytes == nil then return M.missing end
    if type(bytes) ~= "string" then
        return nil, failure("InvalidXmlCarrier", "carrier input must be bytes or nil")
    end
    local kind = assert(text.xml_carrier_kind(bytes))
    return new_carrier(true, kind == "text" and "text" or "base64", bytes)
end

---Creates a forced binary base64 carrier from exact bytes.
-- @param bytes string Exact arbitrary bytes.
-- @return table|nil carrier Immutable base64 carrier.
-- @return table|nil err Structured type failure.
function M.binary(bytes)
    if type(bytes) ~= "string" then
        return nil, failure("InvalidXmlCarrier", "binary carrier input must be bytes")
    end
    return new_carrier(true, "base64", bytes)
end

---Returns immutable public metadata and encoded content for a carrier.
-- @param carrier table Carrier created by this module.
-- @return table|nil info Presence, representation, size, and encoded content.
-- @return table|nil err Structured carrier failure.
function M.carrier_info(carrier)
    local state = carrier_states[carrier]
    if not state then
        return nil, failure("InvalidXmlCarrier", "value is not an XML carrier")
    end
    if not state.present then
        return readonly({ present = false, representation = "missing" }, "XML carrier info")
    end
    return readonly({
        present = true,
        representation = state.representation,
        raw_bytes = state.raw_bytes,
        encoded = state.representation == "base64"
            and encode_base64(state.bytes)
            or escaped_xml(state.bytes),
    }, "XML carrier info")
end

---Returns the exact canonical bytes held by a present XML carrier.
-- @param carrier table Carrier created by this module.
-- @return string|nil bytes Exact original bytes; nil for missing.
-- @return table|nil err Structured carrier failure or missing marker.
function M.carrier_bytes(carrier)
    local state = carrier_states[carrier]
    if not state then
        return nil, failure("InvalidXmlCarrier", "value is not an XML carrier")
    end
    if not state.present then
        return nil, failure("XmlCarrierMissing", "XML carrier is explicitly missing")
    end
    return state.bytes
end

local function validate_lxp(lxp)
    if type(lxp) ~= "table" or type(lxp.new) ~= "function" then
        return nil, failure("InvalidXmlDependency", "lxp module does not expose new")
    end
    if lxp._VERSION ~= "LuaExpat 1.5.2" then
        return nil, failure(
            "XmlDependencyMismatch",
            "LuaExpat runtime is not the pinned version"
        )
    end
    if lxp._EXPAT_VERSION ~= "expat_2.8.2" then
        return nil, failure("XmlDependencyMismatch", "Expat runtime is not the pinned version")
    end
    if type(lxp._EXPAT_FEATURES) ~= "table" then
        return nil, failure("InvalidXmlDependency", "Expat feature manifest is unavailable")
    end
    return true
end

local LIMIT_NAMES = {
    "maximum_bytes",
    "maximum_depth",
    "maximum_elements",
    "maximum_attributes_per_element",
    "maximum_text_node_bytes",
    "maximum_total_text_bytes",
    "maximum_sax_events",
    "maximum_context_events",
    "maximum_carrier_bytes",
    "maximum_chunk_bytes",
}

local function validate_options(options)
    if type(options) ~= "table" then
        return nil, failure("InvalidXmlOptions", "XML codec options are required")
    end
    local allowed = { lxp = true }
    for _, name in ipairs(LIMIT_NAMES) do allowed[name] = true end
    for key in pairs(options) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure("InvalidXmlOptions", "XML options contain an unknown field")
        end
    end
    local valid_lxp, lxp_error = validate_lxp(options.lxp)
    if not valid_lxp then return nil, lxp_error end
    local limits = {}
    for _, name in ipairs(LIMIT_NAMES) do
        if not valid_integer(options[name], 1) then
            return nil, failure("InvalidXmlOptions", name .. " must be a positive integer")
        end
        limits[name] = options[name]
    end
    for _, name in ipairs({
        "maximum_text_node_bytes",
        "maximum_total_text_bytes",
        "maximum_carrier_bytes",
        "maximum_chunk_bytes",
    }) do
        if limits[name] > limits.maximum_bytes then
            return nil, failure("InvalidXmlOptions", name .. " must not exceed maximum_bytes")
        end
    end
    return { lxp = options.lxp, limits = limits }
end

local function path_string(stack)
    if #stack == 0 then return "/" end
    return "/" .. table.concat(stack, "/")
end

local function parser_position(parser)
    if type(parser) ~= "userdata" and type(parser) ~= "table" then return nil end
    local ok, line, column, offset = pcall(parser.pos, parser)
    if not ok then return nil end
    return line, column, offset
end

local function positioned(error_value, parser, stack)
    if error_value.path == nil then error_value.path = path_string(stack) end
    if error_value.line == nil then
        local line, column, offset = parser_position(parser)
        error_value.line = line
        error_value.column = column
        error_value.offset = offset
    end
    return error_value
end

local function validate_sink(sink)
    sink = sink or {}
    if type(sink) ~= "table" then
        return nil, failure("InvalidXmlSink", "XML reader sink must be a table")
    end
    local allowed = { start_element = true, text = true, end_element = true }
    for key, value in pairs(sink) do
        if type(key) ~= "string" or not allowed[key] or type(value) ~= "function" then
            return nil, failure("InvalidXmlSink", "XML reader sink is malformed")
        end
    end
    return sink
end

local function at_most_decimal(value, maximum)
    if type(value) ~= "string" or not value:match("^[0-9]+$") then return nil end
    if #value > 1 and value:sub(1, 1) == "0" then return nil end
    local boundary = tostring(maximum)
    if #value ~= #boundary then return #value < #boundary end
    return value <= boundary
end

local function new_reader(admitted, sink)
    local limits = admitted.limits
    local state = {
        bytes = 0,
        depth = 0,
        depth_peak = 0,
        elements = 0,
        attributes_peak = 0,
        text_bytes = 0,
        sax_events = 0,
        context_events = 0,
        stack = {},
        pending_text = {},
        pending_text_bytes = 0,
        finished = false,
        closed = false,
        failed = nil,
    }
    local parser

    local function abort(error_value)
        if not state.failed then
            state.failed = positioned(error_value, parser, state.stack)
        end
        error(ABORT_MARKER, 0)
    end

    local function admit_sax_event()
        state.sax_events = state.sax_events + 1
        if state.sax_events > limits.maximum_sax_events then
            abort(failure("XmlLimit", "XML exceeds maximum_sax_events", "sax-events"))
        end
    end

    local function invoke(name, ...)
        local callback = sink[name]
        if not callback then return end
        local ok, accepted, consumer_error = pcall(callback, ...)
        if not ok then
            abort(failure("XmlConsumer", "XML consumer raised an error", "consumer"))
        end
        if accepted == false then
            local message = type(consumer_error) == "string"
                and consumer_error
                or "XML consumer rejected an event"
            abort(failure("XmlConsumer", message, "consumer"))
        end
    end

    local function flush_text()
        if state.pending_text_bytes == 0 then return end
        local value = table.concat(state.pending_text)
        state.pending_text = {}
        state.pending_text_bytes = 0
        admit_sax_event()
        invoke("text", value, path_string(state.stack))
    end

    local callbacks = {}

    callbacks.StartElement = function(_, name, attributes)
        flush_text()
        state.depth = state.depth + 1
        state.elements = state.elements + 1
        if state.depth > state.depth_peak then state.depth_peak = state.depth end
        if state.depth > limits.maximum_depth then
            abort(failure("XmlLimit", "XML exceeds maximum_depth", "depth"))
        end
        if state.elements > limits.maximum_elements then
            abort(failure("XmlLimit", "XML exceeds maximum_elements", "elements"))
        end
        state.stack[#state.stack + 1] = name
        if name == "Event" then
            state.context_events = state.context_events + 1
            if state.context_events > limits.maximum_context_events then
                abort(failure("XmlLimit", "XML exceeds maximum_context_events", "events"))
            end
        end
        local copied = {}
        local count = 0
        for key, value in pairs(attributes) do
            if type(key) == "string" then
                if type(value) ~= "string" then
                    abort(failure("XmlSyntax", "XML attribute value is malformed", "attribute"))
                end
                copied[key] = value
                count = count + 1
            end
        end
        if count > limits.maximum_attributes_per_element then
            abort(failure("XmlLimit", "XML has too many attributes", "attributes"))
        end
        if count > state.attributes_peak then state.attributes_peak = count end
        if name == "Field" and copied.rawBytes then
            local admitted_size = at_most_decimal(copied.rawBytes, limits.maximum_carrier_bytes)
            if admitted_size == false then
                abort(failure("XmlLimit", "XML carrier exceeds maximum_carrier_bytes", "carrier"))
            end
        end
        admit_sax_event()
        invoke(
            "start_element",
            name,
            readonly(copied, "XML attributes"),
            path_string(state.stack)
        )
    end

    callbacks.EndElement = function(_, name)
        flush_text()
        local current = state.stack[#state.stack]
        if current ~= name then
            abort(failure("XmlSyntax", "XML element stack is inconsistent", "element-stack"))
        end
        admit_sax_event()
        invoke("end_element", name, path_string(state.stack))
        state.stack[#state.stack] = nil
        state.depth = state.depth - 1
    end

    callbacks.CharacterData = function(_, value)
        state.pending_text_bytes = state.pending_text_bytes + #value
        state.text_bytes = state.text_bytes + #value
        if state.pending_text_bytes > limits.maximum_text_node_bytes then
            abort(failure("XmlLimit", "XML text node is too large", "text-node"))
        end
        if state.text_bytes > limits.maximum_total_text_bytes then
            abort(failure("XmlLimit", "XML total text is too large", "total-text"))
        end
        state.pending_text[#state.pending_text + 1] = value
    end

    callbacks.XmlDecl = function(_, version, encoding)
        if version ~= "1.0"
            or (encoding ~= nil and encoding:upper() ~= "UTF-8")
        then
            abort(failure("XmlSyntax", "XML declaration is outside the UTF-8 profile", "encoding"))
        end
    end

    callbacks.ProcessingInstruction = function()
        abort(failure(
            "XmlSecurity",
            "XML processing instructions are forbidden",
            "processing-instruction"
        ))
    end

    callbacks.StartDoctypeDecl = function()
        abort(failure("XmlSecurity", "XML DTD is forbidden", "dtd"))
    end

    callbacks.EntityDecl = function()
        abort(failure("XmlSecurity", "XML entity declarations are forbidden", "entity"))
    end

    callbacks.UnparsedEntityDecl = callbacks.EntityDecl
    callbacks.NotationDecl = callbacks.EntityDecl
    callbacks.AttlistDecl = callbacks.EntityDecl
    callbacks.ElementDecl = callbacks.EntityDecl
    callbacks.SkippedEntity = callbacks.EntityDecl
    callbacks.NotStandalone = callbacks.EntityDecl
    callbacks.ExternalEntityRef = function()
        abort(failure("XmlSecurity", "XML external entities are forbidden", "external-entity"))
    end

    local created, created_or_error = pcall(admitted.lxp.new, callbacks, nil, false)
    if not created then
        return nil, failure("XmlDependencyFailure", "LuaExpat could not create a parser")
    end
    parser = created_or_error
    if (type(parser) ~= "userdata" and type(parser) ~= "table")
        or type(parser.parse) ~= "function"
        or type(parser.close) ~= "function"
    then
        return nil, failure("InvalidXmlDependency", "LuaExpat returned a malformed parser")
    end

    local function close_parser()
        if not state.closed then
            state.closed = true
            pcall(parser.close, parser)
        end
    end

    local function parser_call(chunk, final)
        local called, parsed, parse_error, line, column, offset
        if final then
            called, parsed, parse_error, line, column, offset = pcall(parser.parse, parser)
        else
            called, parsed, parse_error, line, column, offset = pcall(
                parser.parse,
                parser,
                chunk
            )
        end
        if state.failed then
            close_parser()
            return nil, state.failed
        end
        if not called then
            close_parser()
            return nil, positioned(failure(
                "XmlDependencyFailure",
                "LuaExpat raised outside a registered rejection",
                "parser-callback"
            ), parser, state.stack)
        end
        if not parsed then
            local syntax_error = failure(
                "XmlSyntax",
                type(parse_error) == "string" and parse_error or "XML is not well formed",
                "well-formed",
                path_string(state.stack),
                line,
                column,
                offset
            )
            close_parser()
            state.failed = syntax_error
            return nil, syntax_error
        end
        return true
    end

    local reader = {}

    ---Feeds exact bytes through fixed-size chunks to bound native buffering.
    -- @param chunk string Next source bytes.
    -- @return boolean|nil accepted True while the reader remains usable.
    -- @return table|nil err Structured terminal reader failure.
    function reader.feed(chunk)
        if state.failed then return nil, state.failed end
        if state.finished or state.closed then
            return nil, failure("XmlReaderClosed", "XML reader is already terminal")
        end
        if type(chunk) ~= "string" then
            return nil, failure("InvalidXmlInput", "XML reader chunks must be byte strings")
        end
        if state.bytes > limits.maximum_bytes - #chunk then
            state.failed = positioned(
                failure("XmlLimit", "XML exceeds maximum_bytes", "bytes"),
                parser,
                state.stack
            )
            close_parser()
            return nil, state.failed
        end
        state.bytes = state.bytes + #chunk
        for index = 1, #chunk, limits.maximum_chunk_bytes do
            local accepted, parse_error = parser_call(
                chunk:sub(index, index + limits.maximum_chunk_bytes - 1),
                false
            )
            if not accepted then return nil, parse_error end
        end
        return true
    end

    ---Finalizes the native parser and returns bounded parse statistics.
    -- @return table|nil stats Immutable successful reader statistics.
    -- @return table|nil err Structured terminal reader failure.
    function reader.finish()
        if state.failed then return nil, state.failed end
        if state.finished or state.closed then
            return nil, failure("XmlReaderClosed", "XML reader is already terminal")
        end
        local accepted, parse_error = parser_call(nil, true)
        if not accepted then return nil, parse_error end
        flush_text()
        state.finished = true
        close_parser()
        if state.depth ~= 0 or #state.stack ~= 0 then
            return nil, failure("XmlSyntax", "XML ended with open elements", "open-elements")
        end
        return readonly({
            bytes = state.bytes,
            elements = state.elements,
            maximum_depth_observed = state.depth_peak,
            maximum_attributes_observed = state.attributes_peak,
            text_bytes = state.text_bytes,
            sax_events = state.sax_events,
            context_events = state.context_events,
            external_entity_opens = 0,
        }, "XML reader statistics")
    end

    ---Closes an unfinished reader without accepting a document.
    -- @return boolean closed Always true after validation.
    function reader.close()
        close_parser()
        return true
    end

    return readonly(reader, "XML reader")
end

local function valid_xml_name(name)
    return type(name) == "string" and name:match("^[A-Za-z][A-Za-z0-9]*$") ~= nil
end

local function safe_xml_text(value)
    if type(value) ~= "string" then return nil end
    return text.xml_carrier_kind(value) == "text"
end

local function validate_writer_sink(sink)
    if type(sink) ~= "function" then
        return nil, failure("InvalidXmlSink", "XML writer sink must be a function")
    end
    return true
end

local function new_writer(admitted, sink)
    local limits = admitted.limits
    local state = {
        bytes = 0,
        depth = 0,
        depth_peak = 0,
        elements = 0,
        text_bytes = 0,
        text_node_bytes = 0,
        sax_events = 0,
        stack = {},
        declaration = false,
        root_started = false,
        root_closed = false,
        terminal = false,
        failed = nil,
    }

    local function reject(error_value)
        state.failed = state.failed or error_value
        return nil, state.failed
    end

    local function emit(bytes)
        if state.bytes > limits.maximum_bytes - #bytes then
            return reject(failure("XmlLimit", "written XML exceeds maximum_bytes", "bytes"))
        end
        local called, accepted, sink_error = pcall(sink, bytes)
        if not called then
            return reject(failure("XmlSinkFailure", "XML writer sink raised an error"))
        end
        if accepted == false then
            local message = type(sink_error) == "string" and sink_error or "XML sink rejected bytes"
            return reject(failure("XmlSinkFailure", message))
        end
        state.bytes = state.bytes + #bytes
        return true
    end

    local function admit_events(count)
        if state.sax_events > limits.maximum_sax_events - count then
            return reject(failure(
                "XmlLimit",
                "written XML exceeds maximum_sax_events",
                "sax-events"
            ))
        end
        state.sax_events = state.sax_events + count
        return true
    end

    local function validate_attributes(attributes)
        attributes = attributes or {}
        local count = dense_array_length(attributes)
        if count == nil then
            return nil, failure("InvalidXmlAttributes", "attributes must be a dense array")
        end
        if count > limits.maximum_attributes_per_element then
            return nil, failure("XmlLimit", "element has too many attributes", "attributes")
        end
        local seen = {}
        local output = {}
        for _, attribute in ipairs(attributes) do
            if type(attribute) ~= "table"
                or not valid_xml_name(attribute.name)
                or type(attribute.value) ~= "string"
            then
                return nil, failure("InvalidXmlAttributes", "attribute is malformed")
            end
            for key in pairs(attribute) do
                if key ~= "name" and key ~= "value" then
                    return nil, failure("InvalidXmlAttributes", "attribute has an unknown field")
                end
            end
            if seen[attribute.name] then
                return nil, failure("InvalidXmlAttributes", "attribute is duplicated")
            end
            if not safe_xml_text(attribute.value)
                or attribute.value:find("[\t\n\r]")
            then
                return nil, failure("InvalidXmlAttributes", "attribute is not canonical XML text")
            end
            seen[attribute.name] = true
            output[#output + 1] = " " .. attribute.name .. "=\""
                .. escaped_xml(attribute.value) .. "\""
        end
        return table.concat(output)
    end

    local function admit_element(name, attributes, empty)
        if state.failed then return nil, state.failed end
        if state.terminal then return nil, failure("XmlWriterClosed", "XML writer is terminal") end
        if not state.declaration then
            return nil, failure("InvalidXmlSequence", "XML declaration must be written first")
        end
        if not valid_xml_name(name) then
            return nil, failure("InvalidXmlName", "writer accepts fixed ASCII XML names only")
        end
        if state.root_closed then
            return nil, failure("InvalidXmlSequence", "XML cannot have multiple roots")
        end
        local starting_root = state.depth == 0
        if starting_root and state.root_started then
            return nil, failure("InvalidXmlSequence", "XML cannot have multiple roots")
        end
        local rendered, attribute_error = validate_attributes(attributes)
        if not rendered then return nil, attribute_error end
        local next_depth = state.depth + 1
        if next_depth > limits.maximum_depth then
            return reject(failure("XmlLimit", "written XML exceeds maximum_depth", "depth"))
        end
        if state.elements >= limits.maximum_elements then
            return reject(failure("XmlLimit", "written XML exceeds maximum_elements", "elements"))
        end
        local events, event_error = admit_events(empty and 2 or 1)
        if not events then return nil, event_error end
        state.elements = state.elements + 1
        state.text_node_bytes = 0
        if next_depth > state.depth_peak then state.depth_peak = next_depth end
        local accepted, emit_error = emit("<" .. name .. rendered .. (empty and "/>" or ">"))
        if not accepted then return nil, emit_error end
        if starting_root then state.root_started = true end
        if empty then
            if starting_root then state.root_closed = true end
        else
            state.depth = next_depth
            state.stack[#state.stack + 1] = name
        end
        return true
    end

    local writer = {}

    ---Writes the only admitted declaration for canonical context XML.
    -- @return boolean|nil accepted True when emitted.
    -- @return table|nil err Structured sequence or sink failure.
    function writer.declaration()
        if state.failed then return nil, state.failed end
        if state.declaration or state.root_started or state.terminal then
            return nil, failure("InvalidXmlSequence", "XML declaration is out of order")
        end
        local accepted, emit_error = emit('<?xml version="1.0" encoding="UTF-8"?>\n')
        if not accepted then return nil, emit_error end
        state.declaration = true
        return true
    end

    ---Starts a fixed-name element with caller-ordered attributes.
    -- @param name string Fixed ASCII element name.
    -- @param attributes table|nil Dense ordered name/value records.
    -- @return boolean|nil accepted True when emitted.
    -- @return table|nil err Structured writer failure.
    function writer.start_element(name, attributes)
        return admit_element(name, attributes, false)
    end

    ---Writes a fixed-name empty element using canonical self-closing syntax.
    -- @param name string Fixed ASCII element name.
    -- @param attributes table|nil Dense ordered name/value records.
    -- @return boolean|nil accepted True when emitted.
    -- @return table|nil err Structured writer failure.
    function writer.empty_element(name, attributes)
        return admit_element(name, attributes, true)
    end

    ---Writes canonical XML-1.0-safe, CR-free UTF-8 text.
    -- @param value string Exact semantic text bytes.
    -- @return boolean|nil accepted True when emitted.
    -- @return table|nil err Structured text, limit, sequence, or sink failure.
    function writer.text(value)
        if state.failed then return nil, state.failed end
        if state.terminal then return nil, failure("XmlWriterClosed", "XML writer is terminal") end
        if state.depth == 0 then
            return nil, failure("InvalidXmlSequence", "XML text requires an open element")
        end
        if not safe_xml_text(value) then
            return nil, failure("InvalidXmlText", "XML text is not lossless XML 1.0 UTF-8")
        end
        if state.text_node_bytes > limits.maximum_text_node_bytes - #value then
            return reject(failure("XmlLimit", "written text node is too large", "text-node"))
        end
        if state.text_bytes > limits.maximum_total_text_bytes - #value then
            return reject(failure("XmlLimit", "written total text is too large", "total-text"))
        end
        if #value > 0 and state.text_node_bytes == 0 then
            local events, event_error = admit_events(1)
            if not events then return nil, event_error end
        end
        state.text_node_bytes = state.text_node_bytes + #value
        state.text_bytes = state.text_bytes + #value
        return emit(escaped_xml(value))
    end

    ---Writes the encoded content of a present typed carrier.
    -- @param carrier table XML carrier created by this module.
    -- @return boolean|nil accepted True when emitted.
    -- @return table|nil err Structured carrier or writer failure.
    function writer.carrier(carrier)
        local carrier_state = carrier_states[carrier]
        if not carrier_state or not carrier_state.present then
            return nil, failure("InvalidXmlCarrier", "writer requires a present XML carrier")
        end
        if carrier_state.raw_bytes > limits.maximum_carrier_bytes then
            return reject(failure("XmlLimit", "carrier exceeds maximum_carrier_bytes", "carrier"))
        end
        local value = carrier_state.representation == "base64"
            and encode_base64(carrier_state.bytes)
            or carrier_state.bytes
        return writer.text(value)
    end

    ---Closes the current element, requiring an exact name match.
    -- @param name string Expected current fixed element name.
    -- @return boolean|nil accepted True when emitted.
    -- @return table|nil err Structured sequence or sink failure.
    function writer.end_element(name)
        if state.failed then return nil, state.failed end
        if state.terminal then return nil, failure("XmlWriterClosed", "XML writer is terminal") end
        if state.stack[#state.stack] ~= name then
            return nil, failure("InvalidXmlSequence", "XML close element does not match")
        end
        local events, event_error = admit_events(1)
        if not events then return nil, event_error end
        local accepted, emit_error = emit("</" .. name .. ">")
        if not accepted then return nil, emit_error end
        state.stack[#state.stack] = nil
        state.depth = state.depth - 1
        state.text_node_bytes = 0
        if state.depth == 0 then state.root_closed = true end
        return true
    end

    ---Finishes a complete single-root XML document.
    -- @return table|nil stats Immutable successful writer statistics.
    -- @return table|nil err Structured completeness failure.
    function writer.finish()
        if state.failed then return nil, state.failed end
        if state.terminal then return nil, failure("XmlWriterClosed", "XML writer is terminal") end
        if not state.declaration or not state.root_started or not state.root_closed
            or state.depth ~= 0
        then
            return nil, failure("InvalidXmlSequence", "XML document is incomplete")
        end
        state.terminal = true
        return readonly({
            bytes = state.bytes,
            elements = state.elements,
            maximum_depth_observed = state.depth_peak,
            text_bytes = state.text_bytes,
            sax_events = state.sax_events,
        }, "XML writer statistics")
    end

    return readonly(writer, "XML writer")
end

---Creates a pinned, bounded XML reader/writer service.
-- LuaExpat must be supplied by the absolute release loader. Every limit is an
-- injected release value; users of this module cannot disable a hard cap.
-- @param options table Pinned lxp module and complete limit set.
-- @return table|nil codec Immutable XML service.
-- @return table|nil err Structured dependency or limit failure.
function M.new(options)
    local admitted, options_error = validate_options(options)
    if not admitted then return nil, options_error end
    local service = {}

    ---Creates an incremental secure SAX reader.
    -- @param sink table|nil Optional start_element/text/end_element callbacks.
    -- @return table|nil reader Incremental reader.
    -- @return table|nil err Structured sink or dependency failure.
    function service.new_reader(sink)
        local validated, sink_error = validate_sink(sink)
        if not validated then return nil, sink_error end
        return new_reader(admitted, validated)
    end

    ---Parses a byte string or dense chunk array through the incremental reader.
    -- @param source string|table Exact XML bytes or dense byte chunk array.
    -- @param sink table|nil Optional SAX consumer.
    -- @return table|nil stats Immutable successful parse statistics.
    -- @return table|nil err Structured input, syntax, security, or limit failure.
    function service.parse(source, sink)
        local reader, reader_error = service.new_reader(sink)
        if not reader then return nil, reader_error end
        if type(source) == "string" then
            local accepted, feed_error = reader.feed(source)
            if not accepted then return nil, feed_error end
        else
            local count = dense_array_length(source)
            if count == nil then
                reader.close()
                return nil, failure("InvalidXmlInput", "XML source must be bytes or dense chunks")
            end
            for _, chunk in ipairs(source) do
                local accepted, feed_error = reader.feed(chunk)
                if not accepted then return nil, feed_error end
            end
        end
        return reader.finish()
    end

    ---Creates a deterministic streaming XML writer.
    -- @param sink function Receives each exact output chunk.
    -- @return table|nil writer Narrow writer service.
    -- @return table|nil err Structured sink failure.
    function service.new_writer(sink)
        local valid, sink_error = validate_writer_sink(sink)
        if not valid then return nil, sink_error end
        return new_writer(admitted, sink)
    end

    ---Decodes and validates a parsed text/base64 carrier under release limits.
    -- @param representation string|nil Nil is the default text representation.
    -- @param encoded string Parsed element character data.
    -- @param raw_bytes integer|nil Optional declared exact byte count.
    -- @return table|nil carrier Immutable present carrier.
    -- @return table|nil err Structured representation, encoding, or limit failure.
    function service.decode_carrier(representation, encoded, raw_bytes)
        representation = representation or "text"
        if representation ~= "text" and representation ~= "base64" then
            return nil, failure("InvalidXmlCarrier", "unknown carrier representation")
        end
        if type(encoded) ~= "string" then
            return nil, failure("InvalidXmlCarrier", "encoded carrier must be bytes")
        end
        if raw_bytes ~= nil and not valid_integer(raw_bytes, 0) then
            return nil, failure("InvalidXmlCarrier", "raw byte count must be non-negative")
        end
        local bytes
        if representation == "base64" then
            local maximum_encoded = ((admitted.limits.maximum_carrier_bytes + 2) // 3) * 4
            if #encoded > maximum_encoded then
                return nil, failure("XmlLimit", "carrier exceeds maximum_carrier_bytes", "carrier")
            end
            local decode_error
            bytes, decode_error = decode_base64(encoded)
            if not bytes then return nil, decode_error end
        else
            if #encoded > admitted.limits.maximum_carrier_bytes then
                return nil, failure("XmlLimit", "carrier exceeds maximum_carrier_bytes", "carrier")
            end
            if text.xml_carrier_kind(encoded) ~= "text" then
                return nil, failure("InvalidXmlCarrier", "text carrier is not lossless XML text")
            end
            bytes = encoded
        end
        if #bytes > admitted.limits.maximum_carrier_bytes then
            return nil, failure("XmlLimit", "carrier exceeds maximum_carrier_bytes", "carrier")
        end
        if raw_bytes ~= nil and raw_bytes ~= #bytes then
            return nil, failure("InvalidXmlCarrier", "raw byte count does not match")
        end
        return new_carrier(true, representation, bytes)
    end

    local copied_limits = {}
    for _, name in ipairs(LIMIT_NAMES) do copied_limits[name] = admitted.limits[name] end
    service.limits = readonly(copied_limits, "XML limits")
    service.dependency = readonly({
        luaexpat = "1.5.2",
        expat = "2.8.2",
    }, "XML dependency identity")

    return readonly(service, "XML codec")
end

return M
