--[[
Author: WaterRun
Date: 2026-09-23
File: json.lua
Description: Parses and writes a bounded strict RFC 8259 JSON subset.
]]

local text = require("text")

local M = {}

--@metatable array_values Marks module-admitted JSON arrays independently of their Lua table shape.
--@field __mode string Fixed k mode: keys are weak; entries remain mutable within their owning module.
local array_values = setmetatable({}, { __mode = "k" })
--@metatable object_values Marks module-admitted JSON objects independently of their Lua table shape.
--@field __mode string Fixed k mode: keys are weak; entries remain mutable within their owning module.
local object_values = setmetatable({}, { __mode = "k" })
--@metatable number_values Associates lossless JSON number proxies with their original validated numeric lexemes.
--@field __mode string Fixed k mode: keys are weak; entries remain mutable within their owning module.
local number_values = setmetatable({}, { __mode = "k" })

--@metatable JSON_NULL Unique JSON null sentinel; ordinary writes are rejected and its metatable is hidden.
--@field __newindex function Rejects every ordinary assignment to the sentinel.
--@field __metatable string Fixed locked marker returned by getmetatable.
--@field __tostring function Returns json.null without exposing the underlying table address.
local JSON_NULL = setmetatable({}, {
    -- Refuse mutation of the shared JSON null sentinel.
    --@param none Lua's assignment operands are deliberately ignored.
    --@return nil Does not return normally.
    --@error Always raises JSON null cannot be modified at the caller frame.
    __newindex = function()
        error("JSON null cannot be modified", 2)
    end,
    __metatable = "locked",
    -- Give the sentinel a stable diagnostic representation.
    --@param none Lua's sentinel operand is deliberately ignored.
    --@return string The fixed json.null label.
    __tostring = function()
        return "json.null"
    end,
})

M.null = JSON_NULL

-- Construct a structured diagnostic without throwing or formatting its optional fields.
--@param code string Stable diagnostic code used by callers to choose recovery behavior.
--@param message string Human-readable summary supplied by the failing operation.
--@param offset integer|nil Source byte position in the reporting parser's coordinate convention.
--@param reason string|nil Optional machine-readable cause or validation rule.
--@return table New diagnostic record; optional non-nil fields are retained without deep copying.
local function failure(code, message, offset, reason)
    local result = { code = code, message = message }
    if offset ~= nil then result.offset = offset end
    if reason ~= nil then result.reason = reason end
    return result
end

-- Create a shallow read-only view without copying the backing table.
--@param values table Backing fields retained by reference; the caller owns their stability.
--@param label string|nil Diagnostic label; defaults to "readonly value".
--@return table Empty proxy exposing the backing fields through its locked metatable.
--@ownership Retains values by reference; nested values and the backing table are not frozen.
local function readonly(values, label)
    --@metatable readonly_proxy Forwards reads and iteration; ordinary assignments raise an error.
    --@field __index table Backing values used for missing-key reads.
    --@field __newindex function Rejects ordinary assignments without changing the backing values.
    --@field __pairs function Enumerates the backing table with next.
    --@field __metatable string Hides this metatable behind the fixed "locked" marker.
    return setmetatable({}, {
        __index = values,
        -- Reject a write through the proxy before it can create an ordinary field.
        --@param _ table Proxy receiving the assignment; its contents are not consulted.
        --@param key any Attempted field name included in the diagnostic.
        --@return nil Does not return normally.
        --@error Always raises a read-only assignment error at the caller frame.
        __newindex = function(_, key)
            error((label or "readonly value") .. " cannot be modified: " .. tostring(key), 2)
        end,
        -- Iterate the backing fields instead of the empty proxy table.
        --@param none The proxy argument supplied by pairs is ignored.
        --@return function The standard next iterator.
        --@return table Backing values used as iterator state.
        --@return nil Initial key used to start iteration.
        __pairs = function()
            return next, values, nil
        end,
        __metatable = "locked",
    })
end

