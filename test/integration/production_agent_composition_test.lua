--[[
File: production_agent_composition_test.lua
Date: 2026-08-30
Author: WaterRun
Description: Verifies the production first-turn Agent composition and durable ordering.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()
local compact = assert(loadfile(
    YACA_TEST_ROOT .. "/src/compact.lua",
    "t",
    _ENV
))()

local function test_digest(bytes)
    local value = 2166136261
    for index = 1, #bytes do
        value = (value * 16777619 + bytes:byte(index)) % 4294967296
    end
    return string.format("test-digest-%08x-%d", value, #bytes)
end

local function append_compaction_event(facts, event_type, turn_id, fields)
    facts[#facts + 1] = {
        seq = #facts + 1,
        type = event_type,
        at = "2026-08-30T00:00:00Z",
        turn_id = turn_id,
        fields = fields,
    }
end

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

local function load_main(cache)
    local environment = {}
    for key, value in pairs(_ENV) do environment[key] = value end
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
    setmetatable(environment, { __index = _ENV })
    local chunk, load_error = loadfile(
        YACA_TEST_ROOT .. "/src/main.lua",
        "t",
        environment
    )
    A.truthy(chunk, load_error)
    return chunk()
end

local function fixture(settings)
    settings = settings or {}
    local log = {}
    local compact_source = settings.compaction_lifecycle
        and compaction_document() or false
    local published = false
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
        network = {},
        exec = {
            max_output_kb = 64,
            timeout_ms = 5000,
            environment_mode = "minimal",
        },
        agent = {
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
        models = { Primary = {
            context_length = 16000,
            max_output_tokens = 1024,
            system_prompt = "model",
        } },
        scan_registered_secrets = function() return {} end,
        new_stream_scanner = function() return {} end,
    }
    local next_generation = {}
    for key, value in pairs(generation) do next_generation[key] = value end
    next_generation.id = "config-generation-2"
    next_generation.agent = {
        action_review_enabled = true,
        max_turn_model_requests = 6,
        max_turn_tool_calls = 10,
        queue_max_items = 4,
        compact_threshold = 0.75,
    }
    local active_generation = generation
    local loop_status = {
        state = "RequestingModel",
        context_generation = 2,
        last_durable_sequence = 3,
        active_view_manifest_ref = "view-1",
        turn_id = "turn-1",
        halted = false,
    }
    local compaction_gate = false
    local loop = {}
    for _, name in ipairs({
        "submit_main", "enqueue", "steer", "start_side", "resolve_yield",
        "reply", "list_queue", "drop_queue", "edit_queue", "reorder_queue",
        "clear_queue", "use_side",
    }) do
        loop[name] = function() return true end
    end
    function loop:status() return loop_status end
    function loop:resume_published_main(observed)
        A.truthy(published, "Model admission crossed the first publication barrier")
        A.equal(observed, handoff)
        log[#log + 1] = "runtime-resume"
        return { state = "RequestingModel", request_id = "turn-1:request:1" }
    end
    function loop:close(reason)
        A.equal(reason, "agent-composition-failed")
        loop_closed = true
        log[#log + 1] = "runtime-close"
        return true
    end
    function loop:begin_compaction(command)
        if not settings.compaction_lifecycle then return true end
        A.equal(loop_status.state, "Idle")
        A.equal(command.mode, "manual")
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
    function loop:adopt_compaction_receipt(record, receipt)
        if not settings.compaction_lifecycle then return true end
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
    function loop:fail_compaction_barrier(reason)
        if not settings.compaction_lifecycle then
            return nil, { code = "AgentDurabilityFailure" }
        end
        loop_status.halted = true
        log[#log + 1] = "runtime-compaction-fail:" .. tostring(reason)
        return nil, { code = "AgentDurabilityFailure" }
    end
    function loop:finish_compaction(command)
        if not settings.compaction_lifecycle then return true end
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
        return {
            outcome = command.outcome,
            compaction_id = command.compaction_id,
            mode = "manual",
            state = loop_status.state,
            context_generation = loop_status.context_generation,
            last_sequence = loop_status.last_durable_sequence,
            manifest_digest = loop_status.active_view_manifest_ref,
        }
    end

    local operation_journal = {
        commit_intent = function() return true end,
        commit_result = function() return true end,
        take_intent_receipt = function() return {} end,
        take_result_receipt = function() return {} end,
    }
    local function compaction_events(record)
        if record.kind == "compaction-request" then
            return { {
                type = "model_request",
                turn_id = false,
                fields = {
                    requestId = record.request_id,
                    purpose = "compaction",
                    viewManifestRef = record.expected_manifest_digest,
                    attemptId = tostring(record.attempt),
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
    local function commit_compaction(record, publishing)
        A.truthy(settings.compaction_lifecycle)
        A.equal(record.expected_context_generation, loop_status.context_generation)
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
        commit_intent = function(record)
            return commit_compaction(record, false)
        end,
        commit_response = function(record)
            return commit_compaction(record, false)
        end,
        commit_rejection = function(record)
            return commit_compaction(record, false)
        end,
        publish = function(record)
            return commit_compaction(record, true)
        end,
        commit_correction = function(record)
            return commit_compaction(record, false)
        end,
    }
    local publication = {
        operation_journal = function()
            log[#log + 1] = "operation-journal"
            return operation_journal
        end,
        compaction_journal = function()
            log[#log + 1] = "compaction-journal"
            if settings.compaction_lifecycle then
                return durable_compaction_journal
            end
            return {
                commit_intent = function() return false end,
                commit_response = function() return false end,
                commit_rejection = function() return false end,
                publish = function() return false end,
                commit_correction = function() return false end,
            }
        end,
        compaction_snapshot = function(observation)
            if not settings.compaction_lifecycle then return nil end
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
                binding = observation,
            }
        end,
        turn_context = function(observation)
            A.truthy(published)
            A.equal(observation.expected_context_generation, 2)
            log[#log + 1] = "turn-context"
            return {
                context_generation = 2,
                overrides = {
                    CurrentModel = "Primary",
                    CurrentPermission = "Std",
                    DoubleCheckOverride = true,
                    DoubleCheckGoalOverride = "inherit",
                    ContextPrompt = "workspace context",
                    AutoRenameDisabled = false,
                },
            }
        end,
        capture_turn = function(specification)
            A.truthy(specification.kind == "main" or specification.kind == "side")
            A.equal(
                specification.text,
                specification.kind == "side" and "inspect durable facts" or "second turn"
            )
            A.equal(specification.source, "terminal")
            A.equal(specification.expected_context_generation, 2)
            log[#log + 1] = "capture-turn"
            local prompt_snapshot = specification.kind == "side"
                and "side-prompt-snapshot-2"
                or "prompt-snapshot-2"
            return {
                text = specification.text,
                source = specification.source,
                config_generation = "config-snapshot-2",
                model_snapshot = "model-snapshot-2",
                permission_snapshot = "permission-snapshot-2",
                prompt_snapshot = prompt_snapshot,
                tool_registry_snapshot = "registry-1",
                view_manifest_ref = "view-1",
                double_check = true,
                context_generation = 2,
                model_request_limit = 6,
                tool_call_limit = 10,
                queue_limit = 4,
            }
        end,
        resolve_view = function() return {} end,
        prepare_view = function() return {} end,
        commit = function() return true end,
    }
    local safety = {
        digest = test_digest,
        binding_digest = function(domain, fields)
            A.equal(domain, "yaca-tool-authority-v1")
            A.equal(fields[1].value, "call-digest")
            return string.rep("a", 64)
        end,
    }
    local contexts = {
        safety = safety,
        path = {},
        prompt = {},
        tool_registry = { digest = "registry-1", tools = {} },
    }
    local model_activities = {}
    local tool_port = {
        poll = function() return {}, false end,
        active_handle = function() return false end,
    }
    local review_port = {
        poll = function() return {} end,
        status = function() return { state = "idle" } end,
    }
    local compaction_port = {
        start = function(specification)
            if not settings.compaction_lifecycle then return {} end
            settings.compaction_specification = specification
            settings.compaction_response_pending = true
            settings.compaction_port_state = "active"
            log[#log + 1] = "effect:compaction-model"
            return "compaction-model-handle"
        end,
        cancel = function()
            settings.compaction_port_state = "idle"
            return { outcome = "cancelled" }
        end,
        poll = function()
            if not settings.compaction_lifecycle
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
        status = function()
            return { state = settings.compaction_port_state or "idle" }
        end,
    }
    local runtime_ports

    local modules = {}
    modules.context = {
        new_operation_service = function(ports, options)
            A.equal(ports.journal, operation_journal)
            A.equal(options.maximum_identifier_bytes, 256)
            log[#log + 1] = "operations"
            return { begin = function() end, finish = function() end, status = function() end }
        end,
    }
    modules.permission = {
        new = function(_, options)
            A.equal(options.maximum_name_bytes, 128)
            local service = {}
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
        new = function(dependencies, options)
            A.equal(options.workspace_path, "/workspace")
            A.equal(options.reserved_paths[1], "/release/__yaca__")
            A.equal(options.maximum_exec_output_bytes, 65536)
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
            return { registry_digest = settings.tool_registry_digest or "registry-1" }
        end,
        new_agent_port = function(_, options)
            A.equal(options.config_generation, active_generation.id)
            A.equal(options.exec_policy.decoder, "utf-8-strict-candidate-v1")
            log[#log + 1] = "tool-port"
            return tool_port
        end,
    }
    modules.model = {
        new_request_builder = function(_, options)
            local suffix = active_generation.id:sub(-1)
            A.equal(options.model_snapshot, "model-snapshot-" .. suffix)
            A.equal(options.prompt_snapshot, "prompt-snapshot-" .. suffix)
            A.equal(options.default_max_output_tokens, 4096)
            log[#log + 1] = "model-builder"
            return {}
        end,
        new_side_request_builder = function(ports, options)
            A.equal(ports.generation.id, "config-generation-2")
            A.equal(options.model_name, "Primary")
            A.equal(options.permission_name, "Std")
            A.equal(options.prompt_snapshot, "side-prompt-snapshot-2")
            A.equal(options.tool_registry_snapshot, "registry-1")
            A.equal(options.maximum_request_time_ms, 120000)
            A.equal(options.maximum_output_tokens, 1024)
            log[#log + 1] = "side-model-builder"
            return {}
        end,
        new_compaction_request_builder = function(_, options)
            local suffix = active_generation.id:sub(-1)
            A.equal(options.model_snapshot, "model-snapshot-" .. suffix)
            A.equal(options.prompt_snapshot, "prompt-snapshot-" .. suffix)
            A.equal(options.maximum_source_bytes, 16 * 1024 * 1024)
            log[#log + 1] = "compaction-builder"
            return {}
        end,
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
        new_activity = function(_, options)
            A.equal(options.identity_namespace, "context-0123456789ABCDEF")
            local serial = #model_activities + 1
            local activity = {
                start = function()
                    log[#log + 1] = "effect:model-activity-" .. tostring(serial)
                    return {}
                end,
                cancel = function() return { outcome = "cancelled" } end,
                poll = function() return {} end,
                status = function() return { state = "idle" } end,
            }
            model_activities[#model_activities + 1] = activity
            log[#log + 1] = "model-activity-" .. tostring(#model_activities)
            return activity
        end,
        new_review_port = function()
            log[#log + 1] = "review-port"
            return review_port
        end,
        new_compaction_port = function(_, options)
            A.equal(options.maximum_poll_events, 128)
            log[#log + 1] = "compaction-port"
            return compaction_port
        end,
    }
    modules.json = {
        new = function(options)
            A.equal(options.maximum_bytes, 1024 * 1024)
            return {}
        end,
    }
    modules.runtime = {
        new_agent_loop = function(ports, options)
            A.equal(ports.journal, publication)
            A.truthy(ports.model ~= model_activities[1])
            A.truthy(ports.tools ~= tool_port)
            A.truthy(ports.reviews ~= review_port)
            A.equal(type(ports.snapshots.capture), "function")
            A.equal(type(ports.side.start), "function")
            A.equal(type(ports.side.poll), "function")
            A.equal(options.hard_caps.model_requests, 64)
            A.equal(options.hard_caps.tool_calls, 256)
            A.equal(options.lanes.queue_maximum, 9)
            runtime_ports = ports
            log[#log + 1] = "agent-loop"
            return loop
        end,
        new_agent_activity_driver = function(ports, options)
            A.equal(ports.loop, loop)
            A.equal(ports.model, runtime_ports.model)
            A.equal(ports.tools, runtime_ports.tools)
            A.equal(ports.reviews, runtime_ports.reviews)
            A.equal(ports.side, runtime_ports.side)
            A.equal(options.maximum_output_events, 512)
            log[#log + 1] = "driver"
            return { step = function() return {} end }
        end,
    }
    modules.session = {
        new_agent_session = function(candidate, options)
            A.equal(candidate, loop)
            A.equal(options.maximum_draft_bytes, 16384)
            log[#log + 1] = "agent-session"
            if settings.session_error then
                return nil, { code = "InjectedSessionFailure" }
            end
            return { status = function() return {} end }
        end,
    }

    local draft = {}
    function draft.begin_main(message, source)
        A.equal(message, "implement the project")
        A.equal(source, "terminal")
        A.falsy(published)
        published = true
        log[#log + 1] = "publish-first"
        return { durable = true }
    end
    function draft.agent_handoff()
        A.truthy(published)
        return handoff
    end
    function draft.config_generation() return generation end
    function draft.status()
        return {
            workspace = "/workspace",
            permission = "Std",
            model = "Primary",
            double_check = true,
            context_prompt = "workspace context",
            context_hash = "0123456789ABCDEF",
        }
    end
    function draft.close()
        closed = true
        log[#log + 1] = "draft-close"
        return true
    end

    local composed = {
        backend = {
            filesystem = {
                direct_inspect = function(path)
                    A.truthy(published)
                    A.equal(path, "/workspace")
                    return true, {
                        identity = {
                            volume = "volume-1",
                            object = "workspace-1",
                            kind = "directory",
                        },
                    }
                end,
            },
            processes = {},
            clock_port = {
                monotonic_now = function() return 1 end,
                utc_now = function() return "2026-08-30T00:00:00Z" end,
            },
        },
        contexts = contexts,
        publication = publication,
        config = {
            reload_file = function(path, overrides)
                A.equal(path, "/release/__yaca__/config.ini")
                A.equal(overrides.CurrentModel, "Primary")
                log[#log + 1] = "config-reload"
                active_generation = next_generation
                return next_generation
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
    local chat = { kind = "run-chat", outcome = "ready", draft = draft }
    return {
        main = load_main(modules),
        composed = composed,
        chat = chat,
        log = log,
        closed = function() return closed end,
        loop_closed = function() return loop_closed end,
        capture = function(specification)
            return runtime_ports.snapshots.capture(specification)
        end,
        start_current_model = function()
            return runtime_ports.model.start({ request_id = "turn-2:request:1" })
        end,
        start_side_model = function()
            return runtime_ports.side.start({
                side_id = "side-1",
                turn_id = "side-1",
                request_id = "side-1:request:1",
                purpose = "side",
                view_manifest_ref = "view-1",
                no_tools = true,
                active_time_cap_ms = 120000,
                response_byte_cap = 65536,
                budget_snapshot_id = "tp022-modern-candidate-v1",
            })
        end,
        pause_for_compaction = function()
            A.truthy(compact_source)
            loop_status.state = "Idle"
            loop_status.turn_id = false
            loop_status.context_generation = compact_source.generation
            loop_status.last_durable_sequence = compact_source.event_count
            loop_status.active_view_manifest_ref
                = compact_source.model_view.active_manifest.digest
        end,
        current_generation = function() return active_generation end,
    }
end

return {
    name = "integration/production-agent-composition",
    cases = {
        {
            name = "durable first turn precedes every production Agent activity",
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
                A.truthy(agent.capabilities.side)
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
            name = "manual compaction crosses the real production owner and publication chain",
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
            name = "production compaction journal ambiguity halts instead of releasing its lane",
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
            name = "side snapshot reloads independently and exposes no Tool activity",
            run = function()
                local f = fixture()
                local agent = assert(f.main.start_published_agent(
                    f.composed,
                    f.chat,
                    "implement the project",
                    "terminal"
                ))
                local snapshot = assert(f.capture({
                    kind = "side",
                    text = "inspect durable facts",
                    source = "terminal",
                    context_generation = 2,
                    active_turn_id = "turn-1",
                    cause = { kind = "side" },
                }))
                A.equal(snapshot.prompt_snapshot, "side-prompt-snapshot-2")
                A.equal(agent.current_generation().id, "config-generation-1")
                A.equal(agent.current_side_generation().id, "config-generation-2")
                A.truthy(f.start_side_model())
                A.equal(f.log[#f.log], "effect:model-activity-4")

                local tool_builds = 0
                local side_builder_index, side_activity_index
                for index, value in ipairs(f.log) do
                    if value == "tools" then tool_builds = tool_builds + 1 end
                    if value == "side-model-builder" then side_builder_index = index end
                    if value == "model-activity-4" then side_activity_index = index end
                end
                A.equal(tool_builds, 1)
                A.truthy(side_builder_index < side_activity_index)
            end,
        },
        {
            name = "post-publication composition failure releases the writer",
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
