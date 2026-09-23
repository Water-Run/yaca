--[[
Author: WaterRun
Date: 2026-09-23
File: publication_self_test_test.lua
Description: Exercises the actual filesystem port, including failures, without user data.
]]

-- Exercises the actual filesystem port, including failures, without user data.
local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()
local harness = assert(loadfile(YACA_TEST_ROOT .. "/test/support/direct_filesystem_harness.lua", "t", _ENV))()
--Loads a source module into an isolated per-case environment.
--@param name string Module, Model, or resource name selected by the case.
--@return any module Module export loaded in the isolated source environment.
local function load_module(name)
    --@metatable fixture_view Test-owned lookup and mutation contract for the current case.
    --@field __index any Fallback table or function used for missing fixture keys.
    local env = setmetatable({}, { __index = _ENV })
    env._G = env
    env.require = load_module
    return assert(loadfile(YACA_TEST_ROOT .. "/src/" .. name .. ".lua", "t", env))()
end
local main = load_module("main")
local fs_module = load_module("fs")
--Supplies probe behavior required by this suite.
--@param fault any The fault supplied to the fake service for this scenario.
--@param relocate_object_ids any The relocate object ids supplied to the fake service for this scenario.
--@return any observed probe value observed by the scenario assertion.
local function probe(fault, relocate_object_ids)
    local native, controls = harness.new({ ["/data"] = { kind = "directory" }, ["/data/config.ini"] = "unchanged" })
    if fault then controls.faults[fault] = "InjectedFailure" end
    controls.relocate_object_ids = relocate_object_ids
    local fs = assert(fs_module.new(native, {
        maximum_chunk_bytes = 4096, maximum_lease_bytes = 256, maximum_direct_entries = 128,
    }))
    local result = main.check_publication({ backend = { filesystem = fs,
        system = {
            --Supplies deterministic secure random bytes for this suite.
            --@param n any The n supplied to the fake service for this scenario.
            --@return any value Callback value consumed by the enclosing scenario assertion.
            secure_random = function(n) return string.rep("a", n) end } }, layout = { data_root = "/data" } })
    A.equal(controls.bytes("/data/config.ini"), "unchanged")
    for _, suffix in ipairs({ ".old", ".new", ".target" }) do
        A.falsy(controls.exists("/data/.yaca-self-test-" .. string.rep("61", 16) .. suffix), suffix)
    end
    return result
end
return { name = "integration/publication-self-test", cases = {
    { name = "publication probe exercises replacement and removes only its fixtures",
        --Verifies the current case.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return nil No value; assertions verify the current case.
        run = function()
        local result = probe()
        A.equal(result.outcome, "passed")
        A.contains(table.concat(result.evidence), "qualification=not-assessed")
    end },
    { name = "publication probe fails closed and cleans up when filesystem operations fail",
        --Verifies the current case.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return nil No value; assertions verify the current case.
        run = function()
        for _, fault in ipairs({ "write", "flush_file", "replace", "rename", "create" }) do
            A.equal(probe(fault).outcome, "failed", fault)
        end
        A.equal(probe("flush_directory").outcome, "unknown")
    end },
    { name = "publication probe follows changed file IDs after FAT-style publication",
        --Verifies the current case.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return nil No value; assertions verify the current case.
        run = function()
        A.equal(probe(nil, true).outcome, "passed")
    end },
} }