-- Check the Lua integer subtype and the caller's inclusive lower bound.
--@param value any Candidate value; floats and non-numeric values are rejected.
--@param minimum integer Inclusive minimum accepted by this check.
--@return boolean True only for an integer at least minimum.
local function valid_integer(value, minimum)
    return math.type(value) == "integer" and value >= minimum
end

-- Scan one RFC 8259 number lexeme and reject leading zeroes or incomplete parts.
--@param value string Source bytes containing a candidate number.
--@param start_index integer One-based index of its first byte.
--@return integer|nil finish Exclusive byte index after the lexeme, or nil for invalid grammar.
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

-- Bind an already validated number lexeme to an immutable JSON number proxy.
--@param lexeme string Exact validated number bytes.
--@return table number Read-only number wrapper retaining the lexeme privately.
--@effect Adds the proxy-to-lexeme binding to the weak-key registry.
local function new_number(lexeme)
    local proxy = readonly({ lexeme = lexeme }, "JSON number")
    number_values[proxy] = lexeme
    return proxy
end

-- Mark a Lua table as an admitted JSON array without changing its contents.
--@param value table Mutable array table owned by the caller or parser.
--@return table array The same table with a private JSON array tag.
--@effect Adds the table to the weak-key array registry.
local function tag_array(value)
    array_values[value] = true
    return value
end

-- Mark a Lua table as an admitted JSON object without changing its contents.
--@param value table Mutable string-keyed table owned by the caller or parser.
--@return table object The same table with a private JSON object tag.
--@effect Adds the table to the weak-key object registry.
local function tag_object(value)
    object_values[value] = true
    return value
end

-- Validate a dense one-based Lua sequence and tag its shallow copy as JSON.
--@param values any Candidate source sequence.
--@return table|nil array New tagged mutable JSON array.
--@return table|nil err Structured invalid-key or sparse-array failure.
--@ownership Copies the outer table; nested element references remain shared.
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

-- Validate UTF-8 string keys and tag a shallow object copy as JSON.
--@param values any Candidate string-keyed source map.
--@return table|nil object New tagged mutable JSON object.
--@return table|nil err Structured key-type or UTF-8 failure.
--@ownership Copies the outer table; nested member references remain shared.
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
--@param values table Dense source array.
--@return table|nil array Tagged mutable JSON array copy.
--@return table|nil err Structured shape failure.
function M.array(values)
    return copy_dense_array(values)
end

---Creates an explicitly typed JSON object from a string-keyed Lua table.
--@param values table String-keyed source map.
--@return table|nil object Tagged mutable JSON object copy.
--@return table|nil err Structured shape or UTF-8 failure.
function M.object(values)
    return copy_string_object(values)
end

---Creates a JSON number that preserves its exact RFC 8259 lexeme.
--@param lexeme string Exact number bytes.
--@return table|nil number Immutable number wrapper.
--@return table|nil err Structured grammar failure.
function M.number(lexeme)
    if type(lexeme) ~= "string"
        or number_end(lexeme, 1) ~= #lexeme + 1
    then
        return nil, failure("InvalidJsonNumber", "number lexeme is not RFC 8259 JSON")
    end
    return new_number(lexeme)
end

---Returns the explicit JSON kind of a codec value.
--@param value any Candidate JSON value.
--@return string|nil kind JSON kind, or nil for an untyped value.
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
--@param value table Number wrapper returned by this module.
--@return string|nil lexeme Exact number bytes.
--@return table|nil err Structured type failure.
function M.number_lexeme(value)
    local lexeme = number_values[value]
    if not lexeme then
        return nil, failure("InvalidJsonNumber", "value is not a JSON number")
    end
    return lexeme
end

-- Validate and copy the five required JSON parser/writer hard limits.
--@param options table Candidate positive integer limits with no extra fields.
--@return table|nil limits Independent admitted limit record.
--@return table|nil err Structured limit-shape or inconsistency failure.
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

-- Create a syntax diagnostic at an exact one-based source byte position.
--@param reason string Machine-readable JSON grammar failure.
--@param offset integer One-based source byte position.
--@return table err New JsonSyntax diagnostic.
local function parser_failure(reason, offset)
    return failure("JsonSyntax", "JSON input is invalid", offset, reason)
