--[[
Author: WaterRun
Date: 2026-09-23
File: context_lock_test.lua
Description: Verifies long-lived Context writer leases and publication mutex ownership.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

--Loads a source module into an isolated per-case environment.
--@param name string Module, Model, or resource name selected by the case.
--@param cache table Per-case module cache preserving isolated imports.
--@return any module Module export loaded in the isolated source environment.
local function load_module(name, cache)
    cache = cache or {}
    if cache[name] then return cache[name] end
    local environment = {
        --Resolves an imported Lua module through the isolated test loader.
        --@param dependency string Source module requested from the isolated loader.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        require = function(dependency)
        return load_module(dependency, cache)
    end }
    environment._G = environment
    --@metatable environment Test-owned lookup and mutation contract for the current case.
    --@field __index any Fallback table or function used for missing fixture keys.
    setmetatable(environment, { __index = _ENV })
    local chunk, load_error = loadfile(
        YACA_TEST_ROOT .. "/src/" .. name .. ".lua",
        "t",
        environment
    )
    A.truthy(chunk, load_error)
    local value = chunk()
    cache[name] = value
    return value
end

--Loads a repository Lua module as a test support value.
--@param relative_path string Repository-relative Lua source path to load.
--@return any module Test support module export loaded from the repository.
local function load_table(relative_path)
    local chunk, load_error = loadfile(YACA_TEST_ROOT .. "/" .. relative_path, "t", _ENV)
    A.truthy(chunk, load_error)
    return chunk()
end

local cache = {}
local harness = load_table("test/support/context_store_harness.lua")
local modules = {
    context = load_module("context", cache),
    xml = load_module("xml", cache),
    fs = load_module("fs", cache),
    fake_lxp = load_table("test/support/fake_lxp.lua"),
    sha256 = load_table("test/support/sha256_reference.lua"),
    fake_filesystem = load_table("test/support/fake_filesystem.lua"),
}

local TARGET = "/data/Task.xml"
local LOCK = TARGET .. ".yaca-lock"

--Supplies count operation behavior required by this suite.
--@param operations table Queued operations supplied to the fixture.
--@param exact any The exact supplied to the fake service for this scenario.
--@return any observed count operation value observed by the scenario assertion.
local function count_operation(operations, exact)
    local count = 0
    for _, operation in ipairs(operations) do
        if operation == exact then count = count + 1 end
    end
    return count
end

return {
    name = "integration/context-lock",
    cases = {
        {
            name = "second writer conflicts before any Context body read",
            --Verifies second writer conflicts before any Context body read.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify second writer conflicts before any Context body read.
            run = function()
                local fixture = harness.new(modules, { [TARGET] = harness.minimal("Task") })
                local first, document = assert(fixture.store.open_writer(
                    TARGET,
                    fixture.metadata(101)
                ))
                A.equal(document.generation, 1)
                A.truthy(fixture.controls.exists(LOCK))
                A.contains(fixture.controls.bytes(LOCK), "version=1\n")
                A.contains(fixture.controls.bytes(LOCK), "pid=101\n")
                A.contains(fixture.controls.bytes(LOCK), "startedAt=2026-08-29T00:00:00Z\n")
                A.contains(fixture.controls.bytes(LOCK), "hostname=test-host\n")
                local inspection = assert(fixture.store.inspect_writer(TARGET))
                A.equal(inspection.busy, true)
                A.equal(inspection.pid, 101)
                A.equal(inspection.started_at, "2026-08-29T00:00:00Z")
                A.equal(inspection.hostname, "test-host")
                A.equal(inspection.metadata_state, "valid")
                local opens_before = count_operation(fixture.controls.operations, "open:" .. TARGET)

                local second_store = fixture.new_store()
                local second, lock_error = second_store.open_writer(
                    TARGET,
                    fixture.metadata(202)
                )
                A.falsy(second)
                A.equal(lock_error.code, "LockConflict")
                A.equal(
                    count_operation(fixture.controls.operations, "open:" .. TARGET),
                    opens_before
                )

                A.truthy(fixture.store.close_writer(first))
                A.falsy(fixture.controls.exists(LOCK))
                A.equal(fixture.store.inspect_writer(TARGET).busy, false)
                local admitted = assert(second_store.open_writer(TARGET, fixture.metadata(202)))
                A.truthy(second_store.close_writer(admitted))
            end,
        },
        {
            name = "stale-looking lock is never broken by age or confirmation",
            --Verifies stale-looking lock is never broken by age or confirmation.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify stale-looking lock is never broken by age or confirmation.
            run = function()
                local fixture = harness.new(modules, { [TARGET] = harness.minimal("Task") })
                fixture.controls.external_replace(LOCK, table.concat({
                    "version=1",
                    "pid=1",
                    "startedAt=2001-01-01T00:00:00Z",
                    "hostname=old-host",
                    "",
                }, "\n"))
                local writer, lock_error = fixture.store.open_writer(
                    TARGET,
                    fixture.metadata(303)
                )
                A.falsy(writer)
                A.equal(lock_error.code, "LockConflict")
                A.truthy(fixture.controls.exists(LOCK))
                A.contains(fixture.controls.bytes(LOCK), "startedAt=2001")
                local inspection = assert(fixture.store.inspect_writer(TARGET))
                A.equal(inspection.busy, true)
                A.equal(inspection.pid, 1)
                A.equal(inspection.metadata_state, "valid")
            end,
        },
        {
            name = "writer metadata paths and ownership fail closed",
            --Verifies writer metadata paths and ownership fail closed.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify writer metadata paths and ownership fail closed.
            run = function()
                local fixture = harness.new(modules)
                local invalid_pid, pid_error = fixture.store.create_writer(TARGET, {
                    pid = 0,
                    started_at = "2026-08-29T00:00:00Z",
                })
                A.falsy(invalid_pid)
                A.equal(pid_error.code, "InvalidWriterMetadata")
                local bad_host, host_error = fixture.store.create_writer(TARGET, {
                    pid = 1,
                    started_at = "2026-08-29T00:00:00Z",
                    hostname = "bad\nhost",
                })
                A.falsy(bad_host)
                A.truthy(host_error.code)
                A.falsy(fixture.store.create_writer("relative.xml", fixture.metadata()))
                A.falsy(fixture.store.create_writer("/data/not-context", fixture.metadata()))
                A.falsy(fixture.store.create_writer("/data/../Task.xml", fixture.metadata()))

                local writer = assert(fixture.store.create_writer(TARGET, fixture.metadata()))
                local foreign = {}
                A.falsy(fixture.store.writer_status(foreign))
                A.falsy(fixture.store.publish(foreign, {}, TARGET .. ".yaca-tmp-a"))
                --Executes the action expected to raise in the 'writer metadata paths and ownership fail closed' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify writer metadata paths and ownership fail closed.
                A.raises(function() writer.value = true end, "cannot be modified")
                A.truthy(fixture.store.close_writer(writer))
                A.falsy(fixture.store.close_writer(writer))
            end,
        },
        {
            name = "in-process publication mutex rejects a reentrant commit",
            --Verifies in-process publication mutex rejects a reentrant commit.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify in-process publication mutex rejects a reentrant commit.
            run = function()
                local fixture = harness.new(modules)
                local candidate = harness.minimal("Task")
                local document = fixture.document(candidate)
                local writer = assert(fixture.store.create_writer(TARGET, fixture.metadata()))
                local nested
                --Supplies fs write behavior required by the 'in-process publication mutex rejects a reentrant commit' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify in-process publication mutex rejects a reentrant commit.
                fixture.hooks.before.fs_write = function()
                    if not nested then
                        local value, nested_error = fixture.store.publish(
                            writer,
                            document,
                            TARGET .. ".yaca-tmp-nested"
                        )
                        nested = { value = value, error = nested_error }
                    end
                end
                local receipt = assert(fixture.store.publish(
                    writer,
                    document,
                    TARGET .. ".yaca-tmp-outer"
                ))
                A.equal(receipt.outcome, "published")
                A.falsy(nested.value)
                A.equal(nested.error.code, "ContextCommitConflict")
                A.equal(fixture.store.writer_status(writer).publication_active, false)
                A.truthy(fixture.store.close_writer(writer))
            end,
        },
        {
            name = "lease identity replacement is never deleted as if still owned",
            --Verifies lease identity replacement is never deleted as if still owned.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify lease identity replacement is never deleted as if still owned.
            run = function()
                local fixture = harness.new(modules)
                local writer = assert(fixture.store.create_writer(TARGET, fixture.metadata()))
                fixture.controls.external_replace(LOCK, "foreign-lock\n")
                local closed, close_error = fixture.store.close_writer(writer)
                A.falsy(closed)
                A.equal(close_error.code, "IdentityChanged")
                A.equal(fixture.controls.bytes(LOCK), "foreign-lock\n")
                A.equal(fixture.store.writer_status(writer).status, "closed")
                local inspection = assert(fixture.store.inspect_writer(TARGET))
                A.equal(inspection.busy, true)
                A.equal(inspection.pid, "unknown")
                A.equal(inspection.metadata_state, "invalid")
            end,
        },
        {
            name = "lease write flush and directory faults never admit a writer",
            --Verifies lease write flush and directory faults never admit a writer.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify lease write flush and directory faults never admit a writer.
            run = function()
                local cases = {
                    { field = "write", code = "InjectedWrite" },
                    { field = "flush_file", code = "InjectedFlush" },
                    { field = "flush_directory", code = "LeaseAcquireUnknown" },
                }
                for _, case in ipairs(cases) do
                    local fixture = harness.new(modules)
                    fixture.controls.faults[case.field] = true
                    local writer, lease_error = fixture.store.create_writer(
                        TARGET,
                        fixture.metadata()
                    )
                    A.falsy(writer, case.field)
                    A.equal(lease_error.code, case.code, case.field)
                    A.falsy(fixture.controls.exists(LOCK), case.field)
                    A.falsy(fixture.controls.exists(TARGET), case.field)
                end
            end,
        },
    },
}
