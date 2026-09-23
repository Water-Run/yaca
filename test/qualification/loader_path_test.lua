--[[
Author: WaterRun
Date: 2026-09-23
File: loader_path_test.lua
Description: Qualifies absolute native loading against ambient path injection.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

--Loads a repository Lua module as a test support value.
--@param relative_path string Repository-relative Lua source path to load.
--@return any module Test support module export loaded from the repository.
local function load_table(relative_path)
    local chunk, load_error = loadfile(YACA_TEST_ROOT .. "/" .. relative_path, "t", _ENV)
    A.truthy(chunk, load_error)
    return chunk()
end

--Reads read all for this test scenario.
--@param relative_path string Repository-relative Lua source path to load.
--@return any bytes Complete bytes read from the selected fixture file.
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
            --Verifies native module path is absolute allowlisted and independent of ambient cpath.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify native module path is absolute allowlisted and independent of ambient cpath.
            run = function()
                local loader = load_table(".tools/check_loader.lua")
                local manifest = load_table("release/manifest.lua")
                local calls = {}
                local secure = assert(loader.new(manifest, YACA_TEST_ROOT, {
                    target_id = "linux-x86_64",
                    --Supplies the loadlib behavior used by the 'native module path is absolute allowlisted and independent of ambient cpath' case.
                    --@param path string File or Context path exercised by the case.
                    --@param symbol any The symbol supplied to the fake service for this scenario.
                    --@return function callback Nested callback supplied by this scenario.
                    loadlib = function(path, symbol)
                        calls[#calls + 1] = { path = path, symbol = symbol }
                        --Supplies an assertion callback for the native module path is absolute allowlisted and independent of ambient cpath scenario.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return table record Fixture record emitted by the scenario callback.
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
            --Verifies validated native filename map is snapshotted against mutation.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify validated native filename map is snapshotted against mutation.
            run = function()
                local loader = load_table(".tools/check_loader.lua")
                local manifest = load_table("release/manifest.lua")
                local secure = assert(loader.new(manifest, YACA_TEST_ROOT, {
                    target_id = "win32-x86",
                    --Supplies the loadlib behavior used by the 'validated native filename map is snapshotted against mutation' case.
                    --@param path string File or Context path exercised by the case.
                    --@return function callback Nested callback supplied by this scenario.
                    loadlib = function(path)
                        --Supplies an assertion callback for the validated native filename map is snapshotted against mutation scenario.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return any value Callback value consumed by the enclosing scenario assertion.
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
            --Verifies validated native filename map is snapshotted against mutation.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify validated native filename map is snapshotted against mutation.
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
            --Verifies native source exposes one portable allowlisted Lua entry point.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify native source exposes one portable allowlisted Lua entry point.
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
        {
            name = "native component carrier bypasses both platform command shells",
            --Verifies native component carrier bypasses both platform command shells.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify native component carrier bypasses both platform command shells.
            run = function()
                local source = read_all("native/yaca_native.c")
                local supervisor = read_all("native/yaca_supervisor.h")
                A.contains(source, "request_component_stdin")
                A.contains(source, 'memcmp(mode, "argv", 4U)')
                A.contains(source, "build_wide_arguments")
                A.contains(source, "CreateProcessW(\n        application_name,")
                A.contains(
                    supervisor,
                    "execve(executable, arguments, environment)"
                )
                A.contains(source, "start_process_input(stdin_write, stdin_bytes, stdin_length)")
                A.contains(source, "yaca_supervisor_run(argv_mode ? stdin_pipe[0] : null_input")
                A.contains(supervisor, "PR_SET_CHILD_SUBREAPER")
                A.contains(source, "command_length >= 32767U")
            end,
        },
        {
            name = "Windows console paths retain the XP API floor and host line editor",
            --Verifies windows console paths retain the XP API floor and host line editor.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify windows console paths retain the XP API floor and host line editor.
            run = function()
                local source = read_all("native/yaca_native.c")
                A.contains(source, "#define _WIN32_WINNT 0x0501")
                A.contains(source, "ReadConsoleW")
                A.contains(source, "ReadConsoleInputW")
                A.contains(source, "CreateThread")
                A.contains(source, "WriteConsoleInputW")
                A.contains(source, "WaitForSingleObject")
                A.contains(source, "ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT")
                A.contains(source, "terminal->cooked_mode")
                A.falsy(source:find("CancelSynchronousIo", 1, true))
                A.falsy(source:find("GetConsoleModeEx", 1, true))
                A.falsy(source:find("TerminateThread", 1, true))
            end,
        },
    },
}