end

-- Create a single-use bounded recursive parser over admitted UTF-8 bytes.
--@param source string Strict UTF-8 JSON source without BOM.
--@param limits table Validated byte, depth, node, and token limits.
--@return table parser Stateful parser with one parse method.
local function new_parser(source, limits)
    local parser = {
        source = source,
        limits = limits,
        index = 1,
        nodes = 0,
    }

    -- Advance past the four RFC 8259 whitespace bytes.
    --@param none Source and cursor are captured from the enclosing parser.
    --@return nil Stops at the first non-whitespace byte or end of input.
    --@effect Advances parser.index.
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

    -- Append one decoded string fragment subject to its byte cap.
    --@param parts table Mutable decoded fragment sequence.
    --@param bytes string Newly decoded UTF-8 bytes.
    --@param current_length integer Total decoded bytes before this fragment.
    --@param start_offset integer Source offset used for a limit diagnostic.
    --@return integer|nil next_length Updated decoded byte count.
    --@return table|nil err Structured decoded-string limit failure.
    --@effect Appends to parts only when the byte cap admits the fragment.
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

    -- Decode one ASCII hexadecimal digit used by a Unicode escape.
    --@param byte integer Candidate source byte or negative missing-byte marker.
    --@return integer|nil value Digit value from zero to fifteen, or nil.
    local function hex_value(byte)
        if byte >= 0x30 and byte <= 0x39 then return byte - 0x30 end
        if byte >= 0x41 and byte <= 0x46 then return byte - 0x41 + 10 end
        if byte >= 0x61 and byte <= 0x66 then return byte - 0x61 + 10 end
        return nil
    end

    -- Parse four source hex digits into one UTF-16 code unit.
    --@param offset integer One-based position of the first hex digit.
    --@return integer|nil unit Decoded 16-bit code unit.
    --@return table|nil err Structured malformed-escape diagnostic.
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

    -- Decode a JSON string, including surrogate pairs, with an exact byte cap.
    --@param none Reads source at parser.index, expected to point at a quote.
    --@return string|nil decoded Strict UTF-8 decoded string.
    --@return table|nil err Structured syntax or decoded-byte limit failure.
    --@effect Advances parser.index across the consumed string or failure prefix.
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

    -- Charge one parsed JSON value against the node limit.
    --@param offset integer Source byte offset for a possible limit failure.
    --@return boolean|nil admitted True while under the node cap.
    --@return table|nil err Structured node-limit failure.
    --@effect Increments parser.nodes before the limit check.
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

    -- Parse a bracketed JSON array with bounded nesting and dense order.
    --@param depth integer Current value depth with top level equal to one.
    --@return table|nil array Mutable tagged JSON array.
    --@return table|nil err Structured depth, syntax, or child-value failure.
    --@effect Advances parser.index and charges child nodes.
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

    -- Parse a JSON object while rejecting duplicate decoded keys.
    --@param depth integer Current value depth with top level equal to one.
    --@return table|nil object Mutable tagged JSON object.
    --@return table|nil err Structured depth, duplicate-key, syntax, or child failure.
    --@effect Advances parser.index and charges child nodes.
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

    -- Capture one grammatical JSON number as an exact lexeme wrapper.
    --@param none Reads source at parser.index, expected to begin a number.
    --@return table|nil number Immutable exact-lexeme number wrapper.
    --@return table|nil err Structured grammar or number-byte limit failure.
    --@effect Advances parser.index on success.
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

    -- Dispatch one bounded JSON scalar or container at the current cursor.
    --@param depth integer Current value depth with top level equal to one.
    --@return any value Tagged container, string, boolean, number wrapper, or null sentinel.
    --@return table|nil err Structured syntax or limit failure when value is nil.
    --@effect Advances parser.index and charges a node before dispatch.
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

    -- Parse one complete top-level object or array with no trailing data.
    --@param none Uses this parser's captured source and limits.
    --@return table|nil value Tagged top-level JSON object or array.
    --@return table|nil err Structured syntax, top-level, or limit failure.
    --@effect Advances parser.index and node count; this parser is single-use.
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

