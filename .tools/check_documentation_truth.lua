--[[
File: check_documentation_truth.lua
Date: 2026-09-19
Author: WaterRun
Description: C34 guard: public statements must only describe released
capability. While Release Gate R is closed every public document must carry
the pending-qualification markers and none may claim release authorization
or a fully qualified target.

Usage: bin/lua55 .tools/check_documentation_truth.lua <repo-root>
]]

local M = {}

local PUBLIC_DOCUMENTS = {
    "README.md",
    "README-zh.md",
    "release/WINDOWS-QUICKSTART.md",
    "release/LINUX-QUICKSTART.md",
}

-- Phrases that would overstate the current state. Matched literally.
local FORBIDDEN_PHRASES = {
    "Release Gate R remains passed",
    "release is authorized",
    "release_authorized = true",
    "is qualified for release",
    "has passed release qualification",
    "all targets qualified",
    "all three targets qualified",
    "发行资格已通过",
    "正式发行已授权",
    "全部目标已通过资格",
    "三个目标均已通过资格",
}

--- Extracts the truth signals the checker keys on.
-- readiness: contracts/readiness.lua value; manifest: release/manifest.lua.
function M.signals(readiness, manifest)
    local signals = {}
    signals.gate_r_closed = readiness.gates.R.status ~= "passed"
    signals.release_not_authorized = readiness.source_start
        .release_is_not_authorized == true
    signals.phase = readiness.source_start.implementation_phase
    local pending_targets = {}
    for _, target in ipairs(manifest.targets or {}) do
        if target.qualification ~= "passed" then
            pending_targets[#pending_targets + 1] = target.id
        end
    end
    signals.pending_targets = pending_targets
    signals.all_targets_passed = #pending_targets == 0
    return signals
end

--- Decides whether one public document's text is truthful for the signals.
-- Returns an array of findings (empty when truthful).
function M.document_findings(relative_path, text, signals)
    local findings = {}
    for _, phrase in ipairs(FORBIDDEN_PHRASES) do
        if text:find(phrase, 1, true) then
            findings[#findings + 1] = relative_path
                .. " claims forbidden phrase: " .. phrase
        end
    end
    if signals.gate_r_closed then
        if text:find("Release Gate R is passed", 1, true)
            or text:find("Release Gate R remains passed", 1, true) then
            findings[#findings + 1] = relative_path
                .. " claims a passed release gate while it is closed"
        end
    end
    if signals.gate_r_closed and (relative_path == "README.md") then
        if not text:find("target qualification pending", 1, true) then
            findings[#findings + 1] = relative_path
                .. " is missing the pending-qualification status marker"
        end
    end
    if signals.gate_r_closed and (relative_path == "README-zh.md") then
        if not text:find("目标资格验证待完成", 1, true) then
            findings[#findings + 1] = relative_path
                .. " is missing the pending-qualification status marker"
        end
    end
    if signals.gate_r_closed and relative_path:find("QUICKSTART", 1, true) then
        -- Both quickstarts are written in Chinese; the pending word is 待.
        local pending_word = "待"
        if not (text:find(pending_word, 1, true)) then
            findings[#findings + 1] = relative_path
                .. " does not state its target qualification as pending"
        end
    end
    return findings
end

function M.run(repo_root)
    local checks, failures = 0, {}
    local function load(relative)
        local chunk, load_error = loadfile(
            repo_root .. "/" .. relative, "t", _ENV)
        if not chunk then
            failures[#failures + 1] = "cannot load " .. relative .. ": "
                .. tostring(load_error)
            return nil
        end
        local ok, value = pcall(chunk)
        if not ok then
            failures[#failures + 1] = "cannot execute " .. relative
            return nil
        end
        return value
    end
    local readiness = load(".develope-docs/contracts/readiness.lua")
    local manifest = load("release/manifest.lua")
    if readiness and manifest then
        checks = checks + 1
        local signals = M.signals(readiness, manifest)
        if signals.all_targets_passed and signals.gate_r_closed then
            failures[#failures + 1] =
                "manifest marks every target passed while Gate R is closed"
        end
        for _, relative in ipairs(PUBLIC_DOCUMENTS) do
            local file = io.open(repo_root .. "/" .. relative, "r")
            if not file then
                failures[#failures + 1] = "public document missing: " .. relative
                checks = checks + 1
            else
                local text = file:read("a") or ""
                file:close()
                checks = checks + 1
                for _, finding in ipairs(
                    M.document_findings(relative, text, signals)) do
                    failures[#failures + 1] = finding
                end
            end
        end
    end
    return checks, failures
end

----------------------------------------------------------------------------

local function main(argv)
    local repo_root = argv[1]
    if not repo_root then
        io.stderr:write("usage: check_documentation_truth.lua <repo-root>\n")
        return 64
    end
    local checks, failures = M.run((repo_root:gsub("[/\\]+$", "")))
    for _, failure in ipairs(failures) do
        io.stderr:write("documentation-truth FINDING: " .. failure .. "\n")
    end
    if #failures > 0 or checks == 0 then
        io.stderr:write("documentation-truth validation FAIL: "
            .. #failures .. " findings\n")
        return 1
    end
    io.write("documentation-truth validation PASS: " .. checks
        .. " public documents consistent with Gate R state\n")
    return 0
end

if arg and arg[0] and arg[0]:match("check_documentation_truth%.lua$") then
    os.exit(main(arg))
end

return M
