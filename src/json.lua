--[[
File: json.lua
Date: 2026-08-29
Author: WaterRun
Description: Parses and writes a bounded strict RFC 8259 JSON subset.
]]

local text = require("text")

local M = {}

local array_values = setmetatable({}, { __mode = "k" })
local object_values = setmetatable({}, { __mode = "k" })
local number_values = setmetatable({}, { __mode = "k" })

local JSON_NULL = setmetatable({}, {
    __newindex = function()
        error("JSON null cannot be modified", 2)
    end,
    __metatable = "locked",
    __tostring = function()
        return "json.null"
    end,
})

M.null = JSON_NULL

local function failure(code, message, offset, reason)
    local result = { code = code, message = message }
    if offset ~= nil then result.offset = offset end
    if reason ~= nil then result.reason = reason end
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

local function number_end(value, start_index)
    local index = start_index
    local length = #value
    if value:byte(index) == 0x2D then index = index + 1 end
    if index > length then return nil end
    local first = value:byte(index)
    if first == 0x30 then
        index = index + 1
        local following = value:byte(index)
        if following and following >= 0x30 and following <= 0x39 then return nil end
    elseif first and first >= 0x31 and first <= 0x39 then
        repeat
            index = index + 1
            first = value:byte(index)
        until not first or first < 0x30 or first > 0x39
    else
        return nil
    end
    if value:byte(index) == 0x2E then
        index = index + 1
        local digit = value:byte(index)
        if not digit or digit < 0x30 or digit > 0x39 then return nil end
        repeat
            index = index + 1
            digit = value:byte(index)
        until not digit or digit < 0x30 or digit > 0x39
    end
    local exponent = value:byte(index)
    if exponent == 0x45 or exponent == 0x65 then
        index = index + 1
        local sign = value:byte(index)
        if sign == 0x2B or sign == 0x2D then index = index + 1 end
        local digit = value:byte(index)
        if not digit or digit < 0x30 or digit > 0x39 then return nil end
        repeat
            index = index + 1
            digit = value:byte(index)
        until not digit or digit < 0x30 or digit > 0x39
    end
    return index
end

local function new_number(lexeme)
    local proxy = readonly({ lexeme = lexeme }, "JSON number")
    number_values[proxy] = lexeme
    return proxy
end

local function tag_array(value)
    array_values[value] = true
    return value
end

local function tag_object(value)
    object_values[value] = true
    return value
end

local function copy_dense_array(values)
    if type(values) ~= "table" then
        return nil, failure("InvalidJsonArray", "JSON array source must be a table")
    end
    local count = 0
    for key in pairs(values) do
        if math.type(key) ~= "integer" or key < 1 then
            return nil, failure("InvalidJsonArray", "JSON array must use positive integer keys")
        end
        count = count + 1
    end
    local result = {}
    for index = 1, count do
        if values[index] == nil then
            return nil, failure("InvalidJsonArray", "JSON array must not be sparse")
        end
        result[index] = values[index]
    end
    return tag_array(result)
end

local function copy_string_object(values)
    if type(values) ~= "table" then
        return nil, failure("InvalidJsonObject", "JSON object source must be a table")
    end
    local result = {}
    for key, value in pairs(values) do
        if type(key) ~= "string" then
            return nil, failure("InvalidJsonObject", "JSON object keys must be strings")
        end
        local valid, validation_error = text.validate_utf8(key)
        if not valid then return nil, validation_error end
        result[key] = value
    end
    return tag_object(result)
end

---Creates an explicitly typed JSON array from a dense Lua array.
-- @param values table Dense source array.
-- @return table|nil array Tagged mutable JSON array copy.
-- @return table|nil err Structured shape failure.
function M.array(values)
    return copy_dense_array(values)
end

---Creates an explicitly typed JSON object from a string-keyed Lua table.
-- @param values table String-keyed source map.
-- @return table|nil object Tagged mutable JSON object copy.
-- @return table|nil err Structured shape or UTF-8 failure.
function M.object(values)
    return copy_string_object(values)
end

---Creates a JSON number that preserves its exact RFC 8259 lexeme.
-- @param lexeme string Exact number bytes.
-- @return table|nil number Immutable number wrapper.
-- @return table|nil err Structured grammar failure.
function M.number(lexeme)
    if type(lexeme) ~= "string"
        or number_end(lexeme, 1) ~= #lexeme + 1
    then
        return nil, failure("InvalidJsonNumber", "number lexeme is not RFC 8259 JSON")
    end
    return new_number(lexeme)
end

