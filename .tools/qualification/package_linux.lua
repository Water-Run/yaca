--[[
Author: WaterRun
Date: 2026-09-23
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
