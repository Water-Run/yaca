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
        active_tool_call_id = false,
        pending_kind = false,
        pending_tool_call_id = false,
        pending_operation_id = false,
        pending_review_verdict = false,
        pending_question = false,
        context_generation = 1,
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
    local loop_status = status("RequestingModel")
    local driver_steps = 0
    local side_started = false
    local side_emitted = false
    local compaction_active = false

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
            model = "Primary",
            permission = "Std",
            double_check = true,
            display_name = "first-task",
            context_hash = "0123456789ABCDEF",
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

    local driver = {}
    function driver.step()
        driver_steps = driver_steps + 1
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
        if settings.compaction_active then
            compaction_active = true
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
        tools = tools,
        compaction = compaction,
        draft = draft,
    }
    local agent_factory = function(message, source)
        log[#log + 1] = "agent:" .. source .. ":" .. message
        return constructed_agent
    end

    local chat_draft = {}
    function chat_draft.status()
        return {
            lifecycle = "not-saved",
            workspace = "/workspace",
            model = "Primary",
            permission = "Std",
            double_check = true,
        }
    end
    function chat_draft:close()
        log[#log + 1] = "chat-draft-close"
        return true
    end
    local chat = {
        kind = "run-chat",
        outcome = "ready",
        status = chat_draft.status(),
        draft = chat_draft,
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
        agent_factory = agent_factory,
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
