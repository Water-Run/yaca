--[[
File: agent_activity_driver_test.lua
Date: 2026-08-30
Author: WaterRun
Description: Verifies Model, Tool, and review activity facts reduce through one AgentLoop driver.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()
local runtime = assert(loadfile(YACA_TEST_ROOT .. "/src/runtime.lua", "t", _ENV))()

local function result()
    return {
        kind = "real-success",
        body = "ok",
        truncated = false,
        raw_bytes = 2,
        digest = false,
        error_id = false,
        external_effects_unsettled = false,
        progress_identity = "workspace-2",
    }
end

local function fixture()
    local state = "RequestingModel"
    local log = {}
    local model_batches = { {
        { kind = "canonical-event", request_id = "request-1" },
        {
            kind = "adapter-event",
            request_id = "request-1",
            event = { kind = "text_delta", text = "working" },
        },
        {
            kind = "response",
            request_id = "request-1",
            wrapper = { request_id = "request-1" },
        },
    } }
    local review_batches = { {
        {
            kind = "verdict",
            request_id = "review-1",
            purpose = "termination-review",
            verdict = {
                verdict = "pass",
                review_id = "review-local",
                binding_digest = "binding-local",
                gap = "",
                reason = "verified",
            },
        },
    } }
    local now = 10
    local loop = {}

    function loop:status()
        return { state = state, last_outcome = state == "Idle" and "completed" or false }
    end

    function loop:tick()
        log[#log + 1] = "tick:" .. state
        return { state = state }
    end

    function loop:accept_model_event(request_id)
        log[#log + 1] = "model-event:" .. request_id
        state = "Streaming"
        return { state = state }
    end

    function loop:accept_model_response(wrapper)
        log[#log + 1] = "model-response:" .. wrapper.request_id
        state = "ExecutingTool"
        return { state = state }
    end

    function loop:accept_tool_result(value, receipt)
        log[#log + 1] = "tool-result:" .. value.kind .. ":" .. receipt.barrier_id
        state = "EvaluatingTermination"
        return { state = state }
    end

    function loop:resolve_action_review(verdict)
        log[#log + 1] = "action-review:" .. verdict.verdict
        state = "ExecutingTool"
        return { state = state }
    end

    function loop:resolve_termination_review(verdict)
        log[#log + 1] = "termination-review:" .. verdict.verdict
        state = "Idle"
        return { state = state, outcome = "completed" }
    end

    local model = {}
    function model.poll()
        return table.remove(model_batches, 1) or {}
    end

    local tools = {}
    function tools.poll(observed_now, budget)
        log[#log + 1] = "tool-poll:" .. tostring(observed_now) .. ":" .. tostring(budget)
        return { { kind = "io_progress", stream = "stdout", bytes = "ok" } }, {
            result = result(),
            result_receipt = { barrier_id = "operation-result-1" },
            outcome = "completed",
        }
    end

    local reviews = {}
    function reviews.poll()
        return table.remove(review_batches, 1) or {}
    end

    local driver = assert(runtime.new_agent_activity_driver({
        loop = loop,
        model = model,
        tools = tools,
        reviews = reviews,
        clock = { now = function() now = now + 1 return now end },
    }, {
        model_poll_events = 8,
        tool_poll_events = 4,
        review_poll_events = 4,
        maximum_output_events = 16,
    }))
    return {
        driver = driver,
        loop = loop,
        log = log,
        set_state = function(value) state = value end,
        model_batches = model_batches,
        review_batches = review_batches,
    }
end

return {
    name = "integration/agent-activity-driver",
    cases = {
        {
            name = "canonical Model Tool and termination review facts drive one ordered journey",
            run = function()
                local f = fixture()
                local first = assert(f.driver.step())
                A.equal(first.status.state, "ExecutingTool")
                A.equal(first.events[1].kind, "model-event")
                A.equal(first.events[1].event.text, "working")
                A.equal(first.events[2].cause, "model-response")

                local second = assert(f.driver.step())
                A.equal(second.status.state, "EvaluatingTermination")
                A.equal(second.events[1].kind, "tool-event")
                A.equal(second.events[2].cause, "tool-result")

                local third = assert(f.driver.step())
                A.equal(third.status.state, "Idle")
                A.equal(third.status.last_outcome, "completed")
                A.equal(third.events[1].cause, "termination-review")
                A.deep_equal(f.log, {
                    "tick:RequestingModel",
                    "model-event:request-1",
                    "model-response:request-1",
                    "tick:ExecutingTool",
                    "tool-poll:11:4",
                    "tool-result:real-success:operation-result-1",
                    "tick:EvaluatingTermination",
                    "termination-review:pass",
                })
            end,
        },
        {
            name = "action review uses its distinct resolver and resumes the Tool lane",
            run = function()
                local f = fixture()
                f.set_state("EvaluatingAction")
                f.review_batches[1][1].purpose = "action-review"
                f.review_batches[1][1].verdict = {
                    verdict = "tighten",
                    review_id = "review-action",
                    binding_digest = "binding-action",
                    reason = "confirm exact target",
                }
                local stepped = assert(f.driver.step())
                A.equal(stepped.status.state, "ExecutingTool")
                A.equal(stepped.events[1].cause, "action-review")
                A.contains(table.concat(f.log, "|"), "action-review:tighten")
            end,
        },
        {
            name = "waiting states do not poll an unrelated effect lane",
            run = function()
                local f = fixture()
                f.set_state("WaitingUser")
                local stepped = assert(f.driver.step())
                A.falsy(stepped.progressed)
                A.equal(#stepped.events, 0)
                A.equal(stepped.status.state, "WaitingUser")
            end,
        },
        {
            name = "unknown activity events and missing review ports fail closed",
            run = function()
                local f = fixture()
                f.model_batches[1] = { { kind = "invented", request_id = "request-1" } }
                local stepped, step_error = f.driver.step()
                A.falsy(stepped)
                A.equal(step_error.code, "ModelActivityContract")

                local unavailable = assert(runtime.new_agent_activity_driver({
                    loop = f.loop,
                    model = { poll = function() return {} end },
                    tools = { poll = function() return {}, false end },
                    reviews = false,
                    clock = { now = function() return 20 end },
                }, {
                    model_poll_events = 1,
                    tool_poll_events = 1,
                    review_poll_events = 1,
                    maximum_output_events = 2,
                }))
                f.set_state("EvaluatingTermination")
                stepped, step_error = unavailable.step()
                A.falsy(stepped)
                A.equal(step_error.code, "ReviewActivityUnavailable")
            end,
        },
    },
}