-- Create single-use bounded canonical JSON writer state.
--@param limits table Validated byte, depth, node, and string/number limits.
--@return table writer Stateful writer with one write method.
local function new_writer(limits)
    local writer = {
        parts = {},
        byte_count = 0,
        nodes = 0,
        active = {},
    }

    -- Append exact output bytes without exceeding the total encoded byte cap.
    --@param bytes string Encoded JSON fragment to append.
    --@return boolean|nil appended True after the fragment is retained.
    --@return table|nil err Structured total-byte limit failure.
    --@effect Increments writer.byte_count and appends to writer.parts on success.
    local function append(bytes)
        if writer.byte_count > limits.maximum_bytes - #bytes then
            return nil, failure("JsonLimit", "encoded JSON exceeds maximum_bytes", nil, "bytes")
        end
        writer.byte_count = writer.byte_count + #bytes
        writer.parts[#writer.parts + 1] = bytes
        return true
    end

    -- Encode a strict UTF-8 string with only necessary JSON escapes.
    --@param value string Candidate JSON string or object key.
    --@return boolean|nil written True after the closing quote is appended.
    --@return table|nil err Structured UTF-8, string, or total-byte failure.
    --@effect May append a prefix to writer.parts before a later failure.
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

    -- Charge one emitted JSON value against the writer node cap.
    --@param none Uses the captured writer and limits.
    --@return boolean|nil admitted True while under the node cap.
    --@return table|nil err Structured node-limit failure.
    --@effect Increments writer.nodes before the limit check.
    local function admit_node()
        writer.nodes = writer.nodes + 1
        if writer.nodes > limits.maximum_nodes then
            return nil, failure("JsonLimit", "encoded JSON exceeds maximum_nodes")
        end
        return true
    end

    -- Encode a tagged dense JSON array without cycles or excess nesting.
    --@param value table Tagged JSON array to inspect.
    --@param depth integer Current container depth.
    --@return boolean|nil written True after the closing bracket is appended.
    --@return table|nil err Structured cycle, shape, depth, or output failure.
    --@effect Appends encoded bytes and temporarily marks value active.
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

    -- Encode a tagged JSON object in sorted UTF-8 byte key order.
    --@param value table Tagged string-keyed JSON object.
    --@param depth integer Current container depth.
    --@return boolean|nil written True after the closing brace is appended.
    --@return table|nil err Structured cycle, key, depth, or output failure.
    --@effect Appends encoded bytes and temporarily marks value active.
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

    -- Encode one tagged JSON value after charging its node budget.
    --@param value any Candidate JSON scalar, wrapper, or tagged container.
    --@param depth integer Current value depth.
    --@return boolean|nil written True after complete encoding.
    --@return table|nil err Structured type, limit, cycle, or output failure.
    --@effect Appends encoded bytes or a partial prefix on failure.
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

    -- Serialize one tagged top-level object or array from fresh writer state.
    --@param value table Tagged JSON object or array.
    --@return string|nil encoded Compact canonical JSON bytes.
    --@return table|nil err Structured top-level, shape, cycle, or limit failure.
    --@effect Consumes this writer's output state; callers create a new writer for each call.
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
--@param options table Required byte, depth, node, string, and number limits.
--@return table|nil codec Immutable parser/writer service.
--@return table|nil err Structured limit failure.
function M.new(options)
    local limits, limits_error = validate_limits(options)
    if not limits then return nil, limits_error end
    local service = {}

    ---Parses strict UTF-8 JSON into explicitly typed Lua values.
    --@param source string Exact JSON bytes without a BOM.
    --@return table|nil value Tagged top-level object or array.
    --@return table|nil err Structured syntax, UTF-8, or limit failure.
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
    --@param value table Tagged JSON object or array.
    --@return string|nil source Canonical JSON bytes.
    --@return table|nil err Structured shape, UTF-8, cycle, or limit failure.
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
