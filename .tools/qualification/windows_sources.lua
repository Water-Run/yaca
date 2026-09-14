--[[
File: windows_sources.lua
Date: 2026-09-14
Author: WaterRun
Description: Emits pinned luainstaller C sources for an explicitly unqualified Windows build.
]]

local builder_root, yaca_root, mode, output, stage = table.unpack(arg)
assert(builder_root and yaca_root and mode and output, "missing source-generation arguments")
table.insert(package.searchers, 1, function(name)
    local relative = name:match("^luainstaller%.(.+)$")
    if not relative then return nil end
    return assert(loadfile(builder_root .. "/src/" .. relative:gsub("%.", "/") .. ".lua"))
end)
local launcher = require("luainstaller.launcher")
local hash = require("luainstaller.hash")

local function read(path)
    local file = assert(io.open(path, "rb"))
    local bytes = assert(file:read("a"))
    assert(file:close())
    return bytes
end

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
    write(output, launcher.generateSource({
        entry = yaca_root .. "/src/main.lua",
        dependencies = { scripts = scripts, libraries = {} },
        source_hashes = hashes,
        source_hash_algorithm = "sha256",
        native_dir = ".luai/native",
        lua_version = { major = 5, minor = 5, num = 505, abi = "lua5.5" },
    }))
elseif mode == "extractor" then
    assert(stage, "missing explicit onedir stage")
    -- The locked builder only compiles on its native host. Expose its existing
    -- source emitters in this build process; do not bypass or claim its native
    -- compile/run qualification. Runtime extractor code is unchanged.
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
    write(output .. "/extractor.c", extractor)
    write(output .. "/payload.inc", payload)
else
    error("unknown source-generation mode")
end
