--[[
Author: WaterRun
Date: 2026-09-23
File: tool_runtime_port_test.lua
Description: Verifies the production Tool/Permission adapter and operation receipts.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

--Loads a source module into an isolated per-case environment.
--@param name string Module, Model, or resource name selected by the case.
--@param cache table Per-case module cache preserving isolated imports.
--@return any module Module export loaded in the isolated source environment.
local function load_module(name, cache)
    cache = cache or {}
    if cache[name] then return cache[name] end
    local environment = {}
    for key, value in pairs(_ENV) do environment[key] = value end
    --Resolves an imported Lua module through the isolated test loader.
    --@param dependency string Source module requested from the isolated loader.
    --@return any value Callback value consumed by the enclosing scenario assertion.
    environment.require = function(dependency) return load_module(dependency, cache) end
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
    local result = chunk()
    cache[name] = result
    return result
end

local tools = load_module("tools", {})

--Copies test data so a mutation cannot affect the original fixture.
--@param value any Candidate whose acceptance or transformation the test checks.
--@return any copy Independent copy of the source fixture value.
local function copy(value)
    local result = {}
    for key, item in pairs(value) do result[key] = item end
    return result
end

--Supplies runtime call behavior required by this suite.
--@param name string Module, Model, or resource name selected by the case.
--@param id string|integer Identity selected for the fake operation.
--@return table observed Structured fixture record selected by the exercised branch.
local function runtime_call(name, id)
    return {
        tool_call_id = "turn-1:tool:" .. tostring(id),
        operation_id = "turn-1:operation:" .. tostring(id),
        adapter_call_id = "adapter-" .. tostring(id),
        provider_call_id = "provider-" .. tostring(id),
        name = name,
        canonical_arguments = name == "exec"
            and '{"command":"true"}' or '{"path":"/work/a"}',
        side_effecting = name == "write" or name == "exec",
    }
end

--Constructs the suite's isolated runtime fixture and observation ports.
--@param settings table|nil Fixture settings and scenario overrides.
--@return any fixture Constructed fixture service used by this suite.
--@return any secondary2 Additional status or structured error from the fixture operation.
local function fixture(settings)
    settings = settings or {}
    local log = {}
    local settled = false
    local settled_kind = "real-success"
    local current_call
    local service = {
        schema_version = "1.0.0",
        registry_digest = "registry-digest",
    }

    --Supplies admit call behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param envelope table Transport or activity envelope under inspection.
    --@return any observed admit call value observed by the scenario assertion.
    function service:admit_call(envelope)
        log[#log + 1] = "admit:" .. envelope.tool
        current_call = {
            tool = envelope.tool,
            tool_call_id = envelope.tool_call_id,
            operation_id = envelope.operation_id,
            mutates = envelope.tool == "write",
        }
        return current_call
    end

    --Supplies permission action behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param call table|integer Recorded call or call ordinal under inspection.
    --@return table observed Structured fixture record selected by the exercised branch.
    function service:permission_action(call)
        return {
            tool = call.tool,
            outside_workspace = false,
            reserved_tree = false,
            schema_version = self.schema_version,
            registry_digest = self.registry_digest,
            canonical_arguments = "{}",
            canonical_target = call.tool == "exec" and "" or "/work/a",
            expected_raw_digest = "",
            cwd = "/work",
            workspace_root_identity = "workspace-identity",
            operation_id = call.operation_id,
            tool_call_id = call.tool_call_id,
        }
    end

    --Supplies begin operation behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param call table|integer Recorded call or call ordinal under inspection.
    --@return string observed Fixture text "intent-digest".
    function service:begin_operation(call)
        log[#log + 1] = "intent:" .. call.operation_id
        return "intent-digest"
    end

    --Simulates the authorize port for this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param call table|integer Recorded call or call ordinal under inspection.
    --@param facts table Platform or file-descriptor facts supplied to the case.
    --@return string|nil observed Fixture text "execution-token"; nil on alternate branches.
    --@return table|nil secondary2 Typed error record with code AuthorizationDenied.
    function service:authorize(call, facts)
        log[#log + 1] = "authorize:" .. facts.action_review
        A.equal(facts.config_generation, "config-1")
        A.equal(facts.workspace_identity, "workspace-identity")
        if settings.authorization_failure then
            return nil, { code = "AuthorizationDenied", message = "injected" }
        end
        return "execution-token"
    end

    --Supplies fail before effect behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param _ any Unused callback argument supplied by the port.
    --@param error_value any The error value supplied to the fake service for this scenario.
    --@return table observed Outcome record with status failed.
    function service:fail_before_effect(_, error_value)
        log[#log + 1] = "pre-effect-failure:" .. error_value.code
        settled = true
        settled_kind = "real-failed"
        return { outcome = "failed" }
    end

    --Supplies execute behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@return table observed Outcome record with status success.
    function service:execute()
        log[#log + 1] = "execute"
        settled = true
        return { outcome = "success" }
    end

    --Supplies result behavior required by this suite.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return table|boolean observed result value observed by the scenario assertion.
    local function result()
        if not settled then return false end
        return {
            kind = settled_kind,
            body = "canonical-result",
            truncated = false,
            raw_bytes = 16,
            digest = "body-digest",
            error_id = settled_kind == "real-failed" and "AuthorizationDenied" or false,
            external_effects_unsettled = false,
            progress_identity = "result-digest",
        }
    end

    --Supplies runtime result behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@return any observed runtime result value observed by the scenario assertion.
    function service:runtime_result() return result() end

    --Supplies execution port behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@return any observed execution port value observed by the scenario assertion.
    function service:execution_port()
        local raw = {}
        --Simulates the start transition of a fake activity port for this suite.
        --@param self table Fixture or port instance receiving this call.
        --@param now integer Monotonic timestamp supplied by the fake clock.
        --@return boolean accepted Whether start succeeds in the fixture.
        function raw:start(now)
            log[#log + 1] = "exec-start:" .. tostring(now)
            return true
        end
        --Simulates the poll transition of a fake activity port for this suite.
        --@param self table Fixture or port instance receiving this call.
        --@return table observed Outcome record with status completed.
        function raw:poll()
            return { { kind = "io_terminal", outcome = "completed" } }
        end
        --Simulates the cancel transition of a fake activity port for this suite.
        --@param self table Fixture or port instance receiving this call.
        --@return boolean accepted Whether cancel succeeds in the fixture.
        function raw:cancel()
            log[#log + 1] = "exec-cancel"
            return true
        end
        --Simulates the join transition of a fake activity port for this suite.
        --@param self table Fixture or port instance receiving this call.
        --@return table observed Outcome record with status completed.
        function raw:join()
            settled = true
            return { outcome = "completed", tool_result = true, error = false }
        end
        --Simulates the close transition of a fake activity port for this suite.
        --@param self table Fixture or port instance receiving this call.
        --@return boolean accepted Whether close succeeds in the fixture.
        function raw:close()
            log[#log + 1] = "exec-close"
            return true
        end
        return raw
    end

    local permission = {}
    --Simulates the evaluate port for this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param _ any Unused callback argument supplied by the port.
    --@param action table|string Action supplied to the exercised service.
    --@return table observed Structured fixture record selected by the exercised branch.
    function permission:evaluate(_, action)
        local review = settings.review == true and action.tool ~= "read"
        return {
            required_capabilities = { action.tool == "exec" and "Shell" or "Write" },
            profile_snapshot_digest = "permission-snapshot",
            hard_denial = false,
            review_required = review,
            review_status = review and "required" or "not-required",
            decision = settings.confirm == true and "confirm" or "allow",
        }
    end
    --Supplies tighten behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param decision table|string Permission decision supplied to the case.
    --@param reviewer_decision any The reviewer decision supplied to the fake service for this scenario.
    --@return any observed tighten value observed by the scenario assertion.
    function permission:tighten(decision, reviewer_decision)
        log[#log + 1] = "review:" .. reviewer_decision
        local result = copy(decision)
        result.review_required = false
        result.review_status = "reviewed"
        if reviewer_decision == "confirm" then result.decision = "confirm" end
        return result
    end
    --Supplies approval snapshot behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param _ any Unused callback argument supplied by the port.
    --@param binding table Verified binding under inspection.
    --@return any observed Captured snapshot returned by the fixture.
    function permission:approval_snapshot(_, binding)
        log[#log + 1] = "approval-snapshot"
        local snapshot = copy(binding)
        snapshot.snapshot_digest = "approval-snapshot-digest"
        return snapshot
    end
    --Supplies record approval behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param _ any Unused callback argument supplied by the port.
    --@param approval_id string|integer Approval identity being resolved.
    --@param decision table|string Permission decision supplied to the case.
    --@return table observed Structured fixture record with approval_id, decision.
    function permission:record_approval(_, approval_id, decision)
        log[#log + 1] = "approval:" .. decision
        return { approval_id = approval_id, decision = decision }
    end
    --Supplies consume approval behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@return table observed Structured fixture record with authorized.
    function permission:consume_approval()
        log[#log + 1] = "approval-consumed"
        return { authorized = true }
    end
    --Supplies admit without approval behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@return table observed Structured fixture record with authorized.
    function permission:admit_without_approval()
        log[#log + 1] = "permission-allow"
        return { authorized = true }
    end

    local journal = {}
    --Supplies take intent receipt behavior required by this suite.
    --@param operation_id string|integer Operation identity being resolved.
    --@param digest string Expected or computed hexadecimal digest.
    --@return table observed Structured fixture record with kind, operation_id.
    function journal.take_intent_receipt(operation_id, digest)
        A.equal(digest, "intent-digest")
        log[#log + 1] = "intent-receipt"
        return { kind = "intent-receipt", operation_id = operation_id }
    end
    --Supplies take result receipt behavior required by this suite.
    --@param operation_id string|integer Operation identity being resolved.
    --@return table observed Structured fixture record with kind, operation_id.
    function journal.take_result_receipt(operation_id)
        log[#log + 1] = "result-receipt"
        return { kind = "result-receipt", operation_id = operation_id }
    end

    local now = 7
    local port = assert(tools.new_agent_port({
        service = service,
        permission = permission,
        profile = {},
        operation_journal = journal,
        clock = {
            --Supplies deterministic clock behavior for this suite.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return any value Callback value consumed by the enclosing scenario assertion.
            now = function() return now end },
    }, {
        config_generation = "config-1",
        double_check = settings.review == true,
        action_review_enabled = true,
        exec_policy = {},
    }))
    return port, log
end

return {
    name = "integration/tool-runtime-port",
    cases = {
        {
            name = "read allow executes directly without an operation receipt",
            --Verifies read allow executes directly without an operation receipt.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify read allow executes directly without an operation receipt.
            run = function()
                local port, log = fixture()
                local call = runtime_call("read", 1)
                local admission = assert(port.admit(call))
                A.equal(admission.decision, "allow")
                local started = assert(port.start({
                    turn_id = "turn-1",
                    call = call,
                    admission = admission,
                }))
                A.equal(started.kind, "complete")
                A.equal(started.result.kind, "real-success")
                A.falsy(started.intent_receipt)
                A.falsy(started.result_receipt)
                A.deep_equal(log, {
                    "admit:read", "permission-allow", "authorize:not-required", "execute",
                })
            end,
        },
        {
            name = "reviewed confirmation is consumed before durable mutation intent",
            --Verifies read allow executes directly without an operation receipt.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify read allow executes directly without an operation receipt.
            run = function()
                local port, log = fixture({ review = true, confirm = true })
                local call = runtime_call("write", 1)
                local admission = assert(port.admit(call))
                A.equal(admission.decision, "review")
                A.equal(admission.after_review, "confirm")
                local snapshot = assert(port.prepare_approval(call.tool_call_id, "pass"))
                A.equal(snapshot.snapshot_digest, "approval-snapshot-digest")
                local approval = assert(port.record_approval(
                    call.tool_call_id,
                    "pass",
                    "approval-1",
                    "approve"
                ))
                local admitted = copy(admission)
                admitted.review_verdict = "pass"
                admitted.approval_digest = approval.approval_digest
                local started = assert(port.start({
                    turn_id = "turn-1",
                    call = call,
                    admission = admitted,
                }))
                A.equal(started.intent_receipt.kind, "intent-receipt")
                A.equal(started.result_receipt.kind, "result-receipt")
                A.deep_equal(log, {
                    "admit:write", "review:allow", "approval-snapshot",
                    "approval:approved", "approval-consumed",
                    "intent:turn-1:operation:1", "intent-receipt",
                    "authorize:approved", "execute", "result-receipt",
                })
            end,
        },
        {
            name = "exec remains async and settles with the paired operation receipt",
            --Verifies exec remains async and settles with the paired operation receipt.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify exec remains async and settles with the paired operation receipt.
            run = function()
                local port, log = fixture()
                local call = runtime_call("exec", 1)
                local admission = assert(port.admit(call))
                local started = assert(port.start({
                    turn_id = "turn-1",
                    call = call,
                    admission = admission,
                }))
                A.equal(started.kind, "async")
                A.equal(port.active_handle(), started.handle)
                A.equal(port.cancel(started.handle).outcome, "pending")
                local events, settlement = assert(port.poll(8, 16))
                A.equal(events[1].kind, "io_terminal")
                A.equal(settlement.result.kind, "real-success")
                A.equal(settlement.result_receipt.kind, "result-receipt")
                A.falsy(port.active_handle())
                A.deep_equal(log, {
                    "admit:exec", "permission-allow", "intent:turn-1:operation:1",
                    "intent-receipt", "authorize:not-required", "exec-start:7",
                    "exec-cancel", "exec-close", "result-receipt",
                })
            end,
        },
        {
            name = "post-intent authorization failure closes a real durable result",
            --Verifies post-intent authorization failure closes a real durable result.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify post-intent authorization failure closes a real durable result.
            run = function()
                local port, log = fixture({ authorization_failure = true })
                local call = runtime_call("write", 1)
                local admission = assert(port.admit(call))
                local started = assert(port.start({
                    turn_id = "turn-1",
                    call = call,
                    admission = admission,
                }))
                A.equal(started.kind, "complete")
                A.equal(started.result.kind, "real-failed")
                A.equal(started.result.error_id, "AuthorizationDenied")
                A.equal(started.intent_receipt.kind, "intent-receipt")
                A.equal(started.result_receipt.kind, "result-receipt")
                A.deep_equal(log, {
                    "admit:write", "permission-allow", "intent:turn-1:operation:1",
                    "intent-receipt", "authorize:not-required",
                    "pre-effect-failure:AuthorizationDenied", "result-receipt",
                })
            end,
        },
    },
}
