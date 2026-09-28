--[[
Author: WaterRun
Date: 2026-09-28
File: textcodec.lua
Description: Normalizes text encoding labels and adapts native code page conversion for tools.
]]

local M = {}

-- Build a typed text-codec failure.
--@param code string Stable diagnostic code.
--@param message string Human-readable summary.
--@return table New diagnostic record.
local function failure(code, message)
    return { code = code, message = message }
end

-- Supported single-byte and double-byte legacy code pages. Stateful ISO-2022,
-- UTF-7 and EBCDIC pages are excluded because line splitting on ASCII CR/LF
-- bytes would not be valid for them.
local SUPPORTED_CODEPAGES = {}
for _, codepage in ipairs({
    437, 720, 737, 775, 850, 852, 855, 857, 858, 860, 861, 862, 863, 864, 865,
    866, 869, 874, 932, 936, 949, 950, 1250, 1251, 1252, 1253, 1254, 1255,
    1256, 1257, 1258, 20866, 21866, 28591, 28592, 28593, 28594, 28595, 28596,
    28597, 28598, 28599, 28603, 28605, 54936,
}) do
    SUPPORTED_CODEPAGES[codepage] = true
end

-- Common charset names mapped to their Windows code page numbers.
local ALIASES = {
    gbk = 936, gb2312 = 936, ["euc-cn"] = 936, euccn = 936, ["x-gbk"] = 936,
    gb18030 = 54936,
    big5 = 950, ["big5-hkscs"] = 950,
    ["shift_jis"] = 932, ["shift-jis"] = 932, sjis = 932, ["windows-31j"] = 932,
    ["euc-kr"] = 949, euckr = 949, uhc = 949, ["ks_c_5601-1987"] = 949,
    latin1 = 28591, ["latin-1"] = 28591,
    ["koi8-r"] = 20866, koi8r = 20866, ["koi8-u"] = 21866, koi8u = 21866,
    ["tis-620"] = 874,
}

-- iconv names used on POSIX for code pages whose "CP<N>" alias is not portable.
local ICONV_NAMES = {
    [932] = "CP932", [936] = "CP936", [949] = "CP949", [950] = "CP950",
    [874] = "CP874", [20866] = "KOI8-R", [21866] = "KOI8-U",
    [28603] = "ISO-8859-13", [28605] = "ISO-8859-15", [54936] = "GB18030",
}
for part = 1, 9 do ICONV_NAMES[28590 + part] = "ISO-8859-" .. tostring(part) end

-- Map a numeric code page to its canonical label when it is supported.
--@param codepage integer|nil Candidate Windows code page number.
--@return string|nil Canonical "cp<N>" label, or nil when unsupported.
local function codepage_label(codepage)
    if math.type(codepage) == "integer" and SUPPORTED_CODEPAGES[codepage] then
        return "cp" .. tostring(codepage)
    end
    return nil
end

---Normalizes a user or model supplied charset label.
-- UTF labels keep their tool spelling; legacy names become "cp<N>".
--@param label any Candidate label such as "GBK", "cp936", "windows-1252" or "utf8".
--@return string|nil Canonical label: utf-8, utf-8-bom, utf-16le-bom, utf-16be-bom, or cp<N>.
--@return table|nil InvalidEncoding diagnostic for unknown or unsupported labels.
function M.normalize(label)
    if type(label) ~= "string" or #label == 0 or #label > 64 then
        return nil, failure("InvalidEncoding", "encoding label is invalid")
    end
    local lowered = label:lower()
    if lowered == "utf-8" or lowered == "utf8" then return "utf-8" end
    if lowered == "utf-8-bom" then return "utf-8-bom" end
    if lowered == "utf-16le-bom" then return "utf-16le-bom" end
    if lowered == "utf-16be-bom" then return "utf-16be-bom" end
    local number = lowered:match("^cp(%d+)$")
        or lowered:match("^windows%-(%d+)$")
        or lowered:match("^ibm(%d+)$")
        or lowered:match("^x%-cp(%d+)$")
    if number then
        local label_result = codepage_label(tonumber(number))
        if label_result then return label_result end
        return nil, failure("InvalidEncoding", "code page is not supported: " .. label)
    end
    local iso = lowered:match("^iso%-?8859%-(%d+)$")
    if iso then
        local part = tonumber(iso)
        local mapped = (part >= 1 and part <= 9) and (28590 + part)
            or (part == 13 and 28603) or (part == 15 and 28605) or nil
        if mapped then return codepage_label(mapped) end
        return nil, failure("InvalidEncoding", "ISO-8859 part is not supported: " .. label)
    end
    local alias = ALIASES[lowered]
    if alias then return codepage_label(alias) end
    return nil, failure("InvalidEncoding", "encoding label is not supported: " .. label)
end

---Reports whether a canonical label names a legacy code page.
--@param label any Canonical label.
--@return boolean True for cp<N> labels.
function M.is_legacy(label)
    return type(label) == "string" and label:match("^cp%d+$") ~= nil
end

-- Derive the POSIX locale charset from the process environment without calling setlocale.
--@param getenv function Environment reader compatible with os.getenv.
--@return string|boolean utf-8, a supported cp<N> label, or false when unknown or ASCII-only.
local function posix_locale_charset(getenv)
    local value
    for _, name in ipairs({ "LC_ALL", "LC_CTYPE", "LANG" }) do
        local called, candidate = pcall(getenv, name)
        if called and type(candidate) == "string" and candidate ~= "" then
            value = candidate
            break
        end
    end
    if not value then return false end
    local charset = value:match("^[^.@]*%.([^@]+)")
    if not charset then return false end
    local normalized = M.normalize(charset)
    return normalized or false
