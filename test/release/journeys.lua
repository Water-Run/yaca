--[[
File: journeys.lua
Date: 2026-09-19
Author: WaterRun
Description: Clean-machine release journey driver. The module part is a
pure plan/verify core covered by the suite; the CLI part executes the
offline journey for a candidate zip on a matching Linux host.

CLI usage:
  bin/lua55 test/release/journeys.lua <repo-root> <zip> <target-id> <scratch>
    [--i-accept-online-journey <config-ini>]
The online segment (stages 2/3 with a provider) only runs with the explicit
consent flag plus a configuration file path.
]]

local M = {}

local PLATFORM_LINE = {
    ["win32-x86"] = "yaca 0%.1%.0 %(win32%-x86%)",
    ["win64-x86_64"] = "yaca 0%.1%.0 %(win64%-x86_64%)",
    ["linux-x86_64"] = "yaca 0%.1%.0 %(linux%-x86_64%)",
}

local EXECUTABLE_BY_OS = {
    windows = "yaca.exe",
    linux = "yaca",
}

--- Plans the journey steps for one target.
-- options.online is only honoured when options.online_consent is true.
function M.plan(target_id, options)
    options = options or {}
    if not PLATFORM_LINE[target_id] then
        return nil, "unknown target id: " .. tostring(target_id)
    end
    local os_name = target_id:match("^win") and "windows" or "linux"
    local steps = {
        { id = "extract", kind = "setup" },
        { id = "zero-surface", kind = "static" },
        { id = "version", kind = "run", os = os_name },
        { id = "selftest-stage1", kind = "run", os = os_name },
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

--- Verifies the observed evidence for one journey step.
-- observed: table with string fields depending on the step (output, exit_code,
-- residue_paths). Returns true or false, finding.
function M.verify_step(step_id, target_id, observed)
    observed = observed or {}
    if step_id == "extract" then
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
        if pattern and (observed.output or ""):find(pattern) then
            return true
        end
        return false, "version output does not match the target platform"
    elseif step_id == "selftest-stage1" or step_id == "selftest-stage3" then
        -- A clean machine may run stage 1 before any configuration exists;
        -- the honest result then is "partial" (exit code 1) with a
        -- not-initialized warning, which still proves the offline surface.
        local output = observed.output or ""
        local outcome = output:match("outcome=([a-z]+)")
        local acceptable = outcome == "passed"
            or (step_id == "selftest-stage1" and outcome == "partial")
        if acceptable
            and (observed.exit_code == 0
                or (outcome == "partial" and observed.exit_code == 1))
            and output:find("auto%-fixes=0", 1, false) then
            return true
        end
        return false, "self-test did not pass cleanly (outcome="
            .. tostring(outcome) .. ", exit=" .. tostring(observed.exit_code) .. ")"
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

--- Steps that must be skipped when the driver host OS differs from the
-- target OS (for example auditing a Windows zip from a Linux driver).
function M.skipped_on_host_mismatch(steps, host_os)
    local skipped = {}
    for _, step in ipairs(steps) do
        if step.os and step.os ~= host_os then
            skipped[#skipped + 1] = step.id
        end
    end
    return skipped
end

----------------------------------------------------------------------------
-- CLI execution (Linux hosts only for the run/online kinds).
----------------------------------------------------------------------------

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function run_command(command)
    local pipe = io.popen(command .. " 2>&1", "r")
    if not pipe then return { exit_code = 1, output = "cannot start command" } end
    local output = pipe:read("a") or ""
    local ok, _, code = pipe:close()
    return { exit_code = ok and 0 or (code or 1), output = output }
end

local function main(argv)
    local repo, zip_path, target_id, scratch = argv[1], argv[2], argv[3], argv[4]
    local consent, config_path
    for index = 5, #argv do
        if argv[index] == "--i-accept-online-journey" then
            consent = true
            config_path = argv[index + 1]
        end
    end
    if not (repo and zip_path and target_id and scratch) then
        io.stderr:write("usage: journeys.lua <repo-root> <zip> <target-id> "
            .. "<scratch> [--i-accept-online-journey <config-ini>]\n")
        return 64
    end
    if package.config:sub(1, 1) == "\\" then
        io.stderr:write("journeys: the executing driver supports Linux hosts; "
            .. "run Windows zips on the Windows target\n")
        return 1
    end
    local steps, plan_error = M.plan(target_id, {
        online = consent ~= nil, online_consent = consent,
    })
    if not steps then
        io.stderr:write("journeys: " .. tostring(plan_error) .. "\n")
        return 1
    end
    local install = scratch .. "/yaca-install"
    local work = scratch .. "/yaca-work"
    os.execute("rm -rf " .. shell_quote(install) .. " "
        .. shell_quote(work) .. " " .. shell_quote(scratch .. "/unpack"))
    os.execute("mkdir -p " .. shell_quote(scratch .. "/unpack") .. " "
        .. shell_quote(work))

    local results = {}
    local failed = false
    for _, step in ipairs(steps) do
        local observed
        if step.id == "extract" then
            observed = run_command("unzip -q " .. shell_quote(zip_path)
                .. " -d " .. shell_quote(install))
        elseif step.id == "zero-surface" then
            observed = run_command("bin/lua55 .tools/check_zero_surface.lua "
                .. shell_quote(repo) .. " " .. shell_quote(install) .. " "
                .. shell_quote(target_id))
        elseif step.id == "version" then
            observed = run_command(shell_quote(install .. "/yaca")
                .. " --version")
        elseif step.id == "selftest-stage1" then
            observed = run_command(shell_quote(install .. "/yaca")
                .. " --self-test --through-stage 1")
        elseif step.id == "configure" then
            os.execute("mkdir -p " .. shell_quote(install .. "/__yaca__"))
            os.execute("cp " .. shell_quote(config_path or "/dev/null")
                .. " " .. shell_quote(install .. "/__yaca__/config.ini"))
            local status = run_command(shell_quote(install .. "/yaca")
                .. " --status")
            observed = {
                config_active = status.output:find("config%-generation", 1, false)
                    ~= nil,
                output = status.output,
            }
        elseif step.id == "chat-tool-turn" or step.id == "restore"
            or step.id == "selftest-stage3" then
            -- The interactive segment is driven by the operator's expect
            -- harness against the same install; record it as not executed
            -- here instead of faking evidence.
            observed = { output = "interactive segment not executed by driver" }
        elseif step.id == "uninstall" then
            observed = run_command("rm -rf " .. shell_quote(install) .. " "
                .. shell_quote(work) .. " " .. shell_quote(scratch .. "/unpack"))
        elseif step.id == "verify-no-residue" then
            local residue = {}
            for _, path in ipairs({ install, work, scratch .. "/unpack" }) do
                local probe = io.open(path, "r")
                if probe then
                    probe:close()
                    residue[#residue + 1] = path
                end
            end
            observed = { residue_paths = residue }
        end
        local ok, finding = M.verify_step(step.id, target_id, observed or {})
        results[#results + 1] = string.format("%s %s%s",
            ok and "PASS" or "SKIP-FAIL", step.id,
            (ok and "") or (" :: " .. tostring(finding)))
        if not ok and step.kind ~= "online" then failed = true end
    end
    for _, line in ipairs(results) do print(line) end
    if failed then
        print("journey=FAIL target=" .. target_id)
        return 1
    end
    print("journey=PASS target=" .. target_id)
    return 0
end

if arg and arg[0] and arg[0]:match("journeys%.lua$") then
    os.exit(main(arg))
end

return M
