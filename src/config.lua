--[[
File: config.lua
Date: 2026-08-29
Author: WaterRun
Description: Validates typed configuration generations and publishes safe INI edits.
]]

local ini = require("ini")
local json = require("json")
local safety = require("safety")
local text = require("text")

local M = {}

local draft_states = setmetatable({}, { __mode = "k" })

local function failure(code, message, reason, detail)
    local result = { code = code, message = message }
    if reason ~= nil then result.reason = reason end
    if detail ~= nil then result.detail = detail end
    return result
end

local function readonly(values, label)
    return setmetatable({}, {
        __index = values,
        __newindex = function(_, key)
            error((label or "readonly value") .. " cannot be modified: " .. tostring(key), 2)
        end,
        __pairs = function()
            return next, values, nil
        end,
        __len = function()
            return #values
        end,
        __metatable = "locked",
    })
end

local function valid_integer(value, minimum)
    return math.type(value) == "integer" and value >= minimum
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

local function field(id, section, key, type_name, form, default, extra)
    local result = {
        id = id,
        section = section,
        key = key,
        type = type_name,
        form = form,
        default = default,
    }
    for name, value in pairs(extra or {}) do result[name] = value end
    return result
end

local CATALOG = {
    field("General.SchemaVersion", "General", "SchemaVersion", "schema", "token", nil,
        { required = true }),
    field("Global.SystemPrompt", "General", "SystemPrompt", "text", "text", ""),
    field("General.StartupSelfTest", "General", "StartupSelfTest", "enum", "token", "off",
        { values = { "off", "stage1", "stage2", "stage3" } }),
    field("General.LogLevel", "General", "LogLevel", "enum", "token", "info",
        { values = { "error", "warn", "info", "debug", "trace" } }),

    field("TUI.StartupShowSlogan", "TUI", "StartupShowSlogan", "bool", "token", true),
    field("TUI.StartupShowVersion", "TUI", "StartupShowVersion", "bool", "token", true),
    field("TUI.StartupShowWorkDir", "TUI", "StartupShowWorkDir", "bool", "token", true),
    field("TUI.StartupShowDataRoot", "TUI", "StartupShowDataRoot", "bool", "token", false),
    field("TUI.StartupShowConfigStatus", "TUI", "StartupShowConfigStatus", "bool",
        "token", true),
    field("TUI.StartupShowContext", "TUI", "StartupShowContext", "bool", "token", true),
    field("TUI.StartupShowContextHash", "TUI", "StartupShowContextHash", "bool",
        "token", true),
    field("TUI.StartupShowModel", "TUI", "StartupShowModel", "bool", "token", true),
    field("TUI.StartupShowPermission", "TUI", "StartupShowPermission", "bool",
        "token", true),
    field("TUI.StartupShowDoubleCheck", "TUI", "StartupShowDoubleCheck", "bool",
        "token", true),
    field("TUI.StartupShowStatusHint", "TUI", "StartupShowStatusHint", "bool",
        "token", true),

    field("Agent.DoubleCheck", "Agent", "DoubleCheck", "bool", "token", true),
    field("Agent.DoubleCheckGoal", "Agent", "DoubleCheckGoal", "text", "text", ""),
    field("Agent.ActionReviewEnabled", "Agent", "ActionReviewEnabled", "bool", "token",
        true),
    field("Agent.ActionReviewModel", "Agent", "ActionReviewModel", "model-ref", "text", ""),
    field("Agent.TerminationReviewModel", "Agent", "TerminationReviewModel", "model-ref",
        "text", ""),
    field("Agent.QueueMaxItems", "Agent", "QueueMaxItems", "positive-int", "token", 9,
        { hard_limit = "queue_items" }),
    field("Agent.CompactThreshold", "Agent", "CompactThreshold", "ratio", "token", 0.75),
    field("Agent.MaxTurnModelRequests", "Agent", "MaxTurnModelRequests", "optional-int",
        "token", nil, { hard_limit = "turn_model_requests" }),
    field("Agent.MaxTurnToolCalls", "Agent", "MaxTurnToolCalls", "optional-int", "token",
        nil, { hard_limit = "turn_tool_calls" }),

    field("Network.FollowProxy", "Network", "FollowProxy", "bool", "token", true),
    field("Network.ProxyUrl", "Network", "ProxyUrl", "url-empty", "text", "",
        { conditional_secret = true }),
    field("Network.NoProxy", "Network", "NoProxy", "text", "text", ""),
    field("Network.CaBundlePath", "Network", "CaBundlePath", "path", "text", "release-ca"),
    field("Network.ConnectTimeoutMs", "Network", "ConnectTimeoutMs", "optional-int",
        "token", nil, { hard_limit = "connect_timeout_ms" }),
    field("Network.MaxResponseBytes", "Network", "MaxResponseBytes", "optional-int",
        "token", nil, { hard_limit = "response_bytes" }),

    field("Exec.TimeoutMs", "Exec", "TimeoutMs", "optional-int", "token", nil,
        { hard_limit = "exec_timeout_ms" }),
    field("Exec.MaxOutputKB", "Exec", "MaxOutputKB", "optional-int", "token", 1024,
        { hard_limit = "exec_output_kb" }),
    field("Exec.EnvironmentMode", "Exec", "EnvironmentMode", "enum", "token", "minimal",
        { values = { "minimal", "inherit_filtered" } }),

    field("Context.AutoNameEveryMainTurns", "Context", "AutoNameEveryMainTurns",
        "non-negative-int", "token", 10, { hard_limit = "auto_name_turns" }),
    field("Context.ListSortBy", "Context", "ListSortBy", "enum", "token", "updated",
        { values = { "created", "updated", "name" } }),
    field("Context.ListSortDirection", "Context", "ListSortDirection", "enum", "token",
        "descending", { values = { "ascending", "descending" } }),
    field("Context.RecentListLimit", "Context", "RecentListLimit", "optional-int", "token",
        nil, { hard_limit = "recent_contexts" }),

    field("Permission.*.Description", "Permission.", "Description", "text", "text", ""),
    field("Permission.*.SystemPrompt", "Permission.", "SystemPrompt", "text", "text", ""),
    field("Permission.*.Read", "Permission.", "Read", "enum", "token", nil,
        { required = true, values = { "allow", "confirm", "deny" } }),
    field("Permission.*.Write", "Permission.", "Write", "enum", "token", nil,
        { required = true, values = { "allow", "confirm", "deny" } }),
    field("Permission.*.Delete", "Permission.", "Delete", "enum", "token", nil,
        { required = true, values = { "allow", "confirm", "deny" } }),
    field("Permission.*.Shell", "Permission.", "Shell", "enum", "token", nil,
        { required = true, values = { "allow", "confirm", "deny" } }),
    field("Permission.*.OutsideWorkspace", "Permission.", "OutsideWorkspace", "enum",
        "token", nil, { required = true, values = { "allow", "confirm", "deny" } }),

    field("Model.*.Enabled", "Model.", "Enabled", "bool", "token", false),
    field("Model.*.Description", "Model.", "Description", "text", "text", ""),
    field("Model.*.Protocol", "Model.", "Protocol", "enum", "token", nil,
        { required = true, values = { "openai-chat", "anthropic-messages" } }),
    field("Model.*.Endpoint", "Model.", "Endpoint", "url-empty", "text", ""),
    field("Model.*.RemoteModel", "Model.", "RemoteModel", "text", "text", ""),
    field("Model.*.Key", "Model.", "Key", "text", "text", "", { secret = true }),
    field("Model.*.SystemPrompt", "Model.", "SystemPrompt", "text", "text", ""),
    field("Model.*.ContextLength", "Model.", "ContextLength", "optional-int", "token", nil,
        { hard_limit = "model_context_tokens" }),
    field("Model.*.MaxOutputTokens", "Model.", "MaxOutputTokens", "optional-int", "token",
        nil, { hard_limit = "model_output_tokens" }),
    field("Model.*.Streaming", "Model.", "Streaming", "enum", "token", "try",
        { values = { "force", "try", "off" } }),
    field("Model.*.RequestTimeoutMs", "Model.", "RequestTimeoutMs", "optional-int",
        "token", nil, { hard_limit = "request_timeout_ms" }),
    field("Model.*.RetryCount", "Model.", "RetryCount", "non-negative-int", "token",
        "runtime-retry", { hard_limit = "retry_count" }),
    field("Model.*.RetryBaseDelayMs", "Model.", "RetryBaseDelayMs", "optional-int",
        "token", nil, { hard_limit = "retry_base_delay_ms" }),
    field("Model.*.ToolsEnabled", "Model.", "ToolsEnabled", "bool", "token", true),
    field("Model.*.AdapterOptions", "Model.", "AdapterOptions", "adapter-map", "text", ""),
}

