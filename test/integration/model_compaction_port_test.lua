--[[
File: model_compaction_port_test.lua
Date: 2026-08-30
Author: WaterRun
Description: Verifies the no-tool compaction Model builder and response port.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()
local SHA = assert(loadfile(
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
local compact = load_module("compact", cache)
local json = load_module("json", cache)
local model = load_module("model", cache)
local prompt = load_module("prompt", cache)

local SUMMARY_SLOTS = {
    "goals_decisions",
    "constraints_permissions",
    "files_touched",
    "verification_evidence",
    "unknown_side_effects",
    "open_todos",
    "prompt_model_transitions",
}

local safety = {}

function safety.digest(bytes)
    return SHA.hex(bytes)
end

function safety.binding_digest(domain, fields)
    local parts = { tostring(#domain), ":", domain, "\0", tostring(#fields), "\0" }
    for _, field in ipairs(fields) do
        local value = field.value
        local kind = type(value)
        if kind == "boolean" then value = value and "true" or "false" end
        value = tostring(value)
        parts[#parts + 1] = table.concat({
            tostring(#field.name), ":", field.name, "=",
            kind, ":", tostring(#value), ":", value, "\0",
        })
    end
    return SHA.hex(table.concat(parts))
end

local function codec()
    return assert(json.new({
        maximum_bytes = 65536,
        maximum_depth = 32,
        maximum_nodes = 4096,
        maximum_string_bytes = 32768,
        maximum_number_bytes = 32,
    }))
end

local function model_options()
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
    return assert(prompt.new({ digest = safety.digest }, {
        maximum_component_bytes = 32768,
        maximum_quoted_bytes = 16384,
        maximum_total_bytes = 262144,
        maximum_estimated_tokens = 262144,
        maximum_components = 16,
        maximum_source_bytes = 256,
        maximum_version_bytes = 256,
    }))
end

local function generation()
    local value = {
        id = "config-generation-1",
        general = { system_prompt = "global" },
        network = {
            follow_proxy = false,
            no_proxy = "",
            ca_bundle_path = "/opt/yaca/bin/cacert.pem",
            connect_timeout_ms = nil,
        },
        models = {
            Primary = {
                enabled = true,
                tools_enabled = true,
                protocol = "openai-chat",
                endpoint = "https://api.example/v1/chat/completions",
                remote_model = "gpt-main",
                system_prompt = "main model",
                key_configured = false,
                adapter_options = {},
                streaming = "off",
                context_length = 4096,
                max_output_tokens = 512,
                retry_count = 0,
                retry_base_delay_ms = 0,
                request_timeout_ms = 1000,
            },
        },
        permissions = {
            Std = { system_prompt = "PERMISSION_INSTRUCTION_CANARY" },
        },
    }
    function value.reveal_secret() return nil, { code = "NoSecret" } end
    return value
end

local function compaction_spec(serial)
    local source = table.concat({
        "yaca-event-v1\n",
        "seq:1:1\n",
        "type:12:user_message\n",
        "value:11:hello world\n",
    })
    return {
        request_id = "compaction-1:request:" .. tostring(serial),
        compaction_id = "compaction-1",
        purpose = "compaction",
        attempt = serial,
        no_tools = true,
        config_snapshot = "durable-config-snapshot",
        model_snapshot = {
            id = "Primary",
            digest = "durable-model-snapshot",
            window_tokens = 4096,
            maximum_output_tokens = 256,
        },
        prompt_bundle_digest = "durable-prompt-snapshot",
        expected_manifest_digest = "view-old",
        source_first_seq = 1,
        source_last_seq = 2,
        source_digest = SHA.hex(source),
        source_bytes = source,
        summary_schema = "structured-summary-v1",
        summary_slots = SUMMARY_SLOTS,
        corrections = {},
        correction_reason = false,
        maximum_summary_bytes = 8192,
    }
end

local function fixture()
    local adapter = assert(model.new(model_options()))
    local codec_value = codec()
    local builder = assert(model.new_compaction_request_builder({
        adapter = adapter,
        prompt = prompt_service(),
        generation = generation(),
        codec = codec_value,
        safety = safety,
    }, {
        model_name = "Primary",
        permission_name = "Std",
        config_snapshot = "durable-config-snapshot",
        model_snapshot = "durable-model-snapshot",
        prompt_snapshot = "durable-prompt-snapshot",
        context_prompt = "CONTEXT_INSTRUCTION_CANARY",
        default_connect_timeout_ms = 100,
        default_request_timeout_ms = 5000,
        default_retry_base_delay_ms = 5,
        default_max_output_tokens = 512,
        maximum_source_bytes = 32768,
        maximum_summary_bytes = 8192,
        maximum_correction_bytes = 8192,
    }))
    return {
        adapter = adapter,
        builder = builder,
        codec = codec_value,
    }
end

local function valid_body(spec, goals_decisions)
    return table.concat({
        "{",
        '"constraints_permissions":"exact approval remains required",',
        '"files_touched":"src/model.lua",',
        '"goals_decisions":"', goals_decisions or "connect production compaction", '",',
        '"open_todos":"publish the durable Model view",',
        '"prompt_model_transitions":"Primary remains frozen",',
        '"schema_version":"', spec.summary_schema, '",',
        '"source_digest":"', spec.source_digest, '",',
        '"source_first_seq":', tostring(spec.source_first_seq), ',',
        '"source_last_seq":', tostring(spec.source_last_seq), ',',
        '"unknown_side_effects":"none observed",',
        '"verification_evidence":"deterministic fake provider"',
        "}",
    })
end

local function compaction_port(
    fixture_value,
    body,
    overrides,
    cancel_outcome,
    summary_encoder
)
    local prepared = {}
    local active_handle
    local activity = {}

    function activity.start(specification)
        prepared[#prepared + 1] = assert(fixture_value.builder.prepare(specification))
        active_handle = { request_id = specification.request_id }
        return active_handle
    end

    function activity.cancel(handle)
        if handle ~= active_handle then return { outcome = "unknown" } end
        local outcome = cancel_outcome or "cancelled"
        if outcome == "cancelled" then active_handle = nil end
        return { outcome = outcome }
    end

    function activity.poll()
        if not active_handle then return {} end
        local request_id = active_handle.request_id
        active_handle = nil
        local normalized = {
            content_blocks = { { kind = "text", text = body } },
            tool_calls = {},
            finish_class = "stop",
            incomplete = false,
            tool_calls_validated = true,
            execution_admitted = false,
            usage = { input = 120, output = 40, total = 160 },
        }
        for key, value in pairs(overrides or {}) do normalized[key] = value end
        return { {
            kind = "response",
            request_id = request_id,
            wrapper = {
                request_id = request_id,
                canonical_body = body,
                canonical_digest = SHA.hex(body),
                progress_identity = "compaction-progress",
                normalized = normalized,
            },
        } }
    end

    function activity.status()
        return { state = active_handle and "active" or "idle" }
    end

    local port = assert(model.new_compaction_port({
        activity = activity,
        builder = fixture_value.builder,
        safety = safety,
        codec = fixture_value.codec,
        summary = { encode = summary_encoder or compact.encode_summary },
    }, {
        maximum_poll_events = 16,
        maximum_summary_bytes = 8192,
    }))
    return port, prepared
end

return {
    name = "integration/model-compaction-port",
    cases = {
        {
            name = "builder sends one quoted source with no tools or controls",
            run = function()
                local f = fixture()
                local specification = compaction_spec(1)
                local activity_spec = assert(f.builder.bind(specification))
                local prepared = assert(f.builder.prepare(activity_spec))
                A.equal(prepared.request.purpose, "compaction")
                A.equal(prepared.request.model_ref.name, "Primary")
                A.equal(
                    prepared.request.model_ref.capabilities_digest,
                    "durable-model-snapshot"
                )
                A.equal(#prepared.request.tool_registry.tools, 0)
                A.equal(#prepared.request.controls_schema.controls, 0)
                A.equal(prepared.request.model_view_manifest.body, specification.source_bytes)
                A.equal(prepared.request.model_view_manifest.digest, specification.source_digest)
                A.equal(prepared.request.limits.max_output_tokens, 256)
                A.equal(f.builder.snapshots.config, "durable-config-snapshot")
                A.contains(
                    prepared.request.prompt_bundle.components[1].text,
                    "requested StructuredSummary"
                )
                A.contains(
                    prepared.request.prompt_bundle.components[4].text,
                    "yaca-compaction-input-v1"
                )
                local wire = assert(f.adapter:encode(prepared.request))
                A.falsy(wire.body:find('"tools"', 1, true))
                local _, source_occurrences = wire.body:gsub("hello world", "")
                A.equal(source_occurrences, 1)
                A.falsy(wire.body:find("PERMISSION_INSTRUCTION_CANARY", 1, true))
                A.falsy(wire.body:find("CONTEXT_INSTRUCTION_CANARY", 1, true))
                assert(f.builder.release(specification.request_id))

                specification.config_snapshot = "forged-config-snapshot"
                local rebound, binding_error = f.builder.bind(specification)
                A.falsy(rebound)
                A.equal(binding_error.code, "InvalidCompactionModelRequest")

                specification.config_snapshot = "durable-config-snapshot"
                specification.source_bytes = specification.source_bytes .. "forged"
                rebound, binding_error = f.builder.bind(specification)
                A.falsy(rebound)
                A.equal(binding_error.code, "CompactionSourceMismatch")
            end,
        },
        {
            name = "valid JSON becomes the exact canonical structured summary",
            run = function()
                local f = fixture()
                local specification = compaction_spec(1)
                local port, prepared = compaction_port(
                    f,
                    valid_body(specification)
                )
                local handle = assert(port.start(specification))
                specification.model_snapshot.digest = "forged"
                A.equal(
                    f.builder.binding(handle.request_id)
                        .specification.model_snapshot.digest,
                    "durable-model-snapshot"
                )
                local response = assert(port.poll(16))[1].response
                A.equal(response.completion.incomplete, false)
                A.equal(response.completion.finish_class, "stop")
                A.equal(response.completion.tool_call_count, 0)
                A.equal(response.completion.control, false)
                A.equal(response.summary.files_touched, "src/model.lua")
                A.matches(response.canonical_body, "^yaca%-structured%-summary%-v1")
                A.equal(response.canonical_digest, SHA.hex(response.canonical_body))
                A.equal(response.usage.input_tokens, 120)
                A.equal(response.usage.output_tokens, 40)
                A.equal(response.usage.estimated, false)
                A.equal(#prepared[1].request.tool_registry.tools, 0)
                A.equal(port.status().state, "idle")
            end,
        },
        {
            name = "malformed incomplete and tool-bearing responses remain rejectable",
            run = function()
                local cases = {
                    {
                        body = '{"goals_decisions":"missing fields"}',
                        overrides = {},
                        expected = "summary",
                    },
                    {
                        body = false,
                        overrides = {
                            incomplete = true,
                            finish_class = "incomplete",
                        },
                        expected = "incomplete",
                    },
                    {
                        body = false,
                        overrides = { tool_calls = { { name = "exec" } } },
                        expected = "tools",
                    },
                }
                for index, case in ipairs(cases) do
                    local f = fixture()
                    local specification = compaction_spec(index)
                    local body = case.body or valid_body(specification)
                    local port = compaction_port(f, body, case.overrides)
                    assert(port.start(specification))
                    local response = assert(port.poll(16))[1].response
                    if case.expected == "summary" then
                        A.equal(response.summary, false)
                    elseif case.expected == "incomplete" then
                        A.equal(response.completion.incomplete, true)
                        A.equal(response.completion.finish_class, "incomplete")
                    else
                        A.equal(response.completion.tool_call_count, 1)
                    end
                end
            end,
        },
        {
            name = "canonical envelope overflow remains a rejectable response",
            run = function()
                local f = fixture()
                local specification = compaction_spec(1)
                local body = valid_body(specification, string.rep("x", 7900))
                local port = compaction_port(f, body)
                assert(port.start(specification))
                local events, poll_error = port.poll(16)
                A.truthy(events, poll_error and poll_error.code)
                A.equal(events[1].response.summary, false)
                A.equal(events[1].response.canonical_body, body)
                A.equal(port.status().state, "idle")
            end,
        },
        {
            name = "internal summary encoding failure releases terminal binding",
            run = function()
                local f = fixture()
                local specification = compaction_spec(1)
                local port = compaction_port(
                    f,
                    valid_body(specification),
                    nil,
                    nil,
                    function() error("summary-encoder-fault") end
                )
                assert(port.start(specification))
                local events, poll_error = port.poll(16)
                A.falsy(events)
                A.equal(poll_error.code, "CompactionSummaryEncoding")
                A.equal(port.status().state, "idle")
                A.equal(f.builder.binding(specification.request_id), false)
            end,
        },
        {
            name = "cancel releases the exact binding for a later request",
            run = function()
                local f = fixture()
                local first = compaction_spec(1)
                local port = compaction_port(f, valid_body(first))
                local handle = assert(port.start(first))
                A.equal(assert(port.cancel(handle, "user-cancel")).outcome, "cancelled")
                A.equal(port.status().state, "idle")
                local second = compaction_spec(2)
                assert(port.start(second))
                A.truthy(assert(port.poll(16))[1].response.summary)
            end,
        },
    },
}
