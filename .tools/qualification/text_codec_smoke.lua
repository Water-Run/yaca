--[[
Author: WaterRun
Date: 2026-09-28
File: text_codec_smoke.lua
Description: Exercises production legacy-code-page conversion through the native module on qualification hosts.
]]

local native = require("yaca_native")
local root = assert(arg[1], "usage: text_codec_smoke.lua REPOSITORY_ROOT")
local textcodec = assert(loadfile(root .. "/src/textcodec.lua"))()
local identity = native.platform_identity()
local platform = identity.os == "windows" and "windows" or "posix"
local codec = assert(textcodec.new(native, platform), "native text codec unavailable")
local checked, unavailable, failures = 0, 0, 0
local available = {}

-- Retain every failed codec observation so one unavailable/broken page does not hide later repair checks.
--@param condition boolean Whether the observation matched its expected conversion result.
--@param message string Safe case description without file contents or credentials.
--@return boolean The supplied condition.
--@effect Increments the failure count and prints a diagnostic when the condition is false.
local function check(condition, message)
    if not condition then
        failures = failures + 1
        print("FAIL " .. message)
    end
    return condition
end

local cases = {
    { "gbk", "\214\208\206\196", "中文" },
    { "latin1", "\233", "é" },
    { "iso-8859-2", "\163", "Ł" },
    { "iso-8859-5", "\208", "а" },
    { "iso-8859-7", "\225", "α" },
    { "iso-8859-9", "\253", "ı" },
    { "iso-8859-13", "\192", "Ą" },
    { "iso-8859-15", "\164", "€" },
    { "cp874", "\128\161", "€ก" },
    { "cp950", "\249\214", "碁" },
    { "cp1252", "\128\233", "€é" },
    { "cp932", "\130\160", "あ" },
    { "gb18030", "\148\57\252\54", "😀" },
}

for _, item in ipairs(cases) do
    local label = assert(textcodec.normalize(item[1]))
    local decoded, exact = codec.decode(label, item[2], false)
    if not decoded and type(exact) == "table" and exact.code == "EncodingUnavailable"
        and platform == "windows" and not native.text_convert("decode", tonumber(label:sub(3)), "", false)
    then
        -- An optional Windows NLS page may be absent. Report it separately from a pass.
        unavailable = unavailable + 1
        print("unavailable=" .. label)
    else
        local decode_ok = check(decoded == item[3] and exact == true, "native decode failed for " .. label)
        local encoded, encoded_exact = codec.encode(label, item[3])
        local encode_ok = check(encoded == item[2] and encoded_exact == true, "native encode failed for " .. label)
        if decode_ok and encode_ok then
            checked = checked + 1
            available[label] = true
        end
    end
end

local invalid, invalid_error = codec.decode("cp936", "\255", false)
check(not invalid and type(invalid_error) == "table" and invalid_error.code == "InvalidEncoding", "invalid GBK was accepted")
local encoded, encoded_error = codec.encode("cp936", "😀")
check(not encoded and type(encoded_error) == "table" and encoded_error.code == "EncodingLossy", "unmappable GBK was accepted")
local replacement = "\239\191\189"
local damaged = {
    { "\255", replacement },
    { "a\255b", "a" .. replacement .. "b" },
    { "\255\255", replacement .. replacement },
    { "a\214", "a" .. replacement },
    { "a\214 b", "a" .. replacement .. " b" },
    { "\214\208\255\206\196", "中" .. replacement .. "文" },
    { "a\0\255b", "a\0" .. replacement .. "b" },
}
for index, item in ipairs(damaged) do
    local decoded, exact = codec.decode("cp936", item[1], true)
    check(decoded == item[2] and exact == false, "lossy GBK replacement failed for case " .. tostring(index))
end
local aliases_checked = 0
if available.cp932 then
    -- CP932 has duplicate encodings for this valid character; lossy display retains its meaning.
    local ambiguous, exact = codec.decode("cp932", "\135\144", true)
    check(ambiguous == "≒" and exact == false, "non-round-trip CP932 character was discarded")
    local repaired, repaired_exact = codec.decode("cp932", "\135\144\129", true)
    check(repaired == "≒" .. replacement and repaired_exact == false,
        "CP932 repair discarded a valid duplicate mapping next to invalid input")
    aliases_checked = 2
end
local invalid_utf8 = {
    "\128", "\192\175", "\224\128\175", "\237\160\128",
    "\244\144\128\128", "\245\128\128\128", "\226\130", "\226\40\161",
}
for index, bytes in ipairs(invalid_utf8) do
    local result, err = codec.encode("cp1252", "a" .. bytes .. "b")
    check(not result and type(err) == "table" and err.code == "InvalidEncoding",
        "strict UTF-8 encoding rejection failed for case " .. tostring(index))
end
local gb_repaired = 0
if available.cp54936 then
    local result, exact = codec.decode("cp54936", "\148\57\252\54\255x", true)
    check(result == "😀" .. replacement .. "x" and exact == false, "GB18030 repair lost valid supplementary text")
    gb_repaired = 1
end
check(checked > 0, "no native charset was exercised")
print("text-codec=" .. (failures == 0 and "PASS" or "FAIL") .. " platform=" .. platform .. " cases=" .. checked
    .. " lossy=" .. #damaged .. " duplicate_mappings=" .. aliases_checked
    .. " invalid_utf8=" .. #invalid_utf8 .. " gb18030_repair=" .. gb_repaired
    .. " unavailable=" .. unavailable .. " failures=" .. failures)
assert(failures == 0, "native codec qualification failed")
