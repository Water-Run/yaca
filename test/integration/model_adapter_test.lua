--[[
File: model_adapter_test.lua
Date: 2026-08-29
Author: WaterRun
Description: Verifies canonical dual-provider request and event adapters.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

local function load_module(name, cache)
    cache = cache or {}
    if cache[name] then return cache[name] end
    local environment = {}
    for key, value in pairs(_ENV) do environment[key] = value end
    environment.require = function(dependency) return load_module(dependency, cache) end
    environment._G = environment
    setmetatable(environment, { __index = _ENV })
    local chunk, load_error = loadfile(YACA_TEST_ROOT .. "/src/" .. name .. ".lua", "t", environment)
    A.truthy(chunk, load_error)
    local result = chunk()
    cache[name] = result
    return result
end

local function limits(overrides)
    local result = {
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
    for key, value in pairs(overrides or {}) do result[key] = value end
    return result
end

local function controls()
    return {
        {
            id = "finish",
            wire_name = "yaca_finish",
            description = "finish",
            schema = { type = "object", additionalProperties = false, properties = {} },
        },
        {
            id = "ask-user",
            wire_name = "yaca_ask_user",
            description = "ask",
            schema = { type = "object", additionalProperties = false, properties = {
                question = { type = "string" },
            }, required = { "question" } },
        },
        {
            id = "refuse",
            wire_name = "yaca_refuse",
            description = "refuse",
            schema = { type = "object", additionalProperties = false, properties = {
                reason = { type = "string" },
            }, required = { "reason" } },
        },
    }
end

local function request(service, protocol, streaming, suffix, surface, schema)
    local remote_model = protocol == "openai-chat" and "gpt-test" or "claude-test"
    local tools = {}
    local control_list = {}
    if surface then
        tools[1] = {
            name = "read",
            description = "read",
            schema = schema or { type = "object", additionalProperties = true },
        }
        control_list = controls()
    end
    return assert(service:normalize_request({
        request_id = "request-" .. suffix,
        purpose = "main",
        model_ref = {
            name = "test",
            protocol = protocol,
            endpoint = protocol == "openai-chat"
                and "https://api.example/v1/chat/completions"
                or "https://api.example/v1/messages",
            remote_model = remote_model,
            capabilities_digest = "capabilities-1",
        },
        config_generation = "generation-1",
        prompt_bundle = { messages = { { role = "user", content = "hi" } } },
        model_view_manifest = { digest = "view-1", first_sequence = 1, last_sequence = 1 },
        tool_registry = { version = "tools-1", digest = "registry-1", tools = tools },
        controls_schema = { version = "controls-1", controls = control_list },
        streaming = streaming and "force" or "off",
        limits = protocol == "anthropic-messages" and { max_output_tokens = 64 } or {},
        retry_policy = { count = 0, base_delay_ms = 1 },
    }))
end

local function kinds(events)
    local result = {}
    for index, event in ipairs(events) do result[index] = event.kind end
    return result
end

local function append(target, events)
    for _, event in ipairs(events or {}) do target[#target + 1] = event end
end

local function drive(service, normalized, fixture, chunks)
    local session = assert(service:new_response(normalized))
    local events = {}
    if fixture.id == "auth_401_no_retry" then
        append(events, assert(session:http_error(401, "http-401", false)))
    else
        for _, chunk in ipairs(chunks or { fixture.response_bytes }) do
            append(events, assert(session:push(chunk)))
        end
        if fixture.id == "cancel_mid_stream" then
            append(events, assert(session:cancel("cancelled")))
        else
            local tail = assert(session:finish())
            append(events, tail)
        end
    end
    return events, assert(session:response())
end

local function fixture_source()
    return assert(loadfile(
        YACA_TEST_ROOT .. "/.develope-docs/contracts/fixtures/wire.lua",
        "t",
        _ENV
    ))()
end

return {
    name = "integration/model-adapter",
    cases = {
        {
            name = "every frozen OpenAI and Anthropic wire case has one canonical mapping",
            run = function()
                local service = assert(load_module("model").new(limits()))
                local fixture_set = fixture_source()
                local counts = { ["openai-chat"] = 0, ["anthropic-messages"] = 0 }
                for _, fixture in ipairs(fixture_set.cases) do
                    if fixture.protocol ~= "cross" then
                        counts[fixture.protocol] = counts[fixture.protocol] + 1
                        local streaming = fixture.request_bytes:find('"stream":true', 1, true) ~= nil

                        -- Synthetic response fixtures intentionally omit tool declarations from their
                        -- tiny request bytes. Verify the exact request projection independently, then
                        -- decode against the bound registry/control snapshot used by the response.
                        local projection = request(
                            service,
                            fixture.protocol,
                            streaming,
                            "projection-" .. fixture.id,
                            false
                        )
                        A.equal(assert(service:encode(projection)).body, fixture.request_bytes, fixture.id)

                        local normalized = request(
                            service,
                            fixture.protocol,
                            streaming,
                            "decode-" .. fixture.id,
                            true
                        )
                        local events, response = drive(service, normalized, fixture)
                        A.deep_equal(kinds(events), fixture.canonical_events, fixture.id)
                        A.equal(response.finish_class, fixture.finish_class, fixture.id)
                        A.equal(response.execution_admitted, false)
                        if fixture.control then
                            A.truthy(response.control, fixture.id)
                            A.equal(response.control.control, fixture.control, fixture.id)
                            A.equal(#response.tool_calls, 0, fixture.id)
                        else
                            A.falsy(response.control, fixture.id)
                        end
                        for _, event in ipairs(events) do
                            A.equal(event.request_id, normalized.request_id)
                        end
                    end
                end
                A.equal(counts["openai-chat"], 12)
                A.equal(counts["anthropic-messages"], 10)
            end,
        },
        {
            name = "synthetic archive is complete and remains explicitly non-qualifying",
            run = function()
                local archive = assert(loadfile(
                    YACA_TEST_ROOT .. "/test/golden/provider_wire/manifest.lua",
                    "t",
                    _ENV
                ))()
                local fixtures = fixture_source()
                local seen = { ["openai-chat"] = {}, ["anthropic-messages"] = {}, cross = {} }
                for _, fixture in ipairs(fixtures.cases) do seen[fixture.protocol][fixture.id] = true end
                for protocol, inventory in pairs(archive.inventory) do
                    for _, id in ipairs(inventory) do
                        A.truthy(seen[protocol][id], protocol .. "/" .. id)
                        seen[protocol][id] = nil
                    end
                    A.deep_equal(seen[protocol], {})
                end
                A.equal(archive.recorded_provider_bytes, false)
                A.equal(archive.target_proof.id, "TP-015")
                A.equal(archive.target_proof.status, "pending-target-recording")
                A.equal(archive.target_proof.qualifies_release, false)
            end,
        },
        {
            name = "stream parsing is invariant under one-byte provider chunking",
            run = function()
                local service = assert(load_module("model").new(limits()))
                for _, fixture in ipairs(fixture_source().cases) do
                    if fixture.id == "stream_tool_args_split" or fixture.id == "tool_input_json_delta" then
                        local chunks = {}
                        for index = 1, #fixture.response_bytes do
                            chunks[index] = fixture.response_bytes:sub(index, index)
                        end
                        local normalized = request(
                            service,
                            fixture.protocol,
                            true,
                            "chunked-" .. fixture.protocol,
                            true
                        )
                        local events, response = drive(service, normalized, fixture, chunks)
                        A.deep_equal(kinds(events), fixture.canonical_events)
                        A.equal(response.finish_class, fixture.finish_class)
                    end
                end
            end,
        },
        {
            name = "streaming tool arguments never complete or execute before response closure",
            run = function()
                local service = assert(load_module("model").new(limits()))
                local caller_schema = {
                    type = "object",
                    additionalProperties = false,
                    required = { "path" },
                    properties = { path = { type = "string" } },
                }
                local normalized = request(
                    service,
                    "openai-chat",
                    true,
                    "gate",
                    true,
                    caller_schema
                )
                caller_schema.required[1] = "mutated-after-admission"
                caller_schema.properties.path.type = "boolean"
                local session = assert(service:new_response(normalized))
                local first = assert(session:push(
                    'data: {"id":"r","choices":[{"delta":{"tool_calls":[' ..
                    '{"index":0,"id":"c","function":{"name":"read","arguments":"{\\"path\\":\\"a\\"}"}}]}}]}\n\n'
                ))
                A.deep_equal(kinds(first), {
                    "response_start", "tool_call_start", "tool_arguments_delta",
                })
                A.falsy(session:response())
                local second = assert(session:push(
                    'data: {"id":"r","choices":[{"delta":{},"finish_reason":"tool_calls"}]}\n\n'
                ))
                A.deep_equal(kinds(second), { "tool_call_complete", "response_finish" })
                local response = assert(session:response())
                A.equal(response.tool_calls[1].canonical_arguments, '{"path":"a"}')
                A.equal(response.tool_calls_validated, true)
                A.equal(response.execution_admitted, false)
                A.raises(function() second[1].name = "exec" end, "cannot be modified")
                A.raises(function() response.tool_calls[1].name = "exec" end, "cannot be modified")
            end,
        },
        {
            name = "schema identity controls and cross-protocol conflicts fail closed",
            run = function()
                local service = assert(load_module("model").new(limits()))
                local normalized = request(service, "openai-chat", true, "conflict", true)
                local mismatch = assert(service:registry_digest_event(normalized, "old"))
                A.deep_equal(kinds(mismatch), { "protocol_error" })
                A.equal(mismatch[1].error_id, "registry-digest-mismatch")
                A.equal(#assert(service:registry_digest_event(normalized, "registry-1")), 0)

                local session = assert(service:new_response(normalized))
                local events = assert(session:push(
                    'data: {"id":"mixed","choices":[{"delta":{"content":"x","tool_calls":[' ..
                    '{"index":0,"id":"c1","function":{"name":"read","arguments":""}},' ..
                    '{"index":1,"id":"c2","function":{"name":"yaca_finish","arguments":"{}"}}' ..
                    ']},"finish_reason":"tool_calls"}]}\n\n'
                ))
                A.deep_equal(kinds(events), {
                    "response_start", "text_delta", "tool_call_start", "control", "protocol_error",
                })
                local response = assert(session:response())
                A.equal(response.finish_class, "incomplete")
                A.equal(#response.tool_calls, 0)
                A.equal(response.execution_admitted, false)

                local ordered = assert(service:new_response(normalized))
                local before_text = assert(ordered:push(
                    'data: {"id":"ordered","choices":[{"delta":{"tool_calls":[' ..
                    '{"index":0,"id":"control","function":' ..
                    '{"name":"yaca_finish","arguments":"{}"}}]}}]}\n\n'
                ))
                A.deep_equal(kinds(before_text), { "response_start" })
                local after_text = assert(ordered:push(
                    'data: {"id":"ordered","choices":[{"delta":{"content":"after"},' ..
                    '"finish_reason":"tool_calls"}]}\n\n'
                ))
                A.deep_equal(kinds(after_text), { "control", "text_delta", "response_finish" })
                local ordered_response = assert(ordered:response())
                A.equal(ordered_response.content_blocks[1].kind, "control")
                A.equal(ordered_response.content_blocks[2].kind, "text")
            end,
        },
        {
            name = "tool argument and response content caps emit bounded protocol failures",
            run = function()
                local model = load_module("model")
                local argument_service = assert(model.new(limits({ maximum_tool_argument_bytes = 16 })))
                local normalized = request(argument_service, "openai-chat", true, "oversize", true)
                local session = assert(argument_service:new_response(normalized))
                local events = assert(session:push(
                    'data: {"id":"large","choices":[{"delta":{"tool_calls":[' ..
                    '{"index":0,"id":"c","function":{"name":"read","arguments":"0123456789abcdefX"}}' ..
                    ']}}]}\n\n'
                ))
                A.deep_equal({ events[2].kind, events[3].kind, events[4].kind }, {
                    "tool_call_start", "tool_arguments_delta", "protocol_error",
                })
                A.equal(events[4].error_id, "tool-argument-limit")
                A.equal(assert(session:response()).finish_class, "incomplete")

                local text_service = assert(model.new(limits({ maximum_text_bytes = 3 })))
                local text_request = request(text_service, "openai-chat", true, "text-limit", false)
                local text_session = assert(text_service:new_response(text_request))
                local text_events = assert(text_session:push(
                    'data: {"id":"text","choices":[{"delta":{"content":"four"}}]}\n\n'
                ))
                A.deep_equal(kinds(text_events), { "response_start", "protocol_error" })
                A.equal(text_events[2].error_id, "text-limit")
            end,
        },
        {
            name = "normalized requests reject secrets ambiguity and silent force fallback",
            run = function()
                local service = assert(load_module("model").new(limits()))
                local base = {
                    request_id = "request-invalid",
                    purpose = "main",
                    model_ref = {
                        name = "test",
                        protocol = "openai-chat",
                        endpoint = "https://api.example/v1/chat/completions",
                        remote_model = "gpt-test",
                        capabilities_digest = "capabilities-1",
                    },
                    config_generation = "g",
                    prompt_bundle = { messages = {} },
                    model_view_manifest = { digest = "v" },
                    tool_registry = { version = "tools-1", digest = "r", tools = {} },
                    controls_schema = { version = "c", controls = {} },
                    streaming = "force",
                    limits = {},
                    retry_policy = {},
                    key = "secret",
                }
                local rejected, secret_error = service:normalize_request(base)
                A.falsy(rejected)
                A.equal(secret_error.code, "SecretInRequest")
                base.key = nil
                base.unknown = true
                local unknown, unknown_error = service:normalize_request(base)
                A.falsy(unknown)
                A.equal(unknown_error.code, "InvalidRequest")
                base.unknown = nil
                local admitted = assert(service:normalize_request(base))
                local wire, fallback_error = service:encode(admitted, false)
                A.falsy(wire)
                A.equal(fallback_error.code, "StreamingRequired")
                A.raises(function() admitted.purpose = "side" end, "cannot be modified")

                base.request_id = "request-try"
                base.streaming = "try"
                local try_request = assert(service:normalize_request(base))
                local allowed = assert(service:streaming_fallback(try_request, false, 0))
                A.equal(allowed.allowed, true)
                A.equal(allowed.next_streaming, false)
                A.equal(assert(service:streaming_fallback(try_request, true, 0)).allowed, false)
                A.equal(assert(service:streaming_fallback(try_request, false, 1)).allowed, false)
                A.contains(assert(service:encode(try_request, false)).body, '"stream":false')
                local fallback = assert(service:new_response(try_request, false))
                assert(fallback:push(
                    '{"id":"fallback","choices":[{"message":{"role":"assistant",' ..
                    '"content":"ok"},"finish_reason":"stop"}]}'
                ))
                local fallback_events, fallback_response = fallback:finish()
                A.deep_equal(kinds(fallback_events), {
                    "response_start", "text_delta", "response_finish",
                })
                A.equal(fallback_response.finish_class, "stop")
                A.equal(service.capabilities.recorded_provider_wire, false)
                A.equal(service.capabilities.target_qualified, false)
            end,
        },
        {
            name = "auth and cancellation map without leaking or retrying credentials",
            run = function()
                local service = assert(load_module("model").new(limits()))
                local spec = {
                    request_id = "request-auth",
                    purpose = "main",
                    model_ref = {
                        name = "auth-model",
                        protocol = "openai-chat",
                        endpoint = "https://api.example/v1/chat/completions",
                        remote_model = "gpt-test",
                        capabilities_digest = "capabilities-1",
                        auth_secret_id = "secret:model-key",
                    },
                    config_generation = "g",
                    prompt_bundle = { messages = { { role = "user", content = "hi" } } },
                    model_view_manifest = { digest = "v" },
                    tool_registry = { version = "tools-1", digest = "r", tools = {} },
                    controls_schema = { version = "c", controls = {} },
                    streaming = "force",
                    limits = {},
                    retry_policy = {},
                }
                local normalized = assert(service:normalize_request(spec))
                local wire = assert(service:encode(normalized))
                A.equal(#wire.secret_headers, 1)
                A.equal(wire.secret_headers[1].secret_id, "secret:model-key")
                A.falsy(wire.body:find("secret:model-key", 1, true))

                local auth = assert(service:new_response(normalized))
                local auth_events = assert(auth:http_error(401, "authentication", true))
                A.deep_equal(kinds(auth_events), { "transport_error" })
                A.equal(auth_events[1].retryable, false)

                local cancel = assert(service:new_response(normalized))
                assert(cancel:push('data: {"id":"r","choices":[{"delta":{"content":"one"}}]}\n\n'))
                local cancel_events, response = cancel:cancel("user-cancel")
                A.deep_equal(kinds(cancel_events), { "transport_error", "response_finish" })
                A.equal(response.finish_class, "cancelled")
                A.equal(response.incomplete, false)
            end,
        },
    },
}