end

---Creates the production codec from the native module, or returns false when unavailable.
--@param native table|nil Loaded yaca_native module.
--@param platform_kind string windows or posix.
--@param getenv function|nil Environment reader for POSIX locale facts; defaults to os.getenv.
--@return table|boolean Read-only codec service, or false when the native module lacks text conversion.
function M.new(native, platform_kind, getenv)
    if type(native) ~= "table"
        or type(native.text_convert) ~= "function"
        or type(native.text_facts) ~= "function"
        or (platform_kind ~= "windows" and platform_kind ~= "posix")
    then
        return false
    end
    local called, raw = pcall(native.text_facts)
    if not called or type(raw) ~= "table" then return false end
    local facts = { platform = platform_kind }
    if platform_kind == "windows" then
        facts.ansi = codepage_label(raw.ansi) or (raw.ansi == 65001 and "utf-8") or false
        facts.oem = codepage_label(raw.oem) or (raw.oem == 65001 and "utf-8") or false
        facts.console_output = codepage_label(raw.console_output)
            or (raw.console_output == 65001 and "utf-8") or false
        facts.file_default = M.is_legacy(facts.ansi) and facts.ansi or false
        local output = facts.console_output or facts.oem
        facts.output_default = M.is_legacy(output) and output or false
    else
        facts.locale = posix_locale_charset(getenv or os.getenv)
        facts.file_default = M.is_legacy(facts.locale) and facts.locale or false
        facts.output_default = facts.file_default
    end

    -- Translate a canonical legacy label into the native conversion target.
    --@param label string Canonical cp<N> label.
    --@return integer|string|nil Windows code page number or iconv charset name.
    --@return table|nil InvalidEncoding diagnostic.
    local function native_target(label)
        local number = M.is_legacy(label) and tonumber(label:sub(3)) or nil
        if not number or not SUPPORTED_CODEPAGES[number] then
            return nil, failure("InvalidEncoding", "legacy code page label is invalid")
        end
        if platform_kind == "windows" then return number end
        return ICONV_NAMES[number] or ("CP" .. tostring(number))
    end

    -- Invoke the native converter, preserving typed errors and checking its success contract.
    --@param direction string decode or encode.
    --@param label string Canonical cp<N> label.
    --@param bytes string Input bytes.
    --@param lossy boolean Whether decoding may replace invalid input.
    --@return string|nil Converted bytes.
    --@return boolean|table Exact flag on success, or a native diagnostic/NativeFailure/NativeContract error.
    local function convert(direction, label, bytes, lossy)
        if type(bytes) ~= "string" then
            return nil, failure("InvalidEncoding", "text conversion input must be a string")
        end
        local target, target_error = native_target(label)
        if not target then return nil, target_error end
        local allow_lossy = direction == "decode" and lossy == true
        local invoked, ok, output, exact = pcall(native.text_convert, direction, target, bytes, allow_lossy)
        if not invoked then
            return nil, failure("NativeFailure", "native text conversion raised an exception")
        end
        if ok ~= true then
            if ok == false and type(output) == "table" and type(output.code) == "string" then
                return nil, failure(output.code, tostring(output.message))
            end
            return nil, failure("NativeContract", "native text conversion returned an invalid failure")
        end
        if type(output) ~= "string" or type(exact) ~= "boolean"
            or (not allow_lossy and not exact)
        then
            return nil, failure("NativeContract", "native text conversion returned an invalid success")
        end
        return output, exact
    end

    --@metatable text_codec_facts Read-only view of the observed code page facts.
    --@field __index table Observed facts table.
    --@field __newindex function Rejects mutation.
    --@field __metatable string Locked marker.
    local frozen_facts = setmetatable({}, {
        __index = facts,
        -- Reject mutation of observed platform facts.
        --@param _ table Proxy receiving the assignment.
        --@param key any Attempted field name.
        --@return nil Does not return normally.
        --@error Always raises a read-only error.
        __newindex = function(_, key)
            error("text codec facts cannot be modified: " .. tostring(key), 2)
        end,
        __metatable = "locked",
    })
    --@metatable text_codec Read-only codec service shared by tool services.
    --@field __index table Codec methods and facts.
    --@field __newindex function Rejects mutation.
    --@field __metatable string Locked marker.
    return setmetatable({}, {
        __index = {
            facts = frozen_facts,
            -- Decode legacy bytes into UTF-8.
            --@param label string Canonical cp<N> label.
            --@param bytes string Input bytes.
            --@param lossy boolean|nil Whether invalid sequences may be replaced.
            --@return string|nil UTF-8 text.
            --@return boolean|table True when the conversion is exact, false when lossy, or a diagnostic.
            decode = function(label, bytes, lossy)
                return convert("decode", label, bytes, lossy)
            end,
            -- Encode UTF-8 text into a legacy code page only when exact.
            --@param label string Canonical cp<N> label.
            --@param text string Strict UTF-8 text.
            --@return string|nil Encoded bytes.
            --@return boolean|table True on success, or an encoding, resource or native-port diagnostic.
            encode = function(label, text)
                return convert("encode", label, text, false)
            end,
        },
        -- Reject mutation of the shared codec.
        --@param _ table Proxy receiving the assignment.
        --@param key any Attempted field name.
        --@return nil Does not return normally.
        --@error Always raises a read-only error.
        __newindex = function(_, key)
            error("text codec cannot be modified: " .. tostring(key), 2)
        end,
        __metatable = "locked",
    })
end

return M
