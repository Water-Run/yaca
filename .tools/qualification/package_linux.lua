--[[
Author: WaterRun
Date: 2026-10-09
File: package_linux.lua
Description: Builds the Linux onedir prerequisite and onefile candidate from exact inputs.
]]

--Computes fail in package linux.
--@param message string|table Message delivered through the fake port.
--@return nil No value; assertions or fixture effects define this case.
local function fail(message)
    io.stderr:write("package-linux: ", tostring(message), "\n")
    os.exit(1, true)
end

if #arg ~= 8 then
    fail(table.concat({
        "expected: <luainstaller-root> <yaca-root> <lua-prefix>",
        " <onedir-output> <onefile-output> <curl> <ca-bundle> <lua-source>",
    }))
end

local luainstaller_root = arg[1]
local yaca_root = arg[2]
local lua_prefix = arg[3]
local onedir_output = arg[4]
local onefile_output = arg[5]
local curl_path = arg[6]
local ca_bundle_path = arg[7]
local lua_source = arg[8]

local harness = assert(dofile(luainstaller_root .. "/test/support/harness.lua"))
harness.install_loader()

local hash = require("luainstaller.hash")
local luainstaller = require("luainstaller")
local toolchain = require("luainstaller.toolchain")
local compile_launcher = toolchain.compile

--Reads the complete fixture file for package linux.
--@param path string File or Context path exercised by the case.
--@return any bytes Bytes read from the selected fixture file.
local function read_bytes(path)
    local handle, open_error = io.open(path, "rb")
    if not handle then fail(open_error) end
    local bytes = handle:read("a")
    local closed, close_error = handle:close()
    if not closed then fail(close_error) end
    return bytes
end

-- Copy the official public headers onto the directory the pinned compiler already searches.
-- luainstaller 1.5.0 writes only lua_min.h there. The wrapped launcher also
-- compiles lua.c, which includes the real headers.
--@param directory string Absolute include directory named by the compiler options.
--@return nil No return value.
--@effect Creates or replaces lua.h, luaconf.h, lauxlib.h, and lualib.h in directory.
--@error Exits the process when a header cannot be read or written.
local function install_public_lua_headers(directory)
    local names = { "lua.h", "luaconf.h", "lauxlib.h", "lualib.h" }
    for index = 1, #names do
        local name = names[index]
        local bytes = read_bytes(lua_source .. "/" .. name)
        local handle, open_error = io.open(directory .. "/" .. name, "wb")
        if not handle then fail(open_error) end
        local written, write_error = handle:write(bytes)
        if not written then fail(write_error) end
        local closed, close_error = handle:close()
        if not closed then fail(close_error) end
    end
end

-- Place the interpreter headers before the pinned launcher compilation runs.
-- The compiler command itself stays the one luainstaller 1.5.0 builds.
--@param config table Toolchain selected by luainstaller for this launch.
--@param source_path string Generated C translation unit.
--@param output_path string Executable path requested by the bundler.
--@param opts table|nil Compile options. lua_header_dir or work_dir is the include directory.
--@return boolean ok True when the pinned compiler succeeds.
--@return string|nil output Compiler output, or the reason the header directory is absent.
--@return string|nil descriptor Command text returned by the pinned compiler.
toolchain.compile = function(config, source_path, output_path, opts)
    local directory = type(opts) == "table" and (opts.lua_header_dir or opts.work_dir) or nil
    if type(directory) ~= "string" or directory == "" then
        return false, "the launcher compile did not name a header directory", nil
    end
    install_public_lua_headers(directory)
    return compile_launcher(config, source_path, output_path, opts)
end

local release_chunk, release_error = loadfile(
    yaca_root .. "/release/manifest.lua",
    "t",
    {}
)
if not release_chunk then fail(release_error) end
local release_manifest = release_chunk()

-- Adapt the pinned generator locally; its compiler and onefile payload paths
-- remain unchanged. lua.c comes from the same verified tree as liblua.a.
local launcher = require("luainstaller.launcher")
local generate_source = launcher.generateSource
local entry = assert(loadfile(yaca_root .. "/release/launcher.lua"))()
local interpreter_source = read_bytes(lua_source .. "/lua.c")
local entry_source = read_bytes(yaca_root .. "/native/yaca_entry.c")
--Exercises generateSource in the package linux fixture.
--@param options table|nil Options configuring the exercised component.
--@return any value Value emitted by the scenario callback for the current assertion.
launcher.generateSource = function(options)
    return entry.wrap(generate_source(options), interpreter_source, entry_source, {
        prefix = read_bytes(lua_source .. "/lprefix.h"),
        limits = read_bytes(lua_source .. "/llimits.h"),
    })
end

local includes = {}
for _, module_name in ipairs(release_manifest.lua_modules) do
    if module_name ~= "main" then
        includes[#includes + 1] = yaca_root .. "/src/" .. module_name .. ".lua"
    end
end

local native_name = release_manifest.native_module_filenames[
    "linux-x86_64"
].yaca_native
local native_path = yaca_root .. "/build/candidates/linux-x86_64/" .. native_name
local lxp_path = yaca_root .. "/build/candidates/linux-x86_64/lxp.so"

--Computes resource in package linux.
--@param source_path string Source file path read by the fixture.
--@param destination_path any The destination path supplied to this scenario's fixture operation.
--@return table observed Structured fixture record with source_path, destination_path, content_hash.
local function resource(source_path, destination_path)
    return {
        source_path = source_path,
        destination_path = destination_path,
        content_hash = hash.sha256(read_bytes(source_path)),
    }
end

local resources = {
    resource(native_path, ".luai/native/yaca_native.so"),
    resource(lxp_path, ".luai/native/lxp.so"),
    resource(curl_path, ".luai/components/curl"),
    resource(ca_bundle_path, ".luai/components/cacert.pem"),
}

--Computes build in package linux.
--@param mode string Operating mode selected by the scenario.
--@param output any The output supplied to this scenario's fixture operation.
--@return any observed build value observed by the scenario assertion.
local function build(mode, output)
    local result = luainstaller.bundle({
        entry = yaca_root .. "/src/main.lua",
        mode = mode,
        out = output,
        discovery_mode = "manual",
        depscan = false,
        include = includes,
        max_deps = 64,
        resources = resources,
        target_os = "linux",
        lua = lua_prefix .. "/bin/lua",
        lua_prefix = lua_prefix,
    })
    if not result.ok then
        local error_value = result.error or {}
        io.stderr:write(
            "package-linux-detail: command=",
            tostring(error_value.command or ""),
            "\npackage-linux-detail: output=",
            tostring(error_value.output or ""),
            "\n"
        )
        fail(tostring(error_value.type) .. ": " .. tostring(error_value.message))
    end
    return result
end

local onedir = build("onedir", onedir_output)
local onefile = build("onefile", onefile_output)

io.write("luainstaller=", luainstaller.VERSION, "\n")
io.write("lua-modules=", tostring(#release_manifest.lua_modules), "\n")
io.write("resources=", tostring(#resources), "\n")
io.write("onedir=", onedir.out, "\n")
io.write("onedir-executable=", onedir.executable, "\n")
io.write("onefile=", onefile.executable, "\n")
io.write("package-linux=PASS\n")
