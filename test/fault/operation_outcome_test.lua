--[[
File: operation_outcome_test.lua
Date: 2026-08-29
Author: WaterRun
Description: Verifies durable operation generations, fail-stop, and no replay.
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

local function temp(id)
    return TARGET .. ".yaca-tmp-" .. id
end

local function append(candidate, event_type, fields)
    candidate.facts[#candidate.facts + 1] = {
        seq = #candidate.facts + 1,
        type = event_type,
        at = "2026-08-29T00:00:01Z",
        turn_id = "turn-1",
        fields = fields,
    }
    candidate.model_view.active_manifest.last_event_seq = #candidate.facts
end

local function accepted_candidate()
    local candidate = harness.minimal("Task")
    append(candidate, "model_request", {
        requestId = "request-1",
        purpose = "main",
        viewManifestRef = "sha256:view-manifest",
    })
    append(candidate, "tool_call", {
        toolCallId = "tool-1",
        requestId = "request-1",
        name = "exec",
        canonicalArguments = '{"command":"true"}',
        providerCallId = "provider-1",
    })
    return candidate
end

local function hash_port()
    return {
        sha256_start = function() return { parts = {} } end,
        sha256_update = function(handle, bytes)
            handle.parts[#handle.parts + 1] = bytes
            return true
        end,
        sha256_finish = function(handle)
            return modules.sha256.digest(table.concat(handle.parts))
        end,
        sha256_close = function() return true end,
    }
end

local function operation_fixture(settings)
    settings = settings or {}
    local safety = assert(load_module("safety", {}).new(hash_port(), {
        maximum_hash_chunk_bytes = 11,
        minimum_scannable_secret_bytes = 8,
    }))
    local journal = { intents = {}, results = {}, calls = {} }
    function journal.commit_intent(record, digest)
        journal.calls[#journal.calls + 1] = "intent:" .. record.operation_id
        journal.intents[#journal.intents + 1] = record
        if settings.intent_unknown then
            return false, { code = "ContextPublishUnknown", message = "intent uncertain" }
        end
        if settings.intent_failure then
            return false, { code = "DiskFull", message = "intent not written" }
        end
        return true, settings.bad_intent_receipt and "wrong" or digest
    end
    function journal.commit_result(record, digest)
        journal.calls[#journal.calls + 1] = "result:" .. record.operation_id
        journal.results[#journal.results + 1] = record
        if settings.result_failure then
            return false, { code = "DiskFull", message = "result not durable" }
        end
        return true, settings.bad_result_receipt and "wrong" or digest
    end
    local operations = assert(load_module("context", {}).new_operation_service({
        safety = safety,
        journal = journal,
    }, {
        maximum_identifier_bytes = 128,
        maximum_evidence_bytes = 131072,
        unresolved_operation_ids = settings.unresolved or {},
    }))
    return operations, journal
end

local function intent(id)
    return {
        operation_id = id,
        tool_call_id = "tool-" .. id,
        kind = "exec",
        target_identity = "target-digest-" .. id,
        expected_digest = "expected-digest-" .. id,
        call_digest = "call-digest-" .. id,
    }
end

local function result(status)
    status = status or "ok"
    return {
        status = status,
        evidence = "canonical-result:0123456789abcdef",
        tool_status = status,
        tool_body = '{"outcome":"success"}',
        tool_truncated = false,
        tool_raw_bytes = 21,
        tool_digest = "body-digest",
    }
end

return {
    name = "fault/operation-outcome",
    cases = {
        {
            name = "intent and paired result are separate durable full-XML generations",
            run = function()
                local candidate = accepted_candidate()
                local fixture = harness.new(modules, { [TARGET] = candidate })
                local writer, document = assert(fixture.store.open_writer(
                    TARGET,
                    fixture.metadata()
                ))
                local intent_document = assert(modules.context.operation_document(
                    fixture.schema,
                    document,
                    {
                        kind = "begin",
                        updated_at = "2026-08-29T00:00:02Z",
                        view_manifest_digest = "sha256:view-operation-intent",
                        operation_id = "operation-1",
                        tool_call_id = "tool-1",
                        operation_kind = "exec",
                        target_identity = "workspace-object",
                        expected_digest = "sha256:opaque-call",
                    }
                ))
                A.equal(intent_document.generation, 2)
                A.deep_equal(intent_document.recovery.unresolved_operation_ids, {
                    "operation-1",
                })
                A.deep_equal(intent_document.recovery.unresolved_tool_call_ids, { "tool-1" })
                A.falsy(intent_document.recovery.auto_continue)
                fixture.register_document(intent_document)
                local intent_receipt, intent_publish_error = fixture.store.publish(
                    writer,
                    intent_document,
                    temp("intent")
                )
                A.truthy(intent_receipt, intent_publish_error and intent_publish_error.code)
                A.deep_equal(intent_receipt.unresolved_operation_ids, { "operation-1" })

                local body = '{"outcome":"success","result_digest":"abc"}'
                local result_document = assert(modules.context.operation_document(
                    fixture.schema,
                    intent_document,
                    {
                        kind = "finish",
                        updated_at = "2026-08-29T00:00:03Z",
                        view_manifest_digest = "sha256:view-operation-result",
                        operation_id = "operation-1",
                        tool_call_id = "tool-1",
                        status = "ok",
                        evidence = "canonical-result:abc",
                        tool_status = "ok",
                        tool_body = body,
                        tool_truncated = false,
                        tool_raw_bytes = #body,
                        tool_digest = "sha256:tool-body",
                    }
                ))
                A.equal(result_document.generation, 3)
                A.deep_equal(result_document.recovery.unresolved_operation_ids, {})
                A.deep_equal(result_document.recovery.unresolved_tool_call_ids, {})
                A.truthy(result_document.recovery.auto_continue)
                fixture.register_document(result_document)
                local receipt = assert(fixture.store.publish(
                    writer,
                    result_document,
                    temp("result")
                ))
                A.truthy(receipt.auto_continue)
                A.truthy(fixture.store.close_writer(writer))

                local reopened_writer, reopened = assert(fixture.store.open_writer(
                    TARGET,
                    fixture.metadata(200)
                ))
                A.equal(reopened.generation, 3)
                A.equal(reopened.facts[5].type, "operation_intent")
                A.equal(reopened.facts[7].type, "operation_result")
                A.equal(reopened.facts[8].type, "tool_result")
                A.deep_equal(reopened.recovery.unresolved_operation_ids, {})
                A.truthy(fixture.store.close_writer(reopened_writer))
            end,
        },
        {
            name = "result durability failure is fail-stop and cannot replay its operation id",
            run = function()
                local operations, journal = operation_fixture({ result_failure = true })
                local handle, digest = assert(operations.begin(intent("one")))
                A.truthy(digest:match("^[0-9a-f]+$"))
                local committed, commit_error = operations.finish(handle, result())
                A.falsy(committed)
                A.equal(commit_error.code, "OperationResultDurabilityUnknown")
                A.truthy(operations.status().blocked)
                A.falsy(operations.status().auto_replay)
                local second, blocked_error = operations.begin(intent("two"))
                A.falsy(second)
                A.equal(blocked_error.code, "OperationBarrierBlocked")
                local replay, replay_error = operations.finish(handle, result())
                A.falsy(replay)
                A.equal(replay_error.code, "InvalidOperationHandle")
                A.deep_equal(journal.calls, { "intent:one", "result:one" })
            end,
        },
        {
            name = "ambiguous intent and recovered unresolved ids block without auto-execution",
            run = function()
                local uncertain, journal = operation_fixture({ intent_unknown = true })
                local handle, intent_error = uncertain.begin(intent("uncertain"))
                A.falsy(handle)
                A.equal(intent_error.code, "ContextPublishUnknown")
                A.truthy(uncertain.status().blocked)
                A.deep_equal(journal.calls, { "intent:uncertain" })
                local retry, retry_error = uncertain.begin(intent("new-id"))
                A.falsy(retry)
                A.equal(retry_error.code, "OperationBarrierBlocked")

                local recovered, recovered_journal = operation_fixture({
                    unresolved = { "operation-from-crash" },
                })
                local status = recovered.status()
                A.truthy(status.blocked)
                A.deep_equal(status.unresolved_operation_ids, {
                    "operation-from-crash",
                })
                A.falsy(status.auto_replay)
                local started, recovery_error = recovered.begin(intent("fresh"))
                A.falsy(started)
                A.equal(recovery_error.code, "OperationBarrierBlocked")
                A.deep_equal(recovered_journal.calls, {})
            end,
        },
        {
            name = "ordinary pre-intent failure permits only a fresh operation identity",
            run = function()
                local operations, journal = operation_fixture({ intent_failure = true })
                local handle, write_error = operations.begin(intent("not-written"))
                A.falsy(handle)
                A.equal(write_error.code, "DiskFull")
                A.falsy(operations.status().blocked)
                local repeated, repeated_error = operations.begin(intent("not-written"))
                A.falsy(repeated)
                A.equal(repeated_error.code, "InvalidOperationIntent")
                A.deep_equal(journal.calls, { "intent:not-written" })
            end,
        },
    },
}
