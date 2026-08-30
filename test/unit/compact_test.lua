--[[
File: compact_test.lua
Date: 2026-08-30
Author: WaterRun
Description: Verifies lossless-facts structured ModelView compaction.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()
local sha256 = assert(loadfile(
    YACA_TEST_ROOT .. "/test/support/sha256_reference.lua",
    "t",
    _ENV
))()
local compact = assert(loadfile(YACA_TEST_ROOT .. "/src/compact.lua", "t", _ENV))()

local function copy(values)
    local result = {}
    for key, value in pairs(values or {}) do result[key] = value end
    return result
end

local function options(overrides, initial_automatic_failure_count)
    local manifest = {
        snapshot_id = "manifest-compaction-v1",
        builder_algorithm = "structured-prefix-v1",
        summary_schema = "structured-summary-v1",
        maximum_events = 4096,
        maximum_groups = 2048,
        maximum_input_bytes = 1024 * 1024,
        maximum_summary_bytes = 8192,
        maximum_summary_tokens = 80,
        maximum_view_tokens = 512,
        maximum_attempts = 2,
        active_time_ms = 1000,
        failure_threshold = 3,
        failure_cooldown_ms = 5000,
        trigger_numerator = 3,
        trigger_denominator = 4,
        reserve_tokens = 8,
        minimum_benefit_tokens = 10,
    }
    for key, value in pairs(overrides or {}) do manifest[key] = value end
    return {
        manifest = manifest,
        maximum_identifier_bytes = 128,
        initial_serial = 40,
        initial_automatic_failure_count = initial_automatic_failure_count or 0,
    }
end

local function append_event(facts, event_type, turn_id, fields)
    local order, metadata = {}, {}
    for name, value in pairs(fields) do
        order[#order + 1] = name
        metadata[name] = {
            representation = "text",
            raw_bytes = #value,
            digest = false,
        }
    end
    table.sort(order)
    facts[#facts + 1] = {
        seq = #facts + 1,
        type = event_type,
        at = "2026-08-30T00:00:00Z",
        turn_id = turn_id,
        fields = fields,
        field_order = order,
        field_metadata = metadata,
    }
end

local function append_turn(facts, serial, settings)
    settings = settings or {}
    local turn_id = "turn-" .. tostring(serial)
    local request_id = "request-" .. tostring(serial)
    local payload = settings.payload or ("message-" .. tostring(serial))
    append_event(facts, "turn_started", turn_id, {
        kind = "main",
        configGeneration = "config-1",
        modelSnapshot = "model-snapshot-1",
        permissionSnapshot = "permission-snapshot-1",
        promptSnapshot = "prompt-snapshot-1",
        toolRegistrySnapshot = "tools-snapshot-1",
    })
    append_event(facts, "user_message", turn_id, {
        messageId = "user-message-" .. tostring(serial),
        text = payload,
        source = "composer",
    })
    append_event(facts, "model_request", turn_id, {
        requestId = request_id,
        purpose = "main",
        viewManifestRef = "view-old",
    })
    if settings.tool then
        local call_id = "tool-call-" .. tostring(serial)
        append_event(facts, "tool_call", turn_id, {
            toolCallId = call_id,
            requestId = request_id,
            name = "read",
            canonicalArguments = settings.tool_payload or "{}",
        })
        if not settings.unpaired_tool then
            append_event(facts, "tool_result", turn_id, {
                toolCallId = call_id,
                status = "ok",
                body = "tool-result-" .. tostring(serial),
                truncated = "false",
            })
        end
    end
    append_event(facts, "model_message", turn_id, {
        messageId = "assistant-message-" .. tostring(serial),
        requestId = request_id,
        role = "assistant",
        status = "complete",
        body = "answer-" .. payload,
    })
    if not settings.active then
        append_event(facts, "turn_ended", turn_id, { outcome = "completed" })
    end
end

local function document(turn_count, settings_by_turn)
    local facts = {}
    for serial = 1, turn_count do
        append_turn(facts, serial, settings_by_turn and settings_by_turn[serial])
    end
    return {
        generation = 10,
        event_count = #facts,
        facts = facts,
        model_view = {
            active_manifest = {
                digest = "view-old",
                first_event_seq = 1,
                last_event_seq = #facts,
            },
            compaction_records = {},
        },
    }
end

local function fixture(settings, manifest_overrides, source_document)
    settings = settings or {}
    source_document = source_document or document(6)
    local generation = source_document.generation
    local manifest_digest = source_document.model_view.active_manifest.digest
    local now = 0
    local log, starts, cancel_calls, publications = {}, {}, {}, {}
    local journal_records = {}
    local digest_calls, estimate_calls = 0, 0
    local old_manifest_at_publish

    local function digest(bytes)
        digest_calls = digest_calls + 1
        if settings.fail_digest_at == digest_calls then return nil, "digest-fault" end
        return "sha256:" .. sha256.hex(bytes)
    end

    local function estimate(bytes)
        estimate_calls = estimate_calls + 1
        if settings.fail_estimate_at == estimate_calls then return nil, "estimate-fault" end
        local bytes_per_token = settings.bytes_per_token or 32
        if #bytes == 0 then return 0 end
        return (#bytes + bytes_per_token - 1) // bytes_per_token
    end

    local function journal_commit(method, binding, publishing)
        log[#log + 1] = "journal:" .. method .. ":" .. binding.kind
        journal_records[#journal_records + 1] = { method = method, binding = binding }
        if settings.fail_journal_method == method then return false, nil end
        local previous = generation
        if settings.bad_receipt_method == method then
            return true, {
                binding = {},
                previous_context_generation = previous,
                context_generation = previous + 1,
                active_manifest_digest = manifest_digest,
            }
        end
        generation = generation + 1
        local receipt = {
            binding = binding,
            previous_context_generation = previous,
            context_generation = generation,
        }
        if publishing then
            old_manifest_at_publish = manifest_digest
            publications[#publications + 1] = binding
            receipt.previous_manifest_digest = manifest_digest
            receipt.published_manifest_digest = binding.manifest.digest
            manifest_digest = binding.manifest.digest
        else
            receipt.active_manifest_digest = manifest_digest
        end
        return true, receipt
    end

    local journal = {
        commit_intent = function(binding)
            return journal_commit("commit_intent", binding, false)
        end,
        commit_response = function(binding)
            return journal_commit("commit_response", binding, false)
        end,
        commit_rejection = function(binding)
            return journal_commit("commit_rejection", binding, false)
        end,
        publish = function(binding)
            return journal_commit("publish", binding, true)
        end,
        commit_correction = function(binding)
            return journal_commit("commit_correction", binding, false)
        end,
    }
    local model = {
        start = function(specification)
            starts[#starts + 1] = specification
            log[#log + 1] = "model:start:" .. specification.request_id
            if settings.fail_model_start then return nil, "model-start-fault" end
            return "handle:" .. specification.request_id
        end,
        cancel = function(handle, reason)
            cancel_calls[#cancel_calls + 1] = { handle = handle, reason = reason }
            log[#log + 1] = "model:cancel:" .. tostring(handle)
            return settings.cancel_result or { outcome = "cancelled" }
        end,
    }
    local service, create_error = compact.new({
        safety = { digest = digest },
        estimator = { estimate = estimate },
        clock = { now = function() return now end },
        model = model,
        journal = journal,
    }, options(manifest_overrides, settings.initial_automatic_failure_count))
    A.truthy(service, create_error and create_error.code)
    return {
        service = service,
        document = source_document,
        log = log,
        starts = starts,
        cancel_calls = cancel_calls,
        publications = publications,
        journal_records = journal_records,
        digest = digest,
        generation = function() return generation end,
        manifest = function() return manifest_digest end,
        old_manifest_at_publish = function() return old_manifest_at_publish end,
        advance = function(delta) now = now + delta end,
    }
end

local function input_for(instance, overrides)
    overrides = overrides or {}
    local source = overrides.document or instance.document
    local active_view = false
    if overrides.active_estimated_tokens then
        active_view = {
            manifest_digest = source.model_view.active_manifest.digest,
            estimated_tokens = overrides.active_estimated_tokens,
            builder_algorithm = "structured-prefix-v1",
            summary_id = overrides.summary_id or false,
            included_ranges = { { first = 1, last = #source.facts } },
        }
    end
    if overrides.active_view ~= nil then active_view = overrides.active_view end
    return {
        mode = overrides.mode or "automatic",
        document = source,
        expected_context_generation = source.generation,
        expected_manifest_digest = source.model_view.active_manifest.digest,
        context_digest = "sha256:" .. sha256.hex(
            "context:" .. tostring(source.generation) .. ":" .. tostring(#source.facts)
        ),
        config_snapshot = "config-snapshot-1",
        model_snapshot = overrides.model_snapshot or {
            id = "main-model",
            digest = "model-snapshot-1",
            window_tokens = 512,
            maximum_output_tokens = 24,
        },
        prompt_bundle_digest = "prompt-bundle-1",
        prompt_tokens = overrides.prompt_tokens or 12,
        tool_schema_tokens = overrides.tool_schema_tokens or 8,
        control_schema_tokens = overrides.control_schema_tokens or 4,
        main_state = overrides.main_state or "Idle",
        active_view = active_view,
        corrections = overrides.corrections or {},
    }
end

local function response_for(instance, index, overrides)
    overrides = overrides or {}
    local specification = instance.starts[index or #instance.starts]
    local summary = {
        schema_version = overrides.schema_version or specification.summary_schema,
        source_first_seq = specification.source_first_seq,
        source_last_seq = specification.source_last_seq,
        source_digest = specification.source_digest,
        goals_decisions = overrides.goals_decisions or "实现 C28\n保持事实完整",
        constraints_permissions = "不删除 canonical XML facts",
        files_touched = "src/compact.lua: modified",
        verification_evidence = "unit fixture: passed",
        unknown_side_effects = "none observed",
        open_todos = "publish next ModelView",
        prompt_model_transitions = "main-model snapshot remains frozen",
    }
    local body = compact.encode_summary(summary)
    return {
        request_id = specification.request_id,
        canonical_body = body,
        canonical_digest = assert(instance.digest(body)),
        source_first_seq = specification.source_first_seq,
        source_last_seq = specification.source_last_seq,
        source_digest = specification.source_digest,
        generator_model_snapshot = specification.model_snapshot.digest,
        summary = summary,
        usage = { input_tokens = 100, output_tokens = 20, estimated = false },
        completion = {
            incomplete = false,
            finish_class = "stop",
            tool_call_count = 0,
            control = false,
        },
    }
end

local function published_document(instance, completed, summary_body)
    local source = instance.document
    return {
        generation = instance.generation(),
        event_count = #source.facts,
        facts = source.facts,
        model_view = {
            active_manifest = {
                digest = instance.manifest(),
                first_event_seq = 1,
                last_event_seq = #source.facts,
            },
            compaction_records = {
                {
                    id = completed.compaction_id,
                    source_first_seq = instance.publications[1].source_first_seq,
                    source_last_seq = instance.publications[1].source_last_seq,
                    source_digest = instance.publications[1].source_digest,
                    status = "ok",
                    summary = summary_body,
                },
            },
        },
    }
end

return {
    name = "unit/compact",
    cases = {
        {
            name = "manifest threshold and hard caps drive fail-closed admission",
            run = function()
                local source = document(2)
                local instance = fixture({}, nil, source)
                local fits = assert(instance.service:begin(input_for(instance)))
                A.equal(fits.decision, "fits")
                A.equal(#instance.starts, 0)
                A.equal(#instance.journal_records, 0)

                local lower = fixture({}, { trigger_numerator = 1 }, source)
                local lower_input = input_for(lower, { active_estimated_tokens = 200 })
                local decision = assert(lower.service:begin(lower_input))
                A.truthy(decision.decision ~= "fits")
                A.equal(decision.threshold_tokens, 128)
                A.equal(#lower.starts, 0)

                local exact = fixture({}, nil, source)
                local exact_plan = assert(exact.service:plan(input_for(exact, {
                    active_estimated_tokens = 384,
                })))
                A.truthy(exact_plan.decision ~= "fits")

                local byte_limited_source = document(6, {
                    [1] = { payload = string.rep("p", 400) },
                })
                local byte_limited = fixture(
                    { bytes_per_token = 64 },
                    { maximum_input_bytes = 1024 },
                    byte_limited_source
                )
                local byte_plan = assert(byte_limited.service:plan(input_for(
                    byte_limited,
                    { active_estimated_tokens = 450 }
                )))
                A.equal(byte_plan.decision, "waiting_user")
                A.equal(byte_plan.error_code, "CompactionInputTooLarge")
                A.truthy(byte_plan.source_byte_count > 1024)

                local manual = input_for(instance, {
                    mode = "manual",
                    main_state = "Running",
                })
                local admitted, manual_error = instance.service:begin(manual)
                A.falsy(admitted)
                A.equal(manual_error.code, "ManualCompactionBusy")

                local invalid = options({ maximum_attempts = 3 })
                local created, create_error = compact.new({}, invalid)
                A.falsy(created)
                A.equal(create_error.code, "InvalidCompactionPorts")
                local valid_ports = {
                    safety = { digest = function() return "digest" end },
                    estimator = { estimate = function() return 1 end },
                    clock = { now = function() return 0 end },
                    model = { start = function() return true end, cancel = function()
                        return { outcome = "cancelled" }
                    end },
                    journal = {
                        commit_intent = function() end,
                        commit_response = function() end,
                        commit_rejection = function() end,
                        publish = function() end,
                        commit_correction = function() end,
                    },
                }
                created, create_error = compact.new(valid_ports, invalid)
                A.falsy(created)
                A.equal(create_error.code, "InvalidCompactionOptions")
            end,
        },
        {
            name = "successful publication is durable ordered visible and lossless",
            run = function()
                local instance = fixture()
                local source_count = #instance.document.facts
                local started = assert(instance.service:begin(input_for(instance, {
                    active_estimated_tokens = 450,
                })))
                A.equal(started.state, "Compacting")
                A.equal(instance.log[1], "journal:commit_intent:compaction-request")
                A.matches(instance.log[2], "^model:start:")
                A.equal(instance.starts[1].purpose, "compaction")
                A.equal(instance.starts[1].no_tools, true)
                A.equal(instance.starts[1].config_snapshot, "config-snapshot-1")
                A.equal(instance.starts[1].model_snapshot.digest, "model-snapshot-1")
                A.equal(
                    instance.journal_records[1].binding.prompt_bundle_digest,
                    "prompt-bundle-1"
                )
                A.equal(assert(compact.encode_source(
                    instance.document,
                    instance.starts[1].source_first_seq,
                    instance.starts[1].source_last_seq,
                    128,
                    1024 * 1024
                )), instance.starts[1].source_bytes)
                A.equal(instance.manifest(), "view-old")

                local wrapper = response_for(instance)
                local completed = assert(instance.service:accept_response(wrapper))
                A.equal(completed.outcome, "completed")
                A.equal(completed.canonical_facts_removed, 0)
                A.equal(completed.atomic_groups_split, 0)
                A.equal(#instance.document.facts, source_count)
                A.equal(instance.document.event_count, source_count)
                A.equal(instance.old_manifest_at_publish(), "view-old")
                A.equal(instance.manifest(), completed.manifest_digest)
                A.equal(#instance.publications, 1)
                A.equal(assert(compact.encode_manifest(
                    instance.publications[1].manifest,
                    128,
                    1024 * 1024
                )), instance.publications[1].manifest.canonical_bytes)
                A.equal(instance.publications[1].canonical_facts_removed, 0)
                A.equal(instance.publications[1].atomic_groups_split, 0)
                A.equal(instance.publications[1].old_view_retained_until_publish, true)

                local shown = assert(instance.service:show_summary(
                    published_document(instance, completed, wrapper.canonical_body),
                    completed.compaction_id
                ))
                A.equal(shown.summary.goals_decisions, "实现 C28\n保持事实完整")
                A.raises(function() shown.summary.open_todos = "changed" end, "cannot be modified")
                A.equal(instance.service:status().state, "Idle")
                A.equal(instance.service:status().automatic_consent_required, false)
            end,
        },
        {
            name = "atomic tool groups never split and oversized required groups wait",
            run = function()
                local source = document(6, { [3] = { tool = true } })
                local instance = fixture({}, nil, source)
                local plan = assert(instance.service:plan(input_for(instance, {
                    active_estimated_tokens = 450,
                })))
                A.equal(plan.decision, "compact")
                local call_sequence, result_sequence
                for _, fact in ipairs(source.facts) do
                    if fact.type == "tool_call" then call_sequence = fact.seq end
                    if fact.type == "tool_result" then result_sequence = fact.seq end
                end
                local paired
                for _, group in ipairs(plan.groups) do
                    local has_call, has_result = false, false
                    for _, sequence in ipairs(group.sequences) do
                        if sequence == call_sequence then has_call = true end
                        if sequence == result_sequence then has_result = true end
                    end
                    if has_call or has_result then
                        A.equal(has_call, true)
                        A.equal(has_result, true)
                        paired = group
                    end
                    if group.first <= plan.source_last_seq then
                        A.truthy(group.last <= plan.source_last_seq)
                    else
                        A.truthy(group.first > plan.source_last_seq)
                    end
                end
                A.truthy(paired)

                local oversized_source = document(2, {
                    [2] = {
                        tool = true,
                        unpaired_tool = true,
                        active = true,
                        tool_payload = string.rep("x", 4096),
                    },
                })
                local oversized = fixture(
                    { bytes_per_token = 4 },
                    { maximum_view_tokens = 256, maximum_summary_tokens = 32 },
                    oversized_source
                )
                local oversized_input = input_for(oversized, {
                    active_estimated_tokens = 250,
                    model_snapshot = {
                        id = "main-model",
                        digest = "model-snapshot-small",
                        window_tokens = 256,
                        maximum_output_tokens = 24,
                    },
                })
                local waiting = assert(oversized.service:begin(oversized_input))
                A.equal(waiting.decision, "waiting_user")
                A.equal(waiting.error_code, "OversizedAtomicGroup")
                A.equal(waiting.recommendation_required, true)
                A.equal(#oversized.starts, 0)
            end,
        },
        {
            name = "invalid or useless summaries get one correction retry only",
            run = function()
                local instance = fixture({}, { minimum_benefit_tokens = 10000 })
                assert(instance.service:begin(input_for(instance, {
                    active_estimated_tokens = 450,
                })))
                local first = response_for(instance, 1, {
                    schema_version = "structured-summary-v0",
                })
                local retried = assert(instance.service:accept_response(first))
                A.equal(retried.state, "Compacting")
                A.equal(retried.attempt, 2)
                A.equal(#instance.starts, 2)

                local stale, stale_error = instance.service:accept_response(first)
                A.falsy(stale)
                A.equal(stale_error.code, "StaleCompactionResponse")
                A.equal(instance.service:status().attempt, 2)

                local second = response_for(instance, 2)
                local waiting = assert(instance.service:accept_response(second))
                A.equal(waiting.outcome, "waiting_user")
                A.equal(waiting.error_code, "CompactionNoBenefit")
                A.equal(#instance.starts, 2)
                A.equal(#instance.publications, 0)
                A.equal(instance.manifest(), "view-old")
            end,
        },
        {
            name = "incomplete provider responses never publish a summary",
            run = function()
                local instance = fixture()
                assert(instance.service:begin(input_for(instance, {
                    active_estimated_tokens = 450,
                })))
                local first = response_for(instance, 1)
                first.completion.incomplete = true
                local retried = assert(instance.service:accept_response(first))
                A.equal(retried.state, "Compacting")
                A.equal(retried.attempt, 2)

                local second = response_for(instance, 2)
                second.completion.finish_class = "length"
                local waiting = assert(instance.service:accept_response(second))
                A.equal(waiting.outcome, "waiting_user")
                A.equal(waiting.error_code, "InvalidCompactionResponse")
                A.equal(#instance.publications, 0)
                A.equal(instance.manifest(), "view-old")
            end,
        },
        {
            name = "automatic failures open a cooldown circuit with one half-open probe",
            run = function()
                local instance = fixture({}, {
                    failure_threshold = 2,
                    failure_cooldown_ms = 100,
                })
                local function fail_lifecycle()
                    assert(instance.service:begin(input_for(instance, {
                        active_estimated_tokens = 450,
                    })))
                    local first = response_for(instance)
                    first.completion.incomplete = true
                    assert(instance.service:accept_response(first))
                    local second = response_for(instance)
                    second.completion.incomplete = true
                    return assert(instance.service:accept_response(second))
                end
                A.equal(fail_lifecycle().outcome, "waiting_user")
                A.equal(instance.service:status().automatic_failure_count, 1)
                A.equal(fail_lifecycle().outcome, "waiting_user")
                A.equal(instance.service:status().automatic_circuit_state, "open")

                local start_count = #instance.starts
                local suppressed = assert(instance.service:begin(input_for(instance, {
                    active_estimated_tokens = 450,
                })))
                A.equal(suppressed.decision, "suppressed")
                A.equal(suppressed.error_code, "CompactionCircuitOpen")
                A.equal(suppressed.retry_after_ms, 100)
                A.equal(#instance.starts, start_count)

                instance.advance(100)
                assert(instance.service:begin(input_for(instance, {
                    active_estimated_tokens = 450,
                })))
                local completed = assert(instance.service:accept_response(
                    response_for(instance)
                ))
                A.equal(completed.outcome, "completed")
                A.equal(instance.service:status().automatic_failure_count, 0)
                A.equal(instance.service:status().automatic_circuit_state, "closed")
            end,
        },
        {
            name = "recovered automatic failures reopen a full monotonic cooldown",
            run = function()
                local instance = fixture({
                    initial_automatic_failure_count = 2,
                }, {
                    failure_threshold = 2,
                    failure_cooldown_ms = 100,
                })
                local status = instance.service:status()
                A.equal(status.automatic_failure_count, 2)
                A.equal(status.automatic_circuit_state, "open")
                A.truthy(status.automatic_circuit_recovered)
                A.equal(status.automatic_circuit_opened_at, false)

                local suppressed = assert(instance.service:begin(input_for(instance, {
                    active_estimated_tokens = 450,
                })))
                A.equal(suppressed.decision, "suppressed")
                A.equal(suppressed.retry_after_ms, 100)
                A.equal(#instance.starts, 0)
                A.falsy(instance.service:status().automatic_circuit_recovered)

                instance.advance(100)
                assert(instance.service:begin(input_for(instance, {
                    active_estimated_tokens = 450,
                })))
                local completed = assert(instance.service:accept_response(
                    response_for(instance)
                ))
                A.equal(completed.outcome, "completed")
                A.equal(instance.service:status().automatic_failure_count, 0)
                A.equal(instance.service:status().automatic_circuit_state, "closed")
            end,
        },
        {
            name = "publication and receipt faults retain the prior manifest",
            run = function()
                local failed = fixture({ fail_journal_method = "publish" })
                assert(failed.service:begin(input_for(failed, {
                    active_estimated_tokens = 450,
                })))
                local completed, publish_error = failed.service:accept_response(
                    response_for(failed)
                )
                A.falsy(completed)
                A.equal(publish_error.code, "CompactionJournalFailure")
                A.equal(failed.manifest(), "view-old")
                A.equal(failed.service:status().state, "Unknown")
                local attempted = failed.journal_records[#failed.journal_records].binding
                A.equal(attempted.kind, "compaction-publication")
                A.equal(attempted.canonical_facts_removed, 0)

                local bad = fixture({ bad_receipt_method = "commit_intent" })
                local started, receipt_error = bad.service:begin(input_for(bad, {
                    active_estimated_tokens = 450,
                }))
                A.falsy(started)
                A.equal(receipt_error.code, "CompactionJournalFailure")
                A.equal(#bad.starts, 0)
                A.equal(bad.manifest(), "view-old")
                A.equal(bad.service:status().state, "Unknown")
            end,
        },
        {
            name = "manual lifecycle cancellation has durable terminal settlement",
            run = function()
                local instance = fixture()
                local input = input_for(instance, {
                    mode = "manual",
                    active_estimated_tokens = 200,
                })
                assert(instance.service:begin(input))
                local cancelled = assert(instance.service:cancel("user-cancel"))
                A.equal(cancelled.outcome, "cancelled")
                A.equal(cancelled.old_view_retained, true)
                A.equal(instance.journal_records[#instance.journal_records].binding.kind,
                    "compaction-cancel-result")
                A.equal(instance.manifest(), "view-old")
                local closed = assert(instance.service:close())
                A.equal(closed.closed, true)
                local reopened, closed_error = instance.service:begin(input)
                A.falsy(reopened)
                A.equal(closed_error.code, "CompactionClosed")

                local pending = fixture({ cancel_result = { outcome = "pending" } })
                assert(pending.service:begin(input_for(pending, {
                    mode = "manual",
                    active_estimated_tokens = 200,
                })))
                local cancellation = assert(pending.service:cancel("user-cancel"))
                A.equal(cancellation.cancel_pending, true)
                A.equal(pending.service:status().state, "Cancelling")
                A.equal(assert(pending.service:close()).cancel_pending, true)
                local request_id = pending.service:status().active_request_id
                local settled = assert(pending.service:settle_cancel({
                    request_id = request_id,
                    outcome = "cancelled",
                }))
                A.equal(settled.outcome, "cancelled")
                A.equal(pending.journal_records[#pending.journal_records].binding.kind,
                    "compaction-cancel-result")
                A.equal(pending.service:status().closed, true)

                local timed = fixture({ cancel_result = { outcome = "pending" } })
                assert(timed.service:begin(input_for(timed, {
                    mode = "manual",
                    active_estimated_tokens = 200,
                })))
                assert(timed.service:cancel("user-cancel"))
                timed.advance(1000)
                local unknown = assert(timed.service:tick())
                A.equal(unknown.outcome, "unknown")
                A.equal(timed.service:status().state, "Unknown")
                A.equal(timed.journal_records[#timed.journal_records].binding.kind,
                    "compaction-cancel-result")
            end,
        },
        {
            name = "summary lookup correction and next publication preserve provenance",
            run = function()
                local instance = fixture()
                assert(instance.service:begin(input_for(instance, {
                    active_estimated_tokens = 450,
                })))
                local first_response = response_for(instance)
                local first = assert(instance.service:accept_response(first_response))
                local published = published_document(instance, first, first_response.canonical_body)
                local shown = assert(instance.service:show_summary(
                    published,
                    first.compaction_id
                ))
                A.equal(shown.source_digest, instance.publications[1].source_digest)

                local malformed, malformed_error = instance.service:correct_summary({
                    document = { generation = published.generation },
                    compaction_id = first.compaction_id,
                    text = "修正：验证证据尚未覆盖目标机",
                    expected_context_generation = published.generation,
                    expected_manifest_digest = instance.manifest(),
                })
                A.falsy(malformed)
                A.equal(malformed_error.code, "InvalidSummaryCorrection")

                local correction = assert(instance.service:correct_summary({
                    document = published,
                    compaction_id = first.compaction_id,
                    text = "修正：验证证据尚未覆盖目标机",
                    expected_context_generation = published.generation,
                    expected_manifest_digest = instance.manifest(),
                }))
                A.equal(correction.effective_at, "next-model-view-publication")
                A.matches(correction.correction_id, "^summary%-correction%-[0-9]+%-[0-9]+$")

                local next_document = copy(published)
                next_document.generation = instance.generation()
                next_document.model_view = copy(published.model_view)
                next_document.model_view.active_manifest = copy(
                    published.model_view.active_manifest
                )
                local next_input = input_for(instance, {
                    document = next_document,
                    active_estimated_tokens = 450,
                    summary_id = first.summary_id,
                    corrections = {
                        {
                            correction_id = correction.correction_id,
                            compaction_id = first.compaction_id,
                            text = "修正：验证证据尚未覆盖目标机",
                        },
                    },
                })
                assert(instance.service:begin(next_input))
                A.equal(instance.starts[2].corrections[1].correction_id,
                    correction.correction_id)
                A.equal(instance.starts[2].corrections[1].text,
                    "修正：验证证据尚未覆盖目标机")
                local second = assert(instance.service:accept_response(response_for(instance, 2)))
                A.equal(second.outcome, "completed")
                A.equal(instance.publications[2].correction_ids[1], correction.correction_id)
            end,
        },
    },
}
