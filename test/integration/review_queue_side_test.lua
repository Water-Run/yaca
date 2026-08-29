--[[
File: review_queue_side_test.lua
Date: 2026-08-29
Author: WaterRun
Description: Verifies C27 review isolation and the queue, steer, and side lanes.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()
local runtime = assert(loadfile(YACA_TEST_ROOT .. "/src/runtime.lua", "t", _ENV))()

local function load_module(name, cache)
    cache = cache or {}
    if cache[name] then return cache[name] end
    local environment = {}
    for key, value in pairs(_ENV) do environment[key] = value end
    environment.require = function(dependency) return load_module(dependency, cache) end
    environment._G = environment
    setmetatable(environment, { __index = _ENV })
    local chunk = assert(loadfile(
        YACA_TEST_ROOT .. "/src/" .. name .. ".lua",
        "t",
        environment
    ))
    local result = chunk()
    cache[name] = result
    return result
end

local sessions = load_module("session")

local function copy(values)
    local result = {}
    for key, value in pairs(values or {}) do result[key] = value end
    return result
end

local function options(queue_maximum)
    return {
        hard_caps = {
            active_time_ms = 1000,
            model_requests = 20,
            tool_calls = 20,
            reviews = 8,
            steps = 64,
            message_bytes = 4096,
            result_bytes = 4096,
        },
        stuck = {
            snapshot_id = "manifest-stuck-v1",
            exact_repeat = 10,
            same_error = 10,
            abab_cycle = 10,
            semantic_no_progress = 10,
            runtime_maximum = 20,
        },
        initial_sequence = 0,
        initial_context_generation = 1,
        maximum_identifier_bytes = 128,
        hard_cap_snapshot_id = "manifest-hard-v1",
        lanes = {
            queue_maximum = queue_maximum or 9,
            side_active_time_ms = 1000,
            side_response_bytes = 4096,
            side_snapshot_id = "manifest-side-v1",
        },
    }
end

local function turn_input(text_value, source, generation, double_check)
    return {
        text = text_value,
        source = source,
        config_generation = "config-generation-1",
        model_snapshot = "model-snapshot-1",
        permission_snapshot = "permission-snapshot-1",
        prompt_snapshot = "prompt-snapshot-1",
        tool_registry_snapshot = "tool-registry-snapshot-1",
        view_manifest_ref = "view-manifest-1",
        double_check = double_check == true,
        context_generation = generation,
    }
end

local function tool_result(kind, error_id)
    local body = kind
    return {
        kind = kind,
        body = body,
        truncated = false,
        raw_bytes = #body,
        digest = false,
        error_id = error_id or false,
        external_effects_unsettled = kind == "unknown",
        progress_identity = false,
    }
end

local function fixture(settings)
    settings = settings or {}
    local now = 0
    local generation = 1
    local events, log = {}, {}
    local model_starts, review_starts, side_starts, snapshots = {}, {}, {}, {}
    local tool_starts = {}

    local journal = {}
    function journal.commit(batch)
        local previous = generation
        for _, event in ipairs(batch.events) do
            events[#events + 1] = event
            log[#log + 1] = "durable:" .. event.type
        end
        generation = generation + 1
        return true, {
            barrier_id = batch.barrier_id,
            first_sequence = batch.first_sequence,
            last_sequence = batch.last_sequence,
            event_count = batch.event_count,
            binding = batch,
            previous_context_generation = previous,
            context_generation = generation,
        }
    end

    local model = {}
    function model.start(specification)
        model_starts[#model_starts + 1] = specification
        log[#log + 1] = "effect:model:" .. specification.request_id
        return "model:" .. specification.request_id
    end
    function model.cancel(handle)
        log[#log + 1] = "cancel:model:" .. handle
        return settings.model_cancel or { outcome = "cancelled" }
    end

    local tools = {}
    function tools.admit(call)
        if settings.review_actions then
            return {
                decision = "review",
                capabilities = "RawExec",
                permission_snapshot_digest = "permission-digest",
                reason = "review high-risk action",
                token = "token:" .. call.tool_call_id,
                after_review = "allow",
            }
        end
        return {
            decision = "allow",
            capabilities = "ReadOrdinary",
            permission_snapshot_digest = "permission-digest",
            reason = "",
            token = "token:" .. call.tool_call_id,
            after_review = false,
        }
    end
    function tools.start(specification)
        tool_starts[#tool_starts + 1] = specification
        log[#log + 1] = "effect:tool:" .. specification.call.tool_call_id
        if settings.async_tool and #tool_starts == 1 then
            return { kind = "async", handle = "tool:active" }
        end
        return { kind = "complete", result = tool_result("real-success") }
    end
    function tools.cancel(handle)
        log[#log + 1] = "cancel:tool:" .. handle
        return settings.tool_cancel or { outcome = "cancelled" }
    end

    local reviews = {}
    function reviews.start(specification)
        review_starts[#review_starts + 1] = specification
        log[#log + 1] = "effect:review:" .. specification.purpose
        return "review:" .. specification.request_id
    end
    function reviews.cancel(handle)
        log[#log + 1] = "cancel:review:" .. handle
        return { outcome = "cancelled" }
    end

    local snapshot_port = {}
    function snapshot_port.capture(specification)
        snapshots[#snapshots + 1] = specification
        log[#log + 1] = "snapshot:" .. specification.kind .. ":" .. specification.text
        return turn_input(
            specification.text,
            specification.source,
            specification.context_generation,
            settings.double_check
        )
    end

    local side_port = {}
    function side_port.start(specification)
        side_starts[#side_starts + 1] = specification
        log[#log + 1] = "effect:side:" .. specification.request_id
        return "side:" .. specification.request_id
    end
    function side_port.cancel(handle)
        log[#log + 1] = "cancel:side:" .. handle
        return settings.side_cancel or { outcome = "cancelled" }
    end

    local loop = assert(runtime.new_agent_loop({
        clock = { now = function() return now end },
        journal = journal,
        model = model,
        tools = tools,
        reviews = reviews,
        snapshots = snapshot_port,
        side = side_port,
    }, options(settings.queue_maximum)))
    return {
        loop = loop,
        events = events,
        log = log,
        model_starts = model_starts,
        review_starts = review_starts,
        side_starts = side_starts,
        tool_starts = tool_starts,
        snapshots = snapshots,
        advance = function(delta) now = now + delta end,
    }
end

local function observed(loop, values)
    local status = loop:status()
    local result = copy(values)
    result.expected_context_generation = status.context_generation
    result.expected_turn_id = status.turn_id
    return result
end

local function call(name, serial)
    return {
        local_tool_call_id = "adapter-call-" .. tostring(serial),
        name = name,
        canonical_arguments = "{}",
        provider_tool_call_id = "provider-call-" .. tostring(serial),
    }
end

local function response(request_id, settings)
    settings = settings or {}
    local calls = settings.calls or {}
    local normalized = {
        content_blocks = {},
        tool_calls = calls,
        finish_class = #calls > 0 and "tool_calls" or "stop",
        incomplete = settings.incomplete == true,
        tool_calls_validated = settings.incomplete ~= true,
        execution_admitted = false,
    }
    if settings.control then normalized.control = settings.control end
    if settings.incomplete_reason then normalized.incomplete_reason = settings.incomplete_reason end
    local body = settings.body or "canonical response"
    return {
        request_id = request_id,
        canonical_body = body,
        canonical_digest = settings.digest or ("digest-" .. body),
        progress_identity = settings.progress_identity or "workspace-v1",
        normalized = normalized,
    }
end

local function main_response(loop, settings)
    return response(loop:status().active_request_id, settings)
end

local function finish(loop, summary)
    return main_response(loop, {
        body = "finish:" .. (summary or "done"),
        control = { control = "finish", payload = { summary = summary or "done" } },
    })
end

local function event_fields(events, event_type)
    local result = {}
    for _, event in ipairs(events) do
        if event.type == event_type then result[#result + 1] = event.fields end
    end
    return result
end

return {
    name = "integration/review-queue-side",
    cases = {
        {
            name = "queue amendments are durable and completed alone auto-starts a fresh snapshot",
            run = function()
                local f = fixture()
                local first = assert(f.loop:submit_main(observed(f.loop, {
                    text = "first main", source = "user",
                })))
                local first_turn = first.turn_id
                local q1 = assert(f.loop:enqueue(observed(f.loop, {
                    text = "queued second", source = "user",
                })))
                local stale = observed(f.loop, {
                    queue_item_id = q1.queue_item_id,
                    text = "stale amendment",
                })
                local q2 = assert(f.loop:enqueue(observed(f.loop, {
                    text = "queued third", source = "user",
                })))
                local rejected, stale_error = f.loop:edit_queue(stale)
                A.falsy(rejected)
                A.equal(stale_error.code, "StaleLaneObservation")

                assert(f.loop:edit_queue(observed(f.loop, {
                    queue_item_id = q1.queue_item_id,
                    text = "queued second edited",
                })))
                assert(f.loop:reorder_queue(observed(f.loop, {
                    queue_item_id = q2.queue_item_id,
                    before_queue_item_id = q1.queue_item_id,
                })))
                local listed = f.loop:list_queue()
                A.equal(listed.items[1].queue_item_id, q2.queue_item_id)
                A.equal(listed.items[2].text, "queued second edited")
                assert(f.loop:drop_queue(observed(f.loop, {
                    queue_item_id = q1.queue_item_id,
                    reason = "not needed",
                })))

                local completed = assert(f.loop:accept_model_response(finish(f.loop)))
                A.equal(completed.outcome, "completed")
                A.equal(completed.auto_started_queue_item, q2.queue_item_id)
                A.equal(f.loop:status().state, "RequestingModel")
                A.falsy(f.loop:status().turn_id == first_turn)
                A.equal(f.snapshots[#f.snapshots].text, "queued third")
                A.equal(f.loop:list_queue().count, 0)

                local reset = assert(f.loop:enqueue(observed(f.loop, {
                    text = "after empty", source = "user",
                })))
                A.equal(reset.display_id, "#1")
                local actions = event_fields(f.events, "queue_item")
                A.deep_equal({
                    actions[1].action, actions[2].action, actions[3].action,
                    actions[4].action, actions[5].action, actions[6].action,
                }, { "enqueue", "enqueue", "edit", "move", "drop", "consume" })
            end,
        },
        {
            name = "queue-full and side-busy preserve the single session draft",
            run = function()
                local f = fixture({ queue_maximum = 1 })
                local session = assert(sessions.new_agent_session(f.loop, {
                    maximum_draft_bytes = 4096,
                }))
                assert(session:stage("main", "user"))
                assert(session:submit())
                assert(session:stage("queued one", "user"))
                assert(session:queue())
                assert(session:stage("queued two", "user"))
                local queued, queue_error = session:queue()
                A.falsy(queued)
                A.equal(queue_error.code, "QueueFull")
                A.equal(session:draft().text, "queued two")
                session:clear_draft()

                assert(session:stage("side one", "user"))
                local side = assert(session:side())
                assert(session:stage("side two", "user"))
                local started, side_error = session:side()
                A.falsy(started)
                A.equal(side_error.code, "SideBusy")
                A.equal(session:draft().text, "side two")
                A.equal(f.loop:status().active_side_id, side.side_id)
            end,
        },
        {
            name = "non-completed main outcomes pause queue until exact run-next",
            run = function()
                local f = fixture()
                assert(f.loop:submit_main(observed(f.loop, {
                    text = "main", source = "user",
                })))
                local queued = assert(f.loop:enqueue(observed(f.loop, {
                    text = "must pause", source = "user",
                })))
                local refused = assert(f.loop:accept_model_response(main_response(f.loop, {
                    body = "refused",
                    control = {
                        control = "refuse",
                        payload = { reason = "cannot complete" },
                    },
                })))
                A.equal(refused.outcome, "refused")
                A.equal(f.loop:status().state, "Idle")
                A.equal(f.loop:list_queue().count, 1)
                A.equal(#f.model_starts, 1)
                local started = assert(f.loop:run_next(observed(f.loop, {})))
                A.equal(started.queue_item_id, queued.queue_item_id)
                A.equal(f.loop:status().state, "RequestingModel")
                A.equal(#f.model_starts, 2)
            end,
        },
        {
            name = "action and termination reviewers use isolated no-tool purposes on the frozen model",
            run = function()
                local f = fixture({ double_check = true, review_actions = true })
                assert(f.loop:submit_main(observed(f.loop, {
                    text = "reviewed task", source = "user",
                })))
                assert(f.loop:accept_model_response(main_response(f.loop, {
                    body = "high-risk call",
                    calls = { call("exec", 1) },
                })))
                A.equal(#f.review_starts, 1)
                A.equal(f.review_starts[1].purpose, "action-review")
                A.truthy(f.review_starts[1].no_tools)
                A.equal(f.review_starts[1].model_snapshot, "model-snapshot-1")
                assert(f.loop:resolve_action_review({
                    verdict = "pass",
                    review_id = "action-review-1",
                    binding_digest = "action-binding-1",
                    reason = "bounded",
                }))
                assert(f.loop:accept_model_response(finish(f.loop, "verified")))
                A.equal(#f.review_starts, 2)
                A.equal(f.review_starts[2].purpose, "termination-review")
                A.truthy(f.review_starts[2].no_tools)
                A.equal(f.review_starts[2].model_snapshot, "model-snapshot-1")
                A.falsy(f.review_starts[1].request_id == f.review_starts[2].request_id)
                assert(f.loop:resolve_termination_review({
                    verdict = "pass",
                    review_id = "termination-review-1",
                    binding_digest = "termination-binding-1",
                    gap = "",
                    reason = "complete",
                }))
                A.equal(f.loop:status().last_outcome, "completed")
            end,
        },
        {
            name = "steer waits for the active tool and skips every accepted unstarted call",
            run = function()
                local f = fixture({
                    async_tool = true,
                    tool_cancel = { outcome = "pending" },
                })
                assert(f.loop:submit_main(observed(f.loop, {
                    text = "tool task", source = "user",
                })))
                assert(f.loop:accept_model_response(main_response(f.loop, {
                    body = "two calls",
                    calls = { call("read", 1), call("search", 2) },
                })))
                local turn_id = f.loop:status().turn_id
                local steered = assert(f.loop:steer(observed(f.loop, {
                    text = "change direction", source = "user",
                })))
                A.truthy(steered.activity_pending)
                A.equal(f.loop:status().turn_id, turn_id)
                A.equal(#f.tool_starts, 1)
                assert(f.loop:accept_tool_result(tool_result("real-cancelled", "ToolSteered")))
                A.equal(f.loop:status().state, "RequestingModel")
                A.equal(f.loop:status().turn_id, turn_id)
                A.equal(#f.model_starts, 2)
                local results = event_fields(f.events, "tool_result")
                A.equal(results[1].status, "cancelled")
                A.equal(results[2].status, "skipped")
                A.contains(results[2].body, "skipped-by-steer")
                local steers = event_fields(f.events, "steer")
                A.equal(steers[1].targetTurnId, turn_id)
                A.equal(steers[1].summary, "change direction")
            end,
        },
        {
            name = "side is one bounded no-tool turn and enters main only through explicit side-use",
            run = function()
                local f = fixture()
                assert(f.loop:submit_main(observed(f.loop, {
                    text = "main work", source = "user",
                })))
                local main_turn = f.loop:status().turn_id
                local main_request = f.loop:status().active_request_id
                local side = assert(f.loop:start_side(observed(f.loop, {
                    text = "explain a detail", source = "user",
                })))
                A.equal(f.loop:status().turn_id, main_turn)
                A.equal(f.loop:status().active_request_id, main_request)
                A.equal(f.side_starts[1].purpose, "side")
                A.truthy(f.side_starts[1].no_tools)
                local side_result = assert(f.loop:accept_side_response(side.side_id, response(
                    side.request_id,
                    { body = "side answer", digest = "side-answer-digest" }
                )))
                A.equal(side_result.outcome, "completed")
                A.equal(f.loop:status().side_state, "idle")
                A.equal(f.loop:list_queue().count, 0)

                local used = assert(f.loop:use_side(observed(f.loop, {
                    side_id = side.side_id,
                    lane = "queue",
                })))
                A.equal(f.loop:list_queue().count, 1)
                local queues = event_fields(f.events, "queue_item")
                A.equal(queues[#queues].sideId, side.side_id)
                A.equal(used.queue_item_id, f.loop:list_queue().items[1].queue_item_id)

                assert(f.loop:accept_model_response(finish(f.loop, "main complete")))
                A.equal(f.loop:status().state, "RequestingModel")
                A.falsy(f.loop:status().turn_id == main_turn)
                A.equal(f.snapshots[#f.snapshots].text, "side answer")
            end,
        },
        {
            name = "side active-time and pending cancellation settle without consuming a paused main",
            run = function()
                local capped = fixture()
                assert(capped.loop:submit_main(observed(capped.loop, {
                    text = "main", source = "user",
                })))
                assert(capped.loop:accept_model_response(main_response(capped.loop, {
                    body = "need input",
                    control = {
                        control = "ask-user",
                        payload = { question = "Wait?" },
                    },
                })))
                local main_turn = capped.loop:status().turn_id
                local side = assert(capped.loop:start_side(observed(capped.loop, {
                    text = "bounded side", source = "user",
                })))
                capped.advance(1000)
                assert(capped.loop:tick())
                A.equal(capped.loop:status().side_state, "idle")
                A.equal(capped.loop:status().turn_id, main_turn)
                A.equal(capped.loop:status().state, "WaitingUser")
                A.equal(assert(capped.loop:side_result(side.side_id)).outcome, "cancelled")

                local pending = fixture({ side_cancel = { outcome = "pending" } })
                assert(pending.loop:submit_main(observed(pending.loop, {
                    text = "main", source = "user",
                })))
                local pending_side = assert(pending.loop:start_side(observed(pending.loop, {
                    text = "cancel me", source = "user",
                })))
                assert(pending.loop:cancel_side(observed(pending.loop, {
                    side_id = pending_side.side_id,
                    reason = "user-cancel",
                })))
                A.equal(pending.loop:status().side_state, "cancelling")
                local settled = assert(pending.loop:settle_side_cancel({
                    side_id = pending_side.side_id,
                    request_id = pending_side.request_id,
                    outcome = "cancelled",
                }))
                A.equal(settled.outcome, "cancelled")
                A.equal(pending.loop:status().side_state, "idle")
            end,
        },
        {
            name = "ask-user stays same-turn while yield continue and ordinary input create causal new turns",
            run = function()
                local f = fixture()
                local session = assert(sessions.new_agent_session(f.loop, {
                    maximum_draft_bytes = 4096,
                }))
                assert(session:stage("initial task", "user"))
                assert(session:submit())
                local first_turn = f.loop:status().turn_id
                assert(f.loop:accept_model_response(main_response(f.loop, {
                    body = "ask target",
                    control = {
                        control = "ask-user",
                        payload = { question = "Which target?" },
                    },
                })))
                assert(session:stage("Linux", "user"))
                assert(session:submit())
                A.equal(f.loop:status().turn_id, first_turn)

                assert(f.loop:accept_model_response(main_response(f.loop, {
                    body = "a complete ordinary answer",
                    digest = "yield-one",
                })))
                local response_id = f.loop:status().pending_response_id
                A.truthy(response_id)
                assert(session:stage("new independent request", "user"))
                local superseded = assert(session:submit())
                A.equal(superseded.action, "supersede")
                A.falsy(superseded.turn_id == first_turn)
                local starts = event_fields(f.events, "turn_started")
                A.equal(starts[#starts].supersedesResponseId, response_id)

                local continued = fixture()
                local continued_session = assert(sessions.new_agent_session(continued.loop, {
                    maximum_draft_bytes = 4096,
                }))
                assert(continued_session:stage("task", "user"))
                assert(continued_session:submit())
                assert(continued.loop:accept_model_response(main_response(continued.loop, {
                    body = "first response",
                    digest = "yield-two",
                })))
                local continued_response_id = continued.loop:status().pending_response_id
                assert(continued_session:stage("continue with more detail", "user"))
                local resolution = assert(
                    continued_session:continue_response(continued_response_id)
                )
                A.equal(resolution.action, "continue")
                local continued_starts = event_fields(continued.events, "turn_started")
                A.equal(
                    continued_starts[#continued_starts].continuesResponseId,
                    continued_response_id
                )
            end,
        },
    },
}
