--[[
Author: WaterRun
Date: 2026-09-23
File: windows_native_smoke.lua
Description: Exercises real Windows publication primitives and the bundled XML module.
]]

local root = assert(arg[1], "an isolated writable test directory is required")
local native = require("yaca_native")
local lxp = require("lxp")
assert(native.platform_identity().os == "windows")
local architecture, inherited_fixture = "x86", false
for index = 2, #arg do
    if arg[index] == "--inherited-fixture" then inherited_fixture = true
    else architecture = arg[index] end
end
assert(native.platform_identity().arch == architecture)
assert(native.abi_version() == "yaca-native-v0.1.0")
assert(lxp._VERSION == "LuaExpat 1.5.2")
assert(lxp._EXPAT_VERSION == "expat_2.8.2")
--Records an assertion failure when a windows native smoke condition is false.
--@param ok boolean Success status returned by the fake operation.
--@param value any Candidate value supplied to the fixture operation.
--@return any observed Selected fixture value returned by the fixture.
local function check(ok, value)
    if not ok then
        error(type(value) == "table" and (value.code .. ": " .. (value.message or "")) or tostring(value))
    end
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
-- Always cover native-created files with the legacy inheritance descriptor.
-- windows_inherited_smoke.py creates the modern-inheritance fixture with
-- verified AUTO_INHERITED control and inherited ACEs, then passes
-- --inherited-fixture. No PowerShell version or execution policy is required.
local replacements = inherited_fixture and { false, true } or { false }
for _, inherited in ipairs(replacements) do
    local target_path = root .. (inherited and "/direct-inherited-smoke.txt" or "/direct-replace-smoke.txt")
    local temporary_path = root .. "/direct-replace-smoke.tmp"
    if not inherited then
        file = check(native.fs_create_new(target_path, 384))
        check(native.fs_write(file, "original"))
        check(native.fs_flush_file(file))
        check(native.fs_close(file))
    end
    file = check(native.fs_create_new(temporary_path, 384))
    check(native.fs_write(file, payload))
    check(native.fs_flush_file(file))
    check(native.fs_close(file))
    local target = check(native.fs_inspect_direct(target_path))
    local temporary = check(native.fs_inspect_direct(temporary_path))
    if inherited then
        assert(target.metadata.behavior_digest ~= temporary.metadata.behavior_digest,
            "test fixture must provide an inherited DACL distinct from a native temporary")
    end
    check(native.fs_replace_verified(temporary_path, target_path,
        temporary.identity, target.identity, target.parent_identity, target.metadata.behavior_digest))
    local replaced = check(native.fs_inspect_direct(target_path))
    assert(replaced.metadata.behavior_digest == target.metadata.behavior_digest)
    assert(not check(native.fs_inspect_direct(temporary_path)).exists)
    assert(not check(native.fs_inspect_direct(temporary_path .. ".yaca-previous")).exists)
    file = check(native.fs_open_read_verified(target_path, replaced.identity))
    assert(check(native.fs_read(file, 128)).bytes == payload)
    check(native.fs_close(file))
    check(native.fs_delete_verified(target_path, replaced.identity))
    print(inherited and "windows-inherited-replacement=PASS" or "windows-legacy-replacement=PASS")
end
-- On FAT, a longer filename can change the numeric file ID. Every operation
-- must still bind to the admitted object and remove only its own recovery file.
local short = root .. "/s.tmp"
local longer = root .. "/a-much-longer-direct-publication-target.txt"
--Constructs bytes for windows native smoke.
--@param name string Module, Model, or resource name selected by the case.
--@param bytes string Byte chunk supplied to the fake I/O port.
--@return any created Constructed create bytes fixture value.
local function create_bytes(name, bytes)
    local handle = check(native.fs_create_new(name, 384))
    check(native.fs_write(handle, bytes))
    check(native.fs_flush_file(handle))
    check(native.fs_close(handle))
    return check(native.fs_inspect_direct(name))
end
local initial = create_bytes(short, "longer filename payload\n")
local destination = check(native.fs_inspect_direct(longer))
local rename_receipt = check(native.fs_rename_no_replace_verified(short, longer, initial.identity,
    initial.parent_identity, destination.parent_identity))
assert(not check(native.fs_inspect_direct(short)).exists)
local current = check(native.fs_inspect_direct(longer))
assert(rename_receipt.object == current.identity.object and rename_receipt.volume == current.identity.volume)
local replacement = create_bytes(short, "replacement with a changed file ID\n")
local replace_receipt = check(native.fs_replace_verified(short, longer, replacement.identity,
    current.identity, current.parent_identity, current.metadata.behavior_digest))
current = check(native.fs_inspect_direct(longer))
assert(replace_receipt.object == current.identity.object and replace_receipt.volume == current.identity.volume)
file = check(native.fs_open_read_verified(longer, current.identity))
assert(check(native.fs_read(file, 128)).bytes == "replacement with a changed file ID\n")
check(native.fs_close(file))
check(native.fs_delete_direct_verified(longer, current.identity, current.parent_identity))
assert(not check(native.fs_inspect_direct(longer)).exists)
assert(not check(native.fs_inspect_direct(longer .. ".yaca-delete")).exists)
assert(not check(native.fs_inspect_direct(short .. ".yaca-previous")).exists)
local short_directory = root .. "/d"
local long_directory = root .. "/a-much-longer-directory-name"
check(native.fs_make_directory(short_directory, 448))
initial = check(native.fs_inspect_direct(short_directory))
destination = check(native.fs_inspect_direct(long_directory))
check(native.fs_rename_no_replace_verified(short_directory, long_directory,
    initial.identity, initial.parent_identity, destination.parent_identity))
current = check(native.fs_inspect_direct(long_directory))
check(native.fs_delete_direct_verified(long_directory, current.identity, current.parent_identity))
assert(not check(native.fs_inspect_direct(short_directory)).exists)
assert(not check(native.fs_inspect_direct(long_directory)).exists)
print("windows-longer-name-rename-replace-delete=PASS file-and-directory")
local parser = assert(lxp.new({}))
assert(parser:parse("<smoke>Windows XML</smoke>"))
assert(parser:parse())
parser:close()
print("windows-native-publication-and-xml=PASS")
