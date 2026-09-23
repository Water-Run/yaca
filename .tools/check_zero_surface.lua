--[[
Author: WaterRun
Date: 2026-09-23
File: check_zero_surface.lua
Description: Verifies an extracted clean-edition package contains only its
target executable and no shipped data, configuration, or Context artifacts.

Usage (qualification-time operator tool, not shipped):
bin/lua55 .tools/check_zero_surface.lua <repo-root> <package-root> <target-id>
]]

local M = {}

local IS_WINDOWS = package.config:sub(1, 1) == "\\"

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

-- Normalize path separators and redundant dot components for tree comparison.
--@param relative any Candidate path; nil is treated as empty.
--@return string path Slash-separated path with redundant separators removed.
local function normalize(relative)
    local path = tostring(relative or ""):gsub("\\", "/")
    path = path:gsub("/%./", "/"):gsub("//+", "/")
    if #path > 1 then path = path:gsub("/$", "") end
    return path
end

-- Extract one lowercased leaf for forbidden component and data-name checks.
--@param path string Normalized package-relative path.
--@return string stem Lowercased last path component.
local function lowercase_stem(path)
    local name = path:match("[^/]+$") or path
    return name:lower()
end

--- Verifies one package tree against the manifest surface.
--@param manifest table Loaded release manifest with the target and clean root policy.
--@param entries table Relative file paths enumerated in the extracted package.
--@param target_id string Exact target identifier from the manifest.
--@return boolean ok True only for exactly the clean executable file.
--@return table result Target summary on success or ordered findings on failure.
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
    local required = manifest.packaging.required_root_entries
        and manifest.packaging.required_root_entries[target.os]
    if type(required) ~= "table" or #required ~= 1
        or required[1] ~= target.executable
    then
        return false, { "manifest clean root must contain only target executable" }
    end
    for key in pairs(required) do
        if key ~= 1 then
            return false, { "manifest clean root must contain only target executable" }
        end
    end
    local expected = { [target.executable] = true }

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
        surface = "minimal-allowlist",
    }
end

-- Quote one package path for the host shell enumeration command.
--@param path string Filesystem path passed as one argument to find or dir.
--@return string quoted Host-shell word with embedded quote characters escaped.
local function shell_quote(path)
    if IS_WINDOWS then return '"' .. path:gsub('"', '""') .. '"' end
    return "'" .. path:gsub("'", "'\\''") .. "'"
end

-- Enumerate regular files under an extracted package root.
--@param root string Extracted package directory in host path syntax.
--@return table|nil entries Relative normalized file paths.
--@return string|nil err Enumeration start or command failure.
--@effect Starts a host file-enumeration command and reads its output.
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

-- Run the clean-edition surface audit from command-line arguments.
--@param argv table Repository root, package root, and target identifier.
--@return integer Exit code: zero on pass, one on findings, or 64 for usage.
--@effect Reads the manifest and package tree and writes the report to stdout/stderr.
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
