--[[
Author: WaterRun
Date: 2026-09-23
File: agent_activity_driver_test.lua
Description: Verifies Model, Tool, and review activity facts reduce through one AgentLoop driver.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()
local runtime = assert(loadfile(YACA_TEST_ROOT .. "/src/runtime.lua", "t", _ENV))()

--Supplies result behavior required by this suite.
--@param none No arguments; this closure uses its captured fixture state.
--@return table observed Structured fixture record selected by the exercised branch.
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

--Constructs the suite's isolated runtime fixture and observation ports.
--@param none No arguments; this closure uses its captured fixture state.
--@return table fixture Constructed fixture service used by this suite.
local function fixture()
    local state = "RequestingModel"
    local ask_state = "idle"
    local active_ask_id = false
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
    local ask_batches = {}
    local now = 10
    local loop = {}

    --Simulates the status transition of a fake activity port for this suite.
    --@param self table Fixture or port instance receiving this call.
    --@return table observed Structured fixture record selected by the exercised branch.
    function loop:status()
        return {
            state = state,
            last_outcome = state == "Idle" and "completed" or false,
            ask_state = ask_state,
            active_ask_id = active_ask_id,
            active_tool_call_id = state == "ExecutingTool" and "turn-1:tool:1" or false,
            active_tool_adapter_call_id = state == "ExecutingTool" and "request-1:tool:1" or false,
        }
    end

    --Supplies tick behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@return table observed Structured fixture record with state.
    function loop:tick()
        log[#log + 1] = "tick:" .. state
        return { state = state }
    end

    --Supplies accept model event behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param request_id string|integer Request identity being completed.
    --@return table observed Structured fixture record with state.
    function loop:accept_model_event(request_id)
        log[#log + 1] = "model-event:" .. request_id
        state = "Streaming"
        return { state = state }
    end

    --Supplies accept model response behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param wrapper any The wrapper supplied to the fake service for this scenario.
    --@return table observed Structured fixture record with state.
    function loop:accept_model_response(wrapper)
        log[#log + 1] = "model-response:" .. wrapper.request_id
        state = "ExecutingTool"
        return { state = state }
    end

    --Supplies accept tool result behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param value any Candidate whose acceptance or transformation the test checks.
    --@param receipt table Publication receipt inspected by the assertion.
    --@return table observed Structured fixture record with state.
    function loop:accept_tool_result(value, receipt)
        log[#log + 1] = "tool-result:" .. value.kind .. ":" .. receipt.barrier_id
        state = "EvaluatingTermination"
        return { state = state }
    end

    --Supplies resolve action review behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param verdict any The verdict supplied to the fake service for this scenario.
    --@return table observed Structured fixture record with state.
    function loop:resolve_action_review(verdict)
        log[#log + 1] = "action-review:" .. verdict.verdict
        state = "ExecutingTool"
        return { state = state }
    end

    --Supplies resolve termination review behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param verdict any The verdict supplied to the fake service for this scenario.
    --@return table observed Outcome record with status completed.
    function loop:resolve_termination_review(verdict)
        log[#log + 1] = "termination-review:" .. verdict.verdict
        state = "Idle"
        return { state = state, outcome = "completed" }
    end

    --Supplies accept ask event behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param ask_id string|integer Ask activity identity being completed.
    --@param request_id string|integer Request identity being completed.
    --@return table observed Structured fixture record with ask_id, canonical_event_seen.
    function loop:accept_ask_event(ask_id, request_id)
        log[#log + 1] = "ask-event:" .. ask_id .. ":" .. request_id
        return { ask_id = ask_id, canonical_event_seen = true }
    end

    --Supplies accept ask response behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param ask_id string|integer Ask activity identity being completed.
    --@param wrapper any The wrapper supplied to the fake service for this scenario.
    --@return table observed Outcome record with status completed.
    function loop:accept_ask_response(ask_id, wrapper)
        log[#log + 1] = "ask-response:" .. ask_id .. ":" .. wrapper.request_id
        ask_state = "idle"
        active_ask_id = false
        return { ask_id = ask_id, outcome = "completed" }
    end

    local model = {}
    --Simulates the poll transition of a fake activity port for this suite.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return any observed poll value observed by the scenario assertion.
    function model.poll()
        return table.remove(model_batches, 1) or {}
    end

    local tools = {}
    --Simulates the poll transition of a fake activity port for this suite.
    --@param observed_now any The observed now supplied to the fake service for this scenario.
    --@param budget integer|table Resource budget applied by the scenario.
    --@return table observed Structured fixture record with kind, stream, bytes.
    --@return table secondary2 Outcome record with status completed.
    function tools.poll(observed_now, budget)
        log[#log + 1] = "tool-poll:" .. tostring(observed_now) .. ":" .. tostring(budget)
        return { { kind = "io_progress", stream = "stdout", bytes = "ok" } }, {
            result = result(),
            result_receipt = { barrier_id = "operation-result-1" },
            outcome = "completed",
        }
    end

    local reviews = {}
    --Simulates the poll transition of a fake activity port for this suite.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return any observed poll value observed by the scenario assertion.
    function reviews.poll()
        return table.remove(review_batches, 1) or {}
    end

    local ask = {}
    --Simulates the poll transition of a fake activity port for this suite.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return any observed poll value observed by the scenario assertion.
    function ask.poll()
        return table.remove(ask_batches, 1) or {}
    end

    local driver = assert(runtime.new_agent_activity_driver({
        loop = loop,
        model = model,
        tools = tools,
        reviews = reviews,
        ask = ask,
        clock = {
            --Supplies deterministic clock behavior for this suite.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return any value Callback value consumed by the enclosing scenario assertion.
            now = function() now = now + 1 return now end },
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
        --Supplies set state behavior required by this suite.
        --@param value any Candidate whose acceptance or transformation the test checks.
        --@return nil No value; the fake port or test assertion observes this callback's effects.
        set_state = function(value) state = value end,
        model_batches = model_batches,
        review_batches = review_batches,
        ask_batches = ask_batches,
        --Supplies start ask behavior required by this suite.
        --@param ask_id string|integer Ask activity identity being completed.
        --@return nil No value; the fake port or test assertion observes this callback's effects.
        start_ask = function(ask_id)
            ask_state = "active"
            active_ask_id = ask_id
        end,
    }
end

return {
    name = "integration/agent-activity-driver",
    cases = {
        {
            name = "canonical Model Tool and termination review facts drive one ordered journey",
            --Verifies canonical Model Tool and termination review facts drive one ordered journey.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify canonical Model Tool and termination review facts drive one ordered journey.
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
                A.equal(second.events[1].tool_call_id, "turn-1:tool:1")
                A.equal(second.events[1].adapter_call_id, "request-1:tool:1")
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
            --Verifies action review uses its distinct resolver and resumes the Tool lane.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify action review uses its distinct resolver and resumes the Tool lane.
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
            --Verifies action review uses its distinct resolver and resumes the Tool lane.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify action review uses its distinct resolver and resumes the Tool lane.
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
            name = "active ask Model is reduced independently while main keeps progressing",
            --Verifies waiting states do not poll an unrelated effect lane.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify waiting states do not poll an unrelated effect lane.
            run = function()
                local f = fixture()
                f.start_ask("ask-1")
                f.ask_batches[1] = {
                    { kind = "canonical-event", request_id = "ask-request-1" },
                    {
                        kind = "adapter-event",
                        request_id = "ask-request-1",
                        event = { kind = "text_delta", text = "ask answer" },
                    },
                    {
                        kind = "response",
                        request_id = "ask-request-1",
                        wrapper = { request_id = "ask-request-1" },
                    },
                }
                local stepped = assert(f.driver.step())
                A.equal(stepped.status.state, "ExecutingTool")
                A.equal(stepped.status.ask_state, "idle")
                A.equal(stepped.events[1].kind, "model-event")
                A.equal(stepped.events[2].cause, "model-response")
                A.equal(stepped.events[3].kind, "ask-model-event")
                A.equal(stepped.events[3].ask_id, "ask-1")
                A.equal(stepped.events[3].event.text, "ask answer")
                A.equal(stepped.events[4].cause, "ask-response")
                A.equal(stepped.events[4].result.outcome, "completed")
                A.contains(
                    table.concat(f.log, "|"),
                    "ask-event:ask-1:ask-request-1"
                )
                A.contains(
                    table.concat(f.log, "|"),
                    "ask-response:ask-1:ask-request-1"
                )
            end,
        },
        {
            name = "unknown activity events and missing review ports fail closed",
            --Verifies unknown activity events and missing review ports fail closed.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify unknown activity events and missing review ports fail closed.
            run = function()
                local f = fixture()
                f.model_batches[1] = { { kind = "invented", request_id = "request-1" } }
                local stepped, step_error = f.driver.step()
                A.falsy(stepped)
                A.equal(step_error.code, "ModelActivityContract")

                local unavailable = assert(runtime.new_agent_activity_driver({
                    loop = f.loop,
                    model = {
                        --Simulates the poll transition of a fake activity port for the 'unknown activity events and missing review ports fail closed' case.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return table record Fixture record emitted by the scenario callback.
                        poll = function() return {} end },
                    tools = {
                        --Simulates the poll transition of a fake activity port for the 'unknown activity events and missing review ports fail closed' case.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return table record Fixture record emitted by the scenario callback.
                        --@return boolean secondary2 Explicit false rejection from the fake port.
                        poll = function() return {}, false end },
                    reviews = false,
                    ask = false,
                    clock = {
                        --Supplies deterministic clock behavior for the 'unknown activity events and missing review ports fail closed' case.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return integer value Callback value consumed by the enclosing scenario assertion.
                        now = function() return 20 end },
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
