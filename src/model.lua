--[[
File: model.lua
Date: 2026-08-29
Author: WaterRun
Description: Maps bounded OpenAI Chat and Anthropic Messages wire data to canonical model events.
]]

local json = require("json")
local network = require("network")
local text = require("text")

local M = {}

local PURPOSES = {
    main = true,
    side = true,
    ["action-review"] = true,
    ["termination-review"] = true,
    compaction = true,
    ["self-test"] = true,
    ["context-name"] = true,
}

local STREAMING_MODES = { force = true, try = true, off = true }
local PROTOCOLS = { ["openai-chat"] = true, ["anthropic-messages"] = true }
local CONTROL_NAMES = {
    yaca_finish = "finish",
    yaca_ask_user = "ask-user",
    yaca_refuse = "refuse",
}
local DIRECT_TOOL_NAMES = {
    list = true,
    read = true,
    search = true,
    write = true,
    patch = true,
    rename = true,
    delete = true,
    exec = true,
}

local REQUIRED_REQUEST_FIELDS = {
    "request_id",
    "purpose",
    "model_ref",
    "config_generation",
    "prompt_bundle",
    "model_view_manifest",
    "tool_registry",
    "controls_schema",
    "streaming",
    "limits",
    "retry_policy",
}

local FORBIDDEN_REQUEST_FIELDS = {
    key = true,
    authorization = true,
    proxy_credentials = true,
    private_source_digest = true,
}

local function forbidden_request_field(key)
    return type(key) == "string" and FORBIDDEN_REQUEST_FIELDS[key:lower()] == true
end

local OPTION_NAMES = {
    "maximum_json_bytes",
    "maximum_json_depth",
    "maximum_json_nodes",
    "maximum_string_bytes",
    "maximum_number_bytes",
    "maximum_sse_line_bytes",
    "maximum_sse_event_bytes",
    "maximum_sse_buffered_bytes",
    "maximum_sse_events_per_push",
    "maximum_response_bytes",
    "maximum_text_bytes",
    "maximum_reasoning_bytes",
    "maximum_tool_calls",
    "maximum_tool_argument_bytes",
    "maximum_total_tool_argument_bytes",
    "maximum_content_blocks",
    "maximum_events",
}

local function failure(code, message, detail)
    local result = { code = code, message = message }
    if detail ~= nil then result.detail = detail end
    return result
end

local function readonly(values, label)
    return setmetatable({}, {
        __index = values,
        __newindex = function(_, key)
            error((label or "readonly value") .. " cannot be modified: " .. tostring(key), 2)
        end,
        __pairs = function() return next, values, nil end,
        __len = function() return #values end,
        __metatable = "locked",
    })
end

local function dense_count(values)
    if type(values) ~= "table" then return nil end
    local count = 0
    for key in pairs(values) do
        if math.type(key) ~= "integer" or key < 1 then return nil end
        count = count + 1
    end
    for index = 1, count do
        if values[index] == nil then return nil end
    end
    return count
end

local function valid_integer(value, minimum)
    return math.type(value) == "integer" and value >= minimum
end

local function valid_token(value, maximum)
    return type(value) == "string"
        and value ~= ""
        and #value <= maximum
        and not value:find("[%z\r\n]")
end

local function valid_endpoint(value)
    if type(value) ~= "string" or value == "" or value:find("[%z\r\n]")
        or value:find("#", 1, true)
    then
        return false
    end
    local scheme, authority = value:match("^([A-Za-z][A-Za-z0-9+%.%-]*)://([^/%?#]+)")
    return scheme ~= nil
        and (scheme:lower() == "http" or scheme:lower() == "https")
        and authority ~= ""
        and not authority:find("@", 1, true)
end

