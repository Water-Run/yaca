--[[
Author: WaterRun
Date: 2026-09-23
File: production_agent_composition_test.lua
Description: Verifies the production first-turn Agent composition and durable ordering.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()
local compact = assert(loadfile(
    YACA_TEST_ROOT .. "/src/compact.lua",
    "t",
    _ENV
))()

--Supplies test digest behavior required by this suite.
--@param bytes string Byte chunk supplied to the fake I/O port.
--@return any observed test digest value observed by the scenario assertion.
local function test_digest(bytes)
    local value = 2166136261
    for index = 1, #bytes do
        value = (value * 16777619 + bytes:byte(index)) % 4294967296
    end
    return string.format("test-digest-%08x-%d", value, #bytes)
end

--Writes append compaction event through the the current case fixture.
--@param facts table Platform or file-descriptor facts supplied to the case.
--@param event_type string Event kind emitted by the fake activity.
--@param turn_id integer Agent turn identity under inspection.
--@param fields table Field values used to construct the test document.
--@return nil No value; the fake port or test assertion observes this callback's effects.
local function append_compaction_event(facts, event_type, turn_id, fields)
    facts[#facts + 1] = {
        seq = #facts + 1,
        type = event_type,
        at = "2026-08-30T00:00:00Z",
        turn_id = turn_id,
        fields = fields,
    }
end

--Supplies compaction document behavior required by this suite.
--@param none No arguments; this closure uses its captured fixture state.
--@return table observed Structured fixture record selected by the exercised branch.
local function compaction_document()
    local facts = {}
    for serial = 1, 6 do
        local turn_id = "turn-" .. tostring(serial)
        local request_id = turn_id .. ":request:1"
        append_compaction_event(facts, "turn_started", turn_id, {
            kind = "main",
            configGeneration = "config-snapshot-1",
            modelSnapshot = "model-snapshot-1",
            permissionSnapshot = "permission-snapshot-1",
            promptSnapshot = "prompt-snapshot-1",
            toolRegistrySnapshot = "registry-1",
        })
        append_compaction_event(facts, "user_message", turn_id, {
            messageId = turn_id .. ":message:1",
            text = "implement bounded project milestone " .. tostring(serial),
            source = "terminal",
        })
        append_compaction_event(facts, "model_request", turn_id, {
            requestId = request_id,
            purpose = "main",
            viewManifestRef = "view-1",
        })
        append_compaction_event(facts, "model_message", turn_id, {
            requestId = request_id,
            status = "complete",
            body = "verified result " .. tostring(serial),
            digest = "message-digest-" .. tostring(serial),
        })
        append_compaction_event(facts, "turn_ended", turn_id, {
            outcome = "completed",
        })
    end
    return {
        generation = 10,
        event_count = #facts,
        facts = facts,
        model_view = {
            active_manifest = {
                digest = "view-1",
                first_event_seq = 1,
                last_event_seq = #facts,
            },
            compaction_records = {},
        },
    }
end

--Reads load main for this test scenario.
--@param cache table Per-case module cache preserving isolated imports.
--@return any decoded load main data supplied to the assertion.
local function load_main(cache)
    local environment = {}
    for key, value in pairs(_ENV) do environment[key] = value end
    --Resolves an imported Lua module through the isolated test loader.
    --@param name string Module, Model, or resource name selected by the case.
    --@return any value Callback value consumed by the enclosing scenario assertion.
    environment.require = function(name)
        if cache[name] then return cache[name] end
        local chunk, load_error = loadfile(
            YACA_TEST_ROOT .. "/src/" .. name .. ".lua",
            "t",
            environment
        )
        A.truthy(chunk, load_error)
        local module = chunk()
        cache[name] = module
        return module
    end
    environment._G = environment
    --@metatable environment Test-owned lookup and mutation contract for the current case.
    --@field __index any Fallback table or function used for missing fixture keys.
    setmetatable(environment, { __index = _ENV })
    local chunk, load_error = loadfile(
        YACA_TEST_ROOT .. "/src/main.lua",
        "t",
        environment
    )
    A.truthy(chunk, load_error)
    return chunk()
end

--Constructs the suite's isolated runtime fixture and observation ports.
--@param settings table|nil Fixture settings and scenario overrides.
--@return table fixture Constructed fixture service used by this suite.
local function fixture(settings)
    settings = settings or {}
    local continuing = settings.continuing == true
    local log = {}
    local compaction_lifecycle = settings.compaction_lifecycle
        or settings.automatic_compaction_lifecycle
    local compact_source = compaction_lifecycle
        and compaction_document() or false
    local published = continuing
    local closed = false
    local loop_closed = false
    local handoff = {
        input = {
            text = "implement the project",
            source = "terminal",
            config_generation = "config-snapshot-1",
            model_snapshot = "model-snapshot-1",
            permission_snapshot = "permission-snapshot-1",
            prompt_snapshot = "prompt-snapshot-1",
            tool_registry_snapshot = "registry-1",
            view_manifest_ref = "view-1",
            double_check = true,
            context_generation = 1,
            model_request_limit = 7,
            tool_call_limit = 11,
            queue_limit = 5,
        },
        binding = {},
    }
    local generation = {
        id = "config-generation-1",
        agent_ready = true,
        current_model = "Primary",
        current_permission = "Std",
        effective_double_check = true,
        effective_double_check_goal = "",
        context_prompt = "workspace context",
        auto_rename_disabled = false,
        general = { system_prompt = "global" },
        network = { follow_proxy = false },
        exec = {
            max_output_kb = settings.max_output_kb or 1024,
            timeout_ms = 5000,
            environment_mode = "minimal",
        },
        agent = {
            double_check = true,
            action_review_enabled = true,
            max_turn_model_requests = 7,
            max_turn_tool_calls = 11,
            queue_max_items = 5,
            compact_threshold = 0.75,
        },
        permissions = {
            Std = {
                read = "allow",
                write = "confirm",
                delete = "confirm",
                shell = "confirm",
                outside_workspace = "confirm",
                description = "standard",
                system_prompt = "permission",
            },
        },
        model_order = { "Primary", "Secondary" },
        default_model = "Primary",
        models = {
            Primary = {
                enabled = true,
                description = "primary",
                protocol = "openai-chat",
                endpoint = "https://primary.example/v1/chat/completions",
                remote_model = "primary-remote",
                key_configured = true,
                context_length = 16000,
                max_output_tokens = 1024,
                system_prompt = "model",
                streaming = "try",
                tools_enabled = true,
                adapter_options = {},
            },
            Secondary = {
                enabled = true,
                description = "secondary",
                protocol = "anthropic-messages",
                endpoint = "https://secondary.example/v1/messages",
                remote_model = "secondary-remote",
                key_configured = true,
                context_length = settings.small_model_window and 2048 or 64000,
                max_output_tokens = 2048,
                system_prompt = "secondary model",
                streaming = "force",
                tools_enabled = true,
                adapter_options = {},
            },
        },
        --Simulates the scan registered secrets boundary for this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return table record Fixture record emitted by the scenario callback.
        scan_registered_secrets = function() return {} end,
        --Constructs new stream scanner for this test scenario.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return table record Fixture record emitted by the scenario callback.
        new_stream_scanner = function() return {} end,
    }
    if settings.proxy_route then
        generation.network = {
            follow_proxy = true,
            proxy_url_configured = true,
            proxy_route = settings.proxy_route,
        }
    end
    local next_generation = {}
    for key, value in pairs(generation) do next_generation[key] = value end
    next_generation.id = "config-generation-2"
    --Supplies matches model secrets behavior required by this suite.
    --@param previous any The previous supplied to the fake service for this scenario.
    --@param name string Module, Model, or resource name selected by the case.
    --@return any observed matches model secrets value observed by the scenario assertion.
    function next_generation.matches_model_secrets(previous, name)
        A.equal(previous, generation)
        A.equal(name, "Secondary")
        log[#log + 1] = "model-secret-reverify"
        return not settings.model_secret_changed_on_reload
    end
    next_generation.agent = {
        double_check = true,
        action_review_enabled = true,
        max_turn_model_requests = 6,
        max_turn_tool_calls = 10,
        queue_max_items = 4,
        compact_threshold = 0.75,
    }
    local active_generation = generation
    local loop_status = {
        state = continuing and "Idle" or "RequestingModel",
        context_generation = continuing and 7 or 2,
        last_durable_sequence = continuing and 29 or 3,
        active_view_manifest_ref = continuing and "sha256:restored-view" or "view-1",
        turn_id = continuing and false or "turn-1",
        halted = false,
        compaction_state = "idle",
        compaction_preflight_state = "idle",
        compaction_preflight_id = false,
        compaction_preflight_purpose = false,
    }
    local compaction_gate = false
    local loop = {}
    for _, name in ipairs({
        "submit_main", "enqueue", "steer", "start_ask", "resolve_yield",
        "reply", "list_queue", "drop_queue", "edit_queue", "reorder_queue",
        "clear_queue", "use_ask",
    }) do
        --Supplies an assertion callback for this test scenario.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return boolean accepted Whether the fake callback accepts this scenario.
        loop[name] = function() return true end
    end
    --Simulates the status transition of a fake activity port for this suite.
    --@param self table Fixture or port instance receiving this call.
    --@return any observed status value observed by the scenario assertion.
    function loop:status() return loop_status end
    --Supplies resume published main behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param observed table|any State observed after the exercised operation.
    --@return table observed Structured fixture record with state, request_id.
    function loop:resume_published_main(observed)
        A.truthy(published, "Model admission crossed the first publication barrier")
        A.equal(observed, handoff)
        log[#log + 1] = "runtime-resume"
        return { state = "RequestingModel", request_id = "turn-1:request:1" }
    end
    --Simulates the close transition of a fake activity port for this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param reason string Failure or close reason supplied to the port.
    --@return boolean accepted Whether close succeeds in the fixture.
    function loop:close(reason)
        A.equal(reason, "agent-composition-failed")
        loop_closed = true
        log[#log + 1] = "runtime-close"
        return true
    end
    --Supplies begin compaction behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param command string|table Command delivered to the fake executor.
    --@return table|boolean observed begin compaction value observed by the scenario assertion.
    function loop:begin_compaction(command)
        if not compaction_lifecycle then return true end
        local automatic = settings.automatic_compaction_lifecycle == true
        A.equal(loop_status.state, automatic and "Preparing" or "Idle")
        A.equal(command.mode, automatic and "automatic" or "manual")
        A.equal(
            command.preflight_id,
            automatic and "turn-1:compaction-preflight:1" or false
        )
        A.equal(command.expected_context_generation, loop_status.context_generation)
        A.equal(command.expected_last_sequence, loop_status.last_durable_sequence)
        A.equal(command.expected_manifest_digest, loop_status.active_view_manifest_ref)
        A.falsy(compaction_gate)
        compaction_gate = true
        log[#log + 1] = "runtime-compaction-begin"
        return {
            state = loop_status.state,
            mode = command.mode,
            context_generation = loop_status.context_generation,
            last_sequence = loop_status.last_durable_sequence,
            manifest_digest = loop_status.active_view_manifest_ref,
        }
    end
    --Supplies adopt compaction receipt behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param record table Recorded event or publication under inspection.
    --@param receipt table Publication receipt inspected by the assertion.
    --@return table|boolean observed adopt compaction receipt value observed by the scenario assertion.
    function loop:adopt_compaction_receipt(record, receipt)
        if not compaction_lifecycle then return true end
        A.truthy(compaction_gate)
        A.equal(receipt.previous_context_generation, loop_status.context_generation)
        A.equal(receipt.first_sequence, loop_status.last_durable_sequence + 1)
        loop_status.context_generation = receipt.context_generation
        loop_status.last_durable_sequence = receipt.last_sequence
        if record.kind == "compaction-publication" then
            A.equal(record.expected_manifest_digest, loop_status.active_view_manifest_ref)
            loop_status.active_view_manifest_ref = record.manifest.digest
        end
        log[#log + 1] = "runtime-adopt:" .. record.kind
        return {
            context_generation = loop_status.context_generation,
            last_sequence = loop_status.last_durable_sequence,
            manifest_digest = loop_status.active_view_manifest_ref,
        }
    end
    --Supplies adopt session override behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param record table Recorded event or publication under inspection.
    --@param receipt table Publication receipt inspected by the assertion.
    --@return table observed Structured fixture record with context_generation, last_sequence, manifest_digest, effective_at.
    function loop:adopt_session_override(record, receipt)
        A.equal(record.kind, "session-override")
        A.equal(record.replaces_manifest_digest, loop_status.active_view_manifest_ref)
        A.equal(receipt.previous_context_generation, loop_status.context_generation)
        A.equal(receipt.context_generation, loop_status.context_generation + 1)
        A.equal(receipt.first_sequence, loop_status.last_durable_sequence + 1)
        A.equal(receipt.last_sequence, loop_status.last_durable_sequence + 2)
        loop_status.context_generation = receipt.context_generation
        loop_status.last_durable_sequence = receipt.last_sequence
        loop_status.active_view_manifest_ref = record.manifest_digest
        log[#log + 1] = "runtime-adopt:session-override"
        return {
            context_generation = loop_status.context_generation,
            last_sequence = loop_status.last_durable_sequence,
            manifest_digest = loop_status.active_view_manifest_ref,
            effective_at = "next-turn",
        }
    end
    --Supplies fail session override barrier behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param reason string Failure or close reason supplied to the port.
    --@return nil rejected Explicit empty outcome from fail session override barrier.
    --@return table secondary2 Typed error record with code AgentDurabilityFailure.
    function loop:fail_session_override_barrier(reason)
        loop_status.halted = true
        log[#log + 1] = "runtime-session-fail:" .. reason
        return nil, { code = "AgentDurabilityFailure" }
    end
    --Supplies fail context observation behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@return nil rejected Explicit empty outcome from fail context observation.
    --@return table secondary2 Typed error record with code AgentDurabilityFailure.
    function loop:fail_context_observation()
        loop_status.halted = true
        log[#log + 1] = "runtime-context-stale"
        return nil, { code = "AgentDurabilityFailure" }
    end
    --Supplies fail compaction barrier behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param reason string Failure or close reason supplied to the port.
    --@return nil rejected Explicit empty outcome from fail compaction barrier.
    --@return table secondary2 Typed error record with code AgentDurabilityFailure.
    function loop:fail_compaction_barrier(reason)
        if not compaction_lifecycle then
            return nil, { code = "AgentDurabilityFailure" }
        end
        loop_status.halted = true
        log[#log + 1] = "runtime-compaction-fail:" .. tostring(reason)
        return nil, { code = "AgentDurabilityFailure" }
    end
    --Supplies finish compaction behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param command string|table Command delivered to the fake executor.
    --@return boolean|any|nil observed finish compaction value observed by the scenario assertion.
    --@return table|nil secondary2 Typed error record with code AgentDurabilityFailure.
    function loop:finish_compaction(command)
        if not compaction_lifecycle then return true end
        if loop_status.halted then
            return nil, { code = "AgentDurabilityFailure" }
        end
        A.truthy(compaction_gate)
        A.equal(command.expected_context_generation, loop_status.context_generation)
        A.equal(command.expected_last_sequence, loop_status.last_durable_sequence)
        A.equal(command.expected_manifest_digest, loop_status.active_view_manifest_ref)
        if command.outcome == "completed" then
            A.equal(command.compaction_id, "compaction-1")
            A.truthy(loop_status.active_view_manifest_ref ~= "view-1")
        end
        compaction_gate = false
        log[#log + 1] = "runtime-compaction-finish:" .. command.outcome
        local settlement = {
            outcome = command.outcome,
            compaction_id = command.compaction_id,
            mode = settings.automatic_compaction_lifecycle
                and "automatic" or "manual",
            preflight_id = settings.automatic_compaction_lifecycle
                and "turn-1:compaction-preflight:1" or false,
            state = loop_status.state,
            context_generation = loop_status.context_generation,
            last_sequence = loop_status.last_durable_sequence,
            manifest_digest = loop_status.active_view_manifest_ref,
        }
        if settings.automatic_compaction_lifecycle then
            loop_status.compaction_preflight_state = "settled"
            settings.automatic_settlement = settlement
        end
        return settlement
    end
    --Supplies resolve compaction preflight behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param command string|table Command delivered to the fake executor.
    --@return table observed Structured fixture record with state, request_id.
    function loop:resolve_compaction_preflight(command)
        A.truthy(settings.automatic_compaction_lifecycle)
        A.equal(command.preflight_id, loop_status.compaction_preflight_id)
        A.equal(command.settlement, settings.automatic_settlement)
        A.equal(command.outcome, "completed")
        log[#log + 1] = "runtime-preflight-resolve"
        loop_status.state = "RequestingModel"
        loop_status.compaction_preflight_state = "idle"
        loop_status.compaction_preflight_id = false
        loop_status.compaction_preflight_purpose = false
        return { state = "RequestingModel", request_id = "turn-1:request:1" }
    end

    local operation_journal = {
        --Simulates the commit intent publication step for this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return boolean accepted Whether the fake callback accepts this scenario.
        commit_intent = function() return true end,
        --Simulates the commit result publication step for this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return boolean accepted Whether the fake callback accepts this scenario.
        commit_result = function() return true end,
        --Supplies take intent receipt behavior required by this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return table record Fixture record emitted by the scenario callback.
        take_intent_receipt = function() return {} end,
        --Supplies take result receipt behavior required by this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return table record Fixture record emitted by the scenario callback.
        take_result_receipt = function() return {} end,
    }
    local durable_compaction_attempt = 0
    local durable_compaction_mode = false
    --Supplies compaction events behavior required by this suite.
    --@param record table Recorded event or publication under inspection.
    --@return table observed Structured fixture record selected by the exercised branch.
    local function compaction_events(record)
        if record.kind == "compaction-request" then
            durable_compaction_attempt = record.attempt
            durable_compaction_mode = record.mode
            return { {
                type = "model_request",
                turn_id = false,
                fields = {
                    requestId = record.request_id,
                    purpose = "compaction",
                    viewManifestRef = record.expected_manifest_digest,
                    attemptId = tostring(record.attempt),
                    compactionId = record.compaction_id,
                    compactionMode = record.mode,
                    sourceFirstSeq = tostring(record.source_first_seq),
                    sourceLastSeq = tostring(record.source_last_seq),
                    sourceDigest = record.source_digest,
                    configSnapshot = record.config_snapshot,
                    modelSnapshot = record.model_snapshot_digest,
                    promptSnapshot = record.prompt_bundle_digest,
                    manifestSnapshot = record.manifest_snapshot_id,
                    viewContextGeneration = tostring(
                        record.expected_context_generation
                    ),
                },
            } }
        end
        if record.kind == "compaction-response" then
            return { {
                type = "model_message",
                turn_id = false,
                fields = {
                    requestId = record.request_id,
                    status = "complete",
                    body = record.canonical_body,
                    digest = record.canonical_digest,
                },
            } }
        end
        if record.kind == "compaction-publication" then
            return {
                {
                    type = "compaction",
                    turn_id = false,
                    fields = {
                        compactionId = record.compaction_id,
                        status = "ok",
                        summaryDigest = record.summary_digest,
                        manifestDigest = record.manifest.digest,
                        requestId = record.request_id,
                        attemptId = tostring(durable_compaction_attempt),
                        compactionMode = durable_compaction_mode,
                        automaticFailure = "false",
                    },
                },
                {
                    type = "model_view_published",
                    turn_id = false,
                    fields = {
                        compactionId = record.compaction_id,
                        manifestDigest = record.manifest.digest,
                        replacesManifestDigest = record.expected_manifest_digest,
                    },
                },
            }
        end
        return { {
            type = "warning",
            turn_id = false,
            fields = {
                errorId = record.error_code or record.kind,
                causeId = record.compaction_id,
            },
        } }
    end
    --Supplies commit compaction behavior required by this suite.
    --@param record table Recorded event or publication under inspection.
    --@param publishing any The publishing supplied to the fake service for this scenario.
    --@return boolean accepted Whether commit compaction succeeds in the fixture.
    --@return table|any secondary2 Additional status or structured error from the fixture operation.
    local function commit_compaction(record, publishing)
        A.truthy(compaction_lifecycle)
        A.equal(record.expected_context_generation, loop_status.context_generation)
        if settings.compaction_capacity and record.kind == "compaction-request" then
            return false, { code = "ContextCapacity", publication_started = false }
        end
        if settings.compaction_journal_failure == record.kind then
            log[#log + 1] = "journal-rejected:" .. record.kind
            return false, { code = "InjectedCompactionJournalFailure" }
        end
        local events = compaction_events(record)
        local first_sequence = loop_status.last_durable_sequence + 1
        for index, event in ipairs(events) do
            event.seq = first_sequence + index - 1
        end
        local batch = {
            barrier_id = "compaction-test:" .. record.kind,
            first_sequence = first_sequence,
            last_sequence = first_sequence + #events - 1,
            event_count = #events,
            expected_context_generation = loop_status.context_generation,
            events = events,
        }
        local next_generation_value = loop_status.context_generation + 1
        local runtime_receipt = {
            barrier_id = batch.barrier_id,
            first_sequence = batch.first_sequence,
            last_sequence = batch.last_sequence,
            event_count = batch.event_count,
            binding = batch,
            previous_context_generation = loop_status.context_generation,
            context_generation = next_generation_value,
        }
        local receipt = {
            binding = record,
            previous_context_generation = loop_status.context_generation,
            context_generation = next_generation_value,
            runtime_receipt = runtime_receipt,
        }
        if publishing then
            receipt.previous_manifest_digest = loop_status.active_view_manifest_ref
            receipt.published_manifest_digest = record.manifest.digest
        else
            receipt.active_manifest_digest = loop_status.active_view_manifest_ref
        end
        log[#log + 1] = "journal:" .. record.kind
        return true, receipt
    end
    local durable_compaction_journal = {
        --Simulates the commit intent publication step for this suite.
        --@param record table Recorded event or publication under inspection.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        commit_intent = function(record)
            return commit_compaction(record, false)
        end,
        --Simulates the commit response publication step for this suite.
        --@param record table Recorded event or publication under inspection.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        commit_response = function(record)
            return commit_compaction(record, false)
        end,
        --Simulates the commit rejection publication step for this suite.
        --@param record table Recorded event or publication under inspection.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        commit_rejection = function(record)
            return commit_compaction(record, false)
        end,
        --Records the publish effect observed by this suite.
        --@param record table Recorded event or publication under inspection.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        publish = function(record)
            return commit_compaction(record, true)
        end,
        --Simulates the commit correction publication step for this suite.
        --@param record table Recorded event or publication under inspection.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        commit_correction = function(record)
            return commit_compaction(record, false)
        end,
    }
    local durable_double_check_override = true
    local durable_context_prompt = "workspace context"
    local durable_current_model = "Primary"
    local publication = {
        --Supplies inspect active behavior required by this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return table|nil value Callback value consumed by the enclosing scenario assertion.
        --@return any|nil secondary2 Configured context inspection error override.
        inspect_active = function()
            if settings.context_inspection_throws then error("private diagnostic") end
            if settings.context_inspection_error then
                return nil, settings.context_inspection_error
            end
            return { context_hash = "ABCDABCD12341234", display_name = "current-task" }
        end,
        --Supplies operation journal behavior required by this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        operation_journal = function()
            log[#log + 1] = "operation-journal"
            return operation_journal
        end,
        --Supplies compaction journal behavior required by this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return table|any value Callback value consumed by the enclosing scenario assertion.
        compaction_journal = function()
            log[#log + 1] = "compaction-journal"
            if compaction_lifecycle then
                return durable_compaction_journal
            end
            return {
                --Simulates the commit intent publication step for this suite.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether the fake callback accepts this scenario.
                commit_intent = function() return false end,
                --Simulates the commit response publication step for this suite.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether the fake callback accepts this scenario.
                commit_response = function() return false end,
                --Simulates the commit rejection publication step for this suite.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether the fake callback accepts this scenario.
                commit_rejection = function() return false end,
                --Records the publish effect observed by this suite.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether the fake callback accepts this scenario.
                publish = function() return false end,
                --Simulates the commit correction publication step for this suite.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether the fake callback accepts this scenario.
                commit_correction = function() return false end,
            }
        end,
        --Supplies compaction snapshot behavior required by this suite.
        --@param observation table Observed state supplied to the assertion.
        --@return table|nil value Callback value consumed by the enclosing scenario assertion.
        compaction_snapshot = function(observation)
            if not compaction_lifecycle then return nil end
            A.equal(observation.expected_context_generation, loop_status.context_generation)
            A.equal(observation.expected_last_sequence, loop_status.last_durable_sequence)
            A.equal(observation.expected_manifest_digest, loop_status.active_view_manifest_ref)
            return {
                document = compact_source,
                context_digest = test_digest("canonical-context-source"),
                context_generation = compact_source.generation,
                last_sequence = compact_source.event_count,
                manifest_digest = compact_source.model_view.active_manifest.digest,
                manifest_compaction_id = false,
                view_body_bytes = 12000,
                included_ranges = { {
                    first = 1,
                    last = compact_source.event_count,
                } },
                corrections = {},
                initial_serial = 0,
                initial_automatic_failure_count =
                    settings.initial_automatic_failure_count or 0,
                automatic_failure_history_complete =
                    settings.automatic_failure_history_complete ~= false,
                binding = observation,
            }
        end,
        --Supplies turn context behavior required by this suite.
        --@param observation table Observed state supplied to the assertion.
        --@return table record Fixture record emitted by the scenario callback.
        turn_context = function(observation)
            A.truthy(published)
            A.equal(
                observation.expected_context_generation,
                loop_status.context_generation
            )
            log[#log + 1] = "turn-context"
            return {
                context_generation = loop_status.context_generation,
                overrides = {
                    CurrentModel = durable_current_model,
                    CurrentPermission = "Std",
                    DoubleCheckOverride = durable_double_check_override,
                    DoubleCheckGoalOverride = "inherit",
                    ContextPrompt = durable_context_prompt,
                    AutoRenameDisabled = false,
                },
            }
        end,
        --Supplies update session behavior required by this suite.
        --@param specification table Test specification used to construct the fixture.
        --@return any|nil value Callback value consumed by the enclosing scenario assertion.
        --@return table secondary2 Structured fixture record selected by the exercised branch.
        update_session = function(specification)
            if settings.session_update_exception then
                error("injected Session publication exception")
            end
            if settings.session_update_unknown then
                log[#log + 1] = "publication:session-unknown"
                return nil, { code = "ContextPublicationUnknown" }
            end
            A.equal(
                specification.expected_context_generation,
                loop_status.context_generation
            )
            A.equal(
                specification.expected_last_sequence,
                loop_status.last_durable_sequence
            )
            A.equal(
                specification.expected_manifest_digest,
                loop_status.active_view_manifest_ref
            )
            A.falsy(specification.mode)
            local prompt_update = specification.name == "ContextPrompt"
            local model_update = specification.name == "CurrentModel"
            if model_update then
                A.equal(specification.value, "Secondary")
                A.equal(specification.generation.current_model, "Secondary")
                durable_current_model = specification.value
            elseif prompt_update then
                A.equal(specification.value, "bounded production guidance")
                A.equal(
                    specification.generation.context_prompt,
                    "bounded production guidance"
                )
                durable_context_prompt = specification.value
            else
                A.equal(specification.name, "DoubleCheckOverride")
                A.equal(specification.value, false)
                A.falsy(specification.generation.effective_double_check)
                durable_double_check_override = specification.value
            end
            local first_sequence = loop_status.last_durable_sequence + 1
            local manifest_digest = model_update and "view-session-model"
                or prompt_update and "view-session-prompt"
                or "view-session-override"
            local record = {
                kind = "session-override",
                name = specification.name,
                old_value_digest = model_update and "sha256:model-primary"
                    or prompt_update and "sha256:prompt-old"
                    or "sha256:cautious-on",
                new_value_digest = model_update and "sha256:model-secondary"
                    or prompt_update and "sha256:prompt-new"
                    or "sha256:cautious-off",
                effective_at = "next-turn",
                replaces_manifest_digest = loop_status.active_view_manifest_ref,
                manifest_digest = manifest_digest,
                compaction_id = false,
                view_context_generation = loop_status.context_generation + 1,
            }
            local batch = {
                barrier_id = "session-override:test",
                first_sequence = first_sequence,
                last_sequence = first_sequence + 1,
                event_count = 2,
                expected_context_generation = loop_status.context_generation,
                events = {
                    {
                        seq = first_sequence,
                        type = "session_override",
                        turn_id = false,
                        fields = {
                            name = record.name,
                            oldValueDigest = record.old_value_digest,
                            newValueDigest = record.new_value_digest,
                            effectiveAt = record.effective_at,
                        },
                    },
                    {
                        seq = first_sequence + 1,
                        type = "model_view_published",
                        turn_id = false,
                        fields = {
                            manifestDigest = manifest_digest,
                            firstEventSeq = "1",
                            lastEventSeq = tostring(first_sequence),
                            replacesManifestDigest
                                = record.replaces_manifest_digest,
                        },
                    },
                },
            }
            log[#log + 1] = "publication:session-override"
            return record, {
                barrier_id = batch.barrier_id,
                first_sequence = batch.first_sequence,
                last_sequence = batch.last_sequence,
                event_count = batch.event_count,
                binding = batch,
                previous_context_generation = loop_status.context_generation,
                context_generation = loop_status.context_generation + 1,
            }
        end,
        --Supplies capture turn behavior required by this suite.
        --@param specification table Test specification used to construct the fixture.
        --@return table record Fixture record emitted by the scenario callback.
        capture_turn = function(specification)
            A.truthy(specification.kind == "main" or specification.kind == "ask")
            local reopening = continuing
                and specification.source == "context-reopen"
            if reopening then
                A.contains(specification.text, "latest durable Context facts")
                A.equal(specification.source, "context-reopen")
                A.equal(specification.expected_context_generation, 7)
            else
                A.equal(
                    specification.text,
                    specification.kind == "ask" and "inspect durable facts" or "second turn"
                )
                A.equal(specification.source, "terminal")
                A.equal(specification.expected_context_generation, continuing and 7 or 2)
            end
            log[#log + 1] = "capture-turn"
            if settings.after_capture then settings.after_capture() end
            local prompt_snapshot = reopening and "prompt-snapshot-1"
                or specification.kind == "ask"
                and "ask-prompt-snapshot-2"
                or "prompt-snapshot-2"
            local suffix = reopening and "1" or "2"
            return {
                text = specification.text,
                source = specification.source,
                config_generation = "config-snapshot-" .. suffix,
                model_snapshot = "model-snapshot-" .. suffix,
                permission_snapshot = "permission-snapshot-" .. suffix,
                prompt_snapshot = prompt_snapshot,
                tool_registry_snapshot = "registry-1",
                view_manifest_ref = reopening
                    and "sha256:restored-view" or "view-1",
                double_check = true,
                context_generation = specification.expected_context_generation,
                model_request_limit = reopening and 7 or 6,
                tool_call_limit = reopening and 11 or 10,
                queue_limit = reopening and 5 or 4,
            }
        end,
        --Supplies resolve view behavior required by this suite.
        --@param digest string Expected or computed hexadecimal digest.
        --@return table record Fixture record emitted by the scenario callback.
        resolve_view = function(digest)
            A.equal(digest, loop_status.active_view_manifest_ref)
            return {
                digest = digest,
                first_sequence = loop_status.last_durable_sequence > 1 and 1 or 0,
                last_sequence = math.max(0, loop_status.last_durable_sequence - 1),
                body = "<DurableFacts><Goal>implement</Goal></DurableFacts>",
            }
        end,
        --Supplies prepare view behavior required by this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return table record Fixture record emitted by the scenario callback.
        prepare_view = function() return {} end,
        --Simulates the commit publication step for this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return boolean accepted Whether the fake callback accepts this scenario.
        commit = function() return true end,
    }
    local safety = {
        digest = test_digest,
        --Computes or records binding digest data for this suite.
        --@param domain string Namespace used to classify this value.
        --@param fields table Field values used to construct the test document.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        binding_digest = function(domain, fields)
            A.equal(domain, "yaca-tool-authority-v1")
            A.equal(fields[1].value, "call-digest")
            return string.rep("a", 64)
        end,
    }
    local contexts = {
        safety = safety,
        path = {},
        prompt = {
            --Supplies assemble behavior required by this suite.
            --@param _ any Unused callback argument supplied by the port.
            --@param specification table Test specification used to construct the fixture.
            --@return table record Fixture record emitted by the scenario callback.
            assemble = function(_, specification)
                A.equal(specification.purpose, "main")
                A.equal(specification.tool_mode, "registered")
                return {
                    digest = "prompt-preflight-digest",
                    estimated_token_upper_bound = 512,
                }
            end,
        },
        tool_registry = { digest = "registry-1", tools = {} },
    }
    local model_activities = {}
    local tool_port = {
        --Simulates the poll transition of a fake activity port for this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return table record Fixture record emitted by the scenario callback.
        --@return boolean secondary2 Explicit false rejection from the fake port.
        poll = function() return {}, false end,
        --Supplies active handle behavior required by this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return boolean accepted Whether the fake callback accepts this scenario.
        active_handle = function() return false end,
    }
    local review_port = {
        --Simulates the poll transition of a fake activity port for this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return table record Fixture record emitted by the scenario callback.
        poll = function() return {} end,
        --Simulates the status transition of a fake activity port for this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return table record Fixture record emitted by the scenario callback.
        status = function() return { state = "idle" } end,
    }
    local compaction_port = {
        --Simulates the start transition of a fake activity port for this suite.
        --@param specification table Test specification used to construct the fixture.
        --@return table|string value Callback value consumed by the enclosing scenario assertion.
        start = function(specification)
            if not compaction_lifecycle then return {} end
            settings.compaction_specification = specification
            settings.compaction_response_pending = true
            settings.compaction_port_state = "active"
            log[#log + 1] = "effect:compaction-model"
            return "compaction-model-handle"
        end,
        --Simulates the cancel transition of a fake activity port for this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return table record Fixture record emitted by the scenario callback.
        cancel = function()
            settings.compaction_port_state = "idle"
            return { outcome = "cancelled" }
        end,
        --Simulates the poll transition of a fake activity port for this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return table record Fixture record emitted by the scenario callback.
        poll = function()
            if not compaction_lifecycle
                or not settings.compaction_response_pending
            then return {} end
            settings.compaction_response_pending = false
            settings.compaction_port_state = "idle"
            local specification = settings.compaction_specification
            local summary = {
                schema_version = specification.summary_schema,
                source_first_seq = specification.source_first_seq,
                source_last_seq = specification.source_last_seq,
                source_digest = specification.source_digest,
                goals_decisions = "继续实现通用 Agent 与可靠压缩",
                constraints_permissions = "保留事实并维持权限边界",
                files_touched = "src/main.lua and src/runtime.lua",
                verification_evidence = "production composition fixture",
                unknown_side_effects = "none observed",
                open_todos = "automatic trigger and target qualification",
                prompt_model_transitions = "frozen model snapshot retained",
            }
            local body = compact.encode_summary(summary)
            return { {
                kind = "response",
                response = {
                    request_id = specification.request_id,
                    canonical_body = body,
                    canonical_digest = test_digest(body),
                    source_first_seq = specification.source_first_seq,
                    source_last_seq = specification.source_last_seq,
                    source_digest = specification.source_digest,
                    generator_model_snapshot = specification.model_snapshot.digest,
                    summary = summary,
                    usage = {
                        input_tokens = 4000,
                        output_tokens = 256,
                        estimated = false,
                    },
                    completion = {
                        incomplete = false,
                        finish_class = "stop",
                        tool_call_count = 0,
                        control = false,
                    },
                },
            } }
        end,
        --Simulates the status transition of a fake activity port for this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return table record Fixture record emitted by the scenario callback.
        status = function()
            return { state = settings.compaction_port_state or "idle" }
        end,
    }
    local runtime_ports

    local modules = {}
    modules.context = {
        --Constructs new operation service for this test scenario.
        --@param ports table Ports supplied to the component under test.
        --@param options table|nil Options configuring the exercised component.
        --@return table record Fixture record emitted by the scenario callback.
        new_operation_service = function(ports, options)
            A.equal(ports.journal, operation_journal)
            A.equal(options.maximum_identifier_bytes, 256)
            log[#log + 1] = "operations"
            return {
                --Simulates the begin transition of a fake activity port for this suite.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; the fake port or test assertion observes this callback's effects.
                begin = function() end,
                --Simulates the finish transition of a fake activity port for this suite.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; the fake port or test assertion observes this callback's effects.
                finish = function() end,
                --Simulates the status transition of a fake activity port for this suite.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; the fake port or test assertion observes this callback's effects.
                status = function() end }
        end,
    }
    modules.permission = {
        --Constructs the new service used by this suite.
        --@param _ any Unused callback argument supplied by the port.
        --@param options table|nil Options configuring the exercised component.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        new = function(_, options)
            A.equal(options.maximum_name_bytes, 128)
            local service = {}
            --Builds the profile values used by this suite.
            --@param self table Fixture or port instance receiving this call.
            --@param spec table Test specification or request under evaluation.
            --@return table observed Structured fixture record with snapshot_digest.
            function service:profile(spec)
                A.equal(spec.config_generation, active_generation.id)
                A.equal(spec.matrix.Read, "allow")
                A.equal(spec.matrix.OutsideWorkspace, "confirm")
                log[#log + 1] = "permission-profile"
                return { snapshot_digest = "profile-snapshot-" .. active_generation.id:sub(-1) }
            end
            return service
        end,
    }
    modules.tools = {
        --Constructs the new service used by this suite.
        --@param dependencies any The dependencies supplied to the fake service for this scenario.
        --@param options table|nil Options configuring the exercised component.
        --@return table record Fixture record emitted by the scenario callback.
        new = function(dependencies, options)
            A.equal(options.workspace_path, "/workspace")
            A.equal(options.reserved_paths[1], "/release/__yaca__")
            A.equal(options.maximum_exec_output_bytes, settings.expected_output_bytes or 65536)
            local facts = {
                permission_snapshot_digest = "profile-snapshot-" .. active_generation.id:sub(-1),
                approval_digest = "",
                durable_intent_digest = "not-required:call-digest",
                config_generation = active_generation.id,
                workspace_identity = "volume-1\0workspace-1\0directory",
                double_check = true,
                action_review = "not-required",
            }
            local admitted, digest = dependencies.authorization.admit({
                call_digest = "call-digest",
            }, facts)
            A.truthy(admitted)
            A.truthy(dependencies.authorization.reverify({
                call_digest = "call-digest",
            }, facts, digest))
            log[#log + 1] = "tools"
            if settings.after_tools then settings.after_tools() end
            return { registry_digest = settings.tool_registry_digest or "registry-1" }
        end,
        --Constructs new agent port for this test scenario.
        --@param _ any Unused callback argument supplied by the port.
        --@param options table|nil Options configuring the exercised component.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        new_agent_port = function(_, options)
            A.equal(options.config_generation, active_generation.id)
            A.equal(options.exec_policy.decoder, "utf-8-strict-candidate-v1")
            A.equal(options.exec_policy.output_limit_bytes, settings.expected_output_bytes or 65536)
            A.equal(options.exec_policy.deadline_ms, active_generation.exec.timeout_ms)
            log[#log + 1] = "tool-port"
            return tool_port
        end,
    }
    modules.model = {
        --Constructs new request builder for this test scenario.
        --@param _ any Unused callback argument supplied by the port.
        --@param options table|nil Options configuring the exercised component.
        --@return table record Fixture record emitted by the scenario callback.
        new_request_builder = function(_, options)
            local suffix = active_generation.id:sub(-1)
            A.equal(options.model_snapshot, "model-snapshot-" .. suffix)
            A.equal(options.prompt_snapshot, "prompt-snapshot-" .. suffix)
            A.equal(options.default_max_output_tokens, 4096)
            log[#log + 1] = "model-builder"
            return {}
        end,
        --Constructs new ask request builder for this test scenario.
        --@param ports table Ports supplied to the component under test.
        --@param options table|nil Options configuring the exercised component.
        --@return table record Fixture record emitted by the scenario callback.
        new_ask_request_builder = function(ports, options)
            A.equal(ports.generation.id, "config-generation-2")
            A.equal(options.model_name, "Primary")
            A.equal(options.permission_name, "Std")
            A.equal(options.prompt_snapshot, "ask-prompt-snapshot-2")
            A.equal(options.tool_registry_snapshot, "registry-1")
            A.equal(options.maximum_request_time_ms, 120000)
            A.equal(options.maximum_output_tokens, 1024)
            log[#log + 1] = "ask-model-builder"
            return {}
        end,
        --Constructs new compaction request builder for this test scenario.
        --@param _ any Unused callback argument supplied by the port.
        --@param options table|nil Options configuring the exercised component.
        --@return table record Fixture record emitted by the scenario callback.
        new_compaction_request_builder = function(_, options)
            local suffix = active_generation.id:sub(-1)
            A.equal(options.model_snapshot, "model-snapshot-" .. suffix)
            A.equal(options.prompt_snapshot, "prompt-snapshot-" .. suffix)
            A.equal(options.maximum_source_bytes, 16 * 1024 * 1024)
            log[#log + 1] = "compaction-builder"
            return {}
        end,
        --Constructs new review request builder for this test scenario.
        --@param _ any Unused callback argument supplied by the port.
        --@param options table|nil Options configuring the exercised component.
        --@return table record Fixture record emitted by the scenario callback.
        new_review_request_builder = function(_, options)
            A.equal(options.main_model_name, "Primary")
            A.equal(
                options.config_snapshot,
                "config-snapshot-" .. active_generation.id:sub(-1)
            )
            A.equal(options.default_max_output_tokens, 1024)
            log[#log + 1] = "review-builder"
            return {}
        end,
        --Constructs new activity for this test scenario.
        --@param _ any Unused callback argument supplied by the port.
        --@param options table|nil Options configuring the exercised component.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        new_activity = function(_, options)
            A.equal(options.identity_namespace, "context-0123456789ABCDEF")
            local serial = #model_activities + 1
            local activity = {
                --Simulates the start transition of a fake activity port for this suite.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return table record Fixture record emitted by the scenario callback.
                start = function()
                    log[#log + 1] = "effect:model-activity-" .. tostring(serial)
                    return {}
                end,
                --Simulates the cancel transition of a fake activity port for this suite.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return table record Fixture record emitted by the scenario callback.
                cancel = function() return { outcome = "cancelled" } end,
                --Simulates the poll transition of a fake activity port for this suite.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return table record Fixture record emitted by the scenario callback.
                poll = function() return {} end,
                --Simulates the status transition of a fake activity port for this suite.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return table record Fixture record emitted by the scenario callback.
                status = function() return { state = "idle" } end,
            }
            model_activities[#model_activities + 1] = activity
            log[#log + 1] = "model-activity-" .. tostring(#model_activities)
            return activity
        end,
        --Constructs new review port for this test scenario.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        new_review_port = function()
            log[#log + 1] = "review-port"
            return review_port
        end,
        --Constructs new compaction port for this test scenario.
        --@param _ any Unused callback argument supplied by the port.
        --@param options table|nil Options configuring the exercised component.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        new_compaction_port = function(_, options)
            A.equal(options.maximum_poll_events, 128)
            log[#log + 1] = "compaction-port"
            return compaction_port
        end,
    }
    modules.json = {
        --Constructs the new service used by this suite.
        --@param options table|nil Options configuring the exercised component.
        --@return table record Fixture record emitted by the scenario callback.
        new = function(options)
            A.equal(options.maximum_bytes, 1024 * 1024)
            return {}
        end,
    }
    local runtime_options_seen
    modules.runtime = {
        --Constructs new agent loop for this test scenario.
        --@param ports table Ports supplied to the component under test.
        --@param options table|nil Options configuring the exercised component.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        new_agent_loop = function(ports, options)
            A.equal(ports.journal, publication)
            A.truthy(ports.model ~= model_activities[1])
            A.truthy(ports.tools ~= tool_port)
            A.truthy(ports.reviews ~= review_port)
            A.equal(type(ports.snapshots.capture), "function")
            A.equal(type(ports.ask.start), "function")
            A.equal(type(ports.ask.poll), "function")
            A.equal(options.hard_caps.model_requests, 64)
            A.equal(options.hard_caps.tool_calls, 256)
            A.equal(options.lanes.queue_maximum, 9)
            A.truthy(options.automatic_compaction)
            runtime_options_seen = options
            runtime_ports = ports
            log[#log + 1] = "agent-loop"
            return loop
        end,
        --Constructs new agent activity driver for this test scenario.
        --@param ports table Ports supplied to the component under test.
        --@param options table|nil Options configuring the exercised component.
        --@return table record Fixture record emitted by the scenario callback.
        new_agent_activity_driver = function(ports, options)
            A.equal(ports.loop, loop)
            A.equal(ports.model, runtime_ports.model)
            A.equal(ports.tools, runtime_ports.tools)
            A.equal(ports.reviews, runtime_ports.reviews)
            A.equal(ports.ask, runtime_ports.ask)
            A.equal(options.maximum_output_events, 512)
            log[#log + 1] = "driver"
            return {
                --Simulates the step transition of a fake activity port for this suite.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return table record Fixture record emitted by the scenario callback.
                step = function() return {} end }
        end,
    }
    modules.session = {
        --Constructs new agent session for this test scenario.
        --@param candidate table|any Candidate state or value being validated.
        --@param options table|nil Options configuring the exercised component.
        --@return table|nil value Callback value consumed by the enclosing scenario assertion.
        --@return table|nil secondary2 Typed error record with code InjectedSessionFailure.
        new_agent_session = function(candidate, options)
            A.equal(candidate, loop)
            A.equal(options.maximum_draft_bytes, 16384)
            log[#log + 1] = "agent-session"
            if settings.session_error then
                return nil, { code = "InjectedSessionFailure" }
            end
            return {
                --Simulates the status transition of a fake activity port for this suite.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return table record Fixture record emitted by the scenario callback.
                status = function() return {} end }
        end,
    }

    local draft = {}
    --Supplies begin main behavior required by this suite.
    --@param message string|table Message or diagnostic passed through this test port.
    --@param source string|table Source content or object under test.
    --@return table observed Structured fixture record with durable.
    function draft.begin_main(message, source)
        A.falsy(continuing)
        A.equal(message, "implement the project")
        A.equal(source, "terminal")
        A.falsy(published)
        published = true
        log[#log + 1] = "publish-first"
        return { durable = true }
    end
    --Supplies begin ask behavior required by this suite.
    --@param message string|table Message or diagnostic passed through this test port.
    --@param source string|table Source content or object under test.
    --@return table observed Structured fixture record selected by the exercised branch.
    function draft.begin_ask(message, source)
        A.equal(message, "only a question"); A.equal(source, "terminal")
        A.falsy(published); published = true
        log[#log + 1] = "publish-empty"
        return { durable = true, event_count = 0, generation = 1,
            view_manifest_snapshot = "sha256:empty-view",
            runtime_initial_serials = { turn = 0, message = 0, request = 0, tool = 0,
                operation = 0, queue = 0, queue_display = 0, ask = 0 } }
    end
    --Supplies agent handoff behavior required by this suite.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return any observed agent handoff value observed by the scenario assertion.
    function draft.agent_handoff()
        A.truthy(published)
        return handoff
    end
    --Builds the config generation values used by this suite.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return any observed config generation value observed by the scenario assertion.
    function draft.config_generation() return generation end
    --Supplies open receipt behavior required by this suite.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return table observed Structured fixture record selected by the exercised branch.
    function draft.open_receipt()
        A.truthy(continuing)
        return {
            durable = true,
            auto_continue = true,
            generation = 7,
            event_count = 29,
            last_sequence = 29,
            view_manifest_snapshot = "sha256:restored-view",
            approval_initial_serial = 7,
            runtime_initial_serials = {
                turn = 4, message = 8, request = 6, tool = 3,
                operation = 2, queue = 5, queue_display = 2, ask = 1,
            },
        }
    end
    --Simulates the status transition of a fake activity port for this suite.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return table observed Structured fixture record selected by the exercised branch.
    function draft.status()
        return {
            workspace = "/workspace",
            permission = "Std",
            model = "Primary",
            double_check = true,
            context_prompt = "workspace context",
            context_hash = published and "0123456789ABCDEF" or false,
        }
    end
    --Simulates the close transition of a fake activity port for this suite.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether close succeeds in the fixture.
    function draft.close()
        closed = true
        log[#log + 1] = "draft-close"
        return true
    end

    local composed = {
        backend = {
            filesystem = {
                --Supplies the direct inspect observation used by this suite.
                --@param path string File or Context path exercised by the case.
                --@return boolean accepted Whether the fake callback accepts this scenario.
                --@return table secondary2 Structured fixture record with identity, volume, object, kind.
                direct_inspect = function(path)
                    A.truthy(published)
                    A.equal(path, "/workspace")
                    return true, {
                        identity = {
                            volume = "volume-1",
                            object = settings.workspace_object or "workspace-1",
                            kind = "directory",
                        },
                    }
                end,
            },
            processes = {},
            clock_port = {
                --Supplies deterministic clock behavior for this suite.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return integer value Callback value consumed by the enclosing scenario assertion.
                monotonic_now = function() return 1 end,
                --Supplies deterministic clock behavior for this suite.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return string text Text emitted by the scenario callback.
                utc_now = function() return "2026-08-30T00:00:00Z" end,
            },
        },
        contexts = contexts,
        publication = publication,
        config = {
            --Supplies reload file behavior required by this suite.
            --@param path string File or Context path exercised by the case.
            --@param overrides table|nil Per-case overrides of default fixture behavior.
            --@return any value Callback value consumed by the enclosing scenario assertion.
            reload_file = function(path, overrides)
                A.equal(path, "/release/__yaca__/config.ini")
                A.truthy(overrides.CurrentModel == "Primary"
                    or overrides.CurrentModel == "Secondary")
                log[#log + 1] = "config-reload"
                local reloaded = next_generation
                if overrides.CurrentModel == "Secondary" then
                    reloaded = {}
                    for key, value in pairs(next_generation) do
                        reloaded[key] = value
                    end
                    reloaded.id = "config-generation-model-secondary"
                    reloaded.current_model = "Secondary"
                    if settings.model_definition_changed_on_reload then
                        local models = {}
                        for name, model in pairs(next_generation.models) do
                            models[name] = model
                        end
                        local changed = {}
                        for key, value in pairs(models.Secondary) do
                            changed[key] = value
                        end
                        changed.endpoint = "https://changed.example/v1/messages"
                        models.Secondary = changed
                        reloaded.models = models
                    end
                elseif overrides.ContextPrompt ~= "workspace context" then
                    reloaded = {}
                    for key, value in pairs(next_generation) do
                        reloaded[key] = value
                    end
                    reloaded.id = "config-generation-prompt"
                    reloaded.context_prompt = overrides.ContextPrompt
                elseif overrides.DoubleCheckOverride == false then
                    reloaded = {}
                    for key, value in pairs(next_generation) do
                        reloaded[key] = value
                    end
                    reloaded.id = "config-generation-cautious-off"
                    reloaded.effective_double_check = false
                end
                active_generation = reloaded
                return reloaded
            end,
        },
        model_adapter = {},
        network = {},
        identity = { os = "linux" },
        layout = {
            data_root = "/release/__yaca__",
            config_path = "/release/__yaca__/config.ini",
        },
        model_activity_options = {
            maximum_poll_events = 128,
            maximum_turn_time_ms = 3600000,
            maximum_canonical_body_bytes = 65536,
        },
    }
    local chat = {
        kind = continuing and "continue-chat" or "run-chat",
        outcome = "ready",
        draft = draft,
        workspace_identity = continuing and {
            volume = "volume-1", object = "workspace-1", kind = "directory",
        } or nil,
    }
    return {
        main = load_main(modules),
        composed = composed,
        chat = chat,
        log = log,
        --Supplies closed behavior required by this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        closed = function() return closed end,
        --Supplies loop closed behavior required by this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        loop_closed = function() return loop_closed end,
        --Supplies capture behavior required by this suite.
        --@param specification table Test specification used to construct the fixture.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        capture = function(specification)
            return runtime_ports.snapshots.capture(specification)
        end,
        --Supplies start current model behavior required by this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        start_current_model = function()
            return runtime_ports.model.start({ request_id = "turn-2:request:1" })
        end,
        --Supplies start ask model behavior required by this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        start_ask_model = function()
            return runtime_ports.ask.start({
                ask_id = "ask-1",
                turn_id = "ask-1",
                request_id = "ask-1:request:1",
                purpose = "ask",
                view_manifest_ref = "view-1",
                no_tools = true,
                active_time_cap_ms = 120000,
                response_byte_cap = 65536,
                budget_snapshot_id = "tp022-modern-candidate-v1",
            })
        end,
        --Supplies pause for compaction behavior required by this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return nil No value; the fake port or test assertion observes this callback's effects.
        pause_for_compaction = function()
            A.truthy(compact_source)
            loop_status.state = "Idle"
            loop_status.turn_id = false
            loop_status.context_generation = compact_source.generation
            loop_status.last_durable_sequence = compact_source.event_count
            loop_status.active_view_manifest_ref
                = compact_source.model_view.active_manifest.digest
        end,
        --Supplies pause for automatic compaction behavior required by this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return nil No value; the fake port or test assertion observes this callback's effects.
        pause_for_automatic_compaction = function()
            A.truthy(compact_source)
            loop_status.state = "Preparing"
            loop_status.turn_id = "turn-1"
            loop_status.context_generation = compact_source.generation
            loop_status.last_durable_sequence = compact_source.event_count
            loop_status.active_view_manifest_ref
                = compact_source.model_view.active_manifest.digest
            loop_status.compaction_preflight_state = "pending"
            loop_status.compaction_preflight_id
                = "turn-1:compaction-preflight:1"
            loop_status.compaction_preflight_purpose = "main"
        end,
        --Supplies current generation behavior required by this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        current_generation = function() return active_generation end,
        --Supplies runtime options behavior required by this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        runtime_options = function() return runtime_options_seen end,
    }
end

return {
    name = "integration/production-agent-composition",
    cases = {
        {
            name = "configured output below the durable result cap stays effective in production",
            --Verifies configured output below the durable result cap stays effective in production.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify configured output below the durable result cap stays effective in production.
            run = function()
                local f = fixture({ max_output_kb = 16, expected_output_bytes = 16384 })
                A.truthy(f.main.start_published_agent(
                    f.composed, f.chat, "implement the project", "terminal"))
            end,
        },
        {
            name = "first Ask composes an idle Agent without resuming a main request",
            --Verifies configured output below the durable result cap stays effective in production.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify configured output below the durable result cap stays effective in production.
            run = function()
                local f = fixture()
                local agent = assert(f.main.start_published_agent(
                    f.composed, f.chat, "only a question", "terminal", "ask"))
                A.falsy(agent.capabilities.published_first_turn)
                A.falsy(agent.admission)
                A.equal(f.runtime_options().initial_sequence, 0)
                A.equal(f.runtime_options().initial_serials.turn, 0)
                A.equal(f.runtime_options().initial_serials.ask, 0)
                A.falsy(table.concat(f.log, "|"):find("runtime-resume", 1, true))
                A.equal(f.log[1], "publish-empty")
            end,
        },
        {
            name = "production status uses publication ownership and halts on inspection failure",
            --Verifies first Ask composes an idle Agent without resuming a main request.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify first Ask composes an idle Agent without resuming a main request.
            run = function()
                for _, throws in ipairs({ false, true }) do
                    local settings = {}
                    local f = fixture(settings)
                    local agent = assert(f.main.start_published_agent(
                        f.composed, f.chat, "implement the project", "terminal"
                    ))
                    A.equal(assert(agent.context_status()).context_hash, "ABCDABCD12341234")
                    settings.context_inspection_throws = throws
                    settings.context_inspection_error = { code = "TargetChanged" }
                    local result, result_error = agent.context_status()
                    A.falsy(result)
                    A.equal(result_error.code, "ContextStale")
                    A.falsy(A.render(result_error):find("private diagnostic", 1, true))
                    A.truthy(agent.loop:status().halted)
                    A.contains(table.concat(f.log, "|"), "runtime-context-stale")
                end
            end,
        },
        {
            name = "durable first turn precedes every production Agent activity",
            --Verifies durable first turn precedes every production Agent activity.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify durable first turn precedes every production Agent activity.
            run = function()
                local f = fixture()
                local agent = assert(f.main.start_published_agent(
                    f.composed,
                    f.chat,
                    "implement the project",
                    "terminal"
                ))
                A.equal(agent.admission.request_id, "turn-1:request:1")
                A.equal(agent.loop:status().state, "RequestingModel")
                A.truthy(agent.capabilities.published_first_turn)
                A.truthy(agent.capabilities.later_turn_snapshots)
                A.truthy(agent.capabilities.ask)
                A.truthy(agent.capabilities.compaction)
                A.falsy(f.closed())
                A.deep_equal(f.log, {
                    "publish-first",
                    "operation-journal",
                    "operations",
                    "permission-profile",
                    "tools",
                    "tool-port",
                    "model-builder",
                    "model-activity-1",
                    "compaction-builder",
                    "model-activity-2",
                    "compaction-port",
                    "review-builder",
                    "model-activity-3",
                    "review-port",
                    "agent-loop",
                    "compaction-journal",
                    "runtime-resume",
                    "driver",
                    "agent-session",
                })
            end,
        },
        {
            name = "verified existing Context composes an idle collision-free Agent owner",
            --Verifies verified existing Context composes an idle collision-free Agent owner.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify verified existing Context composes an idle collision-free Agent owner.
            run = function()
                local f = fixture({ continuing = true })
                local agent = assert(f.main.start_published_agent(
                    f.composed,
                    f.chat,
                    "Continue from the latest durable Context facts.",
                    "context-reopen"
                ))
                A.equal(agent.admission, false)
                A.equal(agent.loop:status().state, "Idle")
                A.truthy(agent.capabilities.reopened_existing_context)
                A.equal(agent.approval_initial_serial, 7)
                A.falsy(agent.capabilities.published_first_turn)
                local options = f.runtime_options()
                A.equal(options.initial_sequence, 29)
                A.equal(options.initial_context_generation, 7)
                A.equal(options.initial_view_manifest_ref, "sha256:restored-view")
                A.equal(options.initial_serials.turn, 4)
                A.equal(options.initial_serials.message, 8)
                A.equal(options.initial_serials.queue, 5)
                A.deep_equal(f.log, {
                    "capture-turn",
                    "operation-journal",
                    "operations",
                    "permission-profile",
                    "tools",
                    "tool-port",
                    "model-builder",
                    "model-activity-1",
                    "compaction-builder",
                    "model-activity-2",
                    "compaction-port",
                    "review-builder",
                    "model-activity-3",
                    "review-port",
                    "agent-loop",
                    "compaction-journal",
                    "driver",
                    "agent-session",
                })
            end,
        },
        {
            name = "continued workspace replacement fails before Agent admission",
            --Verifies continued workspace replacement fails before Agent admission.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify continued workspace replacement fails before Agent admission.
            run = function()
                for _, phase in ipairs({ "before", "capture", "tools", "missing" }) do
                    local settings = { continuing = true }
                    local f = fixture(settings)
                    --Records the replace effect observed by the 'continued workspace replacement fails before Agent admission' case.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return nil No value; assertions verify continued workspace replacement fails before Agent admission.
                    local function replace() settings.workspace_object = "replacement" end
                    if phase == "before" then replace() end
                    if phase == "capture" then settings.after_capture = replace end
                    if phase == "tools" then settings.after_tools = replace end
                    if phase == "missing" then f.chat.workspace_identity = nil end
                    local agent, agent_error = f.main.start_published_agent(
                        f.composed, f.chat,
                        "Continue from the latest durable Context facts.", "context-reopen"
                    )
                    A.falsy(agent)
                    A.equal(agent_error.code, phase == "missing"
                        and "InvalidAgentComposition" or "ContextTargetChanged")
                    A.truthy(f.closed())
                    for _, entry in ipairs(f.log) do
                        A.falsy(entry:match("^effect:"))
                        A.falsy(entry == "agent-loop")
                        if phase == "before" or phase == "missing" then
                            A.falsy(entry == "capture-turn" or entry == "tools")
                        end
                    end
                end
            end,
        },
        {
            name = "continued main and ask snapshots retain the confirmed workspace identity",
            --Verifies continued main and ask snapshots retain the confirmed workspace identity.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify continued main and ask snapshots retain the confirmed workspace identity.
            run = function()
                for _, kind in ipairs({ "main", "ask" }) do
                    for _, phase in ipairs({ "before", "capture" }) do
                        local settings = { continuing = true }
                        local f = fixture(settings)
                        local agent = assert(f.main.start_published_agent(
                            f.composed, f.chat,
                            "Continue from the latest durable Context facts.", "context-reopen"
                        ))
                        --Records the replace effect observed by the 'continued main and ask snapshots retain the confirmed workspace identity' case.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return nil No value; assertions verify continued main and ask snapshots retain the confirmed workspace identity.
                        local function replace() settings.workspace_object = "replacement" end
                        if phase == "before" then replace()
                        else settings.after_capture = replace end
                        local previous_count = #f.log
                        local snapshot, snapshot_error = f.capture({
                            kind = kind,
                            text = kind == "main" and "second turn" or "inspect durable facts",
                            source = "terminal",
                            context_generation = 7,
                            active_turn_id = false,
                            cause = { kind = kind == "main" and "direct-main" or "ask" },
                        })
                        A.falsy(snapshot)
                        A.equal(snapshot_error.code, "ContextTargetChanged")
                        A.equal(agent.current_generation().id, "config-generation-1")
                        for index = previous_count + 1, #f.log do
                            A.falsy(f.log[index]:match("^effect:"))
                            A.falsy(f.log[index] == "tools" or f.log[index] == "ask-model-builder")
                        end
                        if phase == "before" then A.equal(#f.log, previous_count) end
                        f.chat.draft.close()
                    end
                end
            end,
        },
        {
            name = "production Session settings publish and adopt cautious for the next turn",
            --Verifies production Session settings publish and adopt cautious for the next turn.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify production Session settings publish and adopt cautious for the next turn.
            run = function()
                local f = fixture()
                local agent = assert(f.main.start_published_agent(
                    f.composed,
                    f.chat,
                    "implement the project",
                    "terminal"
                ))
                A.truthy(agent.capabilities.session_settings)
                local before = assert(agent.settings:status())
                A.truthy(before.double_check_default)
                A.truthy(before.double_check_override)
                A.truthy(before.double_check_effective)
                local updated = assert(agent.settings:update({
                    name = "DoubleCheckOverride",
                    value = false,
                }))
                A.falsy(updated.double_check_override)
                A.falsy(updated.double_check_effective)
                A.equal(updated.effective_at, "next-turn")
                A.equal(updated.context_generation, 3)
                A.equal(agent.loop:status().last_durable_sequence, 5)
                A.equal(
                    agent.loop:status().active_view_manifest_ref,
                    "view-session-override"
                )
                -- Active turn ports retain their captured generation. The
                -- reloaded settings generation is adopted only for next turn.
                A.equal(agent.current_generation().id, "config-generation-1")
                A.equal(
                    f.current_generation().id,
                    "config-generation-cautious-off"
                )
                local after = assert(agent.settings:status())
                A.falsy(after.double_check_override)
                A.falsy(after.double_check_effective)
                local reload_index, publish_index, adopt_index
                for index, value in ipairs(f.log) do
                    if value == "config-reload" then reload_index = index end
                    if value == "publication:session-override" then
                        publish_index = index
                    end
                    if value == "runtime-adopt:session-override" then
                        adopt_index = index
                    end
                end
                A.truthy(reload_index < publish_index)
                A.truthy(publish_index < adopt_index)
            end,
        },
        {
            name = "production Session settings publish and adopt ContextPrompt for the next turn",
            --Verifies production Session settings publish and adopt ContextPrompt for the next turn.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify production Session settings publish and adopt ContextPrompt for the next turn.
            run = function()
                local f = fixture()
                local agent = assert(f.main.start_published_agent(
                    f.composed,
                    f.chat,
                    "implement the project",
                    "terminal"
                ))
                local before = assert(agent.settings:status())
                A.equal(before.context_prompt, "workspace context")
                local updated = assert(agent.settings:update({
                    name = "ContextPrompt",
                    value = "bounded production guidance",
                }))
                A.equal(updated.context_prompt, "bounded production guidance")
                A.equal(updated.effective_at, "next-turn")
                A.equal(updated.context_generation, 3)
                A.equal(agent.loop:status().last_durable_sequence, 5)
                A.equal(
                    agent.loop:status().active_view_manifest_ref,
                    "view-session-prompt"
                )
                -- The active request retains its captured prompt bundle; only
                -- the next complete turn may build ports from this generation.
                A.equal(agent.current_generation().id, "config-generation-1")
                A.equal(f.current_generation().id, "config-generation-prompt")
                local after = assert(agent.settings:status())
                A.equal(after.context_prompt, "bounded production guidance")
                local reload_index, publish_index, adopt_index
                for index, value in ipairs(f.log) do
                    if value == "config-reload" then reload_index = index end
                    if value == "publication:session-override" then
                        publish_index = index
                    end
                    if value == "runtime-adopt:session-override" then
                        adopt_index = index
                    end
                end
                A.truthy(reload_index < publish_index)
                A.truthy(publish_index < adopt_index)
            end,
        },
        {
            name = "production Model selection binds disclosure then publishes exact next-turn selector",
            --Verifies production Model selection binds disclosure then publishes exact next-turn selector.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify production Model selection binds disclosure then publishes exact next-turn selector.
            run = function()
                local f = fixture()
                local agent = assert(f.main.start_published_agent(
                    f.composed,
                    f.chat,
                    "implement the project",
                    "terminal"
                ))
                A.truthy(agent.capabilities.model_selection)
                local catalog = assert(agent.models:list())
                A.equal(catalog.current, "Primary")
                A.equal(catalog.total, 2)
                A.equal(catalog.rows[1].name, "Primary")
                A.truthy(catalog.rows[1].current)
                A.equal(catalog.rows[2].name, "Secondary")

                local preview = assert(agent.models:preview("sECONDARY"))
                A.truthy(preview.confirmation_required)
                A.equal(preview.effective_at, "next-turn")
                A.equal(preview.from.endpoint_origin, "https://primary.example")
                A.equal(preview.to.endpoint_origin, "https://secondary.example")
                A.equal(preview.history.first_sequence, 1)
                A.equal(preview.history.last_sequence, 2)
                A.equal(preview.history.transition_last_sequence, 4)
                A.truthy(preview.preflight.required_tokens
                    <= preview.preflight.window_tokens)
                local reasons = table.concat(preview.reasons, "|")
                A.contains(reasons, "endpoint-route")
                A.contains(reasons, "credential-policy")
                A.contains(reasons, "protocol")
                A.contains(reasons, "usage-source")
                A.contains(reasons, "history-destination")

                local updated = assert(agent.models:apply(preview))
                A.equal(updated.model, "Secondary")
                A.equal(updated.effective_at, "next-turn")
                A.equal(updated.context_generation, 3)
                A.equal(agent.loop:status().last_durable_sequence, 5)
                A.equal(
                    agent.loop:status().active_view_manifest_ref,
                    "view-session-model"
                )
                A.equal(agent.current_generation().id, "config-generation-1")
                A.equal(
                    f.current_generation().id,
                    "config-generation-model-secondary"
                )
                local after = assert(agent.settings:status())
                A.equal(after.model, "Secondary")
                local repeated, repeat_error = agent.models:apply(preview)
                A.falsy(repeated)
                A.equal(repeat_error.code, "ModelSelectionStale")

                local reload_index, publish_index, adopt_index
                for index, value in ipairs(f.log) do
                    if value == "config-reload" then reload_index = index end
                    if value == "publication:session-override" then
                        publish_index = index
                    end
                    if value == "runtime-adopt:session-override" then
                        adopt_index = index
                    end
                end
                A.truthy(reload_index < publish_index)
                A.truthy(publish_index < adopt_index)
            end,
        },
        {
            name = "production Model previews disclose the sanitized proxy route",
            --Verifies production Model previews disclose the sanitized proxy route.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify production Model previews disclose the sanitized proxy route.
            run = function()
                local route = "https://proxy.example/tunnel?configured"
                local f = fixture({ proxy_route = route })
                local agent = assert(f.main.start_published_agent(
                    f.composed, f.chat, "implement the project", "terminal"
                ))
                local catalog = assert(agent.models:list())
                A.equal(catalog.rows[1].proxy_route, route)
                local preview = assert(agent.models:preview("Secondary"))
                A.equal(preview.from.proxy_route, route)
                A.equal(preview.to.proxy_route, route)
                A.equal(preview.to.proxy_policy, "explicit-secret-slot")
            end,
        },
        {
            name = "secret-only Model reload race is rejected before Context publication",
            --Verifies production Model previews disclose the sanitized proxy route.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify production Model previews disclose the sanitized proxy route.
            run = function()
                local f = fixture({ model_secret_changed_on_reload = true })
                local agent = assert(f.main.start_published_agent(
                    f.composed, f.chat, "implement the project", "terminal"
                ))
                local preview = assert(agent.models:preview("Secondary"))
                local updated, update_error = agent.models:apply(preview)
                A.falsy(updated)
                A.equal(update_error.code, "ModelSelectionStale")
                A.equal(agent.loop:status().context_generation, 2)
                A.equal(agent.loop:status().last_durable_sequence, 3)
                A.equal(agent.loop:status().active_view_manifest_ref, "view-1")
                local joined = table.concat(f.log, "|")
                A.contains(joined, "model-secret-reverify")
                A.falsy(joined:find("publication:session-override", 1, true))
                A.falsy(joined:find("runtime-adopt:session-override", 1, true))
            end,
        },
        {
            name = "Model definition reload race is rejected before Context publication",
            --Verifies model definition reload race is rejected before Context publication.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify model definition reload race is rejected before Context publication.
            run = function()
                local f = fixture({ model_definition_changed_on_reload = true })
                local agent = assert(f.main.start_published_agent(
                    f.composed,
                    f.chat,
                    "implement the project",
                    "terminal"
                ))
                local preview = assert(agent.models:preview("Secondary"))
                local updated, update_error = agent.models:apply(preview)
                A.falsy(updated)
                A.equal(update_error.code, "ModelSelectionStale")
                A.equal(agent.loop:status().context_generation, 2)
                A.equal(agent.loop:status().last_durable_sequence, 3)
                A.equal(agent.loop:status().active_view_manifest_ref, "view-1")
                local joined = table.concat(f.log, "|")
                A.contains(joined, "config-reload")
                A.falsy(joined:find("publication:session-override", 1, true))
                A.falsy(joined:find("runtime-adopt:session-override", 1, true))
            end,
        },
        {
            name = "smaller Model that cannot carry Prompt tools and view is rejected before staging",
            --Verifies smaller Model that cannot carry Prompt tools and view is rejected before staging.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify smaller Model that cannot carry Prompt tools and view is rejected before staging.
            run = function()
                local f = fixture({ small_model_window = true })
                local agent = assert(f.main.start_published_agent(
                    f.composed,
                    f.chat,
                    "implement the project",
                    "terminal"
                ))
                local preview, preview_error = agent.models:preview("Secondary")
                A.falsy(preview)
                A.equal(preview_error.code, "ModelIncompatible")
                A.contains(preview_error.next_action, ".compact")
                A.equal(agent.loop:status().context_generation, 2)
                A.falsy(table.concat(f.log, "|"):find("config-reload", 1, true))
            end,
        },
        {
            name = "ambiguous Session publication and adoption exceptions halt the Runtime",
            --Verifies smaller Model that cannot carry Prompt tools and view is rejected before staging.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify smaller Model that cannot carry Prompt tools and view is rejected before staging.
            run = function()
                for _, scenario in ipairs({
                    {
                        option = "session_update_unknown",
                        log = "runtime-session-fail:publication-unknown",
                    },
                    {
                        option = "session_update_exception",
                        log = "runtime-session-fail:publication-exception",
                    },
                }) do
                    local options = {}
                    options[scenario.option] = true
                    local f = fixture(options)
                    local agent = assert(f.main.start_published_agent(
                        f.composed,
                        f.chat,
                        "implement the project",
                        "terminal"
                    ))
                    local updated, update_error = agent.settings:update({
                        name = "DoubleCheckOverride",
                        value = false,
                    })
                    A.falsy(updated)
                    A.equal(update_error.code, "AgentDurabilityFailure")
                    A.truthy(agent.loop:status().halted)
                    A.contains(table.concat(f.log, "|"), scenario.log)
                end
            end,
        },
        {
            name = "reopened interactive chat uses its saved Model owner and releases failed terminal setup",
            --Verifies reopened interactive chat uses its saved Model owner and releases failed terminal setup.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify reopened interactive chat uses its saved Model owner and releases failed terminal setup.
            run = function()
                local f = fixture({ continuing = true })
                local calls = {}
                --Supplies deterministic clock behavior for the 'reopened interactive chat uses its saved Model owner and releases failed terminal setup' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether the fake callback accepts this scenario.
                f.composed.backend.clock_port.sleep_ms = function() return true end
                --Constructs new terminal for the reopened interactive chat uses its saved Model owner and releases failed terminal setup scenario.
                --@param mode string Operating mode selected by the scenario.
                --@return nil rejected Explicit rejection from the scenario callback.
                --@return table secondary2 Typed error record with code TerminalUnavailable.
                f.composed.backend.new_terminal = function(mode)
                    A.equal(mode, "cooked")
                    calls[#calls + 1] = "terminal"
                    return nil, { code = "TerminalUnavailable", message = "test terminal failure" }
                end
                local draft = {
                    --Simulates the close transition of a fake activity port for the 'reopened interactive chat uses its saved Model owner and releases failed terminal setup' case.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return boolean accepted Whether the fake callback accepts this scenario.
                    close = function() calls[#calls + 1] = "draft-close" return true end,
                }
                local agent = {
                    models = {
                        --Returns the list observation prepared for the 'reopened interactive chat uses its saved Model owner and releases failed terminal setup' case.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return table record Fixture record emitted by the scenario callback.
                        list = function() return {} end },
                    compaction = {
                        --Simulates the close transition of a fake activity port for the 'reopened interactive chat uses its saved Model owner and releases failed terminal setup' case.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return boolean accepted Whether the fake callback accepts this scenario.
                        close = function() calls[#calls + 1] = "compaction-close" return true end,
                    },
                    session = {
                        --Simulates the close transition of a fake activity port for the 'reopened interactive chat uses its saved Model owner and releases failed terminal setup' case.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return boolean accepted Whether the fake callback accepts this scenario.
                        close = function() calls[#calls + 1] = "session-close" return true end,
                    },
                    draft = draft,
                }
                local result, result_error = f.main.run_interactive_chat(f.composed, {
                    kind = "continue-chat", outcome = "ready", draft = draft,
                }, { cli = {}, stdio_facts = {} }, agent)
                A.falsy(result)
                A.equal(result_error.code, "TerminalUnavailable")
                A.deep_equal(calls, {
                    "terminal", "compaction-close", "session-close", "draft-close",
                })
            end,
        },
        {
            name = "production Context switcher reopens only the previewed exact hash",
            --Verifies production Context switcher reopens only the previewed exact hash.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify production Context switcher reopens only the previewed exact hash.
            run = function()
                local f = fixture()
                local current_preview_calls = 0
                local next_preview_calls = 0
                local closed = 0
                local initial = { application = {} }
                --Simulates the dispatch port for the 'production Context switcher reopens only the previewed exact hash' case.
                --@param request table Request delivered to the fake component.
                --@return table observed Structured fixture record with action, rows.
                function initial.application.dispatch(request)
                    A.equal(request.id, "context-repl")
                    A.equal(request.view, "recent")
                    return { action = "context-repl", rows = {} }
                end
                --Returns the preview continue observation prepared for the 'production Context switcher reopens only the previewed exact hash' case.
                --@param selector string Context selector resolved by the case.
                --@return table observed Structured fixture record selected by the exercised branch.
                function initial.application.preview_continue(selector)
                    current_preview_calls = current_preview_calls + 1
                    return {
                        kind = "continue-preview",
                        selector = selector,
                        logical_path = "/workspace/Second.xml",
                        context_hash = "FEDCBA9876543210",
                        recorded_workspace = "/workspace",
                    }
                end
                local next_composed = { application = {} }
                --Returns the continue preview observation prepared for the 'production Context switcher reopens only the previewed exact hash' case.
                --@param preview table Preflight preview being confirmed or rejected.
                --@param confirmation any The confirmation supplied to the fake service for this scenario.
                --@return table observed Outcome record with status ready.
                function next_composed.application.continue_preview(preview, confirmation)
                    A.equal(preview.context_hash, "FEDCBA9876543210")
                    A.equal(confirmation, nil)
                    local draft = {
                        --Simulates the close transition of a fake activity port for the 'production Context switcher reopens only the previewed exact hash' case.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return boolean accepted Whether the fake callback accepts this scenario.
                        close = function()
                        closed = closed + 1
                        return true
                    end }
                    return {
                        kind = "continue-chat",
                        outcome = "ready",
                        draft = draft,
                        status = {
                            logical_path = "/workspace/Second.xml",
                            context_hash = "FEDCBA9876543210",
                            display_name = "Second",
                            workspace = "/workspace",
                        },
                    }
                end
                --Returns the preview continue observation prepared for the 'production Context switcher reopens only the previewed exact hash' case.
                --@param selector string Context selector resolved by the case.
                --@return table observed Structured fixture record with selector.
                function next_composed.application.preview_continue(selector)
                    next_preview_calls = next_preview_calls + 1
                    return { selector = selector }
                end
                local agent = {
                    owner = "second",
                    loop = {},
                    driver = {},
                    session = {},
                    settings = {
                        --Simulates the status transition of a fake activity port for the 'production Context switcher reopens only the previewed exact hash' case.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return table record Fixture record emitted by the scenario callback.
                        status = function() return {} end,
                        --Supplies update behavior required by the 'production Context switcher reopens only the previewed exact hash' case.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return table record Fixture record emitted by the scenario callback.
                        update = function() return {} end,
                    },
                    models = {
                        --Returns the list observation prepared for the 'production Context switcher reopens only the previewed exact hash' case.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return table record Fixture record emitted by the scenario callback.
                        list = function() return {} end,
                        --Returns the preview observation prepared for the 'production Context switcher reopens only the previewed exact hash' case.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return table record Fixture record emitted by the scenario callback.
                        preview = function() return {} end,
                        --Supplies apply behavior required by the 'production Context switcher reopens only the previewed exact hash' case.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return table record Fixture record emitted by the scenario callback.
                        apply = function() return {} end,
                    },
                    tools = {},
                    compaction = {},
                    draft = {},
                }
                local switcher = assert(f.main.new_context_switcher(initial, {}, {
                    --Supplies compose behavior required by the 'production Context switcher reopens only the previewed exact hash' case.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return any value Callback value consumed by the enclosing scenario assertion.
                    compose = function() return next_composed end,
                    --Supplies start agent behavior required by the 'production Context switcher reopens only the previewed exact hash' case.
                    --@param composed any The composed supplied to the fake service for this scenario.
                    --@param chat any The chat supplied to the fake service for this scenario.
                    --@param message string|table Message or diagnostic passed through this test port.
                    --@param source string|table Source content or object under test.
                    --@return any value Callback value consumed by the enclosing scenario assertion.
                    start_agent = function(composed, chat, message, source)
                        A.equal(composed, next_composed)
                        A.equal(chat.status.context_hash, "FEDCBA9876543210")
                        A.contains(message, "latest durable Context facts")
                        A.equal(source, "context-switch")
                        return agent
                    end,
                }))
                A.equal(assert(switcher:list()).action, "context-repl")
                local preview = assert(switcher:preview("Second"))
                local activated = assert(switcher:activate(preview))
                A.equal(activated.agent, agent)
                A.equal(activated.status.logical_path, preview.logical_path)
                A.equal(current_preview_calls, 1)
                assert(switcher:preview("after-switch"))
                A.equal(next_preview_calls, 1)
                A.equal(closed, 0)

                local mismatch = assert(f.main.new_context_switcher(initial, {}, {
                    --Supplies compose behavior required by the 'production Context switcher reopens only the previewed exact hash' case.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return table record Fixture record emitted by the scenario callback.
                    compose = function()
                        return { application = {
                            --Returns the preview continue observation prepared for the 'production Context switcher reopens only the previewed exact hash' case.
                            --@param none No arguments; this closure uses its captured fixture state.
                            --@return table record Fixture record emitted by the scenario callback.
                            preview_continue = function() return {} end,
                            --Returns the continue preview observation prepared for the 'production Context switcher reopens only the previewed exact hash' case.
                            --@param none No arguments; this closure uses its captured fixture state.
                            --@return table record Fixture record emitted by the scenario callback.
                            continue_preview = function()
                                return {
                                    draft = {
                                        --Simulates the close transition of a fake activity port for the 'production Context switcher reopens only the previewed exact hash' case.
                                        --@param none No arguments; this closure uses its captured fixture state.
                                        --@return boolean accepted Whether the fake callback accepts this scenario.
                                        close = function()
                                        closed = closed + 1
                                        return true
                                    end },
                                    status = {
                                        logical_path = "/workspace/Replaced.xml",
                                        context_hash = "0000000000000000",
                                    },
                                }
                            end,
                        } }
                    end,
                    --Supplies start agent behavior required by the 'production Context switcher reopens only the previewed exact hash' case.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return nil No value; assertions verify production Context switcher reopens only the previewed exact hash.
                    start_agent = function()
                        error("changed target must not start an Agent")
                    end,
                }))
                local changed, changed_error = mismatch:activate(assert(mismatch:preview("Second")))
                A.falsy(changed)
                A.equal(changed_error.code, "TargetChanged")
                A.equal(closed, 1)
            end,
        },
        {
            name = "manual compaction crosses the real production owner and publication chain",
            --Verifies manual compaction crosses the real production owner and publication chain.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify manual compaction crosses the real production owner and publication chain.
            run = function()
                local f = fixture({ compaction_lifecycle = true })
                local agent = assert(f.main.start_published_agent(
                    f.composed,
                    f.chat,
                    "implement the project",
                    "terminal"
                ))
                f.pause_for_compaction()
                local started, start_error = agent.compaction:begin("manual")
                A.truthy(
                    started,
                    start_error and (start_error.code .. ": " .. start_error.message)
                )
                A.equal(started.state, "active")
                A.equal(started.compaction_id, "compaction-1")
                A.truthy(agent.compaction:status().active)

                local step, poll_error = agent.compaction:poll()
                A.truthy(
                    step,
                    poll_error and (poll_error.code .. ": " .. poll_error.message)
                )
                A.truthy(step.progressed)
                A.equal(#step.events, 1)
                A.equal(step.events[1].kind, "terminal")
                local terminal = step.events[1].result
                A.equal(terminal.settlement.outcome, "completed")
                A.equal(terminal.settlement.compaction_id, "compaction-1")
                A.truthy(terminal.settlement.manifest_digest ~= "view-1")
                A.falsy(agent.compaction:status().active)
                A.equal(
                    agent.loop:status().active_view_manifest_ref,
                    terminal.settlement.manifest_digest
                )

                local expected = {
                    "runtime-compaction-begin",
                    "journal:compaction-request",
                    "runtime-adopt:compaction-request",
                    "effect:compaction-model",
                    "journal:compaction-response",
                    "runtime-adopt:compaction-response",
                    "journal:compaction-publication",
                    "runtime-adopt:compaction-publication",
                    "runtime-compaction-finish:completed",
                }
                local cursor = 1
                for _, entry in ipairs(f.log) do
                    if entry == expected[cursor] then cursor = cursor + 1 end
                end
                A.equal(cursor, #expected + 1)
            end,
        },
        {
            name = "automatic compaction binds the deferred production request before resuming it",
            --Verifies automatic compaction binds the deferred production request before resuming it.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify automatic compaction binds the deferred production request before resuming it.
            run = function()
                local f = fixture({ automatic_compaction_lifecycle = true })
                local agent = assert(f.main.start_published_agent(
                    f.composed,
                    f.chat,
                    "implement the project",
                    "terminal"
                ))
                f.pause_for_automatic_compaction()
                local started = assert(agent.compaction:begin("automatic"))
                A.equal(started.state, "active")
                A.equal(started.mode, "automatic")

                local step = assert(agent.compaction:poll())
                A.equal(#step.events, 1)
                local terminal = step.events[1].result
                A.equal(terminal.settlement.outcome, "completed")
                A.equal(terminal.settlement.mode, "automatic")
                A.equal(
                    terminal.settlement.preflight_id,
                    "turn-1:compaction-preflight:1"
                )
                local status = agent.loop:status()
                A.equal(status.compaction_preflight_state, "settled")
                assert(agent.loop:resolve_compaction_preflight({
                    preflight_id = status.compaction_preflight_id,
                    outcome = terminal.settlement.outcome,
                    compaction_id = terminal.settlement.compaction_id,
                    expected_context_generation = status.context_generation,
                    expected_last_sequence = status.last_durable_sequence,
                    expected_manifest_digest = status.active_view_manifest_ref,
                    settlement = terminal.settlement,
                }))
                A.equal(agent.loop:status().state, "RequestingModel")
                A.contains(table.concat(f.log, "|"), "runtime-preflight-resolve")
            end,
        },
        {
            name = "recovered failure history suppresses the production automatic request",
            --Verifies recovered failure history suppresses the production automatic request.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify recovered failure history suppresses the production automatic request.
            run = function()
                for _, recovered in ipairs({
                    {
                        initial_automatic_failure_count = 3,
                        automatic_failure_history_complete = true,
                    },
                    {
                        initial_automatic_failure_count = 0,
                        automatic_failure_history_complete = false,
                    },
                }) do
                    recovered.automatic_compaction_lifecycle = true
                    local f = fixture(recovered)
                    local agent = assert(f.main.start_published_agent(
                        f.composed,
                        f.chat,
                        "implement the project",
                        "terminal"
                    ))
                    f.pause_for_automatic_compaction()
                    local suppressed = assert(agent.compaction:begin("automatic"))
                    A.equal(suppressed.result.decision, "suppressed")
                    A.equal(suppressed.result.reason, "compaction-circuit-open")
                    A.equal(suppressed.result.retry_after_ms, 60000)
                    A.equal(suppressed.settlement.outcome, "suppressed")
                    local status = agent.compaction:status()
                    A.equal(status.automatic_failure_count, 3)
                    A.equal(status.automatic_circuit_state, "open")
                    A.falsy(table.concat(f.log, "|"):find(
                        "effect:compaction-model",
                        1,
                        true
                    ))
                end
            end,
        },
        {
            name = "production compaction capacity refusal releases the untouched lane",
            --Verifies production compaction capacity refusal releases the untouched lane.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify production compaction capacity refusal releases the untouched lane.
            run = function()
                local settings = { compaction_lifecycle = true, compaction_capacity = true }
                local f = fixture(settings)
                local agent = assert(f.main.start_published_agent(
                    f.composed, f.chat, "implement the project", "terminal"))
                f.pause_for_compaction()
                local started, err = agent.compaction:begin("manual")
                A.falsy(started); A.equal(err.code, "ContextCapacity")
                A.falsy(agent.loop:status().halted)
                A.falsy(agent.compaction:status().active)
                A.falsy(table.concat(f.log, "|"):find("effect:compaction-model", 1, true))
                settings.compaction_capacity = false
                A.equal(assert(agent.compaction:begin("manual")).state, "active")
            end,
        },
        {
            name = "production compaction journal ambiguity halts instead of releasing its lane",
            --Verifies production compaction journal ambiguity halts instead of releasing its lane.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify production compaction journal ambiguity halts instead of releasing its lane.
            run = function()
                local f = fixture({
                    compaction_lifecycle = true,
                    compaction_journal_failure = "compaction-request",
                })
                local agent = assert(f.main.start_published_agent(
                    f.composed,
                    f.chat,
                    "implement the project",
                    "terminal"
                ))
                f.pause_for_compaction()
                local started, start_error = agent.compaction:begin("manual")
                A.falsy(started)
                A.equal(start_error.code, "AgentDurabilityFailure")
                A.truthy(agent.loop:status().halted)
                A.truthy(agent.compaction:status().active)

                local expected = {
                    "runtime-compaction-begin",
                    "journal-rejected:compaction-request",
                    "runtime-compaction-fail:journal-rejected",
                }
                local cursor = 1
                for _, entry in ipairs(f.log) do
                    if entry == expected[cursor] then cursor = cursor + 1 end
                end
                A.equal(cursor, #expected + 1)
            end,
        },
        {
            name = "ask snapshot reloads independently and exposes no Tool activity",
            --Verifies ask snapshot reloads independently and exposes no Tool activity.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify ask snapshot reloads independently and exposes no Tool activity.
            run = function()
                local f = fixture()
                local agent = assert(f.main.start_published_agent(
                    f.composed,
                    f.chat,
                    "implement the project",
                    "terminal"
                ))
                local snapshot = assert(f.capture({
                    kind = "ask",
                    text = "inspect durable facts",
                    source = "terminal",
                    context_generation = 2,
                    active_turn_id = "turn-1",
                    cause = { kind = "ask" },
                }))
                A.equal(snapshot.prompt_snapshot, "ask-prompt-snapshot-2")
                A.equal(agent.current_generation().id, "config-generation-1")
                A.equal(agent.current_ask_generation().id, "config-generation-2")
                A.truthy(f.start_ask_model())
                A.equal(f.log[#f.log], "effect:model-activity-4")

                local tool_builds = 0
                local ask_builder_index, ask_activity_index
                for index, value in ipairs(f.log) do
                    if value == "tools" then tool_builds = tool_builds + 1 end
                    if value == "ask-model-builder" then ask_builder_index = index end
                    if value == "model-activity-4" then ask_activity_index = index end
                end
                A.equal(tool_builds, 1)
                A.truthy(ask_builder_index < ask_activity_index)
            end,
        },
        {
            name = "post-publication composition failure releases the writer",
            --Verifies post-publication composition failure releases the writer.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify post-publication composition failure releases the writer.
            run = function()
                local f = fixture({ tool_registry_digest = "stale-registry" })
                local agent, agent_error = f.main.start_published_agent(
                    f.composed,
                    f.chat,
                    "implement the project",
                    "terminal"
                )
                A.falsy(agent)
                A.equal(agent_error.code, "ToolRegistryMismatch")
                A.truthy(f.closed())
                A.equal(f.log[#f.log], "draft-close")
            end,
        },
        {
            name = "later main snapshot reloads and atomically replaces turn ports",
            --Verifies post-publication composition failure releases the writer.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify post-publication composition failure releases the writer.
            run = function()
                local f = fixture()
                local agent = assert(f.main.start_published_agent(
                    f.composed,
                    f.chat,
                    "implement the project",
                    "terminal"
                ))
                local snapshot, snapshot_error = f.capture({
                    kind = "main",
                    text = "second turn",
                    source = "terminal",
                    context_generation = 2,
                    active_turn_id = false,
                    cause = { kind = "direct-main" },
                })
                A.truthy(
                    snapshot,
                    snapshot_error and (snapshot_error.code .. ": " .. snapshot_error.message)
                )
                A.equal(snapshot.config_generation, "config-snapshot-2")
                A.equal(snapshot.model_request_limit, 6)
                A.equal(snapshot.tool_call_limit, 10)
                A.equal(snapshot.queue_limit, 4)
                A.equal(agent.current_generation().id, "config-generation-2")
                A.equal(f.current_generation().id, "config-generation-2")
                A.truthy(f.start_current_model())
                A.equal(f.log[#f.log], "effect:model-activity-4")
                local context_index, reload_index, capture_index
                for index, value in ipairs(f.log) do
                    if value == "turn-context" then context_index = index end
                    if value == "config-reload" then reload_index = index end
                    if value == "capture-turn" then capture_index = index end
                end
                A.truthy(context_index < reload_index)
                A.truthy(reload_index < capture_index)
            end,
        },
        {
            name = "post-admission composition failure closes activity and writer",
            --Verifies post-admission composition failure closes activity and writer.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify post-admission composition failure closes activity and writer.
            run = function()
                local f = fixture({ session_error = true })
                local agent, agent_error = f.main.start_published_agent(
                    f.composed,
                    f.chat,
                    "implement the project",
                    "terminal"
                )
                A.falsy(agent)
                A.equal(agent_error.code, "InjectedSessionFailure")
                A.truthy(f.loop_closed())
                A.truthy(f.closed())
                A.equal(f.log[#f.log - 1], "runtime-close")
                A.equal(f.log[#f.log], "draft-close")
            end,
        },
    },
}