local GROUP_ORDER = {
    "General", "TUI", "Agent", "Network", "Exec", "Context", "Permission.", "Model.",
}

local HARD_LIMIT_NAMES = {
    "queue_items",
    "turn_model_requests",
    "turn_tool_calls",
    "connect_timeout_ms",
    "response_bytes",
    "exec_timeout_ms",
    "exec_output_kb",
    "auto_name_turns",
    "recent_contexts",
    "model_context_tokens",
    "model_output_tokens",
    "request_timeout_ms",
    "retry_count",
    "retry_base_delay_ms",
}

local CONTEXT_KEYS = {
    CurrentModel = true,
    CurrentPermission = true,
    DoubleCheckOverride = true,
    DoubleCheckGoalOverride = true,
    ContextPrompt = true,
    AutoRenameDisabled = true,
}

local MIGRATIONS = {
    ["Model.*.CustomPrompt"] = "copy-exact-then-validate-before-delete",
    ["Permission.*.DoubleCheck"] =
        "diagnostic-explicit-Agent.DoubleCheck-choice-required",
    ["Permission.Cautious"] =
        "diagnostic-explicit-profile-and-session-mapping-required",
    ["Network.UseStunnel"] = "remove-and-explain-external-stunnel-endpoint-route",
    ["Context.AutoJumpToDir"] = "remove-no-equivalent",
    ["Context.ResumeDirectory"] = "remove-no-equivalent",
    ["optional-numeric=false"] =
        "diagnostic-explicit-missing-or-value-choice-required",
}

local function snake_case(value)
    return (value:gsub("(%l)(%u)", "%1_%2"):gsub("(%u)(%u%l)", "%1_%2"):lower())
end

local function config_failure(reason, message, detail)
    return failure("ConfigInvalid", message or "configuration is invalid", reason, detail)
end

local function valid_text(value, maximum_bytes)
    if type(value) ~= "string" or #value > maximum_bytes then return false end
    local valid, metadata = text.validate_utf8(value)
    return valid and not metadata.contains_nul
end

local function valid_absolute_path(value)
    if type(value) ~= "string" or value == "" or value:find("\0", 1, true) then return false end
    local normalized = value:gsub("\\", "/")
    return normalized:sub(1, 1) == "/"
        or normalized:match("^[A-Za-z]:/") ~= nil
        or normalized:match("^//[^/]+/[^/]+") ~= nil
end

local function url_parts(value)
    if type(value) ~= "string" or value:find("[%c%s]") or value:find("#", 1, true) then
        return nil
    end
    local scheme, authority = value:match("^(https?)://([^/%?]+)")
    if not scheme or authority == "" then return nil end
    local host_port = authority:match("@(.+)$") or authority
    local host, port
    if host_port:sub(1, 1) == "[" then
        host, port = host_port:match("^(%[[0-9A-Fa-f:.]+%]):?(%d*)$")
    else
        host, port = host_port:match("^([A-Za-z0-9.-]+):?(%d*)$")
    end
    if not host or host == "" then return nil end
    if port and port ~= "" then
        local port_number = tonumber(port)
        if not port_number or port_number < 1 or port_number > 65535 then return nil end
    end
    return scheme, authority
end

local function valid_host_patterns(value)
    if value == "" then return true end
    for item in (value .. ","):gmatch("([^,]*),") do
        local trimmed = item:match("^[ \t]*(.-)[ \t]*$")
        if trimmed == "" or not trimmed:match("^[A-Za-z0-9.*:%-]+$") then return false end
    end
    return true
end

local function valid_name(value, maximum_bytes)
    if not valid_text(value, maximum_bytes) or value == ""
        or value:match("^[%s]") or value:match("[%s]$")
        or value:find(".", 1, true) or value:find("/", 1, true)
        or value:find("\\", 1, true) or value:find("[", 1, true)
        or value:find("]", 1, true)
    then
        return false
    end
    return true
end

local function parse_integer(token, minimum, maximum)
    if type(token) ~= "string"
        or not (token == "0" or token:match("^[1-9][0-9]*$"))
    then
        return nil
    end
    local value = tonumber(token)
    if math.type(value) ~= "integer" or value < minimum or value > maximum then return nil end
    return value
end

local function enum_set(values)
    local result = {}
    for _, value in ipairs(values or {}) do result[value] = true end
    return result
end

local function validate_adapter_schemas(input)
    if input == nil then return {} end
    if type(input) ~= "table" then
        return nil, failure("InvalidConfigOptions", "adapter option schemas must be a table")
    end
    local result = {}
    for protocol, fields in pairs(input) do
        if (protocol ~= "openai-chat" and protocol ~= "anthropic-messages")
            or type(fields) ~= "table"
        then
            return nil, failure("InvalidConfigOptions", "adapter option protocol is invalid")
        end
        local admitted = {}
        for key, declaration in pairs(fields) do
            if type(key) ~= "string" or not key:match("^[A-Za-z][A-Za-z0-9_]*$")
                or type(declaration) ~= "table"
            then
                return nil, failure("InvalidConfigOptions", "adapter option field is invalid")
            end
            for name in pairs(declaration) do
                if name ~= "type" and name ~= "secret" then
                    return nil, failure(
                        "InvalidConfigOptions",
                        "adapter option declaration has an unknown field"
                    )
                end
            end
            if declaration.type ~= "string"
                and declaration.type ~= "boolean"
                and declaration.type ~= "integer"
            then
                return nil, failure("InvalidConfigOptions", "adapter option type is invalid")
            end
            if declaration.secret ~= nil and type(declaration.secret) ~= "boolean" then
                return nil, failure("InvalidConfigOptions", "adapter secret flag is invalid")
            end
            admitted[key] = { type = declaration.type, secret = declaration.secret == true }
        end
        result[protocol] = admitted
    end
    return result
end

