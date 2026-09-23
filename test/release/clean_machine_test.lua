--[[
Author: WaterRun
Date: 2026-09-23
File: clean_machine_test.lua
Description: Verifies the zero-surface package verifier decision table.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

-- Load a repository-owned Lua contract under the isolated test environment.
--@param relative_path string Path relative to YACA_TEST_ROOT.
--@return any value First value produced by the loaded contract chunk.
--@error Fails the test when loading or executing the contract fails.
local function load_value(relative_path)
    local chunk, load_error = loadfile(YACA_TEST_ROOT .. "/" .. relative_path, "t", _ENV)
    A.truthy(chunk, load_error)
    local ok, value = pcall(chunk)
    A.truthy(ok, value)
    return value
end

local manifest = load_value("release/manifest.lua")
local surface = load_value(".tools/check_zero_surface.lua")
local journeys = load_value("test/release/journeys.lua")

local WINDOWS_ROOT = { "yaca.exe" }

local LINUX_ROOT = { "yaca" }

-- Copy one flat sequence used as a mutable package fixture.
--@param values table Dense source file list.
--@return table copy New sequence with the same file-name strings.
local function clone(values)
    local copy = {}
    for index, value in ipairs(values) do copy[index] = value end
    return copy
end

-- Add one file path to an independent package fixture copy.
--@param base table Dense base file list.
--@param extra string Additional relative file path.
--@return table copy New list containing base entries followed by extra.
local function with_extra(base, extra)
    local copy = clone(base)
    copy[#copy + 1] = extra
    return copy
end

-- Remove one matching file path from an independent package fixture copy.
--@param base table Dense base file list.
--@param removed string Exact path omitted from the result.
--@return table copy New list of remaining paths.
local function without(base, removed)
    local copy = {}
    for _, value in ipairs(base) do
        if value ~= removed then copy[#copy + 1] = value end
    end
    return copy
end

return {
    name = "release/clean-machine",
    cases = {
        {
            name = "exact minimal windows trees pass for both windows targets",
            -- Verify both Windows clean editions accept precisely their executable.
            --@param none The test harness passes no case arguments.
            --@return nil Returns after both target assertions succeed.
            --@error Assertions fail if either clean package shape is rejected.
            run = function()
                for _, target_id in ipairs({ "win32-x86", "win64-x86_64" }) do
                    local ok, result = surface.verify(manifest, clone(WINDOWS_ROOT), target_id)
                    A.truthy(ok, table.concat(result or {}, "; "))
                    A.equal(result.target, target_id)
                    A.equal(result.files, #WINDOWS_ROOT)
                    A.equal(result.surface, "minimal-allowlist")
                end
            end,
        },
        {
            name = "exact minimal linux tree passes",
            -- Verify the Linux clean package has one executable and no companion files.
            --@param none The test harness passes no case arguments.
            --@return nil Returns after Linux surface assertions succeed.
            --@error Assertions fail if the clean Linux tree is rejected.
            run = function()
                local ok, result = surface.verify(manifest, clone(LINUX_ROOT), "linux-x86_64")
                A.truthy(ok, table.concat(result or {}, "; "))
                A.equal(result.executable, "yaca")
                A.equal(result.files, 1)
            end,
        },
        {
            name = "unexpected root file is rejected",
            -- Verify the clean allowlist rejects a second root-level executable.
            --@param none The test harness passes no case arguments.
            --@return nil Returns after checking the exact unexpected-file finding.
            --@error Assertions fail if the extra executable is admitted or misreported.
            run = function()
                local ok, findings = surface.verify(manifest,
                    with_extra(WINDOWS_ROOT, "sqlite3.exe"), "win32-x86")
                A.falsy(ok)
                A.truthy(#findings >= 1)
                local matched = false
                for _, finding in ipairs(findings) do
                    if finding:find("unexpected file: sqlite3.exe", 1, true) then
                        matched = true
                    end
                end
                A.truthy(matched, "unexpected-file finding is missing")
            end,
        },
        {
            name = "forbidden component names are rejected anywhere in the tree",
            -- Verify historical utility names remain forbidden even at nested paths.
            --@param none The test harness passes no case arguments.
            --@return nil Returns after every forbidden-name finding is checked.
            --@error Assertions fail if a forbidden component is admitted.
            run = function()
                for _, extra in ipairs({
                    "busybox", "docs/licenses/7za.exe", ".luai/jq",
                }) do
                    local ok, findings = surface.verify(manifest,
                        with_extra(WINDOWS_ROOT, extra), "win32-x86")
                    A.falsy(ok, extra)
                    local matched = false
                    for _, finding in ipairs(findings) do
                        if finding:find("forbidden component name", 1, true) then
                            matched = true
                        end
                    end
                    A.truthy(matched, extra)
                end
            end,
        },
        {
            name = "shipped configuration and data roots are rejected",
            -- Verify a package cannot carry a configured instance's data tree.
            --@param none The test harness passes no case arguments.
            --@return nil Returns after all data-root fixtures are rejected.
            --@error Assertions fail if configuration or Context data is admitted.
            run = function()
                for _, extra in ipairs({
                    "config.ini", "__yaca__/config.ini",
                    "__yaca__/CONTEXT/C/work/Untitled.xml",
                }) do
                    local ok, findings = surface.verify(manifest,
                        with_extra(WINDOWS_ROOT, extra), "win32-x86")
                    A.falsy(ok, extra)
                end
            end,
        },
        {
            name = "shipped Context artifacts are rejected",
            -- Verify Context XML and lease artifacts are identified as unsafe inputs.
            --@param none The test harness passes no case arguments.
            --@return nil Returns after both Context artifact findings are checked.
            --@error Assertions fail if a Context artifact is admitted or misreported.
            run = function()
                for _, extra in ipairs({
                    "context-backup.xml", "work/Untitled.xml.yaca-lock",
                }) do
                    local ok, findings = surface.verify(manifest,
                        with_extra(WINDOWS_ROOT, extra), "win32-x86")
                    A.falsy(ok, extra)
                    local matched = false
                    for _, finding in ipairs(findings) do
                        if finding:find("shipped Context artifact", 1, true) then
                            matched = true
                        end
                    end
                    A.truthy(matched, extra)
                end
            end,
        },
        {
            name = "missing clean executable is rejected",
            -- Verify the only required clean file cannot be absent.
            --@param none The test harness passes no case arguments.
            --@return nil Returns after the missing-executable finding is checked.
            --@error Assertions fail if an empty package is accepted.
            run = function()
                local ok, findings = surface.verify(manifest,
                    without(WINDOWS_ROOT, "yaca.exe"), "win32-x86")
                A.falsy(ok)
                local matched = false
                for _, finding in ipairs(findings) do
                    if finding:find("missing expected file: yaca.exe", 1, true) then
                        matched = true
                    end
                end
                A.truthy(matched)
            end,
        },
        {
            name = "clean edition rejects installer and documentation companions",
            -- Verify installer, README, license, and SBOM stay outside the clean archive.
            --@param none The test harness passes no case arguments.
            --@return nil Returns after all companion paths are rejected.
            --@error Assertions fail if any companion becomes part of clean.
            run = function()
                for _, extra in ipairs({ "Install.cmd", "README.txt",
                                         "LICENSE", "docs/SBOM.spdx.json" }) do
                    local ok, findings = surface.verify(manifest,
                        with_extra(WINDOWS_ROOT, extra), "win32-x86")
                    A.falsy(ok, extra)
                    A.contains(table.concat(findings, "; "), "unexpected file: " .. extra)
                end
            end,
        },
        {
            name = "manifest cannot expand the clean root allowlist",
            -- Verify a forged manifest cannot add either a second entry or map key.
            --@param none The test harness passes no case arguments.
            --@return nil Returns after both malformed root policies are rejected.
            --@error Assertions fail if a widened clean policy is accepted.
            run = function()
                local altered = clone(manifest.packaging.required_root_entries.windows)
                altered[2] = "README.txt"
                local forged = {
                    targets = manifest.targets,
                    packaging = { required_root_entries = {
                        windows = altered,
                    } },
                }
                local ok, findings = surface.verify(forged,
                    { "yaca.exe", "README.txt" }, "win32-x86")
                A.falsy(ok)
                A.equal(findings[1], "manifest clean root must contain only target executable")
                altered[2] = nil
                altered.extra = true
                ok, findings = surface.verify(forged,
                    { "yaca.exe" }, "win32-x86")
                A.falsy(ok)
                A.equal(findings[1], "manifest clean root must contain only target executable")
            end,
        },
        {
            name = "unknown target ids and broken manifests fail closed",
            -- Verify unknown targets and missing packaging policy are rejected.
            --@param none The test harness passes no case arguments.
            --@return nil Returns after exact failure findings are checked.
            --@error Assertions fail if either malformed request is admitted.
            run = function()
                local ok, findings = surface.verify(manifest, clone(WINDOWS_ROOT), "win16-x86")
                A.falsy(ok)
                A.equal(findings[1], "unknown target id: win16-x86")
                ok, findings = surface.verify({ packaging = nil },
                    clone(WINDOWS_ROOT), "win32-x86")
                A.falsy(ok)
                A.equal(findings[1], "manifest is missing its packaging section")
            end,
        },
        {
            name = "journey plan is offline by default and gates online steps on consent",
            -- Verify the journey planner adds online steps only after explicit consent.
            --@param none The test harness passes no case arguments.
            --@return nil Returns after offline, consented, and unknown-target checks.
            --@error Assertions fail if online work is scheduled without consent.
            run = function()
                local offline, plan_error = journeys.plan("linux-x86_64", {})
                A.truthy(offline, plan_error)
                A.equal(#offline, 6)
                A.equal(offline[1].id, "extract")
                A.equal(offline[6].id, "verify-no-residue")
                local without_consent = journeys.plan("win32-x86",
                    { online = true })
                A.equal(#without_consent, 6)
                local with_consent = journeys.plan("win32-x86",
                    { online = true, online_consent = true })
                A.equal(#with_consent, 10)
                A.equal(with_consent[5].id, "configure")
                A.equal(with_consent[10].id, "verify-no-residue")
                local bad, bad_error = journeys.plan("win16", {})
                A.falsy(bad)
                A.truthy(bad_error)
            end,
        },
        {
            name = "journey step verification accepts matching and rejects wrong evidence",
            -- Verify version, self-test, surface, and residue evidence bindings.
            --@param none The test harness passes no case arguments.
            --@return nil Returns after accepted and rejected evidence is checked.
            --@error Assertions fail if a mismatched journey observation passes.
            run = function()
                local ok = journeys.verify_step("version", "linux-x86_64",
                    { output = "yaca 0.1.0 (linux-x86_64)\n" })
                A.truthy(ok)
                ok = journeys.verify_step("version", "linux-x86_64",
                    { output = "yaca 0.1.0 (win32-x86)\n" })
                A.falsy(ok)
                ok = journeys.verify_step("selftest-stage1", "win32-x86",
                    { exit_code = 0,
                      output = "self-test outcome=passed completed-stage=1 online-requests=0 auto-fixes=0" })
                A.truthy(ok)
                ok = journeys.verify_step("selftest-stage1", "win32-x86",
                    { exit_code = 0,
                      output = "self-test outcome=passed completed-stage=1 auto-fixes=2" })
                A.falsy(ok)
                ok = journeys.verify_step("selftest-stage1", "linux-x86_64",
                    { exit_code = 1,
                      output = "self-test outcome=partial completed-stage=1 online-requests=0 auto-fixes=0" })
                A.truthy(ok)
                ok = journeys.verify_step("selftest-stage1", "linux-x86_64",
                    { exit_code = 1,
                      output = "self-test outcome=error completed-stage=1 auto-fixes=0" })
                A.falsy(ok)
                ok = journeys.verify_step("zero-surface", "win32-x86",
                    { exit_code = 0, output = "zero-surface=PASS target=win32-x86 files=1" })
                A.truthy(ok)
                ok = journeys.verify_step("verify-no-residue", "win32-x86",
                    { residue_paths = {} })
                A.truthy(ok)
                local failed, finding = journeys.verify_step(
                    "verify-no-residue", "win32-x86",
                    { residue_paths = { "/tmp/yaca-install" } })
                A.falsy(failed)
                A.truthy(finding:find("residue", 1, true))
            end,
        },
        {
            name = "host mismatch only skips run and online steps",
            -- Verify cross-host qualification skips only host-dependent actions.
            --@param none The test harness passes no case arguments.
            --@return nil Returns after skip-list assertions succeed.
            --@error Assertions fail if offline package checks are skipped.
            run = function()
                local steps = journeys.plan("win64-x86_64", {})
                local skipped = journeys.skipped_on_host_mismatch(steps, "linux")
                A.equal(#skipped, 2)
                A.equal(skipped[1], "version")
                A.equal(skipped[2], "selftest-stage1")
                local none = journeys.skipped_on_host_mismatch(
                    journeys.plan("linux-x86_64", {}), "linux")
                A.equal(#none, 0)
            end,
        },
        {
            name = "duplicate entries are reported",
            -- Verify a duplicate executable path is not accepted as a valid clean tree.
            --@param none The test harness passes no case arguments.
            --@return nil Returns after the duplicate-path finding is checked.
            --@error Assertions fail if duplicate entries are admitted or hidden.
            run = function()
                local ok, findings = surface.verify(manifest,
                    with_extra(WINDOWS_ROOT, "yaca.exe"), "win32-x86")
                A.falsy(ok)
                local matched = false
                for _, finding in ipairs(findings) do
                    if finding:find("duplicate entry: yaca.exe", 1, true) then
                        matched = true
                    end
                end
                A.truthy(matched)
            end,
        },
    },
}
