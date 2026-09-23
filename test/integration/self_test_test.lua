--[[
Author: WaterRun
Date: 2026-09-23
File: self_test_test.lua
Description: Verifies ordered offline, Model, and advisory self-test execution.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()
local diagnostics = assert(loadfile(
    YACA_TEST_ROOT .. "/src/diagnostics.lua",
    "t",
    _ENV
))()

local CHECK_IDS = {
    "ST1-PLATFORM",
    "ST1-PACKAGE",
    "ST1-SAFE-LOAD",
    "ST1-DATA-ROOT",
    "ST1-CONFIG-SCHEMA",
    "ST1-CONFIG-SOURCE",
    "ST1-ATOMIC-WRITE",
    "ST1-CONTEXT-CODEC",
    "ST1-CONTEXT-SCHEMA",
    "ST1-CONTEXT-CATALOG",
    "ST1-CONTEXT-LOCK",
    "ST1-TOOLS",
    "ST1-CA-BUNDLE",
    "ST1-TTY-INPUT",
    "ST1-ZERO-SURFACE",
    "ST2-MODEL-TRANSPORT",
    "ST2-MODEL-AUTH",
    "ST2-MODEL-WIRE",
    "ST2-MODEL-STREAM",
    "ST2-MODEL-TOOLS",
    "ST2-MODEL-CONTROL",
    "ST2-MODEL-USAGE-CANCEL",
    "ST3-CONFIG-SEMANTICS",
    "ST3-PERMISSION-SEMANTICS",
    "ST3-NAMING-AND-SPELLING",
}

--Builds validated options for this suite's component fixture.
--@param overrides table|nil Per-case overrides of default fixture behavior.
--@return any options options used to configure the component under test.
local function options(overrides)
    local result = {
        maximum_models = 8,
        maximum_filters = 32,
        maximum_results = 128,
        maximum_summary_bytes = 256,
        maximum_evidence_items = 8,
        maximum_evidence_bytes = 256,
        maximum_online_requests = 128,
        maximum_snapshot_nodes = 2048,
        maximum_snapshot_bytes = 65536,
        maximum_identifier_bytes = 128,
    }
    for key, value in pairs(overrides or {}) do result[key] = value end
    return result
end

--Simulates the request port for this suite.
--@param overrides table|nil Per-case overrides of default fixture behavior.
--@return any observed request value observed by the scenario assertion.
local function request(overrides)
    local result = {
        mode = "explicit",
        through_stage = 1,
        list_checks = false,
        online_consent = false,
        excluded_models = {},
        excluded_checks = {},
        selected_checks = {},
        snapshot_id = "config-generation-7",
        snapshot = {
            product = { name = "yaca", version = "0.1.0-dev" },
            config = {
                available = true,
                permissions = {
                    Std = { read = "allow", write = "confirm" },
                },
            },
        },
        models = {
            {
                id = "Primary",
                endpoint = "https://primary.example/v1/chat",
                snapshot_id = "config-generation-7:model:1",
            },
            {
                id = "\228\184\187\230\168\161\229\158\139",
                endpoint = "https://secondary.example/v1/messages",
                snapshot_id = "config-generation-7:model:2",
            },
        },
    }
    for key, value in pairs(overrides or {}) do result[key] = value end
    return result
end

--Supplies raw result behavior required by this suite.
--@param outcome string Expected terminal outcome.
--@param online_requests any The online requests supplied to the fake service for this scenario.
--@param overrides table|nil Per-case overrides of default fixture behavior.
--@return any observed raw result value observed by the scenario assertion.
local function raw_result(outcome, online_requests, overrides)
    local result = {
        outcome = outcome or "passed",
        summary = "check completed",
        evidence = { "fixture evidence" },
        online_requests = online_requests or 0,
        auto_fixes = 0,
    }
    for key, value in pairs(overrides or {}) do result[key] = value end
    return result
end

--Constructs new fixture for this test scenario.
--@param settings table|nil Fixture settings and scenario overrides.
--@param option_overrides table|nil Per-case overrides of default options.
--@return any created Constructed new fixture fixture value.
--@return any secondary2 Configured control actions returned by the fixture.
--@return any secondary3 Additional status or structured error from the fixture operation.
local function new_fixture(settings, option_overrides)
    settings = settings or {}
    local controls = {
        offline_calls = {},
        model_calls = {},
        advisory_calls = {},
        network_requests = 0,
        immutable_requests = true,
        reentrant_error = false,
    }
    local service
    --Supplies immutable behavior required by this suite.
    --@param specification table Test specification used to construct the fixture.
    --@return nil No value; the fake port or test assertion observes this callback's effects.
    local function immutable(specification)
        --Supplies pcall behavior required by this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return nil No value; the fake port or test assertion observes this callback's effects.
        local root_ok = pcall(function() specification.no_auto_fix = false end)
        --Supplies pcall behavior required by this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return nil No value; the fake port or test assertion observes this callback's effects.
        local check_ok = pcall(function() specification.check.id = "changed" end)
        controls.immutable_requests = controls.immutable_requests
            and not root_ok and not check_ok
    end
    local ports = {
        offline = { online = false },
        model = { online = true },
        advisory = { online = true, auto_fix = false },
    }
    --Supplies run behavior required by this suite.
    --@param specification table Test specification used to construct the fixture.
    --@return any observed run value observed by the scenario assertion.
    function ports.offline.run(specification)
        immutable(specification)
        controls.offline_calls[#controls.offline_calls + 1] = specification
        if settings.reenter and #controls.offline_calls == 1 then
            local nested, nested_error = service:run(request())
            A.falsy(nested)
            controls.reentrant_error = nested_error and nested_error.code
        end
        local configured = settings.offline
            and settings.offline[specification.check.id] or nil
        if type(configured) == "function" then return configured(specification) end
        return raw_result(configured or "passed", 0)
    end
    --Supplies run behavior required by this suite.
    --@param specification table Test specification used to construct the fixture.
    --@return any observed run value observed by the scenario assertion.
    function ports.model.run(specification)
        immutable(specification)
        controls.model_calls[#controls.model_calls + 1] = specification
        local identity = specification.model.id .. "\0" .. specification.check.id
        local configured = settings.model and settings.model[identity]
            or settings.model and settings.model[specification.check.id]
        if type(configured) == "function" then return configured(specification) end
        local online_requests = settings.model_online_requests
        if online_requests == nil then online_requests = 1 end
        controls.network_requests = controls.network_requests + online_requests
        return raw_result(configured or "passed", online_requests)
    end
    --Supplies run behavior required by this suite.
    --@param specification table Test specification used to construct the fixture.
    --@return any observed run value observed by the scenario assertion.
    function ports.advisory.run(specification)
        immutable(specification)
        controls.advisory_calls[#controls.advisory_calls + 1] = specification
        local configured = settings.advisory
            and settings.advisory[specification.check.id] or nil
        if type(configured) == "function" then return configured(specification) end
        local online_requests = settings.advisory_online_requests
        if online_requests == nil then online_requests = 1 end
        controls.network_requests = controls.network_requests + online_requests
        return raw_result(configured or "passed", online_requests)
    end
    service = assert(diagnostics.new_self_test(ports, options(option_overrides)))
    return service, controls, ports
end

--Supplies call ids behavior required by this suite.
--@param calls any The calls supplied to the fake service for this scenario.
--@return any observed call ids value observed by the scenario assertion.
local function call_ids(calls)
    local result = {}
    for index, call in ipairs(calls) do result[index] = call.check.id end
    return result
end

return {
    name = "integration/self-test",
    cases = {
        {
            name = "registry is exact topological immutable and declares no mutation surface",
            --Verifies registry is exact topological immutable and declares no mutation surface.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify registry is exact topological immutable and declares no mutation surface.
            run = function()
                local service = assert(new_fixture())
                A.equal(service.online, "explicit-current-invocation-only")
                A.equal(service.auto_fix, false)
                A.truthy(service.stage3_is_advisory)
                A.truthy(service.strict_dependency_order)
                A.equal(#service.checks, 25)
                --Supplies an assertion callback for the registry is exact topological immutable and declares no mutation surface scenario.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return any value Callback value consumed by the enclosing scenario assertion.
                A.deep_equal(call_ids((function()
                    local wrapped = {}
                    for index, item in ipairs(service.checks) do
                        wrapped[index] = { check = item }
                    end
                    return wrapped
                end)()), CHECK_IDS)
                local seen = {}
                for _, item in ipairs(service.checks) do
                    for _, dependency in ipairs(item.dependencies) do
                        A.truthy(seen[dependency], item.id .. " dependency is not earlier")
                    end
                    seen[item.id] = true
                end
                --Executes the action expected to raise in the 'registry is exact topological immutable and declares no mutation surface' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; the fake port or test assertion observes this callback's effects.
                A.raises(function() service.checks[1].id = "changed" end, "cannot be modified")
                A.falsy(service.repair)
                A.falsy(service.apply)
                A.falsy(service.write)
            end,
        },
        {
            name = "listing all stages performs no check and no online request",
            --Verifies listing all stages performs no check and no online request.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify listing all stages performs no check and no online request.
            run = function()
                local service, controls = new_fixture()
                local result = assert(service:run(request({
                    through_stage = 3,
                    list_checks = true,
                })))
                A.equal(result.outcome, "passed")
                A.truthy(result.listed)
                A.equal(result.completed_stage, 0)
                A.equal(#result.checks, 25)
                A.equal(#result.models, 2)
                A.equal(#result.results, 0)
                A.equal(result.online_requests, 0)
                A.falsy(result.consent_consumed)
                A.equal(#controls.offline_calls, 0)
                A.equal(#controls.model_calls, 0)
                A.equal(#controls.advisory_calls, 0)
                A.equal(controls.network_requests, 0)
            end,
        },
        {
            name = "Stage 1 runs all offline checks in order and tolerates optional warning",
            --Verifies stage 1 runs all offline checks in order and tolerates optional warning.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify stage 1 runs all offline checks in order and tolerates optional warning.
            run = function()
                local service, controls = new_fixture({
                    offline = { ["ST1-TTY-INPUT"] = "warning" },
                })
                local result = assert(service:run(request()))
                A.equal(result.outcome, "passed")
                A.equal(result.completed_stage, 1)
                A.equal(result.online_requests, 0)
                A.equal(result.advisories, 0)
                A.equal(#result.results, 15)
                local expected = {}
                for index = 1, 15 do expected[index] = CHECK_IDS[index] end
                A.deep_equal(call_ids(controls.offline_calls), expected)
                A.equal(#controls.model_calls, 0)
                A.equal(#controls.advisory_calls, 0)
                A.equal(controls.network_requests, 0)
                A.truthy(controls.immutable_requests)
                for _, call in ipairs(controls.offline_calls) do
                    A.truthy(call.no_network)
                    A.truthy(call.no_auto_fix)
                    A.equal(call.mode, "explicit")
                end
            end,
        },
        {
            name = "online consent is checked before every offline or Model effect",
            --Verifies online consent is checked before every offline or Model effect.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify online consent is checked before every offline or Model effect.
            run = function()
                for _, stage in ipairs({ 2, 3 }) do
                    local service, controls = new_fixture()
                    local result, result_error = service:run(request({
                        through_stage = stage,
                    }))
                    A.falsy(result)
                    A.equal(result_error.code, "OnlineConsentRequired")
                    A.equal(#controls.offline_calls, 0)
                    A.equal(#controls.model_calls, 0)
                    A.equal(#controls.advisory_calls, 0)
                    A.equal(controls.network_requests, 0)
                end
            end,
        },
        {
            name = "Stage 2 checks every enabled Model independently with real requests",
            --Verifies online consent is checked before every offline or Model effect.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify online consent is checked before every offline or Model effect.
            run = function()
                local service, controls = new_fixture()
                local result = assert(service:run(request({
                    through_stage = 2,
                    online_consent = true,
                })))
                A.equal(result.outcome, "passed")
                A.equal(result.completed_stage, 2)
                A.equal(result.online_requests, 14)
                A.equal(result.auto_fixes, 0)
                A.equal(#result.confirmed_models, 2)
                A.equal(#controls.offline_calls, 15)
                A.equal(#controls.model_calls, 14)
                A.equal(#controls.advisory_calls, 0)
                A.equal(controls.network_requests, 14)
                for model_index = 1, 2 do
                    for check_index = 1, 7 do
                        local call = controls.model_calls[(model_index - 1) * 7 + check_index]
                        A.equal(call.model.id, request().models[model_index].id)
                        A.equal(call.check.id, CHECK_IDS[15 + check_index])
                        A.truthy(call.online_consent)
                        A.truthy(call.no_tools_outside_fixture)
                        A.truthy(call.no_auto_fix)
                        A.falsy(call.snapshot)
                    end
                end
                A.truthy(controls.immutable_requests)
            end,
        },
        {
            name = "required Model or check exclusion is partial and prevents Stage 3",
            --Verifies required Model or check exclusion is partial and prevents Stage 3.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify required Model or check exclusion is partial and prevents Stage 3.
            run = function()
                local service, controls = new_fixture()
                local result = assert(service:run(request({
                    through_stage = 3,
                    online_consent = true,
                    excluded_models = { "Primary" },
                })))
                A.equal(result.outcome, "partial")
                A.equal(result.completed_stage, 2)
                A.equal(result.required_exclusions, 7)
                A.equal(#controls.model_calls, 7)
                A.equal(#controls.advisory_calls, 0)

                service, controls = new_fixture()
                result = assert(service:run(request({
                    through_stage = 3,
                    online_consent = true,
                    excluded_checks = { "ST2-MODEL-TRANSPORT" },
                })))
                A.equal(result.outcome, "partial")
                A.equal(result.completed_stage, 2)
                A.equal(result.required_exclusions, 2)
                A.equal(#controls.model_calls, 0)
                A.equal(#controls.advisory_calls, 0)

                service, controls = new_fixture()
                result = assert(service:run(request({
                    through_stage = 2,
                    online_consent = true,
                    models = {},
                })))
                A.equal(result.outcome, "partial")
                A.equal(result.completed_stage, 2)
                A.equal(result.required_exclusions, 7)
                A.equal(#controls.model_calls, 0)
            end,
        },
        {
            name = "Stage 2 failure skips dependents and withholds failed Model from Stage 3",
            --Verifies stage 2 failure skips dependents and withholds failed Model from Stage 3.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify stage 2 failure skips dependents and withholds failed Model from Stage 3.
            run = function()
                local service, controls = new_fixture({
                    model = {
                        ["Primary\0ST2-MODEL-TRANSPORT"] = "failed",
                    },
                })
                local result = assert(service:run(request({
                    through_stage = 3,
                    online_consent = true,
                })))
                A.equal(result.outcome, "error")
                A.equal(result.completed_stage, 2)
                A.equal(result.required_exclusions, 0)
                A.equal(#result.confirmed_models, 1)
                A.equal(result.confirmed_models[1].id, "\228\184\187\230\168\161\229\158\139")
                A.equal(#controls.model_calls, 8)
                A.equal(#controls.advisory_calls, 0)
            end,
        },
        {
            name = "Stage 3 sees only confirmed Models and cannot block with advisories",
            --Verifies stage 3 sees only confirmed Models and cannot block with advisories.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify stage 3 sees only confirmed Models and cannot block with advisories.
            run = function()
                local service, controls = new_fixture({
                    advisory = {
                        ["ST3-CONFIG-SEMANTICS"] = "failed",
                        ["ST3-NAMING-AND-SPELLING"] = "warning",
                    },
                })
                local result = assert(service:run(request({
                    through_stage = 3,
                    online_consent = true,
                })))
                A.equal(result.outcome, "passed")
                A.equal(result.completed_stage, 3)
                A.equal(result.online_requests, 17)
                A.equal(result.advisories, 2)
                A.equal(result.auto_fixes, 0)
                A.equal(#controls.advisory_calls, 3)
                for index, call in ipairs(controls.advisory_calls) do
                    A.equal(call.check.id, CHECK_IDS[22 + index])
                    A.equal(#call.confirmed_models, 2)
                    A.truthy(call.advisory_only)
                    A.truthy(call.no_auto_fix)
                    A.truthy(call.online_consent)
                    A.truthy(call.snapshot.config.available)
                end
                A.equal(result.results[30].outcome, "warning")
                A.truthy(result.results[30].advisory)
                A.equal(controls.network_requests, 17)
            end,
        },
        {
            name = "executor network and mutation contract violations fail closed",
            --Verifies executor network and mutation contract violations fail closed.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify executor network and mutation contract violations fail closed.
            run = function()
                local service, controls = new_fixture({
                    offline = {
                        --Supplies an assertion callback for the executor network and mutation contract violations fail closed scenario.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return any value Callback value consumed by the enclosing scenario assertion.
                        ["ST1-PLATFORM"] = function()
                            return raw_result("passed", 1)
                        end,
                    },
                })
                local result, result_error = service:run(request())
                A.falsy(result)
                A.equal(result_error.code, "SelfTestContract")
                A.equal(#controls.offline_calls, 1)

                service, controls = new_fixture({ model_online_requests = 0 })
                result, result_error = service:run(request({
                    through_stage = 2,
                    online_consent = true,
                }))
                A.falsy(result)
                A.equal(result_error.code, "SelfTestContract")
                A.equal(#controls.model_calls, 1)

                service, controls = new_fixture({
                    advisory = {
                        --Supplies an assertion callback for the executor network and mutation contract violations fail closed scenario.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return any value Callback value consumed by the enclosing scenario assertion.
                        ["ST3-CONFIG-SEMANTICS"] = function()
                            return raw_result("passed", 1, { auto_fixes = 1 })
                        end,
                    },
                })
                result, result_error = service:run(request({
                    through_stage = 3,
                    online_consent = true,
                }))
                A.falsy(result)
                A.equal(result_error.code, "SelfTestContract")
                A.equal(#controls.advisory_calls, 1)

                service, controls = new_fixture({
                    offline = { ["ST1-PLATFORM"] = "cancelled" },
                })
                result = assert(service:run(request({
                    through_stage = 1,
                })))
                A.equal(result.outcome, "cancelled")
                A.equal(#controls.offline_calls, 1)
                A.equal(#controls.model_calls, 0)
            end,
        },
        {
            name = "requests filters caps and synchronous reentry are bounded",
            --Verifies requests filters caps and synchronous reentry are bounded.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify requests filters caps and synchronous reentry are bounded.
            run = function()
                local service, controls = new_fixture({ reenter = true })
                local result = assert(service:run(request()))
                A.equal(result.outcome, "passed")
                A.equal(controls.reentrant_error, "SelfTestBusy")

                service, controls = new_fixture()
                result = assert(service:run(request({
                    selected_checks = { "ST1-TOOLS" },
                })))
                A.equal(result.outcome, "partial")
                A.equal(result.required_exclusions, 10)
                A.deep_equal(call_ids(controls.offline_calls), {
                    "ST1-PLATFORM",
                    "ST1-PACKAGE",
                    "ST1-SAFE-LOAD",
                    "ST1-TOOLS",
                })

                result, result_error = service:run(request({
                    excluded_checks = { "ST1-PLATFORM", "ST1-PLATFORM" },
                }))
                A.falsy(result)
                A.equal(result_error.code, "InvalidSelfTestRequest")

                local unsafe = request()
                unsafe.snapshot[string.rep("k", 65537)] = true
                result, result_error = service:run(unsafe)
                A.falsy(result)
                A.equal(result_error.code, "InvalidSelfTestRequest")

                service = assert((new_fixture({}, {
                    maximum_models = 2,
                    maximum_results = 15,
                })))
                result, result_error = service:run(request({
                    through_stage = 2,
                    online_consent = true,
                }))
                A.falsy(result)
                A.equal(result_error.code, "SelfTestLimit")
            end,
        },
    },
}
