--[[
File: package_linux.lua
Date: 2026-08-30
Author: WaterRun
Description: Builds the Linux onedir prerequisite and onefile candidate from exact inputs.
]]

local function fail(message)
    io.stderr:write("package-linux: ", tostring(message), "\n")
    os.exit(1, true)
end

if #arg ~= 7 then
    fail(table.concat({
        "expected: <luainstaller-root> <yaca-root> <lua-prefix>",
        " <onedir-output> <onefile-output> <curl> <ca-bundle>",
    }))
end

local luainstaller_root = arg[1]
local yaca_root = arg[2]
local lua_prefix = arg[3]
local onedir_output = arg[4]
local onefile_output = arg[5]
local curl_path = arg[6]
local ca_bundle_path = arg[7]

local harness = assert(dofile(luainstaller_root .. "/test/support/harness.lua"))
harness.install_loader()

local hash = require("luainstaller.hash")
local luainstaller = require("luainstaller")

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
