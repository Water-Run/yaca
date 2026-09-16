-- Exercises the actual filesystem port, including failures, without user data.
local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()
local harness = assert(loadfile(YACA_TEST_ROOT .. "/test/support/direct_filesystem_harness.lua", "t", _ENV))()
local function load_module(name)
    local env = setmetatable({}, { __index = _ENV })
    env._G = env
    env.require = load_module
    return assert(loadfile(YACA_TEST_ROOT .. "/src/" .. name .. ".lua", "t", env))()
end
local main = load_module("main")
local fs_module = load_module("fs")
local function probe(fault)
    local native, controls = harness.new({ ["/data"] = { kind = "directory" }, ["/data/config.ini"] = "unchanged" })
    if fault then controls.faults[fault] = "InjectedFailure" end
    local fs = assert(fs_module.new(native, {
        maximum_chunk_bytes = 4096, maximum_lease_bytes = 256, maximum_direct_entries = 128,
    }))
    local result = main.check_publication({ backend = { filesystem = fs,
        system = { secure_random = function(n) return string.rep("a", n) end } }, layout = { data_root = "/data" } })
    A.equal(controls.bytes("/data/config.ini"), "unchanged")
    for _, suffix in ipairs({ ".old", ".new", ".target" }) do
        A.falsy(controls.exists("/data/.yaca-self-test-" .. string.rep("61", 16) .. suffix), suffix)
    end
    return result
end
return { name = "integration/publication-self-test", cases = {
    { name = "publication probe exercises replacement and removes only its fixtures", run = function()
        local result = probe()
        A.equal(result.outcome, "passed")
        A.contains(table.concat(result.evidence), "qualification=not-assessed")
    end },
    { name = "publication probe fails closed and cleans up when filesystem operations fail", run = function()
        for _, fault in ipairs({ "write", "flush_file", "replace", "rename", "create" }) do
            A.equal(probe(fault).outcome, "failed", fault)
        end
        A.equal(probe("flush_directory").outcome, "unknown")
    end },
} }