local function freeze(value, label, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then error("cannot freeze a cyclic value", 2) end
    seen[value] = true
    local copy = {}
    for key, item in pairs(value) do copy[key] = freeze(item, label, seen) end
    seen[value] = nil
    return readonly(copy, label)
end

local function copy_bounded(value, options, state, depth)
    state = state or { nodes = 0, bytes = 0 }
    depth = depth or 1
    state.nodes = state.nodes + 1
    if state.nodes > options.maximum_json_nodes or depth > options.maximum_json_depth then
        return nil, failure("RequestLimit", "normalized request exceeds its structural limit")
    end
    local value_type = type(value)
    if value_type == "string" then
        state.bytes = state.bytes + #value
        if state.bytes > options.maximum_json_bytes then
            return nil, failure("RequestLimit", "normalized request exceeds its total byte limit")
        end
        if #value > options.maximum_string_bytes then
            return nil, failure("RequestLimit", "normalized request string exceeds its limit")
        end
        local valid, utf8_error = text.validate_utf8(value)
        if not valid then return nil, utf8_error end
        return value
    end
    if value_type == "number" or value_type == "boolean" or value == nil then return value end
    if value_type ~= "table" then
        return nil, failure("InvalidRequest", "normalized request contains an unsupported value")
    end
    local result = {}
    for key, item in pairs(value) do
        if type(key) ~= "string" and math.type(key) ~= "integer" then
            return nil, failure("InvalidRequest", "normalized request contains an invalid key")
        end
        if type(key) == "string" then
            state.bytes = state.bytes + #key
            if state.bytes > options.maximum_json_bytes then
                return nil, failure("RequestLimit", "normalized request exceeds its total byte limit")
            end
            local valid, utf8_error = text.validate_utf8(key)
            if not valid then return nil, utf8_error end
        end
        local copied, copy_error = copy_bounded(item, options, state, depth + 1)
        if copied == nil and item ~= nil then return nil, copy_error end
        result[key] = copied
    end
    return result
end

local function json_plain(value)
    local kind = json.kind(value)
    if kind == "null" then return nil end
    if kind == "number" then return assert(json.number_lexeme(value)) end
    if kind ~= "array" and kind ~= "object" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = json_plain(item) end
    return result
end

local ARRAY_KEYS = {
    messages = true,
    tools = true,
    required = true,
    enum = true,
    anyOf = true,
    oneOf = true,
    allOf = true,
    content = true,
}

local function to_json_value(value, hint)
    if json.kind(value) then return value end
    local value_type = type(value)
    if value_type == "string" or value_type == "boolean" then return value end
    if value == nil then return json.null end
    if value_type == "number" then
        if math.type(value) ~= "integer" then
            return nil, failure("InvalidWireValue", "wire numbers must be exact integers")
        end
        return json.number(tostring(value))
    end
    if value_type ~= "table" then
        return nil, failure("InvalidWireValue", "wire value contains an unsupported type")
    end
    local count = dense_count(value)
    if count ~= nil and (count > 0 or hint == "array") then
        local items = {}
        for index = 1, count do
            local converted, convert_error = to_json_value(value[index])
            if not converted then return nil, convert_error end
            items[index] = converted
        end
        return json.array(items)
    end
    local items = {}
    for key, item in pairs(value) do
        if type(key) ~= "string" then
            return nil, failure("InvalidWireValue", "wire object keys must be strings")
        end
        local converted, convert_error = to_json_value(item, ARRAY_KEYS[key] and "array" or nil)
        if not converted then return nil, convert_error end
        items[key] = converted
    end
    return json.object(items)
end

local function encode_value(codec, value, hint)
    local converted, convert_error = to_json_value(value, hint)
    if not converted then return nil, convert_error end
    local kind = json.kind(converted)
    if kind == "object" or kind == "array" then return codec.write(converted) end
    local wrapper = assert(json.object({ v = converted }))
    local encoded, encode_error = codec.write(wrapper)
    if not encoded then return nil, encode_error end
    return encoded:sub(6, -2)
end

local function encode_messages(codec, messages)
    if dense_count(messages) == nil then
        return nil, failure("InvalidPromptBundle", "prompt messages must be a dense array")
    end
    local result, byte_count = { "[" }, 1
    local function add(bytes)
        byte_count = byte_count + #bytes
        if byte_count > codec.limits.maximum_bytes then
            return nil, failure("WireRequestLimit", "provider messages exceed their byte limit")
        end
        result[#result + 1] = bytes
        return true
    end
    for index, message in ipairs(messages) do
        if type(message) ~= "table"
            or type(message.role) ~= "string"
            or type(message.content) ~= "string"
        then
            return nil, failure("InvalidPromptBundle", "C21 messages require string role and content")
        end
        if index > 1 and not add(",") then
            return nil, failure("WireRequestLimit", "provider messages exceed their byte limit")
        end
        local role, role_error = encode_value(codec, message.role)
        if not role then return nil, role_error end
        local content, content_error = encode_value(codec, message.content)
        if not content then return nil, content_error end
        local item = "{\"role\":" .. role .. ",\"content\":" .. content .. "}"
        local admitted, limit_error = add(item)
        if not admitted then return nil, limit_error end
    end
    local admitted, limit_error = add("]")
    if not admitted then return nil, limit_error end
    return table.concat(result)
end

local function validate_options(options)
    if type(options) ~= "table" then
        return nil, failure("InvalidModelOptions", "model release limits are required")
    end
    local allowed, result = {}, {}
    for _, name in ipairs(OPTION_NAMES) do allowed[name] = true end
    for key in pairs(options) do
        if not allowed[key] then
            return nil, failure("InvalidModelOptions", "model options contain an unknown field")
        end
    end
    for _, name in ipairs(OPTION_NAMES) do
        if not valid_integer(options[name], 1) then
            return nil, failure("InvalidModelOptions", "all model limits must be positive integers")
        end
        result[name] = options[name]
    end
    if result.maximum_sse_line_bytes > result.maximum_sse_buffered_bytes
        or result.maximum_sse_event_bytes > result.maximum_sse_buffered_bytes
        or result.maximum_sse_buffered_bytes > result.maximum_response_bytes
        or result.maximum_tool_argument_bytes > result.maximum_total_tool_argument_bytes
        or result.maximum_text_bytes > result.maximum_response_bytes
        or result.maximum_reasoning_bytes > result.maximum_response_bytes
        or result.maximum_events < 2
    then
        return nil, failure("InvalidModelOptions", "model sub-limits are inconsistent")
    end
    return result
end

local function normalize_registry(registry, options)
    if type(registry) ~= "table" or not valid_token(registry.version, 128)
        or not valid_token(registry.digest, 256)
        or dense_count(registry.tools) == nil
    then
        return nil, failure("InvalidToolRegistry", "versioned tool registry is required")
    end
    local lookup, names = {}, {}
    for _, tool in ipairs(registry.tools) do
        if type(tool) ~= "table"
            or not valid_token(tool.name, 128)
            or type(tool.schema) ~= "table"
            or (tool.description ~= nil and type(tool.description) ~= "string")
            or not DIRECT_TOOL_NAMES[tool.name]
            or CONTROL_NAMES[tool.name]
            or lookup[tool.name]
        then
            return nil, failure("InvalidToolRegistry", "tool registry entry is invalid or duplicated")
        end
        lookup[tool.name] = tool
        names[#names + 1] = tool.name
    end
    return { public = registry, lookup = lookup, names = names }
end

local function normalize_controls(controls)
    if type(controls) ~= "table" or not valid_token(controls.version, 128)
        or dense_count(controls.controls) == nil
    then
        return nil, failure("InvalidControlSchema", "versioned controls schema is required")
    end
    local lookup = {}
    for _, control in ipairs(controls.controls) do
        local wire_name = type(control) == "table" and control.wire_name or nil
        local canonical = CONTROL_NAMES[wire_name]
        if not canonical or lookup[wire_name]
            or (control.id ~= nil and control.id ~= canonical)
            or (control.schema ~= nil and type(control.schema) ~= "table")
        then
            return nil, failure("InvalidControlSchema", "control schema entry is invalid or duplicated")
        end
        lookup[wire_name] = canonical
    end
    return { public = controls, lookup = lookup }
end

local function validate_request_shape(spec, options)
    if type(spec) ~= "table" then
        return nil, failure("InvalidRequest", "normalized request must be a table")
    end
    local allowed = {}
    for _, name in ipairs(REQUIRED_REQUEST_FIELDS) do allowed[name] = true end
    for key in pairs(spec) do
        if forbidden_request_field(key) then
            return nil, failure("SecretInRequest", "normalized request contains a forbidden secret field")
        end
        if not allowed[key] then
            return nil, failure("InvalidRequest", "normalized request contains an unknown field")
        end
    end
    for _, name in ipairs(REQUIRED_REQUEST_FIELDS) do
        if spec[name] == nil then
            return nil, failure("InvalidRequest", "normalized request omits " .. name)
        end
    end
    if not valid_token(spec.request_id, 128) or not PURPOSES[spec.purpose]
        or not STREAMING_MODES[spec.streaming]
        or not valid_token(spec.config_generation, 256)
        or type(spec.model_ref) ~= "table"
        or type(spec.prompt_bundle) ~= "table"
        or type(spec.model_view_manifest) ~= "table"
        or type(spec.limits) ~= "table"
        or type(spec.retry_policy) ~= "table"
    then
        return nil, failure("InvalidRequest", "normalized request identity or snapshot is invalid")
    end
    for key in pairs(spec.model_ref) do
        if forbidden_request_field(key) then
            return nil, failure("SecretInRequest", "model snapshot contains a forbidden secret field")
        end
    end
    if not valid_token(spec.model_ref.name, 128)
        or not valid_endpoint(spec.model_ref.endpoint)
        or #spec.model_ref.endpoint > options.maximum_string_bytes
        or not valid_token(spec.model_ref.capabilities_digest, 256)
        or not PROTOCOLS[spec.model_ref.protocol]
        or not valid_token(spec.model_ref.remote_model, options.maximum_string_bytes)
    then
        return nil, failure("InvalidModelRef", "model snapshot protocol or remote model is invalid")
    end
    if spec.model_ref.auth_secret_id ~= nil
        and not valid_token(spec.model_ref.auth_secret_id, 256)
    then
        return nil, failure("InvalidModelRef", "model secret reference is invalid")
    end
    if dense_count(spec.prompt_bundle.messages) == nil then
        return nil, failure("InvalidPromptBundle", "prompt bundle messages must be a dense array")
    end
    if spec.prompt_bundle.system ~= nil and type(spec.prompt_bundle.system) ~= "string" then
        return nil, failure("InvalidPromptBundle", "prompt bundle system value must be text")
    end
    if not valid_token(spec.model_view_manifest.digest, 256) then
        return nil, failure("InvalidModelViewManifest", "model view manifest digest is required")
    end
    local registry, registry_error = normalize_registry(spec.tool_registry, options)
    if not registry then return nil, registry_error end
    local controls, controls_error = normalize_controls(spec.controls_schema)
    if not controls then return nil, controls_error end
    local copy, copy_error = copy_bounded(spec, options)
    if not copy then return nil, copy_error end
    -- Rebuild every lookup from the admitted copy. The caller-owned schema tables
    -- must never remain an authority after the immutable request snapshot exists.
    registry = assert(normalize_registry(copy.tool_registry, options))
    controls = assert(normalize_controls(copy.controls_schema))
    return { public = copy, registry = registry, controls = controls }
end

local function nonnegative_json_integer(value)
    if json.kind(value) ~= "number" then return nil end
    local lexeme = assert(json.number_lexeme(value))
    if not lexeme:match("^%d+$") then return nil end
    local number = tonumber(lexeme)
    if not number or math.type(number) ~= "integer" or number < 0 then return nil end
    return number
end

local function schema_scalar_equal(value, expected)
    local kind = json.kind(value)
    if kind == "number" and type(expected) == "number" then
        return tonumber(assert(json.number_lexeme(value))) == expected
    end
    if kind == "number" and type(expected) == "string" then
        return assert(json.number_lexeme(value)) == expected
    end
    if kind == "null" then return expected == nil end
    return value == expected
end

local function validate_schema(value, schema, path, depth)
    path, depth = path or "$", depth or 1
    if depth > 32 or type(schema) ~= "table" then return nil, "invalid-schema" end
    local expected = schema.type
    local kind = json.kind(value)
    if expected == "integer" then
        if kind ~= "number" or not assert(json.number_lexeme(value)):match("^-?%d+$") then
            return nil, path .. ":type"
        end
    elseif expected == "number" then
        if kind ~= "number" then return nil, path .. ":type" end
    elseif expected ~= nil and kind ~= expected then
        return nil, path .. ":type"
    end
    if type(schema.enum) == "table" then
        local matched = false
        for _, candidate in ipairs(schema.enum) do
            if schema_scalar_equal(value, candidate) then matched = true break end
        end
        if not matched then return nil, path .. ":enum" end
    end
    if kind == "string" then
        if valid_integer(schema.minLength, 0) and #value < schema.minLength then
            return nil, path .. ":minLength"
        end
        if valid_integer(schema.maxLength, 0) and #value > schema.maxLength then
            return nil, path .. ":maxLength"
        end
    elseif kind == "object" then
        local required = schema.required or {}
        if dense_count(required) == nil then return nil, "invalid-schema" end
        for _, name in ipairs(required) do
            if type(name) ~= "string" or value[name] == nil then return nil, path .. ":required" end
        end
        local properties = schema.properties or {}
        if type(properties) ~= "table" then return nil, "invalid-schema" end
        for key, item in pairs(value) do
            local child = properties[key]
            if child then
                local valid, reason = validate_schema(item, child, path .. "." .. key, depth + 1)
                if not valid then return nil, reason end
            elseif schema.additionalProperties == false then
                return nil, path .. ":additionalProperties"
            end
        end
    elseif kind == "array" then
        if valid_integer(schema.maxItems, 0) and #value > schema.maxItems then
            return nil, path .. ":maxItems"
        end
        if schema.items then
            for index, item in ipairs(value) do
                local valid, reason = validate_schema(
                    item,
                    schema.items,
                    path .. "[" .. tostring(index) .. "]",
                    depth + 1
                )
                if not valid then return nil, reason end
            end
        end
    end
    return true
end

local function validate_control_payload(control, payload)
    if json.kind(payload) ~= "object" then return nil, "payload-type" end
    local allowed, required = {}, nil
    if control == "finish" then
        allowed.summary = true
        if payload.summary ~= nil and type(payload.summary) ~= "string" then return nil, "summary" end
    elseif control == "ask-user" then
        allowed.question, required = true, "question"
    elseif control == "refuse" then
        allowed.reason, required = true, "reason"
    else
        return nil, "control"
    end
    if required and (type(payload[required]) ~= "string" or payload[required] == "") then
        return nil, required
    end
    for key in pairs(payload) do if not allowed[key] then return nil, "unknown-field" end end
    return true
end

local function map_openai_finish(value)
    local mapping = {
        stop = "stop",
        length = "length",
        content_filter = "content_filter",
        tool_calls = "tool_calls",
        function_call = "tool_calls",
        refusal = "refusal",
    }
    return mapping[value]
end

local function map_anthropic_finish(value)
    local mapping = {
        end_turn = "stop",
        stop_sequence = "stop",
        max_tokens = "length",
        tool_use = "tool_calls",
        refusal = "refusal",
    }
    return mapping[value]
end

local function make_event(request_id, kind, fields)
    local event = { kind = kind, request_id = request_id }
    for key, value in pairs(fields or {}) do event[key] = value end
    return freeze(event, "model event")
end

local function encode_tools(codec, request_data, protocol)
    local projected = {}
    local function add(name, description, schema)
        if protocol == "openai-chat" then
            projected[#projected + 1] = {
                type = "function",
                ["function"] = { name = name, description = description, parameters = schema },
            }
        else
            projected[#projected + 1] = {
                name = name,
                description = description,
                input_schema = schema,
            }
        end
    end
    for _, tool in ipairs(request_data.tool_registry.tools) do
        add(tool.name, tool.description or "", tool.schema)
    end
    for _, control in ipairs(request_data.controls_schema.controls) do
        add(control.wire_name, control.description or "", control.schema or {
            type = "object",
            additionalProperties = false,
            properties = {},
        })
    end
    if #projected == 0 then return nil end
    return encode_value(codec, projected, "array")
end

local function encode_request(codec, request_data, streaming)
    local model_ref = request_data.model_ref
    local protocol = model_ref.protocol
    local messages, messages_error = encode_messages(codec, request_data.prompt_bundle.messages)
    if not messages then return nil, messages_error end
    local remote_model, model_error = encode_value(codec, model_ref.remote_model)
    if not remote_model then return nil, model_error end
    local stream = streaming and "true" or "false"
    local tools, tools_error = encode_tools(codec, request_data, protocol)
    if tools_error then return nil, tools_error end
    local body
    if protocol == "openai-chat" then
        local fields = {
            "\"model\":" .. remote_model,
            "\"messages\":" .. messages,
        }
        if request_data.limits.max_output_tokens ~= nil then
            if not valid_integer(request_data.limits.max_output_tokens, 1) then
                return nil, failure("InvalidRequestLimit", "max_output_tokens must be positive")
            end
            fields[#fields + 1] = "\"max_tokens\":" .. tostring(request_data.limits.max_output_tokens)
        end
        fields[#fields + 1] = "\"stream\":" .. stream
        if tools then fields[#fields + 1] = "\"tools\":" .. tools end
        body = "{" .. table.concat(fields, ",") .. "}"
    else
        if not valid_integer(request_data.limits.max_output_tokens, 1) then
            return nil, failure("InvalidRequestLimit", "Anthropic requires max_output_tokens")
        end
        local fields = {
            "\"model\":" .. remote_model,
            "\"max_tokens\":" .. tostring(request_data.limits.max_output_tokens),
            "\"messages\":" .. messages,
            "\"stream\":" .. stream,
        }
        if request_data.prompt_bundle.system ~= nil and request_data.prompt_bundle.system ~= "" then
            local system, system_error = encode_value(codec, request_data.prompt_bundle.system)
            if not system then return nil, system_error end
            fields[#fields + 1] = "\"system\":" .. system
        end
        if tools then fields[#fields + 1] = "\"tools\":" .. tools end
        body = "{" .. table.concat(fields, ",") .. "}"
    end
    if #body > codec.limits.maximum_bytes then
        return nil, failure("WireRequestLimit", "provider request exceeds its byte limit")
    end
    local headers = {
        { name = "Content-Type", value = "application/json" },
        { name = "Accept", value = streaming and "text/event-stream" or "application/json" },
    }
    if protocol == "anthropic-messages" then
        local adapter_options = model_ref.adapter_options or {}
        local version = adapter_options.anthropic_version or "2023-06-01"
        if not valid_token(version, 64) then
            return nil, failure("InvalidAdapterOption", "Anthropic version header is invalid")
        end
        headers[#headers + 1] = {
            name = "anthropic-version",
            value = version,
        }
    end
    local secret_headers = {}
    if model_ref.auth_secret_id then
        if protocol == "openai-chat" then
            secret_headers[1] = {
                name = "Authorization",
                prefix = "Bearer ",
                suffix = "",
                secret_id = model_ref.auth_secret_id,
                destination = "model-auth:" .. (model_ref.name or request_data.request_id),
            }
        else
            secret_headers[1] = {
                name = "x-api-key",
                prefix = "",
                suffix = "",
                secret_id = model_ref.auth_secret_id,
                destination = "model-auth:" .. (model_ref.name or request_data.request_id),
            }
        end
    end
    return freeze({
        protocol = protocol,
        url = model_ref.endpoint,
        canonical_endpoint_shape = protocol == "openai-chat"
            and "/v1/chat/completions"
            or "/v1/messages",
        body = body,
        streaming = streaming,
        public_headers = headers,
        secret_headers = secret_headers,
        registry_digest = request_data.tool_registry.digest,
    }, "provider request")
end

local function new_response_session(codec, options, request_data, registry, controls, streaming)
    local request_id = request_data.request_id
    local protocol = request_data.model_ref.protocol
    local sse
    if streaming then
        sse = assert(network.new_sse_parser({
            maximum_line_bytes = options.maximum_sse_line_bytes,
            maximum_event_bytes = options.maximum_sse_event_bytes,
            maximum_buffered_bytes = options.maximum_sse_buffered_bytes,
            maximum_events_per_push = options.maximum_sse_events_per_push,
        }))
    end

    local state = "open"
    local response_bytes = 0
    local buffered = {}
    local batch = {}
    local deferred_events = {}
    local control_barrier = false
    local event_count = 0
    local started = false
    local provider_response_id = ""
    local text_bytes, reasoning_bytes = 0, 0
    local total_tool_argument_bytes = 0
    local content_blocks = {}
    local tools, tools_by_index, provider_ids = {}, {}, {}
    local complete_tool_calls = {}
    local primary_control
    local usage
    local terminal_response

    local function append_event(kind, fields, bypass_barrier)
        if event_count >= options.maximum_events then return nil, "event-limit" end
        local terminal = kind == "protocol_error"
            or kind == "transport_error"
            or kind == "response_finish"
        if not terminal and event_count + 3 > options.maximum_events then
            return nil, "event-limit"
        end
        event_count = event_count + 1
        local event = make_event(request_id, kind, fields)
        if control_barrier and not bypass_barrier then
            deferred_events[#deferred_events + 1] = event
        else
            batch[#batch + 1] = event
        end
        return true
    end

    local function release_deferred_events()
        control_barrier = false
        for _, event in ipairs(deferred_events) do batch[#batch + 1] = event end
        deferred_events = {}
    end

    local function build_response(finish_class, reason)
        if terminal_response then return terminal_response end
        local frozen_blocks, frozen_calls = {}, {}
        for index, block in ipairs(content_blocks) do
            if block.kind ~= "pending_control" then frozen_blocks[#frozen_blocks + 1] = block end
        end
        for index, call in ipairs(complete_tool_calls) do frozen_calls[index] = call end
        local result = {
            content_blocks = frozen_blocks,
            tool_calls = frozen_calls,
            finish_class = finish_class,
            incomplete = finish_class == "incomplete",
            tool_calls_validated = finish_class ~= "incomplete" and finish_class ~= "cancelled",
            execution_admitted = false,
        }
        if reason then result.incomplete_reason = reason end
        if primary_control then result.control = primary_control end
        if usage then result.usage = usage end
        terminal_response = freeze(result, "normalized response")
        return terminal_response
    end

    local function protocol_fail(error_id, start_openai)
        if state ~= "open" then return end
        if start_openai and protocol == "openai-chat" and not started then
            started = true
            append_event("response_start", { provider_response_id = "" })
        end
        if control_barrier then release_deferred_events() end
        if event_count < options.maximum_events then
            append_event("protocol_error", { error_id = error_id })
        end
        state = "failed"
        build_response("incomplete", error_id)
    end

    local function emit_start(provider_id)
        if started then
            if provider_id and provider_id ~= "" and provider_response_id ~= ""
                and provider_response_id ~= provider_id
            then
                protocol_fail("provider-response-id-changed")
                return nil
            end
            if provider_response_id == "" and provider_id then provider_response_id = provider_id end
            return true
        end
        if not valid_token(provider_id, 256) then
            protocol_fail("provider-response-id")
            return nil
        end
        provider_response_id = provider_id
        started = true
        local ok = append_event("response_start", { provider_response_id = provider_id })
        if not ok then protocol_fail("event-limit") return nil end
        return true
    end

    local function add_content_block(block)
        if #content_blocks >= options.maximum_content_blocks then
            protocol_fail("content-block-limit")
            return nil
        end
        content_blocks[#content_blocks + 1] = block
        return #content_blocks
    end

    local function append_text_delta(value, reasoning)
        if type(value) ~= "string" or value == "" then return true end
        local running = reasoning and reasoning_bytes or text_bytes
        local limit = reasoning and options.maximum_reasoning_bytes or options.maximum_text_bytes
        if running + #value > limit then
            protocol_fail(reasoning and "reasoning-limit" or "text-limit")
            return nil
        end
        if reasoning then reasoning_bytes = running + #value else text_bytes = running + #value end
        local kind = reasoning and "reasoning_summary_delta" or "text_delta"
        local ok = append_event(kind, { text = value })
        if not ok then protocol_fail("event-limit") return nil end
        if not reasoning then
            local last = content_blocks[#content_blocks]
            if last and last.kind == "text" then
                last.text = last.text .. value
            elseif not add_content_block({ kind = "text", text = value }) then
                return nil
            end
        end
        return true
    end

    local function start_tool(index, provider_id, name, initial_arguments)
        if tools_by_index[index] then
            local existing = tools_by_index[index]
            if provider_id and provider_id ~= existing.provider_id then
                protocol_fail("tool-call-id-changed")
                return nil
            end
            if name and name ~= existing.name then
                protocol_fail("tool-call-name-changed")
                return nil
            end
            return existing
        end
        if #tools >= options.maximum_tool_calls then protocol_fail("tool-count-limit") return nil end
        if not valid_token(provider_id, 256) or not valid_token(name, 128) then
            protocol_fail("tool-call-identity")
            return nil
        end
        if provider_ids[provider_id] then protocol_fail("duplicate-tool-call-id") return nil end
        local control = controls.lookup[name]
        if not control and not registry.lookup[name] then
            protocol_fail("unregistered-tool")
            return nil
        end
        provider_ids[provider_id] = true
        local tool = {
            index = index,
            provider_id = provider_id,
            name = name,
            control = control,
            local_id = request_id .. ":tool:" .. tostring(#tools + 1),
            arguments = "",
            initial_arguments = initial_arguments,
            saw_delta = false,
        }
        tools[#tools + 1] = tool
        tools_by_index[index] = tool
        if control then
            tool.block_index = add_content_block({ kind = "pending_control" })
            if tool.block_index then control_barrier = true end
        else
            tool.block_index = add_content_block({
                kind = "tool_call",
                local_tool_call_id = tool.local_id,
                name = name,
            })
            if tool.block_index then
                local ok = append_event("tool_call_start", {
                    local_tool_call_id = tool.local_id,
                    name = name,
                })
                if not ok then protocol_fail("event-limit") return nil end
            end
        end
        return state == "open" and tool or nil
    end

    local function append_tool_arguments(tool, bytes)
        if type(bytes) ~= "string" or bytes == "" then return true end
        if not tool.control then
            local ok = append_event("tool_arguments_delta", {
                local_tool_call_id = tool.local_id,
                bytes = bytes,
            })
            if not ok then protocol_fail("event-limit") return nil end
        end
        local next_tool = #tool.arguments + #bytes
        local next_total = total_tool_argument_bytes + #bytes
        if next_tool > options.maximum_tool_argument_bytes
            or next_total > options.maximum_total_tool_argument_bytes
        then
            protocol_fail("tool-argument-limit")
            return nil
        end
        tool.saw_delta = true
        tool.arguments = tool.arguments .. bytes
        total_tool_argument_bytes = next_total
        return true
    end

    local function arguments_for(tool)
        if tool.saw_delta then return tool.arguments end
        return tool.initial_arguments or ""
    end

    local function parse_tool_arguments(tool)
        local source = arguments_for(tool)
        if source == "" then source = "{}" end
        local parsed, parse_error = codec.parse(source)
        if not parsed or json.kind(parsed) ~= "object" then
            return nil, parse_error and parse_error.code or "arguments-object"
        end
        if tool.control then
            local valid, reason = validate_control_payload(tool.control, parsed)
            if not valid then return nil, "control-" .. reason end
        else
            local descriptor = registry.lookup[tool.name]
            local valid, reason = validate_schema(parsed, descriptor.schema)
            if not valid then return nil, "tool-schema-" .. reason end
        end
        local canonical, canonical_error = codec.write(parsed)
        if not canonical then return nil, canonical_error.code end
        return { parsed = parsed, canonical = canonical }
    end

    local function finalize_tools()
        local parsed = {}
        local control_count, executable_count = 0, 0
        for index, tool in ipairs(tools) do
            local result, parse_error = parse_tool_arguments(tool)
            if not result then protocol_fail(parse_error) return nil end
            parsed[index] = result
            if tool.control then control_count = control_count + 1 else executable_count = executable_count + 1 end
        end
        if control_count > 1 then protocol_fail("multiple-controls") return nil end
        for index, tool in ipairs(tools) do
            if tool.control then
                local payload = json_plain(parsed[index].parsed)
                primary_control = { control = tool.control, payload = payload }
                content_blocks[tool.block_index] = {
                    kind = "control",
                    control = tool.control,
                    payload = payload,
                }
                local ok = append_event(
                    "control",
                    { control = tool.control, payload = payload },
                    true
                )
                if not ok then protocol_fail("event-limit") return nil end
            end
        end
        if control_barrier then release_deferred_events() end
        if control_count > 0 and executable_count > 0 then
            protocol_fail("control-tool-conflict")
            return nil
        end
        for index, tool in ipairs(tools) do
            if not tool.control then
                local call = {
                    local_tool_call_id = tool.local_id,
                    name = tool.name,
                    canonical_arguments = parsed[index].canonical,
                    provider_tool_call_id = tool.provider_id,
                }
                complete_tool_calls[#complete_tool_calls + 1] = call
                content_blocks[tool.block_index].canonical_arguments = parsed[index].canonical
                local ok = append_event("tool_call_complete", call)
                if not ok then protocol_fail("event-limit") return nil end
            end
        end
        return true
    end

    local function emit_usage(source, anthropic)
        if type(source) ~= "table" then return true end
        local input = nonnegative_json_integer(source[anthropic and "input_tokens" or "prompt_tokens"])
        local output = nonnegative_json_integer(source[anthropic and "output_tokens" or "completion_tokens"])
        local total = nonnegative_json_integer(source.total_tokens)
        if input == nil and output == nil and total == nil then return true end
        if total == nil and input ~= nil and output ~= nil then total = input + output end
        usage = { input = input, output = output, total = total }
        local fields = {}
        for key, value in pairs(usage) do if value ~= nil then fields[key] = value end end
        local ok = append_event("usage_update", fields)
        if not ok then protocol_fail("event-limit") return nil end
        return true
    end

    local function finish_response(finish_class)
        if state ~= "open" then return nil end
        if not finish_class then protocol_fail("finish-reason") return nil end
        if #tools > 0 then
            if finish_class ~= "tool_calls" then protocol_fail("tool-finish-mismatch") return nil end
            if not finalize_tools() then return nil end
        elseif finish_class == "tool_calls" then
            protocol_fail("missing-tool-call")
            return nil
        end
        if not started then protocol_fail("missing-response-start") return nil end
        local ok = append_event("response_finish", { finish_class = finish_class })
        if not ok then protocol_fail("event-limit") return nil end
        state = "finished"
        build_response(finish_class)
        return true
    end

    local function parse_openai_tool_deltas(values)
        if json.kind(values) ~= "array" then protocol_fail("openai-tool-calls") return nil end
        for _, item in ipairs(values) do
            if json.kind(item) ~= "object" then protocol_fail("openai-tool-call") return nil end
            local zero_index = nonnegative_json_integer(item.index)
            if zero_index == nil then protocol_fail("openai-tool-index") return nil end
            local index = zero_index + 1
            local function_value = item["function"]
            if json.kind(function_value) ~= "object" then
                protocol_fail("openai-tool-function")
                return nil
            end
            local tool = tools_by_index[index]
            if not tool then
                tool = start_tool(index, item.id, function_value.name)
                if not tool then return nil end
            else
                if item.id ~= nil and item.id ~= tool.provider_id then
                    protocol_fail("tool-call-id-changed") return nil
                end
                if function_value.name ~= nil and function_value.name ~= tool.name then
                    protocol_fail("tool-call-name-changed") return nil
                end
            end
            if function_value.arguments ~= nil then
                if type(function_value.arguments) ~= "string" then
                    protocol_fail("openai-tool-arguments") return nil
                end
                if not append_tool_arguments(tool, function_value.arguments) then return nil end
            end
        end
        return true
    end

    local function handle_openai_json(source)
        local document, parse_error = codec.parse(source)
        if not document or json.kind(document) ~= "object" then
            protocol_fail(parse_error and parse_error.code or "openai-json", true)
            return nil
        end
        if not emit_start(document.id) then return nil end
        if document.usage and not emit_usage(document.usage, false) then return nil end
        if json.kind(document.choices) ~= "array" then
            protocol_fail("openai-choices") return nil
        end
        if #document.choices == 0 then return true end
        if #document.choices ~= 1 or json.kind(document.choices[1]) ~= "object" then
            protocol_fail("openai-choice-count") return nil
        end
        local choice = document.choices[1]
        local delta = choice.delta
        if json.kind(delta) ~= "object" then
            protocol_fail("openai-delta") return nil
        end
        if delta.content ~= nil and not append_text_delta(delta.content, false) then return nil end
        if delta.reasoning_summary ~= nil
            and not append_text_delta(delta.reasoning_summary, true)
        then return nil end
        if delta.tool_calls ~= nil and not parse_openai_tool_deltas(delta.tool_calls) then return nil end
        if choice.finish_reason ~= nil and choice.finish_reason ~= json.null then
            if type(choice.finish_reason) ~= "string" then
                protocol_fail("openai-finish-reason") return nil
            end
            return finish_response(map_openai_finish(choice.finish_reason))
        end
        return true
    end

    local function handle_openai_nonstream(source)
        local document, parse_error = codec.parse(source)
        if not document or json.kind(document) ~= "object" then
            protocol_fail(parse_error and parse_error.code or "openai-json", true)
            return nil
        end
        if json.kind(document.choices) ~= "array" or #document.choices ~= 1
            or json.kind(document.choices[1]) ~= "object"
        then
            protocol_fail("openai-choices", true) return nil
        end
        if not emit_start(document.id) then return nil end
        local choice = document.choices[1]
        local message = choice.message
        if json.kind(message) ~= "object" then protocol_fail("openai-message") return nil end
        if message.content ~= nil and message.content ~= json.null
            and not append_text_delta(message.content, false)
        then return nil end
        if message.tool_calls ~= nil then
            if json.kind(message.tool_calls) ~= "array" then
                protocol_fail("openai-tool-calls") return nil
            end
            for index, item in ipairs(message.tool_calls) do
                if json.kind(item) ~= "object" or json.kind(item["function"]) ~= "object" then
                    protocol_fail("openai-tool-call") return nil
                end
                local function_value = item["function"]
                local tool = start_tool(index, item.id, function_value.name)
                if not tool then return nil end
                if type(function_value.arguments) ~= "string"
                    or not append_tool_arguments(tool, function_value.arguments)
                then
                    if state == "open" then protocol_fail("openai-tool-arguments") end
                    return nil
                end
            end
        end
        if document.usage and not emit_usage(document.usage, false) then return nil end
        return finish_response(map_openai_finish(choice.finish_reason))
    end

    local function anthropic_start_tool(index, block)
        local provider_id, name = block.id, block.name
        local initial
        if block.input ~= nil then
            if json.kind(block.input) ~= "object" then
                protocol_fail("anthropic-tool-input") return nil
            end
            initial = assert(codec.write(block.input))
        end
        return start_tool(index, provider_id, name, initial)
    end

    local function handle_anthropic_event(event_name, source)
        local document, parse_error = codec.parse(source)
        if not document or json.kind(document) ~= "object" then
            protocol_fail(parse_error and parse_error.code or "anthropic-json")
            return nil
        end
        local event_type = document.type
        if type(event_type) ~= "string" then protocol_fail("anthropic-event-type") return nil end
        if event_name ~= "message" and event_name ~= event_type then
            protocol_fail("anthropic-event-name") return nil
        end
        if event_type == "message_start" then
            if json.kind(document.message) ~= "object" then
                protocol_fail("anthropic-message-start") return nil
            end
            if not emit_start(document.message.id) then return nil end
            return emit_usage(document.message.usage, true)
        elseif event_type == "content_block_start" then
            local zero_index = nonnegative_json_integer(document.index)
            local block = document.content_block
            if zero_index == nil or json.kind(block) ~= "object" then
                protocol_fail("anthropic-content-start") return nil
            end
            if block.type == "text" then
                return append_text_delta(block.text or "", false)
            elseif block.type == "tool_use" then
                return anthropic_start_tool(zero_index + 1, block) ~= nil
            end
            protocol_fail("anthropic-content-type")
            return nil
        elseif event_type == "content_block_delta" then
            local zero_index = nonnegative_json_integer(document.index)
            local delta = document.delta
            if zero_index == nil or json.kind(delta) ~= "object" then
                protocol_fail("anthropic-content-delta") return nil
            end
            if delta.type == "text_delta" then
                return append_text_delta(delta.text, false)
            elseif delta.type == "input_json_delta" then
                local tool = tools_by_index[zero_index + 1]
                if not tool then protocol_fail("anthropic-tool-order") return nil end
                return append_tool_arguments(tool, delta.partial_json)
            elseif delta.type == "summary_text_delta" then
                return append_text_delta(delta.text, true)
            end
            protocol_fail("anthropic-delta-type")
            return nil
        elseif event_type == "content_block_stop" or event_type == "ping" then
            return true
        elseif event_type == "message_delta" then
            if document.usage and not emit_usage(document.usage, true) then return nil end
            if json.kind(document.delta) ~= "object" then
                protocol_fail("anthropic-message-delta") return nil
            end
            return finish_response(map_anthropic_finish(document.delta.stop_reason))
        elseif event_type == "message_stop" then
            if state == "open" then protocol_fail("anthropic-missing-stop-reason") return nil end
            return true
        elseif event_type == "error" then
            local error_type = json.kind(document.error) == "object" and document.error.type or "provider-error"
            if not valid_token(error_type, 64) then error_type = "provider-error" end
            local retryable = error_type == "overloaded_error" or error_type == "rate_limit_error"
            append_event("transport_error", { error_id = "anthropic-" .. tostring(error_type), retryable = retryable })
            state = "failed"
            build_response("incomplete", "provider-error")
            return nil
        end
        protocol_fail("anthropic-event-unknown")
        return nil
    end

    local function handle_anthropic_nonstream(source)
        local document, parse_error = codec.parse(source)
        if not document or json.kind(document) ~= "object" then
            protocol_fail(parse_error and parse_error.code or "anthropic-json") return nil
        end
        if not emit_start(document.id) then return nil end
        if json.kind(document.content) ~= "array" then
            protocol_fail("anthropic-content") return nil
        end
        for index, block in ipairs(document.content) do
            if json.kind(block) ~= "object" then protocol_fail("anthropic-content-block") return nil end
            if block.type == "text" then
                if not append_text_delta(block.text, false) then return nil end
            elseif block.type == "tool_use" then
                if not anthropic_start_tool(index, block) then return nil end
            else
                protocol_fail("anthropic-content-type") return nil
            end
        end
        if document.usage and not emit_usage(document.usage, true) then return nil end
        return finish_response(map_anthropic_finish(document.stop_reason))
    end

    local session = {}

    function session:push(bytes)
        if state ~= "open" then return nil, failure("ModelState", "response session is closed") end
        if type(bytes) ~= "string" then
            return nil, failure("InvalidResponseBytes", "response bytes must be a string")
        end
        batch = {}
        if response_bytes + #bytes > options.maximum_response_bytes then
            protocol_fail("response-byte-limit", protocol == "openai-chat")
            return freeze(batch, "model event batch")
        end
        response_bytes = response_bytes + #bytes
        if not streaming then
            buffered[#buffered + 1] = bytes
            return freeze(batch, "model event batch")
        end
        local events, sse_error = sse:push(bytes)
        if not events then
            protocol_fail(sse_error.code, protocol == "openai-chat")
            return freeze(batch, "model event batch")
        end
        for _, event in ipairs(events) do
            if protocol == "openai-chat" then
                if event.data ~= "[DONE]" and not handle_openai_json(event.data) then break end
            elseif not handle_anthropic_event(event.event, event.data) then
                break
            end
        end
        return freeze(batch, "model event batch")
    end

    function session:finish()
        batch = {}
        if state ~= "open" then
            return freeze(batch, "model event batch"), terminal_response
        end
        if streaming then
            local events, sse_error = sse:finish()
            if not events then
                protocol_fail(sse_error.code, protocol == "openai-chat")
            else
                for _, event in ipairs(events) do
                    if protocol == "openai-chat" then
                        if event.data ~= "[DONE]" and not handle_openai_json(event.data) then break end
                    elseif not handle_anthropic_event(event.event, event.data) then
                        break
                    end
                end
            end
            if state == "open" then
                if #tools > 0 then
                    finish_response("tool_calls")
                else
                    protocol_fail("stream-incomplete", protocol == "openai-chat")
                end
            end
        else
            local source = table.concat(buffered)
            if protocol == "openai-chat" then
                handle_openai_nonstream(source)
            else
                handle_anthropic_nonstream(source)
            end
        end
        return freeze(batch, "model event batch"), terminal_response
    end

    function session:cancel(error_id)
        if state ~= "open" then return nil, failure("ModelState", "response session is closed") end
        batch = {}
        if control_barrier then release_deferred_events() end
        if not valid_token(error_id, 128) then error_id = "cancelled" end
        append_event("transport_error", { error_id = error_id, retryable = false })
        append_event("response_finish", { finish_class = "cancelled" })
        state = "cancelled"
        build_response("cancelled", error_id)
        return freeze(batch, "model event batch"), terminal_response
    end

    function session:http_error(status, error_id, retryable)
        if state ~= "open" then return nil, failure("ModelState", "response session is closed") end
        if not valid_integer(status, 100) or status > 599 then
            return nil, failure("InvalidHttpStatus", "provider HTTP status is invalid")
        end
        batch = {}
        if control_barrier then release_deferred_events() end
        if not valid_token(error_id, 128) then error_id = "http-" .. tostring(status) end
        -- HTTP retry eligibility is a protocol classification, never a caller override.
        -- The retry controller may further reduce it after observing request/body state.
        retryable = status == 429 or status == 503
        append_event("transport_error", {
            error_id = error_id,
            retryable = retryable,
            status = status,
        })
        state = "failed"
        build_response("incomplete", "http-" .. tostring(status))
        return freeze(batch, "model event batch"), terminal_response
    end

    function session:response()
        return terminal_response
    end

    function session:status()
        return state, response_bytes, event_count
    end

    return readonly(session, "model response session")
end

---Creates the canonical dual-provider model adapter service.
-- @param options table Immutable release hard-cap snapshot.
-- @return table|nil service Model request/response adapter.
-- @return table|nil err Structured constructor failure.
function M.new(options)
    local limits, limit_error = validate_options(options)
    if not limits then return nil, limit_error end
    local codec, codec_error = json.new({
        maximum_bytes = limits.maximum_json_bytes,
        maximum_depth = limits.maximum_json_depth,
        maximum_nodes = limits.maximum_json_nodes,
        maximum_string_bytes = limits.maximum_string_bytes,
        maximum_number_bytes = limits.maximum_number_bytes,
    })
    if not codec then return nil, codec_error end
    local normalized = setmetatable({}, { __mode = "k" })
    local service = {}

    function service:normalize_request(spec)
        local admitted, admission_error = validate_request_shape(spec, limits)
        if not admitted then return nil, admission_error end
        local public = freeze(admitted.public, "normalized request")
        normalized[public] = {
            public = admitted.public,
            registry = admitted.registry,
            controls = admitted.controls,
        }
        return public
    end

    local function request_state(request)
        local state_value = normalized[request]
        if not state_value then
            return nil, failure("InvalidRequest", "request was not normalized by this service")
        end
        return state_value
    end

    local function resolve_streaming(admitted, streaming_override)
        local mode = admitted.public.streaming
        local streaming
        if streaming_override == nil then
            streaming = mode ~= "off"
        elseif type(streaming_override) == "boolean" then
            streaming = streaming_override
        else
            return nil, failure("InvalidStreamingOverride", "streaming override must be boolean")
        end
        if mode == "force" and not streaming then
            return nil, failure("StreamingRequired", "force streaming cannot fall back")
        end
        if mode == "off" and streaming then
            return nil, failure("StreamingDisabled", "off streaming cannot be enabled per attempt")
        end
        return streaming
    end

    function service:encode(request, streaming_override)
        local admitted, request_error = request_state(request)
        if not admitted then return nil, request_error end
        local streaming, streaming_error = resolve_streaming(admitted, streaming_override)
        if streaming == nil then return nil, streaming_error end
        return encode_request(codec, admitted.public, streaming)
    end

    function service:new_response(request, streaming_override)
        local admitted, request_error = request_state(request)
        if not admitted then return nil, request_error end
        local streaming, streaming_error = resolve_streaming(admitted, streaming_override)
        if streaming == nil then return nil, streaming_error end
        return new_response_session(
            codec,
            limits,
            admitted.public,
            admitted.registry,
            admitted.controls,
            streaming
        )
    end

    function service:streaming_fallback(request, canonical_event_seen, prior_fallbacks)
        local admitted, request_error = request_state(request)
        if not admitted then return nil, request_error end
        if type(canonical_event_seen) ~= "boolean" or not valid_integer(prior_fallbacks, 0) then
            return nil, failure("InvalidFallbackObservation", "fallback observation is invalid")
        end
        local allowed = admitted.public.streaming == "try"
            and not canonical_event_seen
            and prior_fallbacks == 0
        local next_streaming = admitted.public.streaming ~= "off"
        if allowed then next_streaming = false end
        return freeze({
            allowed = allowed,
            next_streaming = next_streaming,
            reason = allowed and "try-pre-canonical" or "fallback-forbidden",
        }, "streaming fallback decision")
    end

    function service:registry_digest_event(request, observed_digest)
        local admitted, request_error = request_state(request)
        if not admitted then return nil, request_error end
        if type(observed_digest) ~= "string" then
            return nil, failure("InvalidRegistryDigest", "observed registry digest must be text")
        end
        if observed_digest == admitted.public.tool_registry.digest then return freeze({}, "model event batch") end
        return freeze({ make_event(
            admitted.public.request_id,
            "protocol_error",
            { error_id = "registry-digest-mismatch" }
        ) }, "model event batch")
    end

    service.capabilities = freeze({
        schema_version = "0.1.0",
        protocols = { "openai-chat", "anthropic-messages" },
        canonical_only = true,
        streaming_arguments_executable = false,
        synthetic_wire_inventory = true,
        recorded_provider_wire = false,
        target_qualified = false,
        target_proof = "TP-015-pending",
    }, "model capabilities")
    service.limits = freeze(limits, "model limits")

    return readonly(service, "model service")
end

return M