local function validate_options(options)
    if type(options) ~= "table" then
        return nil, failure("InvalidConfigOptions", "configuration options are required")
    end
    local allowed = {
        schema_version = true,
        release_ca_path = true,
        ini_limits = true,
        hard_limits = true,
        runtime_defaults = true,
        maximum_text_bytes = true,
        maximum_name_bytes = true,
        maximum_adapter_options_bytes = true,
        maximum_hash_chunk_bytes = true,
        minimum_scannable_secret_bytes = true,
        adapter_option_schemas = true,
    }
    for key in pairs(options) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure("InvalidConfigOptions", "config options contain an unknown field")
        end
    end
    if type(options.schema_version) ~= "string" or options.schema_version == ""
        or not valid_absolute_path(options.release_ca_path)
        or not valid_integer(options.maximum_text_bytes, 1)
        or not valid_integer(options.maximum_name_bytes, 1)
        or options.maximum_name_bytes > options.maximum_text_bytes
        or not valid_integer(options.maximum_adapter_options_bytes, 1)
        or options.maximum_adapter_options_bytes > options.maximum_text_bytes
        or not valid_integer(options.maximum_hash_chunk_bytes, 1)
        or not valid_integer(options.minimum_scannable_secret_bytes, 1)
        or #options.release_ca_path > options.maximum_text_bytes
        or not options.schema_version:match("^[0-9A-Za-z_.%-]+$")
    then
        return nil, failure("InvalidConfigOptions", "config scalar limits are invalid")
    end
    if type(options.ini_limits) ~= "table" or type(options.hard_limits) ~= "table"
        or type(options.runtime_defaults) ~= "table"
    then
        return nil, failure("InvalidConfigOptions", "INI and runtime limits are required")
    end
    local ini_names = {
        maximum_bytes = true,
        maximum_lines = true,
        maximum_line_bytes = true,
        maximum_value_bytes = true,
    }
    for key in pairs(options.ini_limits) do
        if not ini_names[key] then
            return nil, failure("InvalidConfigOptions", "INI limits contain an unknown field")
        end
    end
    for name in pairs(ini_names) do
        if not valid_integer(options.ini_limits[name], 1) then
            return nil, failure("InvalidConfigOptions", "INI limits are incomplete")
        end
    end
    local hard_names = {}
    for _, name in ipairs(HARD_LIMIT_NAMES) do hard_names[name] = true end
    for key in pairs(options.hard_limits) do
        if not hard_names[key] then
            return nil, failure("InvalidConfigOptions", "hard limits contain an unknown field")
        end
    end
    for _, name in ipairs(HARD_LIMIT_NAMES) do
        local minimum = (name == "retry_count" or name == "auto_name_turns") and 0 or 1
        if not valid_integer(options.hard_limits[name], minimum) then
            return nil, failure("InvalidConfigOptions", "hard limits are incomplete")
        end
    end
    for key in pairs(options.runtime_defaults) do
        if key ~= "retry_count" then
            return nil, failure("InvalidConfigOptions", "runtime defaults contain an unknown field")
        end
    end
    if not valid_integer(options.runtime_defaults.retry_count, 0)
        or options.runtime_defaults.retry_count > options.hard_limits.retry_count
        or options.hard_limits.queue_items < 9
        or options.hard_limits.exec_output_kb < 1024
        or options.hard_limits.auto_name_turns < 10
    then
        return nil, failure("InvalidConfigOptions", "runtime defaults exceed hard limits")
    end
    local adapter_schemas, adapter_error = validate_adapter_schemas(
        options.adapter_option_schemas
    )
    if not adapter_schemas then return nil, adapter_error end
    return {
        schema_version = options.schema_version,
        release_ca_path = options.release_ca_path,
        ini_limits = options.ini_limits,
        hard_limits = options.hard_limits,
        runtime_defaults = options.runtime_defaults,
        maximum_text_bytes = options.maximum_text_bytes,
        maximum_name_bytes = options.maximum_name_bytes,
        maximum_adapter_options_bytes = options.maximum_adapter_options_bytes,
        maximum_hash_chunk_bytes = options.maximum_hash_chunk_bytes,
        minimum_scannable_secret_bytes = options.minimum_scannable_secret_bytes,
        adapter_option_schemas = adapter_schemas,
    }
end

local function validate_ports(ports)
    if type(ports) ~= "table" then
        return nil, failure("InvalidConfigPorts", "configuration ports are required")
    end
    for key in pairs(ports) do
        if key ~= "sha256" and key ~= "filesystem" then
            return nil, failure(
                "InvalidConfigPorts",
                "configuration ports contain an unknown field"
            )
        end
    end
    if type(ports.sha256) ~= "table" then
        return nil, failure("InvalidConfigPorts", "SHA-256 port is required")
    end
    if ports.filesystem ~= nil then
        if type(ports.filesystem) ~= "table" then
            return nil, failure("InvalidConfigPorts", "filesystem port is invalid")
        end
        for _, method in ipairs({
            "open_read", "create_new", "stat_identity", "stream_read", "stream_write",
            "flush_file", "flush_directory", "replace", "rename_no_replace",
            "delete_verified", "close",
        }) do
            if type(ports.filesystem[method]) ~= "function" then
                return nil, failure("InvalidConfigPorts", "filesystem port is incomplete")
            end
        end
        local capabilities = ports.filesystem.capabilities
        if type(capabilities) ~= "table"
            or not valid_integer(capabilities.maximum_chunk_bytes, 1)
        then
            return nil, failure("InvalidConfigPorts", "filesystem capabilities are invalid")
        end
    end
    return { sha256 = ports.sha256, filesystem = ports.filesystem }
end

