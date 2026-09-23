--[[
Author: WaterRun
Date: 2026-08-29
File: text.lua
Description: Validates strict UTF-8 and keeps text, binary, and display bytes separate.
]]

local M = {}

--@metatable carrier_values Associates module-created proxies with their canonical bytes and carrier metadata.
--@field __mode string Weak keys allow carrier proxies and their private metadata to be collected together.
local carrier_values = setmetatable({}, { __mode = "k" })

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
    local proxy = setmetatable({}, {
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
    return proxy
end

-- Bind a specific decoding failure to the stable InvalidUtf8 diagnostic code.
--@param reason string Decoder rule identifying the malformed scalar sequence.
--@param offset integer One-based offending byte position in the original string.
--@return table Structured diagnostic retaining the reason and byte offset.
local function utf8_failure(reason, offset)
    return failure("InvalidUtf8", "input is not a Unicode scalar sequence", offset, reason)
end

-- Recognize a UTF-8 continuation octet without accepting end-of-input.
--@param byte integer|nil Octet obtained from string.byte, or nil beyond the string.
--@return boolean True only for bytes in the inclusive range 0x80 through 0xBF.
local function continuation(byte)
    return byte ~= nil and byte >= 0x80 and byte <= 0xBF
end

-- Decode one scalar while rejecting overlong encodings, surrogates and invalid continuation bytes.
--@param value string Exact candidate UTF-8 byte sequence.
--@param index integer One-based start position; callers ensure it lies inside value.
--@return integer|nil Unicode scalar value, or nil when this sequence is malformed.
--@return integer|table Next byte position on success, or an InvalidUtf8 diagnostic on failure.
local function decode_one(value, index)
    local first = value:byte(index)
    if first <= 0x7F then return first, index + 1 end
    if first >= 0x80 and first <= 0xBF then
        return nil, utf8_failure("isolated-continuation", index)
    end
    if first == 0xC0 or first == 0xC1 then
        return nil, utf8_failure("overlong", index)
    end
    if first >= 0xC2 and first <= 0xDF then
        local second = value:byte(index + 1)
        if second == nil then return nil, utf8_failure("truncated", index) end
        if not continuation(second) then
            return nil, utf8_failure("invalid-continuation", index + 1)
        end
        return (first - 0xC0) * 0x40 + second - 0x80, index + 2
    end
    if first >= 0xE0 and first <= 0xEF then
        local second, third = value:byte(index + 1, index + 2)
        if second == nil or third == nil then
            return nil, utf8_failure("truncated", index)
        end
        if not continuation(second) then
            return nil, utf8_failure("invalid-continuation", index + 1)
        end
        if not continuation(third) then
            return nil, utf8_failure("invalid-continuation", index + 2)
        end
        if first == 0xE0 and second < 0xA0 then
            return nil, utf8_failure("overlong", index)
        end
        if first == 0xED and second >= 0xA0 then
            return nil, utf8_failure("surrogate", index)
        end
        local codepoint = (first - 0xE0) * 0x1000
            + (second - 0x80) * 0x40
            + third - 0x80
        return codepoint, index + 3
    end
    if first >= 0xF0 and first <= 0xF4 then
        local second, third, fourth = value:byte(index + 1, index + 3)
        if second == nil or third == nil or fourth == nil then
            return nil, utf8_failure("truncated", index)
        end
        if not continuation(second) then
            return nil, utf8_failure("invalid-continuation", index + 1)
        end
        if not continuation(third) then
            return nil, utf8_failure("invalid-continuation", index + 2)
        end
        if not continuation(fourth) then
            return nil, utf8_failure("invalid-continuation", index + 3)
        end
        if first == 0xF0 and second < 0x90 then
            return nil, utf8_failure("overlong", index)
        end
        if first == 0xF4 and second > 0x8F then
            return nil, utf8_failure("above-maximum", index)
        end
        local codepoint = (first - 0xF0) * 0x40000
            + (second - 0x80) * 0x1000
            + (third - 0x80) * 0x40
            + fourth - 0x80
        return codepoint, index + 4
    end
    return nil, utf8_failure("invalid-leading-byte", index)
end

-- Validate every scalar and optionally retain the decoded scalar sequence.
--@param value any Candidate bytes; non-string input returns InvalidTextType.
--@param collect boolean Whether to include a dense codepoints array in the inspection.
--@return table|nil Byte/scalar counts, NUL flag and optional codepoints; nil on invalid input.
--@return table|nil Type or UTF-8 diagnostic with the offending byte location when available.
local function inspect_utf8(value, collect)
    if type(value) ~= "string" then
        return nil, failure("InvalidTextType", "UTF-8 input must be a byte string")
    end
    local index = 1
    local scalar_count = 0
    local contains_nul = false
    local codepoints = collect and {} or nil
    while index <= #value do
        local codepoint, next_index = decode_one(value, index)
        if codepoint == nil then return nil, next_index end
        scalar_count = scalar_count + 1
        contains_nul = contains_nul or codepoint == 0
        if codepoints then codepoints[scalar_count] = codepoint end
        index = next_index
    end
    return {
        byte_count = #value,
        scalar_count = scalar_count,
        contains_nul = contains_nul,
        codepoints = codepoints,
    }
end

-- Encode one validated Unicode scalar using its shortest UTF-8 representation.
--@param codepoint any Candidate integer; surrogate code points and values outside Unicode are rejected.
--@return string|nil One through four UTF-8 bytes, or nil for an invalid scalar.
--@return table|nil InvalidScalar diagnostic on failure.
local function encode_scalar_value(codepoint)
    if math.type(codepoint) ~= "integer"
        or codepoint < 0
        or codepoint > 0x10FFFF
        or (codepoint >= 0xD800 and codepoint <= 0xDFFF)
    then
        return nil, failure("InvalidScalar", "codepoint is not a Unicode scalar value")
    end
    if codepoint <= 0x7F then
        return string.char(codepoint)
    end
    if codepoint <= 0x7FF then
        return string.char(
            0xC0 + (codepoint // 0x40),
            0x80 + (codepoint % 0x40)
        )
    end
    if codepoint <= 0xFFFF then
        return string.char(
            0xE0 + (codepoint // 0x1000),
            0x80 + ((codepoint // 0x40) % 0x40),
            0x80 + (codepoint % 0x40)
        )
    end
    return string.char(
        0xF0 + (codepoint // 0x40000),
        0x80 + ((codepoint // 0x1000) % 0x40),
        0x80 + ((codepoint // 0x40) % 0x40),
        0x80 + (codepoint % 0x40)
    )
end

-- Register a read-only carrier with its exact bytes in the private weak-key registry.
--@param kind string Already validated carrier kind, either text or binary.
--@param bytes string Canonical bytes retained without conversion.
--@param scalar_count integer|nil Scalar count for text carriers; absent for binary carriers.
--@return table Registered carrier exposing its kind, exact bytes and byte/scalar counts.
--@effect Adds one private registry entry whose lifetime follows the returned carrier.
local function new_carrier(kind, bytes, scalar_count)
    local values = {
        kind = kind,
        bytes = bytes,
        byte_count = #bytes,
    }
    if scalar_count ~= nil then values.scalar_count = scalar_count end
    local carrier = readonly(values, kind .. " carrier")
    carrier_values[carrier] = values
    return carrier
end

-- Resolve bytes from a registered carrier or accept an untyped raw byte string.
--@param value any Registered carrier proxy or raw string; other values are not admitted.
--@return string|nil Exact underlying bytes; nil for unregistered non-string input.
--@return string|nil Registered kind or untyped for a raw string; nil when input is rejected.
local function carrier_bytes(value)
    local values = carrier_values[value]
    if values then return values.bytes, values.kind end
    if type(value) == "string" then return value, "untyped" end
    return nil
end

-- Determine whether an XML text round trip can preserve this scalar exactly.
--@param codepoint integer Decoded Unicode scalar value.
--@return boolean True for XML-safe text scalars except carriage return, which XML normalizes.
--@return string|nil carriage-return or xml-control when text would lose or reject the scalar.
local function xml_text_lossless(codepoint)
    if codepoint == 0x0D then return false, "carriage-return" end
    if codepoint == 0x09 or codepoint == 0x0A then return true end
    if codepoint >= 0x20 and codepoint <= 0xD7FF then return true end
    if codepoint >= 0xE000 and codepoint <= 0xFFFD then return true end
    if codepoint >= 0x10000 and codepoint <= 0x10FFFF then return true end
    return false, "xml-control"
end

-- Identify controls and invisible formatting scalars that require a visible terminal escape.
--@param codepoint integer Decoded Unicode scalar value.
--@return boolean True for the control, bidi, separator and invisible-format ranges listed here.
local function terminal_control(codepoint)
    return codepoint < 0x20
        or (codepoint >= 0x7F and codepoint <= 0x9F)
        or codepoint == 0x061C
        or (codepoint >= 0x200B and codepoint <= 0x200F)
        or (codepoint >= 0x2028 and codepoint <= 0x202E)
        or (codepoint >= 0x2060 and codepoint <= 0x206F)
        or (codepoint >= 0xFFF9 and codepoint <= 0xFFFB)
        or codepoint == 0xFEFF
end

-- Normalize the two display switches while rejecting unknown fields and non-boolean values.
--@param options table|nil ascii_only and allow_newline switches; absent switches default to false.
--@return table|nil Fresh normalized boolean options, or nil for invalid input.
--@return table|nil InvalidDisplayOptions diagnostic on failure.
local function validate_display_options(options)
    options = options or {}
    if type(options) ~= "table" then
        return nil, failure("InvalidDisplayOptions", "display options must be a table")
    end
    local allowed = { ascii_only = true, allow_newline = true }
    for key in pairs(options) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure("InvalidDisplayOptions", "display options contain an unknown field")
        end
    end
    if options.ascii_only ~= nil and type(options.ascii_only) ~= "boolean" then
        return nil, failure("InvalidDisplayOptions", "ascii_only must be boolean")
    end
    if options.allow_newline ~= nil and type(options.allow_newline) ~= "boolean" then
        return nil, failure("InvalidDisplayOptions", "allow_newline must be boolean")
    end
    return {
        ascii_only = options.ascii_only == true,
        allow_newline = options.allow_newline == true,
    }
end

---Validates that bytes encode exactly one strict Unicode scalar sequence.
-- No normalization or replacement is performed. NUL is valid UTF-8 and is
-- reported separately because ordinary text carriers reject it.
--@param value string Exact candidate bytes.
--@return boolean valid Whether the bytes are strict UTF-8.
--@return table metadata_or_err Counts or a stable error with byte offset.
function M.validate_utf8(value)
    local inspection, validation_error = inspect_utf8(value, false)
    if not inspection then return false, validation_error end
    return true, readonly({
        byte_count = inspection.byte_count,
        scalar_count = inspection.scalar_count,
        contains_nul = inspection.contains_nul,
    }, "UTF-8 metadata")
end

---Decodes strict UTF-8 into Unicode scalar integers.
--@param value string Exact candidate bytes.
--@return table|nil codepoints Dense scalar array when valid.
--@return table|nil err Stable validation failure.
function M.decode_utf8(value)
    local inspection, validation_error = inspect_utf8(value, true)
    if not inspection then return nil, validation_error end
    return inspection.codepoints
end

---Encodes one Unicode scalar without normalization.
--@param codepoint integer Unicode scalar value.
--@return string|nil bytes Exact UTF-8 bytes.
--@return table|nil err Structured scalar failure.
function M.encode_scalar(codepoint)
    return encode_scalar_value(codepoint)
end

---Encodes a dense array of Unicode scalar values.
--@param codepoints table Dense scalar array.
--@return string|nil bytes Concatenated strict UTF-8.
--@return table|nil err Structured array or scalar failure.
function M.encode_utf8(codepoints)
    if type(codepoints) ~= "table" then
        return nil, failure("InvalidScalarArray", "codepoints must be a dense array")
    end
    local count = 0
    for key in pairs(codepoints) do
        if math.type(key) ~= "integer" or key < 1 then
            return nil, failure("InvalidScalarArray", "codepoints must be a dense array")
        end
        count = count + 1
    end
    local output = {}
    for index = 1, count do
        if codepoints[index] == nil then
            return nil, failure("InvalidScalarArray", "codepoints must not be sparse")
        end
        local encoded, encode_error = encode_scalar_value(codepoints[index])
        if not encoded then
            encode_error.index = index
            return nil, encode_error
        end
        output[index] = encoded
    end
    return table.concat(output)
end

---Creates an immutable canonical text carrier.
-- Strict UTF-8 is preserved byte-for-byte; NUL is rejected at this text
-- boundary even though it remains a valid Unicode scalar and valid binary byte.
--@param bytes string Exact UTF-8 bytes.
--@return table|nil carrier Immutable text carrier.
--@return table|nil err Structured validation failure.
function M.text(bytes)
    local inspection, validation_error = inspect_utf8(bytes, false)
    if not inspection then return nil, validation_error end
    if inspection.contains_nul then
        return nil, failure("NulNotText", "NUL cannot enter the ordinary text carrier")
    end
    return new_carrier("text", bytes, inspection.scalar_count)
end

---Creates an immutable binary carrier without decoding or rewriting bytes.
--@param bytes string Exact arbitrary bytes.
--@return table|nil carrier Immutable binary carrier.
--@return table|nil err Structured type failure.
function M.binary(bytes)
    if type(bytes) ~= "string" then
        return nil, failure("InvalidBinaryType", "binary input must be a byte string")
    end
    return new_carrier("binary", bytes)
end

---Returns the exact canonical bytes from a project carrier.
--@param carrier table Text or binary carrier created by this module.
--@return string|nil bytes Exact original bytes.
--@return table|nil err Structured carrier failure.
function M.canonical_bytes(carrier)
    local values = carrier_values[carrier]
    if not values then
        return nil, failure("InvalidCarrier", "value is not a text or binary carrier")
    end
    return values.bytes
end

---Selects the lossless XML representation without encoding it.
-- Invalid UTF-8 and XML-unsafe scalars are classified as binary so a later
-- typed base64 codec can preserve their exact bytes.
--@param bytes string Exact bytes to classify.
--@return string|nil kind Either "text" or "binary".
--@return string|table|nil reason Stable binary reason or input type error.
function M.xml_carrier_kind(bytes)
    if type(bytes) ~= "string" then
        return nil, failure("InvalidBinaryType", "XML carrier input must be bytes")
    end
    local index = 1
    while index <= #bytes do
        local codepoint, next_index = decode_one(bytes, index)
        if codepoint == nil then return "binary", "invalid-utf8" end
        local lossless, reason = xml_text_lossless(codepoint)
        if not lossless then return "binary", reason end
        index = next_index
    end
    return "text"
end

---Produces a terminal-safe display projection without changing canonical bytes.
-- Binary and invalid input escape non-ASCII octets as hexadecimal. Valid text
-- preserves Unicode only when ascii_only is false and always escapes controls.
--@param value string|table Raw bytes or a text/binary carrier.
--@param options table|nil ascii_only and allow_newline switches.
--@return string|nil display Safe display bytes.
--@return table|nil err Structured input or option failure.
function M.display_lossy(value, options)
    local bytes, kind = carrier_bytes(value)
    if not bytes then
        return nil, failure("InvalidCarrier", "display input must be bytes or a carrier")
    end
    local validated_options, options_error = validate_display_options(options)
    if not validated_options then return nil, options_error end
    local valid = inspect_utf8(bytes, false) ~= nil
    local binary_mode = kind == "binary" or not valid
    local output = {}
    local index = 1
    while index <= #bytes do
        if binary_mode then
            local byte = bytes:byte(index)
            if byte >= 0x20 and byte <= 0x7E then
                output[#output + 1] = string.char(byte)
            else
                output[#output + 1] = string.format("\\x%02X", byte)
            end
            index = index + 1
        else
            local codepoint, next_index = decode_one(bytes, index)
            if codepoint == 0x0A and validated_options.allow_newline then
                output[#output + 1] = "\n"
            elseif codepoint == 0x09 then
                output[#output + 1] = "\\t"
            elseif codepoint == 0x0A then
                output[#output + 1] = "\\n"
            elseif codepoint == 0x0D then
                output[#output + 1] = "\\r"
            elseif terminal_control(codepoint) then
                output[#output + 1] = string.format("\\u{%04X}", codepoint)
            elseif codepoint > 0x7F and validated_options.ascii_only then
                output[#output + 1] = string.format("\\u{%X}", codepoint)
            else
                output[#output + 1] = bytes:sub(index, next_index - 1)
            end
            index = next_index
        end
    end
    return table.concat(output)
end

return M
