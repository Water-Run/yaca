--[[
Author: WaterRun
Date: 2026-09-23
File: application_coordinator_test.lua
Description: Verifies the interactive ApplicationCoordinator input, Agent, approval, and close paths.
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

local cache = {}
local json = load_module("json", cache)
local cli = load_module("cli", cache)
local main = load_module("main", cache)

--Supplies cli service behavior required by this suite.
--@param none No arguments; this closure uses its captured fixture state.
--@return any observed cli service value observed by the scenario assertion.
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

--Simulates the status transition of a fake activity port for this suite.
--@param state table|string Current state observed by the fixture.
--@param overrides table|nil Per-case overrides of default fixture behavior.
--@return any observed Selected fixture value returned by the fixture.
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
        ask_state = "idle",
        active_ask_id = false,
        last_outcome = false,
    }
    for key, item in pairs(overrides or {}) do value[key] = item end
    return value
end

--Constructs the suite's isolated runtime fixture and observation ports.
--@param settings table|nil Fixture settings and scenario overrides.
--@return table fixture Constructed fixture service used by this suite.
local function fixture(settings)
    settings = settings or {}
    local log = {}
    local blocks = {}
    local prompts = {}
    local batches = settings.batches or {}
    local now = 0
    local loop_status = status(settings.initial_state or "RequestingModel", settings.initial_status)
    local driver_steps = 0
    local ask_started = false
    local ask_emitted = false
    local compaction_active = false
    local cautious_override = "inherit"
    local cautious_default = true
    local context_prompt = ""
    local settings_serial = 0
    local saved_model = "Primary"
    local draft_model = "Primary"

    --Supplies model summary behavior required by this suite.
    --@param name string Module, Model, or resource name selected by the case.
    --@return table observed Structured fixture record selected by the exercised branch.
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
            proxy_policy = settings.proxy_route and "explicit-secret-slot" or "off",
            proxy_route = settings.proxy_route or "",
            context_length = secondary and 65536 or 32768,
            max_output_tokens = 4096,
            streaming = "try",
            tools = "native",
            controls = "yaca-native-v1",
            roles = "openai-chat-canonical-v1",
        }
    end

    --Supplies model owner behavior required by this suite.
    --@param durable any The durable supplied to the fake service for this scenario.
    --@return any observed model owner value observed by the scenario assertion.
    local function model_owner(durable)
        --@metatable fixture_view Test-owned lookup and mutation contract for the current case.
        --@field __mode any Weak-reference mode controlling fixture object retention.
        local bindings = setmetatable({}, { __mode = "k" })
        local owner = {}
        --Supplies current behavior required by this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return any observed current value observed by the scenario assertion.
        local function current()
            return durable and saved_model or draft_model
        end
        --Returns the list observation prepared for this suite.
        --@param self table Fixture or port instance receiving this call.
        --@return table observed Structured fixture record selected by the exercised branch.
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
        --Returns the preview observation prepared for this suite.
        --@param self table Fixture or port instance receiving this call.
        --@param selector string Context selector resolved by the case.
        --@return any|nil observed preview value observed by the scenario assertion.
        --@return table|nil secondary2 Typed error record with code ModelNotFound.
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
        --Supplies apply behavior required by this suite.
        --@param self table Fixture or port instance receiving this call.
        --@param preview table Preflight preview being confirmed or rejected.
        --@return table|nil observed Structured fixture record selected by the exercised branch.
        --@return table|nil secondary2 Typed error record with code ModelSelectionStale.
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
    local poll_count = 0
    --Simulates the start transition of a fake activity port for this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param observed_now any The observed now supplied to the fake service for this scenario.
    --@return boolean accepted Whether start succeeds in the fixture.
    function terminal:start(observed_now)
        log[#log + 1] = "terminal-start:" .. tostring(observed_now)
        return true
    end
    --Simulates the poll transition of a fake activity port for this suite.
    --@param self table Fixture or port instance receiving this call.
    --@return any observed poll value observed by the scenario assertion.
    function terminal:poll()
        poll_count = poll_count + 1
        if settings.on_poll then settings.on_poll(poll_count) end
        return table.remove(batches, 1) or {}
    end
    --Simulates the cancel transition of a fake activity port for this suite.
    --@param self table Fixture or port instance receiving this call.
    --@return boolean accepted Whether cancel succeeds in the fixture.
    function terminal:cancel()
        log[#log + 1] = "terminal-cancel"
        return true
    end
    --Simulates the join transition of a fake activity port for this suite.
    --@param self table Fixture or port instance receiving this call.
    --@return table observed Outcome record with status cancelled.
    function terminal:join()
        log[#log + 1] = "terminal-join"
        return { outcome = "cancelled" }
    end
    --Supplies restore behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@return boolean accepted Whether restore succeeds in the fixture.
    function terminal:restore()
        log[#log + 1] = "terminal-restore"
        return true
    end
    --Simulates the close transition of a fake activity port for this suite.
    --@param self table Fixture or port instance receiving this call.
    --@return boolean accepted Whether close succeeds in the fixture.
    function terminal:close()
        log[#log + 1] = "terminal-close"
        return true
    end

    local draft = {}
    --Simulates the status transition of a fake activity port for this suite.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return table observed Structured fixture record selected by the exercised branch.
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
    --Simulates the close transition of a fake activity port for this suite.
    --@param self table Fixture or port instance receiving this call.
    --@return boolean accepted Whether close succeeds in the fixture.
    function draft:close()
        log[#log + 1] = "draft-close"
        return true
    end

    local session = {}
    --Supplies stage behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param message string|table Message or diagnostic passed through this test port.
    --@param source string|table Source content or object under test.
    --@return table observed Structured fixture record with text.
    function session:stage(message, source)
        log[#log + 1] = "stage:" .. source .. ":" .. message
        return { text = message }
    end
    --Supplies submit behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@return table observed Structured fixture record with turn_id.
    function session:submit()
        log[#log + 1] = "submit"
        return { turn_id = "turn-2" }
    end
    --Supplies steer behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@return table observed Structured fixture record with steer_message_id.
    function session:steer()
        log[#log + 1] = "steer"
        return { steer_message_id = "turn-1:message:2" }
    end
    --Supplies ask behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@return table|nil observed Structured fixture record with ask_id; nil on alternate branches.
    --@return any|nil secondary2 Configured ask error override.
    function session:ask()
        if settings.ask_error then return nil, settings.ask_error end
        log[#log + 1] = "ask"
        ask_started = true
        loop_status = status(loop_status.state, {
            pending_kind = loop_status.pending_kind,
            ask_state = "active",
            active_ask_id = "ask-1",
        })
        return { ask_id = "ask-1" }
    end
    --Supplies queue list behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@return table observed Structured fixture record with count, maximum, items.
    function session:queue_list()
        return { count = 0, maximum = 9, items = {} }
    end
    --Simulates the close transition of a fake activity port for this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param reason string Failure or close reason supplied to the port.
    --@return boolean accepted Whether close succeeds in the fixture.
    function session:close(reason)
        log[#log + 1] = "session-close:" .. reason
        loop_status = status("Closing", { last_outcome = "cancelled" })
        return true
    end

    local loop = {}
    --Simulates the status transition of a fake activity port for this suite.
    --@param self table Fixture or port instance receiving this call.
    --@return any observed status value observed by the scenario assertion.
    function loop:status() return loop_status end
    --Simulates the cancel transition of a fake activity port for this suite.
    --@param self table Fixture or port instance receiving this call.
    --@return table observed Outcome record with status cancelled.
    function loop:cancel()
        log[#log + 1] = "loop-cancel"
        loop_status = status("Idle", { last_outcome = "cancelled" })
        return { outcome = "cancelled" }
    end
    --Supplies cancel ask behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param command string|table Command delivered to the fake executor.
    --@return table observed Outcome record with status cancelled.
    function loop:cancel_ask(command)
        A.equal(command.ask_id, "ask-1")
        A.equal(command.expected_context_generation, loop_status.context_generation)
        A.equal(command.expected_turn_id, loop_status.turn_id)
        log[#log + 1] = "ask-cancel:" .. command.reason
        loop_status = status(loop_status.state, {
            pending_kind = loop_status.pending_kind,
            ask_state = "idle",
            active_ask_id = false,
        })
        return { ask_id = command.ask_id, outcome = "cancelled" }
    end
    --Supplies resolve approval behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param envelope table Transport or activity envelope under inspection.
    --@return table observed Structured fixture record with state.
    function loop:resolve_approval(envelope)
        log[#log + 1] = "resolve-approval:" .. envelope.decision
        loop_status = status("RequestingModel")
        return { state = "RequestingModel" }
    end
    --Supplies resolve compaction preflight behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param command string|table Command delivered to the fake executor.
    --@return table observed Structured fixture record with state, request_id.
    function loop:resolve_compaction_preflight(command)
        A.equal(command.preflight_id, "turn-1:compaction-preflight:1")
        A.equal(command.outcome, "completed")
        A.equal(command.settlement.mode, "automatic")
        log[#log + 1] = "preflight-resolve:" .. command.outcome
        loop_status = status("RequestingModel")
        return { state = "RequestingModel", request_id = "turn-1:request:1" }
    end

    local tools = {}
    --Supplies prepare approval behavior required by this suite.
    --@param tool_call_id any The tool call id supplied to the fake service for this scenario.
    --@param review_verdict any The review verdict supplied to the fake service for this scenario.
    --@return table observed Structured fixture record selected by the exercised branch.
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
    --Supplies record approval behavior required by this suite.
    --@param tool_call_id any The tool call id supplied to the fake service for this scenario.
    --@param review_verdict any The review verdict supplied to the fake service for this scenario.
    --@param approval_id string|integer Approval identity being resolved.
    --@param answer any The answer supplied to the fake service for this scenario.
    --@return table observed Structured fixture record selected by the exercised branch.
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
    --Simulates the status transition of a fake activity port for this suite.
    --@param self table Fixture or port instance receiving this call.
    --@return table observed Structured fixture record selected by the exercised branch.
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
            context_prompt = settings.changed_prompt or context_prompt,
            effective_at = "current",
        }
    end
    --Supplies update behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param change any The change supplied to the fake service for this scenario.
    --@return any|nil observed update value observed by the scenario assertion.
    --@return any|nil secondary2 Configured prompt save error override.
    function session_settings:update(change)
        if settings.prompt_save_error and change.name == "ContextPrompt" then
            return nil, settings.prompt_save_error
        end
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
    --Simulates the scan registered secrets boundary for this suite.
    --@param bytes string Byte chunk supplied to the fake I/O port.
    --@return table|nil observed Structured fixture record selected by the exercised branch.
    --@return any|nil secondary2 Configured prompt scan error override.
    function session_settings.scan_registered_secrets(bytes)
        if settings.prompt_scan_error then return nil, settings.prompt_scan_error end
        if bytes:find("fixture-secret", 1, true) then return { { id = "test-secret" } } end
        return {}
    end

    local driver = {}
    --Simulates the step transition of a fake activity port for this suite.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return table observed Structured fixture record selected by the exercised branch.
    function driver.step()
        driver_steps = driver_steps + 1
        if settings.driver_events and driver_steps == 1 then
            return { events = settings.driver_events, status = loop_status, progressed = true }
        end
        if settings.freeze_driver then
            return { events = {}, status = loop_status, progressed = false }
        end
        if settings.ask_response and ask_started and not ask_emitted then
            ask_emitted = true
            loop_status = status(loop_status.state, {
                pending_kind = loop_status.pending_kind,
                ask_state = "idle",
                active_ask_id = false,
            })
            return {
                events = {
                    {
                        kind = "ask-model-event",
                        ask_id = "ask-1",
                        event = { kind = "text_delta", text = "bounded advice" },
                    },
                    {
                        kind = "ask-model-event",
                        ask_id = "ask-1",
                        event = { kind = "response_finish", finish_class = "stop" },
                    },
                    {
                        kind = "runtime-transition",
                        cause = "ask-response",
                        ask_id = "ask-1",
                        result = { ask_id = "ask-1", outcome = "completed" },
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
                        event = settings.model_control or { kind = "text_delta", text = "implemented" },
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
    --Simulates the begin transition of a fake activity port for this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param mode string Operating mode selected by the scenario.
    --@return table observed Structured fixture record selected by the exercised branch.
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
    --Simulates the poll transition of a fake activity port for this suite.
    --@param self table Fixture or port instance receiving this call.
    --@return table observed Structured fixture record selected by the exercised branch.
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
    --Simulates the cancel transition of a fake activity port for this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param reason string Failure or close reason supplied to the port.
    --@return table observed Outcome record with status cancelled.
    function compaction:cancel(reason)
        log[#log + 1] = "compaction-cancel:" .. reason
        compaction_active = false
        return {
            result = { outcome = "cancelled", compaction_id = "compaction-1" },
            settlement = { outcome = "cancelled" },
        }
    end
    --Simulates the status transition of a fake activity port for this suite.
    --@param self table Fixture or port instance receiving this call.
    --@return table observed Structured fixture record selected by the exercised branch.
    function compaction:status()
        return {
            state = compaction_active and "Compacting" or "Idle",
            active = compaction_active,
            active_compaction_id = compaction_active and "compaction-1" or false,
            automatic_failure_count = 0,
            automatic_circuit_state = "closed",
        }
    end
    --Simulates the close transition of a fake activity port for this suite.
    --@param self table Fixture or port instance receiving this call.
    --@return boolean accepted Whether close succeeds in the fixture.
    function compaction:close()
        compaction_active = false
        return true
    end

    local constructed_agent = {
        approval_initial_serial = settings.approval_initial_serial,
        loop = loop,
        driver = driver,
        session = session,
        settings = session_settings,
        models = saved_models,
        tools = tools,
        compaction = compaction,
        draft = draft,
        --Supplies context status behavior required by this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return table|nil value Callback value consumed by the enclosing scenario assertion.
        --@return any|nil secondary2 Configured context inspection error override.
        context_status = function()
            log[#log + 1] = "context-inspect"
            if settings.context_inspection_error then
                return nil, settings.context_inspection_error
            end
            return { display_name = "current-task", context_hash = "ABCDABCD12341234" }
        end,
    }
    local context_switch = {}
    --Returns the list observation prepared for this suite.
    --@param self table Fixture or port instance receiving this call.
    --@return table observed Structured fixture record selected by the exercised branch.
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
    --Returns the preview observation prepared for this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param selector string Context selector resolved by the case.
    --@return table|nil observed Structured fixture record selected by the exercised branch.
    --@return any|nil secondary2 Configured context preview error override.
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
            origin_workspace = "/workspace",
            recorded_workspace = settings.cross_workspace and "/other" or "/workspace",
            requires_workspace_confirmation = settings.cross_workspace == true,
        }
    end
    --Supplies activate behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param preview table Preflight preview being confirmed or rejected.
    --@param confirmation any The confirmation supplied to the fake service for this scenario.
    --@return table|nil observed Structured fixture record with agent, status; nil on alternate branches.
    --@return any|nil secondary2 Configured context activation error override.
    function context_switch:activate(preview, confirmation)
        log[#log + 1] = "context-activate:" .. preview.context_hash
        if settings.cross_workspace then A.equal(confirmation, "CONTINUE " .. preview.context_hash) end
        if settings.context_activation_error then
            return nil, settings.context_activation_error
        end
        loop_status = status("Idle", { turn_id = false })
        local next_draft = {}
        --Simulates the status transition of a fake activity port for this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return table observed Structured fixture record selected by the exercised branch.
        function next_draft.status()
            return {
                lifecycle = "saved",
                durable = true,
                workspace = settings.cross_workspace and "/other" or "/workspace",
                model = saved_model,
                permission = "Std",
                double_check = true,
                display_name = "second-task",
                context_hash = "FEDCBA9876543210",
                logical_path = "/workspace/Second.xml",
            }
        end
        --Simulates the close transition of a fake activity port for this suite.
        --@param self table Fixture or port instance receiving this call.
        --@return boolean accepted Whether close succeeds in the fixture.
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
    --Supplies agent factory behavior required by this suite.
    --@param message string|table Message or diagnostic passed through this test port.
    --@param source string|table Source content or object under test.
    --@param lane any The lane supplied to the fake service for this scenario.
    --@return any|nil value Callback value consumed by the enclosing scenario assertion.
    --@return any|nil secondary2 Configured factory error override.
    local agent_factory = function(message, source, lane)
        if settings.expected_first_lane then A.equal(lane, settings.expected_first_lane) end
        log[#log + 1] = "agent:" .. source .. ":" .. message
        if settings.factory_error then
            settings.factory_closed = true
            return nil, settings.factory_error
        end
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
    --Builds the config generation values used by this suite.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return table observed Structured fixture record with scan_registered_secrets.
    function chat_draft.config_generation()
        return { scan_registered_secrets = session_settings.scan_registered_secrets }
    end
    --Simulates the status transition of a fake activity port for this suite.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return table observed Structured fixture record selected by the exercised branch.
    function chat_draft.status()
        return {
            lifecycle = settings.factory_closed and "closed" or "not-saved",
            workspace = "/workspace",
            model = draft_model,
            permission = "Std",
            double_check = true,
            double_check_default = true,
            double_check_override = draft_cautious_override,
            context_prompt = draft_context_prompt,
        }
    end
    --Supplies update behavior required by this suite.
    --@param changes table Proposed changes exercised by the case.
    --@return any observed update value observed by the scenario assertion.
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
    --Simulates the close transition of a fake activity port for this suite.
    --@param self table Fixture or port instance receiving this call.
    --@return boolean accepted Whether close succeeds in the fixture.
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
    --Supplies startup behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param startup_status any The startup status supplied to the fake service for this scenario.
    --@return boolean accepted Whether startup succeeds in the fixture.
    function view:startup(startup_status)
        log[#log + 1] = "startup:" .. startup_status.workspace
        return true
    end
    --Records the publish effect observed by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param block table|string Transcript or storage block under test.
    --@return boolean accepted Whether publish succeeds in the fixture.
    function view:publish(block)
        blocks[#blocks + 1] = block
        return true
    end
    --Supplies prompt behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param focus any The focus supplied to the fake service for this scenario.
    --@return boolean accepted Whether prompt succeeds in the fixture.
    function view:prompt(focus)
        prompts[#prompts + 1] = focus
        return true
    end

    local coordinator = assert(main.new_application_coordinator({
        terminal = terminal,
        clock = {
            --Supplies deterministic clock behavior for this suite.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return any value Callback value consumed by the enclosing scenario assertion.
            now = function() now = now + 1 return now end },
        --Supplies idle wait behavior required by this suite.
        --@param milliseconds integer Requested fake-clock delay in milliseconds.
        --@return boolean accepted Whether the fake callback accepts this scenario.
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
        --Supplies current prompt behavior required by this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        current_prompt = function()
            if settings.initial_agent then return context_prompt end
            return draft_context_prompt
        end,
    }
end

--Supplies input lines behavior required by this suite.
--@param lines any The lines supplied to the fake service for this scenario.
--@return any observed input lines value observed by the scenario assertion.
local function input_lines(lines)
    local batches = {}
    for _, line in ipairs(lines) do
        batches[#batches + 1] = {
            { kind = "user_action", action = "text", text = line },
            { kind = "user_action", action = "submit-or-queue" },
        }
    end
    return batches
end

--Supplies blocks of kind behavior required by this suite.
--@param blocks any The blocks supplied to the fake service for this scenario.
--@param kind string Kind of event or resource under test.
--@return any observed blocks of kind value observed by the scenario assertion.
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
            name = "cooked multiline collects literal lines and starts first Ask only on explicit submission",
            --Verifies cooked multiline collects literal lines and starts first Ask only on explicit submission.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify cooked multiline collects literal lines and starts first Ask only on explicit submission.
            run = function()
                local batches = {}
                for _, line in ipairs({ ".multiline", "中文问题", "..status", ".ask", ".quit" }) do
                    batches[#batches + 1] = {
                        { kind = "user_action", action = "text", text = line },
                        { kind = "user_action", action = "submit-or-queue" },
                    }
                end
                local f = fixture({ expected_first_lane = "ask", batches = batches })
                assert(f.coordinator:run())
                A.contains(table.concat(f.log, "|"), "agent:terminal:中文问题\n.status")
                A.contains(table.concat(f.log, "|"), "stage:terminal:中文问题\n.status|ask")
                A.equal(#blocks_of_kind(f.blocks, "error"), 0)
            end,
        },
        {
            name = "Ask works as the first submitted line and enters only the Ask lane",
            --Verifies ask works as the first submitted line and enters only the Ask lane.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify ask works as the first submitted line and enters only the Ask lane.
            run = function()
                local f = fixture({ expected_first_lane = "ask", batches = {
                    { { kind = "user_action", action = "text", text = ".ask only a question" },
                      { kind = "user_action", action = "submit-or-queue" } },
                    { { kind = "user_action", action = "text", text = ".quit" },
                      { kind = "user_action", action = "submit-or-queue" } },
                } })
                assert(f.coordinator:run())
                A.contains(table.concat(f.log, "|"), "stage:terminal:only a question|ask")
                A.falsy(table.concat(f.log, "|"):find("|submit|", 1, true))
                A.equal(#blocks_of_kind(f.blocks, "error"), 0)
            end,
        },
        {
            name = "one tool keeps the same display identity from request through process output",
            --Verifies ask works as the first submitted line and enters only the Ask lane.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify ask works as the first submitted line and enters only the Ask lane.
            run = function()
                local f = fixture({ initial_agent = true, batches = { {},
                    { { kind = "user_action", action = "text", text = ".quit" },
                      { kind = "user_action", action = "submit-or-queue" } },
                }, driver_events = {
                    { kind = "model-event", event = { kind = "tool_call_start",
                        local_tool_call_id = "request-7:tool:1", name = "lua" } },
                    { kind = "model-event", event = { kind = "tool_call_complete",
                        local_tool_call_id = "request-7:tool:1", name = "lua",
                        canonical_arguments = '{"code":"print(42)"}' } },
                    { kind = "tool-event", tool_call_id = "turn-1:tool:3",
                        adapter_call_id = "request-7:tool:1",
                        event = { kind = "io_terminal", outcome = "completed" } },
                } })
                assert(f.coordinator:run())
                local blocks = blocks_of_kind(f.blocks, "tool")
                A.equal(#blocks, 3)
                for _, block in ipairs(blocks) do A.equal(block.id, "tool-1") end
            end,
        },
        {
            name = "rejected command does not contaminate the next cooked input line",
            --Verifies rejected command does not contaminate the next cooked input line.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify rejected command does not contaminate the next cooked input line.
            run = function()
                local f = fixture({ batches = input_lines({
                    ".side obsolete", ".status", ".help", ".quit",
                }) })
                assert(f.coordinator:run())
                A.equal(#blocks_of_kind(f.blocks, "error"), 1)
                A.equal(blocks_of_kind(f.blocks, "details")[1].id, "status")
                A.contains(A.render(f.blocks), ".ask")
                A.equal(f.coordinator:status().draft_bytes, 0)
            end,
        },
        {
            name = "reopened approvals continue above the durable identity waterline",
            --Verifies rejected command does not contaminate the next cooked input line.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify rejected command does not contaminate the next cooked input line.
            run = function()
                local lines = input_lines({ "allow approval-8 once", ".quit" })
                local f = fixture({ initial_agent = true, approval = true,
                    approval_initial_serial = 7, batches = { {}, lines[1], lines[2] } })
                assert(f.coordinator:run())
                local actions = blocks_of_kind(f.blocks, "action")
                A.equal(actions[1].id, "approval-8")
                A.equal(actions[2].text, "allowed once")
                local joined = table.concat(f.log, "|")
                A.contains(joined, "record-approval:turn-1:tool:1:tighten:approval-8:approve")
                A.falsy(joined:find("tighten:approval-1:approve", 1, true))
            end,
        },
        {
            name = "unresolved reviews explain the available recovery without claiming success",
            --Verifies reopened approvals continue above the durable identity waterline.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify reopened approvals continue above the durable identity waterline.
            run = function()
                for _, kind in ipairs({ "termination-review", "action-review" }) do
                    local lines = input_lines({ ".cancel", ".quit" })
                    local f = fixture({ initial_agent = true, freeze_driver = true,
                        initial_state = "WaitingUser", initial_status = { pending_kind = kind },
                        batches = { {}, {}, lines[1], lines[2] } })
                    assert(f.coordinator:run())
                    local notices = blocks_of_kind(f.blocks, "notice")
                    A.equal(#notices, 1)
                    A.contains(notices[1].text, ".cancel")
                    A.contains(notices[1].text, kind == "termination-review"
                        and "Reply with clarification" or "proposed tool has not run")
                    A.contains(table.concat(f.log, "|"), "loop-cancel")
                    A.falsy(A.render(f.blocks):find("Turn outcome: completed", 1, true))
                end
            end,
        },
        {
            name = "finish summaries and refusal reasons remain visible assistant content",
            --Verifies finish summaries and refusal reasons remain visible assistant content.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify finish summaries and refusal reasons remain visible assistant content.
            run = function()
                for _, control in ipairs({
                    { kind = "control", control = "finish", payload = { summary = "verified file contents" } },
                    { kind = "control", control = "refuse", payload = { reason = "requested capability denied" } },
                }) do
                    local f = fixture({ initial_agent = true, model_control = control,
                        batches = { {}, input_lines({ ".quit" })[1] } })
                    assert(f.coordinator:run())
                    local assistant = blocks_of_kind(f.blocks, "assistant")
                    A.equal(#assistant, 1)
                    A.equal(assistant[1].text, control.payload.summary or control.payload.reason)
                end
            end,
        },
        {
            name = "Prompt edit publication failure retains its draft for explicit retry",
            --Verifies finish summaries and refusal reasons remain visible assistant content.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify finish summaries and refusal reasons remain visible assistant content.
            run = function()
                local f
                local settings = { initial_agent = true, freeze_driver = true,
                    prompt_save_error = { code = "ConfigInvalid", message = "configuration needs repair" },
                    batches = input_lines({
                        ".prompt edit", "retry safely", ".save prompt-edit-1", ".show",
                        ".save prompt-edit-1", ".quit",
                    }),
                }
                --Records the event callback behavior exercised by the 'Prompt edit publication failure retains its draft for explicit retry' case.
                --@param count integer Number of items or calls expected by the fixture.
                --@return nil No value; assertions verify finish summaries and refusal reasons remain visible assistant content.
                settings.on_poll = function(count)
                    if count == 4 then
                        A.equal(f.current_prompt(), "")
                        settings.prompt_save_error = nil
                    end
                end
                f = fixture(settings)
                assert(f.coordinator:run())
                A.equal(f.current_prompt(), "retry safely")
                A.contains(A.render(f.blocks), "ConfigInvalid")
                A.contains(A.render(f.blocks), "effective: not saved")
            end,
        },
        {
            name = "Tool approval preempts a Prompt draft without applying it",
            --Verifies tool approval preempts a Prompt draft without applying it.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify tool approval preempts a Prompt draft without applying it.
            run = function()
                local batches = input_lines({ "deny approval-1", ".quit" })
                table.insert(batches, 1, {
                    { kind = "user_action", action = "text", text = ".prompt edit" },
                    { kind = "user_action", action = "submit-or-queue" },
                    { kind = "user_action", action = "text", text = "pending draft" },
                    { kind = "user_action", action = "submit-or-queue" },
                })
                local f = fixture({ initial_agent = true, approval = true, batches = batches })
                assert(f.coordinator:run())
                local actions = blocks_of_kind(f.blocks, "action")
                A.equal(actions[1].id, "prompt-edit-1")
                A.equal(actions[2].id, "prompt-edit-1")
                A.contains(actions[2].text, "not saved; a Tool approval became pending")
                A.equal(actions[3].id, "approval-1")
                A.equal(actions[4].text, "denied")
                A.equal(f.current_prompt(), "")
                A.falsy(f.coordinator:status().prompt_editor_id)
            end,
        },
        {
            name = "Prompt editing rejects ask input and clear reset keep save explicit",
            --Verifies prompt editing rejects ask input and clear reset keep save explicit.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify prompt editing rejects ask input and clear reset keep save explicit.
            run = function()
                local batches = input_lines({ ".prompt set initial", ".prompt edit", ".clear", ".reset", ".status" })
                batches[#batches + 1] = {
                    { kind = "user_action", action = "text", text = "not a ask question" },
                    { kind = "user_action", action = "ask" },
                }
                batches[#batches + 1] = { { kind = "user_action", action = "cancel" } }
                batches[#batches + 1] = input_lines({ ".quit" })[1]
                local f = fixture({ initial_agent = true, freeze_driver = true, batches = batches })
                assert(f.coordinator:run())
                A.equal(f.current_prompt(), "initial")
                A.contains(A.render(f.blocks), "prompt editor: prompt-edit-1 (7 bytes; not saved)")
                A.contains(A.render(f.blocks), "PromptEditorBusy")
                A.falsy(table.concat(f.log, "|"):find("ask:", 1, true))
            end,
        },
        {
            name = "Prompt editor saves a bounded literal multiline draft only on exact save",
            --Verifies prompt editor saves a bounded literal multiline draft only on exact save.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify prompt editor saves a bounded literal multiline draft only on exact save.
            run = function()
                for _, saved in ipairs({ false, true }) do
                    local f
                    local settings = { initial_agent = saved, freeze_driver = true,
                        batches = input_lines({
                            ".prompt set original", ".prompt edit", ".clear", " first ", "",
                            "second line", "..save prompt-edit-1", ".show", ".save prompt-edit-1",
                            ".prompt show", ".quit",
                        }),
                        --Records the event callback behavior exercised by the 'Prompt editor saves a bounded literal multiline draft only on exact save' case.
                        --@param count integer Number of items or calls expected by the fixture.
                        --@return nil No value; assertions verify prompt editor saves a bounded literal multiline draft only on exact save.
                        on_poll = function(count)
                            if count >= 3 and count <= 9 then A.equal(f.current_prompt(), "original") end
                        end,
                    }
                    f = fixture(settings)
                    assert(f.coordinator:run())
                    A.equal(f.current_prompt(), " first \n\nsecond line\n.save prompt-edit-1")
                    local rendered = A.render(f.blocks)
                    A.contains(rendered, "Editing ContextPrompt in memory")
                    A.contains(rendered, "effective: not saved")
                    A.contains(rendered, "saved")
                    A.equal(f.coordinator:status().prompt_editor_bytes, 0)
                    A.falsy(f.coordinator:status().prompt_editor_id)
                    A.falsy(table.concat(f.log, "|"):find("agent:terminal:", 1, true))
                    A.equal(#blocks_of_kind(f.blocks, "user"), 0)
                end
            end,
        },
        {
            name = "Prompt editor cancel quit and terminal end discard staged text",
            --Verifies prompt editor cancel quit and terminal end discard staged text.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify prompt editor cancel quit and terminal end discard staged text.
            run = function()
                for _, ending in ipairs({ ".cancel", ".quit", "escape", "eof" }) do
                    local batches = input_lines({ ".prompt edit", "discard this" })
                    if ending == "escape" or ending == "eof" then
                        batches[#batches + 1] = { {
                            kind = "user_action", action = ending == "escape" and "cancel" or "eof",
                        } }
                    else
                        batches[#batches + 1] = input_lines({ ending })[1]
                    end
                    if ending ~= ".quit" and ending ~= "eof" then
                        batches[#batches + 1] = input_lines({ ".quit" })[1]
                    end
                    local f = fixture({ freeze_driver = true, batches = batches })
                    assert(f.coordinator:run())
                    A.equal(f.current_prompt(), "")
                    A.falsy(table.concat(f.log, "|"):find("draft-prompt-bytes:", 1, true))
                    A.falsy(table.concat(f.log, "|"):find("agent:terminal:", 1, true))
                    A.equal(f.coordinator:status().prompt_editor_bytes, 0)
                end
            end,
        },
        {
            name = "Prompt editor rejects secret overflow and stale save while retaining safe draft",
            --Verifies prompt editor rejects secret overflow and stale save while retaining safe draft.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify prompt editor rejects secret overflow and stale save while retaining safe draft.
            run = function()
                local f = fixture({ initial_agent = true, freeze_driver = true,
                    batches = input_lines({
                        ".prompt edit", "safe", "fixture-secret", string.rep("x", 1020),
                        ".save prompt-edit-9", ".show", ".save prompt-edit-1", ".quit",
                    }),
                })
                assert(f.coordinator:run())
                A.equal(f.current_prompt(), "safe")
                local rendered = A.render(f.blocks)
                A.contains(rendered, "RegisteredSecret")
                A.contains(rendered, "DraftLimit")
                A.contains(rendered, "PromptEditorStale")
                A.falsy(rendered:find("fixture-secret", 1, true))
                A.falsy(rendered:find(string.rep("x", 1020), 1, true))
            end,
        },
        {
            name = "Prompt editor notices changed Session and never overwrites it",
            --Verifies prompt editor notices changed Session and never overwrites it.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify prompt editor notices changed Session and never overwrites it.
            run = function()
                local settings = { initial_agent = true, freeze_driver = true,
                    batches = input_lines({ ".prompt edit", "draft", ".save prompt-edit-1", ".cancel", ".quit" }),
                }
                --Records the event callback behavior exercised by the 'Prompt editor notices changed Session and never overwrites it' case.
                --@param count integer Number of items or calls expected by the fixture.
                --@return nil No value; assertions verify prompt editor notices changed Session and never overwrites it.
                settings.on_poll = function(count)
                    if count == 3 then settings.changed_prompt = "changed elsewhere" end
                end
                local f = fixture(settings)
                assert(f.coordinator:run())
                A.equal(f.current_prompt(), "")
                A.contains(A.render(f.blocks), "Session settings changed")
                A.falsy(table.concat(f.log, "|"):find("settings-prompt-bytes:", 1, true))
            end,
        },
        {
            name = "status shows current owned Context and effective Session settings",
            --Verifies prompt editor notices changed Session and never overwrites it.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify prompt editor notices changed Session and never overwrites it.
            run = function()
                local f = fixture({ initial_agent = true, freeze_driver = true, batches = {
                    { { kind = "user_action", action = "text", text = ".cautious off" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                    { { kind = "user_action", action = "text", text = ".status" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                    { { kind = "user_action", action = "text", text = ".quit" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                } })
                assert(f.coordinator:run())
                local rendered = A.render(blocks_of_kind(f.blocks, "details"))
                A.contains(rendered, "context: current-task")
                A.contains(rendered, "context hash: ABCDABCD12341234")
                A.falsy(rendered:find("0123456789ABCDEF", 1, true))
                A.contains(rendered, "workspace: /workspace")
                A.contains(rendered, "permission: Std")
                A.contains(rendered, "double-check: false")
                A.contains(rendered, "config: config-settings-1")
                A.falsy(table.concat(f.log, "|"):find("context-list", 1, true))
            end,
        },
        {
            name = "status renders stale and closes before accepting another action",
            --Verifies status renders stale and closes before accepting another action.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify status renders stale and closes before accepting another action.
            run = function()
                local f = fixture({ initial_agent = true, freeze_driver = true,
                    context_inspection_error = {
                        code = "ContextStale", message = "active file changed",
                    }, batches = {
                        { { kind = "user_action", action = "text", text = ".status" } },
                        {
                            { kind = "user_action", action = "submit-or-queue" },
                            { kind = "user_action", action = "text", text = "must not run" },
                            { kind = "user_action", action = "submit-or-queue" },
                        },
                    },
                })
                local result, result_error = f.coordinator:run()
                A.falsy(result)
                A.equal(result_error.code, "ContextStale")
                local rendered = A.render(blocks_of_kind(f.blocks, "details"))
                A.contains(rendered, "context hash: stale")
                A.contains(rendered, "fail-stop: ContextStale: active file changed")
                A.falsy(rendered:find("0123456789ABCDEF", 1, true))
                A.falsy(table.concat(f.log, "|"):find("must not run", 1, true))
                A.equal(f.coordinator:status().lifecycle, "closed")
                A.contains(table.concat(f.log, "|"), "draft-close")
            end,
        },
        {
            name = "failed first Agent construction closes a consumed draft and restores input",
            --Verifies failed first Agent construction closes a consumed draft and restores input.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify failed first Agent construction closes a consumed draft and restores input.
            run = function()
                local f = fixture({
                    factory_error = { code = "InvalidContextIdentity", message = "identity missing" },
                    batches = input_lines({ "implement", "must not run" }),
                })
                local result, result_error = f.coordinator:run()
                A.falsy(result)
                A.equal(result_error.code, "InvalidContextIdentity")
                A.falsy(table.concat(f.log, "|"):find("must not run", 1, true))
                A.equal(f.log[#f.log - 1], "terminal-restore")
                A.equal(f.log[#f.log], "terminal-close")
            end,
        },
        {
            name = "first input drives the published Agent and typed close path",
            --Verifies failed first Agent construction closes a consumed draft and restores input.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify failed first Agent construction closes a consumed draft and restores input.
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
            --Verifies reopened Context enters with its existing idle Agent already owned.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify reopened Context enters with its existing idle Agent already owned.
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
            --Verifies reopened Context enters with its existing idle Agent already owned.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify reopened Context enters with its existing idle Agent already owned.
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
            --Verifies saved cautious change advances its Context for the next turn while busy.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify saved cautious change advances its Context for the next turn while busy.
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
            --Verifies prompt show set and clear use draft or durable next-turn settings.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify prompt show set and clear use draft or durable next-turn settings.
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
                A.contains(unsaved_rendered, "Editing ContextPrompt in memory")
                A.contains(unsaved_rendered, "not saved; cancelled")

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
            --Verifies model picker and safe draft switch retain an old CMD line fallback.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify model picker and safe draft switch retain an old CMD line fallback.
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
            --Verifies saved cross-boundary model switch discloses and confirms exact next-turn change.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify saved cross-boundary model switch discloses and confirms exact next-turn change.
            run = function()
                local f = fixture({
                    proxy_route = "https://proxy.example/tunnel?configured",
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
                A.contains(disclosure,
                    "to proxy: explicit-secret-slot https://proxy.example/tunnel?configured")
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
            --Verifies empty model confirmation line denies by default without mutation.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify empty model confirmation line denies by default without mutation.
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
            --Verifies tool approval supersedes an unapplied Model confirmation without two modal owners.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify tool approval supersedes an unapplied Model confirmation without two modal owners.
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
            --Verifies context picker lists bounded recent targets without closing the draft.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify context picker lists bounded recent targets without closing the draft.
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
            --Verifies context switch closes the old owner then activates only the previewed hash.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify context switch closes the old owner then activates only the previewed hash.
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
            name = "cross-workspace chat switching waits for literal consent and cancellation retains its owner",
            --Verifies cross-workspace chat switching waits for literal consent and cancellation retains its owner.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify cross-workspace chat switching waits for literal consent and cancellation retains its owner.
            run = function()
                for _, answer in ipairs({ "no", ".cancel", "CONTINUE FEDCBA9876543210" }) do
                    local batches = {}
                    for _, text in ipairs({ ".context second-task", ".status", answer, ".quit" }) do
                        batches[#batches + 1] = { { kind = "user_action", action = "text", text = text } }
                        batches[#batches + 1] = { { kind = "user_action", action = "submit-or-queue" } }
                    end
                    local f = fixture({ initial_agent = true, initial_state = "Idle", freeze_driver = true,
                        cross_workspace = true, batches = batches })
                    assert(f.coordinator:run())
                    local output = A.render(f.blocks)
                    local log = table.concat(f.log, "|")
                    A.contains(output, "Context workspace: /other")
                    A.contains(output, "context change: FEDCBA9876543210")
                    if answer:sub(1, 8) == "CONTINUE" then
                        A.contains(log, "session-close:context-switch")
                        A.contains(log, "context-activate:FEDCBA9876543210")
                        A.contains(output, "workspace=/other")
                    else
                        A.falsy(log:find("context-activate:", 1, true))
                        A.falsy(log:find("session-close:context-switch", 1, true))
                        A.contains(output, "current session remains open")
                    end
                    A.falsy(log:find("agent:terminal:CONTINUE", 1, true))
                end
            end,
        },
        {
            name = "unsaved chat can switch without publishing an empty replacement Context",
            --Verifies unsaved chat can switch without publishing an empty replacement Context.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify unsaved chat can switch without publishing an empty replacement Context.
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
            --Verifies post-close Context activation race is fatal and restores the terminal.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify post-close Context activation race is fatal and restores the terminal.
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
            --Verifies busy Context switch rejects before previewing or closing the owner.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify busy Context switch rejects before previewing or closing the owner.
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
            --Verifies interactive diagnostics retain only the newest bounded error instances.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify interactive diagnostics retain only the newest bounded error instances.
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
            --Verifies approval view binds full snapshot and explicit allow once answer.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify approval view binds full snapshot and explicit allow once answer.
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
            --Verifies rejected busy lane preserves draft until explicit cancel clears it.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify rejected busy lane preserves draft until explicit cancel clears it.
            run = function()
                local f = fixture({
                    ask_error = {
                        code = "AskUnavailable",
                        message = "ask request transport is unavailable",
                    },
                    batches = {
                        { { kind = "user_action", action = "text", text = "first" } },
                        { { kind = "user_action", action = "submit-or-queue" } },
                        { { kind = "user_action", action = "text", text = "why" } },
                        { { kind = "user_action", action = "ask" } },
                        { { kind = "user_action", action = "cancel" } },
                        { { kind = "user_action", action = "text", text = ".quit" } },
                        { { kind = "user_action", action = "submit-or-queue" } },
                    },
                })
                assert(f.coordinator:run())
                A.contains(A.render(f.blocks), "ask request transport is unavailable")
                A.contains(A.render(f.blocks), "Input draft cleared")
                A.equal(#blocks_of_kind(f.blocks, "user"), 1)
                A.equal(f.coordinator:status().draft_bytes, 0)
            end,
        },
        {
            name = "accepted ask stream renders one separately identified advisory block",
            --Verifies accepted ask stream renders one separately identified advisory block.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify accepted ask stream renders one separately identified advisory block.
            run = function()
                local f = fixture({
                    ask_response = true,
                    batches = {
                        { { kind = "user_action", action = "text", text = "first" } },
                        { { kind = "user_action", action = "submit-or-queue" } },
                        {
                            {
                                kind = "user_action",
                                action = "text",
                                text = ".ask explain the durable facts",
                            },
                        },
                        { { kind = "user_action", action = "submit-or-queue" } },
                        { { kind = "user_action", action = "text", text = ".quit" } },
                        { { kind = "user_action", action = "submit-or-queue" } },
                    },
                })
                assert(f.coordinator:run())
                local sides = blocks_of_kind(f.blocks, "ask")
                A.equal(#sides, 1)
                A.equal(sides[1].id, "ask-1")
                A.equal(sides[1].text, "bounded advice")
                A.contains(A.render(f.blocks), "Ask ask-1 outcome: completed")
                A.contains(table.concat(f.log, "|"), "stage:terminal:explain the durable facts")
                A.contains(table.concat(f.log, "|"), "ask")
            end,
        },
        {
            name = "automatic compaction visibly pauses then resumes the pending Model request",
            --Verifies automatic compaction visibly pauses then resumes the pending Model request.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify automatic compaction visibly pauses then resumes the pending Model request.
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
            --Verifies manual compact is publicly routed and cancel owns its active lane.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify manual compact is publicly routed and cancel owns its active lane.
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
            name = "cancel follows active ask focus without cancelling the paused main",
            --Verifies cancel follows active ask focus without cancelling the paused main.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify cancel follows active ask focus without cancelling the paused main.
            run = function()
                local f = fixture({ batches = {
                    { { kind = "user_action", action = "text", text = "first" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                    {
                        {
                            kind = "user_action",
                            action = "text",
                            text = ".ask bounded question",
                        },
                    },
                    { { kind = "user_action", action = "submit-or-queue" } },
                    { { kind = "user_action", action = "text", text = ".cancel" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                    { { kind = "user_action", action = "text", text = ".quit" } },
                    { { kind = "user_action", action = "submit-or-queue" } },
                } })
                assert(f.coordinator:run())
                A.contains(table.concat(f.log, "|"), "ask-cancel:user-cancel")
                A.falsy(table.concat(f.log, "|"):find("loop-cancel", 1, true))
                A.contains(A.render(f.blocks), "Ask cancellation requested")
            end,
        },
    },
}
