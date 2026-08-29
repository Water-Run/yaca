--[=[
File: agentloop_test.lua
Date: 2026-08-29
Author: WaterRun
Description: Verifies typed AgentLoop traces, durable ordering, caps, and fail-stop.
]=]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()
local runtime = assert(loadfile(YACA_TEST_ROOT .. "/src/runtime.lua", "t", _ENV))()
local golden = assert(loadfile(
    YACA_TEST_ROOT .. "/test/golden/agentloop/manifest.lua",
    "t",
    _ENV
))()

local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = clone(item) end
    return result
end

local function options(overrides)
    overrides = overrides or {}
    local result = {
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
        maximum_identifier_bytes = 128,
        hard_cap_snapshot_id = "manifest-hard-caps-v1",
    }
    for key, value in pairs(overrides.hard_caps or {}) do result.hard_caps[key] = value end
    for key, value in pairs(overrides.stuck or {}) do result.stuck[key] = value end
    if overrides.initial_sequence ~= nil then result.initial_sequence = overrides.initial_sequence end
    return result
end

local function tool_result(kind, settings)
    settings = settings or {}
    local body = settings.body or kind
    return {
        kind = kind,
        body = body,
        truncated = false,
        raw_bytes = #body,
        digest = settings.digest or false,
        error_id = settings.error_id or false,
        external_effects_unsettled = settings.external_effects_unsettled == true,
        progress_identity = settings.progress_identity or false,
    }
end

