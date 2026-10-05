--[[
Author: WaterRun
Date: 2026-10-05
File: journeys.lua
Description: Plans and verifies release journeys; delegates offline Linux execution
of audited clean/std/full ZIP pairs to the isolated build-host PTY driver.

CLI usage:
bin/lua55 test/release/journeys.lua <repo-root> <zip> <target-id> <scratch>
[--notices <notices-zip>] [--report <new-json-path>]
Online steps require the separate configured-target terminal smoke driver.
]]

local M = {}

local PLATFORM_LINE = {
    ["win32-x86"] = "yaca 1%.0%.0 %(win32%-x86%)",
    ["win64-x86_64"] = "yaca 1%.0%.0 %(win64%-x86_64%)",
    ["linux-x86_64"] = "yaca 1%.0%.0 %(linux%-x86_64%)",
}

-- Build the target's offline plan, adding online steps only with explicit consent.
--@param target_id string Canonical release target identifier.
--@param options table|nil Optional online and online_consent booleans; defaults to offline.
--@return table|nil Ordered journey steps; nil for an unknown target.
--@return string|nil Unknown-target diagnostic; nil when planning succeeds.
function M.plan(target_id, options)
    options = options or {}
    if not PLATFORM_LINE[target_id] then
        return nil, "unknown target id: " .. tostring(target_id)
    end
    local os_name = target_id:match("^win") and "windows" or "linux"
    local steps = {
        { id = "package-integrity", kind = "static" },
        { id = "extract", kind = "setup" },
        { id = "version", kind = "run", os = os_name },
        { id = "non-tty-no-writes", kind = "run", os = os_name },
        { id = "embedded-lua", kind = "run", os = os_name },
        { id = "selftest-stage1", kind = "run", os = os_name },
        { id = "without-tools", kind = "run", os = os_name },
        { id = "move", kind = "run", os = os_name },
    }
    if options.online and options.online_consent then
        steps[#steps + 1] = { id = "configure", kind = "online", os = os_name }
        steps[#steps + 1] = { id = "chat-tool-turn", kind = "online", os = os_name }
        steps[#steps + 1] = { id = "restore", kind = "online", os = os_name }
        steps[#steps + 1] = { id = "selftest-stage3", kind = "online", os = os_name }
    end
    steps[#steps + 1] = { id = "uninstall", kind = "teardown" }
    steps[#steps + 1] = { id = "verify-no-residue", kind = "teardown" }
    return steps
end

-- Validate one observation against the step's completion and failure requirements.
--@param step_id string Stable journey step identifier.
--@param target_id string Canonical target used to bind version observations.
--@param observed table|nil Captured exit code, transcript or explicit observation flags.
--@return boolean True only when the step has the required successful evidence.
--@return string|nil Missing or contradictory evidence diagnostic; nil on success.
function M.verify_step(step_id, target_id, observed)
    observed = observed or {}
    if step_id == "package-integrity" then
        if observed.integrity == "passed" and observed.target == target_id then
            return true
        end
        return false, "package integrity did not pass for the selected target"
    elseif step_id == "extract" then
        if observed.exit_code ~= 0 then
            return false, "extraction failed with " .. tostring(observed.exit_code)
        end
        return true
    elseif step_id == "zero-surface" then
        local output = observed.output or ""
        if observed.exit_code == 0 and output:find("zero%-surface=PASS", 1, false) then
            return true
        end
        return false, "zero-surface check did not pass"
    elseif step_id == "version" then
        local pattern = PLATFORM_LINE[target_id]
        if observed.exit_code == 0 and pattern and (observed.output or ""):find(pattern) then
            return true
        end
        return false, "version output does not match the target platform"
    elseif step_id == "selftest-stage1" or step_id == "selftest-stage3" then
        local output = observed.output or ""
        local outcome = output:match("outcome=([a-z]+)")
        local expected_code = outcome == "passed" and 0 or 1
        local expected_stage = step_id == "selftest-stage1" and "1" or "3"
        local acceptable = outcome == "passed"
            or (step_id == "selftest-stage1" and outcome == "partial")
        if acceptable and observed.exit_code == expected_code
            and output:match("completed%-stage=(%d+)") == expected_stage
            and output:match("auto%-fixes=(%d+)") == "0"
            and not output:match("%f[%a]FAILED%f[%A]")
            and (step_id ~= "selftest-stage1"
                or output:match("online%-requests=(%d+)") == "0")
        then
            return true
        end
        return false, "self-test did not finish the requested stage without failures"
    elseif step_id == "non-tty-no-writes" then
        if observed.exit_code and observed.exit_code ~= 0
            and (observed.output or ""):find("TtyRequired", 1, true)
            and observed.zero_writes == true
        then
            return true
        end
        return false, "non-TTY refusal or zero-write evidence is missing"
    elseif step_id == "embedded-lua" then
        if observed.exit_code == 0 and (observed.output or ""):match("^%s*42%s*$") then
            return true
        end
        return false, "embedded Lua did not produce 42 successfully"
    elseif step_id == "without-tools" or step_id == "move" then
        if observed.core_verified == true and observed.lua_verified == true then
            return true
        end
        return false, "portable core or embedded Lua evidence is missing"
    elseif step_id == "configure" then
        if observed.config_active then return true end
        return false, "configuration was not activated"
    elseif step_id == "chat-tool-turn" then
        if observed.turn_completed and observed.approvals_seen then
            return true
        end
        return false, "interactive tool turn did not complete with approvals"
    elseif step_id == "restore" then
        if observed.history_recalled then return true end
        return false, "restored context did not recall durable history"
    elseif step_id == "uninstall" then
        if observed.exit_code == 0 then return true end
        return false, "uninstall did not complete"
    elseif step_id == "verify-no-residue" then
        local residue = observed.residue_paths or {}
        if #residue == 0 then return true end
        return false, "residue after uninstall: " .. table.concat(residue, ", ")
    end
    return false, "unknown journey step: " .. tostring(step_id)
end

-- Identify target execution steps that cannot run on the driver's host OS.
--@param steps table Ordered step descriptors returned by plan.
--@param host_os string Driver OS identity, windows or linux.
--@return table Ordered IDs requiring a different operating system.
function M.skipped_on_host_mismatch(steps, host_os)
    local skipped = {}
    for _, step in ipairs(steps) do
        if step.os and step.os ~= host_os then
            skipped[#skipped + 1] = step.id
        end
    end
    return skipped
end

-- Quote one literal argument for the POSIX build-host command shell.
--@param value string Command argument, including paths containing spaces or quotes.
--@return string Single shell word preserving the argument's exact bytes.
local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

-- Delegate runtime work to the guarded driver, propagating every failure exit.
--@param argv table Repository, runtime ZIP, target, scratch and optional driver arguments.
--@return integer Driver exit status, or 64 for missing arguments or a Windows driver host.
--@effect Starts the resource guard and Python build-host driver; it owns extraction and cleanup.
local function main(argv)
    if not (argv[1] and argv[2] and argv[3] and argv[4]) then
        io.stderr:write("usage: journeys.lua <repo-root> <zip> <target-id> <scratch> "
            .. "[--notices <zip>] [--report <new-json-path>]\n")
        return 64
    end
    if package.config:sub(1, 1) == "\\" then
        io.stderr:write("journeys: execute the offline driver on a Linux build host\n")
        return 64
    end
    local repo = argv[1]
    local words = {
        "bash", shell_quote(repo .. "/.tools/run_with_resource_guard.sh"),
        "python3", shell_quote(repo .. "/.tools/qualification/edition_journey.py"),
    }
    for _, value in ipairs(argv) do words[#words + 1] = shell_quote(value) end
    local ok, _, code = os.execute(table.concat(words, " "))
    return ok and 0 or (code or 1)
end

if arg and arg[0] and arg[0]:match("journeys%.lua$") then
    os.exit(main(arg))
end

return M
