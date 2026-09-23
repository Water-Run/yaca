--[[
Author: WaterRun
Date: 2026-09-23
File: context_commit_test.lua
Description: Verifies full-XML publication, recovery, and injected commit failures.
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
local PREVIOUS = TARGET .. ".yaca-prev"

--Supplies temp behavior required by this suite.
--@param id string|integer Identity selected for the fake operation.
--@return string observed temp value observed by the scenario assertion.
local function temp(id)
    return TARGET .. ".yaca-tmp-" .. id
end

--Supplies operation index behavior required by this suite.
--@param operations table Queued operations supplied to the fixture.
--@param expected any Expected value used by the assertion.
--@return any|nil observed operation index value observed by the scenario assertion.
local function operation_index(operations, expected)
    for index, operation in ipairs(operations) do
        if operation == expected then return index end
    end
    return nil
end

--Supplies replacement fixture behavior required by this suite.
--@param none No arguments; this closure uses its captured fixture state.
--@return any observed replacement fixture value observed by the scenario assertion.
--@return any secondary2 Additional status or structured error from the fixture operation.
--@return any secondary3 Additional status or structured error from the fixture operation.
--@return any secondary4 Additional status or structured error from the fixture operation.
--@return any secondary5 Context document returned by the fixture.
--@return any secondary6 Additional status or structured error from the fixture operation.
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
            name = "first Ask can publish and reopen an empty view with newly appended facts",
            -- Exercise empty Context creation, first Ask admission and reopen with FAT-style close timestamps.
            --@param none No arguments.
            --@return nil Assertions complete without returning a value.
            --@effect Mutates only the isolated in-memory Context fixture.
            run = function()
                local first = harness.minimal("Task")
                local events = first.facts
                first.facts = {}
                first.model_view.active_manifest.first_event_seq = 0
                first.model_view.active_manifest.last_event_seq = 0
                local f = harness.new(modules)
                f.controls.close_updates_modified = true
                local writer = assert(f.store.create_writer(TARGET, f.metadata()))
                local initial = f.document(first)
                assert(f.store.publish(writer, initial, temp("empty")))
                for _, event in ipairs(events) do event.turn_id, event.at = "ask-1", nil end
                events[1].fields.kind = "ask"
                events[3] = { seq = 3, type = "model_request", turn_id = "ask-1", fields = {
                    requestId = "ask-1:request:1", purpose = "ask",
                    viewManifestRef = first.model_view.active_manifest.digest,
                } }
                local next_document = assert(f.schema.append_events(initial, {
                    updated_at = "2026-08-29T00:00:02Z", events = events,
                }))
                f.register_document(next_document)
                assert(f.store.publish(writer, next_document, temp("ask")))
                assert(f.store.close_writer(writer))
                local reopened, document = assert(f.store.open_writer(TARGET, f.metadata()))
                A.equal(document.event_count, 3)
                A.equal(document.recovery.model_view_status, "current")
                A.equal(document.facts[1].fields.kind, "ask")
                A.equal(document.recovery.unfinished_turn_ids[1], "ask-1")
                assert(f.store.close_writer(reopened))
            end,
        },
        {
            name = "capacity rejects new work without IO while accepted calls and terminal still publish",
            --Verifies capacity rejects new work without IO while accepted calls and terminal still publish.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify capacity rejects new work without IO while accepted calls and terminal still publish.
            run = function()
                local first = harness.next_generation(harness.minimal("Task"), {
                    event = { type = "model_request", turn_id = "turn-1", fields = {
                        requestId = "request-1", purpose = "main", viewManifestRef = "sha256:view-manifest",
                    } },
                })
                first.generation = 1
                local fixture = harness.new(modules, nil, {
                    maximum_bytes = 8 * 1024 * 1024, maximum_total_text_bytes = 4 * 1024 * 1024,
                    maximum_events = 40,
                    settlement_reserve = { model_calls = 2, model_bytes = 4096,
                        message_bytes = 4096, result_bytes = 32768 },
                })
                local writer = assert(fixture.store.create_writer(TARGET, fixture.metadata()))
                local current = first
                local document = fixture.document(current)
                assert(fixture.store.publish(writer, document, temp("initial")))
                local serial = 0
                --Records the publish effect observed by the 'capacity rejects new work without IO while accepted calls and terminal still publish' case.
                --@param event table Event delivered to the fake runtime.
                --@return any observed Publication receipt returned by the fixture.
                --@return any secondary2 Failure diagnostic returned by the fixture.
                local function publish(event)
                    serial = serial + 1
                    local candidate = harness.next_generation(current, {
                        updated_at = string.format("2026-08-29T00:%02d:%02dZ", serial // 60 + 1, serial % 60),
                        event = event,
                    })
                    local next_document = fixture.document(candidate)
                    fixture.controls.operations = {}
                    local receipt, err = fixture.store.publish(writer, next_document, temp(tostring(serial)))
                    if receipt then current, document = candidate, next_document end
                    return receipt, err
                end
                local rejected
                for _ = 1, 40 do
                    local receipt, err = publish({ type = "warning", fields = {
                        errorId = "CapacityProbe", summary = "metadata may not consume pending results",
                    } })
                    if not receipt then
                        A.equal(err.code, "ContextCapacity")
                        A.equal(err.publication_started, false)
                        A.equal(#fixture.controls.operations, 0)
                        A.equal(fixture.store.writer_status(writer).status, "active")
                        rejected = true
                        break
                    end
                end
                A.truthy(rejected)
                -- Reopen before settlement to prove that reservations derive
                -- from facts, with no lost in-memory capacity token.
                assert(fixture.store.close_writer(writer))
                fixture.store = fixture.new_store()
                writer = assert(fixture.store.open_writer(TARGET, fixture.metadata()))
                assert(publish({ type = "model_message", turn_id = "turn-1", fields = {
                    messageId = "reply-1", requestId = "request-1", role = "assistant", status = "complete",
                    body = string.rep("&", 4096), rawBytes = "4096", digest = "sha256:reply",
                } }))
                for index = 1, 2 do
                    assert(publish({ type = "tool_call", turn_id = "turn-1", fields = {
                        toolCallId = "call-" .. index, requestId = "request-1", name = "write",
                        canonicalArguments = "{}",
                    } }))
                end
                for index = 1, 2 do
                    assert(publish({ type = "operation_intent", turn_id = "turn-1", fields = {
                        operationId = "op-" .. index, toolCallId = "call-" .. index, kind = "write",
                        targetIdentity = "sha256:target", expectedDigest = "sha256:expected",
                    } }))
                    assert(publish({ type = "operation_result", turn_id = "turn-1", fields = {
                        operationId = "op-" .. index, status = "ok", evidence = "sha256:effect",
                    } }))
                    assert(publish({ type = "tool_result", turn_id = "turn-1", fields = {
                        toolCallId = "call-" .. index, status = "ok", body = string.rep("&", 32768),
                        truncated = "false", rawBytes = "32768",
                    } }))
                end
                assert(publish({ type = "turn_ended", turn_id = "turn-1", fields = {
                    outcome = "budget_exhausted", reason = "ContextCapacity",
                } }))
                A.equal(#document.recovery.unresolved_operation_ids, 0)
                A.equal(#document.recovery.unresolved_tool_call_ids, 0)
                A.equal(#document.recovery.unfinished_turn_ids, 0)
                assert(fixture.store.close_writer(writer))
            end,
        },
        {
            name = "active writer inspection is read-only and stops after external changes",
            --Verifies active writer inspection is read-only and stops after external changes.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify active writer inspection is read-only and stops after external changes.
            run = function()
                for _, mutation in ipairs({ "replace", "write", "delete", "during-read" }) do
                    local fixture, writer = replacement_fixture()
                    local before = fixture.controls.bytes(TARGET)
                    local current = assert(fixture.store.verify_writer(writer))
                    A.equal(current.path, TARGET)
                    A.equal(current.generation, 1)
                    A.equal(fixture.controls.bytes(TARGET), before)
                    local operations = table.concat(fixture.controls.operations, "|")
                    A.falsy(operations:find("create:", 1, true))
                    A.falsy(operations:find("rename", 1, true))
                    A.falsy(operations:find("flush", 1, true))
                    if mutation == "replace" then
                        fixture.controls.external_replace(TARGET, before)
                    elseif mutation == "write" then
                        fixture.controls.external_write(TARGET, before)
                    elseif mutation == "delete" then
                        fixture.controls.external_delete(TARGET)
                    else
                        --Supplies fs close behavior required by the 'active writer inspection is read-only and stops after external changes' case.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return nil No value; assertions verify active writer inspection is read-only and stops after external changes.
                        fixture.hooks.after.fs_close = function()
                            fixture.controls.external_replace(TARGET, before)
                        end
                    end
                    local rejected, reject_error = fixture.store.verify_writer(writer)
                    A.falsy(rejected)
                    A.equal(reject_error.code, "TargetChanged")
                    A.equal(fixture.store.writer_status(writer).status, "faulted")
                    fixture.hooks.after.fs_close = nil
                    fixture.controls.external_replace(TARGET, before)
                    A.falsy(fixture.store.verify_writer(writer))
                    A.truthy(fixture.store.close_writer(writer))
                    A.falsy(fixture.controls.exists(LOCK))
                end
            end,
        },
        {
            name = "new Context publishes no-replace only after exact validation",
            --Verifies new Context publishes no-replace only after exact validation.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify new Context publishes no-replace only after exact validation.
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
                A.equal(receipt.auto_continue, false)
                A.deep_equal(receipt.unfinished_turn_ids, { "turn-1" })
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
                --Executes the action expected to raise in the 'new Context publishes no-replace only after exact validation' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify new Context publishes no-replace only after exact validation.
                A.raises(function() receipt.generation = 99 end, "cannot be modified")
                A.truthy(fixture.store.close_writer(writer))
                A.falsy(fixture.controls.exists(LOCK))
            end,
        },
        {
            name = "existing Context keeps one previous generation only inside replace window",
            --Verifies existing Context keeps one previous generation only inside replace window.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify existing Context keeps one previous generation only inside replace window.
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
            --Verifies write flush validation and replace failures preserve old generation.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify write flush validation and replace failures preserve old generation.
            run = function()
                local fault_cases = {
                    {
                        id = "write",
                        --Supplies enable behavior required by the 'write flush validation and replace failures preserve old generation' case.
                        --@param fixture table Test fixture state shared by this helper.
                        --@return nil No value; assertions verify write flush validation and replace failures preserve old generation.
                        enable = function(fixture) fixture.controls.faults.write = true end,
                        code = "InjectedWrite",
                    },
                    {
                        id = "flush",
                        --Supplies enable behavior required by the 'write flush validation and replace failures preserve old generation' case.
                        --@param fixture table Test fixture state shared by this helper.
                        --@return nil No value; assertions verify write flush validation and replace failures preserve old generation.
                        enable = function(fixture) fixture.controls.faults.flush_file = true end,
                        code = "InjectedFlush",
                    },
                    {
                        id = "validation",
                        --Supplies enable behavior required by the 'write flush validation and replace failures preserve old generation' case.
                        --@param fixture table Test fixture state shared by this helper.
                        --@return nil No value; assertions verify write flush validation and replace failures preserve old generation.
                        enable = function(fixture)
                            fixture.controls.faults.corrupt_after_write_close = true
                        end,
                        code = "ContextTemporaryMismatch",
                    },
                    {
                        id = "replace",
                        --Supplies enable behavior required by the 'write flush validation and replace failures preserve old generation' case.
                        --@param fixture table Test fixture state shared by this helper.
                        --@return nil No value; assertions verify write flush validation and replace failures preserve old generation.
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
            --Verifies external replacement makes writer stale before temporary creation.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify external replacement makes writer stale before temporary creation.
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
            --Verifies post-replace directory failure retains recovery generation and faults writer.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify post-replace directory failure retains recovery generation and faults writer.
            run = function()
                local fixture, writer, first, _, document, expected = replacement_fixture()
                local _, old_bytes = fixture.document(first)
                --Supplies fs replace behavior required by the 'post-replace directory failure retains recovery generation and faults writer' case.
                --@param ok boolean Success status returned by the fake operation.
                --@return nil No value; assertions verify post-replace directory failure retains recovery generation and faults writer.
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
            --Verifies missing or corrupt official restores the validated previous generation.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify missing or corrupt official restores the validated previous generation.
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
            --Verifies generation time name and durable Fact prefix cannot be rewritten.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify generation time name and durable Fact prefix cannot be rewritten.
            run = function()
                local mutations = {
                    {
                        id = "generation",
                        --Supplies apply behavior required by the 'generation time name and durable Fact prefix cannot be rewritten' case.
                        --@param value any Candidate whose acceptance or transformation the test checks.
                        --@return nil No value; assertions verify generation time name and durable Fact prefix cannot be rewritten.
                        apply = function(value) value.generation = 3 end,
                        code = "ContextGeneration",
                    },
                    {
                        id = "time",
                        --Supplies apply behavior required by the 'generation time name and durable Fact prefix cannot be rewritten' case.
                        --@param value any Candidate whose acceptance or transformation the test checks.
                        --@return nil No value; assertions verify generation time name and durable Fact prefix cannot be rewritten.
                        apply = function(value)
                            value.header.updated_at = "2026-08-29T00:00:01Z"
                        end,
                        code = "ContextGeneration",
                    },
                    {
                        id = "name",
                        --Supplies apply behavior required by the 'generation time name and durable Fact prefix cannot be rewritten' case.
                        --@param value any Candidate whose acceptance or transformation the test checks.
                        --@return nil No value; assertions verify generation time name and durable Fact prefix cannot be rewritten.
                        apply = function(value) value.header.name = "Other" end,
                        code = "ContextNameMismatch",
                    },
                    {
                        id = "history",
                        --Supplies apply behavior required by the 'generation time name and durable Fact prefix cannot be rewritten' case.
                        --@param value any Candidate whose acceptance or transformation the test checks.
                        --@return nil No value; assertions verify generation time name and durable Fact prefix cannot be rewritten.
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
            --Verifies intent without result reopens as blocked and is never auto-replayed.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify intent without result reopens as blocked and is never auto-replayed.
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