local function fixture(settings, option_overrides)
    settings = settings or {}
    local now = 0
    local log, durable_events, batches = {}, {}, {}
    local model_starts, tool_starts, review_starts = {}, {}, {}
    local start_cursor = 1
    local journal = {}

    function journal.commit(batch)
        batches[#batches + 1] = batch
        for _, event in ipairs(batch.events) do
            log[#log + 1] = "durable:" .. event.type
            if settings.fail_event == event.type then
                return false, { code = "DiskFull", event = event.type }
            end
        end
        if settings.bad_binding_at == #batches then
            return true, {
                barrier_id = batch.barrier_id,
                first_sequence = batch.first_sequence,
                last_sequence = batch.last_sequence,
                event_count = batch.event_count,
                binding = {},
            }
        end
        for _, event in ipairs(batch.events) do durable_events[#durable_events + 1] = event end
        return true, {
            barrier_id = batch.barrier_id,
            first_sequence = batch.first_sequence,
            last_sequence = batch.last_sequence,
            event_count = batch.event_count,
            binding = batch,
        }
    end

    local model = {}
    function model.start(spec)
        log[#log + 1] = "effect:model:" .. spec.request_id
        model_starts[#model_starts + 1] = spec
        if settings.model_start_failure then return nil, { code = "NoModel" } end
        return "model-handle:" .. spec.request_id
    end
    function model.cancel(handle, reason)
        log[#log + 1] = "cancel:model:" .. handle
        return { outcome = settings.model_cancel_outcome or "cancelled" }
    end

    local tools = {}
    function tools.admit(call)
        log[#log + 1] = "admit:" .. call.tool_call_id
        local admission = settings.admit and settings.admit(call) or nil
        admission = admission or {
            decision = "allow",
            capabilities = "ReadOrdinary",
            permission_snapshot_digest = "permission-digest",
            reason = "",
            token = "token:" .. call.tool_call_id,
            after_review = false,
        }
        return admission
    end
    function tools.start(spec)
        log[#log + 1] = "effect:tool:" .. spec.call.tool_call_id
        tool_starts[#tool_starts + 1] = spec
        local candidate = settings.tool_starts and settings.tool_starts[start_cursor] or nil
        start_cursor = start_cursor + 1
        if candidate then return candidate end
        return { kind = "complete", result = tool_result("real-success") }
    end
    function tools.cancel(handle, reason)
        log[#log + 1] = "cancel:tool:" .. tostring(handle)
        if settings.tool_cancel_result then return settings.tool_cancel_result end
        return { outcome = "cancelled" }
    end

    local reviews = {}
    function reviews.start(spec)
        log[#log + 1] = "effect:review:" .. spec.request_id
        review_starts[#review_starts + 1] = spec
        return "review-handle:" .. spec.request_id
    end
    function reviews.cancel(handle, reason)
        log[#log + 1] = "cancel:review:" .. handle
        return { outcome = "cancelled" }
    end

    local review_port = reviews
    if settings.reviews_false then review_port = false end
    local loop, loop_error = runtime.new_agent_loop({
        clock = { now = function() return now end },
        journal = journal,
        model = model,
        tools = tools,
        reviews = review_port,
    }, options(option_overrides))
    A.truthy(loop, loop_error and loop_error.code)
    return {
        loop = loop,
        log = log,
        events = durable_events,
        batches = batches,
        model_starts = model_starts,
        tool_starts = tool_starts,
        review_starts = review_starts,
        advance = function(delta) now = now + delta end,
    }
end

local function input(double_check)
    return {
        text = "Implement the task",
        source = "user",
        config_generation = "config-1",
        model_snapshot = "model-snapshot",
        permission_snapshot = "permission-snapshot",
        prompt_snapshot = "prompt-snapshot",
        tool_registry_snapshot = "tool-registry-snapshot",
        view_manifest_ref = "view-manifest",
        double_check = double_check == true,
    }
end

local function call(name, serial, arguments)
    return {
        local_tool_call_id = "adapter-call-" .. tostring(serial),
        name = name,
        canonical_arguments = arguments or "{}",
        provider_tool_call_id = "provider-call-" .. tostring(serial),
    }
end

local function response(loop, settings)
    settings = settings or {}
    local calls = settings.calls or {}
    local digest = settings.digest or ("digest-" .. tostring(#calls) .. "-" .. tostring(settings.tag or "x"))
    local normalized = {
        content_blocks = {},
        tool_calls = calls,
        finish_class = #calls > 0 and "tool_calls" or (settings.finish_class or "stop"),
        incomplete = settings.incomplete == true,
        tool_calls_validated = settings.incomplete ~= true,
        execution_admitted = false,
    }
    if settings.control then normalized.control = settings.control end
    if settings.incomplete_reason then normalized.incomplete_reason = settings.incomplete_reason end
    return {
        request_id = loop:status().active_request_id,
        canonical_body = settings.body or ("canonical:" .. digest),
        canonical_digest = digest,
        progress_identity = settings.progress_identity or "workspace-v1",
        normalized = normalized,
    }
end

local function finish(loop, summary, settings)
    settings = settings or {}
    settings.control = { control = "finish", payload = { summary = summary or "done" } }
    settings.tag = settings.tag or "finish"
    return response(loop, settings)
end

local function ask_user(loop, question)
    return response(loop, {
        tag = "ask",
        control = { control = "ask-user", payload = { question = question } },
    })
end

local function refuse(loop, reason)
    return response(loop, {
        tag = "refuse",
        control = { control = "refuse", payload = { reason = reason } },
    })
end

local function trace(loop)
    return clone(loop:status().trace)
end

local function assert_golden(loop, id)
    local expected = golden.traces[id]
    local actual = trace(loop)
    A.deep_equal(actual.states, expected.states, id .. " states")
    A.deep_equal(actual.purposes, expected.purposes, id .. " purposes")
    A.deep_equal(actual.controls, expected.controls, id .. " controls")
    if expected.tool_result_kinds then
        local kinds = {}
        for index, item in ipairs(actual.tool_results) do kinds[index] = item.kind end
        A.deep_equal(kinds, expected.tool_result_kinds, id .. " tool results")
    end
    if expected.outcome then A.equal(actual.outcome, expected.outcome, id .. " outcome") end
    if expected.reported_outcome then
        A.equal(loop:status().reported_outcome, expected.reported_outcome)
    end
end

local function review_verdict(kind, serial)
    return {
        verdict = kind,
        review_id = "review-" .. tostring(serial),
        binding_digest = "review-binding-" .. tostring(serial),
        gap = kind == "gap" and "run the missing verification" or "",
        reason = kind == "pass" and "verified" or "review result",
    }
end

local function index_of(log, prefix, occurrence)
    occurrence = occurrence or 1
    local seen = 0
    for index, value in ipairs(log) do
        if value:sub(1, #prefix) == prefix then
            seen = seen + 1
            if seen == occurrence then return index end
        end
    end
    return nil
end

return {
    name = "fault/agentloop",
    cases = {
        {
            name = "typed finish is the only no-review completion path",
            run = function()
                local f = fixture()
                assert(f.loop:begin_main(input(false)))
                assert(f.loop:accept_model_response(finish(f.loop)))
                assert_golden(f.loop, "finish-no-doublecheck")
                A.equal(f.loop:status().last_outcome, "completed")
                A.truthy(f.loop:status().outcome_durable)
                A.truthy(f.loop:status().reportable)

                local yielded = fixture()
                assert(yielded.loop:begin_main(input(false)))
                assert(yielded.loop:accept_model_response(response(yielded.loop, {
                    body = "I am done, task completed.",
                    digest = "natural-language-done",
                })))
                assert_golden(yielded.loop, "model-yield-waits")
                A.equal(yielded.loop:status().last_outcome, false)
                local resumed, resume_error = yielded.loop:reply("continue", "user")
                A.falsy(resumed)
                A.equal(resume_error.code, "ExplicitContinuationRequired")
            end,
        },
        {
            name = "finish review pass and explicit gap preserve typed same-turn causality",
            run = function()
                local passed = fixture()
                assert(passed.loop:begin_main(input(true)))
                assert(passed.loop:accept_model_response(finish(passed.loop)))
                A.equal(passed.loop:status().state, "EvaluatingTermination")
                assert(passed.loop:resolve_termination_review(review_verdict("pass", 1)))
                assert_golden(passed.loop, "finish-doublecheck-pass")
                A.equal(#passed.review_starts, 1)

                local gap = fixture()
                assert(gap.loop:begin_main(input(true)))
                assert(gap.loop:accept_model_response(finish(gap.loop, "first finish")))
                local turn_id = gap.loop:status().turn_id
                assert(gap.loop:resolve_termination_review(review_verdict("gap", 2)))
                A.equal(gap.loop:status().turn_id, turn_id)
                assert(gap.loop:accept_model_response(finish(gap.loop, "gap fixed", {
                    tag = "finish-after-gap",
                    progress_identity = "workspace-v2",
                })))
                assert_golden(gap.loop, "finish-doublecheck-gap-same-turn")
                A.equal(#gap.review_starts, 1)
            end,
        },
        {
            name = "ask-user reply is durable in the same turn and refuse is exact",
            run = function()
                local asked = fixture()
                assert(asked.loop:begin_main(input(false)))
                assert(asked.loop:accept_model_response(ask_user(asked.loop, "Which target?")))
                A.equal(asked.loop:status().reported_outcome, "waiting_user")
                local turn_id = asked.loop:status().turn_id
                assert(asked.loop:reply("Linux", "user"))
                A.equal(asked.loop:status().turn_id, turn_id)
                assert(asked.loop:accept_model_response(finish(asked.loop)))
                assert_golden(asked.loop, "ask-user-then-reply")

                local refused = fixture()
                assert(refused.loop:begin_main(input(false)))
                assert(refused.loop:accept_model_response(refuse(refused.loop, "unsafe request")))
                assert_golden(refused.loop, "typed-refuse")
            end,
        },
        {
            name = "permission denial and approval rejection produce one durable synthetic result",
            run = function()
                local denied = fixture({
                    admit = function(call_value)
                        return {
                            decision = "deny",
                            capabilities = "WriteWorkspace",
                            permission_snapshot_digest = "permission-digest",
                            reason = "policy denied",
                            token = false,
                            after_review = false,
                        }
                    end,
                })
                assert(denied.loop:begin_main(input(false)))
                assert(denied.loop:accept_model_response(response(denied.loop, {
                    tag = "denied",
                    calls = { call("write", 1) },
                })))
                A.equal(#denied.tool_starts, 0)
                assert(denied.loop:accept_model_response(finish(denied.loop)))
                assert_golden(denied.loop, "permission-deny")

                local rejected = fixture({
                    admit = function()
                        return {
                            decision = "confirm",
                            capabilities = "RawExec",
                            permission_snapshot_digest = "permission-digest",
                            reason = "confirm shell",
                            token = "approval-token",
                            after_review = false,
                        }
                    end,
                })
                assert(rejected.loop:begin_main(input(false)))
                assert(rejected.loop:accept_model_response(response(rejected.loop, {
                    tag = "approval",
                    calls = { call("exec", 1) },
                })))
                assert(rejected.loop:resolve_approval({
                    decision = "reject",
                    approval_id = "approval-1",
                    snapshot_digest = "approval-snapshot",
                    approval_digest = "",
                }))
                assert(rejected.loop:accept_model_response(response(rejected.loop, {
                    tag = "yield-after-reject",
                })))
                assert_golden(rejected.loop, "approval-reject")
            end,
        },
        {
            name = "tools execute serially and first failure stably skips every unstarted call",
            run = function()
                local f = fixture({
                    tool_starts = {
                        {
                            kind = "complete",
                            result = tool_result("real-failed", {
                                error_id = "ReadFailed",
                                digest = "failed-result",
                            }),
                        },
                    },
                })
                assert(f.loop:begin_main(input(false)))
                assert(f.loop:accept_model_response(response(f.loop, {
                    tag = "three-tools",
                    calls = {
                        call("read", 1), call("search", 2), call("list", 3),
                    },
                })))
                A.equal(#f.tool_starts, 1)
                local actual = trace(f.loop)
                A.deep_equal({
                    actual.tool_results[1].kind,
                    actual.tool_results[2].kind,
                    actual.tool_results[3].kind,
                }, {
                    "real-failed", "skipped-after-failure", "skipped-after-failure",
                })
                A.equal(f.loop:status().state, "RequestingModel")
                assert(f.loop:accept_model_response(finish(f.loop)))
                A.equal(f.loop:status().last_outcome, "completed")

                local permission_at = index_of(f.log, "durable:permission_decision")
                local tool_at = index_of(f.log, "effect:tool:")
                local result_at = index_of(f.log, "durable:tool_result")
                local second_model_at = index_of(f.log, "effect:model:", 2)
                A.truthy(permission_at < tool_at)
                A.truthy(tool_at < result_at)
                A.truthy(result_at < second_model_at)
            end,
        },
        {
            name = "stream cancel and unknown side effect retain their real typed outcomes",
            run = function()
                local cancelled = fixture()
                assert(cancelled.loop:begin_main(input(false)))
                local request_id = cancelled.loop:status().active_request_id
                assert(cancelled.loop:accept_model_event(request_id))
                assert(cancelled.loop:cancel("user escape"))
                assert_golden(cancelled.loop, "cancel-streaming")
                A.truthy(index_of(cancelled.log, "durable:cancel")
                    < index_of(cancelled.log, "cancel:model:"))

                local unknown = fixture({
                    tool_starts = { { kind = "async", handle = "process-1" } },
                })
                assert(unknown.loop:begin_main(input(false)))
                assert(unknown.loop:accept_model_response(response(unknown.loop, {
                    tag = "unknown-exec",
                    calls = { call("exec", 1) },
                })))
                assert(unknown.loop:accept_tool_result(tool_result("unknown", {
                    error_id = "ProcessTreeUnknown",
                    external_effects_unsettled = true,
                })))
                assert_golden(unknown.loop, "unknown-tool-side-effect")
                A.falsy(unknown.loop:status().auto_replay)
            end,
        },
        {
            name = "tool and request caps pair accepted calls before budget exhaustion",
            run = function()
                local capped = fixture({}, {
                    hard_caps = { tool_calls = 1, steps = 8 },
                })
                assert(capped.loop:begin_main(input(false)))
                assert(capped.loop:accept_model_response(response(capped.loop, {
                    tag = "over-tool-cap",
                    calls = { call("read", 1), call("read", 2) },
                })))
                A.equal(capped.loop:status().last_outcome, "budget_exhausted")
                A.equal(#capped.tool_starts, 0)
                local result_trace = trace(capped.loop).tool_results
                A.equal(#result_trace, 2)
                A.equal(result_trace[1].kind, "skipped-budget-exhausted")
                A.equal(result_trace[2].kind, "skipped-budget-exhausted")

                local timed = fixture({}, { hard_caps = { active_time_ms = 5 } })
                assert(timed.loop:begin_main(input(false)))
                timed.advance(5)
                assert(timed.loop:tick())
                A.equal(timed.loop:status().last_outcome, "budget_exhausted")
            end,
        },
        {
            name = "stuck warning is durable once and permits exactly one bounded escape request",
            run = function()
                local f = fixture({}, {
                    stuck = {
                        exact_repeat = 2,
                        same_error = 10,
                        abab_cycle = 10,
                        semantic_no_progress = 10,
                    },
                })
                assert(f.loop:begin_main(input(false)))
                assert(f.loop:accept_model_response(response(f.loop, {
                    digest = "repeat-call",
                    progress_identity = "workspace-v1",
                    calls = { call("read", 1) },
                })))
                assert(f.loop:accept_model_response(response(f.loop, {
                    digest = "repeat-call",
                    progress_identity = "workspace-v1",
                    calls = { call("read", 2) },
                })))
                A.equal(f.loop:status().state, "RequestingModel")
                assert(f.loop:accept_model_response(response(f.loop, {
                    digest = "different-words",
                    progress_identity = "workspace-v1",
                    calls = { call("read", 3) },
                })))
                local status = f.loop:status()
                A.equal(status.last_outcome, "stuck")
                A.truthy(status.trace.durable_warning)
                A.equal(status.trace.escape_steps, 1)
                A.equal(#f.tool_starts, 1)
                local warnings = 0
                for _, event in ipairs(f.events) do
                    if event.type == "warning" then warnings = warnings + 1 end
                end
                A.equal(warnings, 1)
            end,
        },
        {
            name = "same-error ABAB and semantic no-progress consume canonical identities only",
            run = function()
                local same_error = fixture({
                    tool_starts = {
                        { kind = "complete", result = tool_result("real-failed", { error_id = "E1" }) },
                        { kind = "complete", result = tool_result("real-failed", { error_id = "E1" }) },
                    },
                }, {
                    stuck = {
                        exact_repeat = 20, same_error = 2,
                        abab_cycle = 20, semantic_no_progress = 20,
                    },
                })
                assert(same_error.loop:begin_main(input(false)))
                for index = 1, 2 do
                    assert(same_error.loop:accept_model_response(response(same_error.loop, {
                        digest = "error-plan-" .. index,
                        progress_identity = "progress-" .. index,
                        calls = { call("read", index) },
                    })))
                end
                A.truthy(same_error.loop:status().trace.durable_warning)
                assert(same_error.loop:accept_model_response(response(same_error.loop, {
                    digest = "escape-error-plan",
                    progress_identity = "progress-2",
                    calls = { call("read", 3) },
                })))
                A.equal(same_error.loop:status().last_outcome, "stuck")

                local semantic = fixture({}, {
                    stuck = {
                        exact_repeat = 20, same_error = 20,
                        abab_cycle = 20, semantic_no_progress = 2,
                    },
                })
                assert(semantic.loop:begin_main(input(false)))
                for index = 1, 2 do
                    assert(semantic.loop:accept_model_response(response(semantic.loop, {
                        digest = "different-text-" .. index,
                        progress_identity = "same-workspace",
                        calls = { call("read", index) },
                    })))
                end
                A.truthy(semantic.loop:status().trace.durable_warning)

                local abab = fixture({}, {
                    stuck = {
                        exact_repeat = 20, same_error = 20,
                        abab_cycle = 1, semantic_no_progress = 20,
                    },
                })
                assert(abab.loop:begin_main(input(false)))
                local digests = { "A", "B", "A", "B" }
                for index, digest in ipairs(digests) do
                    assert(abab.loop:accept_model_response(response(abab.loop, {
                        digest = digest,
                        progress_identity = "state-" .. index,
                        calls = { call("read", index) },
                    })))
                end
                A.truthy(abab.loop:status().trace.durable_warning)
                A.equal(abab.loop:status().trace.escape_steps, 1)
            end,
        },
        {
            name = "action review and deferred approval cannot widen or bypass the exact call binding",
            run = function()
                local f = fixture({
                    admit = function(call_value)
                        return {
                            decision = "review",
                            capabilities = "RawExec",
                            permission_snapshot_digest = "permission-digest",
                            reason = "high risk",
                            token = "token:" .. call_value.tool_call_id,
                            after_review = "confirm",
                        }
                    end,
                })
                assert(f.loop:begin_main(input(true)))
                assert(f.loop:accept_model_response(response(f.loop, {
                    tag = "review-exec",
                    calls = { call("exec", 1) },
                })))
                A.equal(f.loop:status().state, "EvaluatingAction")
                assert(f.loop:resolve_action_review({
                    verdict = "tighten",
                    review_id = "action-review-1",
                    binding_digest = "action-binding-1",
                    reason = "keep the exact command",
                }))
                A.equal(f.loop:status().state, "AwaitingApproval")
                assert(f.loop:resolve_approval({
                    decision = "defer",
                    approval_id = "approval-deferred",
                    snapshot_digest = "approval-snapshot",
                    approval_digest = "",
                }))
                A.equal(f.loop:status().state, "WaitingUser")
                assert(f.loop:resolve_approval({
                    decision = "approve",
                    approval_id = "approval-final",
                    snapshot_digest = "approval-snapshot",
                    approval_digest = "approval-binding",
                }))
                A.equal(f.loop:status().state, "RequestingModel")
                A.equal(#f.tool_starts, 1)
                assert(f.loop:accept_model_response(finish(f.loop, "reviewed finish")))
                assert(f.loop:resolve_termination_review(review_verdict("pass", 9)))
                A.equal(f.loop:status().last_outcome, "completed")
                A.truthy(index_of(f.log, "durable:permission_decision")
                    < index_of(f.log, "effect:review:"))
                A.truthy(index_of(f.log, "durable:action_review")
                    < index_of(f.log, "durable:approval", 1))
                A.truthy(index_of(f.log, "durable:approval", 2)
                    < index_of(f.log, "effect:tool:"))

                local unavailable = fixture({
                    reviews_false = true,
                    admit = function()
                        return {
                            decision = "review",
                            capabilities = "WriteWorkspace",
                            permission_snapshot_digest = "permission-digest",
                            reason = "review required",
                            token = "token",
                            after_review = "allow",
                        }
                    end,
                })
                assert(unavailable.loop:begin_main(input(true)))
                assert(unavailable.loop:accept_model_response(response(unavailable.loop, {
                    tag = "review-unavailable",
                    calls = { call("write", 1) },
                })))
                local continued, continue_error = unavailable.loop:reply("do it anyway", "user")
                A.falsy(continued)
                A.equal(continue_error.code, "ReviewResolutionRequired")
                assert(unavailable.loop:cancel("no reviewer"))
                A.equal(unavailable.loop:status().last_outcome, "cancelled")
                A.equal(trace(unavailable.loop).tool_results[1].kind, "skipped-by-cancel")
            end,
        },
        {
            name = "pending cancellation suppresses late calls and active-tool time cap stays budget typed",
            run = function()
                local late = fixture({ model_cancel_outcome = "pending" })
                assert(late.loop:begin_main(input(false)))
                assert(late.loop:accept_model_event(late.loop:status().active_request_id))
                assert(late.loop:cancel("stop sampling"))
                assert(late.loop:accept_model_response(response(late.loop, {
                    tag = "late-tools",
                    calls = { call("write", 1), call("exec", 2) },
                })))
                A.equal(late.loop:status().last_outcome, "cancelled")
                A.equal(#late.tool_starts, 0)
                local late_results = trace(late.loop).tool_results
                A.equal(late_results[1].kind, "skipped-by-cancel")
                A.equal(late_results[2].kind, "skipped-by-cancel")

                local timed = fixture({
                    tool_starts = { { kind = "async", handle = "long-process" } },
                }, { hard_caps = { active_time_ms = 5 } })
                assert(timed.loop:begin_main(input(false)))
                assert(timed.loop:accept_model_response(response(timed.loop, {
                    tag = "long-tool",
                    calls = { call("exec", 1) },
                })))
                timed.advance(5)
                assert(timed.loop:tick())
                A.equal(timed.loop:status().last_outcome, "budget_exhausted")
                A.equal(trace(timed.loop).tool_results[1].kind, "real-cancelled")
            end,
        },
        {
            name = "result durability loss is fail-stop and suppresses every later effect and report",
            run = function()
                local f = fixture({ fail_event = "tool_result" })
                assert(f.loop:begin_main(input(false)))
                local accepted, result_error = f.loop:accept_model_response(response(f.loop, {
                    tag = "commit-failure",
                    calls = { call("read", 1), call("read", 2) },
                }))
                A.falsy(accepted)
                A.equal(result_error.code, "AgentDurabilityFailure")
                local status = f.loop:status()
                A.truthy(status.halted)
                A.equal(status.state, "Finalizing")
                A.falsy(status.reportable)
                A.equal(status.last_outcome, false)
                A.equal(#f.tool_starts, 1)
                A.equal(#f.model_starts, 1)
                local later, same_error = f.loop:cancel("after failure")
                A.falsy(later)
                A.equal(same_error, result_error)

                local wrong = fixture({ bad_binding_at = 2 })
                local started, start_error = wrong.loop:begin_main(input(false))
                A.falsy(started)
                A.equal(start_error.code, "AgentDurabilityFailure")
                A.equal(#wrong.model_starts, 0)
            end,
        },
        {
            name = "all remaining typed outcomes and closing state share one finalization gate",
            run = function()
                local partial = fixture()
                assert(partial.loop:begin_main(input(false)))
                assert(partial.loop:accept_model_response(response(partial.loop, { tag = "yield" })))
                assert(partial.loop:abort("partial", "bounded partial work", "PartialWork"))
                A.equal(partial.loop:status().last_outcome, "partial")

                local protocol = fixture()
                assert(protocol.loop:begin_main(input(false)))
                local malformed = response(protocol.loop, { tag = "bad" })
                malformed.normalized.execution_admitted = true
                assert(protocol.loop:accept_model_response(malformed))
                A.equal(protocol.loop:status().last_outcome, "error")

                local closing = fixture()
                assert(closing.loop:begin_main(input(false)))
                assert(closing.loop:close("quit"))
                A.equal(closing.loop:status().state, "Closing")
                A.equal(closing.loop:status().last_outcome, "cancelled")
                A.falsy(closing.loop:close("again"))

                local capability = closing.loop.capabilities
                A.falsy(capability.provider_stop_means_completed)
                A.falsy(capability.natural_language_done_means_finish)
                A.equal(capability.accepted_call_results, "exactly-one-real-or-synthetic")
                A.raises(function() capability.single_owner = false end, "cannot be modified")

                local repeated = fixture()
                assert(repeated.loop:begin_main(input(false)))
                assert(repeated.loop:accept_model_response(finish(repeated.loop, "first")))
                assert(repeated.loop:begin_main(input(false)))
                local active_status = repeated.loop:status()
                A.falsy(active_status.reportable)
                A.equal(active_status.reported_outcome, false)
                A.equal(active_status.last_outcome, "completed")
                assert(repeated.loop:accept_model_response(finish(repeated.loop, "second")))
            end,
        },
        {
            name = "constructor rejects missing hard caps unversioned stuck data and ambiguous ports",
            run = function()
                local bad_options = options()
                bad_options.stuck.exact_repeat = 0
                local loop, option_error = runtime.new_agent_loop({
                    clock = { now = function() return 0 end },
                    journal = { commit = function() end },
                    model = { start = function() end, cancel = function() end },
                    tools = {
                        admit = function() end,
                        start = function() end,
                        cancel = function() end,
                    },
                    reviews = false,
                }, bad_options)
                A.falsy(loop)
                A.equal(option_error.code, "InvalidAgentOptions")

                local f = fixture()
                local status = f.loop:status()
                A.equal(status.stuck_snapshot_id, "manifest-stuck-v1")
                A.equal(status.hard_cap_snapshot_id, "manifest-hard-caps-v1")
                A.contains(status.runtime_snapshot, "exact_repeat=10")
                assert(f.loop:begin_main(input(false)))
                A.equal(
                    f.events[1].fields.runtimeSnapshot,
                    status.runtime_snapshot
                )
                A.raises(function() status.state = "Streaming" end, "cannot be modified")
            end,
        },
    },
}