local function build_ini_schema(limits)
    local grouped = {}
    for _, name in ipairs(GROUP_ORDER) do grouped[name] = {} end
    for _, descriptor in ipairs(CATALOG) do
        local fields = grouped[descriptor.section]
        fields[#fields + 1] = { key = descriptor.key, form = descriptor.form }
    end
    local sections = {}
    for _, name in ipairs(GROUP_ORDER) do
        local declaration = { fields = grouped[name] }
        if name:sub(-1) == "." then
            declaration.prefix = name
        else
            declaration.name = name
        end
        sections[#sections + 1] = declaration
    end
    return ini.new({
        maximum_bytes = limits.maximum_bytes,
        maximum_lines = limits.maximum_lines,
        maximum_line_bytes = limits.maximum_line_bytes,
        maximum_value_bytes = limits.maximum_value_bytes,
        sections = sections,
    })
end

local function build_json_codec(maximum_bytes)
    return json.new({
        maximum_bytes = maximum_bytes,
        maximum_depth = 4,
        maximum_nodes = 128,
        maximum_string_bytes = maximum_bytes,
        maximum_number_bytes = 32,
    })
end

local function descriptors_by_section()
    local result = {}
    for _, descriptor in ipairs(CATALOG) do
        local group = result[descriptor.section]
        if not group then
            group = { ordered = {}, by_key = {} }
            result[descriptor.section] = group
        end
        group.ordered[#group.ordered + 1] = descriptor
        group.by_key[descriptor.key] = descriptor
    end
    return result
end

local DESCRIPTORS = descriptors_by_section()

local function section_family(name)
    if DESCRIPTORS[name] then return name end
    if type(name) == "string" and name:sub(1, 11) == "Permission." then
        return "Permission."
    end
    if type(name) == "string" and name:sub(1, 6) == "Model." then return "Model." end
    return nil
end

local function duplicate_section(source)
    local seen = {}
    source = source:gsub("^\239\187\191", "", 1)
    for record in (source .. "\n"):gmatch("([^\n]*)\n") do
        local line = record
        if line:sub(-1) == "\r" then line = line:sub(1, -2) end
        local name = line:match("^[ \t]*%[([^%]]+)%]")
        if name then
            if seen[name] then return name end
            seen[name] = true
        end
    end
    return nil
end

local function migration_advice(source)
    if type(source) ~= "string" then return {} end
    local result, seen = {}, {}
    local current
    local function add(source_id)
        if seen[source_id] then return end
        seen[source_id] = true
        result[#result + 1] = {
            source = source_id,
            action = assert(MIGRATIONS[source_id]),
        }
    end
    source = source:gsub("^\239\187\191", "", 1)
    for record in (source .. "\n"):gmatch("([^\n]*)\n") do
        local line = record
        if line:sub(-1) == "\r" then line = line:sub(1, -2) end
        local section = line:match("^[ \t]*%[([^%]]+)%]")
        if section then
            current = section
            if section == "Permission.Cautious" then add("Permission.Cautious") end
        else
            local key, raw = line:match("^[ \t]*([A-Za-z][A-Za-z0-9_]*)[ \t]*=[ \t]*(.*)$")
            if key and current then
                if current:sub(1, 6) == "Model." and key == "CustomPrompt" then
                    add("Model.*.CustomPrompt")
                elseif current:sub(1, 11) == "Permission." and key == "DoubleCheck" then
                    add("Permission.*.DoubleCheck")
                elseif current == "Network" and key == "UseStunnel" then
                    add("Network.UseStunnel")
                elseif current == "Context" and key == "AutoJumpToDir" then
                    add("Context.AutoJumpToDir")
                elseif current == "Context" and key == "ResumeDirectory" then
                    add("Context.ResumeDirectory")
                else
                    local family = section_family(current)
                    local descriptor = family and DESCRIPTORS[family].by_key[key]
                    if descriptor and descriptor.type == "optional-int" then
                        local token = raw:match("^([^ \t;#]+)")
                        if token == "false" then add("optional-numeric=false") end
                    end
                end
            end
        end
    end
    return result
end

local function default_value(descriptor, options)
    if descriptor.default == "release-ca" then return options.release_ca_path end
    if descriptor.default == "runtime-retry" then
        return options.runtime_defaults.retry_count
    end
    return descriptor.default
end

local function decode_adapter_map(source, protocol, options, json_codec)
    if source == "" then return {}, {} end
    if #source > options.maximum_adapter_options_bytes then
        return nil, config_failure("adapter-options-limit")
    end
    local parsed, parse_error = json_codec.parse(source)
    if not parsed or json.kind(parsed) ~= "object" then
        return nil, config_failure(
            "adapter-options-json",
            "configuration adapter options are invalid",
            parse_error and parse_error.code
        )
    end
    local schema = options.adapter_option_schemas[protocol] or {}
    local public, secret_values = {}, {}
    for key, value in pairs(parsed) do
        local declaration = schema[key]
        if not declaration then return nil, config_failure("adapter-option-unknown") end
        local kind = json.kind(value)
        local decoded = value
        if declaration.type == "integer" then
            if kind ~= "number" then return nil, config_failure("adapter-option-type") end
            local lexeme = assert(json.number_lexeme(value))
            decoded = parse_integer(lexeme, 0, options.hard_limits.model_context_tokens)
            if decoded == nil then return nil, config_failure("adapter-option-type") end
        elseif kind ~= declaration.type then
            return nil, config_failure("adapter-option-type")
        end
        if declaration.secret then
            if type(decoded) ~= "string" or decoded == "" then
                return nil, config_failure("adapter-secret-type")
            end
            secret_values[key] = decoded
            public[key] = { registered_secret = true }
        else
            public[key] = decoded
        end
    end
    return public, secret_values
end

local function decode_field(wrapped, descriptor, section, options, json_codec, protocol)
    if wrapped == nil then
        if descriptor.required then return nil, config_failure("required-field") end
        return default_value(descriptor, options)
    end
    local raw = assert(ini.value(wrapped))
    local kind = descriptor.type
    if kind == "schema" then
        if raw ~= options.schema_version then return nil, config_failure("schema-version") end
        return raw
    end
    if kind == "text" or kind == "model-ref" then
        if not valid_text(raw, options.maximum_text_bytes) then
            return nil, config_failure("text-limit")
        end
        if descriptor.id == "Network.NoProxy" and not valid_host_patterns(raw) then
            return nil, config_failure("host-pattern-list")
        end
        return raw
    end
    if kind == "path" then
        if not valid_text(raw, options.maximum_text_bytes) or not valid_absolute_path(raw) then
            return nil, config_failure("path")
        end
        return raw
    end
    if kind == "url-empty" then
        if not valid_text(raw, options.maximum_text_bytes)
            or (raw ~= "" and not url_parts(raw))
        then
            return nil, config_failure("url")
        end
        return raw
    end
    if kind == "bool" then
        if raw == "true" then return true end
        if raw == "false" then return false end
        return nil, config_failure("boolean")
    end
    if kind == "enum" then
        if not enum_set(descriptor.values)[raw] then return nil, config_failure("enum") end
        return raw
    end
    if kind == "ratio" then
        if not raw:match("^0%.[0-9]+$") then return nil, config_failure("ratio") end
        local value = tonumber(raw)
        if not value or value <= 0 or value >= 1 then return nil, config_failure("ratio") end
        return value
    end
    if kind == "positive-int" or kind == "optional-int" or kind == "non-negative-int" then
        if raw == "false" then return nil, config_failure("numeric-false-migration") end
        local minimum = kind == "non-negative-int" and 0 or 1
        local maximum = descriptor.hard_limit
            and options.hard_limits[descriptor.hard_limit]
            or options.hard_limits.model_context_tokens
        local value = parse_integer(raw, minimum, maximum)
        if value == nil then return nil, config_failure("integer-limit") end
        return value
    end
    if kind == "adapter-map" then
        return decode_adapter_map(raw, protocol, options, json_codec)
    end
    return nil, config_failure("catalog-type", "configuration catalog type is unsupported", {
        section = section,
        key = descriptor.key,
    })
end

local function copy_public_section(values, secret_keys)
    local result = {}
    for key, value in pairs(values) do
        local normalized = snake_case(key)
        if secret_keys and secret_keys[key] then
            result[normalized .. "_configured"] = value ~= ""
        else
            result[normalized] = value
        end
    end
    return result
end

local function context_signature(overrides)
    local parts = {}
    for _, key in ipairs({
        "CurrentModel", "CurrentPermission", "DoubleCheckOverride",
        "DoubleCheckGoalOverride", "ContextPrompt", "AutoRenameDisabled",
    }) do
        local value = overrides[key]
        local kind = type(value)
        if value == nil then
            parts[#parts + 1] = key .. ":0:"
        elseif kind == "string" then
            parts[#parts + 1] = key .. ":s" .. #value .. ":" .. value
        elseif kind == "boolean" then
            parts[#parts + 1] = key .. ":b:" .. tostring(value)
        end
    end
    return table.concat(parts, "\0")
end

local function validate_overrides(overrides, maximum_text_bytes)
    if overrides == nil then return {} end
    if type(overrides) ~= "table" then return nil, config_failure("context-overrides-type") end
    local result = {}
    for key, value in pairs(overrides) do
        if type(key) ~= "string" or not CONTEXT_KEYS[key] then
            return nil, config_failure("context-override-unknown")
        end
        result[key] = value
    end
    for _, key in ipairs({ "CurrentModel", "CurrentPermission", "ContextPrompt" }) do
        if result[key] ~= nil and not valid_text(result[key], maximum_text_bytes) then
            return nil, config_failure("context-override-text")
        end
    end
    local double = result.DoubleCheckOverride
    if double ~= nil and double ~= "inherit" and type(double) ~= "boolean" then
        return nil, config_failure("context-doublecheck")
    end
    local goal = result.DoubleCheckGoalOverride
    if goal ~= nil and not valid_text(goal, maximum_text_bytes) then
        return nil, config_failure("context-doublecheck-goal")
    end
    if result.AutoRenameDisabled ~= nil and type(result.AutoRenameDisabled) ~= "boolean" then
        return nil, config_failure("context-auto-rename")
    end
    return result
end

local function identity_equal(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then return false end
    for _, key in ipairs({ "kind", "volume", "object", "size", "modified" }) do
        if left[key] ~= right[key] then return false end
    end
    return true
end

local function directory_of(path)
    if type(path) ~= "string" then return nil end
    local index
    for offset = #path, 1, -1 do
        local byte = path:byte(offset)
        if byte == 0x2F or byte == 0x5C then
            index = offset
            break
        end
    end
    if not index then return nil end
    if index == 1 then return path:sub(1, 1) end
    if index == 3 and path:sub(2, 2) == ":" then return path:sub(1, 3) end
    return path:sub(1, index - 1)
end

local function same_directory(left, right)
    local left_directory, right_directory = directory_of(left), directory_of(right)
    if not left_directory or not right_directory then return false end
    return left_directory:gsub("\\", "/") == right_directory:gsub("\\", "/")
end

local function new_draft(owner, state)
    local draft = readonly({}, "configuration draft")
    state.owner = owner
    draft_states[draft] = state
    return draft
end

---Creates the strict v0.1 typed configuration service.
-- Runtime hard maxima are mandatory injected values; the user INI can only
-- select values at or below them. No ambient environment or project file is read.
-- @param ports table SHA-256 port and optional narrow filesystem service.
-- @param options table Schema, INI, text, secret, and Runtime hard limits.
-- @return table|nil service Immutable configuration service.
-- @return table|nil err Structured construction failure.
function M.new(ports, options)
    local admitted_ports, ports_error = validate_ports(ports)
    if not admitted_ports then return nil, ports_error end
    local admitted, options_error = validate_options(options)
    if not admitted then return nil, options_error end
    local ini_codec, ini_error = build_ini_schema(admitted.ini_limits)
    if not ini_codec then return nil, ini_error end
    local json_codec, json_error = build_json_codec(admitted.maximum_adapter_options_bytes)
    if not json_codec then return nil, json_error end
    local safety_service, safety_error = safety.new(admitted_ports.sha256, {
        maximum_hash_chunk_bytes = admitted.maximum_hash_chunk_bytes,
        minimum_scannable_secret_bytes = admitted.minimum_scannable_secret_bytes,
    })
    if not safety_service then return nil, safety_error end

    local owner = {}
    local generation_number = 0
    local current_generation
    local current_binding
    local service = {}

    local function freeze(value, label)
        local frozen, freeze_error = safety_service.freeze(value, label)
        if not frozen then error(freeze_error.message, 2) end
        return frozen
    end

    local function parse_generation(source, context_overrides, publish_number)
        if type(source) ~= "string" then return nil, config_failure("source-type") end
        local overrides, override_error = validate_overrides(
            context_overrides,
            admitted.maximum_text_bytes
        )
        if not overrides then return nil, override_error end
        local duplicated = duplicate_section(source)
        if duplicated then return nil, config_failure("duplicate-section") end
        local document, parse_error = ini_codec.parse(source)
        if not document then
            return nil, config_failure("ini", "configuration INI is invalid", {
                code = parse_error.code,
                line = parse_error.line,
                column = parse_error.column,
                reason = parse_error.reason,
            })
        end
        local section_names = assert(ini_codec.sections(document))
        local exact = {}
        local permission_order, model_order = {}, {}
        for _, name in ipairs(section_names) do
            local family = section_family(name)
            if family == "Permission." then
                local suffix = name:sub(#family + 1)
                if not valid_name(suffix, admitted.maximum_name_bytes) then
                    return nil, config_failure("permission-name")
                end
                permission_order[#permission_order + 1] = suffix
            elseif family == "Model." then
                local suffix = name:sub(#family + 1)
                if not valid_name(suffix, admitted.maximum_name_bytes) then
                    return nil, config_failure("model-name")
                end
                model_order[#model_order + 1] = suffix
            end
        end
        if #permission_order == 0 then return nil, config_failure("permission-missing") end
        if #model_order == 0 then return nil, config_failure("model-missing") end

        local secret_entries = {}
        local secret_lookup = {}
        local warnings = {}
        local public = {
            permissions = {},
            models = {},
            permission_order = permission_order,
            model_order = model_order,
        }
        local function add_secret(id, class, value, destinations)
            if value == "" then return end
            secret_entries[#secret_entries + 1] = {
                id = id,
                class = class,
                value = value,
                destinations = destinations,
            }
            secret_lookup[id] = true
        end

        for _, group_name in ipairs({ "General", "TUI", "Agent", "Network", "Exec", "Context" }) do
            local values = {}
            for _, descriptor in ipairs(DESCRIPTORS[group_name].ordered) do
                local wrapped = ini_codec.get(document, group_name, descriptor.key)
                local decoded, decode_error = decode_field(
                    wrapped,
                    descriptor,
                    group_name,
                    admitted,
                    json_codec
                )
                if decoded == nil and decode_error then return nil, decode_error end
                values[descriptor.key] = decoded
            end
            exact[group_name] = values
            public[snake_case(group_name)] = copy_public_section(values)
        end

        local proxy_url = exact.Network.ProxyUrl
        local proxy_authority
        if proxy_url ~= "" then
            local ignored
            ignored, proxy_authority = url_parts(proxy_url)
        end
        if proxy_authority and proxy_authority:find("@", 1, true) then
            add_secret("Network.ProxyUrl", "proxy-credential-url", proxy_url, {
                "network-proxy",
            })
            public.network.proxy_url = nil
            public.network.proxy_url_configured = true
        end

        for _, name in ipairs(permission_order) do
            local section = "Permission." .. name
            local values = {}
            for _, descriptor in ipairs(DESCRIPTORS["Permission."].ordered) do
                local wrapped = ini_codec.get(document, section, descriptor.key)
                local decoded, decode_error = decode_field(
                    wrapped,
                    descriptor,
                    section,
                    admitted,
                    json_codec
                )
                if decoded == nil and decode_error then return nil, decode_error end
                values[descriptor.key] = decoded
            end
            exact[section] = values
            public.permissions[name] = copy_public_section(values)
        end

        local usable_models = 0
        for _, name in ipairs(model_order) do
            local section = "Model." .. name
            local values = {}
            local protocol_wrapped = ini_codec.get(document, section, "Protocol")
            local protocol_descriptor = DESCRIPTORS["Model."].by_key.Protocol
            local protocol, protocol_error = decode_field(
                protocol_wrapped,
                protocol_descriptor,
                section,
                admitted,
                json_codec
            )
            if not protocol then return nil, protocol_error end
            values.Protocol = protocol
            local adapter_secrets = {}
            for _, descriptor in ipairs(DESCRIPTORS["Model."].ordered) do
                if descriptor.key ~= "Protocol" then
                    local wrapped = ini_codec.get(document, section, descriptor.key)
                    local decoded, second_or_error = decode_field(
                        wrapped,
                        descriptor,
                        section,
                        admitted,
                        json_codec,
                        protocol
                    )
                    if decoded == nil and second_or_error then return nil, second_or_error end
                    values[descriptor.key] = decoded
                    if descriptor.type == "adapter-map" then
                        adapter_secrets = second_or_error or {}
                        values.AdapterOptions = freeze(
                            values.AdapterOptions,
                            "model adapter options"
                        )
                    end
                end
            end
            if values.Enabled and (values.Endpoint == "" or values.RemoteModel == "") then
                return nil, config_failure("enabled-model-incomplete")
            end
            local endpoint_authority
            if values.Endpoint ~= "" then
                local ignored
                ignored, endpoint_authority = url_parts(values.Endpoint)
            end
            if endpoint_authority and endpoint_authority:find("@", 1, true) then
                return nil, config_failure("endpoint-credentials")
            end
            if values.Streaming == "force" and values.Enabled == false then
                return nil, config_failure("forced-streaming-disabled-model")
            end
            if values.Enabled then usable_models = usable_models + 1 end
            local model_public = copy_public_section(values, { Key = true })
            public.models[name] = model_public
            exact[section] = values
            add_secret("Model." .. name .. ".Key", "model-key", values.Key, {
                "model-auth:" .. name,
            })
            for key, value in pairs(adapter_secrets) do
                add_secret(
                    "Model." .. name .. ".AdapterOptions." .. key,
                    "model-adapter-option",
                    value,
                    { "model-adapter:" .. name .. ":" .. key }
                )
            end
            if values.Enabled and values.Endpoint:sub(1, 7) == "http://" and values.Key ~= "" then
                warnings[#warnings + 1] = {
                    code = "PlainHttpCredential",
                    model = name,
                }
            end
        end
        if usable_models == 0 then return nil, config_failure("enabled-model-missing") end

        for _, key in ipairs({ "ActionReviewModel", "TerminationReviewModel" }) do
            local reference = exact.Agent[key]
            if reference ~= "" then
                local candidate = exact["Model." .. reference]
                if not candidate or not candidate.Enabled then
                    return nil, config_failure("reviewer-model")
                end
            end
        end

        local current_model = overrides.CurrentModel or model_order[1]
        local current_permission = overrides.CurrentPermission or permission_order[1]
        if not exact["Model." .. current_model] then
            return nil, config_failure("current-model")
        end
        if not exact["Permission." .. current_permission] then
            return nil, config_failure("current-permission")
        end
        local effective_double_check = exact.Agent.DoubleCheck
        if overrides.DoubleCheckOverride ~= nil and overrides.DoubleCheckOverride ~= "inherit" then
            effective_double_check = overrides.DoubleCheckOverride
        end
        local effective_goal = exact.Agent.DoubleCheckGoal
        if overrides.DoubleCheckGoalOverride ~= nil
            and overrides.DoubleCheckGoalOverride ~= "inherit"
        then
            effective_goal = overrides.DoubleCheckGoalOverride
        end
        local selected_model = exact["Model." .. current_model]
        local agent_ready = selected_model.Enabled
            and selected_model.Endpoint ~= ""
            and selected_model.RemoteModel ~= ""
            and selected_model.ToolsEnabled
        public.current_model = current_model
        public.current_permission = current_permission
        public.default_model = model_order[1]
        public.default_permission = permission_order[1]
        public.effective_double_check = effective_double_check
        public.effective_double_check_goal = effective_goal
        public.context_prompt = overrides.ContextPrompt or ""
        public.auto_rename_disabled = overrides.AutoRenameDisabled == true
        public.agent_ready = agent_ready
        if not agent_ready then public.agent_block_reason = "SelectedModelUnavailable" end
        public.warnings = warnings
        public.id = "config-generation-" .. tostring(publish_number)
        public.schema_version = admitted.schema_version

        local registry, registry_error = safety_service.secret_registry(secret_entries)
        if not registry then return nil, registry_error end
        local function public_secret_match(value, visited)
            if type(value) == "string" then
                return #assert(registry.scan(value)) > 0
            end
            if type(value) ~= "table" or visited[value] then return false end
            visited[value] = true
            for key, item in pairs(value) do
                if public_secret_match(key, visited) or public_secret_match(item, visited) then
                    return true
                end
            end
            return false
        end
        if public_secret_match(public, {}) then
            return nil, config_failure("registered-secret-cross-field")
        end
        local frozen_public = freeze(public, "configuration generation")
        local facade = {}
        for key, value in pairs(frozen_public) do facade[key] = value end

        ---Looks up one exact catalog value without exposing registered secrets.
        -- @param section string Exact singleton or family section name.
        -- @param key string Exact PascalCase field key.
        -- @return any value Immutable scalar or adapter map.
        -- @return table|nil err Unknown or secret-field failure.
        function facade.get(section, key)
            if type(section) ~= "string" or type(key) ~= "string" then
                return nil, failure("InvalidConfigSelector", "config selector must be strings")
            end
            local values = exact[section]
            local family = section_family(section)
            local descriptor = family and DESCRIPTORS[family].by_key[key]
            if not values or not descriptor then
                return nil, failure("UnknownConfigField", "config field is unknown")
            end
            local id = section .. "." .. key
            if secret_lookup[id] then
                return nil, failure("RegisteredSecret", "config field is a registered secret")
            end
            if values[key] == nil then return nil end
            return values[key]
        end

        ---Reveals a registered value only to its exact private destination.
        function facade.reveal_secret(id, destination)
            return registry.reveal(id, destination)
        end

        ---Returns non-secret registry descriptors for diagnostics and scanners.
        function facade.secret_descriptors()
            return registry.descriptors()
        end

        ---Scans ordinary bytes against release-eligible registered values.
        function facade.scan_registered_secrets(bytes)
            return registry.scan(bytes)
        end

        ---Creates the cross-chunk scanner used by bounded process output. Raw
        -- bytes remain private to the scanner until it proves the terminal
        -- ToolResult contains no registered configuration secret.
        function facade.new_stream_scanner()
            return registry.new_stream_scanner()
        end

        return readonly(facade, "configuration generation"), document, overrides
    end

    local function read_file(path)
        local filesystem = admitted_ports.filesystem
        if not filesystem then
            return nil, failure("ConfigFilesystemUnavailable", "filesystem service is unavailable")
        end
        local opened, handle_or_error = filesystem.open_read(path)
        if not opened then return nil, handle_or_error end
        local handle = handle_or_error
        local identity_ok, identity_or_error = filesystem.stat_identity(handle)
        if not identity_ok then
            filesystem.close(handle)
            return nil, identity_or_error
        end
        local parts, size = {}, 0
        while true do
            local remaining = admitted.ini_limits.maximum_bytes - size
            if remaining == 0 then
                local probed, probe_or_error = filesystem.stream_read(handle, 1)
                if not probed then
                    filesystem.close(handle)
                    return nil, probe_or_error
                end
                if probe_or_error.eof and #probe_or_error.bytes == 0 then break end
                filesystem.close(handle)
                return nil, config_failure("source-limit")
            end
            local amount = math.min(
                remaining,
                filesystem.capabilities.maximum_chunk_bytes
            )
            local read_ok, chunk_or_error = filesystem.stream_read(handle, amount)
            if not read_ok then
                filesystem.close(handle)
                return nil, chunk_or_error
            end
            local chunk = chunk_or_error
            size = size + #chunk.bytes
            parts[#parts + 1] = chunk.bytes
            if chunk.eof then break end
            if #chunk.bytes == 0 then
                filesystem.close(handle)
                return nil, failure("ConfigFilesystemContract", "file read made no progress")
            end
        end
        local restated, final_identity_or_error = filesystem.stat_identity(handle)
        if not restated then
            filesystem.close(handle)
            return nil, final_identity_or_error
        end
        if not identity_equal(identity_or_error, final_identity_or_error) then
            filesystem.close(handle)
            return nil, failure("ConfigReadUnstable", "configuration changed while read")
        end
        local closed, close_error = filesystem.close(handle)
        if not closed then return nil, close_error end
        return table.concat(parts), identity_or_error
    end

    local function private_digest(source)
        local result, digest_error = safety_service.digest(source)
        if not result then return nil, digest_error end
        return result
    end

    local function check_edit_base(state)
        local source, identity_or_error = read_file(state.path)
        if not source then return nil, identity_or_error end
        local digest_value, digest_error = private_digest(source)
        if not digest_value then return nil, digest_error end
        if digest_value ~= state.base_digest
            or not identity_equal(identity_or_error, state.base_identity)
        then
            return nil, failure(
                "ConfigStale",
                "configuration changed after the edit transaction began"
            )
        end
        return true
    end

    local function target_absent(path)
        local filesystem = admitted_ports.filesystem
        if not filesystem then
            return nil, failure("ConfigFilesystemUnavailable", "filesystem service is unavailable")
        end
        local opened, handle_or_error = filesystem.open_read(path)
        if opened then
            local closed, close_error = filesystem.close(handle_or_error)
            if not closed then return nil, close_error end
            return false, failure("ConfigConflict", "configuration target already exists")
        end
        if type(handle_or_error) == "table" and handle_or_error.code == "NotFound" then
            return true
        end
        return nil, handle_or_error
    end

    local function cleanup_temporary(path, identity)
        local filesystem = admitted_ports.filesystem
        local stated, observed = filesystem.stat_identity(path)
        if stated then identity = observed end
        if identity then filesystem.delete_verified(path, identity) end
    end

    local function write_temporary(path, source)
        local filesystem = admitted_ports.filesystem
        local created, handle_or_error = filesystem.create_new(path, 384)
        if not created then return nil, handle_or_error end
        local handle = handle_or_error
        local offset = 1
        while offset <= #source do
            local bytes = source:sub(
                offset,
                offset + filesystem.capabilities.maximum_chunk_bytes - 1
            )
            local written, write_error = filesystem.stream_write(handle, bytes)
            if not written then
                filesystem.close(handle)
                cleanup_temporary(path)
                return nil, write_error
            end
            offset = offset + #bytes
        end
        local flushed, flush_error = filesystem.flush_file(handle)
        if not flushed then
            filesystem.close(handle)
            cleanup_temporary(path)
            return nil, flush_error
        end
        local stated, identity_or_error = filesystem.stat_identity(handle)
        if not stated then
            filesystem.close(handle)
            cleanup_temporary(path)
            return nil, identity_or_error
        end
        local closed, close_error = filesystem.close(handle)
        if not closed then
            cleanup_temporary(path, identity_or_error)
            return nil, close_error
        end
        return identity_or_error
    end

    local function verify_temporary(path, expected, context_overrides)
        local observed, identity_or_error = read_file(path)
        if not observed then return nil, identity_or_error end
        if observed ~= expected then
            return nil, failure("ConfigTemporaryMismatch", "temporary config bytes changed")
        end
        local generation, parse_error = parse_generation(
            observed,
            context_overrides,
            generation_number + 1
        )
        if not generation then return nil, parse_error end
        return identity_or_error
    end

    local function descriptor_for(section, key)
        local family = section_family(section)
        return family and DESCRIPTORS[family].by_key[key] or nil
    end

    local function encode_change(descriptor, value)
        if descriptor.form == "text" then
            if type(value) ~= "string" then return nil, config_failure("edit-value-type") end
            return ini.text(value)
        end
        if descriptor.type == "bool" then
            if type(value) ~= "boolean" then return nil, config_failure("edit-value-type") end
            return ini.token(tostring(value))
        end
        if descriptor.type == "ratio" then
            if type(value) ~= "number" then return nil, config_failure("edit-value-type") end
            return ini.token(tostring(value))
        end
        if type(value) == "number" then
            if math.type(value) ~= "integer" then return nil, config_failure("edit-value-type") end
            return ini.token(tostring(value))
        end
        if type(value) ~= "string" then return nil, config_failure("edit-value-type") end
        return ini.token(value)
    end

    local function build_values_source(sections)
        local count = dense_count(sections)
        if not count or count == 0 then
            return nil, failure(
                "InvalidConfigValues",
                "configuration values must contain a non-empty section array"
            )
        end
        local encoded, seen_sections = {}, {}
        for index, section in ipairs(sections) do
            if type(section) ~= "table"
                or type(section.name) ~= "string"
                or type(section.values) ~= "table"
            then
                return nil, failure(
                    "InvalidConfigValues",
                    "configuration value section is invalid"
                )
            end
            for key in pairs(section) do
                if key ~= "name" and key ~= "values" then
                    return nil, failure(
                        "InvalidConfigValues",
                        "configuration value section contains an unknown field"
                    )
                end
            end
            if seen_sections[section.name] or not section_family(section.name) then
                return nil, failure(
                    "InvalidConfigValues",
                    "configuration value section is unknown or repeated"
                )
            end
            seen_sections[section.name] = true
            local values = {}
            for key, value in pairs(section.values) do
                if type(key) ~= "string" or value == service.unset then
                    return nil, failure(
                        "InvalidConfigValues",
                        "configuration value field is invalid"
                    )
                end
                local descriptor = descriptor_for(section.name, key)
                if not descriptor then
                    return nil, failure(
                        "InvalidConfigValues",
                        "configuration value field is unknown"
                    )
                end
                local wrapped, wrap_error = encode_change(descriptor, value)
                if not wrapped then return nil, wrap_error end
                values[key] = wrapped
            end
            encoded[index] = { name = section.name, values = values }
        end
        local document, build_error = ini_codec.build(encoded)
        if not document then return nil, build_error end
        local source, write_error = ini_codec.write(document, {
            preserve_concrete = false,
        })
        if not source then return nil, write_error end
        return source
    end

    local function rebuild_without(document, changes)
        local removals, replacements = {}, {}
        for _, change in ipairs(changes) do
            local identity = change.section .. "\0" .. change.key
            if change.value == service.unset then
                removals[identity] = true
            else
                replacements[identity] = assert(encode_change(
                    assert(descriptor_for(change.section, change.key)),
                    change.value
                ))
            end
        end
        local sections, present = {}, {}
        for _, name in ipairs(assert(ini_codec.sections(document))) do
            present[name] = true
            local family = assert(section_family(name))
            local values = {}
            for _, descriptor in ipairs(DESCRIPTORS[family].ordered) do
                local identity = name .. "\0" .. descriptor.key
                if replacements[identity] then
                    values[descriptor.key] = replacements[identity]
                elseif not removals[identity] then
                    values[descriptor.key] = ini_codec.get(document, name, descriptor.key)
                end
            end
            sections[#sections + 1] = { name = name, values = values }
        end
        for _, change in ipairs(changes) do
            if not present[change.section] and change.value ~= service.unset then
                present[change.section] = true
                local family = assert(section_family(change.section))
                local values = {}
                for _, descriptor in ipairs(DESCRIPTORS[family].ordered) do
                    local identity = change.section .. "\0" .. descriptor.key
                    if replacements[identity] then
                        values[descriptor.key] = replacements[identity]
                    end
                end
                sections[#sections + 1] = { name = change.section, values = values }
            end
        end
        return ini_codec.build(sections)
    end

    ---Parses a complete candidate without changing the service's current generation.
    function service.parse(source, context_overrides)
        local generation, generation_or_error = parse_generation(
            source,
            context_overrides,
            generation_number + 1
        )
        if not generation then return nil, generation_or_error end
        return generation
    end

    ---Publishes one validated immutable generation, reusing an identical binding.
    function service.reload(source, context_overrides)
        local overrides, override_error = validate_overrides(
            context_overrides,
            admitted.maximum_text_bytes
        )
        if not overrides then return nil, override_error end
        local digest_value, digest_error = private_digest(source)
        if not digest_value then return nil, digest_error end
        local binding = digest_value .. ":" .. context_signature(overrides)
        if current_generation and binding == current_binding then return current_generation end
        local next_number = generation_number + 1
        local generation, parse_error = parse_generation(source, overrides, next_number)
        if not generation then return nil, parse_error end
        generation_number = next_number
        current_generation = generation
        current_binding = binding
        return generation
    end

    ---Reads and validates the complete INI bytes at a top-level turn boundary.
    function service.reload_file(path, context_overrides)
        local source, read_error = read_file(path)
        if not source then return nil, read_error end
        return service.reload(source, context_overrides)
    end

    ---Returns the last successfully published generation, if any.
    function service.current()
        return current_generation
    end

    ---Returns only typed migration actions; no source values are projected.
    function service.migration_advice(source)
        return freeze(migration_advice(source), "configuration migration advice")
    end

    ---Begins a stale-bound edit of an existing complete configuration file.
    function service.begin_edit(path, context_overrides)
        if not valid_absolute_path(path) then
            return nil, failure("InvalidConfigPath", "config edit path must be absolute")
        end
        local source, identity_or_error = read_file(path)
        if not source then return nil, identity_or_error end
        local generation, document_or_error, overrides = parse_generation(
            source,
            context_overrides,
            generation_number + 1
        )
        if not generation then return nil, document_or_error end
        local digest_value, digest_error = private_digest(source)
        if not digest_value then return nil, digest_error end
        return new_draft(owner, {
            mode = "replace",
            path = path,
            base_digest = digest_value,
            base_identity = identity_or_error,
            candidate_source = source,
            document = document_or_error,
            generation = generation,
            context_overrides = overrides,
            consumed = false,
        })
    end

    ---Begins a no-replace transaction for a complete new configuration.
    function service.begin_new(path, source, context_overrides)
        if not valid_absolute_path(path) then
            return nil, failure("InvalidConfigPath", "new config path must be absolute")
        end
        local absent, absence_error = target_absent(path)
        if not absent then return nil, absence_error end
        local generation, document_or_error, overrides = parse_generation(
            source,
            context_overrides,
            generation_number + 1
        )
        if not generation then return nil, document_or_error end
        return new_draft(owner, {
            mode = "create",
            path = path,
            candidate_source = source,
            document = document_or_error,
            generation = generation,
            context_overrides = overrides,
            consumed = false,
        })
    end

    ---Begins a no-replace transaction from typed semantic section values.
    -- Secret fields remain values inside the draft and are never returned in a
    -- public generation or diagnostic. The complete candidate must validate
    -- before a draft handle is issued.
    function service.begin_new_values(path, sections, context_overrides)
        local source, source_error = build_values_source(sections)
        if not source then return nil, source_error end
        return service.begin_new(path, source, context_overrides)
    end

    ---Begins a replace transaction only when an invalid bootstrap source still
    -- matches exact caller-owned bytes. This narrow path lets the offline setup
    -- flow replace its own repair template without accepting or discarding an
    -- arbitrary invalid user configuration.
    function service.begin_exact_repair_values(
        path,
        expected_source,
        sections,
        context_overrides
    )
        if not valid_absolute_path(path)
            or type(expected_source) ~= "string"
            or expected_source == ""
        then
            return nil, failure(
                "InvalidConfigPath",
                "exact config repair requires an absolute path and expected source"
            )
        end
        local current_source, identity_or_error = read_file(path)
        if not current_source then return nil, identity_or_error end
        if current_source ~= expected_source then
            return nil, failure(
                "ConfigRepairMismatch",
                "configuration does not match the owned bootstrap repair template"
            )
        end
        local candidate_source, source_error = build_values_source(sections)
        if not candidate_source then return nil, source_error end
        local generation, document_or_error, overrides = parse_generation(
            candidate_source,
            context_overrides,
            generation_number + 1
        )
        if not generation then return nil, document_or_error end
        local digest_value, digest_error = private_digest(current_source)
        if not digest_value then return nil, digest_error end
        return new_draft(owner, {
            mode = "replace",
            path = path,
            base_digest = digest_value,
            base_identity = identity_or_error,
            candidate_source = candidate_source,
            document = document_or_error,
            generation = generation,
            context_overrides = overrides,
            consumed = false,
        })
    end

    ---Applies a bounded transaction-sized set of typed semantic changes.
    function service.edit_draft(draft, changes)
        local state = draft_states[draft]
        if not state or state.owner ~= owner or state.consumed then
            return nil, failure("InvalidConfigDraft", "configuration draft is stale or foreign")
        end
        local count = dense_count(changes)
        if not count or count == 0 then
            return nil, failure("InvalidConfigEdit", "config changes must be a non-empty array")
        end
        local encoded, seen, has_removal = {}, {}, false
        for index, change in ipairs(changes) do
            if type(change) ~= "table" or type(change.section) ~= "string"
                or type(change.key) ~= "string"
            then
                return nil, failure("InvalidConfigEdit", "config change shape is invalid")
            end
            for key in pairs(change) do
                if key ~= "section" and key ~= "key" and key ~= "value" then
                    return nil, failure("InvalidConfigEdit", "config change has an unknown field")
                end
            end
            local descriptor = descriptor_for(change.section, change.key)
            if not descriptor then
                return nil, failure("InvalidConfigEdit", "config field is unknown")
            end
            local identity = change.section .. "\0" .. change.key
            if seen[identity] then
                return nil, failure("InvalidConfigEdit", "config change repeats")
            end
            seen[identity] = true
            if change.value == service.unset then
                if descriptor.required then
                    return nil, failure(
                        "InvalidConfigEdit",
                        "required config field cannot be unset"
                    )
                end
                has_removal = true
            else
                local wrapped, encode_error = encode_change(descriptor, change.value)
                if not wrapped then return nil, encode_error end
                encoded[index] = {
                    section = change.section,
                    key = change.key,
                    value = wrapped,
                }
            end
        end
        local document, edit_error
        if has_removal then
            document, edit_error = rebuild_without(state.document, changes)
        else
            document, edit_error = ini_codec.edit(state.document, encoded)
        end
        if not document then return nil, edit_error end
        local source, write_error = ini_codec.write(document, { preserve_concrete = true })
        if not source then return nil, write_error end
        local generation, parsed_document_or_error, overrides = parse_generation(
            source,
            state.context_overrides,
            generation_number + 1
        )
        if not generation then return nil, parsed_document_or_error end
        local next_state = {}
        for key, value in pairs(state) do next_state[key] = value end
        next_state.candidate_source = source
        next_state.document = parsed_document_or_error
        next_state.generation = generation
        next_state.context_overrides = overrides
        return new_draft(owner, next_state)
    end

    ---Returns the immutable non-secret generation represented by a draft.
    function service.draft_generation(draft)
        local state = draft_states[draft]
        if not state or state.owner ~= owner or state.consumed then
            return nil, failure("InvalidConfigDraft", "configuration draft is stale or foreign")
        end
        return state.generation
    end

    ---Publishes a same-directory temporary after revalidation and stale checks.
    function service.commit_draft(draft, temporary_path)
        local state = draft_states[draft]
        if not state or state.owner ~= owner or state.consumed then
            return nil, failure("InvalidConfigDraft", "configuration draft is stale or foreign")
        end
        if type(temporary_path) ~= "string" or temporary_path == state.path
            or not valid_absolute_path(temporary_path)
            or not same_directory(temporary_path, state.path)
        then
            return nil, failure(
                "InvalidConfigPath",
                "temporary config must be a distinct same-directory absolute path"
            )
        end
        if state.mode == "replace" then
            local unchanged, stale_error = check_edit_base(state)
            if not unchanged then return nil, stale_error end
        else
            local absent, absence_error = target_absent(state.path)
            if not absent then return nil, absence_error end
        end
        local temporary_identity, write_error = write_temporary(
            temporary_path,
            state.candidate_source
        )
        if not temporary_identity then return nil, write_error end
        local verified_identity, verify_error = verify_temporary(
            temporary_path,
            state.candidate_source,
            state.context_overrides
        )
        if not verified_identity then
            cleanup_temporary(temporary_path, temporary_identity)
            return nil, verify_error
        end
        if not identity_equal(temporary_identity, verified_identity) then
            cleanup_temporary(temporary_path, verified_identity)
            return nil, failure("ConfigTemporaryMismatch", "temporary config identity changed")
        end
        if state.mode == "replace" then
            local unchanged, stale_error = check_edit_base(state)
            if not unchanged then
                cleanup_temporary(temporary_path, verified_identity)
                return nil, stale_error
            end
        end
        local restated, final_temporary_or_error = admitted_ports.filesystem.stat_identity(
            temporary_path
        )
        if not restated
            or not identity_equal(verified_identity, final_temporary_or_error)
        then
            cleanup_temporary(
                temporary_path,
                restated and final_temporary_or_error or verified_identity
            )
            return nil, restated and failure(
                "ConfigTemporaryMismatch",
                "temporary config identity changed before publication"
            ) or final_temporary_or_error
        end
        local published, publish_error
        if state.mode == "replace" then
            published, publish_error = admitted_ports.filesystem.replace(
                temporary_path,
                state.path
            )
        else
            published, publish_error = admitted_ports.filesystem.rename_no_replace(
                temporary_path,
                state.path
            )
        end
        if not published then
            cleanup_temporary(temporary_path, verified_identity)
            return nil, publish_error
        end
        state.consumed = true
        local directory = assert(directory_of(state.path))
        local flushed, flush_error = admitted_ports.filesystem.flush_directory(directory)
        if not flushed then
            return nil, failure(
                "ConfigPublishUnknown",
                "configuration was replaced but directory durability is unknown",
                nil,
                flush_error.code
            )
        end
        return service.reload(state.candidate_source, state.context_overrides)
    end

    local catalog_public = {}
    for index, descriptor in ipairs(CATALOG) do
        catalog_public[index] = {
            id = descriptor.id,
            section = descriptor.section == "Permission." and "Permission.*"
                or descriptor.section == "Model." and "Model.*"
                or descriptor.section,
            key = descriptor.key,
            type = descriptor.type,
            secret = descriptor.secret == true,
            required = descriptor.required == true,
        }
    end
    service.catalog = freeze(catalog_public, "configuration catalog")
    service.unset = readonly({}, "configuration unset sentinel")
    service.schema_version = admitted.schema_version
    service.target_atomic_write_qualified = false
    return readonly(service, "configuration service")
end

return M
