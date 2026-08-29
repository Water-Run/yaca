--[[
File: rp001_resource_overlay.lua
Date: 2026-08-30
Author: WaterRun
Description: Exercises the pinned luainstaller resource-overlay patch on a modern host.
]]

local harness = dofile("test/support/harness.lua")
harness.install_loader()

local bundler = require("luainstaller.bundler")
local fs = require("luainstaller.fs")
local hash = require("luainstaller.hash")
local luainstaller = require("luainstaller")
local manifest = require("luainstaller.manifest")
local path = require("luainstaller.path")
local process = require("luainstaller.process")

local lua_prefix = assert(arg[1], "exact Lua prefix is required")
local root = assert(fs.makePrivateDirectory("resource-overlay"))
local entry = path.join(root, "main.lua")
local curl_source = path.join(root, "curl-resource")
local ca_source = path.join(root, "cacert-resource.pem")
local curl_bytes = "locked curl bytes\n"
local ca_bytes = "locked CA bytes\n"
assert(fs.writeFile(curl_source, curl_bytes))
assert(fs.writeFile(ca_source, ca_bytes))
assert(fs.writeFile(entry, [=[
local native_template = assert(package.cpath:match("^([^;]+)"))
local root = assert(native_template:match("^(.*)/%.luai/native/"))
local function read(relative)
    local handle = assert(io.open(root .. "/" .. relative, "rb"))
    local bytes = assert(handle:read("a"))
    assert(handle:close())
    return bytes
end
assert(read(".luai/components/curl") == "locked curl bytes\n")
assert(read(".luai/components/cacert.pem") == "locked CA bytes\n")
print("resource-overlay-runtime=PASS")
]=]))

local resources = {
    {
        source_path = curl_source,
        destination_path = ".luai/components/curl",
        content_hash = hash.sha256(curl_bytes),
    },
    {
        source_path = ca_source,
        destination_path = ".luai/components/cacert.pem",
        content_hash = hash.sha256(ca_bytes),
    },
}

local snapshot = manifest.build({
    entry = entry,
    mode = "onedir",
    out = path.join(root, "manifest-only"),
    dependencies = { scripts = {}, libraries = {} },
    resources = resources,
    target_os = "linux",
    lua_prefix = lua_prefix,
})
assert(snapshot.ok, snapshot.error and snapshot.error.message)
assert(#snapshot.manifest.resources == 2)
assert(snapshot.manifest.resources[1].content_hash == resources[1].content_hash)
local projected = manifest.distribution(snapshot.manifest)
assert(#projected.resources == 2)
assert(projected.resources[1].source_path == nil)

local onedir = luainstaller.bundle({
    entry = entry,
    mode = "onedir",
    out = path.join(root, "onedir"),
    resources = resources,
    target_os = "linux",
    lua_prefix = lua_prefix,
})
assert(onedir.ok, onedir.error and onedir.error.message)
assert(assert(fs.readRegularFile(path.join(
    onedir.out,
    ".luai/components/curl"
))) == curl_bytes)
assert(assert(fs.readRegularFile(path.join(
    onedir.out,
    ".luai/components/cacert.pem"
))) == ca_bytes)
local onedir_ok, onedir_output = process.outputCommand(onedir.executable, {})
assert(onedir_ok, onedir_output)
assert(onedir_output:find("resource%-overlay%-runtime=PASS"))

local onefile = luainstaller.bundle({
    entry = entry,
    mode = "onefile",
    out = path.join(root, "yaca-onefile"),
    resources = resources,
    target_os = "linux",
    lua_prefix = lua_prefix,
})
assert(onefile.ok, onefile.error and onefile.error.message)
local onefile_ok, onefile_output = process.outputCommand(onefile.executable, {})
assert(onefile_ok, onefile_output)
assert(onefile_output:find("resource%-overlay%-runtime=PASS"))

local function rejected(output, expected_type)
    assert(not output.ok)
    assert(output.error.type == expected_type, output.error.type)
end

rejected(luainstaller.bundle({
    entry = entry,
    mode = "onedir",
    out = path.join(root, "wrong-hash"),
    resources = { {
        source_path = curl_source,
        destination_path = ".luai/components/curl",
        content_hash = string.rep("0", 64),
    } },
    target_os = "linux",
    lua_prefix = lua_prefix,
}), "SourceChangedError")

rejected(luainstaller.bundle({
    entry = entry,
    mode = "onedir",
    out = path.join(root, "reserved"),
    resources = { {
        source_path = curl_source,
        destination_path = ".luai/native/injected.so",
        content_hash = hash.sha256(curl_bytes),
    } },
    target_os = "linux",
    lua_prefix = lua_prefix,
}), "DuplicateModuleError")

rejected(luainstaller.bundle({
    entry = entry,
    mode = "onedir",
    out = path.join(root, "duplicate"),
    resources = {
        resources[1],
        {
            source_path = ca_source,
            destination_path = ".luai/components/curl/child",
            content_hash = hash.sha256(ca_bytes),
        },
    },
    target_os = "linux",
    lua_prefix = lua_prefix,
}), "DuplicateModuleError")

rejected(luainstaller.bundle({
    entry = entry,
    mode = "onedir",
    out = path.join(root, "unknown"),
    resources = { {
        source_path = curl_source,
        destination_path = ".luai/components/curl",
        content_hash = hash.sha256(curl_bytes),
        glob = "*",
    } },
    target_os = "linux",
    lua_prefix = lua_prefix,
}), "InvalidOptionsError")

local changed_manifest = manifest.build({
    entry = entry,
    mode = "onedir",
    out = path.join(root, "changed"),
    dependencies = { scripts = {}, libraries = {} },
    resources = resources,
    target_os = "linux",
    lua_prefix = lua_prefix,
})
assert(changed_manifest.ok)
assert(fs.writeFile(curl_source, "changed after snapshot\n"))
rejected(bundler.bundleOnedir({
    entry = entry,
    out = path.join(root, "changed"),
    dependencies = { scripts = {}, libraries = {} },
    trace = {},
    manifest = changed_manifest.manifest,
    resources = resources,
    target_os = "linux",
    lua_prefix = lua_prefix,
}), "SourceChangedError")

assert(fs.removeTree(root))
print("resource-overlay-proof=PASS")