---Returns the explicit JSON kind of a codec value.
-- @param value any Candidate JSON value.
-- @return string|nil kind JSON kind, or nil for an untyped value.
function M.kind(value)
    if value == JSON_NULL then return "null" end
    if number_values[value] then return "number" end
    if array_values[value] then return "array" end
    if object_values[value] then return "object" end
    local value_type = type(value)
    if value_type == "string" or value_type == "boolean" then return value_type end
    return nil
end

---Returns the exact preserved number lexeme.
-- @param value table Number wrapper returned by this module.
-- @return string|nil lexeme Exact number bytes.
-- @return table|nil err Structured type failure.
function M.number_lexeme(value)
    local lexeme = number_values[value]
    if not lexeme then
        return nil, failure("InvalidJsonNumber", "value is not a JSON number")
    end
    return lexeme
end

local function validate_limits(options)
    if type(options) ~= "table" then
        return nil, failure("InvalidJsonLimits", "JSON codec limits are required")
    end
    local names = {
        "maximum_bytes",
        "maximum_depth",
        "maximum_nodes",
        "maximum_string_bytes",
        "maximum_number_bytes",
    }
    local allowed = {}
    local limits = {}
    for _, name in ipairs(names) do
        allowed[name] = true
        if not valid_integer(options[name], 1) then
            return nil, failure("InvalidJsonLimits", name .. " must be a positive integer")
        end
        limits[name] = options[name]
    end
    for key in pairs(options) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure("InvalidJsonLimits", "JSON limits contain an unknown field")
        end
    end
    if limits.maximum_string_bytes > limits.maximum_bytes
        or limits.maximum_number_bytes > limits.maximum_bytes
    then
        return nil, failure("InvalidJsonLimits", "field limits must not exceed maximum_bytes")
    end
    return limits
end

local function parser_failure(reason, offset)
    return failure("JsonSyntax", "JSON input is invalid", offset, reason)
end

