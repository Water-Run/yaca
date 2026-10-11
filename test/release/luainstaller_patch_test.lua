--[[
Author: WaterRun
Date: 2026-10-09
File: luainstaller_patch_test.lua
Description: Verifies the exact downstream resource-overlay patch as release input.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()
local SHA256 = assert(loadfile(
    YACA_TEST_ROOT .. "/test/support/sha256_reference.lua",
    "t",
    _ENV
))()

--Reads load value for this test scenario.
--@param relative_path string Repository-relative Lua source path to load.
--@return any module Lua module value loaded for this case.
local function load_value(relative_path)
    local chunk, load_error = loadfile(YACA_TEST_ROOT .. "/" .. relative_path, "t", _ENV)
    A.truthy(chunk, load_error)
    local ok, value = pcall(chunk)
    A.truthy(ok, value)
    return value
end

--Reads read bytes for this test scenario.
--@param relative_path string Repository-relative Lua source path to load.
--@return any bytes Bytes read from the selected fixture file.
local function read_bytes(relative_path)
    local handle, open_error = io.open(YACA_TEST_ROOT .. "/" .. relative_path, "rb")
    A.truthy(handle, open_error)
    local bytes = handle:read("a")
    local close_ok, close_error = handle:close()
    A.truthy(close_ok, close_error)
    return bytes
end

local lock = load_value("release/dependencies.lock")
local manifest = load_value("release/manifest.lua")
local patch_record = lock.components.luainstaller.downstream_patches[1]
local patch_bytes = read_bytes(patch_record.path)

return {
    name = "release/luainstaller-patch",
    cases = {
        {
            name = "resource overlay patch bytes and upstream bases are exactly pinned",
            --Verifies resource overlay patch bytes and upstream bases are exactly pinned.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify resource overlay patch bytes and upstream bases are exactly pinned.
            run = function()
                A.equal(#lock.components.luainstaller.downstream_patches, 1)
                A.equal(patch_record.applies_to_revision, lock.components.luainstaller.revision)
                A.equal(
                    SHA256.hex(patch_bytes),
                    "25f5816a67a3d65f4a7ef74c9c744493f626b1aa657fb4b6451cd0bfbeb57443"
                )
                A.deep_equal(
                    manifest.dependencies.luainstaller.downstream_patches,
                    lock.components.luainstaller.downstream_patches
                )
                A.deep_equal(patch_record.base_file_sha256, {
                    ["src/init.lua"] = "aea35743cbeee546fb7c5128f43a2326425020e5a780f4284f2865e8bd54df1c",
                    ["src/manifest.lua"] = "d86f856d0346a5f42a6611532f29f745f4dab10f892bc2cdf25148e134fc3065",
                    ["src/bundler.lua"] = "b8f7fe1a41499c83da8172b935ca9410a9dda3ea7b2a4e87c3ad315afeaf6a17",
                    ["src/onefile.lua"] = "67edbb961affcc496ad99a1bcdd342f07e0a2c488bed6de3442b8ac23e989a68",
                })
            end,
        },
        {
            name = "patch changes only the four audited packaging files",
            --Verifies patch changes only the four audited packaging files.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify patch changes only the four audited packaging files.
            run = function()
                local old_files, new_files = {}, {}
                for line in (patch_bytes .. "\n"):gmatch("([^\n]*)\n") do
                    local old_file = line:match("^%-%-%- a/(.+)$")
                    local new_file = line:match("^%+%+%+ b/(.+)$")
                    if old_file then old_files[#old_files + 1] = old_file end
                    if new_file then new_files[#new_files + 1] = new_file end
                end
                local expected = {
                    "src/bundler.lua", "src/init.lua", "src/manifest.lua", "src/onefile.lua",
                }
                A.deep_equal(old_files, expected)
                A.deep_equal(new_files, expected)
                A.falsy(patch_bytes:find("/home/", 1, true))
                A.falsy(patch_bytes:find("out/qualification", 1, true))
            end,
        },
        {
            name = "patch binds explicit hashes through manifest onedir and onefile",
            --Verifies patch binds explicit hashes through manifest onedir and onefile.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify patch binds explicit hashes through manifest onedir and onefile.
            run = function()
                for _, marker in ipairs({
                    "local RESOURCE_FIELDS = {",
                    "content_hash = true",
                    "local function validateBundleResources(",
                    '{ path = ".luai/native", subtree = false }',
                    "resource_destinations[path.targetKey(",
                    "resources = normalized.resources",
                    "resources = opts.resources",
                    "resources = distributionEntries(manifest.resources)",
                }) do
                    A.contains(patch_bytes, marker)
                end
                A.contains(patch_bytes, "or record.content_hash ~= expected_hash")
                A.contains(patch_bytes, "resources = opts.resources,")
            end,
        },
    },
}
