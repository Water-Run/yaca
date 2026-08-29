--[[
File: model.lua
Date: 2026-08-30
Author: WaterRun
Description: Maps bounded OpenAI Chat and Anthropic Messages wire data to canonical model events.
]]

local json = require("json")
local network = require("network")
local prompt = require("prompt")
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
            if converted == nil then return nil, convert_error end
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
        if converted == nil then return nil, convert_error end
        items[key] = converted
    end
    return json.object(items)
end

local function encode_value(codec, value, hint)
    local converted, convert_error = to_json_value(value, hint)
    if converted == nil then return nil, convert_error end
    local kind = json.kind(converted)
    if kind == "object" or kind == "array" then return codec.write(converted) end
    local wrapper = assert(json.object({ v = converted }))
    local encoded, encode_error = codec.write(wrapper)
    if not encoded then return nil, encode_error end
    return encoded:sub(6, -2)
end

local function encode_message_array(codec, messages)
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
            or (type(message.content) ~= "string" and type(message.content) ~= "table")
        then
            return nil, failure("InvalidPromptBundle", "prompt messages require string role and content")
        end
        if index > 1 and not add(",") then
            return nil, failure("WireRequestLimit", "provider messages exceed their byte limit")
        end
        local role, role_error = encode_value(codec, message.role)
        if not role then return nil, role_error end
        local content, content_error = encode_value(
            codec,
            message.content,
            type(message.content) == "table" and "array" or nil
        )
        if not content then return nil, content_error end
        local item = "{\"role\":" .. role .. ",\"content\":" .. content .. "}"
        local admitted, limit_error = add(item)
        if not admitted then return nil, limit_error end
    end
    local admitted, limit_error = add("]")
    if not admitted then return nil, limit_error end
    return table.concat(result)
end

