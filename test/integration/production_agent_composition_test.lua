--[[
File: production_agent_composition_test.lua
Date: 2026-08-30
Author: WaterRun
Description: Verifies the production first-turn Agent composition and durable ordering.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

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
        models = { Primary = {} },
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
    }
    local active_generation = generation
    local loop_status = {
        state = "RequestingModel",
        context_generation = 2,
        turn_id = "turn-1",
    }
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

    local operation_journal = {
        commit_intent = function() return true end,
        commit_result = function() return true end,
        take_intent_receipt = function() return {} end,
        take_result_receipt = function() return {} end,
    }
    local publication = {
        operation_journal = function()
            log[#log + 1] = "operation-journal"
            return operation_journal
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
            A.equal(specification.text, "second turn")
            A.equal(specification.source, "terminal")
            A.equal(specification.expected_context_generation, 2)
            log[#log + 1] = "capture-turn"
            return {
                text = specification.text,
                source = specification.source,
                config_generation = "config-snapshot-2",
                model_snapshot = "model-snapshot-2",
                permission_snapshot = "permission-snapshot-2",
                prompt_snapshot = "prompt-snapshot-2",
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
        new_activity = function()
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
            A.equal(ports.side, false)
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
                    "review-builder",
                    "model-activity-2",
                    "review-port",
                    "agent-loop",
                    "runtime-resume",
                    "driver",
                    "agent-session",
                })
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
                A.equal(f.log[#f.log], "effect:model-activity-3")
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
