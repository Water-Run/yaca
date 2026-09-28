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
local checked, unavailable = 0, 0
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
        assert(decoded == item[3] and exact == true, "native decode failed for " .. label)
        local encoded, encoded_exact = codec.encode(label, item[3])
        assert(encoded == item[2] and encoded_exact == true, "native encode failed for " .. label)
        checked = checked + 1
    end
end

local invalid, invalid_error = codec.decode("cp936", "\255", false)
assert(not invalid and invalid_error.code == "InvalidEncoding", "invalid GBK was accepted")
local encoded, encoded_error = codec.encode("cp936", "😀")
assert(not encoded and encoded_error.code == "EncodingLossy", "unmappable GBK was accepted")
assert(checked > 0, "no native charset was exercised")
print("text-codec=PASS platform=" .. platform .. " cases=" .. checked .. " unavailable=" .. unavailable)
