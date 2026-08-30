--[[
File: long_context_test.lua
Date: 2026-08-30
Author: WaterRun
Description: Benchmarks deterministic linear planning for a long Context.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()
local compact = assert(loadfile(YACA_TEST_ROOT .. "/src/compact.lua", "t", _ENV))()

local function append_event(facts, event_type, turn_id, fields)
    facts[#facts + 1] = {
        seq = #facts + 1,
        type = event_type,
        at = "2026-08-30T00:00:00Z",
        turn_id = turn_id,
        fields = fields,
        field_order = {},
        field_metadata = {},
    }
end

local function long_document(turn_count)
    local facts = {}
    for serial = 1, turn_count do
        local suffix = string.format("%04d", serial)
        local turn_id = "turn-" .. suffix
        local request_id = "request-" .. suffix
        append_event(facts, "turn_started", turn_id, {
            kind = "main",
            configGeneration = "config-1",
            modelSnapshot = "model-snapshot-long",
            permissionSnapshot = "permission-snapshot-1",
            promptSnapshot = "prompt-snapshot-1",
            toolRegistrySnapshot = "tool-registry-snapshot-1",
        })
        append_event(facts, "user_message", turn_id, {
            messageId = "user-message-" .. suffix,
            text = "long-context-message-" .. suffix,
            source = "composer",
        })
        append_event(facts, "model_request", turn_id, {
            requestId = request_id,
            purpose = "main",
            viewManifestRef = "view-long-old",
        })
        append_event(facts, "model_message", turn_id, {
            messageId = "assistant-message-" .. suffix,
            requestId = request_id,
            role = "assistant",
            status = "complete",
            body = "long-context-answer-" .. suffix,
        })
        append_event(facts, "turn_ended", turn_id, { outcome = "completed" })
    end
    return {
        generation = 700,
        event_count = #facts,
        facts = facts,
        model_view = {
            active_manifest = {
                digest = "view-long-old",
                first_event_seq = 1,
                last_event_seq = #facts,
            },
            compaction_records = {},
        },
    }
end

local function fast_digest(bytes)
    local first, second = 2166136261, 2246822519
    for index = 1, #bytes do
        local byte = bytes:byte(index)
        first = ((first ~ byte) * 16777619) & 0xffffffff
        second = (second + byte + ((second << 6) & 0xffffffff)
            + (second >> 2)) & 0xffffffff
    end
    return string.format("perf:%08x%08x:%d", first, second, #bytes)
end

local function plan_signature(plan)
    local ranges = {}
    for index, range in ipairs(plan.tail_ranges) do
        ranges[index] = tostring(range.first) .. "-" .. tostring(range.last)
    end
    return table.concat({
        plan.decision,
        tostring(plan.source_first_seq),
        tostring(plan.source_last_seq),
        plan.source_digest,
        table.concat(ranges, ","),
        tostring(plan.source_tokens),
        tostring(plan.tail_tokens),
    }, "|")
end

return {
    name = "performance/long-context",
    cases = {
        {
            name = "twenty thousand events rebuild deterministically without atomic splits",
            run = function()
                local source = long_document(4000)
                A.equal(#source.facts, 20000)
                local first_fact, last_fact = source.facts[1], source.facts[#source.facts]
                local old_manifest = source.model_view.active_manifest.digest
                local estimate_calls, digest_calls, model_calls, journal_calls = 0, 0, 0, 0
                local service = assert(compact.new({
                    safety = { digest = function(bytes)
                        digest_calls = digest_calls + 1
                        return fast_digest(bytes)
                    end },
                    estimator = { estimate = function(bytes)
                        estimate_calls = estimate_calls + 1
                        return (#bytes + 63) // 64
                    end },
                    clock = { now = function() return 0 end },
                    model = {
                        start = function()
                            model_calls = model_calls + 1
                            return "unexpected"
                        end,
                        cancel = function() return { outcome = "cancelled" } end,
                    },
                    journal = {
                        commit_intent = function() journal_calls = journal_calls + 1 end,
                        commit_response = function() journal_calls = journal_calls + 1 end,
                        commit_rejection = function() journal_calls = journal_calls + 1 end,
                        publish = function() journal_calls = journal_calls + 1 end,
                        commit_correction = function() journal_calls = journal_calls + 1 end,
                    },
                }, {
                    manifest = {
                        snapshot_id = "manifest-compaction-long-v1",
                        builder_algorithm = "structured-prefix-v1",
                        summary_schema = "structured-summary-v1",
                        maximum_events = 24000,
                        maximum_groups = 5000,
                        maximum_input_bytes = 16 * 1024 * 1024,
                        maximum_summary_bytes = 64 * 1024,
                        maximum_summary_tokens = 2048,
                        maximum_view_tokens = 65536,
                        maximum_attempts = 2,
                        active_time_ms = 30000,
                        failure_threshold = 3,
                        failure_cooldown_ms = 60000,
                        trigger_numerator = 3,
                        trigger_denominator = 4,
                        reserve_tokens = 512,
                        minimum_benefit_tokens = 256,
                    },
                    maximum_identifier_bytes = 128,
                    initial_serial = 0,
                }))
                local input = {
                    mode = "automatic",
                    document = source,
                    expected_context_generation = source.generation,
                    expected_manifest_digest = old_manifest,
                    context_digest = fast_digest("long-context-generation-700"),
                    config_snapshot = "config-snapshot-long",
                    model_snapshot = {
                        id = "main-model-long",
                        digest = "model-snapshot-long",
                        window_tokens = 65536,
                        maximum_output_tokens = 2048,
                    },
                    prompt_bundle_digest = "prompt-bundle-long",
                    prompt_tokens = 1024,
                    tool_schema_tokens = 512,
                    control_schema_tokens = 256,
                    main_state = "Idle",
                    active_view = {
                        manifest_digest = old_manifest,
                        estimated_tokens = 60000,
                        builder_algorithm = "structured-prefix-v1",
                        summary_id = false,
                        included_ranges = { { first = 1, last = #source.facts } },
                    },
                    corrections = {},
                }

                local started_at = os.clock()
                local first = assert(service:plan(input))
                local first_elapsed = os.clock() - started_at
                A.equal(first.decision, "compact")
                A.equal(#first.groups, 4000)
                A.equal(estimate_calls, #source.facts)
                A.equal(digest_calls, 1)
                for _, group in ipairs(first.groups) do
                    A.equal(#group.sequences, 5)
                    if group.first <= first.source_last_seq then
                        A.truthy(group.last <= first.source_last_seq)
                    else
                        A.truthy(group.first > first.source_last_seq)
                    end
                end

                started_at = os.clock()
                local second_plan = assert(service:plan(input))
                local second_elapsed = os.clock() - started_at
                A.equal(plan_signature(second_plan), plan_signature(first))
                A.equal(estimate_calls, #source.facts * 2)
                A.equal(digest_calls, 2)
                A.equal(model_calls, 0)
                A.equal(journal_calls, 0)
                A.truthy(first_elapsed < 12, "first long-context plan exceeded 12 seconds")
                A.truthy(second_elapsed < 12, "second long-context plan exceeded 12 seconds")

                A.equal(#source.facts, 20000)
                A.equal(source.facts[1], first_fact)
                A.equal(source.facts[#source.facts], last_fact)
                A.equal(source.model_view.active_manifest.digest, old_manifest)
                A.equal(source.event_count, 20000)
            end,
        },
    },
}
