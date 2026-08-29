--[[
File: context_commit_test.lua
Date: 2026-08-29
Author: WaterRun
Description: Verifies full-XML publication, recovery, and injected commit failures.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

local function load_module(name, cache)
    cache = cache or {}
    if cache[name] then return cache[name] end
    local environment = { require = function(dependency)
        return load_module(dependency, cache)
    end }
    environment._G = environment
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
local PREVIOUS = TARGET .. ".yaca-prev"

local function temp(id)
    return TARGET .. ".yaca-tmp-" .. id
end

local function operation_index(operations, expected)
    for index, operation in ipairs(operations) do
        if operation == expected then return index end
    end
    return nil
end

local function replacement_fixture()
    local first = harness.minimal("Task")
    local fixture = harness.new(modules, { [TARGET] = first })
    local writer, opened = assert(fixture.store.open_writer(TARGET, fixture.metadata()))
    A.equal(opened.generation, 1)
    local second = harness.next_generation(first)
    local document, bytes = fixture.document(second)
    fixture.controls.operations = {}
    return fixture, writer, first, second, document, bytes
end

return {
    name = "fault/context-commit",
    cases = {
        {
            name = "new Context publishes no-replace only after exact validation",
            run = function()
                local fixture = harness.new(modules)
                local candidate = harness.minimal("Task")
                local document, expected = fixture.document(candidate)
                local writer = assert(fixture.store.create_writer(TARGET, fixture.metadata()))
                fixture.controls.operations = {}
                local receipt = assert(fixture.store.publish(writer, document, temp("create")))
                A.equal(receipt.outcome, "published")
                A.equal(receipt.generation, 1)
                A.equal(receipt.event_count, 2)
                A.equal(receipt.auto_continue, true)
                A.equal(receipt.target_qualified, false)
                A.equal(fixture.controls.bytes(TARGET), expected)
                A.equal(fixture.controls.permissions(TARGET), 384)
                A.falsy(fixture.controls.exists(temp("create")))
                A.falsy(fixture.controls.exists(PREVIOUS))
                A.truthy(fixture.controls.exists(LOCK))
                local operations = fixture.controls.operations
                local create_index = assert(operation_index(operations, "create:" .. temp("create")))
                local flush_index = assert(operation_index(operations, "flush-file"))
                local publish_index = assert(operation_index(operations, "rename-no-replace"))
                local directory_index = assert(operation_index(
                    operations,
                    "flush-directory:/data"
                ))
                A.truthy(create_index < flush_index)
                A.truthy(flush_index < publish_index)
                A.truthy(publish_index < directory_index)
                A.raises(function() receipt.generation = 99 end, "cannot be modified")
                A.truthy(fixture.store.close_writer(writer))
                A.falsy(fixture.controls.exists(LOCK))
            end,
        },
        {
            name = "existing Context keeps one previous generation only inside replace window",
            run = function()
                local fixture, writer, _, _, document, expected = replacement_fixture()
                local receipt = assert(fixture.store.publish(writer, document, temp("replace")))
                A.equal(receipt.generation, 2)
                A.equal(fixture.controls.bytes(TARGET), expected)
                A.falsy(fixture.controls.exists(temp("replace")))
                A.falsy(fixture.controls.exists(PREVIOUS))
                local operations = fixture.controls.operations
                local temp_create = assert(operation_index(
                    operations,
                    "create:" .. temp("replace")
                ))
                local previous_create = assert(operation_index(
                    operations,
                    "create:" .. PREVIOUS
                ))
                local replace_index = assert(operation_index(operations, "replace"))
                local cleanup_index = assert(operation_index(operations, "delete:" .. PREVIOUS))
                A.truthy(temp_create < previous_create)
                A.truthy(previous_create < replace_index)
                A.truthy(replace_index < cleanup_index)
                A.equal(fixture.store.writer_status(writer).generation, 2)
                A.truthy(fixture.store.close_writer(writer))
            end,
        },
        {
            name = "write flush validation and replace failures preserve old generation",
            run = function()
                local fault_cases = {
                    {
                        id = "write",
                        enable = function(fixture) fixture.controls.faults.write = true end,
                        code = "InjectedWrite",
                    },
                    {
                        id = "flush",
                        enable = function(fixture) fixture.controls.faults.flush_file = true end,
                        code = "InjectedFlush",
                    },
                    {
                        id = "validation",
                        enable = function(fixture)
                            fixture.controls.faults.corrupt_after_write_close = true
                        end,
                        code = "ContextTemporaryMismatch",
                    },
                    {
                        id = "replace",
                        enable = function(fixture) fixture.controls.faults.replace = true end,
                        code = "InjectedReplace",
                    },
                }
                for _, case in ipairs(fault_cases) do
                    local fixture, writer, first, _, document = replacement_fixture()
                    local _, old_bytes = fixture.document(first)
                    case.enable(fixture)
                    local receipt, commit_error = fixture.store.publish(
                        writer,
                        document,
                        temp(case.id)
                    )
                    A.falsy(receipt, case.id)
                    A.equal(commit_error.code, case.code, case.id)
                    A.equal(fixture.controls.bytes(TARGET), old_bytes, case.id)
                    A.falsy(fixture.controls.exists(temp(case.id)), case.id)
                    A.falsy(fixture.controls.exists(PREVIOUS), case.id)
                    fixture.controls.faults = {}
                    A.truthy(fixture.store.close_writer(writer), case.id)
                end
            end,
        },
        {
            name = "external replacement makes writer stale before temporary creation",
            run = function()
                local fixture, writer, _, _, document = replacement_fixture()
                local external = harness.minimal("Task")
                external.header.updated_at = "2026-08-29T00:00:09Z"
                local _, external_bytes = fixture.document(external)
                fixture.controls.external_replace(TARGET, external_bytes)
                fixture.controls.operations = {}
                local receipt, commit_error = fixture.store.publish(
                    writer,
                    document,
                    temp("stale")
                )
                A.falsy(receipt)
                A.equal(commit_error.code, "TargetChanged")
                A.equal(fixture.controls.bytes(TARGET), external_bytes)
                A.falsy(fixture.controls.exists(temp("stale")))
                A.equal(fixture.store.writer_status(writer).status, "faulted")
                A.truthy(fixture.store.close_writer(writer))
            end,
        },
        {
            name = "post-replace directory failure retains recovery generation and faults writer",
            run = function()
                local fixture, writer, first, _, document, expected = replacement_fixture()
                local _, old_bytes = fixture.document(first)
                fixture.hooks.after.fs_replace = function(ok)
                    if ok then fixture.controls.faults.flush_directory = true end
                end
                local receipt, commit_error = fixture.store.publish(
                    writer,
                    document,
                    temp("unknown")
                )
                A.falsy(receipt)
                A.equal(commit_error.code, "ContextPublishUnknown")
                A.equal(fixture.controls.bytes(TARGET), expected)
                A.equal(fixture.controls.bytes(PREVIOUS), old_bytes)
                A.equal(fixture.store.writer_status(writer).status, "faulted")

                fixture.controls.faults.flush_directory = false
                fixture.hooks.after.fs_replace = nil
                A.truthy(fixture.store.close_writer(writer))
                local recovery_store = fixture.new_store()
                local recovered_writer, recovered = assert(recovery_store.open_writer(
                    TARGET,
                    fixture.metadata(200)
                ))
                A.equal(recovered.generation, 2)
                A.falsy(fixture.controls.exists(PREVIOUS))
                A.truthy(recovery_store.close_writer(recovered_writer))
            end,
        },
        {
            name = "missing or corrupt official restores the validated previous generation",
            run = function()
                for _, mode in ipairs({ "missing", "corrupt" }) do
                    local first = harness.minimal("Task")
                    local fixture = harness.new(modules)
                    local _, old_bytes = fixture.document(first)
                    fixture.controls.external_replace(PREVIOUS, old_bytes)
                    if mode == "corrupt" then
                        fixture.controls.external_replace(TARGET, "<broken>")
                    end
                    local writer, recovered = assert(fixture.store.open_writer(
                        TARGET,
                        fixture.metadata(300)
                    ))
                    A.equal(recovered.generation, 1, mode)
                    A.equal(fixture.controls.bytes(TARGET), old_bytes, mode)
                    A.falsy(fixture.controls.exists(PREVIOUS), mode)
                    A.truthy(fixture.store.close_writer(writer), mode)
                end
            end,
        },
        {
            name = "generation time name and durable Fact prefix cannot be rewritten",
            run = function()
                local mutations = {
                    {
                        id = "generation",
                        apply = function(value) value.generation = 3 end,
                        code = "ContextGeneration",
                    },
                    {
                        id = "time",
                        apply = function(value)
                            value.header.updated_at = "2026-08-29T00:00:01Z"
                        end,
                        code = "ContextGeneration",
                    },
                    {
                        id = "name",
                        apply = function(value) value.header.name = "Other" end,
                        code = "ContextNameMismatch",
                    },
                    {
                        id = "history",
                        apply = function(value) value.facts[2].fields.text = "rewritten" end,
                        code = "ContextHistoryRewrite",
                    },
                }
                for _, mutation in ipairs(mutations) do
                    local first = harness.minimal("Task")
                    local fixture = harness.new(modules, { [TARGET] = first })
                    local writer = assert(fixture.store.open_writer(TARGET, fixture.metadata()))
                    local second = harness.next_generation(first)
                    mutation.apply(second)
                    local document = fixture.document(second)
                    fixture.controls.operations = {}
                    local receipt, publish_error = fixture.store.publish(
                        writer,
                        document,
                        temp(mutation.id)
                    )
                    A.falsy(receipt, mutation.id)
                    A.equal(publish_error.code, mutation.code, mutation.id)
                    A.falsy(fixture.controls.exists(temp(mutation.id)), mutation.id)
                    A.truthy(fixture.store.close_writer(writer), mutation.id)
                end
            end,
        },
        {
            name = "intent without result reopens as blocked and is never auto-replayed",
            run = function()
                local fixture = harness.new(modules)
                local candidate = harness.unresolved("Task")
                local document = fixture.document(candidate)
                local writer = assert(fixture.store.create_writer(TARGET, fixture.metadata()))
                local receipt = assert(fixture.store.publish(
                    writer,
                    document,
                    temp("unknownop")
                ))
                A.equal(receipt.auto_continue, false)
                A.deep_equal(receipt.unresolved_operation_ids, { "operation-1" })
                A.deep_equal(receipt.unresolved_tool_call_ids, { "tool-1" })
                A.truthy(fixture.store.close_writer(writer))

                local reopened_writer, reopened = assert(fixture.store.open_writer(
                    TARGET,
                    fixture.metadata(400)
                ))
                A.equal(reopened.event_count, 5)
                A.deep_equal(reopened.recovery.unresolved_operation_ids, { "operation-1" })
                A.deep_equal(reopened.recovery.unresolved_tool_call_ids, { "tool-1" })
                A.equal(reopened.recovery.auto_continue, false)
                A.deep_equal(reopened.recovery.unknown_operation_ids, {})
                A.truthy(fixture.store.close_writer(reopened_writer))
            end,
        },
    },
}