local function new_parser(source, limits)
    local parser = {
        source = source,
        limits = limits,
        index = 1,
        nodes = 0,
    }

    local function skip_whitespace()
        while true do
            local byte = source:byte(parser.index)
            if byte == 0x20 or byte == 0x09 or byte == 0x0A or byte == 0x0D then
                parser.index = parser.index + 1
            else
                return
            end
        end
    end

    local function append_string(parts, bytes, current_length, start_offset)
        local next_length = current_length + #bytes
        if next_length > limits.maximum_string_bytes then
            return nil, failure(
                "JsonLimit",
                "decoded JSON string exceeds maximum_string_bytes",
                start_offset,
                "string-bytes"
            )
        end
        parts[#parts + 1] = bytes
        return next_length
    end

    local function hex_value(byte)
        if byte >= 0x30 and byte <= 0x39 then return byte - 0x30 end
        if byte >= 0x41 and byte <= 0x46 then return byte - 0x41 + 10 end
        if byte >= 0x61 and byte <= 0x66 then return byte - 0x61 + 10 end
        return nil
    end

    local function parse_hex_quad(offset)
        local value = 0
        for step = 0, 3 do
            local digit = hex_value(source:byte(offset + step) or -1)
            if digit == nil then
                return nil, parser_failure("unicode-escape", offset + step)
            end
            value = value * 16 + digit
        end
        return value
    end

    local function parse_string()
        local start_offset = parser.index
        parser.index = parser.index + 1
        local parts = {}
        local decoded_length = 0
        local segment_start = parser.index
        while parser.index <= #source do
            local byte = source:byte(parser.index)
            if byte == 0x22 or byte == 0x5C or byte < 0x20 then
                if parser.index > segment_start then
                    local segment = source:sub(segment_start, parser.index - 1)
                    local next_length, limit_error = append_string(
                        parts,
                        segment,
                        decoded_length,
                        start_offset
                    )
                    if not next_length then return nil, limit_error end
                    decoded_length = next_length
                end
                if byte == 0x22 then
                    parser.index = parser.index + 1
                    return table.concat(parts)
                end
                if byte < 0x20 then
                    return nil, parser_failure("unescaped-control", parser.index)
                end
                local escape_offset = parser.index
                parser.index = parser.index + 1
                local escape = source:byte(parser.index)
                local decoded
                if escape == 0x22 then decoded = "\""
                elseif escape == 0x5C then decoded = "\\"
                elseif escape == 0x2F then decoded = "/"
                elseif escape == 0x62 then decoded = "\b"
                elseif escape == 0x66 then decoded = "\f"
                elseif escape == 0x6E then decoded = "\n"
                elseif escape == 0x72 then decoded = "\r"
                elseif escape == 0x74 then decoded = "\t"
                elseif escape == 0x75 then
                    local high, unicode_error = parse_hex_quad(parser.index + 1)
                    if not high then return nil, unicode_error end
                    parser.index = parser.index + 4
                    local codepoint = high
                    if high >= 0xD800 and high <= 0xDBFF then
                        if source:sub(parser.index + 1, parser.index + 2) ~= "\\u" then
                            return nil, parser_failure("surrogate", escape_offset)
                        end
                        local low, low_error = parse_hex_quad(parser.index + 3)
                        if not low then return nil, low_error end
                        if low < 0xDC00 or low > 0xDFFF then
                            return nil, parser_failure("surrogate", escape_offset)
                        end
                        codepoint = 0x10000
                            + (high - 0xD800) * 0x400
                            + low - 0xDC00
                        parser.index = parser.index + 6
                    elseif high >= 0xDC00 and high <= 0xDFFF then
                        return nil, parser_failure("surrogate", escape_offset)
                    end
                    decoded = assert(text.encode_scalar(codepoint))
                else
                    return nil, parser_failure("escape", parser.index)
                end
                local next_length, limit_error = append_string(
                    parts,
                    decoded,
                    decoded_length,
                    start_offset
                )
                if not next_length then return nil, limit_error end
                decoded_length = next_length
                parser.index = parser.index + 1
                segment_start = parser.index
            else
                parser.index = parser.index + 1
            end
        end
        return nil, parser_failure("unterminated-string", start_offset)
    end

    local parse_value

    local function admit_node(offset)
        parser.nodes = parser.nodes + 1
        if parser.nodes > limits.maximum_nodes then
            return nil, failure(
                "JsonLimit",
                "JSON value exceeds maximum_nodes",
                offset,
                "nodes"
            )
        end
        return true
    end

    local function parse_array(depth)
        if depth > limits.maximum_depth then
            return nil, failure(
                "JsonLimit",
                "JSON value exceeds maximum_depth",
                parser.index,
                "depth"
            )
        end
        parser.index = parser.index + 1
        skip_whitespace()
        local result = tag_array({})
        if source:byte(parser.index) == 0x5D then
            parser.index = parser.index + 1
            return result
        end
        while true do
            local value, value_error = parse_value(depth + 1)
            if value == nil then return nil, value_error end
            result[#result + 1] = value
            skip_whitespace()
            local delimiter = source:byte(parser.index)
            if delimiter == 0x5D then
                parser.index = parser.index + 1
                return result
            end
            if delimiter ~= 0x2C then
                return nil, parser_failure("array-delimiter", parser.index)
            end
            parser.index = parser.index + 1
            skip_whitespace()
        end
    end

    local function parse_object(depth)
        if depth > limits.maximum_depth then
            return nil, failure(
                "JsonLimit",
                "JSON value exceeds maximum_depth",
                parser.index,
                "depth"
            )
        end
        parser.index = parser.index + 1
        skip_whitespace()
        local result = tag_object({})
        local seen = {}
        if source:byte(parser.index) == 0x7D then
            parser.index = parser.index + 1
            return result
        end
        while true do
            if source:byte(parser.index) ~= 0x22 then
                return nil, parser_failure("object-key", parser.index)
            end
            local key, key_error = parse_string()
            if key == nil then return nil, key_error end
            if seen[key] then
                return nil, parser_failure("duplicate-key", parser.index)
            end
            seen[key] = true
            skip_whitespace()
            if source:byte(parser.index) ~= 0x3A then
                return nil, parser_failure("object-colon", parser.index)
            end
            parser.index = parser.index + 1
            skip_whitespace()
            local value, value_error = parse_value(depth + 1)
            if value == nil then return nil, value_error end
            result[key] = value
            skip_whitespace()
            local delimiter = source:byte(parser.index)
            if delimiter == 0x7D then
                parser.index = parser.index + 1
                return result
            end
            if delimiter ~= 0x2C then
                return nil, parser_failure("object-delimiter", parser.index)
            end
            parser.index = parser.index + 1
            skip_whitespace()
        end
    end

    local function parse_number()
        local start_offset = parser.index
        local finish = number_end(source, start_offset)
        if not finish then
            return nil, parser_failure("number", start_offset)
        end
        local lexeme = source:sub(start_offset, finish - 1)
        if #lexeme > limits.maximum_number_bytes then
            return nil, failure(
                "JsonLimit",
                "JSON number exceeds maximum_number_bytes",
                start_offset,
                "number-bytes"
            )
        end
        parser.index = finish
        return new_number(lexeme)
    end

    function parse_value(depth)
        skip_whitespace()
        local offset = parser.index
        local admitted, node_error = admit_node(offset)
        if not admitted then return nil, node_error end
        local byte = source:byte(offset)
        if byte == 0x7B then return parse_object(depth) end
        if byte == 0x5B then return parse_array(depth) end
        if byte == 0x22 then return parse_string() end
        if source:sub(offset, offset + 3) == "true" then
            parser.index = offset + 4
            return true
        end
        if source:sub(offset, offset + 4) == "false" then
            parser.index = offset + 5
            return false
        end
        if source:sub(offset, offset + 3) == "null" then
            parser.index = offset + 4
            return JSON_NULL
        end
        if byte == 0x2D or (byte and byte >= 0x30 and byte <= 0x39) then
            return parse_number()
        end
        if byte == 0x2B
            or source:sub(offset, offset + 2) == "NaN"
            or source:sub(offset, offset + 7) == "Infinity"
        then
            return nil, parser_failure("number", offset)
        end
        return nil, parser_failure("unexpected-token", offset)
    end

    function parser.parse()
        skip_whitespace()
        local result, parse_error = parse_value(1)
        if result == nil then return nil, parse_error end
        skip_whitespace()
        if parser.index <= #source then
            return nil, parser_failure("trailing-data", parser.index)
        end
        if not object_values[result] and not array_values[result] then
            return nil, parser_failure("top-level", 1)
        end
        return result
    end

    return parser
end

local function new_writer(limits)
    local writer = {
        parts = {},
        byte_count = 0,
        nodes = 0,
        active = {},
    }

    local function append(bytes)
        if writer.byte_count > limits.maximum_bytes - #bytes then
            return nil, failure("JsonLimit", "encoded JSON exceeds maximum_bytes", nil, "bytes")
        end
        writer.byte_count = writer.byte_count + #bytes
        writer.parts[#writer.parts + 1] = bytes
        return true
    end

    local function append_escaped_string(value)
        local valid, validation_error = text.validate_utf8(value)
        if not valid then return nil, validation_error end
        if #value > limits.maximum_string_bytes then
            return nil, failure("JsonLimit", "JSON string exceeds maximum_string_bytes")
        end
        local ok, append_error = append("\"")
        if not ok then return nil, append_error end
        local segment_start = 1
        for index = 1, #value do
            local byte = value:byte(index)
            local replacement
            if byte == 0x22 then replacement = "\\\""
            elseif byte == 0x5C then replacement = "\\\\"
            elseif byte == 0x08 then replacement = "\\b"
            elseif byte == 0x0C then replacement = "\\f"
            elseif byte == 0x0A then replacement = "\\n"
            elseif byte == 0x0D then replacement = "\\r"
            elseif byte == 0x09 then replacement = "\\t"
            elseif byte < 0x20 then replacement = string.format("\\u%04x", byte)
            end
            if replacement then
                if index > segment_start then
                    ok, append_error = append(value:sub(segment_start, index - 1))
                    if not ok then return nil, append_error end
                end
                ok, append_error = append(replacement)
                if not ok then return nil, append_error end
                segment_start = index + 1
            end
        end
        if segment_start <= #value then
            ok, append_error = append(value:sub(segment_start))
            if not ok then return nil, append_error end
        end
        return append("\"")
    end

    local write_value

    local function admit_node()
        writer.nodes = writer.nodes + 1
        if writer.nodes > limits.maximum_nodes then
            return nil, failure("JsonLimit", "encoded JSON exceeds maximum_nodes")
        end
        return true
    end

    local function write_array(value, depth)
        if depth > limits.maximum_depth then
            return nil, failure("JsonLimit", "encoded JSON exceeds maximum_depth")
        end
        if writer.active[value] then
            return nil, failure("JsonCycle", "JSON value contains a cycle")
        end
        writer.active[value] = true
        local count = 0
        for key in pairs(value) do
            if math.type(key) ~= "integer" or key < 1 then
                writer.active[value] = nil
                return nil, failure("InvalidJsonArray", "JSON array has a non-array key")
            end
            count = count + 1
        end
        for index = 1, count do
            if value[index] == nil then
                writer.active[value] = nil
                return nil, failure("InvalidJsonArray", "JSON array is sparse")
            end
        end
        local ok, write_error = append("[")
        if not ok then writer.active[value] = nil return nil, write_error end
        for index = 1, count do
            if index > 1 then
                ok, write_error = append(",")
                if not ok then writer.active[value] = nil return nil, write_error end
            end
            ok, write_error = write_value(value[index], depth + 1)
            if not ok then writer.active[value] = nil return nil, write_error end
        end
        writer.active[value] = nil
        return append("]")
    end

    local function write_object(value, depth)
        if depth > limits.maximum_depth then
            return nil, failure("JsonLimit", "encoded JSON exceeds maximum_depth")
        end
        if writer.active[value] then
            return nil, failure("JsonCycle", "JSON value contains a cycle")
        end
        writer.active[value] = true
        local keys = {}
        for key in pairs(value) do
            if type(key) ~= "string" then
                writer.active[value] = nil
                return nil, failure("InvalidJsonObject", "JSON object key is not a string")
            end
            keys[#keys + 1] = key
        end
        table.sort(keys)
        local ok, write_error = append("{")
        if not ok then writer.active[value] = nil return nil, write_error end
        for index, key in ipairs(keys) do
            if index > 1 then
                ok, write_error = append(",")
                if not ok then writer.active[value] = nil return nil, write_error end
            end
            ok, write_error = append_escaped_string(key)
            if not ok then writer.active[value] = nil return nil, write_error end
            ok, write_error = append(":")
            if not ok then writer.active[value] = nil return nil, write_error end
            ok, write_error = write_value(value[key], depth + 1)
            if not ok then writer.active[value] = nil return nil, write_error end
        end
        writer.active[value] = nil
        return append("}")
    end

    function write_value(value, depth)
        local admitted, node_error = admit_node()
        if not admitted then return nil, node_error end
        if value == JSON_NULL then return append("null") end
        if value == true then return append("true") end
        if value == false then return append("false") end
        if type(value) == "string" then return append_escaped_string(value) end
        local lexeme = number_values[value]
        if lexeme then
            if #lexeme > limits.maximum_number_bytes then
                return nil, failure("JsonLimit", "JSON number exceeds maximum_number_bytes")
            end
            return append(lexeme)
        end
        if array_values[value] then return write_array(value, depth) end
        if object_values[value] then return write_object(value, depth) end
        return nil, failure(
            "InvalidJsonValue",
            "writer requires tagged containers, wrapped numbers, and JSON scalars"
        )
    end

    function writer.write(value)
        if not object_values[value] and not array_values[value] then
            return nil, failure("JsonTopLevel", "JSON top level must be an object or array")
        end
        local ok, write_error = write_value(value, 1)
        if not ok then return nil, write_error end
        return table.concat(writer.parts)
    end

    return writer
end

---Creates a bounded JSON codec using release-manifest limits.
-- Numbers remain exact lexeme wrappers until a schema performs bounded numeric
-- conversion. The parser and writer accept only object or array top levels.
-- @param options table Required byte, depth, node, string, and number limits.
-- @return table|nil codec Immutable parser/writer service.
-- @return table|nil err Structured limit failure.
function M.new(options)
    local limits, limits_error = validate_limits(options)
    if not limits then return nil, limits_error end
    local service = {}

    ---Parses strict UTF-8 JSON into explicitly typed Lua values.
    -- @param source string Exact JSON bytes without a BOM.
    -- @return table|nil value Tagged top-level object or array.
    -- @return table|nil err Structured syntax, UTF-8, or limit failure.
    function service.parse(source)
        if type(source) ~= "string" then
            return nil, failure("InvalidJsonType", "JSON source must be a byte string")
        end
        if #source > limits.maximum_bytes then
            return nil, failure("JsonLimit", "JSON source exceeds maximum_bytes", 1, "bytes")
        end
        if source:sub(1, 3) == "\239\187\191" then
            return nil, parser_failure("bom", 1)
        end
        local valid, validation_error = text.validate_utf8(source)
        if not valid then return nil, validation_error end
        return new_parser(source, limits).parse()
    end

    ---Writes a tagged JSON object or array in deterministic canonical form.
    -- Object keys use UTF-8 byte order, whitespace is omitted, and only required
    -- string bytes are escaped. Number wrappers retain their admitted lexemes.
    -- @param value table Tagged JSON object or array.
    -- @return string|nil source Canonical JSON bytes.
    -- @return table|nil err Structured shape, UTF-8, cycle, or limit failure.
    function service.write(value)
        return new_writer(limits).write(value)
    end

    service.limits = readonly({
        maximum_bytes = limits.maximum_bytes,
        maximum_depth = limits.maximum_depth,
        maximum_nodes = limits.maximum_nodes,
        maximum_string_bytes = limits.maximum_string_bytes,
        maximum_number_bytes = limits.maximum_number_bytes,
    }, "JSON limits")

    return readonly(service, "JSON codec")
end

return M
