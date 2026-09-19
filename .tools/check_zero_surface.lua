--[[
File: check_zero_surface.lua
Date: 2026-09-19
Author: WaterRun
Description: Verifies an extracted yaca package tree keeps the minimal
release surface: manifest root entries only, the versioned docs allowlist,
no shipped data/config/Context files and no forbidden components.

Usage (qualification-time operator tool, not shipped):
  bin/lua55 .tools/check_zero_surface.lua <repo-root> <package-root> <target-id>
]]

local M = {}

local IS_WINDOWS = package.config:sub(1, 1) == "\\"

local DOC_FILES = {
    ["docs/WINDOWS-QUICKSTART.md"] = true,
    ["docs/COMPONENTS.txt"] = true,
    ["docs/build-summary.json"] = true,
    ["docs/SBOM.spdx.json"] = true,
    ["docs/licenses/Lua-MIT.html"] = true,
    ["docs/licenses/Expat-MIT.txt"] = true,
    ["docs/licenses/LuaExpat-MIT.html"] = true,
    ["docs/licenses/luainstaller-LGPL.txt"] = true,
    ["docs/licenses/curl.txt"] = true,
    ["docs/licenses/Mbed-TLS.txt"] = true,
    ["docs/licenses/Mozilla-CA.pem"] = true,
}

-- Name fragments of components that must never ship. Mirrors the manifest's
-- forbidden_shipped_components plus concrete historical bin/ residents.
local FORBIDDEN_NAME_FRAGMENTS = {
    "sqlite3", "7za", "busybox", "iconv", "jq", "libcrypto", "libssl",
    "web-server", "browser-assets", "media-codec", "speech-runtime",
    "remote-controller", "plugin-loader", "mcp-client", "telemetry-client",
    "update-client",
}

-- Files that belong to a configured, used installation and therefore must
-- never appear inside a shipped archive.
local FORBIDDEN_DATA_NAMES = {
    ["config.ini"] = "shipped configuration file",
    ["__yaca__"] = "shipped data directory",
}

local function normalize(relative)
    local path = tostring(relative or ""):gsub("\\", "/")
    path = path:gsub("/%./", "/"):gsub("//+", "/")
    if #path > 1 then path = path:gsub("/$", "") end
    return path
end

local function lowercase_stem(path)
    local name = path:match("[^/]+$") or path
    return name:lower()
end

--- Verifies one package tree against the manifest surface.
-- manifest: loaded release/manifest.lua table; entries: array of relative
-- paths found in the extracted package root; target_id: manifest target id.
-- Returns true, summary_table or false, findings_array.
function M.verify(manifest, entries, target_id)
    if type(manifest) ~= "table" or type(manifest.packaging) ~= "table" then
        return false, { "manifest is missing its packaging section" }
    end
    local target
    for _, candidate in ipairs(manifest.targets or {}) do
        if candidate.id == target_id then target = candidate end
    end
    if not target then
        return false, { "unknown target id: " .. tostring(target_id) }
    end
    local required = assert(
        manifest.packaging.required_root_entries[target.os],
        "manifest has no root entries for this target os")

    local expected = {}
    local function expect(path)
        expected[normalize(path)] = true
    end
    for _, entry in ipairs(required) do
        if entry:sub(-1) == "/" then
            -- A required directory contributes its versioned file set.
            if entry == "docs/" then
                for doc in pairs(DOC_FILES) do expect(doc) end
            else
                return false, {
                    "manifest requires unmapped directory entry: " .. entry,
                }
            end
        else
            expect(entry)
        end
    end

    local seen = {}
    local findings = {}
    for _, raw in ipairs(entries) do
        local path = normalize(raw)
        if path == "" then
            -- tolerate a bare root marker
        elseif seen[path] then
            findings[#findings + 1] = "duplicate entry: " .. path
        else
            seen[path] = true
            if not expected[path] then
                findings[#findings + 1] = "unexpected file: " .. path
            end
        end
        local stem = lowercase_stem(path)
        for _, fragment in ipairs(FORBIDDEN_NAME_FRAGMENTS) do
            if stem:find(fragment, 1, true) then
                findings[#findings + 1] =
                    "forbidden component name in package: " .. path
            end
        end
        local first = path:match("^[^/]+")
        local forbidden_reason = FORBIDDEN_DATA_NAMES[stem]
            or FORBIDDEN_DATA_NAMES[first or ""]
        if forbidden_reason then
            findings[#findings + 1] = forbidden_reason .. ": " .. path
        end
        if stem:match("%.xml$") or stem:match("%.yaca%-lock$") then
            findings[#findings + 1] = "shipped Context artifact: " .. path
        end
    end
    for path in pairs(expected) do
        if not seen[path] then
            findings[#findings + 1] = "missing expected file: " .. path
        end
    end
    if #findings > 0 then
        return false, findings
    end
    return true, {
        target = target_id,
        files = #entries,
        executable = target.executable,
        installer = target.installer,
        surface = "minimal-allowlist",
    }
end

local function shell_quote(path)
    if IS_WINDOWS then return '"' .. path:gsub('"', '""') .. '"' end
    return "'" .. path:gsub("'", "'\\''") .. "'"
end

local function list_package_files(root)
    local command
    if IS_WINDOWS then
        local windows_root = root:gsub("/", "\\")
        command = "dir /b /s /a:-d " .. shell_quote(windows_root)
    else
        command = "find " .. shell_quote(root) .. " -type f"
    end
    local pipe = io.popen(command, "r")
    if not pipe then return nil, "cannot start package enumeration" end
    local prefix = normalize(root) .. "/"
    local entries = {}
    for line in pipe:lines() do
        local path = normalize(line)
        if path:sub(1, #prefix) == prefix then
            path = path:sub(#prefix + 1)
        elseif path:sub(1, #root) == root then
            path = path:sub(#root + 1):gsub("^[/\\]+", "")
        end
        if path ~= "" then entries[#entries + 1] = path end
    end
    local ok, why, code = pipe:close()
    if ok == nil and code ~= 0 then
        return nil, "package enumeration failed: " .. tostring(why)
    end
    return entries
end

local function main(argv)
    local repo_root, package_root, target_id = table.unpack(argv)
    if not (repo_root and package_root and target_id) then
        io.stderr:write(
            "usage: check_zero_surface.lua <repo-root> <package-root> <target-id>\n")
        return 64
    end
    local manifest_chunk, load_error =
        loadfile(normalize(repo_root) .. "/release/manifest.lua", "t", _ENV)
    if not manifest_chunk then
        io.stderr:write("zero-surface: cannot load manifest: "
            .. tostring(load_error) .. "\n")
        return 1
    end
    local manifest = assert(manifest_chunk())
    local entries, list_error = list_package_files(normalize(package_root))
    if not entries then
        io.stderr:write("zero-surface: " .. list_error .. "\n")
        return 1
    end
    local ok, result = M.verify(manifest, entries, target_id)
    if not ok then
        for _, finding in ipairs(result) do
            io.stderr:write("zero-surface FINDING: " .. finding .. "\n")
        end
        io.stderr:write("zero-surface=FAIL target=" .. target_id .. "\n")
        return 1
    end
    io.write(("zero-surface=PASS target=%s files=%d surface=%s\n")
        :format(result.target, result.files, result.surface))
    return 0
end

if arg and arg[0] and arg[0]:match("check_zero_surface%.lua$") then
    os.exit(main(arg))
end

return M
