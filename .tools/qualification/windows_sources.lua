--[[
Author: WaterRun
Date: 2026-09-23
File: windows_sources.lua
Description: Emits pinned luainstaller C sources for an explicitly unqualified Windows build.
]]

local builder_root, yaca_root, mode, output, stage = table.unpack(arg)
assert(builder_root and yaca_root and mode and output, "missing source-generation arguments")
--Supplies an assertion callback for the windows sources scenario.
--@param name string Module, Model, or resource name selected by the case.
--@return any|nil value Value emitted by the scenario callback for the current assertion.
table.insert(package.searchers, 1, function(name)
    local relative = name:match("^luainstaller%.(.+)$")
    if not relative then return nil end
    return assert(loadfile(builder_root .. "/src/" .. relative:gsub("%.", "/") .. ".lua"))
end)
local launcher = require("luainstaller.launcher")
local hash = require("luainstaller.hash")

--Computes read in windows sources.
--@param path string File or Context path exercised by the case.
--@return any observed read value observed by the scenario assertion.
local function read(path)
    local file = assert(io.open(path, "rb"))
    local bytes = assert(file:read("a"))
    assert(file:close())
    return bytes
end

--Computes write in windows sources.
--@param path string File or Context path exercised by the case.
--@param bytes string Byte chunk supplied to the fake I/O port.
--@return nil No value; assertions or fixture effects define this case.
local function write(path, bytes)
    local file = assert(io.open(path, "wb"))
    assert(file:write(bytes))
    assert(file:close())
end

if mode == "launcher" then
    local manifest = assert(loadfile(yaca_root .. "/release/manifest.lua", "t", {}))()
    local scripts, hashes = {}, {}
    for _, name in ipairs(manifest.lua_modules) do
        local path = yaca_root .. "/src/" .. name .. ".lua"
        hashes[path] = hash.sha256(read(path))
        if name ~= "main" then scripts[#scripts + 1] = path end
    end
    local generated = launcher.generateSource({
        entry = yaca_root .. "/src/main.lua",
        dependencies = { scripts = scripts, libraries = {} },
        source_hashes = hashes,
        source_hash_algorithm = "sha256",
        native_dir = ".luai/native",
        lua_version = { major = 5, minor = 5, num = 505, abi = "lua5.5" },
    })
    assert(stage, "missing locked Lua source directory")
    local entry = assert(loadfile(yaca_root .. "/release/launcher.lua"))()
    write(output, entry.wrap(generated, read(stage .. "/lua.c"),
        read(yaca_root .. "/native/yaca_entry.c"), {
            prefix = read(stage .. "/lprefix.h"), limits = read(stage .. "/llimits.h"),
            windows = read(yaca_root .. "/native/yaca_lua_windows.h"),
        }))
elseif mode == "extractor" then
    assert(stage, "missing explicit onedir stage")
    -- The locked builder only compiles on its native host. Expose its existing
    -- source emitters in this build process; do not bypass or claim its native
    -- compile/run qualification. The UTF-8 adapters below are yaca-owned.
    local source = read(builder_root .. "/src/onefile.lua")
    local extended, count = source:gsub("\nreturn M%s*$", [[
M.cross_sources = function(root)
    local files, identity = collectFiles(root, "windows")
    assert(files, identity and identity.error and identity.error.message)
    return generateExtractorSource("inner.exe"), generatePayloadInclude(files, identity)
end
return M
]])
    assert(count == 1, "pinned onefile module export changed")
    local onefile = assert(load(extended, "@luainstaller/onefile.lua", "t"))()
    local extractor, payload = onefile.cross_sources(stage)
    -- Public cache bytes remain compared and pinned on FAT, whose filesystem
    -- cannot provide a private DACL. Bind that narrow exception to the actual
    -- handle's volume; retain the locked builder's hardening everywhere else.
    extractor, count = extractor:gsub(
        "static int luai_harden_private_handle%(HANDLE handle%) {",
        "static int luai_harden_private_handle(HANDLE handle, const char *path) {\n"
            .. "    if (yaca_onefile_public_fat_volume(handle, path)) return 0;")
    assert(count == 1, "pinned cache hardening definition changed")
    extractor, count = extractor:gsub("luai_harden_private_handle%(handle%)",
        "luai_harden_private_handle(handle, path)")
    assert(count == 2, "pinned directory/file hardening calls changed")
    extractor, count = extractor:gsub("luai_harden_private_handle%(file%)",
        "luai_harden_private_handle(file, temporary)")
    assert(count == 1, "pinned temporary hardening call changed")
    local adapters = read(yaca_root .. "/native/yaca_onefile_windows.h")
    local marker = "#ifdef _WIN32\nstatic int luai_mkdir_one"
    local first = assert(extractor:find(marker, 1, true))
    extractor = extractor:sub(1, first - 1) .. "#ifdef _WIN32\n" .. adapters
        .. "\n#endif\n" .. extractor:sub(first)
        .. "\n" .. read(yaca_root .. "/native/yaca_onefile_entry.c")
    write(output .. "/extractor.c", extractor)
    write(output .. "/payload.inc", payload)
else
    error("unknown source-generation mode")
end
