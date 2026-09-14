--[[
File: windows_native_smoke.lua
Date: 2026-09-14
Author: WaterRun
Description: Exercises real Windows publication primitives and the bundled XML module.
]]

local root = assert(arg[1], "an isolated writable test directory is required")
local native = require("yaca_native")
local lxp = require("lxp")
assert(native.platform_identity().os == "windows")
assert(native.platform_identity().arch == "x86")
assert(native.abi_version() == "yaca-native-v0.1.0")
assert(lxp._VERSION == "LuaExpat 1.5.2")
assert(lxp._EXPAT_VERSION == "expat_2.8.2")
local function check(ok, value)
    if not ok then error(type(value) == "table" and value.code or tostring(value)) end
    return value
end

local path = root .. "/publication-smoke.txt"
local renamed = root .. "/publication-smoke-renamed.txt"
local file = check(native.fs_create_new(path, 384))
check(native.fs_write(file, "Windows publication smoke\r\n"))
check(native.fs_flush_file(file))
check(native.fs_close(file))
check(native.fs_flush_directory(root))
check(native.fs_rename_no_replace(path, renamed))
check(native.fs_flush_directory(root))
local identity = check(native.fs_stat_identity(renamed))
file = check(native.fs_open_read(renamed))
assert(check(native.fs_read(file, 128)).bytes == "Windows publication smoke\r\n")
check(native.fs_close(file))
check(native.fs_delete_verified(renamed, identity))
check(native.fs_flush_directory(root))
-- Inspection enumerates NTFS streams before returning a verified read handle.
-- The returned handle must still start at byte zero, including after create.
local direct_path = root .. "/direct-read-smoke.txt"
local missing = check(native.fs_inspect_direct(direct_path))
assert(not missing.exists)
file = check(native.fs_create_new_verified(direct_path, missing.parent_identity, 384))
local payload = "verified Windows read\n"
check(native.fs_write(file, payload))
check(native.fs_flush_file(file))
check(native.fs_close(file))
local snapshot = check(native.fs_inspect_direct(direct_path))
assert(snapshot.identity.size == #payload)
file = check(native.fs_open_read_verified(direct_path, snapshot.identity))
assert(check(native.fs_read(file, 128)).bytes == payload, "verified read lost file bytes")
assert(check(native.fs_read(file, 128)).eof)
check(native.fs_close(file))
check(native.fs_delete_verified(direct_path, snapshot.identity))
local parser = assert(lxp.new({}))
assert(parser:parse("<smoke>Windows XML</smoke>"))
assert(parser:parse())
parser:close()
print("windows-native-publication-and-xml=PASS")
