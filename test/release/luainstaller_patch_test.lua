--[[
File: luainstaller_patch_test.lua
Date: 2026-08-30
Author: WaterRun
Description: Verifies the exact downstream resource-overlay patch as release input.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()
local SHA256 = assert(loadfile(
    YACA_TEST_ROOT .. "/test/support/sha256_reference.lua",
    "t",
    _ENV
))()

local function load_value(relative_path)
    local chunk, load_error = loadfile(YACA_TEST_ROOT .. "/" .. relative_path, "t", _ENV)
    A.truthy(chunk, load_error)
    local ok, value = pcall(chunk)
    A.truthy(ok, value)
    return value
end

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
            run = function()
                A.equal(#lock.components.luainstaller.downstream_patches, 1)
                A.equal(patch_record.applies_to_revision, lock.components.luainstaller.revision)
                A.equal(
                    SHA256.hex(patch_bytes),
                    "974cf25b51ab644c8af60a7f2524a5670b1fea38e35ad733267ac4775c5d9dff"
                )
                A.deep_equal(
                    manifest.dependencies.luainstaller.downstream_patches,
                    lock.components.luainstaller.downstream_patches
                )
                A.deep_equal(patch_record.base_file_sha256, {
                    ["src/init.lua"] = "55694d5e1c349362206e24a3ee8670977e5ea40fd51f0a457b221c95a84fce2d",
                    ["src/manifest.lua"] = "d86f856d0346a5f42a6611532f29f745f4dab10f892bc2cdf25148e134fc3065",
                    ["src/bundler.lua"] = "502da4a599ee0565d11d6c58455a1834d3333f31f8c247e6ee8260fb1dafcfae",
                    ["src/onefile.lua"] = "363e9a78d157821be7d6e222a4494c1f65998f5cc920c6f4cfcc0eee01dae610",
                })
            end,
        },
        {
            name = "patch changes only the four audited packaging files",
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
