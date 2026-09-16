--[[
File: self_test_online_request_test.lua
Date: 2026-09-16
Author: WaterRun
Description: Verifies the purpose=self-test request builder and the online
Stage 2 plumbing through a scripted transport. No real network is used.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()
local sha256 = assert(loadfile(
    YACA_TEST_ROOT .. "/test/support/sha256_reference.lua",
    "t",
    _ENV
))()

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

local cache = {}
local model = load_module("model", cache)
local network = load_module("network", cache)
local prompt = load_module("prompt", cache)

local function adapter_limits()
    return {
        maximum_json_bytes = 65536,
        maximum_json_depth = 32,
        maximum_json_nodes = 4096,
        maximum_string_bytes = 32768,
        maximum_number_bytes = 32,
        maximum_sse_line_bytes = 8192,
        maximum_sse_event_bytes = 16384,
        maximum_sse_buffered_bytes = 32768,
        maximum_sse_events_per_push = 128,
        maximum_response_bytes = 65536,
        maximum_text_bytes = 32768,
        maximum_reasoning_bytes = 8192,
        maximum_tool_calls = 16,
        maximum_tool_argument_bytes = 16384,
        maximum_total_tool_argument_bytes = 32768,
        maximum_content_blocks = 64,
        maximum_events = 256,
    }
end

local function prompt_service()
    return assert(prompt.new({ digest = sha256.hex }, {
        maximum_component_bytes = 32768,
        maximum_quoted_bytes = 16384,
        maximum_total_bytes = 262144,
        maximum_estimated_tokens = 262144,
        maximum_components = 16,
        maximum_source_bytes = 256,
        maximum_version_bytes = 256,
    }))
end

local function registry()
    local tools = {}
    for _, name in ipairs({ "list", "read", "search", "write", "patch", "rename", "delete", "exec" }) do
        tools[#tools + 1] = {
            name = name,
            description = name,
            schema = { type = "object", additionalProperties = true },
        }
    end
    return { version = "tools-v1", digest = "registry-1", tools = tools }
end

local function generation()
    local result = {
        id = "config-generation-1",
        general = { system_prompt = "global" },
        network = {
            follow_proxy = false,
            no_proxy = "",
            ca_bundle_path = "/release/cacert.pem",
        },
        models = {
            Primary = {
                enabled = true,
                tools_enabled = true,
                protocol = "openai-chat",
                endpoint = "https://api.example/v1/chat/completions",
                remote_model = "gpt-test",
                system_prompt = "model",
                key_configured = true,
                adapter_options = {},
                streaming = "off",
                retry_count = 0,
                retry_base_delay_ms = 5,
                request_timeout_ms = 5000,
                max_output_tokens = 96,
            },
        },
        permissions = { Std = { system_prompt = "permission" } },
        reveal_secret = function() return "never-in-request" end,
        secret_descriptors = function() return {} end,
        scan_registered_secrets = function() return {} end,
    }
    return result
end

local function builder(settings)
    settings = settings or {}
    return assert(model.new_self_test_request_builder({
        adapter = settings.adapter or assert(model.new(adapter_limits())),
        prompt = prompt_service(),
        generation = settings.generation or generation(),
        tool_registry = registry(),
        safety = { digest = sha256.hex },
    }, {
        model_name = settings.model_name or "Primary",
        phase = settings.phase or "capability",
        synthetic_observation = settings.observation
            or "This is a connectivity probe. Reply with the single word READY.",
        tool_set = settings.tool_set or "none",
        default_connect_timeout_ms = 100,
        default_request_timeout_ms = 5000,
        maximum_request_time_ms = 8000,
        default_retry_base_delay_ms = 5,
        default_max_output_tokens = 256,
    }))
end

local function start_spec(view)
    return {
        request_id = "selftest-st2-model-wire",
        turn_id = "self-test",
        purpose = "self-test",
        continuation = false,
        view_manifest_ref = view,
        progress_identity = "self-test/ST2-MODEL-WIRE",
    }
end

local function scripted_transport(scripts, observed)
    local cursor = 0
    local service = {
        new_retry_controller = network.new_retry_controller,
        parse_http_headers = network.parse_http_headers,
        single_header = network.single_header,
        parse_retry_after = network.parse_retry_after,
    }
    function service.new_attempt(spec)
        cursor = cursor + 1
        local script = scripts[cursor]
        if not script then return nil, { code = "UnexpectedAttempt" } end
        observed[#observed + 1] = spec
        local started, emitted, cancelled = false, false, false
        local port = {}
        function port:start()
            started = true
            return true
        end
        function port:poll()
            A.truthy(started)
            if emitted then return {} end
            emitted = true
            return {
                {
                    kind = "transport_terminal",
                    outcome = cancelled and "cancelled" or "completed",
                },
            }
        end
        function port:cancel()
            cancelled = true
            return true
        end
        function port:join()
            if cancelled then
                return {
                    outcome = "cancelled",
                    exit_kind = "cancelled",
                    exit_code = false,
                    response_body = "",
                    response_headers = "",
                    body_truncated = false,
                    descendants_proven_stopped = true,
                }
            end
            return script.result
        end
        function port:close() return true end
        return port
    end
    return service
end

local function http_result(body)
    return {
        outcome = "completed",
        exit_kind = "exit-code",
        exit_code = 0,
        response_body = body,
        response_headers = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n",
        body_truncated = false,
        descendants_proven_stopped = true,
    }
end

local function self_test_activity(settings)
    local scripts = settings.scripts
    local observed = {}
    local adapter = assert(model.new(adapter_limits()))
    local value = builder({
        adapter = adapter,
        generation = settings.generation,
        observation = settings.observation,
        phase = settings.phase,
        tool_set = settings.tool_set,
    })
    local tick = 0
    local activity = assert(model.new_activity({
        adapter = adapter,
        transport = scripted_transport(scripts, observed),
        safety = { digest = sha256.hex },
        clock = {
            monotonic_now = function() return tick end,
            utc_now = function() return "2026-09-16T00:00:00Z" end,
        },
        requests = value,
    }, {
        identity_namespace = "self-test",
        maximum_poll_events = 64,
        maximum_queued_events = 512,
        maximum_header_bytes = 4096,
        maximum_header_line_bytes = 1024,
        maximum_header_lines = 64,
        maximum_redirects = 3,
        maximum_turn_time_ms = 10000,
        maximum_runtime_time_ms = 10000,
        maximum_canonical_body_bytes = 32768,
        retry_manifest = {
            identity = "self-test-activity-v1",
            maximum_count = 3,
            exponent = 2,
            maximum_delay_ms = 1000,
            runtime_wait_cap_ms = 2000,
            deterministic_jitter_permille = 0,
        },
    }))
    local handle = assert(activity.start(start_spec(value.snapshots.view)))
    local output = {}
    for _ = 1, 16 do
        local batch = assert(activity.poll(64))
        for _, event in ipairs(batch) do output[#output + 1] = event end
        local status = activity.status()
        if status.state == "waiting" then tick = status.waiting_until end
        if status.state == "idle" then break end
    end
    A.equal(activity.status().state, "idle")
    return {
        handle = handle,
        observed = observed,
        output = output,
        activity = activity,
        builder = value,
    }
end

return {
    name = "integration/self-test-online-request",
    cases = {
        {
            name = "control probe accepts only the exact complete validated inert call",
            run = function()
                local main = load_module("main", cache)
                local normalized = { finish_class = "tool_calls", tool_calls_validated = true,
                    tool_calls = { { name = "list", canonical_arguments = '{"depth":1,"page_size":1,"path":"."}' } } }
                local observation = { events = {}, response = { normalized = normalized } }
                local function outcome()
                    return main.evaluate_self_test_check("ST2-MODEL-CONTROL", observation, {}).outcome
                end
                A.equal(outcome(), "passed")
                normalized.incomplete = true
                A.equal(outcome(), "failed")
                normalized.incomplete = false
                normalized.tool_calls[1].canonical_arguments = '{"path":"."}'
                A.equal(outcome(), "failed")
                normalized.tool_calls = {}
                A.equal(outcome(), "failed")
            end,
        },
        {
            name = "an explicitly cancelled probe is a cancellation success rather than a transport failure",
            run = function()
                local main = load_module("main", cache)
                local observation = { cancel_requested = true, online_requests = 1,
                    events = { { kind = "transport_error", error_id = "self-test-cancel" } },
                    response = { normalized = { finish_class = "cancelled", tool_calls = {} } },
                }
                local result = main.evaluate_self_test_check("ST2-MODEL-USAGE-CANCEL", observation, {})
                A.equal(result.outcome, "passed")
                observation.cancel_requested = false
                A.equal(main.evaluate_self_test_check("ST2-MODEL-USAGE-CANCEL", observation, {}).outcome, "failed")
                observation.response.normalized.finish_class = "incomplete"
                observation.cancel_requested = true
                A.equal(main.evaluate_self_test_check("ST2-MODEL-USAGE-CANCEL", observation, {}).outcome, "failed")
            end,
        },
        {
            name = "online production probe rejects a changed generation before transport starts",
            run = function()
                local main = load_module("main", cache)
                local saved, changed = generation(), generation()
                changed.id = "config-generation-2"
                local composed = {
                    config = { reload_file = function() return changed end },
                    layout = { config_path = "/data/config.ini" },
                    model_adapter = {}, network = {},
                    contexts = { safety = {}, prompt = {}, tool_registry = {} },
                }
                local result = main.check_model_connection(composed, "Primary", saved)
                A.equal(result.online_requests, 0)
                A.equal(result.outcome, "failed")
                A.contains(table.concat(result.evidence), "ConfigChanged")
            end,
        },
        {
            name = "self-test builder binds the synthetic view and hides secrets",
            run = function()
                local value = builder({ observation = "Reply with READY." })
                local prepared = assert(value.prepare(start_spec(value.snapshots.view)))
                A.equal(prepared.request.purpose, "self-test")
                A.equal(prepared.request.model_ref.name, "Primary")
                A.equal(prepared.request.model_ref.auth_secret_id, "Model.Primary.Key")
                A.equal(prepared.request.model_view_manifest.digest, value.snapshots.view)
                A.equal(#prepared.request.tool_registry.tools, 0)
                A.equal(#prepared.request.controls_schema.controls, 0)
                A.equal(prepared.request.limits.max_output_tokens, 96)
                A.equal(type(prepared.secret_source), "table")
                A.equal(prepared.secret_source.id, "config-generation-1")
                A.equal(prepared.proxy.mode, "off")
                A.equal(prepared.ca_bundle_path, "/release/cacert.pem")
                A.equal(prepared.total_timeout_ms, 5000)
                local kinds = {}
                for _, component in ipairs(prepared.request.prompt_bundle.components) do
                    kinds[#kinds + 1] = component.kind
                end
                A.deep_equal(kinds, {
                    "runtime-purpose",
                    "global",
                    "model",
                    "synthetic-observation",
                })
                A.truthy(
                    prepared.request.prompt_bundle.digest,
                    "prompt digest is projected"
                )
                local serialized = prepared.request.prompt_bundle.messages[4].content
                A.contains(serialized, "Reply with READY.")
                A.falsy(serialized:find("never-in-request", 1, true))
                local wire = assert(value.prepare(start_spec(value.snapshots.view)))
                A.falsy(
                    tostring(wire.request.model_ref.endpoint):find("@", 1, true),
                    "endpoint carries no credentials"
                )
            end,
        },
        {
            name = "tool_set production transmits the inert registry on the wire",
            run = function()
                local adapter = assert(model.new(adapter_limits()))
                local value = builder({ adapter = adapter, tool_set = "production" })
                local prepared = assert(value.prepare(start_spec(value.snapshots.view)))
                A.equal(#prepared.request.tool_registry.tools, 8)
                A.equal(prepared.request.tool_registry.digest, "registry-1")
                A.equal(value.snapshots.transmitted_tools, "registry-1")
                local encoded = assert(adapter:encode(prepared.request, false))
                A.contains(encoded.body, '"tools"')
                A.contains(encoded.body, '"list"')

                local empty = builder({ adapter = adapter, tool_set = "none" })
                local empty_prepared = assert(empty.prepare(start_spec(empty.snapshots.view)))
                A.equal(empty.snapshots.transmitted_tools ~= "registry-1", true)
                local empty_encoded = assert(adapter:encode(empty_prepared.request, false))
                A.falsy(empty_encoded.body:find('"tools"', 1, true))
                A.contains(empty_encoded.body, '"stream":false')
            end,
        },
        {
            name = "builder rejects foreign purposes, stale views, and invalid options",
            run = function()
                local value = builder({})
                local spec = start_spec(value.snapshots.view)
                spec.purpose = "side"
                local wrong_purpose, purpose_error = value.prepare(spec)
                A.falsy(wrong_purpose)
                A.equal(purpose_error.code, "InvalidModelPurpose")

                spec = start_spec("view-stale")
                local stale, stale_error = value.prepare(spec)
                A.falsy(stale)
                A.equal(stale_error.code, "InvalidModelPurpose")

                spec = start_spec(value.snapshots.view)
                spec.continuation = { resumed = true }
                local continued, continuation_error = value.prepare(spec)
                A.falsy(continued)
                A.truthy(continuation_error)

                local invalid, invalid_error = model.new_self_test_request_builder({
                    adapter = assert(model.new(adapter_limits())),
                    prompt = prompt_service(),
                    generation = generation(),
                    tool_registry = registry(),
                    safety = { digest = sha256.hex },
                }, {
                    model_name = "Primary",
                    phase = "unexpected",
                    synthetic_observation = "text",
                    tool_set = "none",
                    default_connect_timeout_ms = 100,
                    default_request_timeout_ms = 5000,
                    maximum_request_time_ms = 8000,
                    default_retry_base_delay_ms = 5,
                    default_max_output_tokens = 256,
                })
                A.falsy(invalid)
                A.equal(invalid_error.code, "InvalidSelfTestRequestBuilder")

                local disabled = generation()
                disabled.models.Primary.enabled = false
                local offline, offline_error = model.new_self_test_request_builder({
                    adapter = assert(model.new(adapter_limits())),
                    prompt = prompt_service(),
                    generation = disabled,
                    tool_registry = registry(),
                    safety = { digest = sha256.hex },
                }, {
                    model_name = "Primary",
                    phase = "capability",
                    synthetic_observation = "text",
                    tool_set = "none",
                    default_connect_timeout_ms = 100,
                    default_request_timeout_ms = 5000,
                    maximum_request_time_ms = 8000,
                    default_retry_base_delay_ms = 5,
                    default_max_output_tokens = 256,
                })
                A.falsy(offline)
                A.equal(offline_error.code, "InvalidSelfTestRequestBuilder")
            end,
        },
        {
            name = "a scripted provider response completes the self-test request",
            run = function()
                local fixture = self_test_activity({
                    scripts = { { result = http_result(
                        '{"id":"response-1","choices":[{"message":'
                            .. '{"role":"assistant","content":"READY"},'
                            .. '"finish_reason":"stop"}]}'
                    ) } },
                })
                A.equal(#fixture.observed, 1)
                A.equal(fixture.observed[1].url, "https://api.example/v1/chat/completions")
                A.equal(fixture.observed[1].secret_headers[1].secret_id, "Model.Primary.Key")
                local response = fixture.output[#fixture.output]
                A.equal(response.kind, "response")
                A.equal(response.wrapper.canonical_body, "READY")
                A.equal(response.wrapper.normalized.finish_class, "stop")
                A.falsy(response.wrapper.normalized.incomplete)
            end,
        },
        {
            name = "a provider tool call round-trips with schema-validated arguments",
            run = function()
                local fixture = self_test_activity({
                    tool_set = "production",
                    scripts = { { result = http_result(
                        '{"id":"response-2","choices":[{"message":'
                            .. '{"role":"assistant","content":null,"tool_calls":'
                            .. '[{"id":"call-1","type":"function","function":'
                            .. '{"name":"list","arguments":"{\\"path\\":\\".\\"}"}}]},'
                            .. '"finish_reason":"tool_calls"}]}'
                    ) } },
                })
                local response = fixture.output[#fixture.output]
                A.equal(response.wrapper.normalized.finish_class, "tool_calls")
                A.equal(#response.wrapper.normalized.tool_calls, 1)
                A.equal(response.wrapper.normalized.tool_calls[1].name, "list")
                A.equal(
                    response.wrapper.normalized.tool_calls[1].canonical_arguments,
                    '{"path":"."}'
                )
                A.falsy(response.wrapper.normalized.execution_admitted)
            end,
        },
    },
}
