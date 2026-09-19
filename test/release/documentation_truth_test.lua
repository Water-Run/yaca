--[[
File: documentation_truth_test.lua
Date: 2026-09-19
Author: WaterRun
Description: Verifies the documentation-truth guard decision table.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

local function load_value(relative_path)
    local chunk, load_error = loadfile(YACA_TEST_ROOT .. "/" .. relative_path, "t", _ENV)
    A.truthy(chunk, load_error)
    local ok, value = pcall(chunk)
    A.truthy(ok, value)
    return value
end

local truth = load_value(".tools/check_documentation_truth.lua")

local function signals(overrides)
    local base = {
        gate_r_closed = true,
        release_not_authorized = true,
        phase = "implemented-unqualified",
        pending_targets = { "win32-x86", "win64-x86_64", "linux-x86_64" },
        all_targets_passed = false,
    }
    for key, value in pairs(overrides or {}) do base[key] = value end
    return base
end

return {
    name = "release/documentation-truth",
    cases = {
        {
            name = "honest readme and quickstart texts produce no findings",
            run = function()
                A.equal(#truth.document_findings("README.md",
                    "> **status: target qualification pending.** Gate R closed.",
                    signals()), 0)
                A.equal(#truth.document_findings("README-zh.md",
                    "目标资格验证待完成", signals()), 0)
                A.equal(#truth.document_findings("release/LINUX-QUICKSTART.md",
                    "裸机 CentOS 7 资格仍待完成", signals()), 0)
                A.equal(#truth.document_findings("release/WINDOWS-QUICKSTART.md",
                    "真实 XP 与完整目标验收仍未完成，资格待完成。", signals()), 0)
            end,
        },
        {
            name = "forbidden release claims are rejected in either language",
            run = function()
                for _, text in ipairs({
                    "Release Gate R is passed today.",
                    "The build is qualified for release.",
                    "This archive is qualified for release now.",
                    "all targets qualified on real machines",
                    "发行资格已通过。",
                    "全部目标已通过资格验证。",
                }) do
                    local findings = truth.document_findings("README.md",
                        text, signals())
                    A.truthy(#findings >= 1, text)
                end
            end,
        },
        {
            name = "missing pending markers on readme and quickstarts are rejected",
            run = function()
                local findings = truth.document_findings("README.md",
                    "yaca is a coding agent.", signals())
                A.truthy(#findings == 1)
                A.truthy(findings[1]:find("missing the pending", 1, true))
                findings = truth.document_findings("README-zh.md",
                    "yaca 是一个编码代理。", signals())
                A.truthy(#findings == 1)
                findings = truth.document_findings("release/WINDOWS-QUICKSTART.md",
                    "解压后直接运行。", signals())
                A.truthy(#findings >= 1)
                A.truthy(findings[1]:find("pending", 1, true))
                findings = truth.document_findings("release/LINUX-QUICKSTART.md",
                    "解压后直接运行。", signals())
                A.truthy(#findings >= 1)
            end,
        },
        {
            name = "signals derive from readiness and manifest shapes",
            run = function()
                local readiness = load_value(
                    ".develope-docs/contracts/readiness.lua")
                local manifest = load_value("release/manifest.lua")
                local value = truth.signals(readiness, manifest)
                A.equal(value.phase, "implemented-unqualified")
                A.truthy(value.gate_r_closed)
                A.truthy(value.release_not_authorized)
                A.truthy(not value.all_targets_passed)
                A.equal(#value.pending_targets, 3)
                local passed_manifest = {
                    targets = {
                        { id = "a", qualification = "passed" },
                    },
                }
                value = truth.signals(readiness, passed_manifest)
                A.truthy(value.all_targets_passed)
            end,
        },
    },
}
