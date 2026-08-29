--[[
File: loader_path_test.lua
Date: 2026-08-30
Author: WaterRun
Description: Qualifies absolute native loading against ambient path injection.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

local function load_table(relative_path)
    local chunk, load_error = loadfile(YACA_TEST_ROOT .. "/" .. relative_path, "t", _ENV)
    A.truthy(chunk, load_error)
    return chunk()
end

local function read_all(relative_path)
    local file, open_error = io.open(YACA_TEST_ROOT .. "/" .. relative_path, "rb")
    A.truthy(file, open_error)
    local bytes = file:read("*a")
    file:close()
    return bytes
end

return {
    name = "qualification/loader-path",
    cases = {
        {
            name = "native module path is absolute allowlisted and independent of ambient cpath",
            run = function()
                local loader = load_table(".tools/check_loader.lua")
                local manifest = load_table("release/manifest.lua")
                local calls = {}
                local secure = assert(loader.new(manifest, YACA_TEST_ROOT, {
                    target_id = "linux-x86_64",
                    loadlib = function(path, symbol)
                        calls[#calls + 1] = { path = path, symbol = symbol }
                        return function() return { origin = path } end
                    end,
                }))
                local original_cpath = package.cpath
                package.cpath = "./yaca_native.so;/tmp/malicious/?.so"
                local native = secure:require("yaca_native")
                package.cpath = original_cpath
                A.equal(#calls, 1)
                A.equal(calls[1].path, YACA_TEST_ROOT .. "/native/yaca_native.so")
                A.equal(calls[1].symbol, "luaopen_yaca_native")
                A.equal(native.origin, calls[1].path)
            end,
        },
        {
            name = "validated native filename map is snapshotted against mutation",
            run = function()
                local loader = load_table(".tools/check_loader.lua")
                local manifest = load_table("release/manifest.lua")
                local secure = assert(loader.new(manifest, YACA_TEST_ROOT, {
                    target_id = "win32-x86",
                    loadlib = function(path)
                        return function() return path end
                    end,
                }))
                manifest.native_module_filenames["win32-x86"].yaca_native = "../evil.dll"
                A.equal(
                    secure:resolve_native("yaca_native", "win32-x86"),
                    YACA_TEST_ROOT .. "/native/yaca_native.dll"
                )
            end,
        },
        {
            name = "native source exposes one portable allowlisted Lua entry point",
            run = function()
                local source = read_all("native/yaca_native.c")
                A.contains(source, "luaopen_yaca_native")
                A.contains(source, "#if defined(_WIN32)")
                A.contains(source, "#else")
                A.contains(source, "yaca-native-v0.1.0")
                A.falsy(source:find("LoadLibraryA", 1, true))
                A.falsy(source:find("system(", 1, true))
                A.falsy(source:find("popen(", 1, true))
                local entry_count = 0
                for _ in source:gmatch("int%s+luaopen_yaca_native%s*%(") do
                    entry_count = entry_count + 1
                end
                A.equal(entry_count, 1)
            end,
        },
        {
            name = "native source owns a closed streaming SHA-256 handle",
            run = function()
                local source = read_all("native/yaca_native.c")
                for _, symbol in ipairs({
                    "executable_paths",
                    "stdio_facts",
                    "workspace_inspect",
                    "fs_make_directory",
                    "secure_random",
                    "current_process_id",
                    "sha256_start",
                    "sha256_update",
                    "sha256_finish",
                    "sha256_close",
                    "fs_inspect_direct",
                    "fs_walk_direct",
                    "fs_open_read_verified",
                    "fs_create_new_verified",
                    "fs_replace_verified",
                    "fs_rename_no_replace_verified",
                    "fs_delete_direct_verified",
                }) do
                    A.contains(source, '{ "' .. symbol .. '", l_' .. symbol .. " }")
                end
                A.contains(source, "YACA_SHA256_METATABLE")
                A.contains(source, "yaca_sha256_constants[64]")
                A.contains(source, "secure_zero(context, sizeof(*context))")
                A.contains(source, "SystemFunction036")
                A.contains(source, "GetCurrentProcessId")
                A.contains(source, 'open("/dev/urandom"')
                A.contains(source, "lua_pushlstring")
                A.falsy(source:find("openssl", 1, true))
                A.falsy(source:find("CryptAcquireContext", 1, true))
            end,
        },
    },
}
