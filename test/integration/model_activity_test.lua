--[[
File: model_activity_test.lua
Date: 2026-08-30
Author: WaterRun
Description: Verifies the HTTP-gated logical Model request activity coordinator.
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

local MANIFEST = {
    identity = "activity-test-retry-v1",
    maximum_count = 3,
    exponent = 2,
    maximum_delay_ms = 1000,
    runtime_wait_cap_ms = 2000,
    deterministic_jitter_permille = 0,
}

local function activity_options()
    return {
        maximum_poll_events = 64,
        maximum_queued_events = 512,
        maximum_header_bytes = 4096,
        maximum_header_line_bytes = 1024,
        maximum_header_lines = 64,
        maximum_redirects = 3,
        maximum_turn_time_ms = 10000,
        maximum_runtime_time_ms = 10000,
        maximum_canonical_body_bytes = 32768,
        retry_manifest = MANIFEST,
    }
end

local function normalized_request(adapter, protocol, streaming, retry_count)
    local purpose = "main"
    return assert(adapter:normalize_request({
        request_id = "turn-1:request:1",
        purpose = purpose,
        model_ref = {
            name = "Primary",
            protocol = protocol,
            endpoint = "https://api.example/v1/messages",
            remote_model = protocol == "openai-chat" and "gpt-test" or "claude-test",
            capabilities_digest = "model-snapshot",
        },
        config_generation = "config-generation-1",
        prompt_bundle = {
            messages = { { role = "user", content = "hello" } },
        },
        model_view_manifest = {
            digest = "view-1",
            first_sequence = 1,
            last_sequence = 2,
            body = "<DurableFacts/>",
        },
        tool_registry = { version = "tools-1", digest = "registry-1", tools = {} },
        controls_schema = assert(adapter:controls_schema(purpose)),
        streaming = streaming,
        limits = protocol == "anthropic-messages" and { max_output_tokens = 64 } or {},
        retry_policy = { count = retry_count or 0, base_delay_ms = 5 },
    }))
end

local function result(settings)
    settings = settings or {}
    return {
        outcome = settings.outcome or "completed",
        exit_kind = settings.exit_kind or "exit-code",
        exit_code = settings.exit_code == nil and 0 or settings.exit_code,
        response_body = settings.body or "",
        response_headers = settings.headers or "",
        body_truncated = settings.body_truncated == true,
        descendants_proven_stopped = settings.descendants_proven_stopped ~= false,
    }
end

local function scripted_transport(network, scripts, observed)
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
            if script.pending and not cancelled then return {} end
            if emitted then return {} end
            emitted = true
            return {
                {
                    kind = "transport_terminal",
                    outcome = cancelled and "cancelled"
                        or (script.result.outcome or "completed"),
                },
            }
        end
        function port:cancel()
            cancelled = true
            return true
        end
        function port:join()
            if cancelled then
                return result({
                    outcome = "cancelled",
                    exit_kind = "cancelled",
                    exit_code = false,
                })
            end
            return script.result
        end
        function port:close() return true end
        return port
    end
    return service
end

local function fixture(protocol, streaming, retry_count, scripts)
    local cache = {}
    local model = load_module("model", cache)
    local network = load_module("network", cache)
    local adapter = assert(model.new(adapter_limits()))
    local request = normalized_request(adapter, protocol, streaming, retry_count)
    local observed, tick = {}, 0
    local transport = scripted_transport(network, scripts, observed)
    local activity = assert(model.new_activity({
        adapter = adapter,
        transport = transport,
        safety = { digest = sha256.hex },
        clock = {
            monotonic_now = function() return tick end,
            utc_now = function() return "2026-08-30T00:00:00Z" end,
        },
        requests = {
            prepare = function(spec)
                A.equal(spec.request_id, request.request_id)
                return {
                    request = request,
                    secret_source = false,
                    proxy = { mode = "off" },
                    ca_bundle_path = "/release/cacert.pem",
                    connect_timeout_ms = 100,
                    total_timeout_ms = 5000,
                }
            end,
        },
    }, activity_options()))
    local handle = assert(activity.start({
        request_id = request.request_id,
        turn_id = "turn-1",
        purpose = "main",
        continuation = false,
        view_manifest_ref = "view-1",
        progress_identity = "workspace-state-1",
    }))
    return {
        activity = activity,
        handle = handle,
        observed = observed,
        set_tick = function(value) tick = value end,
    }
end

local function collect(fixture, maximum)
    local output = {}
    for _ = 1, maximum or 16 do
        local batch = assert(fixture.activity.poll(64))
        for _, event in ipairs(batch) do output[#output + 1] = event end
        local status = fixture.activity.status()
        if status.state == "waiting" then fixture.set_tick(status.waiting_until) end
        if status.state == "idle" then return output end
    end
    error("model activity did not settle")
end

local function output_kinds(output)
    local result = {}
    for _, event in ipairs(output) do result[#result + 1] = event.kind end
    return result
end

return {
    name = "integration/model-activity",
    cases = {
        {
            name = "request builder reproduces durable snapshots without revealing secrets",
            run = function()
                local cache = {}
                local model = load_module("model", cache)
                local prompt = load_module("prompt", cache)
                local adapter = assert(model.new(adapter_limits()))
                local prompt_service = assert(prompt.new({ digest = sha256.hex }, {
                    maximum_component_bytes = 32768,
                    maximum_quoted_bytes = 16384,
                    maximum_total_bytes = 262144,
                    maximum_estimated_tokens = 262144,
                    maximum_components = 16,
                    maximum_source_bytes = 256,
                    maximum_version_bytes = 256,
                }))
                local registry = {
                    version = "tools-1",
                    digest = "registry-1",
                    tools = {
                        {
                            name = "read",
                            description = "read",
                            schema = { type = "object", additionalProperties = true },
                        },
                    },
                }
                local generation = {
                    id = "config-generation-1",
                    general = { system_prompt = "global" },
                    network = {
                        follow_proxy = true,
                        proxy_url_configured = true,
                        no_proxy = "localhost",
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
                            retry_count = 1,
                            retry_base_delay_ms = nil,
                        },
                    },
                    permissions = { Std = { system_prompt = "permission" } },
                    reveal_secret = function() return "never-called-by-builder" end,
                    secret_descriptors = function() return {} end,
                    scan_registered_secrets = function() return {} end,
                }
                local initial = assert(prompt_service:assemble({
                    purpose = "main",
                    config_generation = generation.id,
                    layers = {
                        global = {
                            source = "General.SystemPrompt",
                            version = generation.id,
                            text = "global",
                        },
                        model = {
                            source = "Model.Primary.SystemPrompt",
                            version = generation.id,
                            text = "model",
                        },
                        permission = {
                            source = "Permission.Std.SystemPrompt",
                            version = generation.id,
                            text = "permission",
                        },
                        context = {
                            source = "ContextPrompt",
                            version = generation.id,
                            text = "context",
                        },
                    },
                    input = { user_message = "hello" },
                    tool_mode = "registered",
                }))
                local views = {
                    resolve_view = function(digest)
                        if digest ~= "view-1" then return nil, { code = "StaleModelView" } end
                        return {
                            digest = digest,
                            first_sequence = 1,
                            last_sequence = 2,
                            body = "<DurableFacts/>",
                        }
                    end,
                }
                local builder = assert(model.new_request_builder({
                    adapter = adapter,
                    prompt = prompt_service,
                    views = views,
                    generation = generation,
                    tool_registry = registry,
                }, {
                    model_name = "Primary",
                    permission_name = "Std",
                    model_snapshot = "model-snapshot",
                    permission_snapshot = "permission-snapshot",
                    prompt_snapshot = initial.digest,
                    tool_registry_snapshot = registry.digest,
                    initial_message = "hello",
                    context_prompt = "context",
                    continuation_instruction = "Continue from the latest durable facts.",
                    default_connect_timeout_ms = 100,
                    default_request_timeout_ms = 5000,
                    default_retry_base_delay_ms = 5,
                }))
                local spec = {
                    request_id = "turn-1:request:1",
                    turn_id = "turn-1",
                    purpose = "main",
                    continuation = false,
                    view_manifest_ref = "view-1",
                    progress_identity = "workspace-state-1",
                }
                local prepared = assert(builder.prepare(spec))
                A.equal(prepared.request.prompt_bundle.digest, initial.digest)
                A.equal(prepared.request.model_ref.auth_secret_id, "Model.Primary.Key")
                A.equal(prepared.proxy.secret_id, "Network.ProxyUrl")
                A.equal(prepared.proxy.destination, "network-proxy")
                A.equal(prepared.request.retry_policy.base_delay_ms, 5)
                local wire, wire_error = adapter:encode(prepared.request)
                A.truthy(wire, wire_error and wire_error.code)
                A.equal(wire.secret_headers[1].secret_id, "Model.Primary.Key")
                A.contains(wire.body, "YACA-MODEL-VIEW/1")
                A.falsy(wire.body:find("never-called-by-builder", 1, true))
                spec.view_manifest_ref = "view-stale"
                local stale, stale_error = builder.prepare(spec)
                A.falsy(stale)
                A.equal(stale_error.code, "StaleModelView")
            end,
        },
        {
            name = "HTTP retry bodies stay behind status and one canonical response wins",
            run = function()
                local first = result({
                    headers = "HTTP/1.1 503 Service Unavailable\r\nRetry-After: 0\r\n\r\n",
                    body = '{"id":"must-not-parse","choices":[]}',
                })
                local second = result({
                    headers = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n",
                    body = '{"id":"response-1","choices":[{"message":' ..
                        '{"role":"assistant","content":"hello back"},' ..
                        '"finish_reason":"stop"}]}',
                })
                local f = fixture("openai-chat", "off", 1, {
                    { result = first },
                    { result = second },
                })
                local output = collect(f)
                A.equal(#f.observed, 2)
                A.equal(f.observed[1].body, f.observed[2].body)
                A.deep_equal(output_kinds(output), {
                    "canonical-event",
                    "adapter-event",
                    "adapter-event",
                    "adapter-event",
                    "response",
                })
                local wrapper = output[#output].wrapper
                A.equal(wrapper.canonical_body, "hello back")
                A.equal(wrapper.progress_identity, "workspace-state-1")
                A.equal(#wrapper.canonical_digest, 64)
                A.equal(wrapper.normalized.finish_class, "stop")
                A.falsy(wrapper.canonical_body:find("must-not-parse", 1, true))
            end,
        },
        {
            name = "try streaming falls back once only before a canonical event",
            run = function()
                local malformed = result({
                    headers = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n\r\n",
                    body = "not-an-sse-event",
                })
                local fallback = result({
                    headers = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n",
                    body = '{"id":"anthropic-1","content":[{"type":"text",' ..
                        '"text":"fallback ok"}],"stop_reason":"end_turn"}',
                })
                local f = fixture("anthropic-messages", "try", 0, {
                    { result = malformed },
                    { result = fallback },
                })
                local output = collect(f)
                A.equal(#f.observed, 2)
                A.contains(f.observed[1].body, '"stream":true')
                A.contains(f.observed[2].body, '"stream":false')
                A.equal(output[1].kind, "canonical-event")
                A.equal(output[#output].wrapper.canonical_body, "fallback ok")
                A.equal(output[#output].wrapper.normalized.finish_class, "stop")
            end,
        },
        {
            name = "active cancellation waits for proven transport settlement",
            run = function()
                local f = fixture("openai-chat", "off", 0, {
                    { pending = true, result = result() },
                })
                A.deep_equal(f.activity.cancel(f.handle, "user-cancel"), {
                    outcome = "pending",
                })
                local output = collect(f)
                A.equal(output[#output].kind, "response")
                A.equal(output[#output].wrapper.normalized.finish_class, "cancelled")
                A.equal(output[#output].wrapper.normalized.incomplete, false)
                for _, event in ipairs(output) do
                    A.falsy(event.kind == "canonical-event")
                end
            end,
        },
    },
}