local function model_view_message(manifest)
    if manifest.body == nil then return nil end
    return {
        role = "user",
        content = table.concat({
            "YACA-MODEL-VIEW/1\n",
            "authority=quoted-data\n",
            "digest=", manifest.digest, "\n",
            "first-sequence=", tostring(manifest.first_sequence), "\n",
            "last-sequence=", tostring(manifest.last_sequence), "\n",
            "bytes=", tostring(#manifest.body), "\n\n",
            manifest.body,
        }),
    }
end

local function encode_messages(codec, bundle, manifest, protocol)
    local messages = bundle.messages
    if dense_count(messages) == nil then
        return nil, nil, failure("InvalidPromptBundle", "prompt messages must be a dense array")
    end
    local projected = {}
    if bundle.system ~= nil and bundle.system ~= "" then
        if type(bundle.system) ~= "string" then
            return nil, nil, failure("InvalidPromptBundle", "legacy system Prompt must be text")
        end
        projected[#projected + 1] = { role = "system", content = bundle.system }
    end
    local view_message = model_view_message(manifest)
    local inserted_view = view_message == nil
    for _, message in ipairs(messages) do
        if not inserted_view and message.role ~= "system" then
            projected[#projected + 1] = view_message
            inserted_view = true
        end
        projected[#projected + 1] = message
    end
    if not inserted_view then projected[#projected + 1] = view_message end
    if protocol == "openai-chat" then
        for _, message in ipairs(projected) do
            if message.role ~= "system" and message.role ~= "user" and message.role ~= "assistant" then
                return nil, nil, failure("InvalidPromptBundle", "OpenAI Prompt role is invalid")
            end
        end
        local encoded, encode_error = encode_message_array(codec, projected)
        return encoded, nil, encode_error
    end

    local system_blocks, provider_messages = {}, {}
    local saw_provider_message = false
    for _, message in ipairs(projected) do
        if type(message) ~= "table" or type(message.content) ~= "string" then
            return nil, nil, failure("InvalidPromptBundle", "Anthropic Prompt message is invalid")
        end
        if message.role == "system" then
            if saw_provider_message then
                return nil, nil, failure("InvalidPromptBundle", "Anthropic system components must precede messages")
            end
            system_blocks[#system_blocks + 1] = { type = "text", text = message.content }
        elseif message.role == "user" or message.role == "assistant" then
            saw_provider_message = true
            if bundle.version ~= nil then
                local previous = provider_messages[#provider_messages]
                if not previous or previous.role ~= message.role then
                    previous = { role = message.role, content = {} }
                    provider_messages[#provider_messages + 1] = previous
                end
                previous.content[#previous.content + 1] = {
                    type = "text",
                    text = message.content,
                }
            else
                provider_messages[#provider_messages + 1] = {
                    role = message.role,
                    content = message.content,
                }
            end
        else
            return nil, nil, failure("InvalidPromptBundle", "Anthropic Prompt role is invalid")
        end
    end
    if #provider_messages == 0 then
        return nil, nil, failure("InvalidPromptBundle", "Anthropic requires one non-system message")
    end
    local encoded_messages, messages_error = encode_message_array(codec, provider_messages)
    if not encoded_messages then return nil, nil, messages_error end
    local encoded_system
    if #system_blocks > 0 then
        encoded_system, messages_error = encode_value(codec, system_blocks, "array")
        if not encoded_system then return nil, nil, messages_error end
    end
    return encoded_messages, encoded_system
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

local function normalize_controls(controls, purpose)
    local valid, validation_error = prompt.validate_controls_schema(controls, purpose)
    if not valid then return nil, validation_error end
    local lookup = {}
    for _, control in ipairs(controls.controls) do
        local wire_name = control.wire_name
        local canonical = CONTROL_NAMES[wire_name]
        if not canonical or control.canonical_id ~= canonical or lookup[wire_name] then
            return nil, failure("InvalidControlSchema", "control schema entry is invalid")
        end
        lookup[wire_name] = canonical
    end
    return { public = controls, lookup = lookup }
end

local function normalize_model_view(manifest, options)
    if type(manifest) ~= "table" then
        return nil, failure("InvalidModelViewManifest", "model view manifest is required")
    end
    local allowed = {
        digest = true,
        first_sequence = true,
        last_sequence = true,
        body = true,
    }
    for key in pairs(manifest) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure(
                "InvalidModelViewManifest",
                "model view manifest contains an unknown field"
            )
        end
    end
    if not valid_token(manifest.digest, 256) then
        return nil, failure("InvalidModelViewManifest", "model view manifest digest is required")
    end
    local has_first = manifest.first_sequence ~= nil
    local has_last = manifest.last_sequence ~= nil
    if has_first ~= has_last
        or (has_first and (
            not valid_integer(manifest.first_sequence, 0)
            or not valid_integer(manifest.last_sequence, 0)
            or manifest.first_sequence > manifest.last_sequence
            or (manifest.first_sequence == 0 and manifest.last_sequence ~= 0)
        ))
    then
        return nil, failure(
            "InvalidModelViewManifest",
            "model view manifest range is invalid"
        )
    end
    if manifest.body ~= nil then
        if not has_first
            or type(manifest.body) ~= "string"
            or #manifest.body > options.maximum_string_bytes
            or manifest.body:find("\0", 1, true)
        then
            return nil, failure(
                "InvalidModelViewManifest",
                "model view body is unbounded or lacks an exact range"
            )
        end
        local valid, utf8_error = text.validate_utf8(manifest.body)
        if not valid then return nil, utf8_error end
    end
    return manifest
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
    local view, view_error = normalize_model_view(spec.model_view_manifest, options)
    if not view then return nil, view_error end
    if spec.prompt_bundle.version ~= nil then
        local bound, bundle_error = prompt.validate_bundle(
            spec.prompt_bundle,
            spec.purpose,
            spec.config_generation
        )
        if not bound then return nil, bundle_error end
        if type(spec.prompt_bundle.controls_schema) ~= "table"
            or spec.prompt_bundle.controls_schema.digest ~= spec.controls_schema.digest
        then
            return nil, failure("InvalidPromptBundle", "Prompt and request control snapshots differ")
        end
        local tool_count = dense_count(spec.tool_registry.tools)
        if spec.prompt_bundle.tool_mode == "none" and tool_count ~= 0 then
            return nil, failure("InvalidPromptBundle", "no-tool purpose received a tool registry")
        end
        if spec.prompt_bundle.tool_mode == "registered" and tool_count == 0 then
            return nil, failure("InvalidPromptBundle", "registered-tool purpose has an empty registry")
        end
    end
    local registry, registry_error = normalize_registry(spec.tool_registry, options)
    if not registry then return nil, registry_error end
    local controls, controls_error = normalize_controls(spec.controls_schema, spec.purpose)
    if not controls then return nil, controls_error end
    local copy, copy_error = copy_bounded(spec, options)
    if not copy then return nil, copy_error end
    -- Rebuild every lookup from the admitted copy. The caller-owned schema tables
    -- must never remain an authority after the immutable request snapshot exists.
    registry = assert(normalize_registry(copy.tool_registry, options))
    controls = assert(normalize_controls(copy.controls_schema, copy.purpose))
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
    local messages, system, messages_error = encode_messages(
        codec,
        request_data.prompt_bundle,
        request_data.model_view_manifest,
        protocol
    )
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
        }
        if system then fields[#fields + 1] = "\"system\":" .. system end
        fields[#fields + 1] = "\"messages\":" .. messages
        fields[#fields + 1] = "\"stream\":" .. stream
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

    function session:transport_error(error_id)
        if state ~= "open" then return nil, failure("ModelState", "response session is closed") end
        batch = {}
        if control_barrier then release_deferred_events() end
        if not valid_token(error_id, 128) then error_id = "transport-failure" end
        append_event("transport_error", {
            error_id = error_id,
            retryable = false,
        })
        state = "failed"
        build_response("incomplete", error_id)
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

    function service:controls_schema(purpose)
        return prompt.control_schema(purpose)
    end

    service.capabilities = freeze({
        schema_version = "0.1.0",
        prompt_version = prompt.prompt_version(),
        control_schema_digest = prompt.control_schema_digest(),
        protocols = { "openai-chat", "anthropic-messages" },
        canonical_only = true,
        prompt_component_order_preserved = true,
        native_controls = true,
        streaming_arguments_executable = false,
        synthetic_wire_inventory = true,
        recorded_provider_wire = false,
        target_qualified = false,
        target_proof = "TP-015-pending",
    }, "model capabilities")
    service.limits = freeze(limits, "model limits")

    return readonly(service, "model service")
end

local function exact_activity_fields(value, allowed)
    if type(value) ~= "table" then return false end
    for key in pairs(value) do
        if type(key) ~= "string" or not allowed[key] then return false end
    end
    return true
end

local function canonical_value(value, visiting)
    local value_type = type(value)
    if value == nil then return "n;" end
    if value_type == "string" then return "s" .. tostring(#value) .. ":" .. value end
    if value_type == "boolean" then return value and "b1;" or "b0;" end
    if value_type == "number" and math.type(value) == "integer" then
        return "i" .. tostring(value) .. ";"
    end
    if value_type ~= "table" then
        return nil, failure("InvalidCanonicalResponse", "response contains an unsupported value")
    end
    visiting = visiting or {}
    if visiting[value] then
        return nil, failure("InvalidCanonicalResponse", "response contains a cycle")
    end
    visiting[value] = true
    local count = dense_count(value)
    local parts = {}
    if count ~= nil then
        parts[1] = "a" .. tostring(count) .. ":"
        for index = 1, count do
            local encoded, encode_error = canonical_value(value[index], visiting)
            if not encoded then visiting[value] = nil return nil, encode_error end
            parts[#parts + 1] = encoded
        end
    else
        local keys = {}
        for key in pairs(value) do
            if type(key) ~= "string" then
                visiting[value] = nil
                return nil, failure(
                    "InvalidCanonicalResponse",
                    "response maps require string keys"
                )
            end
            keys[#keys + 1] = key
        end
        table.sort(keys)
        parts[1] = "m" .. tostring(#keys) .. ":"
        for _, key in ipairs(keys) do
            local encoded, encode_error = canonical_value(value[key], visiting)
            if not encoded then visiting[value] = nil return nil, encode_error end
            parts[#parts + 1] = "k" .. tostring(#key) .. ":" .. key
            parts[#parts + 1] = encoded
        end
    end
    visiting[value] = nil
    return table.concat(parts)
end

local function response_body(response)
    local parts = {}
    for _, block in ipairs(response.content_blocks or {}) do
        if block.kind == "text" and type(block.text) == "string" then
            parts[#parts + 1] = block.text
        end
    end
    if #parts == 0 and type(response.control) == "table" then
        local payload = response.control.payload or {}
        local value = response.control.control == "finish" and payload.summary
            or response.control.control == "ask-user" and payload.question
            or response.control.control == "refuse" and payload.reason
            or nil
        if type(value) == "string" then parts[1] = value end
    end
    return table.concat(parts)
end

local function leap_year(year)
    return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

local function days_in_month(year, month)
    local lengths = { 31, leap_year(year) and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    return lengths[month]
end

local function days_from_civil(year, month, day)
    year = year - (month <= 2 and 1 or 0)
    local era = year >= 0 and year // 400 or (year - 399) // 400
    local year_of_era = year - era * 400
    local adjusted_month = month + (month > 2 and -3 or 9)
    local day_of_year = (153 * adjusted_month + 2) // 5 + day - 1
    local day_of_era = year_of_era * 365 + year_of_era // 4
        - year_of_era // 100 + day_of_year
    return era * 146097 + day_of_era - 719468
end

local function utc_epoch(value)
    if type(value) ~= "string" then return nil end
    local year, month, day, hour, minute, second = value:match(
        "^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)Z$"
    )
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
    hour, minute, second = tonumber(hour), tonumber(minute), tonumber(second)
    if not year or year < 1970 or year > 9999
        or not month or month < 1 or month > 12
        or not day or day < 1 or day > days_in_month(year, month)
        or not hour or hour > 23
        or not minute or minute > 59
        or not second or second > 59
    then
        return nil
    end
    return days_from_civil(year, month, day) * 86400
        + hour * 3600 + minute * 60 + second
end

local ACTIVITY_OPTION_FIELDS = {
    maximum_poll_events = true,
    maximum_queued_events = true,
    maximum_header_bytes = true,
    maximum_header_line_bytes = true,
    maximum_header_lines = true,
    maximum_redirects = true,
    maximum_turn_time_ms = true,
    maximum_runtime_time_ms = true,
    maximum_canonical_body_bytes = true,
    retry_manifest = true,
}

local RETRY_MANIFEST_FIELDS = {
    identity = true,
    maximum_count = true,
    exponent = true,
    maximum_delay_ms = true,
    runtime_wait_cap_ms = true,
    deterministic_jitter_permille = true,
}

local function validate_activity_options(options)
    if not exact_activity_fields(options, ACTIVITY_OPTION_FIELDS)
        or not valid_integer(options.maximum_poll_events, 1)
        or not valid_integer(options.maximum_queued_events, 1)
        or options.maximum_queued_events < options.maximum_poll_events
        or not valid_integer(options.maximum_header_bytes, 1)
        or not valid_integer(options.maximum_header_line_bytes, 1)
        or options.maximum_header_line_bytes > options.maximum_header_bytes
        or not valid_integer(options.maximum_header_lines, 1)
        or not valid_integer(options.maximum_redirects, 0)
        or not valid_integer(options.maximum_turn_time_ms, 1)
        or not valid_integer(options.maximum_runtime_time_ms, 1)
        or not valid_integer(options.maximum_canonical_body_bytes, 1)
        or not exact_activity_fields(options.retry_manifest, RETRY_MANIFEST_FIELDS)
    then
        return nil, failure("InvalidModelActivityOptions", "model activity limits are incomplete")
    end
    local retry = options.retry_manifest
    if not valid_token(retry.identity, 128)
        or not valid_integer(retry.maximum_count, 0)
        or not valid_integer(retry.exponent, 1)
        or not valid_integer(retry.maximum_delay_ms, 0)
        or not valid_integer(retry.runtime_wait_cap_ms, 0)
        or not valid_integer(retry.deterministic_jitter_permille, 0)
        or retry.deterministic_jitter_permille > 1000
    then
        return nil, failure("InvalidModelActivityOptions", "retry manifest is invalid")
    end
    return options
end

local function validate_activity_ports(ports)
    local allowed = {
        adapter = true,
        transport = true,
        safety = true,
        clock = true,
        requests = true,
    }
    if not exact_activity_fields(ports, allowed)
        or type(ports.adapter) ~= "table"
        or type(ports.adapter.encode) ~= "function"
        or type(ports.adapter.new_response) ~= "function"
        or type(ports.adapter.streaming_fallback) ~= "function"
        or type(ports.transport) ~= "table"
        or type(ports.transport.new_attempt) ~= "function"
        or type(ports.transport.new_retry_controller) ~= "function"
        or type(ports.transport.parse_http_headers) ~= "function"
        or type(ports.transport.single_header) ~= "function"
        or type(ports.transport.parse_retry_after) ~= "function"
        or type(ports.safety) ~= "table"
        or type(ports.safety.digest) ~= "function"
        or type(ports.clock) ~= "table"
        or type(ports.clock.monotonic_now) ~= "function"
        or type(ports.clock.utc_now) ~= "function"
        or type(ports.requests) ~= "table"
        or type(ports.requests.prepare) ~= "function"
    then
        return nil, failure("InvalidModelActivityPorts", "model activity ports are incomplete")
    end
    return ports
end

local ACTIVITY_START_FIELDS = {
    request_id = true,
    turn_id = true,
    purpose = true,
    continuation = true,
    view_manifest_ref = true,
    progress_identity = true,
}

local PREPARED_REQUEST_FIELDS = {
    request = true,
    secret_source = true,
    proxy = true,
    ca_bundle_path = true,
    connect_timeout_ms = true,
    total_timeout_ms = true,
}

local function validate_activity_start(spec)
    if not exact_activity_fields(spec, ACTIVITY_START_FIELDS)
        or not valid_token(spec.request_id, 128)
        or not valid_token(spec.turn_id, 128)
        or not PURPOSES[spec.purpose]
        or not valid_token(spec.view_manifest_ref, 256)
        or not valid_token(spec.progress_identity, 256)
        or (spec.continuation ~= false and type(spec.continuation) ~= "table")
    then
        return nil, failure("InvalidModelActivity", "model activity request is invalid")
    end
    return spec
end

local function validate_prepared_request(prepared, spec)
    local request = type(prepared) == "table" and prepared.request or nil
    local policy = type(request) == "table" and request.retry_policy or nil
    if not exact_activity_fields(prepared, PREPARED_REQUEST_FIELDS)
        or type(request) ~= "table"
        or request.request_id ~= spec.request_id
        or request.purpose ~= spec.purpose
        or not exact_activity_fields(policy, { count = true, base_delay_ms = true })
        or not valid_integer(policy.count, 0)
        or not valid_integer(policy.base_delay_ms, 0)
        or (prepared.secret_source ~= false and type(prepared.secret_source) ~= "table")
        or type(prepared.proxy) ~= "table"
        or type(prepared.ca_bundle_path) ~= "string"
        or prepared.ca_bundle_path == ""
        or not valid_integer(prepared.connect_timeout_ms, 1)
        or not valid_integer(prepared.total_timeout_ms, 1)
        or prepared.connect_timeout_ms > prepared.total_timeout_ms
    then
        return nil, failure("InvalidPreparedModelRequest", "prepared request is incomplete or unbound")
    end
    return prepared
end

local REQUEST_BUILDER_OPTION_FIELDS = {
    model_name = true,
    permission_name = true,
    model_snapshot = true,
    permission_snapshot = true,
    prompt_snapshot = true,
    tool_registry_snapshot = true,
    initial_message = true,
    context_prompt = true,
    continuation_instruction = true,
    default_connect_timeout_ms = true,
    default_request_timeout_ms = true,
    default_retry_base_delay_ms = true,
}

local function validate_request_builder(ports, options)
    local port_fields = {
        adapter = true,
        prompt = true,
        views = true,
        generation = true,
        tool_registry = true,
    }
    if not exact_activity_fields(ports, port_fields)
        or type(ports.adapter) ~= "table"
        or type(ports.adapter.normalize_request) ~= "function"
        or type(ports.prompt) ~= "table"
        or type(ports.prompt.assemble) ~= "function"
        or type(ports.views) ~= "table"
        or type(ports.views.resolve_view) ~= "function"
        or type(ports.generation) ~= "table"
        or type(ports.generation.reveal_secret) ~= "function"
        or type(ports.generation.secret_descriptors) ~= "function"
        or type(ports.generation.scan_registered_secrets) ~= "function"
        or type(ports.tool_registry) ~= "table"
        or not exact_activity_fields(options, REQUEST_BUILDER_OPTION_FIELDS)
        or not valid_token(options.model_name, 128)
        or not valid_token(options.permission_name, 128)
        or not valid_token(options.model_snapshot, 256)
        or not valid_token(options.permission_snapshot, 256)
        or not valid_token(options.prompt_snapshot, 256)
        or not valid_token(options.tool_registry_snapshot, 256)
        or type(options.initial_message) ~= "string"
        or options.initial_message == ""
        or type(options.context_prompt) ~= "string"
        or type(options.continuation_instruction) ~= "string"
        or options.continuation_instruction == ""
        or not valid_integer(options.default_connect_timeout_ms, 1)
        or not valid_integer(options.default_request_timeout_ms, 1)
        or options.default_connect_timeout_ms > options.default_request_timeout_ms
        or not valid_integer(options.default_retry_base_delay_ms, 0)
    then
        return nil, failure("InvalidModelRequestBuilder", "model request builder is incomplete")
    end
    local generation = ports.generation
    local model_ref = generation.models and generation.models[options.model_name]
    local permission_ref = generation.permissions
        and generation.permissions[options.permission_name]
    if not valid_token(generation.id, 256)
        or type(generation.general) ~= "table"
        or type(generation.network) ~= "table"
        or type(model_ref) ~= "table"
        or type(permission_ref) ~= "table"
        or model_ref.enabled ~= true
        or model_ref.tools_enabled ~= true
        or ports.tool_registry.digest ~= options.tool_registry_snapshot
    then
        return nil, failure(
            "InvalidModelRequestBuilder",
            "configuration, Model, Permission, or tool snapshot is unavailable"
        )
    end
    return {
        ports = ports,
        options = options,
        generation = generation,
        model = model_ref,
        permission = permission_ref,
    }
end

---Builds exact adapter and transport snapshots for a session's frozen main
-- Model. Secret values remain in ConfigGeneration and are referenced only by
-- their typed carrier identities.
function M.new_request_builder(ports, options)
    local admitted, admission_error = validate_request_builder(ports, options)
    if not admitted then return nil, admission_error end
    local generation = admitted.generation
    local model_ref = admitted.model
    local permission_ref = admitted.permission
    local service = {}

    local function prompt_input(spec)
        if spec.continuation == false then return admitted.options.initial_message end
        return admitted.options.continuation_instruction
    end

    local function proxy_snapshot()
        local configured = generation.network
        if configured.follow_proxy ~= true then return { mode = "off" } end
        if configured.proxy_url_configured == true then
            return {
                mode = "explicit",
                secret_id = "Network.ProxyUrl",
                destination = "network-proxy",
                no_proxy = configured.no_proxy or "",
            }
        end
        if type(configured.proxy_url) == "string" and configured.proxy_url ~= "" then
            return {
                mode = "explicit",
                url = configured.proxy_url,
                no_proxy = configured.no_proxy or "",
            }
        end
        return { mode = "off" }
    end

    function service.prepare(spec)
        local start, start_error = validate_activity_start(spec)
        if not start then return nil, start_error end
        if start.purpose ~= "main" then
            return nil, failure("InvalidModelPurpose", "main request builder received another purpose")
        end
        local called, view, view_error = pcall(
            admitted.ports.views.resolve_view,
            start.view_manifest_ref
        )
        if not called or type(view) ~= "table"
            or view.digest ~= start.view_manifest_ref
            or not valid_integer(view.first_sequence, 0)
            or not valid_integer(view.last_sequence, 0)
            or view.first_sequence > view.last_sequence
            or type(view.body) ~= "string"
        then
            return nil, called and view_error
                or failure("ModelViewUnavailable", "durable model view could not be resolved")
        end
        local bundle, bundle_error = admitted.ports.prompt:assemble({
            purpose = "main",
            config_generation = generation.id,
            layers = {
                global = {
                    source = "General.SystemPrompt",
                    version = generation.id,
                    text = generation.general.system_prompt,
                },
                model = {
                    source = "Model." .. admitted.options.model_name .. ".SystemPrompt",
                    version = generation.id,
                    text = model_ref.system_prompt,
                },
                permission = {
                    source = "Permission." .. admitted.options.permission_name .. ".SystemPrompt",
                    version = generation.id,
                    text = permission_ref.system_prompt,
                },
                context = {
                    source = "ContextPrompt",
                    version = generation.id,
                    text = admitted.options.context_prompt,
                },
            },
            input = { user_message = prompt_input(start) },
            tool_mode = "registered",
        })
        if not bundle then return nil, bundle_error end
        if start.continuation == false and bundle.digest ~= admitted.options.prompt_snapshot then
            return nil, failure(
                "PromptSnapshotMismatch",
                "first Model request does not reproduce the durable Prompt snapshot"
            )
        end
        local public_model_ref = {
            name = admitted.options.model_name,
            protocol = model_ref.protocol,
            endpoint = model_ref.endpoint,
            remote_model = model_ref.remote_model,
            capabilities_digest = admitted.options.model_snapshot,
            adapter_options = model_ref.adapter_options or {},
        }
        if model_ref.key_configured == true then
            public_model_ref.auth_secret_id = "Model."
                .. admitted.options.model_name .. ".Key"
        end
        local limits = {}
        if model_ref.max_output_tokens ~= nil then
            limits.max_output_tokens = model_ref.max_output_tokens
        end
        local retry_count = model_ref.retry_count
        local retry_base_delay = model_ref.retry_base_delay_ms
            or admitted.options.default_retry_base_delay_ms
        local normalized, normalize_error = admitted.ports.adapter:normalize_request({
            request_id = start.request_id,
            purpose = "main",
            model_ref = public_model_ref,
            config_generation = generation.id,
            prompt_bundle = bundle,
            model_view_manifest = {
                digest = view.digest,
                first_sequence = view.first_sequence,
                last_sequence = view.last_sequence,
                body = view.body,
            },
            tool_registry = admitted.ports.tool_registry,
            controls_schema = bundle.controls_schema,
            streaming = model_ref.streaming,
            limits = limits,
            retry_policy = {
                count = retry_count,
                base_delay_ms = retry_base_delay,
            },
        })
        if not normalized then return nil, normalize_error end
        local connect_timeout = generation.network.connect_timeout_ms
            or admitted.options.default_connect_timeout_ms
        local total_timeout = model_ref.request_timeout_ms
            or admitted.options.default_request_timeout_ms
        if connect_timeout > total_timeout then connect_timeout = total_timeout end
        return readonly({
            request = normalized,
            secret_source = generation,
            proxy = freeze(proxy_snapshot(), "model proxy snapshot"),
            ca_bundle_path = generation.network.ca_bundle_path,
            connect_timeout_ms = connect_timeout,
            total_timeout_ms = total_timeout,
        }, "prepared model request")
    end

    service.snapshots = freeze({
        generation = generation.id,
        model = admitted.options.model_snapshot,
        permission = admitted.options.permission_snapshot,
        prompt = admitted.options.prompt_snapshot,
        tools = admitted.options.tool_registry_snapshot,
    }, "model request builder snapshots")
    return readonly(service, "model request builder")
end

local REVIEW_BUILDER_OPTION_FIELDS = {
    main_model_name = true,
    permission_name = true,
    context_prompt = true,
    default_connect_timeout_ms = true,
    default_request_timeout_ms = true,
    default_retry_base_delay_ms = true,
    default_max_output_tokens = true,
    maximum_binding_bytes = true,
}

local REVIEW_START_FIELDS = {
    request_id = true,
    turn_id = true,
    purpose = true,
    binding = true,
    model_snapshot = true,
    config_generation = true,
    view_manifest_ref = true,
    no_tools = true,
}

local ACTION_REVIEW_BINDING_FIELDS = {
    tool_call_id = true,
    operation_id = true,
    adapter_call_id = true,
    provider_call_id = true,
    name = true,
    canonical_arguments = true,
    side_effecting = true,
}

local TERMINATION_REVIEW_BINDING_FIELDS = {
    request_id = true,
    message_id = true,
}

local function review_model_name(generation, options, purpose)
    local configured = purpose == "action-review"
        and generation.agent.action_review_model
        or generation.agent.termination_review_model
    if configured == "" then return options.main_model_name end
    return configured
end

local function json_data(value, visiting)
    local value_type = type(value)
    if value_type == "string" or value_type == "boolean" then return value end
    if value_type == "number" and math.type(value) == "integer" then
        return json.number(tostring(value))
    end
    if value_type ~= "table" then
        return nil, failure("InvalidReviewBinding", "review binding contains non-data")
    end
    visiting = visiting or {}
    if visiting[value] then
        return nil, failure("InvalidReviewBinding", "review binding contains a cycle")
    end
    visiting[value] = true
    local count = dense_count(value)
    local result
    if count ~= nil and count > 0 then
        local values = {}
        for index = 1, count do
            local converted, convert_error = json_data(value[index], visiting)
            if converted == nil then visiting[value] = nil return nil, convert_error end
            values[index] = converted
        end
        result = json.array(values)
    else
        local values = {}
        for key, item in pairs(value) do
            if type(key) ~= "string" then
                visiting[value] = nil
                return nil, failure("InvalidReviewBinding", "review binding keys must be text")
            end
            local converted, convert_error = json_data(item, visiting)
            if converted == nil then visiting[value] = nil return nil, convert_error end
            values[key] = converted
        end
        result = json.object(values)
    end
    visiting[value] = nil
    return result
end

local function validate_review_builder(ports, options)
    local port_fields = {
        adapter = true,
        prompt = true,
        views = true,
        generation = true,
        codec = true,
        safety = true,
    }
    if not exact_activity_fields(ports, port_fields)
        or type(ports.adapter) ~= "table"
        or type(ports.adapter.normalize_request) ~= "function"
        or type(ports.prompt) ~= "table"
        or type(ports.prompt.assemble) ~= "function"
        or type(ports.views) ~= "table"
        or type(ports.views.resolve_view) ~= "function"
        or type(ports.generation) ~= "table"
        or type(ports.generation.reveal_secret) ~= "function"
        or type(ports.codec) ~= "table"
        or type(ports.codec.write) ~= "function"
        or type(ports.safety) ~= "table"
        or type(ports.safety.digest) ~= "function"
        or type(ports.safety.binding_digest) ~= "function"
        or not exact_activity_fields(options, REVIEW_BUILDER_OPTION_FIELDS)
        or not valid_token(options.main_model_name, 128)
        or not valid_token(options.permission_name, 128)
        or type(options.context_prompt) ~= "string"
        or not valid_integer(options.default_connect_timeout_ms, 1)
        or not valid_integer(options.default_request_timeout_ms, 1)
        or options.default_connect_timeout_ms > options.default_request_timeout_ms
        or not valid_integer(options.default_retry_base_delay_ms, 0)
        or not valid_integer(options.default_max_output_tokens, 1)
        or not valid_integer(options.maximum_binding_bytes, 1)
    then
        return nil, failure(
            "InvalidReviewRequestBuilder",
            "review request builder is incomplete"
        )
    end
    local generation = ports.generation
    local permission_ref = generation.permissions
        and generation.permissions[options.permission_name]
    if not valid_token(generation.id, 256)
        or type(generation.general) ~= "table"
        or type(generation.agent) ~= "table"
        or type(generation.network) ~= "table"
        or type(generation.models) ~= "table"
        or type(permission_ref) ~= "table"
    then
        return nil, failure(
            "InvalidReviewRequestBuilder",
            "review configuration or Permission snapshot is unavailable"
        )
    end
    for _, purpose in ipairs({ "action-review", "termination-review" }) do
        local name = review_model_name(generation, options, purpose)
        local model_ref = generation.models[name]
        if not valid_token(name, 128)
            or type(model_ref) ~= "table"
            or model_ref.enabled ~= true
            or type(model_ref.endpoint) ~= "string"
            or model_ref.endpoint == ""
            or type(model_ref.remote_model) ~= "string"
            or model_ref.remote_model == ""
        then
            return nil, failure(
                "InvalidReviewRequestBuilder",
                "selected review Model is unavailable"
            )
        end
    end
    return {
        ports = ports,
        options = options,
        generation = generation,
        permission = permission_ref,
    }
end

local function validate_runtime_review(spec, admitted)
    if not exact_activity_fields(spec, REVIEW_START_FIELDS)
        or not valid_token(spec.request_id, 128)
        or not valid_token(spec.turn_id, 128)
        or (spec.purpose ~= "action-review" and spec.purpose ~= "termination-review")
        or not valid_token(spec.model_snapshot, 256)
        or spec.config_generation ~= admitted.generation.id
        or not valid_token(spec.view_manifest_ref, 256)
        or spec.no_tools ~= true
    then
        return nil, failure("InvalidReviewRequest", "Runtime review request is invalid")
    end
    local expected = spec.purpose == "action-review"
        and ACTION_REVIEW_BINDING_FIELDS
        or TERMINATION_REVIEW_BINDING_FIELDS
    if not exact_activity_fields(spec.binding, expected) then
        return nil, failure("InvalidReviewBinding", "Runtime review binding is invalid")
    end
    if spec.purpose == "action-review" then
        if not valid_token(spec.binding.tool_call_id, 256)
            or not valid_token(spec.binding.operation_id, 256)
            or not valid_token(spec.binding.adapter_call_id, 256)
            or not valid_token(spec.binding.provider_call_id, 256)
            or not DIRECT_TOOL_NAMES[spec.binding.name]
            or type(spec.binding.canonical_arguments) ~= "string"
            or type(spec.binding.side_effecting) ~= "boolean"
        then
            return nil, failure("InvalidReviewBinding", "action-review binding is invalid")
        end
    elseif not valid_token(spec.binding.request_id, 256)
        or not valid_token(spec.binding.message_id, 256)
    then
        return nil, failure("InvalidReviewBinding", "termination-review binding is invalid")
    end
    local tagged, tag_error = json_data(spec.binding)
    if not tagged then return nil, tag_error end
    local binding_json, encode_error = admitted.ports.codec.write(tagged)
    if not binding_json then return nil, encode_error end
    if #binding_json > admitted.options.maximum_binding_bytes then
        return nil, failure("ReviewBindingLimit", "review binding exceeds its byte limit")
    end
    local binding_digest, digest_error = admitted.ports.safety.binding_digest(
        "yaca-review-request-v1",
        {
            { name = "request_id", value = spec.request_id },
            { name = "turn_id", value = spec.turn_id },
            { name = "purpose", value = spec.purpose },
            { name = "model_snapshot", value = spec.model_snapshot },
            { name = "config_generation", value = spec.config_generation },
            { name = "view_manifest_ref", value = spec.view_manifest_ref },
            { name = "binding", value = binding_json },
        }
    )
    if not binding_digest then return nil, digest_error end
    return {
        specification = freeze(spec, "Runtime review specification"),
        binding_json = binding_json,
        binding_digest = binding_digest,
    }
end

---Builds exact no-tool action/termination review requests from Runtime bindings.
-- Runtime-supplied reviewer IDs or verdict bindings are never accepted here;
-- only the later local review adapter may mint them.
function M.new_review_request_builder(ports, options)
    local admitted, admission_error = validate_review_builder(ports, options)
    if not admitted then return nil, admission_error end
    local generation = admitted.generation
    local bound = {}
    local active_count = 0
    local empty_digest, empty_error = admitted.ports.safety.digest(
        "yaca-empty-tool-registry-v1\0[]"
    )
    if not empty_digest then return nil, empty_error end
    local empty_registry = assert(freeze({
        version = "yaca-empty-tool-registry-v1",
        digest = empty_digest,
        tools = {},
    }, "empty review tool registry"))
    local model_digests = {}
    local service = {}

    local function proxy_snapshot()
        local configured = generation.network
        if configured.follow_proxy ~= true then return { mode = "off" } end
        if configured.proxy_url_configured == true then
            return {
                mode = "explicit",
                secret_id = "Network.ProxyUrl",
                destination = "network-proxy",
                no_proxy = configured.no_proxy or "",
            }
        end
        if type(configured.proxy_url) == "string" and configured.proxy_url ~= "" then
            return {
                mode = "explicit",
                url = configured.proxy_url,
                no_proxy = configured.no_proxy or "",
            }
        end
        return { mode = "off" }
    end

    local function model_digest(name, model_ref)
        if model_digests[name] then return model_digests[name] end
        local encoded, encode_error = canonical_value({
            generation = generation.id,
            name = name,
            values = model_ref,
        })
        if not encoded then return nil, encode_error end
        local digest, digest_error = admitted.ports.safety.digest(
            "yaca-review-model-snapshot-v1\0" .. encoded
        )
        if not digest then return nil, digest_error end
        model_digests[name] = digest
        return digest
    end

    function service.bind(spec)
        if active_count ~= 0 then
            return nil, failure("ReviewRequestBusy", "a review request is already bound")
        end
        local binding, binding_error = validate_runtime_review(spec, admitted)
        if not binding then return nil, binding_error end
        bound[spec.request_id] = binding
        active_count = 1
        return freeze({
            request_id = spec.request_id,
            turn_id = spec.turn_id,
            purpose = spec.purpose,
            continuation = false,
            view_manifest_ref = spec.view_manifest_ref,
            progress_identity = "review:" .. binding.binding_digest,
        }, "review model activity specification")
    end

    function service.prepare(spec)
        local start, start_error = validate_activity_start(spec)
        if not start then return nil, start_error end
        local binding = bound[start.request_id]
        if not binding
            or start.purpose ~= binding.specification.purpose
            or start.turn_id ~= binding.specification.turn_id
            or start.view_manifest_ref ~= binding.specification.view_manifest_ref
        then
            return nil, failure("StaleReviewBinding", "review request binding is unavailable")
        end
        local called, view, view_error = pcall(
            admitted.ports.views.resolve_view,
            start.view_manifest_ref
        )
        if not called or type(view) ~= "table"
            or view.digest ~= start.view_manifest_ref
            or not valid_integer(view.first_sequence, 0)
            or not valid_integer(view.last_sequence, 0)
            or view.first_sequence > view.last_sequence
            or type(view.body) ~= "string"
        then
            return nil, called and view_error
                or failure("ModelViewUnavailable", "durable review view could not be resolved")
        end
        local purpose = start.purpose
        local name = review_model_name(generation, admitted.options, purpose)
        local model_ref = generation.models[name]
        local evidence = table.concat({
            "Durable Model view digest=", view.digest,
            " range=", tostring(view.first_sequence), "..", tostring(view.last_sequence),
            " RuntimeBindingDigest=", binding.binding_digest,
            ". Use the separately supplied durable Model view as canonical evidence.",
        })
        local input
        if purpose == "action-review" then
            input = {
                proposed_action = binding.binding_json,
                evidence = evidence,
            }
        else
            input = {
                double_check_goal = generation.effective_double_check_goal or "",
                candidate_report = binding.binding_json,
                evidence = evidence,
            }
        end
        local bundle, bundle_error = admitted.ports.prompt:assemble({
            purpose = purpose,
            config_generation = generation.id,
            layers = {
                global = {
                    source = "General.SystemPrompt",
                    version = generation.id,
                    text = generation.general.system_prompt,
                },
                model = {
                    source = "Model." .. name .. ".SystemPrompt",
                    version = generation.id,
                    text = model_ref.system_prompt,
                },
                permission = {
                    source = "Permission." .. admitted.options.permission_name
                        .. ".SystemPrompt",
                    version = generation.id,
                    text = admitted.permission.system_prompt,
                },
                context = {
                    source = "ContextPrompt",
                    version = generation.id,
                    text = admitted.options.context_prompt,
                },
            },
            input = input,
            tool_mode = "none",
        })
        if not bundle then return nil, bundle_error end
        local capabilities_digest, model_error = model_digest(name, model_ref)
        if not capabilities_digest then return nil, model_error end
        local public_model_ref = {
            name = name,
            protocol = model_ref.protocol,
            endpoint = model_ref.endpoint,
            remote_model = model_ref.remote_model,
            capabilities_digest = capabilities_digest,
            adapter_options = model_ref.adapter_options or {},
        }
        if model_ref.key_configured == true then
            public_model_ref.auth_secret_id = "Model." .. name .. ".Key"
        end
        local retry_count = model_ref.retry_count or 0
        local retry_base_delay = model_ref.retry_base_delay_ms
            or admitted.options.default_retry_base_delay_ms
        local normalized, normalize_error = admitted.ports.adapter:normalize_request({
            request_id = start.request_id,
            purpose = purpose,
            model_ref = public_model_ref,
            config_generation = generation.id,
            prompt_bundle = bundle,
            model_view_manifest = {
                digest = view.digest,
                first_sequence = view.first_sequence,
                last_sequence = view.last_sequence,
                body = view.body,
            },
            tool_registry = empty_registry,
            controls_schema = bundle.controls_schema,
            streaming = model_ref.streaming,
            limits = {
                max_output_tokens = model_ref.max_output_tokens
                    or admitted.options.default_max_output_tokens,
            },
            retry_policy = {
                count = retry_count,
                base_delay_ms = retry_base_delay,
            },
        })
        if not normalized then return nil, normalize_error end
        local connect_timeout = generation.network.connect_timeout_ms
            or admitted.options.default_connect_timeout_ms
        local total_timeout = model_ref.request_timeout_ms
            or admitted.options.default_request_timeout_ms
        if connect_timeout > total_timeout then connect_timeout = total_timeout end
        return readonly({
            request = normalized,
            secret_source = generation,
            proxy = freeze(proxy_snapshot(), "review proxy snapshot"),
            ca_bundle_path = generation.network.ca_bundle_path,
            connect_timeout_ms = connect_timeout,
            total_timeout_ms = total_timeout,
        }, "prepared review request")
    end

    function service.binding(request_id)
        return bound[request_id] or false
    end

    function service.release(request_id)
        if not bound[request_id] then return false end
        bound[request_id] = nil
        active_count = 0
        return true
    end

    service.empty_tool_registry = empty_registry
    return readonly(service, "review request builder")
end

local function transport_category(result)
    if type(result) ~= "table"
        or type(result.response_body) ~= "string"
        or type(result.response_headers) ~= "string"
        or type(result.outcome) ~= "string"
        or type(result.body_truncated) ~= "boolean"
        or type(result.descendants_proven_stopped) ~= "boolean"
    then
        return "outcome-unknown"
    end
    if result.body_truncated or not result.descendants_proven_stopped then
        return "body-outcome-unknown"
    end
    if result.outcome == "cancelled" then return "cancel" end
    if result.outcome == "unknown" then return "outcome-unknown" end
    if result.outcome == "completed"
        and result.exit_kind == "exit-code"
        and result.exit_code == 0
    then
        return "completed"
    end
    if result.response_body ~= "" or result.response_headers ~= "" then
        return "body-outcome-unknown"
    end
    if result.exit_kind == "exit-code" and result.exit_code == 6 then return "dns" end
    if result.exit_kind == "exit-code" and result.exit_code == 7 then return "connect" end
    if result.exit_kind == "exit-code"
        and (result.exit_code == 35 or result.exit_code == 60)
    then
        return "tls-before-body"
    end
    return "outcome-unknown"
end

---Creates the single-active logical Model request coordinator used by
-- AgentLoop. Provider bytes remain behind the HTTP status barrier; only the
-- final canonical adapter response can cross back into Runtime.
function M.new_activity(ports, options)
    local admitted_ports, ports_error = validate_activity_ports(ports)
    if not admitted_ports then return nil, ports_error end
    local admitted, options_error = validate_activity_options(options)
    if not admitted then return nil, options_error end
    local active
    local activity_serial = 0
    local last_now
    local service = {}

    local function now()
        local called, value, clock_error = pcall(admitted_ports.clock.monotonic_now)
        if not called or not valid_integer(value, 0) or last_now and value < last_now then
            return nil, called and (clock_error or failure(
                "MonotonicClockDegraded",
                "model activity clock regressed or returned an invalid tick"
            )) or failure("MonotonicClockDegraded", "model activity clock failed")
        end
        last_now = value
        return value
    end

    local function append_output(activity, value)
        if #activity.output >= admitted.maximum_queued_events then
            return nil, failure("ModelActivityQueueLimit", "model activity output queue is full")
        end
        activity.output[#activity.output + 1] = freeze(value, "model activity event")
        return true
    end

    local function append_adapter_events(activity, events)
        for _, event in ipairs(events or {}) do
            local appended, append_error = append_output(activity, {
                kind = "adapter-event",
                request_id = activity.spec.request_id,
                event = event,
            })
            if not appended then return nil, append_error end
        end
        return true
    end

    local function canonical_wrapper(activity, response)
        local body = response_body(response)
        if #body > admitted.maximum_canonical_body_bytes then
            return nil, failure("CanonicalModelBodyLimit", "canonical assistant body is too large")
        end
        local encoded, encode_error = canonical_value(response)
        if not encoded then return nil, encode_error end
        local called, digest, digest_error = pcall(
            admitted_ports.safety.digest,
            "yaca-model-response-v1\0" .. encoded
        )
        if not called or type(digest) ~= "string" or not digest:match("^[0-9a-f]+$")
            or #digest ~= 64
        then
            return nil, called and digest_error
                or failure("DigestFailure", "canonical response digest failed")
        end
        return freeze({
            request_id = activity.spec.request_id,
            canonical_body = body,
            canonical_digest = digest,
            progress_identity = activity.spec.progress_identity,
            normalized = response,
        }, "canonical model response")
    end

    local function finish_response(activity, events, response, canonical_seen)
        if canonical_seen and not activity.canonical_emitted then
            local observed_now, clock_error = now()
            if not observed_now then return nil, clock_error end
            local observed, observe_error = activity.retry:observe_canonical_event(
                activity.attempt_id,
                observed_now
            )
            if not observed then return nil, observe_error end
            activity.canonical_emitted = true
            local appended, append_error = append_output(activity, {
                kind = "canonical-event",
                request_id = activity.spec.request_id,
            })
            if not appended then return nil, append_error end
        end
        local appended, append_error = append_adapter_events(activity, events)
        if not appended then return nil, append_error end
        local wrapper, wrapper_error = canonical_wrapper(activity, response)
        if not wrapper then return nil, wrapper_error end
        appended, append_error = append_output(activity, {
            kind = "response",
            request_id = activity.spec.request_id,
            wrapper = wrapper,
        })
        if not appended then return nil, append_error end
        activity.state = "terminal"
        return true
    end

    local function terminal_transport_error(activity, error_id)
        local response_session = activity.response_session
        if not response_session then
            local created, create_error = admitted_ports.adapter:new_response(
                activity.prepared.request,
                activity.current_streaming
            )
            if not created then return nil, create_error end
            response_session = created
            activity.response_session = created
        end
        local events, response = response_session:transport_error(error_id)
        if not events then return nil, response end
        return finish_response(activity, events, response, false)
    end

    local function terminal_cancel(activity, error_id)
        local response_session = activity.response_session
        if not response_session then
            local created, create_error = admitted_ports.adapter:new_response(
                activity.prepared.request,
                activity.current_streaming
            )
            if not created then return nil, create_error end
            response_session = created
            activity.response_session = created
        end
        local events, response = response_session:cancel(error_id)
        if not events then return nil, response end
        return finish_response(activity, events, response, false)
    end

    local function close_attempt(activity)
        if not activity.attempt then return true end
        local attempt = activity.attempt
        activity.attempt = nil
        local called, closed = pcall(attempt.close, attempt)
        if not called or closed ~= true then
            return nil, failure("ModelTransportClose", "network attempt cleanup is unknown")
        end
        return true
    end

    local function finish_retry(activity, observation, observed_now)
        local decision, decision_error = activity.retry:finish_attempt(
            activity.attempt_id,
            observation,
            observed_now
        )
        if not decision then return nil, decision_error end
        if decision.action == "wait" then
            activity.state = "waiting"
            activity.waiting = decision
            activity.response_session = nil
            return decision
        end
        return decision
    end

    local function start_attempt(activity, observed_now)
        activity.attempt_serial = activity.attempt_serial + 1
        local attempt_id = "model" .. tostring(activity.serial)
            .. "_attempt" .. tostring(activity.attempt_serial)
        local admission, admission_error = activity.retry:start_attempt(attempt_id, observed_now)
        if not admission then return nil, admission_error end
        local wire, wire_error = admitted_ports.adapter:encode(
            activity.prepared.request,
            activity.streaming_override
        )
        if not wire then return nil, wire_error end
        local response_session, response_error = admitted_ports.adapter:new_response(
            activity.prepared.request,
            activity.streaming_override
        )
        if not response_session then return nil, response_error end
        activity.current_streaming = wire.streaming
        activity.response_session = response_session
        activity.attempt_id = attempt_id
        local remaining = admission.deadline_at - observed_now
        if remaining < 1 then return nil, failure("RequestDeadlineExceeded", "request deadline elapsed") end
        local total_timeout = math.min(activity.prepared.total_timeout_ms, remaining)
        local connect_timeout = math.min(activity.prepared.connect_timeout_ms, total_timeout)
        local attempt, attempt_error = admitted_ports.transport.new_attempt({
            attempt_id = attempt_id,
            url = admission.url,
            method = "POST",
            public_headers = wire.public_headers,
            secret_headers = wire.secret_headers,
            body = wire.body,
            secret_source = activity.prepared.secret_source ~= false
                and activity.prepared.secret_source or nil,
            proxy = activity.prepared.proxy,
            ca_bundle_path = activity.prepared.ca_bundle_path,
            connect_timeout_ms = connect_timeout,
            total_timeout_ms = total_timeout,
        })
        if not attempt then return nil, attempt_error end
        activity.attempt = attempt
        activity.state = "active"
        activity.waiting = nil
        local called, started = pcall(attempt.start, attempt, observed_now)
        if not called or started ~= true then
            activity.attempt = nil
            local decision = activity.retry:finish_attempt(
                attempt_id,
                { category = "outcome-unknown" },
                observed_now
            )
            activity.state = "terminal"
            local finished, finish_error = terminal_transport_error(
                activity,
                decision and decision.code or "transport-start-unknown"
            )
            if not finished then return nil, finish_error end
        end
        return true
    end

    local function canonical_observation(events)
        local canonical, protocol_error, provider_error = false, false, false
        for _, event in ipairs(events) do
            if event.kind == "protocol_error" then
                protocol_error = true
            elseif event.kind == "transport_error" then
                provider_error = true
            else
                canonical = true
            end
        end
        return canonical, protocol_error, provider_error
    end

    local function parse_provider_response(activity, body, observed_now)
        local events = {}
        local pushed, push_error = activity.response_session:push(body)
        if not pushed then return nil, push_error end
        for _, event in ipairs(pushed) do events[#events + 1] = event end
        local tail, response = activity.response_session:finish()
        if not tail then return nil, response end
        for _, event in ipairs(tail) do events[#events + 1] = event end
        local canonical_seen, protocol_error, provider_error = canonical_observation(events)
        if response.incomplete and protocol_error and not provider_error
            and not activity.cancel_requested
        then
            local fallback, fallback_error = admitted_ports.adapter:streaming_fallback(
                activity.prepared.request,
                canonical_seen,
                activity.streaming_fallbacks
            )
            if not fallback then return nil, fallback_error end
            if fallback.allowed then
                local decision, decision_error = activity.retry:streaming_fallback(
                    activity.attempt_id,
                    observed_now
                )
                if not decision then return nil, decision_error end
                activity.streaming_fallbacks = activity.streaming_fallbacks + 1
                activity.streaming_override = fallback.next_streaming
                activity.state = "waiting"
                activity.waiting = decision
                activity.response_session = nil
                return "fallback"
            end
        end
        if canonical_seen then
            if not activity.cancel_requested then
                local observed, observe_error = activity.retry:observe_canonical_event(
                    activity.attempt_id,
                    observed_now
                )
                if not observed then return nil, observe_error end
            end
            activity.canonical_emitted = true
            local appended, append_error = append_output(activity, {
                kind = "canonical-event",
                request_id = activity.spec.request_id,
            })
            if not appended then return nil, append_error end
        end
        if not activity.cancel_requested then
            local category = response.incomplete and "protocol" or "completed"
            local decision, decision_error = finish_retry(activity, {
                category = category,
            }, observed_now)
            if not decision then return nil, decision_error end
            if decision.action == "wait" then
                return nil, failure("ModelRetryContradiction", "canonical response requested a retry")
            end
        end
        local appended, append_error = append_adapter_events(activity, events)
        if not appended then return nil, append_error end
        local wrapper, wrapper_error = canonical_wrapper(activity, response)
        if not wrapper then return nil, wrapper_error end
        appended, append_error = append_output(activity, {
            kind = "response",
            request_id = activity.spec.request_id,
            wrapper = wrapper,
        })
        if not appended then return nil, append_error end
        activity.state = "terminal"
        return "terminal"
    end

    local function retry_after(activity, response, observed_now)
        local value, header_error = admitted_ports.transport.single_header(response, "Retry-After")
        if header_error then return nil, header_error end
        if value == nil then return nil end
        local epoch = 0
        if not value:match("^%d+$") then
            local called, utc_value = pcall(admitted_ports.clock.utc_now)
            epoch = called and utc_epoch(utc_value) or nil
            if not epoch then
                return nil, failure("UtcClockReadFailed", "Retry-After date needs trusted UTC")
            end
        end
        return admitted_ports.transport.parse_retry_after(
            value,
            epoch,
            admitted.retry_manifest.runtime_wait_cap_ms
        )
    end

    local function process_http(activity, result, observed_now)
        local response, header_error = admitted_ports.transport.parse_http_headers(
            result.response_headers,
            {
                maximum_bytes = admitted.maximum_header_bytes,
                maximum_line_bytes = admitted.maximum_header_line_bytes,
                maximum_lines = admitted.maximum_header_lines,
            }
        )
        if not response then
            local decision = finish_retry(activity, { category = "protocol" }, observed_now)
            if not decision then return nil, header_error end
            return terminal_transport_error(activity, "invalid-http-headers")
        end
        local status = response.status
        if activity.cancel_requested then
            if status >= 200 and status <= 299 then
                return parse_provider_response(activity, result.response_body, observed_now)
            end
            local events, normalized = activity.response_session:http_error(
                status,
                "completed-during-cancel",
                false
            )
            if not events then return nil, normalized end
            return finish_response(activity, events, normalized, false)
        end
        if status == 307 or status == 308 then
            local location, location_error = admitted_ports.transport.single_header(
                response,
                "Location"
            )
            if location_error then
                finish_retry(activity, { category = "protocol" }, observed_now)
                return terminal_transport_error(activity, "ambiguous-location")
            end
            local decision, decision_error = finish_retry(activity, {
                category = "completed",
                status = status,
                location = location,
            }, observed_now)
            if not decision then return nil, decision_error end
            if decision.action == "wait" then return "wait" end
            local events, normalized = activity.response_session:http_error(
                status,
                decision.code,
                false
            )
            if not events then return nil, normalized end
            return finish_response(activity, events, normalized, false)
        end
        if status == 429 or status == 503 then
            local delay, delay_error = retry_after(activity, response, observed_now)
            if delay_error then
                finish_retry(activity, { category = "protocol" }, observed_now)
                local events, normalized = activity.response_session:http_error(
                    status,
                    "invalid-retry-after",
                    false
                )
                if not events then return nil, normalized end
                return finish_response(activity, events, normalized, false)
            end
            local observation = { category = "completed", status = status }
            if delay ~= nil then observation.retry_after_ms = delay end
            local decision, decision_error = finish_retry(activity, observation, observed_now)
            if not decision then return nil, decision_error end
            if decision.action == "wait" then return "wait" end
            local events, normalized = activity.response_session:http_error(
                status,
                decision.code,
                false
            )
            if not events then return nil, normalized end
            return finish_response(activity, events, normalized, false)
        end
        if status < 200 or status > 299 then
            local decision, decision_error = finish_retry(activity, {
                category = "content-refusal",
                status = status,
            }, observed_now)
            if not decision then return nil, decision_error end
            local events, normalized = activity.response_session:http_error(
                status,
                decision.code,
                false
            )
            if not events then return nil, normalized end
            return finish_response(activity, events, normalized, false)
        end
        return parse_provider_response(activity, result.response_body, observed_now)
    end

    local function process_terminal(activity, observed_now)
        local attempt = activity.attempt
        local called, result = pcall(attempt.join, attempt, observed_now)
        local closed, close_error = close_attempt(activity)
        if not called or not closed then
            finish_retry(activity, { category = "outcome-unknown" }, observed_now)
            return terminal_transport_error(
                activity,
                not called and "transport-join-unknown" or close_error.code
            )
        end
        local category = transport_category(result)
        if activity.cancel_requested then
            if category == "cancel" then
                return terminal_cancel(activity, "user-cancel")
            elseif category ~= "completed" then
                return terminal_transport_error(activity, "cancel-outcome-unknown")
            end
            return process_http(activity, result, observed_now)
        end
        if category == "completed" then return process_http(activity, result, observed_now) end
        local decision, decision_error = finish_retry(activity, {
            category = category,
        }, observed_now)
        if not decision then return nil, decision_error end
        if decision.action == "wait" then return "wait" end
        if decision.outcome == "cancelled" then
            return terminal_cancel(activity, decision.code)
        end
        return terminal_transport_error(activity, decision.code)
    end

    function service.start(spec)
        if active then return nil, failure("ModelActivityBusy", "a Model request is already active") end
        local start, start_error = validate_activity_start(spec)
        if not start then return nil, start_error end
        local called, prepared, prepare_error = pcall(admitted_ports.requests.prepare, start)
        if not called then
            return nil, failure("ModelRequestPreparation", "request preparation raised an exception")
        end
        prepared, prepare_error = validate_prepared_request(prepared, start)
        if not prepared then return nil, prepare_error end
        if prepared.request.retry_policy.count > admitted.retry_manifest.maximum_count then
            return nil, failure("ModelRetryLimit", "request retry count exceeds the release manifest")
        end
        local observed_now, clock_error = now()
        if not observed_now then return nil, clock_error end
        local function deadline(duration)
            if duration > math.maxinteger - observed_now then return nil end
            return observed_now + duration
        end
        local logical_deadline = deadline(prepared.total_timeout_ms)
        local turn_deadline = deadline(admitted.maximum_turn_time_ms)
        local runtime_deadline = deadline(admitted.maximum_runtime_time_ms)
        if not logical_deadline or not turn_deadline or not runtime_deadline then
            return nil, failure("InvalidDeadline", "model activity deadline overflows")
        end
        local retry, retry_error = admitted_ports.transport.new_retry_controller({
            logical_request_id = start.request_id,
            initial_url = prepared.request.model_ref.endpoint,
            retry_count = prepared.request.retry_policy.count,
            base_delay_ms = prepared.request.retry_policy.base_delay_ms,
            maximum_redirects = admitted.maximum_redirects,
            logical_deadline_at = logical_deadline,
            turn_deadline_at = turn_deadline,
            runtime_deadline_at = runtime_deadline,
            manifest = admitted.retry_manifest,
        })
        if not retry then return nil, retry_error end
        activity_serial = activity_serial + 1
        local handle = freeze({
            request_id = start.request_id,
            serial = activity_serial,
        }, "model activity handle")
        active = {
            serial = activity_serial,
            handle = handle,
            spec = start,
            prepared = prepared,
            retry = retry,
            output = {},
            output_cursor = 1,
            state = "created",
            attempt_serial = 0,
            streaming_override = nil,
            current_streaming = nil,
            streaming_fallbacks = 0,
            canonical_emitted = false,
            cancel_requested = false,
        }
        local started, attempt_error = start_attempt(active, observed_now)
        if not started then active = nil return nil, attempt_error end
        return handle
    end

    function service.cancel(handle, reason)
        if not active or handle ~= active.handle then
            return { outcome = "unknown" }
        end
        if not valid_token(reason, 128) then return { outcome = "unknown" } end
        local observed_now = now()
        if not observed_now then return { outcome = "unknown" } end
        local decision = active.retry:cancel(observed_now)
        active.cancel_requested = true
        if active.state == "waiting" or not active.attempt then
            active = nil
            return { outcome = "cancelled" }
        end
        local called, accepted = pcall(active.attempt.cancel, active.attempt, observed_now)
        if not called then return { outcome = "unknown" } end
        if accepted == true or accepted == false then return { outcome = "pending" } end
        return { outcome = decision and "pending" or "unknown" }
    end

    local function drain(activity, budget)
        local result = {}
        while #result < budget and activity.output_cursor <= #activity.output do
            result[#result + 1] = activity.output[activity.output_cursor]
            activity.output_cursor = activity.output_cursor + 1
        end
        if activity.output_cursor > #activity.output then
            activity.output = {}
            activity.output_cursor = 1
        end
        return result
    end

    function service.poll(budget)
        if not valid_integer(budget, 0) or budget > admitted.maximum_poll_events then
            return nil, failure("InvalidModelPoll", "model poll budget is invalid")
        end
        if not active or budget == 0 then return freeze({}, "model activity batch") end
        local output = drain(active, budget)
        if #output == budget then return freeze(output, "model activity batch") end
        if active.state == "terminal" then
            if #active.output == 0 then active = nil end
            return freeze(output, "model activity batch")
        end
        local observed_now, clock_error = now()
        if not observed_now then return nil, clock_error end
        if active.state == "waiting" then
            if observed_now < active.waiting.resume_at then
                return freeze(output, "model activity batch")
            end
            local started, start_error = start_attempt(active, observed_now)
            if not started then
                terminal_transport_error(active, start_error.code or "attempt-start-failed")
            end
        end
        if active.state == "active" then
            local remaining = budget - #output
            local called, events = pcall(
                active.attempt.poll,
                active.attempt,
                observed_now,
                remaining
            )
            if not called or dense_count(events) == nil or #events > remaining then
                finish_retry(active, { category = "outcome-unknown" }, observed_now)
                terminal_transport_error(active, "transport-poll-unknown")
            else
                local terminal = false
                for _, event in ipairs(events) do
                    if event.kind == "transport_terminal" then terminal = true end
                end
                if terminal then
                    local processed, process_error = process_terminal(active, observed_now)
                    if not processed then
                        terminal_transport_error(
                            active,
                            type(process_error) == "table" and process_error.code
                                or "transport-terminal-failure"
                        )
                    end
                end
            end
        end
        local tail = drain(active, budget - #output)
        for _, event in ipairs(tail) do output[#output + 1] = event end
        if active and active.state == "terminal" and #active.output == 0 then active = nil end
        return freeze(output, "model activity batch")
    end

    function service.status()
        if not active then return freeze({ state = "idle" }, "model activity status") end
        return freeze({
            state = active.state,
            request_id = active.spec.request_id,
            attempt_number = active.attempt_serial,
            streaming_fallbacks = active.streaming_fallbacks,
            cancel_requested = active.cancel_requested,
            waiting_until = active.waiting and active.waiting.resume_at or false,
        }, "model activity status")
    end

    service.capabilities = freeze({
        http_status_barrier = true,
        retries = "runtime-controller",
        redirects = "same-origin-307-308",
        streaming_fallbacks = 1,
        concurrent_requests = 1,
        target_qualified = false,
    }, "model activity capabilities")
    return readonly(service, "model activity service")
end

local REVIEW_PORT_OPTION_FIELDS = {
    maximum_poll_events = true,
    maximum_reason_bytes = true,
    maximum_gap_bytes = true,
}

local function validate_review_port(ports, options)
    if not exact_activity_fields(ports, {
        activity = true,
        builder = true,
        safety = true,
        codec = true,
    })
        or type(ports.activity) ~= "table"
        or type(ports.activity.start) ~= "function"
        or type(ports.activity.cancel) ~= "function"
        or type(ports.activity.poll) ~= "function"
        or type(ports.builder) ~= "table"
        or type(ports.builder.bind) ~= "function"
        or type(ports.builder.binding) ~= "function"
        or type(ports.builder.release) ~= "function"
        or type(ports.safety) ~= "table"
        or type(ports.safety.binding_digest) ~= "function"
        or type(ports.codec) ~= "table"
        or type(ports.codec.parse) ~= "function"
        or not exact_activity_fields(options, REVIEW_PORT_OPTION_FIELDS)
        or not valid_integer(options.maximum_poll_events, 1)
        or not valid_integer(options.maximum_reason_bytes, 1)
        or not valid_integer(options.maximum_gap_bytes, 1)
    then
        return nil, failure("InvalidReviewPort", "review port is incomplete")
    end
    return { ports = ports, options = options }
end

local function valid_review_text(value, maximum, allow_empty)
    if type(value) ~= "string" or #value > maximum or value:find("\0", 1, true)
        or (not allow_empty and value == "")
    then
        return false
    end
    return text.validate_utf8(value) == true
end

local function parsed_review(document, purpose, options)
    if json.kind(document) ~= "object" then return nil end
    if purpose == "action-review" then
        if not exact_activity_fields(document, { verdict = true, reason = true })
            or (document.verdict ~= "pass" and document.verdict ~= "tighten"
                and document.verdict ~= "deny" and document.verdict ~= "uncertain")
            or not valid_review_text(document.reason, options.maximum_reason_bytes, true)
        then
            return nil
        end
        return { verdict = document.verdict, gap = "", reason = document.reason }
    end
    if not exact_activity_fields(document, {
        verdict = true,
        gap = true,
        reason = true,
    })
        or (document.verdict ~= "pass" and document.verdict ~= "gap"
            and document.verdict ~= "uncertain")
        or not valid_review_text(document.gap, options.maximum_gap_bytes, true)
        or not valid_review_text(document.reason, options.maximum_reason_bytes, true)
        or (document.verdict == "gap" and document.gap == "")
        or (document.verdict ~= "gap" and document.gap ~= "")
    then
        return nil
    end
    return {
        verdict = document.verdict,
        gap = document.gap,
        reason = document.reason,
    }
end

---Adapts one canonical Model activity to Runtime's isolated review port.
-- Model text may choose only the bounded verdict fields. Review identity and
-- the exact request/response binding are always computed locally.
function M.new_review_port(ports, options)
    local admitted, admission_error = validate_review_port(ports, options)
    if not admitted then return nil, admission_error end
    local active
    local service = {}

    local function release()
        if not active then return false end
        admitted.ports.builder.release(active.specification.request_id)
        active = nil
        return true
    end

    local function verdict_from(wrapper)
        local binding = admitted.ports.builder.binding(active.specification.request_id)
        if type(binding) ~= "table"
            or type(wrapper) ~= "table"
            or wrapper.request_id ~= active.specification.request_id
            or not valid_token(wrapper.canonical_digest, 256)
            or type(wrapper.canonical_body) ~= "string"
            or type(wrapper.normalized) ~= "table"
        then
            return nil, failure("InvalidReviewResponse", "review response is unbound")
        end
        local normalized = wrapper.normalized
        local parsed
        if normalized.incomplete ~= true
            and normalized.finish_class == "stop"
            and normalized.control == nil
            and dense_count(normalized.tool_calls) == 0
        then
            local document = admitted.ports.codec.parse(wrapper.canonical_body)
            if document then
                parsed = parsed_review(
                    document,
                    active.specification.purpose,
                    admitted.options
                )
            end
        end
        if not parsed then
            parsed = {
                verdict = "uncertain",
                gap = "",
                reason = "Review response was rejected by the exact JSON schema.",
            }
        end
        local verdict_digest, digest_error = admitted.ports.safety.binding_digest(
            "yaca-review-verdict-v1",
            {
                { name = "request_binding", value = binding.binding_digest },
                { name = "response_digest", value = wrapper.canonical_digest },
                { name = "purpose", value = active.specification.purpose },
                { name = "verdict", value = parsed.verdict },
                { name = "gap", value = parsed.gap },
                { name = "reason", value = parsed.reason },
            }
        )
        if not verdict_digest then return nil, digest_error end
        local result = {
            verdict = parsed.verdict,
            review_id = "review-" .. verdict_digest:sub(1, 32),
            binding_digest = verdict_digest,
            reason = parsed.reason,
        }
        if active.specification.purpose == "termination-review" then
            result.gap = parsed.gap
        end
        return freeze(result, "bound review verdict")
    end

    function service.start(specification)
        if active then return nil, failure("ReviewPortBusy", "a review is already active") end
        local activity_spec, binding_error = admitted.ports.builder.bind(specification)
        if not activity_spec then return nil, binding_error end
        local handle, start_error = admitted.ports.activity.start(activity_spec)
        if not handle then
            admitted.ports.builder.release(specification.request_id)
            return nil, start_error
        end
        local binding = admitted.ports.builder.binding(specification.request_id)
        if type(binding) ~= "table" or type(binding.specification) ~= "table" then
            admitted.ports.builder.release(specification.request_id)
            return nil, failure("StaleReviewBinding", "review binding vanished during start")
        end
        local public_handle = freeze({
            request_id = binding.specification.request_id,
            purpose = binding.specification.purpose,
        }, "review activity handle")
        active = {
            handle = public_handle,
            model_handle = handle,
            specification = binding.specification,
        }
        return public_handle
    end

    function service.cancel(handle, reason)
        if not active or handle ~= active.handle or not valid_token(reason, 128) then
            return { outcome = "unknown" }
        end
        local called, result = pcall(
            admitted.ports.activity.cancel,
            active.model_handle,
            reason
        )
        if not called or type(result) ~= "table"
            or (result.outcome ~= "cancelled" and result.outcome ~= "pending"
                and result.outcome ~= "unknown")
        then
            return { outcome = "unknown" }
        end
        if result.outcome == "cancelled" then release() end
        return result
    end

    function service.poll(budget)
        if not valid_integer(budget, 0) or budget > admitted.options.maximum_poll_events then
            return nil, failure("InvalidReviewPoll", "review poll budget is invalid")
        end
        if not active or budget == 0 then return freeze({}, "review poll batch") end
        local events, poll_error = admitted.ports.activity.poll(budget)
        if not events then return nil, poll_error end
        local output = {}
        for _, event in ipairs(events) do
            if event.kind == "response" then
                local verdict, verdict_error = verdict_from(event.wrapper)
                if not verdict then return nil, verdict_error end
                output[#output + 1] = {
                    kind = "verdict",
                    request_id = active.specification.request_id,
                    purpose = active.specification.purpose,
                    verdict = verdict,
                }
                release()
                break
            end
        end
        return freeze(output, "review poll batch")
    end

    function service.status()
        if not active then return freeze({ state = "idle" }, "review port status") end
        return freeze({
            state = "active",
            request_id = active.specification.request_id,
            purpose = active.specification.purpose,
        }, "review port status")
    end

    service.capabilities = freeze({
        purposes = { "action-review", "termination-review" },
        tools = false,
        runtime_bound_identity = true,
        malformed_response = "uncertain",
        concurrent_requests = 1,
    }, "review port capabilities")
    return readonly(service, "review model port")
end

return M
