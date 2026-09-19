--[[
File: clean_machine_test.lua
Date: 2026-09-19
Author: WaterRun
Description: Verifies the zero-surface package verifier decision table.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

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

local WINDOWS_ROOT = {
    "yaca.exe", "Install.cmd", "README.txt", "LICENSE",
    "docs/WINDOWS-QUICKSTART.md", "docs/COMPONENTS.txt",
    "docs/build-summary.json", "docs/SBOM.spdx.json",
    "docs/licenses/Lua-MIT.html", "docs/licenses/Expat-MIT.txt",
    "docs/licenses/LuaExpat-MIT.html", "docs/licenses/luainstaller-LGPL.txt",
    "docs/licenses/curl.txt", "docs/licenses/Mbed-TLS.txt",
    "docs/licenses/Mozilla-CA.pem",
}

local LINUX_ROOT = {
    "yaca", "Install.sh", "README.txt", "LICENSE",
    "docs/LINUX-QUICKSTART.md", "docs/COMPONENTS.txt",
    "docs/build-summary.json", "docs/SBOM.spdx.json",
    "docs/licenses/Lua-MIT.html", "docs/licenses/Expat-MIT.txt",
    "docs/licenses/LuaExpat-MIT.html", "docs/licenses/luainstaller-LGPL.txt",
    "docs/licenses/curl.txt", "docs/licenses/Mbed-TLS.txt",
    "docs/licenses/Mozilla-CA.pem",
}

local function clone(values)
    local copy = {}
    for index, value in ipairs(values) do copy[index] = value end
    return copy
end

local function with_extra(base, extra)
    local copy = clone(base)
    copy[#copy + 1] = extra
    return copy
end

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
            run = function()
                local ok, result = surface.verify(manifest, clone(LINUX_ROOT), "linux-x86_64")
                A.truthy(ok, table.concat(result or {}, "; "))
                A.equal(result.executable, "yaca")
                A.equal(result.installer, "Install.sh")
            end,
        },
        {
            name = "unexpected root file is rejected",
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
            name = "missing expected files are rejected",
            run = function()
                for _, removed in ipairs({ "yaca.exe", "LICENSE",
                                            "docs/SBOM.spdx.json" }) do
                    local ok, findings = surface.verify(manifest,
                        without(WINDOWS_ROOT, removed), "win32-x86")
                    A.falsy(ok, removed)
                    local matched = false
                    for _, finding in ipairs(findings) do
                        if finding:find("missing expected file: " .. removed, 1, true) then
                            matched = true
                        end
                    end
                    A.truthy(matched, removed)
                end
            end,
        },
        {
            name = "unknown target ids and broken manifests fail closed",
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
                    { exit_code = 0, output = "zero-surface=PASS target=win32-x86 files=15" })
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
