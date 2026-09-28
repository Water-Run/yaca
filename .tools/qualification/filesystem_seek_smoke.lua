--[[
Author: WaterRun
Date: 2026-09-28
File: filesystem_seek_smoke.lua
Description: Exercises native byte seeking across 32-bit offsets, EOF and invalid/closed handles without growing the fixture file.
]]

local root = assert(arg[1], "an isolated writable test directory is required")
local native = require("yaca_native")

-- Require a successful native port result while preserving its diagnostic on failure.
--@param ok boolean Native success flag.
--@param value any Native success value or structured diagnostic.
--@return any The success value, including false when that is an acknowledged result.
--@error Raises the native diagnostic; a failed probe retains its isolated file for inspection.
local function check(ok, value)
    if not ok then
        error(type(value) == "table" and (tostring(value.code) .. ": " .. tostring(value.message)) or tostring(value))
    end
    return value
end

local path = root .. "/seek-smoke.bin"
local payload = "0123456789\0中文\r\nEND"
local handle = check(native.fs_create_new(path, 384))
assert(check(native.fs_write(handle, payload)) == #payload)
check(native.fs_flush_file(handle))
check(native.fs_close(handle))
local before = check(native.fs_stat_identity(path))
handle = check(native.fs_open_read(path))
local offsets = { 0, 1, #payload - 1, #payload, #payload + 1,
    2147483647, 2147483648, 4294967295, 4294967296, 4294967303, 1, 0 }
for _, offset in ipairs(offsets) do
    assert(check(native.fs_seek(handle, offset)) == offset, "native seek narrowed the byte offset")
    local chunk = check(native.fs_read(handle, 7))
    local expected = offset >= #payload and "" or payload:sub(offset + 1, offset + 7)
    assert(chunk.bytes == expected, "native seek/read returned different byte content")
    assert(chunk.eof == (expected == ""), "native EOF disagrees with the byte read")
end
local accepted, invalid = native.fs_seek(handle, -1)
assert(accepted == false and type(invalid) == "table" and invalid.code == "Limit")
assert(check(native.fs_read(handle, 7)).bytes == payload:sub(8, 14),
    "rejected negative seek changed the handle position")
local after = check(native.fs_stat_identity(handle))
for key, value in pairs(before) do
    assert(after[key] == value, "read-only seeking changed file identity: " .. key)
end
check(native.fs_close(handle))
assert(not pcall(native.fs_seek, handle, 0), "closed handle accepted a seek")
check(native.fs_delete_verified(path, before))
print("filesystem-seek=PASS platform=" .. native.platform_identity().os
    .. " offsets=" .. #offsets .. " negative_rejection=1 closed_rejection=1 stable_identity=1")
