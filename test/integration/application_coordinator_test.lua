--[[
File: application_coordinator_test.lua
Date: 2026-08-30
Author: WaterRun
Description: Verifies the interactive ApplicationCoordinator input, Agent, approval, and close paths.
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

local cache = {}
local json = load_module("json", cache)
local cli = load_module("cli", cache)
local main = load_module("main", cache)

local function cli_service()
    local codec = assert(json.new({
        maximum_bytes = 65536,
        maximum_depth = 16,
        maximum_nodes = 2048,
        maximum_string_bytes = 16384,
        maximum_number_bytes = 64,
    }))
    return assert(cli.new({
        platform = "linux",
        product_name = "yaca",
        machine_schema_version = "yaca-cli-v0.1.0",
        json_codec = codec,
    }))
end

local function status(state, overrides)
    local value = {
        state = state,
        turn_id = state == "Closing" and false or "turn-1",
        active_request_id = state == "RequestingModel" and "turn-1:request:1" or false,
        active_tool_call_id = false,
        pending_kind = false,
        pending_tool_call_id = false,
        pending_operation_id = false,
        pending_review_verdict = false,
        pending_question = false,
        context_generation = 1,
        last_durable_sequence = 3,
        active_view_manifest_ref = "view-1",
        compaction_preflight_state = "idle",
        compaction_preflight_id = false,
        compaction_preflight_purpose = false,
        queue_count = 0,
        queue_maximum = 9,
        side_state = "idle",
        active_side_id = false,
        last_outcome = false,
    }
    for key, item in pairs(overrides or {}) do value[key] = item end
    return value
end

local function fixture(settings)
    settings = settings or {}
    local log = {}
    local blocks = {}
    local prompts = {}
    local batches = settings.batches or {}
    local now = 0
    local loop_status = status(settings.initial_state or "RequestingModel")
    local driver_steps = 0
    local side_started = false
    local side_emitted = false
    local compaction_active = false
    local cautious_override = "inherit"
    local cautious_default = true
    local context_prompt = ""
    local settings_serial = 0
    local saved_model = "Primary"
    local draft_model = "Primary"

    local function model_summary(name)
        local secondary = name == "Secondary"
        return {
            name = name,
            protocol = "openai-chat",
            endpoint_origin = secondary and "https://secondary.example"
                or "https://primary.example",
            endpoint_path = "/v1/chat/completions",
            endpoint_query_configured = false,
            remote_model = secondary and "secondary-remote" or "primary-remote",
            credential_policy = "bearer:Model." .. name .. ".Key",
            proxy_policy = "off",
            context_length = secondary and 65536 or 32768,
            max_output_tokens = 4096,
            streaming = "try",
            tools = "native",
            controls = "yaca-native-v1",
            roles = "openai-chat-canonical-v1",
        }
    end

    local function model_owner(durable)
        local bindings = setmetatable({}, { __mode = "k" })
        local owner = {}
        local function current()
            return durable and saved_model or draft_model
        end
        function owner:list()
            local current_name = current()
            local rows = {}
            for _, name in ipairs({ "Primary", "Secondary" }) do
                local row = model_summary(name)
                row.current = name == current_name
                row.default = name == "Primary"
                rows[#rows + 1] = row
            end
            return {
                current = current_name,
                rows = rows,
                total = 2,
                shown = 2,
                truncated = false,
            }
        end
        function owner:preview(selector)
            if selector ~= "Primary" and selector ~= "Secondary" then
                return nil, { code = "ModelNotFound", message = "not found" }
            end
            local current_name = current()
            local unchanged = selector == current_name
            local confirmation = not unchanged and settings.model_direct ~= true
            local preview = {
                kind = "model-switch-preview",
                unchanged = unchanged,
                confirmation_required = confirmation,
                effective_at = durable and "next-turn" or "first-turn",
                from = model_summary(current_name),
                to = model_summary(selector),
                reasons = confirmation and {
                    "endpoint-route",
                    "credential-policy",
                    "usage-source",
                    durable and "history-destination" or nil,
                } or {},
            }
            if confirmation and not durable then
                preview.reasons[4] = nil
            end
            if not unchanged then
                preview.history = {
                    first_sequence = durable and 1 or 0,
                    last_sequence = durable and loop_status.last_durable_sequence or 0,
                    manifest_digest = durable
                        and loop_status.active_view_manifest_ref or false,
                    body_bytes = durable and 128 or 0,
                    transition_last_sequence = durable
                        and (loop_status.last_durable_sequence + 1) or 0,
                }
                preview.preflight = {
                    compatible = true,
                    required_tokens = 8192,
                    window_tokens = preview.to.context_length,
                    tools = "native-compatible",
                    controls = "typed-compatible",
                    roles = "canonical-compatible",
                }
            end
            bindings[preview] = current_name
            return preview
        end
        function owner:apply(preview)
            if bindings[preview] ~= current() then
                return nil, {
                    code = "ModelSelectionStale",
                    message = "stale fake preview",
                }
            end
            bindings[preview] = nil
            if durable then
                saved_model = preview.to.name
                settings_serial = settings_serial + 1
                loop_status.context_generation = loop_status.context_generation + 1
                loop_status.last_durable_sequence
                    = loop_status.last_durable_sequence + 2
                loop_status.active_view_manifest_ref
                    = "view-model-" .. tostring(settings_serial)
                log[#log + 1] = "saved-model:" .. saved_model
            else
                draft_model = preview.to.name
                log[#log + 1] = "draft-model:" .. draft_model
            end
            return {
                context_generation = durable
                    and loop_status.context_generation or 0,
                config_generation = "config-model-" .. tostring(settings_serial),
                model = current(),
                permission = "Std",
                effective_at = durable and "next-turn" or "first-turn",
            }
        end
        return owner
    end

    local saved_models = model_owner(true)
    local draft_models = model_owner(false)

    local terminal = {}
    function terminal:start(observed_now)
        log[#log + 1] = "terminal-start:" .. tostring(observed_now)
        return true
    end
    function terminal:poll()
        return table.remove(batches, 1) or {}
    end
    function terminal:cancel()
        log[#log + 1] = "terminal-cancel"
        return true
    end
    function terminal:join()
        log[#log + 1] = "terminal-join"
        return { outcome = "cancelled" }
    end
    function terminal:restore()
        log[#log + 1] = "terminal-restore"
        return true
    end
    function terminal:close()
        log[#log + 1] = "terminal-close"
        return true
    end

    local draft = {}
    function draft.status()
        return {
            lifecycle = "saved",
            workspace = "/workspace",
            model = saved_model,
            permission = "Std",
            double_check = true,
            display_name = "first-task",
            context_hash = "0123456789ABCDEF",
            logical_path = "/workspace/First.xml",
        }
    end
    function draft:close()
        log[#log + 1] = "draft-close"
        return true
    end

    local session = {}
    function session:stage(message, source)
        log[#log + 1] = "stage:" .. source .. ":" .. message
        return { text = message }
    end
    function session:submit()
        log[#log + 1] = "submit"
        return { turn_id = "turn-2" }
    end
    function session:steer()
        log[#log + 1] = "steer"
        return { steer_message_id = "turn-1:message:2" }
    end
    function session:side()
        if settings.side_error then return nil, settings.side_error end
        log[#log + 1] = "side"
        side_started = true
        loop_status = status(loop_status.state, {
            pending_kind = loop_status.pending_kind,
            side_state = "active",
            active_side_id = "side-1",
        })
        return { side_id = "side-1" }
    end
    function session:queue_list()
        return { count = 0, maximum = 9, items = {} }
    end
    function session:close(reason)
        log[#log + 1] = "session-close:" .. reason
        loop_status = status("Closing", { last_outcome = "cancelled" })
        return true
    end

    local loop = {}
    function loop:status() return loop_status end
    function loop:cancel()
        log[#log + 1] = "loop-cancel"
        loop_status = status("Idle", { last_outcome = "cancelled" })
        return { outcome = "cancelled" }
    end
    function loop:cancel_side(command)
        A.equal(command.side_id, "side-1")
        A.equal(command.expected_context_generation, loop_status.context_generation)
        A.equal(command.expected_turn_id, loop_status.turn_id)
        log[#log + 1] = "side-cancel:" .. command.reason
        loop_status = status(loop_status.state, {
            pending_kind = loop_status.pending_kind,
            side_state = "idle",
            active_side_id = false,
        })
        return { side_id = command.side_id, outcome = "cancelled" }
    end
    function loop:resolve_approval(envelope)
        log[#log + 1] = "resolve-approval:" .. envelope.decision
        loop_status = status("RequestingModel")
        return { state = "RequestingModel" }
    end
    function loop:resolve_compaction_preflight(command)
        A.equal(command.preflight_id, "turn-1:compaction-preflight:1")
        A.equal(command.outcome, "completed")
        A.equal(command.settlement.mode, "automatic")
        log[#log + 1] = "preflight-resolve:" .. command.outcome
        loop_status = status("RequestingModel")
        return { state = "RequestingModel", request_id = "turn-1:request:1" }
    end

    local tools = {}
    function tools.prepare_approval(tool_call_id, review_verdict)
        log[#log + 1] = "prepare-approval:" .. tool_call_id
            .. ":" .. tostring(review_verdict)
        return {
            tool = "write",
            canonical_target = "/workspace/a.lua",
            cwd = "/workspace",
            required_capabilities = { "Write" },
            canonical_arguments = '{"content":"x","path":"a.lua"}',
            snapshot_digest = "approval-digest",
        }
    end
    function tools.record_approval(tool_call_id, review_verdict, approval_id, answer)
        log[#log + 1] = table.concat({
            "record-approval", tool_call_id, tostring(review_verdict),
            approval_id, answer,
        }, ":")
        return {
            decision = answer,
            approval_id = approval_id,
            snapshot_digest = "approval-digest",
            approval_digest = answer == "approve" and "approval-digest" or "",
        }
    end

    local session_settings = {}
    function session_settings:status()
        return {
            context_generation = loop_status.context_generation,
            config_generation = "config-settings-" .. tostring(settings_serial),
            model = saved_model,
            permission = "Std",
            double_check_default = cautious_default,
            double_check_override = cautious_override,
            double_check_effective = cautious_override == "inherit"
                and cautious_default or cautious_override,
            context_prompt = context_prompt,
            effective_at = "current",
        }
    end
    function session_settings:update(change)
        if change.name == "DoubleCheckOverride" then
            A.truthy(change.value == "inherit" or type(change.value) == "boolean")
            cautious_override = change.value
            log[#log + 1] = "settings-cautious:" .. tostring(change.value)
        else
            A.equal(change.name, "ContextPrompt")
            A.equal(type(change.value), "string")
            context_prompt = change.value
            log[#log + 1] = "settings-prompt-bytes:"
                .. tostring(#change.value)
        end
        settings_serial = settings_serial + 1
        loop_status.context_generation = loop_status.context_generation + 1
        loop_status.last_durable_sequence
            = loop_status.last_durable_sequence + 2
        loop_status.active_view_manifest_ref
            = "view-settings-" .. tostring(settings_serial)
        local projected = self:status()
        projected.effective_at = "next-turn"
        return projected
    end

    local driver = {}
    function driver.step()
        driver_steps = driver_steps + 1
        if settings.freeze_driver then
            return { events = {}, status = loop_status, progressed = false }
        end
        if settings.side_response and side_started and not side_emitted then
            side_emitted = true
            loop_status = status(loop_status.state, {
                pending_kind = loop_status.pending_kind,
                side_state = "idle",
                active_side_id = false,
            })
            return {
                events = {
                    {
                        kind = "side-model-event",
                        side_id = "side-1",
                        event = { kind = "text_delta", text = "bounded advice" },
                    },
                    {
                        kind = "side-model-event",
                        side_id = "side-1",
                        event = { kind = "response_finish", finish_class = "stop" },
                    },
                    {
                        kind = "runtime-transition",
                        cause = "side-response",
                        side_id = "side-1",
                        result = { side_id = "side-1", outcome = "completed" },
                    },
                },
                status = loop_status,
                progressed = true,
            }
        end
        if driver_steps == 1 and settings.approval then
            loop_status = status("AwaitingApproval", {
                pending_kind = "approval",
                pending_tool_call_id = "turn-1:tool:1",
                pending_operation_id = "turn-1:operation:1",
                pending_review_verdict = "tighten",
            })
            return {
                events = {},
                status = loop_status,
                progressed = true,
            }
        end
        if driver_steps == 1 then
            loop_status = status("WaitingUser", {
                pending_kind = "model-yield",
            })
            return {
                events = {
                    {
                        kind = "model-event",
                        event = { kind = "text_delta", text = "implemented" },
                    },
                    {
                        kind = "model-event",
                        event = { kind = "response_finish", finish_class = "stop" },
                    },
                    {
                        kind = "runtime-transition",
                        cause = "model-response",
                        result = { state = "WaitingUser", outcome = "waiting_user" },
                    },
                },
                status = loop_status,
                progressed = true,
            }
        end
        return { events = {}, status = loop_status, progressed = false }
    end

    local compaction = {}
    function compaction:begin(mode)
        log[#log + 1] = "compaction-begin:" .. mode
        if settings.compaction_active or (settings.automatic_preflight
            and mode == "automatic")
        then
            compaction_active = true
            settings.automatic_terminal_pending = mode == "automatic"
            return {
                state = "active",
                compaction_id = "compaction-1",
                request_id = "compaction-1:request:1",
                mode = mode,
            }
        end
        return {
            result = { decision = "no_op" },
            settlement = { outcome = "no_op" },
        }
    end
    function compaction:poll()
        if settings.automatic_terminal_pending then
            settings.automatic_terminal_pending = false
            compaction_active = false
            local settlement = {
                outcome = "completed",
                compaction_id = "compaction-1",
                mode = "automatic",
                preflight_id = "turn-1:compaction-preflight:1",
                context_generation = loop_status.context_generation,
                last_sequence = loop_status.last_durable_sequence,
                manifest_digest = "view-2",
            }
            loop_status.active_view_manifest_ref = "view-2"
            return {
                events = { {
                    kind = "terminal",
                    result = {
                        result = {
                            outcome = "completed",
                            compaction_id = "compaction-1",
                            benefit_tokens = 2048,
                        },
                        settlement = settlement,
                    },
                } },
                progressed = true,
                status = self:status(),
            }
        end
        return { events = {}, progressed = false, status = self:status() }
    end
    function compaction:cancel(reason)
        log[#log + 1] = "compaction-cancel:" .. reason
        compaction_active = false
        return {
            result = { outcome = "cancelled", compaction_id = "compaction-1" },
            settlement = { outcome = "cancelled" },
        }
    end
    function compaction:status()
        return {
            state = compaction_active and "Compacting" or "Idle",
            active = compaction_active,
            active_compaction_id = compaction_active and "compaction-1" or false,
            automatic_failure_count = 0,
            automatic_circuit_state = "closed",
        }
    end
    function compaction:close()
        compaction_active = false
        return true
    end

    local constructed_agent = {
        loop = loop,
        driver = driver,
        session = session,
        settings = session_settings,
        models = saved_models,
        tools = tools,
        compaction = compaction,
        draft = draft,
    }
    local context_switch = {}
    function context_switch:list()
        log[#log + 1] = "context-list"
        return {
            action = "context-repl",
            rows = { {
                hash16 = "FEDCBA9876543210",
                display_name = "second-task",
                logical_path = "/workspace/Second.xml",
                header_state = "valid",
            } },
            total = 1,
            shown = 1,
            truncated = false,
        }
    end
    function context_switch:preview(selector)
        log[#log + 1] = "context-preview:" .. selector
        if settings.context_preview_error then
            return nil, settings.context_preview_error
        end
        return {
            kind = "continue-preview",
            selector = selector,
            logical_path = "/workspace/Second.xml",
            context_hash = "FEDCBA9876543210",
            recorded_workspace = "/workspace",
        }
    end
    function context_switch:activate(preview)
        log[#log + 1] = "context-activate:" .. preview.context_hash
        if settings.context_activation_error then
            return nil, settings.context_activation_error
        end
        loop_status = status("Idle", { turn_id = false })
        local next_draft = {}
        function next_draft.status()
            return {
                lifecycle = "saved",
                durable = true,
                workspace = "/workspace",
                model = saved_model,
                permission = "Std",
                double_check = true,
                display_name = "second-task",
                context_hash = "FEDCBA9876543210",
                logical_path = "/workspace/Second.xml",
            }
        end
        function next_draft:close()
            log[#log + 1] = "next-draft-close"
            return true
        end
        local next_agent = {
            loop = loop,
            driver = driver,
            session = session,
            settings = session_settings,
            models = saved_models,
            tools = tools,
            compaction = compaction,
            draft = next_draft,
        }
        return { agent = next_agent, status = next_draft.status() }
    end
    local agent_factory = function(message, source)
        log[#log + 1] = "agent:" .. source .. ":" .. message
        saved_model = draft_model
        if settings.automatic_preflight then
            loop_status = status("Preparing", {
                compaction_preflight_state = "pending",
                compaction_preflight_id = "turn-1:compaction-preflight:1",
                compaction_preflight_purpose = "main",
            })
        end
        return constructed_agent
    end

    local chat_draft = {}
    local draft_cautious_override = "inherit"
    local draft_context_prompt = ""
    function chat_draft.status()
        return {
            lifecycle = "not-saved",
            workspace = "/workspace",
            model = draft_model,
            permission = "Std",
            double_check = true,
            double_check_default = true,
            double_check_override = draft_cautious_override,
            context_prompt = draft_context_prompt,
        }
    end
    function chat_draft.update(changes)
        if changes.double_check_override ~= nil then
            A.truthy(changes.double_check_override == "inherit"
                or type(changes.double_check_override) == "boolean")
            draft_cautious_override = changes.double_check_override
            log[#log + 1] = "draft-cautious:"
                .. tostring(changes.double_check_override)
        else
            A.equal(type(changes.context_prompt), "string")
            draft_context_prompt = changes.context_prompt
            log[#log + 1] = "draft-prompt-bytes:"
                .. tostring(#changes.context_prompt)
        end
        local projected = chat_draft.status()
        projected.double_check = draft_cautious_override == "inherit"
            and true or draft_cautious_override
        return projected
    end
    function chat_draft:close()
        log[#log + 1] = "chat-draft-close"
        return true
    end
    local chat = {
        kind = settings.initial_agent and "continue-chat" or "run-chat",
        outcome = "ready",
        status = settings.initial_agent and draft.status() or chat_draft.status(),
        draft = settings.initial_agent and draft or chat_draft,
    }

    local view = {}
    function view:startup(startup_status)
        log[#log + 1] = "startup:" .. startup_status.workspace
        return true
    end
    function view:publish(block)
        blocks[#blocks + 1] = block
        return true
    end
    function view:prompt(focus)
        prompts[#prompts + 1] = focus
        return true
    end

    local coordinator = assert(main.new_application_coordinator({
        terminal = terminal,
        clock = { now = function() now = now + 1 return now end },
        idle_wait = function(milliseconds)
            log[#log + 1] = "wait:" .. tostring(milliseconds)
            return true
        end,
        cli = cli_service(),
        facts = {
            stdin_is_tty = true,
            stdout_is_tty = true,
            stderr_is_tty = true,
        },
        view = view,
        chat = chat,
        draft_models = draft_models,
        context_switch = context_switch,
        agent_factory = agent_factory,
        initial_agent = settings.initial_agent and constructed_agent or nil,
    }, {
        close_poll_steps = 8,
        idle_wait_ms = 1,
        maximum_assistant_bytes = 1024,
        maximum_draft_bytes = 1024,
        terminal_poll_events = 16,
    }))
    return {
        coordinator = coordinator,
        log = log,
        blocks = blocks,
        prompts = prompts,
    }
end

local function blocks_of_kind(blocks, kind)
    local selected = {}
    for _, block in ipairs(blocks) do
        if block.kind == kind then selected[#selected + 1] = block end
    end
    return selected
end

return {
    name = "integration/application-coordinator",
    cases = {
        {
            name = "first input drives the published Agent and typed close path",
            run = function()
                local f = fixture({ batches = {
                    { { kind = "user_action", action = "text", text = "implement" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                    { { kind = "user_action", action = "text", text = ".quit" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                } })
                local result = assert(f.coordinator:run())
                A.equal(result.outcome, "success")
                A.truthy(result.context_saved)
                A.contains(table.concat(f.log, "|"), "agent:terminal:implement")
                A.equal(blocks_of_kind(f.blocks, "user")[1].text, "implement")
                A.equal(blocks_of_kind(f.blocks, "assistant")[1].text, "implemented")
                A.contains(A.render(f.blocks), "Model yielded without finish")
                A.contains(table.concat(f.log, "|"), "session-close:application-close")
                A.equal(f.log[#f.log - 1], "terminal-restore")
                A.equal(f.log[#f.log], "terminal-close")
                A.equal(f.coordinator:status().lifecycle, "closed")
            end,
        },
        {
            name = "reopened Context enters with its existing idle Agent already owned",
            run = function()
                local f = fixture({ initial_agent = true, batches = {
                    { { kind = "user_action", action = "text", text = ".quit" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                } })
                local result = assert(f.coordinator:run())
                A.truthy(result.context_saved)
                local joined = table.concat(f.log, "|")
                A.falsy(joined:find("agent:terminal:", 1, true))
                A.contains(joined, "session-close:application-close")
                A.contains(joined, "draft-close")
                A.falsy(joined:find("chat-draft-close", 1, true))
            end,
        },
        {
            name = "cautious changes stay in an unsaved draft until the first turn",
            run = function()
                local f = fixture({ freeze_driver = true, batches = {
                    { { kind = "user_action", action = "text", text = ".cautious off" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                    { { kind = "user_action", action = "text", text = ".cautious" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                    { { kind = "user_action", action = "text", text = ".quit" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                } })
                assert(f.coordinator:run())
                local joined = table.concat(f.log, "|")
                A.contains(joined, "draft-cautious:false")
                A.falsy(joined:find("agent:terminal:", 1, true))
                local rendered = A.render(f.blocks)
                A.contains(rendered, "override=off effective=off")
                A.contains(rendered, "applies when the first turn starts")
            end,
        },
        {
            name = "saved cautious change advances its Context for the next turn while busy",
            run = function()
                local f = fixture({
                    initial_agent = true,
                    initial_state = "RequestingModel",
                    freeze_driver = true,
                    batches = {
                        { { kind = "user_action", action = "text", text = ".cautious off" } },
                        { { kind = "user_action", action = "submit-or-queue" } },
                        { { kind = "user_action", action = "text", text = ".cautious" } },
                        { { kind = "user_action", action = "submit-or-queue" } },
                        { { kind = "user_action", action = "text", text = ".quit" } },
                        { { kind = "user_action", action = "submit-or-queue" } },
                    },
                })
                assert(f.coordinator:run())
                A.contains(table.concat(f.log, "|"), "settings-cautious:false")
                local rendered = A.render(f.blocks)
                A.contains(rendered, "override=off effective=off")
                A.contains(rendered, "applies on the next turn")
            end,
        },
        {
            name = "prompt show set and clear use draft or durable next-turn settings",
            run = function()
                local unsaved = fixture({ freeze_driver = true, batches = {
                    { { kind = "user_action", action = "text", text = ".prompt set keep tests exact" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                    { { kind = "user_action", action = "text", text = ".prompt show" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                    { { kind = "user_action", action = "text", text = ".prompt clear" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                    { { kind = "user_action", action = "text", text = ".prompt edit" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                    { { kind = "user_action", action = "cancel" } },
                    { { kind = "user_action", action = "text", text = ".details error-1" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                    { { kind = "user_action", action = "text", text = ".quit" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                } })
                assert(unsaved.coordinator:run())
                A.contains(
                    table.concat(unsaved.log, "|"),
                    "draft-prompt-bytes:16"
                )
                A.contains(
                    table.concat(unsaved.log, "|"),
                    "draft-prompt-bytes:0"
                )
                local unsaved_rendered = A.render(unsaved.blocks)
                A.contains(unsaved_rendered, "keep tests exact")
                A.contains(unsaved_rendered, "applies when the first turn starts")
                A.contains(unsaved_rendered, "| (empty)")
                A.contains(unsaved_rendered, "InteractiveActionUnavailable")
                A.contains(unsaved_rendered, "bounded Prompt editor is not attached")
                local prompt_details = blocks_of_kind(unsaved.blocks, "details")
                A.equal(prompt_details[#prompt_details].id, "error-1")
                A.contains(
                    table.concat(prompt_details[#prompt_details].lines, "|"),
                    "code: InteractiveActionUnavailable"
                )

                local saved = fixture({
                    initial_agent = true,
                    initial_state = "RequestingModel",
                    freeze_driver = true,
                    batches = {
                        { { kind = "user_action", action = "text", text = ".prompt set next turn prompt" } },
                        { { kind = "user_action", action = "submit-or-queue" } },
                        { { kind = "user_action", action = "text", text = ".prompt show" } },
                        { { kind = "user_action", action = "submit-or-queue" } },
                        { { kind = "user_action", action = "text", text = ".quit" } },
                        { { kind = "user_action", action = "submit-or-queue" } },
                    },
                })
                assert(saved.coordinator:run())
                A.contains(
                    table.concat(saved.log, "|"),
                    "settings-prompt-bytes:16"
                )
                local saved_rendered = A.render(saved.blocks)
                A.contains(saved_rendered, "next turn prompt")
                A.contains(saved_rendered, "applies on the next turn")
            end,
        },
        {
            name = "model picker and safe draft switch retain an old CMD line fallback",
            run = function()
                local f = fixture({
                    freeze_driver = true,
                    model_direct = true,
                    batches = {
                        { { kind = "user_action", action = "text", text = ".model" } },
                        { { kind = "user_action", action = "submit-or-queue" } },
                        {
                            {
                                kind = "user_action",
                                action = "text",
                                text = ".model Secondary",
                            },
                        },
                        { { kind = "user_action", action = "submit-or-queue" } },
                        { { kind = "user_action", action = "text", text = ".quit" } },
                        { { kind = "user_action", action = "submit-or-queue" } },
                    },
                })
                assert(f.coordinator:run())
                local rendered = A.render(f.blocks)
                A.contains(rendered, "Use .model <exact-name>")
                A.contains(rendered, "Primary [current,default]")
                A.contains(rendered, "Secondary [available]")
                A.contains(rendered, "Model selected: Secondary; applies on the first turn")
                A.contains(table.concat(f.log, "|"), "draft-model:Secondary")
                A.falsy(rendered:find("api-key", 1, true))
            end,
        },
        {
            name = "saved cross-boundary model switch discloses and confirms exact next-turn change",
            run = function()
                local f = fixture({
                    initial_agent = true,
                    initial_state = "Idle",
                    freeze_driver = true,
                    batches = {
                        {
                            {
                                kind = "user_action",
                                action = "text",
                                text = ".model Secondary",
                            },
                        },
                        { { kind = "user_action", action = "submit-or-queue" } },
                        {
                            {
                                kind = "user_action",
                                action = "text",
                                text = "details model-change-1",
                            },
                        },
                        { { kind = "user_action", action = "submit-or-queue" } },
                        {
                            {
                                kind = "user_action",
                                action = "text",
                                text = "confirm model-change-1",
                            },
                        },
                        { { kind = "user_action", action = "submit-or-queue" } },
                        { { kind = "user_action", action = "text", text = ".quit" } },
                        { { kind = "user_action", action = "submit-or-queue" } },
                    },
                })
                assert(f.coordinator:run())
                local actions = blocks_of_kind(f.blocks, "action")
                A.equal(actions[1].id, "model-change-1")
                local disclosure = table.concat(actions[1].lines, "|")
                A.contains(disclosure, "from endpoint: https://primary.example")
                A.contains(disclosure, "to endpoint: https://secondary.example")
                A.contains(disclosure, "history: seq 1..3")
                A.contains(disclosure, "usage/amount: unavailable")
                A.contains(disclosure, "default: deny")
                local details = blocks_of_kind(f.blocks, "details")
                A.equal(details[1].id, "model-change-1")
                A.contains(table.concat(f.log, "|"), "saved-model:Secondary")
                A.contains(A.render(f.blocks),
                    "Model selected: Secondary; applies on the next turn")
                A.equal(f.prompts[1], "approval")
                A.equal(f.coordinator:status().model_change_action_id, false)
            end,
        },
        {
            name = "empty model confirmation line denies by default without mutation",
            run = function()
                local f = fixture({ freeze_driver = true, batches = {
                    {
                        {
                            kind = "user_action",
                            action = "text",
                            text = ".model Secondary",
                        },
                    },
                    { { kind = "user_action", action = "submit-or-queue" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                    { { kind = "user_action", action = "text", text = ".quit" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                } })
                assert(f.coordinator:run())
                A.falsy(table.concat(f.log, "|"):find("draft-model:", 1, true))
                local actions = blocks_of_kind(f.blocks, "action")
                A.equal(actions[2].text, "denied by default")
            end,
        },
        {
            name = "Tool approval supersedes an unapplied Model confirmation without two modal owners",
            run = function()
                local f = fixture({
                    initial_agent = true,
                    initial_state = "RequestingModel",
                    approval = true,
                    batches = {
                        {
                            {
                                kind = "user_action",
                                action = "text",
                                text = ".model Secondary",
                            },
                            { kind = "user_action", action = "submit-or-queue" },
                        },
                        {
                            {
                                kind = "user_action",
                                action = "text",
                                text = "deny approval-1",
                            },
                        },
                        { { kind = "user_action", action = "submit-or-queue" } },
                        { { kind = "user_action", action = "text", text = ".quit" } },
                        { { kind = "user_action", action = "submit-or-queue" } },
                    },
                })
                assert(f.coordinator:run())
                local actions = blocks_of_kind(f.blocks, "action")
                A.equal(actions[1].id, "model-change-1")
                A.equal(actions[2].id, "model-change-1")
                A.contains(actions[2].text, "Tool approval became pending")
                A.equal(actions[3].id, "approval-1")
                A.equal(actions[4].text, "denied")
                A.falsy(table.concat(f.log, "|"):find("saved-model:", 1, true))
                A.equal(f.coordinator:status().model_change_action_id, false)
            end,
        },
        {
            name = "context picker lists bounded recent targets without closing the draft",
            run = function()
                local f = fixture({ batches = {
                    { { kind = "user_action", action = "text", text = ".context" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                    { { kind = "user_action", action = "text", text = ".quit" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                } })
                assert(f.coordinator:run())
                local joined = table.concat(f.log, "|")
                A.contains(joined, "context-list")
                A.falsy(joined:find("context-preview:", 1, true))
                A.falsy(joined:find("context-activate:", 1, true))
                A.contains(A.render(f.blocks), "FEDCBA9876543210")
                A.contains(A.render(f.blocks), ".context <name-or-hash>")
            end,
        },
        {
            name = "context switch closes the old owner then activates only the previewed hash",
            run = function()
                local f = fixture({
                    initial_agent = true,
                    initial_state = "Idle",
                    freeze_driver = true,
                    batches = {
                        {
                            {
                                kind = "user_action",
                                action = "text",
                                text = ".context 0123456789abcdef",
                            },
                        },
                        { { kind = "user_action", action = "submit-or-queue" } },
                        {
                            {
                                kind = "user_action",
                                action = "text",
                                text = ".context second-task",
                            },
                        },
                        { { kind = "user_action", action = "submit-or-queue" } },
                        { { kind = "user_action", action = "text", text = ".quit" } },
                        { { kind = "user_action", action = "submit-or-queue" } },
                    },
                })
                assert(f.coordinator:run())
                local joined = table.concat(f.log, "|")
                local preview = assert(joined:find("context-preview:second-task", 1, true))
                local closed = assert(joined:find("session-close:context-switch", 1, true))
                local activated = assert(joined:find(
                    "context-activate:FEDCBA9876543210",
                    1,
                    true
                ))
                A.truthy(preview < closed and closed < activated)
                A.contains(A.render(f.blocks), "That Context is already active")
                A.contains(A.render(f.blocks), "Context switched: second-task")
                A.contains(joined, "next-draft-close")
            end,
        },
        {
            name = "unsaved chat can switch without publishing an empty replacement Context",
            run = function()
                local f = fixture({
                    freeze_driver = true,
                    batches = {
                        {
                            {
                                kind = "user_action",
                                action = "text",
                                text = ".context second-task",
                            },
                        },
                        { { kind = "user_action", action = "submit-or-queue" } },
                        { { kind = "user_action", action = "text", text = ".quit" } },
                        { { kind = "user_action", action = "submit-or-queue" } },
                    },
                })
                assert(f.coordinator:run())
                local joined = table.concat(f.log, "|")
                local closed = assert(joined:find("chat-draft-close", 1, true))
                local activated = assert(joined:find(
                    "context-activate:FEDCBA9876543210",
                    1,
                    true
                ))
                A.truthy(closed < activated)
                A.falsy(joined:find("agent:terminal:", 1, true))
                A.contains(joined, "next-draft-close")
            end,
        },
        {
            name = "post-close Context activation race is fatal and restores the terminal",
            run = function()
                local f = fixture({
                    initial_agent = true,
                    initial_state = "Idle",
                    freeze_driver = true,
                    context_activation_error = {
                        code = "TargetChanged",
                        message = "the previewed target changed",
                    },
                    batches = {
                        {
                            {
                                kind = "user_action",
                                action = "text",
                                text = ".context second-task",
                            },
                        },
                        { { kind = "user_action", action = "submit-or-queue" } },
                    },
                })
                local result, result_error = f.coordinator:run()
                A.falsy(result)
                A.equal(result_error.code, "TargetChanged")
                A.contains(table.concat(f.log, "|"), "session-close:context-switch")
                A.contains(A.render(f.blocks), "the previewed target changed")
                A.equal(f.log[#f.log - 1], "terminal-restore")
                A.equal(f.log[#f.log], "terminal-close")
            end,
        },
        {
            name = "busy Context switch rejects before previewing or closing the owner",
            run = function()
                local f = fixture({
                    initial_agent = true,
                    initial_state = "RequestingModel",
                    freeze_driver = true,
                    batches = {
                        {
                            {
                                kind = "user_action",
                                action = "text",
                                text = ".context second-task",
                            },
                        },
                        { { kind = "user_action", action = "submit-or-queue" } },
                        { { kind = "user_action", action = "cancel" } },
                        {
                            {
                                kind = "user_action",
                                action = "text",
                                text = ".details error-1",
                            },
                        },
                        { { kind = "user_action", action = "submit-or-queue" } },
                        { { kind = "user_action", action = "text", text = ".quit" } },
                        { { kind = "user_action", action = "submit-or-queue" } },
                    },
                })
                assert(f.coordinator:run())
                local joined = table.concat(f.log, "|")
                A.falsy(joined:find("context-preview:", 1, true))
                A.falsy(joined:find("session-close:context-switch", 1, true))
                A.contains(A.render(f.blocks), "requires an idle or waiting Agent")
                local errors = blocks_of_kind(f.blocks, "error")
                A.equal(errors[1].id, "error-1")
                A.contains(errors[1].text, "InteractiveActionUnavailable")
                local details = blocks_of_kind(f.blocks, "details")
                A.equal(details[#details].id, "error-1")
                A.contains(table.concat(details[#details].lines, "|"),
                    "code: InteractiveActionUnavailable")
                A.equal(f.coordinator:status().diagnostic_count, 1)
            end,
        },
        {
            name = "interactive diagnostics retain only the newest bounded error instances",
            run = function()
                local batches = {}
                for _ = 1, 65 do
                    batches[#batches + 1] = {
                        {
                            kind = "user_action",
                            action = "text",
                            text = ".context second-task",
                        },
                    }
                    batches[#batches + 1] = {
                        { kind = "user_action", action = "submit-or-queue" },
                    }
                    batches[#batches + 1] = {
                        { kind = "user_action", action = "cancel" },
                    }
                end
                batches[#batches + 1] = {
                    { kind = "user_action", action = "text", text = ".details" },
                }
                batches[#batches + 1] = {
                    { kind = "user_action", action = "submit-or-queue" },
                }
                batches[#batches + 1] = {
                    {
                        kind = "user_action",
                        action = "text",
                        text = ".details error-1",
                    },
                }
                batches[#batches + 1] = {
                    { kind = "user_action", action = "submit-or-queue" },
                }
                batches[#batches + 1] = {
                    { kind = "user_action", action = "cancel" },
                }
                batches[#batches + 1] = {
                    { kind = "user_action", action = "text", text = ".quit" },
                }
                batches[#batches + 1] = {
                    { kind = "user_action", action = "submit-or-queue" },
                }

                local f = fixture({
                    initial_agent = true,
                    initial_state = "RequestingModel",
                    freeze_driver = true,
                    batches = batches,
                })
                assert(f.coordinator:run())
                local details = blocks_of_kind(f.blocks, "details")
                A.equal(details[#details].id, "error-65")
                local errors = blocks_of_kind(f.blocks, "error")
                A.equal(#errors, 66)
                A.equal(errors[#errors].id, "error-66")
                A.contains(errors[#errors].text, "NotFound")
                A.equal(f.coordinator:status().diagnostic_count, 64)
            end,
        },
        {
            name = "approval view binds full snapshot and explicit allow once answer",
            run = function()
                local f = fixture({ approval = true, batches = {
                    { { kind = "user_action", action = "text", text = "change a" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                    {
                        {
                            kind = "user_action",
                            action = "text",
                            text = "allow approval-1 once",
                        },
                    },
                    { { kind = "user_action", action = "submit-or-queue" } },
                    { { kind = "user_action", action = "text", text = ".quit" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                } })
                assert(f.coordinator:run())
                local actions = blocks_of_kind(f.blocks, "action")
                A.equal(actions[1].id, "approval-1")
                A.contains(table.concat(actions[1].lines, "|"), "/workspace/a.lua")
                A.contains(table.concat(actions[1].lines, "|"), "default: deny")
                A.equal(actions[2].text, "allowed once")
                A.contains(table.concat(f.log, "|"),
                    "record-approval:turn-1:tool:1:tighten:approval-1:approve")
                A.contains(table.concat(f.log, "|"), "resolve-approval:approve")
                A.equal(f.prompts[1], "approval")
            end,
        },
        {
            name = "rejected busy lane preserves draft until explicit cancel clears it",
            run = function()
                local f = fixture({
                    side_error = {
                        code = "SideUnavailable",
                        message = "side request transport is unavailable",
                    },
                    batches = {
                        { { kind = "user_action", action = "text", text = "first" } },
                        { { kind = "user_action", action = "submit-or-queue" } },
                        { { kind = "user_action", action = "text", text = "why" } },
                        { { kind = "user_action", action = "side" } },
                        { { kind = "user_action", action = "cancel" } },
                        { { kind = "user_action", action = "text", text = ".quit" } },
                        { { kind = "user_action", action = "submit-or-queue" } },
                    },
                })
                assert(f.coordinator:run())
                A.contains(A.render(f.blocks), "side request transport is unavailable")
                A.contains(A.render(f.blocks), "Input draft cleared")
                A.equal(#blocks_of_kind(f.blocks, "user"), 1)
                A.equal(f.coordinator:status().draft_bytes, 0)
            end,
        },
        {
            name = "accepted side stream renders one separately identified advisory block",
            run = function()
                local f = fixture({
                    side_response = true,
                    batches = {
                        { { kind = "user_action", action = "text", text = "first" } },
                        { { kind = "user_action", action = "submit-or-queue" } },
                        {
                            {
                                kind = "user_action",
                                action = "text",
                                text = ".side explain the durable facts",
                            },
                        },
                        { { kind = "user_action", action = "submit-or-queue" } },
                        { { kind = "user_action", action = "text", text = ".quit" } },
                        { { kind = "user_action", action = "submit-or-queue" } },
                    },
                })
                assert(f.coordinator:run())
                local sides = blocks_of_kind(f.blocks, "side")
                A.equal(#sides, 1)
                A.equal(sides[1].id, "side-1")
                A.equal(sides[1].text, "bounded advice")
                A.contains(A.render(f.blocks), "Side side-1 outcome: completed")
                A.contains(table.concat(f.log, "|"), "stage:terminal:explain the durable facts")
                A.contains(table.concat(f.log, "|"), "side")
            end,
        },
        {
            name = "automatic compaction visibly pauses then resumes the pending Model request",
            run = function()
                local f = fixture({ automatic_preflight = true, batches = {
                    { { kind = "user_action", action = "text", text = "first" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                    { { kind = "user_action", action = "text", text = ".quit" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                } })
                assert(f.coordinator:run())
                local joined = table.concat(f.log, "|")
                A.contains(joined, "compaction-begin:automatic")
                A.contains(joined, "preflight-resolve:completed")
                A.contains(
                    A.render(f.blocks),
                    "Automatic compaction started: compaction-1"
                )
                A.contains(A.render(f.blocks), "Compaction completed: compaction-1")
                A.equal(blocks_of_kind(f.blocks, "assistant")[1].text, "implemented")
            end,
        },
        {
            name = "manual compact is publicly routed and cancel owns its active lane",
            run = function()
                local f = fixture({ compaction_active = true, batches = {
                    { { kind = "user_action", action = "text", text = "first" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                    { { kind = "user_action", action = "text", text = ".compact" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                    { { kind = "user_action", action = "text", text = ".cancel" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                    { { kind = "user_action", action = "text", text = ".quit" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                } })
                assert(f.coordinator:run())
                A.contains(table.concat(f.log, "|"), "compaction-begin:manual")
                A.contains(table.concat(f.log, "|"), "compaction-cancel:user-cancel")
                A.contains(A.render(f.blocks), "Compaction started: compaction-1")
                A.contains(A.render(f.blocks), "Compaction cancelled")
            end,
        },
        {
            name = "cancel follows active side focus without cancelling the paused main",
            run = function()
                local f = fixture({ batches = {
                    { { kind = "user_action", action = "text", text = "first" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                    {
                        {
                            kind = "user_action",
                            action = "text",
                            text = ".side bounded question",
                        },
                    },
                    { { kind = "user_action", action = "submit-or-queue" } },
                    { { kind = "user_action", action = "text", text = ".cancel" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                    { { kind = "user_action", action = "text", text = ".quit" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                } })
                assert(f.coordinator:run())
                A.contains(table.concat(f.log, "|"), "side-cancel:user-cancel")
                A.falsy(table.concat(f.log, "|"):find("loop-cancel", 1, true))
                A.contains(A.render(f.blocks), "Side cancellation requested")
            end,
        },
    },
}
