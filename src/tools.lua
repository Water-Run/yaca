--[[
File: tools.lua
Date: 2026-08-29
Author: WaterRun
Description: Defines the closed tool registry and verified direct-file operations.
]]

local text = require("text")
local json = require("json")

local M = {}

local REGISTRY_VERSION = "yaca-tools-v0.1.0"
local SCHEMA_VERSION = "1.0.0"
local TOOL_ORDER = {
    "list", "read", "search", "write", "patch", "rename", "delete", "exec",
}
local DIRECT_TOOLS = {
    list = true,
    read = true,
    search = true,
    write = true,
    patch = true,
    rename = true,
    delete = true,
}
local MUTATING_TOOLS = {
    write = true,
    patch = true,
    rename = true,
    delete = true,
}
local OPERATION_TOOLS = {
    write = true,
    patch = true,
    rename = true,
    delete = true,
    exec = true,
}

local arrays = setmetatable({}, { __mode = "k" })

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

local function exact_fields(value, allowed)
    if type(value) ~= "table" then return false end
    for key in pairs(value) do
        if type(key) ~= "string" or not allowed[key] then return false end
    end
    return true
end

local function array(values)
    arrays[values] = true
    return values
end

local function copy_array(values)
    local count = dense_count(values)
    if count == nil then return nil end
    local result = {}
    for index = 1, count do result[index] = values[index] end
    return array(result)
end

local function json_escape(value)
    local valid = text.validate_utf8(value)
    if valid ~= true then return nil end
    local output = { '"' }
    local index = 1
    while index <= #value do
        local byte = value:byte(index)
        if byte == 0x22 then
            output[#output + 1] = '\\"'
            index = index + 1
        elseif byte == 0x5C then
            output[#output + 1] = "\\\\"
            index = index + 1
        elseif byte == 0x08 then
            output[#output + 1] = "\\b"
            index = index + 1
        elseif byte == 0x09 then
            output[#output + 1] = "\\t"
            index = index + 1
        elseif byte == 0x0A then
            output[#output + 1] = "\\n"
            index = index + 1
        elseif byte == 0x0C then
            output[#output + 1] = "\\f"
            index = index + 1
        elseif byte == 0x0D then
            output[#output + 1] = "\\r"
            index = index + 1
        elseif byte < 0x20 then
            output[#output + 1] = string.format("\\u%04x", byte)
            index = index + 1
        else
            output[#output + 1] = string.char(byte)
            index = index + 1
        end
    end
    output[#output + 1] = '"'
    return table.concat(output)
end

local function canonical_json(value, visiting)
    local value_type = type(value)
    if value_type == "string" then
        return json_escape(value)
    elseif value_type == "boolean" then
        return value and "true" or "false"
    elseif math.type(value) == "integer" then
        return tostring(value)
    elseif value_type ~= "table" then
        return nil, failure("InvalidCanonicalValue", "canonical value type is unsupported")
    end
    visiting = visiting or {}
    if visiting[value] then
        return nil, failure("InvalidCanonicalValue", "canonical value must not contain cycles")
    end
    visiting[value] = true
    local output = {}
    if arrays[value] then
        local count = dense_count(value)
        if count == nil then
            visiting[value] = nil
            return nil, failure("InvalidCanonicalValue", "canonical array must be dense")
        end
        output[#output + 1] = "["
        for index = 1, count do
            if index > 1 then output[#output + 1] = "," end
            local encoded, encode_error = canonical_json(value[index], visiting)
            if not encoded then visiting[value] = nil; return nil, encode_error end
            output[#output + 1] = encoded
        end
        output[#output + 1] = "]"
    else
        local keys = {}
        for key in pairs(value) do
            if type(key) ~= "string" then
                visiting[value] = nil
                return nil, failure("InvalidCanonicalValue", "canonical object keys must be strings")
            end
            keys[#keys + 1] = key
        end
        table.sort(keys)
        output[#output + 1] = "{"
        for index, key in ipairs(keys) do
            if index > 1 then output[#output + 1] = "," end
            local encoded_key = assert(json_escape(key))
            local encoded, encode_error = canonical_json(value[key], visiting)
            if not encoded then visiting[value] = nil; return nil, encode_error end
            output[#output + 1] = encoded_key
            output[#output + 1] = ":"
            output[#output + 1] = encoded
        end
        output[#output + 1] = "}"
    end
    visiting[value] = nil
    return table.concat(output)
end

local function schema_array(values)
    return array(values)
end

local IDENTITY_SCHEMA = {
    type = "object",
    additionalProperties = false,
    required = schema_array({ "kind", "volume", "object", "size", "modified" }),
    properties = {
        kind = { type = "string" },
        volume = { type = "string" },
        object = { type = "string" },
        size = { type = "integer", minimum = 0 },
        modified = { type = "string" },
    },
}

local STRING_ARRAY_SCHEMA = {
    type = "array",
    items = { type = "string" },
}

local HUNK_SCHEMA = {
    type = "object",
    additionalProperties = false,
    required = schema_array({
        "start_line", "context_before", "delete_lines", "insert_lines",
        "context_after", "newline", "final_newline",
    }),
    properties = {
        start_line = { type = "integer", minimum = 1 },
        context_before = STRING_ARRAY_SCHEMA,
        delete_lines = STRING_ARRAY_SCHEMA,
        insert_lines = STRING_ARRAY_SCHEMA,
        context_after = STRING_ARRAY_SCHEMA,
        newline = { type = "string", enum = schema_array({ "lf", "crlf", "cr" }) },
        final_newline = { type = "boolean" },
    },
}

local SCHEMAS = {
    list = {
        type = "object", additionalProperties = false,
        required = schema_array({ "path", "depth", "page_size" }),
        properties = {
            path = { type = "string" },
            depth = { type = "integer", minimum = 0 },
            page_size = { type = "integer", minimum = 1 },
            continuation = { type = "string" },
        },
    },
    read = {
        type = "object", additionalProperties = false,
        required = schema_array({ "path", "start_line", "max_lines" }),
        properties = {
            path = { type = "string" },
            start_line = { type = "integer", minimum = 1 },
            max_lines = { type = "integer", minimum = 1 },
        },
    },
    search = {
        type = "object", additionalProperties = false,
        required = schema_array({
            "path", "pattern", "dialect", "case_sensitive", "page_size",
        }),
        properties = {
            path = { type = "string" },
            pattern = { type = "string" },
            dialect = {
                type = "string",
                enum = schema_array({ "literal", "lua-pattern-v1" }),
            },
            case_sensitive = { type = "boolean" },
            page_size = { type = "integer", minimum = 1 },
            continuation = { type = "string" },
        },
    },
    write = {
        type = "object", additionalProperties = false,
        required = schema_array({ "path", "mode", "content", "encoding", "newline_policy" }),
        properties = {
            path = { type = "string" },
            mode = { type = "string", enum = schema_array({ "create", "replace" }) },
            content = { type = "string" },
            encoding = {
                type = "string",
                enum = schema_array({
                    "utf-8", "utf-8-bom", "utf-16le-bom", "utf-16be-bom",
                }),
            },
            newline_policy = {
                type = "string",
                enum = schema_array({ "preserve", "lf", "crlf", "cr" }),
            },
            expected_identity = IDENTITY_SCHEMA,
            expected_raw_digest = { type = "string" },
        },
    },
    patch = {
        type = "object", additionalProperties = false,
        required = schema_array({
            "path", "expected_identity", "expected_raw_digest", "hunks",
        }),
        properties = {
            path = { type = "string" },
            expected_identity = IDENTITY_SCHEMA,
            expected_raw_digest = { type = "string" },
            hunks = { type = "array", items = HUNK_SCHEMA },
        },
    },
    rename = {
        type = "object", additionalProperties = false,
        required = schema_array({
            "source", "target", "expected_identity", "expected_raw_digest",
        }),
        properties = {
            source = { type = "string" },
            target = { type = "string" },
            expected_identity = IDENTITY_SCHEMA,
            expected_raw_digest = { type = "string" },
        },
    },
    delete = {
        type = "object", additionalProperties = false,
        required = schema_array({ "path", "expected_identity", "expected_raw_digest" }),
        properties = {
            path = { type = "string" },
            expected_identity = IDENTITY_SCHEMA,
            expected_raw_digest = { type = "string" },
        },
    },
    exec = {
        type = "object", additionalProperties = false,
        required = schema_array({ "command" }),
        properties = {
            command = { type = "string" },
            cwd = { type = "string" },
            deadline_ms = { type = "integer", minimum = 1 },
        },
    },
}

local DESCRIPTIONS = {
    list = "Bounded stable no-follow directory enumeration.",
    read = "Read a line range from one verified ordinary text file.",
    search = "Bounded versioned text search without a host grep command.",
    write = "Create no-replace or replace one verified ordinary text file.",
    patch = "Apply versioned structured hunks to one verified text file.",
    rename = "Rename one verified source without replacing a target.",
    delete = "Permanently delete one verified file or empty directory.",
    exec = "Run one opaque foreground command through the fixed platform shell.",
}

local function build_registry(safety)
    local digest_rows = {}
    local tools = {}
    for index, name in ipairs(TOOL_ORDER) do
        local schema_bytes = assert(canonical_json(SCHEMAS[name]))
        digest_rows[index] = {
            name = name,
            schema_version = SCHEMA_VERSION,
            schema = schema_bytes,
            description = DESCRIPTIONS[name],
        }
        tools[index] = {
            name = name,
            description = DESCRIPTIONS[name],
            schema = SCHEMAS[name],
        }
    end
    local digest_bytes = assert(canonical_json(array(digest_rows)))
    local digest, digest_error = safety.digest(
        "yaca-tool-registry\0" .. REGISTRY_VERSION .. "\0" .. digest_bytes
    )
    if not digest then return nil, digest_error end
    local registry, freeze_error = safety.freeze({
        version = REGISTRY_VERSION,
        digest = digest,
        tools = tools,
    }, "tool registry")
    if not registry then return nil, freeze_error end
    return registry
end

local function valid_string(value, maximum, allow_empty)
    if type(value) ~= "string"
        or (not allow_empty and value == "")
        or #value > maximum
        or value:find("\0", 1, true)
    then
        return false
    end
    local valid = text.validate_utf8(value)
    return valid == true
end

local function valid_identifier(value, maximum)
    return valid_string(value, maximum, false)
        and value:match("^[A-Za-z0-9][A-Za-z0-9._:-]*$") ~= nil
end

local function identity_object(value)
    if not exact_fields(value, {
        kind = true, volume = true, object = true, size = true, modified = true,
    })
        or type(value.kind) ~= "string" or value.kind == ""
        or type(value.volume) ~= "string" or value.volume == ""
        or type(value.object) ~= "string" or value.object == ""
        or not valid_integer(value.size, 0)
        or type(value.modified) ~= "string" or value.modified == ""
    then
        return nil
    end
    return {
        kind = value.kind,
        volume = value.volume,
        object = value.object,
        size = value.size,
        modified = value.modified,
    }
end

local function same_identity(left, right)
    return type(left) == "table" and type(right) == "table"
        and left.kind == right.kind
        and left.volume == right.volume
        and left.object == right.object
        and left.size == right.size
        and left.modified == right.modified
end

local function identity_key(identity)
    return identity.volume .. "\0" .. identity.object .. "\0" .. identity.kind
end

local function identity_bytes(identity)
    return table.concat({
        identity.kind, identity.volume, identity.object,
        tostring(identity.size), identity.modified,
    }, "\0")
end

local function normalize_policy_text(value, options, label, allow_empty)
    if not valid_string(value, options.maximum_content_bytes, allow_empty) then
        return nil, failure("InvalidToolArguments", label .. " is invalid or exceeds its bound")
    end
    return value
end

local function normalize_path(value, options, label)
    if not valid_string(value, options.maximum_path_bytes, false) then
        return nil, failure("InvalidToolArguments", label .. " is not a bounded canonical path")
    end
    local normalized = value:gsub("\\", "/")
    if normalized:sub(1, 1) ~= "/"
        and normalized:match("^[A-Za-z]:/") == nil
        and normalized:match("^//[^/]+/[^/]+") == nil
    then
        return nil, failure("InvalidToolArguments", label .. " must be absolute")
    end
    return value
end

local function normalize_line_array(value, options, budget)
    local count = dense_count(value)
    if count == nil or count > options.maximum_patch_lines then
        return nil, failure("InvalidToolArguments", "patch line array is invalid or too large")
    end
    local result = array({})
    for index, line in ipairs(value) do
        if not valid_string(line, options.maximum_line_bytes, true)
            or line:find("\r", 1, true)
            or line:find("\n", 1, true)
        then
            return nil, failure("InvalidToolArguments", "patch lines must be bounded single lines")
        end
        budget.count = budget.count + 1
        if budget.count > options.maximum_patch_lines then
            return nil, failure("InvalidToolArguments", "patch total line count exceeds its bound")
        end
        result[index] = line
    end
    return result
end

local function validate_options(options)
    if type(options) ~= "table" then
        return nil, failure("InvalidToolOptions", "tool hard limits are required")
    end
    local numeric = {
        "maximum_argument_bytes", "maximum_path_bytes", "maximum_content_bytes",
        "maximum_file_bytes", "maximum_result_bytes", "maximum_list_depth",
        "maximum_page_entries", "maximum_walk_entries", "maximum_search_pattern_bytes",
        "maximum_search_matches", "maximum_patch_hunks", "maximum_patch_lines",
        "maximum_line_bytes", "maximum_continuations", "maximum_identifier_bytes",
        "filesystem_chunk_bytes", "create_permissions", "maximum_json_depth",
        "maximum_json_nodes", "maximum_number_bytes", "maximum_exec_output_bytes",
        "maximum_exec_deadline_ms",
    }
    local allowed = {
        platform_kind = true,
        workspace_path = true,
        reserved_paths = true,
    }
    for _, name in ipairs(numeric) do allowed[name] = true end
    for key in pairs(options) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure("InvalidToolOptions", "tool options contain an unknown field")
        end
    end
    local result = {}
    for _, name in ipairs(numeric) do
        local minimum = name == "maximum_list_depth" and 0 or 1
        if not valid_integer(options[name], minimum) then
            return nil, failure("InvalidToolOptions", name .. " is invalid")
        end
        result[name] = options[name]
    end
    if result.create_permissions > 511
        or result.maximum_page_entries > result.maximum_walk_entries
        or result.maximum_search_matches > result.maximum_walk_entries
        or result.filesystem_chunk_bytes > result.maximum_file_bytes
        or result.maximum_line_bytes > result.maximum_content_bytes
        or result.maximum_content_bytes > result.maximum_argument_bytes
        or result.maximum_exec_output_bytes > result.maximum_result_bytes
    then
        return nil, failure("InvalidToolOptions", "tool sub-limits are inconsistent")
    end
    if options.platform_kind ~= "posix" and options.platform_kind ~= "windows" then
        return nil, failure("InvalidToolOptions", "platform_kind must be posix or windows")
    end
    result.platform_kind = options.platform_kind
    local workspace, workspace_error = normalize_path(options.workspace_path, result, "workspace_path")
    if not workspace then return nil, workspace_error end
    result.workspace_path = workspace
    local reserved_count = dense_count(options.reserved_paths)
    if reserved_count == nil or reserved_count == 0 then
        return nil, failure("InvalidToolOptions", "at least one reserved path is required")
    end
    result.reserved_paths = {}
    local seen = {}
    for index, path in ipairs(options.reserved_paths) do
        local admitted, path_error = normalize_path(path, result, "reserved path")
        if not admitted or seen[admitted] then
            return nil, path_error or failure("InvalidToolOptions", "reserved paths are duplicated")
        end
        seen[admitted] = true
        result.reserved_paths[index] = admitted
    end
    return result
end

local function validate_dependencies(dependencies)
    if type(dependencies) ~= "table" or not exact_fields(dependencies, {
        filesystem = true,
        path = true,
        safety = true,
        secret_registry = true,
        authorization = true,
        processes = true,
        operations = true,
    }) then
        return nil, failure("InvalidToolDependencies", "tool dependencies are ambiguous")
    end
    local filesystem = dependencies.filesystem
    for _, name in ipairs({
        "direct_inspect", "direct_reverify", "direct_walk", "direct_open_read",
        "direct_create_new", "direct_replace", "direct_rename", "direct_delete",
        "stream_read", "stream_write", "flush_file", "flush_directory",
        "stat_identity", "close",
    }) do
        if type(filesystem) ~= "table" or type(filesystem[name]) ~= "function" then
            return nil, failure("InvalidToolDependencies", "filesystem omits " .. name)
        end
    end
    if type(filesystem.capabilities) ~= "table"
        or filesystem.capabilities.verified_direct_candidate ~= true
    then
        return nil, failure(
            "DirectFilesystemUnavailable",
            "verified direct filesystem capability is unavailable"
        )
    end
    local paths = dependencies.path
    for _, name in ipairs({ "to_logical", "is_within_root" }) do
        if type(paths) ~= "table" or type(paths[name]) ~= "function" then
            return nil, failure("InvalidToolDependencies", "path service omits " .. name)
        end
    end
    local safety = dependencies.safety
    for _, name in ipairs({ "freeze", "digest", "binding_digest" }) do
        if type(safety) ~= "table" or type(safety[name]) ~= "function" then
            return nil, failure("InvalidToolDependencies", "safety service omits " .. name)
        end
    end
    local secrets = dependencies.secret_registry
    if secrets ~= false and (type(secrets) ~= "table" or type(secrets.scan) ~= "function") then
        return nil, failure("InvalidToolDependencies", "secret registry is invalid")
    end
    local authorization = dependencies.authorization
    if type(authorization) ~= "table"
        or type(authorization.admit) ~= "function"
        or type(authorization.reverify) ~= "function"
    then
        return nil, failure("InvalidToolDependencies", "authorization port is incomplete")
    end
    local processes = dependencies.processes
    if processes ~= false
        and (type(processes) ~= "table" or type(processes.new_port) ~= "function")
    then
        return nil, failure("InvalidToolDependencies", "process service is invalid")
    end
    if processes ~= false and secrets ~= false
        and type(secrets.new_stream_scanner) ~= "function"
    then
        return nil, failure(
            "InvalidToolDependencies",
            "raw exec requires a cross-chunk registered-secret scanner"
        )
    end
    local operations = dependencies.operations
    if type(operations) ~= "table"
        or type(operations.begin) ~= "function"
        or type(operations.finish) ~= "function"
        or type(operations.status) ~= "function"
    then
        return nil, failure("InvalidToolDependencies", "durable operation service is incomplete")
    end
    return {
        filesystem = filesystem,
        path = paths,
        safety = safety,
        secret_registry = secrets,
        authorization = authorization,
        processes = processes,
        operations = operations,
    }
end

local function json_to_plain(value, depth, maximum_depth)
    depth = depth or 1
    if depth > maximum_depth then
        return nil, failure("InvalidToolArguments", "tool arguments exceed their depth bound")
    end
    local kind = json.kind(value)
    if kind == "string" or kind == "boolean" then return value end
    if kind == "number" then
        local lexeme = assert(json.number_lexeme(value))
        if not lexeme:match("^-?%d+$") then
            return nil, failure("InvalidToolArguments", "tool integers must not use fractions")
        end
        local number = tonumber(lexeme)
        if math.type(number) ~= "integer" or tostring(number) ~= lexeme then
            return nil, failure("InvalidToolArguments", "tool integer is outside the exact range")
        end
        return number
    end
    if kind == "null" then
        return nil, failure("InvalidToolArguments", "tool arguments do not accept null")
    end
    if kind ~= "array" and kind ~= "object" then
        return nil, failure("InvalidToolArguments", "tool argument value is untyped")
    end
    local result = {}
    if kind == "array" then arrays[result] = true end
    for key, item in pairs(value) do
        local converted, convert_error = json_to_plain(item, depth + 1, maximum_depth)
        if converted == nil then return nil, convert_error end
        result[key] = converted
    end
    return result
end

---Creates the closed registry and direct-tool execution service.
-- Direct mutation is reachable only through a current-process authorization
-- token whose external port must bind Permission, approval, and durable intent.
-- @param dependencies table Filesystem/path/safety/secret/authorization ports.
-- @param options table Release hard limits, workspace, platform, reserved roots.
-- @return table|nil service Immutable tool service.
-- @return table|nil err Structured construction failure.
function M.new(dependencies, options)
    local ports, dependency_error = validate_dependencies(dependencies)
    if not ports then return nil, dependency_error end
    local limits, options_error = validate_options(options)
    if not limits then return nil, options_error end
    local registry, registry_error = build_registry(ports.safety)
    if not registry then return nil, registry_error end
    local codec, codec_error = json.new({
        maximum_bytes = limits.maximum_argument_bytes,
        maximum_depth = limits.maximum_json_depth,
        maximum_nodes = limits.maximum_json_nodes,
        maximum_string_bytes = limits.maximum_content_bytes,
        maximum_number_bytes = limits.maximum_number_bytes,
    })
    if not codec then return nil, codec_error end

    local workspace_ok, workspace = ports.filesystem.direct_inspect(limits.workspace_path)
    if not workspace_ok then return nil, workspace end
    if not workspace.exists or workspace.identity.kind ~= "directory"
        or not workspace.ancestry_complete
    then
        return nil, failure("InvalidWorkspace", "workspace must be a proven ordinary directory")
    end
    local workspace_logical, workspace_path_error = ports.path.to_logical(workspace.canonical_path)
    if not workspace_logical then return nil, workspace_path_error end

    local reserved_keys, reserved_logical, reserved_snapshots = {}, {}, {}
    for index, reserved_path in ipairs(limits.reserved_paths) do
        local reserved_ok, reserved = ports.filesystem.direct_inspect(reserved_path)
        if not reserved_ok then return nil, reserved end
        if not reserved.exists or reserved.identity.kind ~= "directory"
            or not reserved.ancestry_complete
        then
            return nil, failure("InvalidReservedTree", "reserved root is not a proven directory")
        end
        reserved_keys[identity_key(reserved.identity)] = true
        reserved_snapshots[index] = reserved
        local logical, logical_error = ports.path.to_logical(reserved.canonical_path)
        if not logical then return nil, logical_error end
        reserved_logical[index] = logical
    end

    local service = {}
    local calls = setmetatable({}, { __mode = "k" })
    local authorizations = setmetatable({}, { __mode = "k" })
    local continuations = {}
    local continuation_count = 0
    local continuation_serial = 0
    local executing = false
    local halted = false

    local function inspect_path(path)
        local ok, snapshot = ports.filesystem.direct_inspect(path)
        if not ok then return nil, snapshot end
        if not snapshot.ancestry_complete then
            return nil, failure(
                "ReservedAliasUnknown",
                "physical ancestry is incomplete at the reserved-tree boundary"
            )
        end
        local logical, logical_error = ports.path.to_logical(snapshot.canonical_path)
        if not logical then return nil, logical_error end
        local reserved = false
        for _, ancestor in ipairs(snapshot.ancestors) do
            if reserved_keys[identity_key(ancestor.identity)] then reserved = true; break end
        end
        if reserved_keys[identity_key(snapshot.parent_identity)]
            or (snapshot.exists and reserved_keys[identity_key(snapshot.identity)])
        then
            reserved = true
        end
        for _, root in ipairs(reserved_logical) do
            local within, within_error = ports.path.is_within_root(
                logical,
                root,
                limits.platform_kind
            )
            if within == nil then return nil, within_error end
            if within then reserved = true; break end
        end
        local within_workspace, within_error = ports.path.is_within_root(
            logical,
            workspace_logical,
            limits.platform_kind
        )
        if within_workspace == nil then return nil, within_error end
        return {
            snapshot = snapshot,
            logical = logical,
            reserved = reserved,
            outside_workspace = not within_workspace,
        }
    end

    local function require_direct_target(target, tool, expected_kind)
        if target.reserved then
            return nil, failure("ReservedTreeDenied", "direct tools cannot access the reserved tree")
        end
        local snapshot = target.snapshot
        if not snapshot.exists then
            return nil, failure("NotFound", "direct target does not exist")
        end
        local kind = snapshot.identity.kind
        if kind == "link" then
            return nil, failure("LinkNotFollowed", "direct tools do not follow links")
        end
        if kind ~= "file" and kind ~= "directory" then
            return nil, failure("SpecialFileDenied", "direct tools reject special objects")
        end
        if expected_kind and kind ~= expected_kind then
            return nil, failure("InvalidTargetType", tool .. " target type is invalid")
        end
        if kind == "file" and snapshot.metadata.link_count ~= 1 then
            return nil, failure("HardlinkDenied", "direct tools reject hardlinked ordinary files")
        end
        return target
    end

    local function validate_expected(expected, observed)
        local normalized = identity_object(expected)
        if not normalized or not same_identity(normalized, observed) then
            return nil, failure("TargetChanged", "expected filesystem identity does not match")
        end
        return normalized
    end

    local function scan_ingress(bytes)
        if ports.secret_registry == false then return true end
        local hits, scan_error = ports.secret_registry.scan(bytes)
        if not hits then return nil, scan_error end
        if #hits > 0 then
            return nil, failure(
                "RegisteredSecretInToolArgument",
                "ordinary tool arguments contain a registered configuration secret"
            )
        end
        return true
    end

    local function continuation_for(tool, token, normalized)
        if token == nil then return nil end
        if not valid_identifier(token, limits.maximum_identifier_bytes) then
            return nil, failure("InvalidContinuation", "continuation token is malformed")
        end
        local state = continuations[token]
        if not state or state.tool ~= tool then
            return nil, failure("InvalidContinuation", "continuation token is stale or foreign")
        end
        if state.path ~= normalized.path
            or (tool == "list" and state.depth ~= normalized.depth)
            or (tool == "search" and (
                state.pattern ~= normalized.pattern
                or state.dialect ~= normalized.dialect
                or state.case_sensitive ~= normalized.case_sensitive
            ))
        then
            return nil, failure("InvalidContinuation", "continuation arguments changed")
        end
        return state
    end

    local function ordinary_text(value, label)
        local codepoints, decode_error = text.decode_utf8(value)
        if not codepoints then
            return nil, failure("InvalidToolArguments", label .. " is not strict UTF-8", decode_error.code)
        end
        for _, codepoint in ipairs(codepoints) do
            local safe = codepoint == 0x09 or codepoint == 0x0A or codepoint == 0x0D
                or (codepoint >= 0x20 and codepoint <= 0xD7FF)
                or (codepoint >= 0xE000 and codepoint <= 0xFFFD)
                or (codepoint >= 0x10000 and codepoint <= 0x10FFFF)
            if not safe then
                return nil, failure(
                    "BinaryContentDenied",
                    label .. " contains NUL or an XML-unsafe control"
                )
            end
        end
        return value
    end

    local function raw_digest(value, allow_empty)
        if type(value) ~= "string"
            or ((not allow_empty) and value == "")
            or (value ~= "" and value:match("^[0-9a-f][0-9a-f]+$") == nil)
            or (value ~= "" and #value ~= 64)
        then
            return nil, failure("InvalidToolArguments", "expected_raw_digest is invalid")
        end
        return value
    end

    local function normalize_hunks(value)
        local count = dense_count(value)
        if count == nil or count == 0 or count > limits.maximum_patch_hunks then
            return nil, failure("InvalidToolArguments", "hunks must be a bounded non-empty array")
        end
        local result, budget, prior_start = array({}), { count = 0 }, 0
        for index, hunk in ipairs(value) do
            if not exact_fields(hunk, {
                start_line = true,
                context_before = true,
                delete_lines = true,
                insert_lines = true,
                context_after = true,
                newline = true,
                final_newline = true,
            })
                or not valid_integer(hunk.start_line, 1)
                or hunk.start_line <= prior_start
                or (hunk.newline ~= "lf" and hunk.newline ~= "crlf" and hunk.newline ~= "cr")
                or type(hunk.final_newline) ~= "boolean"
            then
                return nil, failure("InvalidToolArguments", "structured hunk fields are invalid")
            end
            local before, before_error = normalize_line_array(hunk.context_before, limits, budget)
            if not before then return nil, before_error end
            local deleted, deleted_error = normalize_line_array(hunk.delete_lines, limits, budget)
            if not deleted then return nil, deleted_error end
            local inserted, inserted_error = normalize_line_array(hunk.insert_lines, limits, budget)
            if not inserted then return nil, inserted_error end
            local after, after_error = normalize_line_array(hunk.context_after, limits, budget)
            if not after then return nil, after_error end
            if #deleted == 0 and #inserted == 0 then
                return nil, failure("InvalidToolArguments", "a hunk must change at least one line")
            end
            result[index] = {
                start_line = hunk.start_line,
                context_before = before,
                delete_lines = deleted,
                insert_lines = inserted,
                context_after = after,
                newline = hunk.newline,
                final_newline = hunk.final_newline,
            }
            prior_start = hunk.start_line
        end
        return result
    end

    local function normalize_arguments(tool, arguments)
        if tool == "list" then
            if not exact_fields(arguments, {
                path = true, depth = true, page_size = true, continuation = true,
            }) then
                return nil, failure("InvalidToolArguments", "list arguments contain unknown fields")
            end
            local path, path_error = normalize_path(arguments.path, limits, "list path")
            if not path then return nil, path_error end
            if not valid_integer(arguments.depth, 0) or arguments.depth > limits.maximum_list_depth
                or not valid_integer(arguments.page_size, 1)
                or arguments.page_size > limits.maximum_page_entries
            then
                return nil, failure("InvalidToolArguments", "list bounds are invalid")
            end
            local target, target_error = inspect_path(path)
            if not target then return nil, target_error end
            target, target_error = require_direct_target(target, "list", "directory")
            if not target then return nil, target_error end
            local normalized = {
                path = target.snapshot.canonical_path,
                depth = arguments.depth,
                page_size = arguments.page_size,
            }
            if arguments.continuation ~= nil then normalized.continuation = arguments.continuation end
            local continuation, continuation_error = continuation_for("list", arguments.continuation, normalized)
            if arguments.continuation ~= nil and not continuation then return nil, continuation_error end
            return normalized, { target }, continuation
        elseif tool == "read" then
            if not exact_fields(arguments, { path = true, start_line = true, max_lines = true }) then
                return nil, failure("InvalidToolArguments", "read arguments contain unknown fields")
            end
            local path, path_error = normalize_path(arguments.path, limits, "read path")
            if not path then return nil, path_error end
            if not valid_integer(arguments.start_line, 1)
                or not valid_integer(arguments.max_lines, 1)
                or arguments.max_lines > limits.maximum_page_entries
            then
                return nil, failure("InvalidToolArguments", "read line range is invalid")
            end
            local target, target_error = inspect_path(path)
            if not target then return nil, target_error end
            target, target_error = require_direct_target(target, "read", "file")
            if not target then return nil, target_error end
            return {
                path = target.snapshot.canonical_path,
                start_line = arguments.start_line,
                max_lines = arguments.max_lines,
            }, { target }
        elseif tool == "search" then
            if not exact_fields(arguments, {
                path = true, pattern = true, dialect = true, case_sensitive = true,
                page_size = true, continuation = true,
            }) then
                return nil, failure("InvalidToolArguments", "search arguments contain unknown fields")
            end
            local path, path_error = normalize_path(arguments.path, limits, "search path")
            if not path then return nil, path_error end
            if not valid_string(arguments.pattern, limits.maximum_search_pattern_bytes, false)
                or (arguments.dialect ~= "literal" and arguments.dialect ~= "lua-pattern-v1")
                or type(arguments.case_sensitive) ~= "boolean"
                or not valid_integer(arguments.page_size, 1)
                or arguments.page_size > limits.maximum_page_entries
            then
                return nil, failure("InvalidToolArguments", "search fields are invalid")
            end
            if arguments.dialect == "lua-pattern-v1" then
                local pattern_ok = pcall(string.find, "", arguments.pattern)
                if not pattern_ok then
                    return nil, failure("InvalidToolArguments", "lua-pattern-v1 pattern is malformed")
                end
                if not arguments.case_sensitive then
                    return nil, failure(
                        "InvalidToolArguments",
                        "lua-pattern-v1 requires case_sensitive=true"
                    )
                end
            end
            local target, target_error = inspect_path(path)
            if not target then return nil, target_error end
            target, target_error = require_direct_target(target, "search", "directory")
            if not target then return nil, target_error end
            local normalized = {
                path = target.snapshot.canonical_path,
                pattern = arguments.pattern,
                dialect = arguments.dialect,
                case_sensitive = arguments.case_sensitive,
                page_size = arguments.page_size,
            }
            if arguments.continuation ~= nil then normalized.continuation = arguments.continuation end
            local continuation, continuation_error = continuation_for(
                "search",
                arguments.continuation,
                normalized
            )
            if arguments.continuation ~= nil and not continuation then return nil, continuation_error end
            return normalized, { target }, continuation
        elseif tool == "write" then
            if not exact_fields(arguments, {
                path = true, mode = true, content = true, encoding = true,
                newline_policy = true, expected_identity = true, expected_raw_digest = true,
            }) then
                return nil, failure("InvalidToolArguments", "write arguments contain unknown fields")
            end
            local path, path_error = normalize_path(arguments.path, limits, "write path")
            if not path then return nil, path_error end
            local content, content_error = normalize_policy_text(
                arguments.content,
                limits,
                "write content",
                true
            )
            if not content then return nil, content_error end
            content, content_error = ordinary_text(content, "write content")
            if not content then return nil, content_error end
            local encodings = {
                ["utf-8"] = true, ["utf-8-bom"] = true,
                ["utf-16le-bom"] = true, ["utf-16be-bom"] = true,
            }
            local newline_policies = { preserve = true, lf = true, crlf = true, cr = true }
            if (arguments.mode ~= "create" and arguments.mode ~= "replace")
                or not encodings[arguments.encoding]
                or not newline_policies[arguments.newline_policy]
            then
                return nil, failure("InvalidToolArguments", "write mode/encoding/newline is invalid")
            end
            local target, target_error = inspect_path(path)
            if not target then return nil, target_error end
            if target.reserved then
                return nil, failure("ReservedTreeDenied", "direct mutation cannot enter reserved tree")
            end
            local normalized = {
                path = target.snapshot.canonical_path,
                mode = arguments.mode,
                content = content,
                encoding = arguments.encoding,
                newline_policy = arguments.newline_policy,
            }
            if arguments.mode == "create" then
                if target.snapshot.exists
                    or arguments.expected_identity ~= nil
                    or arguments.expected_raw_digest ~= nil
                then
                    return nil, failure(
                        "DestinationExists",
                        "write(create) requires an absent target and no expected version"
                    )
                end
            else
                target, target_error = require_direct_target(target, "write", "file")
                if not target then return nil, target_error end
                if target.snapshot.metadata.preservation ~= "proven" then
                    return nil, failure(
                        "MetadataPreservationUnsupported",
                        "direct replace cannot preserve target metadata"
                    )
                end
                local expected, expected_error = validate_expected(
                    arguments.expected_identity,
                    target.snapshot.identity
                )
                if not expected then return nil, expected_error end
                local digest, digest_error = raw_digest(arguments.expected_raw_digest, false)
                if not digest then return nil, digest_error end
                normalized.expected_identity = expected
                normalized.expected_raw_digest = digest
            end
            return normalized, { target }
        elseif tool == "patch" then
            if not exact_fields(arguments, {
                path = true, expected_identity = true, expected_raw_digest = true, hunks = true,
            }) then
                return nil, failure("InvalidToolArguments", "patch arguments contain unknown fields")
            end
            local path, path_error = normalize_path(arguments.path, limits, "patch path")
            if not path then return nil, path_error end
            local target, target_error = inspect_path(path)
            if not target then return nil, target_error end
            target, target_error = require_direct_target(target, "patch", "file")
            if not target then return nil, target_error end
            if target.snapshot.metadata.preservation ~= "proven" then
                return nil, failure(
                    "MetadataPreservationUnsupported",
                    "direct patch cannot preserve target metadata"
                )
            end
            local expected, expected_error = validate_expected(
                arguments.expected_identity,
                target.snapshot.identity
            )
            if not expected then return nil, expected_error end
            local digest, digest_error = raw_digest(arguments.expected_raw_digest, false)
            if not digest then return nil, digest_error end
            local hunks, hunks_error = normalize_hunks(arguments.hunks)
            if not hunks then return nil, hunks_error end
            return {
                path = target.snapshot.canonical_path,
                expected_identity = expected,
                expected_raw_digest = digest,
                hunks = hunks,
            }, { target }
        elseif tool == "rename" then
            if not exact_fields(arguments, {
                source = true, target = true, expected_identity = true,
                expected_raw_digest = true,
            }) then
                return nil, failure("InvalidToolArguments", "rename arguments contain unknown fields")
            end
            local source_path, source_error = normalize_path(arguments.source, limits, "rename source")
            if not source_path then return nil, source_error end
            local target_path, target_path_error = normalize_path(arguments.target, limits, "rename target")
            if not target_path then return nil, target_path_error end
            local source, inspect_error = inspect_path(source_path)
            if not source then return nil, inspect_error end
            source, inspect_error = require_direct_target(source, "rename")
            if not source then return nil, inspect_error end
            local target, target_error = inspect_path(target_path)
            if not target then return nil, target_error end
            if target.reserved or target.snapshot.exists then
                return nil, failure(
                    target.reserved and "ReservedTreeDenied" or "DestinationExists",
                    "rename target is reserved or already exists"
                )
            end
            local expected, expected_error = validate_expected(
                arguments.expected_identity,
                source.snapshot.identity
            )
            if not expected then return nil, expected_error end
            local digest, digest_error = raw_digest(
                arguments.expected_raw_digest,
                source.snapshot.identity.kind == "directory"
            )
            if not digest then return nil, digest_error end
            if source.snapshot.identity.kind == "directory" and digest ~= "" then
                return nil, failure("InvalidToolArguments", "directory rename digest must be empty")
            end
            return {
                source = source.snapshot.canonical_path,
                target = target.snapshot.canonical_path,
                expected_identity = expected,
                expected_raw_digest = digest,
            }, { source, target }
        elseif tool == "delete" then
            if not exact_fields(arguments, {
                path = true, expected_identity = true, expected_raw_digest = true,
            }) then
                return nil, failure("InvalidToolArguments", "delete arguments contain unknown fields")
            end
            local path, path_error = normalize_path(arguments.path, limits, "delete path")
            if not path then return nil, path_error end
            local target, target_error = inspect_path(path)
            if not target then return nil, target_error end
            target, target_error = require_direct_target(target, "delete")
            if not target then return nil, target_error end
            local expected, expected_error = validate_expected(
                arguments.expected_identity,
                target.snapshot.identity
            )
            if not expected then return nil, expected_error end
            local digest, digest_error = raw_digest(
                arguments.expected_raw_digest,
                target.snapshot.identity.kind == "directory"
            )
            if not digest then return nil, digest_error end
            if target.snapshot.identity.kind == "directory" and digest ~= "" then
                return nil, failure("InvalidToolArguments", "directory delete digest must be empty")
            end
            return {
                path = target.snapshot.canonical_path,
                expected_identity = expected,
                expected_raw_digest = digest,
            }, { target }
        elseif tool == "exec" then
            if not exact_fields(arguments, { command = true, cwd = true, deadline_ms = true }) then
                return nil, failure("InvalidToolArguments", "exec arguments contain unknown fields")
            end
            if not valid_string(arguments.command, limits.maximum_content_bytes, false) then
                return nil, failure("InvalidToolArguments", "opaque command is invalid or too large")
            end
            local cwd = arguments.cwd or workspace.canonical_path
            local cwd_path, cwd_error = normalize_path(cwd, limits, "exec cwd")
            if not cwd_path then return nil, cwd_error end
            local cwd_target, inspect_error = inspect_path(cwd_path)
            if not cwd_target then return nil, inspect_error end
            if not cwd_target.snapshot.exists or cwd_target.snapshot.identity.kind ~= "directory" then
                return nil, failure("InvalidTargetType", "exec cwd must be a real directory")
            end
            if arguments.deadline_ms ~= nil and not valid_integer(arguments.deadline_ms, 1) then
                return nil, failure("InvalidToolArguments", "exec deadline_ms is invalid")
            end
            local normalized = { command = arguments.command, cwd = cwd_target.snapshot.canonical_path }
            if arguments.deadline_ms ~= nil then normalized.deadline_ms = arguments.deadline_ms end
            return normalized, { cwd_target }
        end
        return nil, failure("UnknownTool", "tool is not registered")
    end

    local empty_digest, empty_digest_error = ports.safety.digest(
        "yaca-tool-registry\0" .. REGISTRY_VERSION .. "\0[]"
    )
    if not empty_digest then return nil, empty_digest_error end
    local empty_registry, empty_freeze_error = ports.safety.freeze({
        version = REGISTRY_VERSION,
        digest = empty_digest,
        tools = {},
    }, "empty tool registry")
    if not empty_registry then return nil, empty_freeze_error end

    local function public_target(target)
        return {
            canonical_path = target.snapshot.canonical_path,
            logical_path = target.logical,
            outside_workspace = target.outside_workspace,
            exists = target.snapshot.exists,
            identity = target.snapshot.exists and {
                kind = target.snapshot.identity.kind,
                volume = target.snapshot.identity.volume,
                object = target.snapshot.identity.object,
                size = target.snapshot.identity.size,
                modified = target.snapshot.identity.modified,
            } or false,
            parent_identity = {
                kind = target.snapshot.parent_identity.kind,
                volume = target.snapshot.parent_identity.volume,
                object = target.snapshot.parent_identity.object,
                size = target.snapshot.parent_identity.size,
                modified = target.snapshot.parent_identity.modified,
            },
        }
    end

    ---Returns the exact model-visible registry for one request purpose.
    -- Only main requests receive executable tools; all side/reviewer/compact
    -- purposes receive a distinct, versioned empty registry.
    function service:registry_for(purpose)
        if purpose == "main" then return registry end
        if purpose == "side" or purpose == "action-review"
            or purpose == "termination-review" or purpose == "compaction"
            or purpose == "self-test" or purpose == "context-name"
        then
            return empty_registry
        end
        return nil, failure("InvalidRequestPurpose", "tool registry purpose is unknown")
    end

    ---Admits one complete provider call after exact schema/canonical validation.
    -- Streaming fragments are intentionally not accepted: callers must supply
    -- the complete canonical argument object emitted by model.lua.
    function service:admit_call(envelope)
        if not exact_fields(envelope, {
            tool = true,
            schema_version = true,
            registry_digest = true,
            provider_call_id = true,
            tool_call_id = true,
            operation_id = true,
            canonical_arguments = true,
        })
            or type(envelope.tool) ~= "string"
            or not SCHEMAS[envelope.tool]
            or envelope.schema_version ~= SCHEMA_VERSION
            or envelope.registry_digest ~= registry.digest
            or not valid_identifier(envelope.provider_call_id, limits.maximum_identifier_bytes)
            or not valid_identifier(envelope.tool_call_id, limits.maximum_identifier_bytes)
            or not valid_identifier(envelope.operation_id, limits.maximum_identifier_bytes)
            or type(envelope.canonical_arguments) ~= "string"
            or #envelope.canonical_arguments > limits.maximum_argument_bytes
        then
            return nil, failure("InvalidToolCall", "tool call envelope is invalid or stale")
        end
        local parsed, parse_error = codec.parse(envelope.canonical_arguments)
        if not parsed or json.kind(parsed) ~= "object" then
            return nil, failure(
                "InvalidToolArguments",
                "canonical_arguments must be one bounded JSON object",
                parse_error and parse_error.code
            )
        end
        local canonical_wire, canonical_error = codec.write(parsed)
        if not canonical_wire then return nil, canonical_error end
        if canonical_wire ~= envelope.canonical_arguments then
            return nil, failure("InvalidToolArguments", "tool arguments are not canonical JSON")
        end
        local plain, plain_error = json_to_plain(parsed, 1, limits.maximum_json_depth)
        if not plain then return nil, plain_error end
        local normalized, targets, continuation = normalize_arguments(envelope.tool, plain)
        if not normalized then return nil, targets end
        local normalized_bytes, normalized_error = canonical_json(normalized)
        if not normalized_bytes then return nil, normalized_error end
        if #normalized_bytes > limits.maximum_argument_bytes then
            return nil, failure("InvalidToolArguments", "normalized arguments exceed their bound")
        end
        local ingress_ok, ingress_error = scan_ingress(normalized_bytes)
        if not ingress_ok then return nil, ingress_error end

        local outside = false
        local public_targets = array({})
        local target_binding = {}
        for index, target in ipairs(targets) do
            outside = outside or target.outside_workspace
            public_targets[index] = public_target(target)
            target_binding[index] = table.concat({
                target.snapshot.canonical_path,
                target.snapshot.exists and identity_bytes(target.snapshot.identity) or "missing",
                identity_bytes(target.snapshot.parent_identity),
            }, "\0")
        end
        local call_digest, digest_error = ports.safety.binding_digest("yaca-tool-call-v1", {
            { name = "registry_version", value = REGISTRY_VERSION },
            { name = "registry_digest", value = registry.digest },
            { name = "tool", value = envelope.tool },
            { name = "schema_version", value = SCHEMA_VERSION },
            { name = "canonical_arguments", value = normalized_bytes },
            { name = "targets", value = table.concat(target_binding, "\1") },
            { name = "workspace", value = identity_key(workspace.identity) },
            { name = "provider_call_id", value = envelope.provider_call_id },
            { name = "tool_call_id", value = envelope.tool_call_id },
            { name = "operation_id", value = envelope.operation_id },
        })
        if not call_digest then return nil, digest_error end
        local public, freeze_error = ports.safety.freeze({
            tool = envelope.tool,
            schema_version = SCHEMA_VERSION,
            registry_version = REGISTRY_VERSION,
            registry_digest = registry.digest,
            provider_call_id = envelope.provider_call_id,
            tool_call_id = envelope.tool_call_id,
            operation_id = envelope.operation_id,
            canonical_arguments = normalized_bytes,
            arguments = normalized,
            targets = public_targets,
            outside_workspace = outside,
            mutates = MUTATING_TOOLS[envelope.tool] == true,
            shell_scope = envelope.tool == "exec" and "opaque-uncontained" or false,
            call_digest = call_digest,
        }, "accepted tool call")
        if not public then return nil, freeze_error end
        calls[public] = {
            public = public,
            tool = envelope.tool,
            arguments = normalized,
            targets = targets,
            continuation = continuation,
            call_digest = call_digest,
            operation_handle = nil,
            operation_digest = nil,
            result = nil,
        }
        return public
    end

    ---Projects a marked call into Permission/approval binding fields.
    function service:permission_action(call)
        local state = calls[call]
        if not state then
            return nil, failure("InvalidToolCall", "permission action requires an admitted call")
        end
        local first = state.targets[1]
        local expected_digest = state.arguments.expected_raw_digest or ""
        local target = first and first.snapshot.canonical_path or ""
        local cwd = state.tool == "exec" and state.arguments.cwd or workspace.canonical_path
        local projection, freeze_error = ports.safety.freeze({
            tool = state.tool,
            outside_workspace = call.outside_workspace,
            reserved_tree = false,
            schema_version = SCHEMA_VERSION,
            registry_digest = registry.digest,
            canonical_arguments = call.canonical_arguments,
            canonical_target = target,
            expected_raw_digest = expected_digest,
            cwd = cwd,
            workspace_root_identity = identity_key(workspace.identity),
            operation_id = call.operation_id,
            tool_call_id = call.tool_call_id,
            call_digest = call.call_digest,
        }, "tool permission action")
        if not projection then return nil, freeze_error end
        return projection
    end

    ---Publishes the unique operation intent for a mutating or raw-shell call.
    -- Permission and any approval are expected to have completed before this
    -- method is invoked.  The returned digest is evidence only; callers cannot
    -- inject it back into authorization because the marked operation handle is
    -- retained inside this service.
    function service:begin_operation(call)
        local state = calls[call]
        if not state or state.result ~= nil or not OPERATION_TOOLS[state.tool] then
            return nil, failure(
                "InvalidToolCall",
                "durable intent requires a pending side-effecting call"
            )
        end
        if state.operation_handle ~= nil then
            return nil, failure("OperationExists", "tool call already has a durable intent")
        end
        if halted then
            return nil, failure(
                "OperationBarrierBlocked",
                "a prior result durability failure blocks new operations"
            )
        end
        local target_rows = {}
        for index, target in ipairs(state.targets) do
            target_rows[index] = table.concat({
                target.snapshot.canonical_path,
                target.snapshot.exists and identity_bytes(target.snapshot.identity) or "missing",
                identity_bytes(target.snapshot.parent_identity),
            }, "\1")
        end
        local target_identity, target_error = ports.safety.binding_digest(
            "yaca-operation-target-v1",
            {
                { name = "call_digest", value = state.call_digest },
                { name = "targets", value = table.concat(target_rows, "\2") },
            }
        )
        if not target_identity then return nil, target_error end
        local expected_digest = state.arguments.expected_raw_digest
        if type(expected_digest) ~= "string" or expected_digest == "" then
            expected_digest = state.tool == "write" and state.arguments.mode == "create"
                and "target-absent:" .. state.call_digest
                or "opaque-call:" .. state.call_digest
        end
        local called, handle, intent_digest = pcall(ports.operations.begin, {
            operation_id = state.public.operation_id,
            tool_call_id = state.public.tool_call_id,
            kind = state.tool,
            target_identity = target_identity,
            expected_digest = expected_digest,
            call_digest = state.call_digest,
        })
        if not called then
            halted = true
            return nil, failure(
                "OperationJournalFailure",
                "durable operation service raised an exception"
            )
        end
        if not handle then return nil, intent_digest end
        if not valid_string(intent_digest, 256, false) then
            halted = true
            return nil, failure(
                "OperationJournalContract",
                "durable operation service returned an invalid intent digest"
            )
        end
        state.operation_handle = handle
        state.operation_digest = intent_digest
        return intent_digest
    end

    ---Mints a one-shot execution token after the external safety pipeline.
    -- The injected port is responsible for verifying deterministic Permission,
    -- exact approval when required, current config/workspace generations, and
    -- a durable operation-intent barrier.  Prompt text is never accepted here.
    function service:authorize(call, facts)
        local state = calls[call]
        if not state or state.result ~= nil then
            return nil, failure("InvalidToolCall", "authorization requires a pending admitted call")
        end
        if not exact_fields(facts, {
            permission_snapshot_digest = true,
            approval_digest = true,
            config_generation = true,
            workspace_identity = true,
            double_check = true,
            action_review = true,
        })
            or not valid_string(facts.permission_snapshot_digest, 256, false)
            or not valid_string(facts.approval_digest, 256, true)
            or not valid_string(facts.config_generation, limits.maximum_identifier_bytes, false)
            or facts.workspace_identity ~= identity_key(workspace.identity)
            or type(facts.double_check) ~= "boolean"
            or (facts.action_review ~= "not-required"
                and facts.action_review ~= "approved"
                and facts.action_review ~= "tightened")
        then
            return nil, failure("InvalidAuthorization", "authorization facts are invalid or stale")
        end
        if OPERATION_TOOLS[state.tool] and state.operation_handle == nil then
            return nil, failure(
                "OperationIntentRequired",
                "side effects require a durable operation intent before authorization"
            )
        end
        local authority_input = {
            permission_snapshot_digest = facts.permission_snapshot_digest,
            approval_digest = facts.approval_digest,
            durable_intent_digest = state.operation_digest or "not-required:" .. state.call_digest,
            config_generation = facts.config_generation,
            workspace_identity = facts.workspace_identity,
            double_check = facts.double_check,
            action_review = facts.action_review,
        }
        local called, admitted, authority_digest = pcall(
            ports.authorization.admit,
            call,
            authority_input
        )
        if not called or admitted ~= true
            or not valid_string(authority_digest, 256, false)
        then
            return nil, failure("AuthorizationDenied", "external authorization did not admit the call")
        end
        local frozen_facts, freeze_error = ports.safety.freeze(
            authority_input,
            "tool authorization facts"
        )
        if not frozen_facts then return nil, freeze_error end
        local token = readonly({}, "tool authorization token")
        authorizations[token] = {
            call = call,
            state = state,
            facts = frozen_facts,
            authority_digest = authority_digest,
            consumed = false,
        }
        return token
    end

    local function read_bytes(snapshot)
        if snapshot.identity.size > limits.maximum_file_bytes then
            return nil, failure("FileTooLarge", "ordinary file exceeds maximum_file_bytes")
        end
        local opened, handle = ports.filesystem.direct_open_read(snapshot)
        if not opened then return nil, handle end
        local chunks, total, eof = {}, 0, false
        while not eof do
            local remaining = limits.maximum_file_bytes - total
            if remaining <= 0 and total < snapshot.identity.size then
                ports.filesystem.close(handle)
                return nil, failure("FileTooLarge", "ordinary file grew beyond its bound")
            end
            local amount = math.min(limits.filesystem_chunk_bytes, math.max(remaining, 1))
            local read_ok, chunk = ports.filesystem.stream_read(handle, amount)
            if not read_ok then ports.filesystem.close(handle); return nil, chunk end
            if #chunk.bytes == 0 and not chunk.eof then
                ports.filesystem.close(handle)
                return nil, failure("FilesystemContract", "direct read made no progress")
            end
            total = total + #chunk.bytes
            if total > limits.maximum_file_bytes or total > snapshot.identity.size then
                ports.filesystem.close(handle)
                return nil, failure("TargetChanged", "ordinary file changed size during read")
            end
            chunks[#chunks + 1] = chunk.bytes
            eof = chunk.eof
        end
        local stated, final_identity = ports.filesystem.stat_identity(handle)
        local closed, close_error = ports.filesystem.close(handle)
        if not stated then return nil, final_identity end
        if not closed then return nil, close_error end
        if not same_identity(final_identity, snapshot.identity) or total ~= snapshot.identity.size then
            return nil, failure("TargetChanged", "ordinary file changed while being read")
        end
        local bytes = table.concat(chunks)
        local digest, digest_error = ports.safety.digest(bytes)
        if not digest then return nil, digest_error end
        return { bytes = bytes, digest = digest }
    end

    local function decode_utf16(bytes, little_endian)
        if #bytes % 2 ~= 0 then return nil end
        local codepoints, index = {}, 1
        local function unit(at)
            local first, second = bytes:byte(at, at + 1)
            if little_endian then return first + second * 0x100 end
            return first * 0x100 + second
        end
        while index <= #bytes do
            local current = unit(index)
            index = index + 2
            if current >= 0xD800 and current <= 0xDBFF then
                if index > #bytes then return nil end
                local following = unit(index)
                if following < 0xDC00 or following > 0xDFFF then return nil end
                codepoints[#codepoints + 1] = 0x10000
                    + (current - 0xD800) * 0x400
                    + following - 0xDC00
                index = index + 2
            elseif current >= 0xDC00 and current <= 0xDFFF then
                return nil
            else
                codepoints[#codepoints + 1] = current
            end
        end
        return text.encode_utf8(codepoints)
    end

    local function encode_utf16(value, little_endian)
        local codepoints, decode_error = text.decode_utf8(value)
        if not codepoints then return nil, decode_error end
        local output = {}
        local function add(unit)
            local low, high = unit % 0x100, unit // 0x100
            if little_endian then
                output[#output + 1] = string.char(low, high)
            else
                output[#output + 1] = string.char(high, low)
            end
        end
        for _, codepoint in ipairs(codepoints) do
            if codepoint <= 0xFFFF then
                add(codepoint)
            else
                local value = codepoint - 0x10000
                add(0xD800 + value // 0x400)
                add(0xDC00 + value % 0x400)
            end
        end
        return table.concat(output)
    end

    local function split_records(value)
        local records, kinds = {}, {}
        local start, index = 1, 1
        while index <= #value do
            local byte = value:byte(index)
            if byte == 0x0A or byte == 0x0D then
                local kind, finish = "lf", index
                if byte == 0x0D then
                    if value:byte(index + 1) == 0x0A then
                        kind, finish = "crlf", index + 1
                    else
                        kind = "cr"
                    end
                end
                records[#records + 1] = { text = value:sub(start, index - 1), newline = kind }
                kinds[kind] = true
                index = finish + 1
                start = index
            else
                index = index + 1
            end
        end
        if start <= #value then records[#records + 1] = { text = value:sub(start), newline = "none" } end
        local kind_count, only = 0
        for kind in pairs(kinds) do kind_count, only = kind_count + 1, kind end
        local newline_kind = kind_count == 0 and "none" or (kind_count == 1 and only or "mixed")
        return records, newline_kind, #records > 0 and records[#records].newline ~= "none"
    end

    local function decode_document(bytes)
        local encoding, decoded, bom_bytes
        if bytes:sub(1, 3) == "\239\187\191" then
            encoding, decoded, bom_bytes = "utf-8-bom", bytes:sub(4), 3
            if text.validate_utf8(decoded) ~= true then return nil, "invalid-encoding" end
        elseif bytes:sub(1, 2) == "\255\254" then
            encoding, decoded, bom_bytes = "utf-16le-bom", decode_utf16(bytes:sub(3), true), 2
            if not decoded then return nil, "invalid-encoding" end
        elseif bytes:sub(1, 2) == "\254\255" then
            encoding, decoded, bom_bytes = "utf-16be-bom", decode_utf16(bytes:sub(3), false), 2
            if not decoded then return nil, "invalid-encoding" end
        else
            encoding, decoded, bom_bytes = "utf-8", bytes, 0
            if text.validate_utf8(decoded) ~= true then return nil, "invalid-encoding" end
        end
        local codepoints = assert(text.decode_utf8(decoded))
        for _, codepoint in ipairs(codepoints) do
            local safe = codepoint == 0x09 or codepoint == 0x0A or codepoint == 0x0D
                or (codepoint >= 0x20 and codepoint <= 0xD7FF)
                or (codepoint >= 0xE000 and codepoint <= 0xFFFD)
                or (codepoint >= 0x10000 and codepoint <= 0x10FFFF)
            if not safe then return nil, "binary-content" end
        end
        local records, newline_kind, final_newline = split_records(decoded)
        return {
            encoding = encoding,
            text = decoded,
            bom_bytes = bom_bytes,
            records = records,
            newline_kind = newline_kind,
            final_newline = final_newline,
        }
    end

    local function normalize_newlines(value, policy)
        if policy == "preserve" then return value end
        local separator = ({ lf = "\n", crlf = "\r\n", cr = "\r" })[policy]
        local records = split_records(value)
        local output = {}
        for _, record in ipairs(records) do
            output[#output + 1] = record.text
            if record.newline ~= "none" then output[#output + 1] = separator end
        end
        return table.concat(output)
    end

    local function encode_document(value, encoding, newline_policy)
        value = normalize_newlines(value, newline_policy)
        if encoding == "utf-8" then return value end
        if encoding == "utf-8-bom" then return "\239\187\191" .. value end
        if encoding == "utf-16le-bom" then
            local encoded, encode_error = encode_utf16(value, true)
            if not encoded then return nil, encode_error end
            return "\255\254" .. encoded
        end
        if encoding == "utf-16be-bom" then
            local encoded, encode_error = encode_utf16(value, false)
            if not encoded then return nil, encode_error end
            return "\254\255" .. encoded
        end
        return nil, failure("InvalidEncoding", "direct text encoding is unknown")
    end

    local function scan_result(bytes)
        if ports.secret_registry == false then return array({}) end
        return ports.secret_registry.scan(bytes)
    end

    local function truncate_utf8(value, maximum)
        if #value <= maximum then return value, false end
        local codepoints = assert(text.decode_utf8(value))
        local output, count = {}, 0
        for _, codepoint in ipairs(codepoints) do
            local encoded = assert(text.encode_scalar(codepoint))
            if count + #encoded > maximum then break end
            output[#output + 1] = encoded
            count = count + #encoded
        end
        return table.concat(output), true
    end

    local function newline_bytes(kind, encoding)
        local value = ({ lf = "\n", crlf = "\r\n", cr = "\r", none = "" })[kind]
        if encoding == "utf-16le-bom" then return assert(encode_utf16(value, true)) end
        if encoding == "utf-16be-bom" then return assert(encode_utf16(value, false)) end
        return value
    end

    local function text_bytes(value, encoding)
        if encoding == "utf-16le-bom" then return assert(encode_utf16(value, true)) end
        if encoding == "utf-16be-bom" then return assert(encode_utf16(value, false)) end
        return value
    end

    local function issue_continuation(state)
        if continuation_count >= limits.maximum_continuations then
            return nil, failure("ContinuationLimit", "too many continuation snapshots are live")
        end
        continuation_serial = continuation_serial + 1
        local token, token_error = ports.safety.binding_digest("yaca-tool-continuation-v1", {
            { name = "tool", value = state.tool },
            { name = "path", value = state.path },
            { name = "generation", value = state.generation },
            { name = "offset", value = state.offset },
            { name = "serial", value = continuation_serial },
        })
        if not token then return nil, token_error end
        continuations[token] = state
        continuation_count = continuation_count + 1
        return token
    end

    local function consume_continuation(token)
        if token and continuations[token] then
            continuations[token] = nil
            continuation_count = continuation_count - 1
        end
    end

    local function page_items(state, page_size, old_token)
        consume_continuation(old_token)
        local first = state.offset
        local last = math.min(#state.items, first + page_size - 1)
        local page = array({})
        for index = first, last do page[#page + 1] = state.items[index] end
        state.offset = last + 1
        local token = false
        if state.offset <= #state.items then
            local token_error
            token, token_error = issue_continuation(state)
            if not token then return nil, token_error end
        end
        return page, token
    end

    local function ensure_walk_generation(state, target, depth)
        local walk_ok, walk = ports.filesystem.direct_walk(
            target.snapshot,
            depth,
            limits.maximum_walk_entries
        )
        if not walk_ok then return nil, walk end
        if state and state.generation ~= walk.generation then
            return nil, failure("ContinuationStale", "walk generation changed")
        end
        return walk
    end

    local function classify_walk_entry(entry)
        local current_ok, current = ports.filesystem.direct_reverify(entry.snapshot)
        if not current_ok then return nil, current end
        local classified, classify_error = inspect_path(current.requested_path)
        if not classified then return nil, classify_error end
        return classified
    end

    local function confirm_walk_generation(target, depth, generation)
        local walk_ok, current = ports.filesystem.direct_walk(
            target.snapshot,
            depth,
            limits.maximum_walk_entries
        )
        if not walk_ok then return nil, current end
        if current.generation ~= generation then
            return nil, failure("TargetChanged", "walk changed while its result was being built")
        end
        return true
    end

    local function execute_list(state)
        local arguments, target = state.arguments, state.targets[1]
        local continuation = state.continuation
        local walk, walk_error = ensure_walk_generation(
            continuation,
            target,
            arguments.depth
        )
        if not walk then
            consume_continuation(arguments.continuation)
            return nil, walk_error
        end
        local page_state = continuation
        if not page_state then
            local items = {}
            for _, entry in ipairs(walk.entries) do
                local classified, classify_error = classify_walk_entry(entry)
                if not classified then return nil, classify_error end
                if classified.reserved then
                    return nil, failure(
                        "ReservedTreeExcluded",
                        "bounded list encountered the reserved tree"
                    )
                end
                local identity = classified.snapshot.identity
                items[#items + 1] = {
                    relative_path = entry.relative_path,
                    type = identity.kind,
                    size = identity.size,
                    modified = identity.modified,
                    link_target = classified.snapshot.metadata.link_target,
                }
            end
            table.sort(items, function(left, right) return left.relative_path < right.relative_path end)
            local confirmed, confirmation_error = confirm_walk_generation(
                target,
                arguments.depth,
                walk.generation
            )
            if not confirmed then return nil, confirmation_error end
            page_state = {
                tool = "list",
                path = arguments.path,
                depth = arguments.depth,
                generation = walk.generation,
                items = items,
                offset = 1,
                complete = walk.complete,
                partial_reason = walk.partial_reason,
            }
        end
        local page, next_token = page_items(
            page_state,
            arguments.page_size,
            arguments.continuation
        )
        if not page then return nil, next_token end
        return {
            entries = page,
            continuation = next_token,
            complete = page_state.complete and next_token == false,
            partial_reason = page_state.partial_reason,
            generation = page_state.generation,
        }
    end

    local function execute_read(state)
        local arguments, target = state.arguments, state.targets[1]
        local read, read_error = read_bytes(target.snapshot)
        if not read then return nil, read_error end
        local hits, scan_error = scan_result(read.bytes)
        if not hits then return nil, scan_error end
        if #hits > 0 then
            local marker_digest = assert(ports.safety.digest(
                "registered-secret-redacted\0" .. tostring(#hits) .. "\0" .. tostring(#read.bytes)
            ))
            return {
                classification = "registered-secret-redacted",
                raw_size = #read.bytes,
                raw_digest = false,
                retention_digest = marker_digest,
                hit_count = #hits,
                lines = array({}),
                eof = true,
            }
        end
        local document, classification = decode_document(read.bytes)
        if not document then
            return {
                classification = classification,
                raw_size = #read.bytes,
                raw_digest = read.digest,
                lines = array({}),
                eof = true,
            }
        end
        local first = arguments.start_line
        local last = math.min(#document.records, first + arguments.max_lines - 1)
        local lines, raw_offset = array({}), document.bom_bytes
        local spans = {}
        for index, record in ipairs(document.records) do
            local bytes = text_bytes(record.text, document.encoding)
                .. newline_bytes(record.newline, document.encoding)
            spans[index] = { first = raw_offset, last = raw_offset + #bytes }
            raw_offset = raw_offset + #bytes
        end
        for index = first, last do
            local record = document.records[index]
            lines[#lines + 1] = {
                number = index,
                text = record.text,
                newline = record.newline,
                raw_start = spans[index].first,
                raw_end = spans[index].last,
            }
        end
        return {
            classification = "text",
            encoding = document.encoding,
            newline = document.newline_kind,
            final_newline = document.final_newline,
            raw_size = #read.bytes,
            raw_digest = read.digest,
            lines = lines,
            next_line = last < #document.records and last + 1 or false,
            eof = last >= #document.records,
        }
    end

    local function ascii_fold(value)
        return (value:gsub("[A-Z]", function(character)
            return string.char(character:byte() + 32)
        end))
    end

    local function scalar_boundaries(value)
        local codepoints = assert(text.decode_utf8(value))
        local boundaries, offset = {}, 1
        for column, codepoint in ipairs(codepoints) do
            boundaries[offset] = column
            offset = offset + #assert(text.encode_scalar(codepoint))
        end
        boundaries[#value + 1] = #codepoints + 1
        return boundaries
    end

    local function next_scalar_boundary(boundaries, offset, maximum)
        while offset <= maximum and boundaries[offset] == nil do offset = offset + 1 end
        return offset
    end

    local function execute_search(state)
        local arguments, target = state.arguments, state.targets[1]
        local continuation = state.continuation
        local walk, walk_error = ensure_walk_generation(
            continuation,
            target,
            limits.maximum_list_depth
        )
        if not walk then
            consume_continuation(arguments.continuation)
            return nil, walk_error
        end
        local page_state = continuation
        if not page_state then
            local matches, skipped_binary, skipped_large, redacted = {}, 0, 0, 0
            local entries = {}
            for _, entry in ipairs(walk.entries) do entries[#entries + 1] = entry end
            table.sort(entries, function(left, right) return left.relative_path < right.relative_path end)
            local stopped = false
            for _, entry in ipairs(entries) do
                if stopped then break end
                local classified, classify_error = classify_walk_entry(entry)
                if not classified then return nil, classify_error end
                if classified.reserved then
                    return nil, failure(
                        "ReservedTreeExcluded",
                        "bounded search encountered the reserved tree"
                    )
                end
                if classified.snapshot.identity.kind == "file" then
                    if classified.snapshot.identity.size > limits.maximum_file_bytes then
                        skipped_large = skipped_large + 1
                    else
                        local read, read_error = read_bytes(classified.snapshot)
                        if not read then return nil, read_error end
                        local hits, scan_error = scan_result(read.bytes)
                        if not hits then return nil, scan_error end
                        if #hits > 0 then
                            redacted = redacted + 1
                        else
                            local document = decode_document(read.bytes)
                            if not document then
                                skipped_binary = skipped_binary + 1
                            else
                                for line_number, record in ipairs(document.records) do
                                    local haystack, needle = record.text, arguments.pattern
                                    local boundaries = scalar_boundaries(record.text)
                                    if not arguments.case_sensitive then
                                        haystack, needle = ascii_fold(haystack), ascii_fold(needle)
                                    end
                                    local offset = 1
                                    while offset <= #haystack + 1 do
                                        local first, last
                                        if arguments.dialect == "literal" then
                                            first, last = haystack:find(needle, offset, true)
                                        else
                                            first, last = haystack:find(needle, offset, false)
                                        end
                                        if not first then break end
                                        local after = last >= first and last + 1 or first
                                        if boundaries[first] and boundaries[after] then
                                            local snippet, truncated = truncate_utf8(
                                                record.text,
                                                limits.maximum_line_bytes
                                            )
                                            matches[#matches + 1] = {
                                                file = entry.relative_path,
                                                line = line_number,
                                                column = boundaries[first],
                                                snippet = snippet,
                                                truncated = truncated,
                                            }
                                            if #matches >= limits.maximum_search_matches then
                                                stopped = true
                                                break
                                            end
                                        end
                                        offset = next_scalar_boundary(
                                            boundaries,
                                            math.max(first + 1, last + 1),
                                            #haystack + 1
                                        )
                                    end
                                    if stopped then break end
                                end
                            end
                        end
                    end
                end
            end
            local confirmed, confirmation_error = confirm_walk_generation(
                target,
                limits.maximum_list_depth,
                walk.generation
            )
            if not confirmed then return nil, confirmation_error end
            page_state = {
                tool = "search",
                path = arguments.path,
                pattern = arguments.pattern,
                dialect = arguments.dialect,
                case_sensitive = arguments.case_sensitive,
                generation = walk.generation,
                items = matches,
                offset = 1,
                complete = walk.complete and not stopped,
                partial_reason = stopped and "match-limit" or walk.partial_reason,
                skipped_binary = skipped_binary,
                skipped_large = skipped_large,
                redacted = redacted,
            }
        end
        local page, next_token = page_items(
            page_state,
            arguments.page_size,
            arguments.continuation
        )
        if not page then return nil, next_token end
        return {
            matches = page,
            continuation = next_token,
            complete = page_state.complete and next_token == false,
            partial_reason = page_state.partial_reason,
            generation = page_state.generation,
            skipped_binary = page_state.skipped_binary,
            skipped_large = page_state.skipped_large,
            redacted_files = page_state.redacted,
        }
    end

    local function directory_of(path)
        local separator
        for index = #path, 1, -1 do
            local byte = path:byte(index)
            if byte == 0x2F or byte == 0x5C then separator = index; break end
        end
        if not separator then return nil end
        if separator == 1 then return path:sub(1, 1) end
        if separator == 3 and path:sub(2, 2) == ":" then return path:sub(1, 3) end
        return path:sub(1, separator - 1)
    end

    local function write_all(handle, bytes)
        local offset = 1
        while offset <= #bytes do
            local chunk = bytes:sub(offset, offset + limits.filesystem_chunk_bytes - 1)
            local written, write_error = ports.filesystem.stream_write(handle, chunk)
            if not written then return nil, write_error end
            offset = offset + #chunk
        end
        return true
    end

    local function cleanup_created(path)
        local target, inspect_error = inspect_path(path)
        if not target then return nil, inspect_error end
        if not target.snapshot.exists then return true end
        local deleted, delete_error = ports.filesystem.direct_delete(target.snapshot)
        if not deleted then return nil, delete_error end
        local flushed, flush_error = ports.filesystem.flush_directory(assert(directory_of(path)))
        if not flushed then return nil, flush_error end
        return true
    end

    local function create_and_fill(missing_snapshot, bytes)
        local created, handle = ports.filesystem.direct_create_new(
            missing_snapshot,
            limits.create_permissions
        )
        if not created then return nil, handle end
        local function abort_created(original_error)
            local cleaned, cleanup_error = cleanup_created(missing_snapshot.canonical_path)
            if not cleaned then
                return nil, failure(
                    "PublicationUnknown",
                    "created file cleanup could not be proven",
                    cleanup_error.code
                )
            end
            return nil, original_error
        end
        local written, write_error = write_all(handle, bytes)
        if not written then
            ports.filesystem.close(handle)
            return abort_created(write_error)
        end
        local flushed, flush_error = ports.filesystem.flush_file(handle)
        if not flushed then
            ports.filesystem.close(handle)
            return abort_created(flush_error)
        end
        local stated, identity = ports.filesystem.stat_identity(handle)
        local closed, close_error = ports.filesystem.close(handle)
        if not stated then return abort_created(identity) end
        if not closed then return abort_created(close_error) end
        if identity.kind ~= "file" or identity.size ~= #bytes then
            return abort_created(failure("PublicationValidation", "created file identity is invalid"))
        end
        local inspected, target = ports.filesystem.direct_inspect(missing_snapshot.canonical_path)
        if not inspected then return abort_created(target) end
        local read, read_error = read_bytes(target)
        if not read then return abort_created(read_error) end
        local expected_digest = assert(ports.safety.digest(bytes))
        if read.digest ~= expected_digest then
            return abort_created(failure(
                "PublicationValidation",
                "created file content validation failed"
            ))
        end
        return { snapshot = target, read = read }
    end

    local function publish_create(target, bytes)
        local filled, fill_error = create_and_fill(target.snapshot, bytes)
        if not filled then return nil, fill_error end
        local directory = assert(directory_of(target.snapshot.canonical_path))
        local flushed, flush_error = ports.filesystem.flush_directory(directory)
        if not flushed then
            return nil, failure(
                "PublicationUnknown",
                "created file directory durability is unknown",
                flush_error.code
            )
        end
        return filled
    end

    local function temporary_path(target_path, operation_id)
        local safe_operation = operation_id:gsub("[^A-Za-z0-9._-]", "-")
        local suffix = ".yaca-" .. safe_operation .. ".tmp"
        if #target_path + #suffix > limits.maximum_path_bytes then
            return nil, failure("PathLimit", "same-directory temporary path exceeds its bound")
        end
        return target_path .. suffix
    end

    local function publish_replace(state, target, bytes)
        local path, path_error = temporary_path(target.snapshot.canonical_path, state.public.operation_id)
        if not path then return nil, path_error end
        local temporary, inspect_error = inspect_path(path)
        if not temporary then return nil, inspect_error end
        if temporary.reserved or temporary.snapshot.exists
            or identity_key(temporary.snapshot.parent_identity)
                ~= identity_key(target.snapshot.parent_identity)
        then
            return nil, failure(
                "TemporaryConflict",
                "same-directory direct temporary is reserved, occupied, or stale"
            )
        end
        local filled, fill_error = create_and_fill(temporary.snapshot, bytes)
        if not filled then return nil, fill_error end
        local replaced, replace_error = ports.filesystem.direct_replace(
            filled.snapshot,
            target.snapshot
        )
        if not replaced then
            if replace_error.code == "Unknown" then
                return nil, failure(
                    "PublicationUnknown",
                    "direct replacement outcome is unknown",
                    replace_error.code
                )
            end
            local cleaned, cleanup_error = cleanup_created(path)
            if not cleaned then
                return nil, failure(
                    "PublicationUnknown",
                    "failed replacement cleanup could not be proven",
                    cleanup_error.code
                )
            end
            return nil, replace_error
        end
        local directory = assert(directory_of(target.snapshot.canonical_path))
        local flushed, flush_error = ports.filesystem.flush_directory(directory)
        if not flushed then
            return nil, failure(
                "PublicationUnknown",
                "replacement directory durability is unknown",
                flush_error.code
            )
        end
        local inspected, published = ports.filesystem.direct_inspect(target.snapshot.canonical_path)
        if not inspected or not published.exists or published.identity.kind ~= "file" then
            return nil, failure(
                "PublicationUnknown",
                "replacement postcondition cannot be inspected",
                inspected and "invalid-target" or published.code
            )
        end
        if published.metadata.behavior_digest ~= target.snapshot.metadata.behavior_digest
            or published.metadata.preservation ~= "proven"
            or published.metadata.link_count ~= 1
        then
            return nil, failure(
                "PublicationUnknown",
                "replacement metadata postcondition is not proven"
            )
        end
        local read, read_error = read_bytes(published)
        if not read then
            return nil, failure(
                "PublicationUnknown",
                "replacement content postcondition cannot be read",
                read_error.code
            )
        end
        local expected_digest = assert(ports.safety.digest(bytes))
        if read.digest ~= expected_digest then
            return nil, failure(
                "PublicationUnknown",
                "replacement content postcondition does not match"
            )
        end
        return { snapshot = published, read = read }
    end

    local function execute_write(state)
        local arguments, target = state.arguments, state.targets[1]
        local bytes, encode_error = encode_document(
            arguments.content,
            arguments.encoding,
            arguments.newline_policy
        )
        if not bytes then return nil, encode_error end
        if #bytes > limits.maximum_file_bytes then
            return nil, failure("FileTooLarge", "encoded write content exceeds maximum_file_bytes")
        end
        local new_digest = assert(ports.safety.digest(bytes))
        if arguments.mode == "create" then
            local published, publish_error = publish_create(target, bytes)
            if not published then return nil, publish_error end
            return {
                mode = "create",
                changed = true,
                old_digest = false,
                new_digest = new_digest,
                raw_size = #bytes,
                identity = identity_object(published.snapshot.identity),
                diff = { old_lines = 0, new_lines = #split_records(arguments.content) },
            }
        end
        local old, old_error = read_bytes(target.snapshot)
        if not old then return nil, old_error end
        if old.digest ~= arguments.expected_raw_digest then
            return nil, failure("TargetChanged", "write base digest no longer matches")
        end
        local document, classification = decode_document(old.bytes)
        if not document then
            return nil, failure(
                classification == "binary-content" and "BinaryContentDenied"
                    or "UnsupportedOrInvalidTextEncoding",
                "write(replace) base is not supported ordinary text"
            )
        end
        if document.encoding ~= arguments.encoding then
            return nil, failure("EncodingChanged", "write encoding does not match the base file")
        end
        if new_digest == old.digest then
            return {
                mode = "replace",
                changed = false,
                old_digest = old.digest,
                new_digest = new_digest,
                raw_size = #bytes,
                identity = identity_object(target.snapshot.identity),
                diff = { old_lines = #document.records, new_lines = #document.records },
            }
        end
        local published, publish_error = publish_replace(state, target, bytes)
        if not published then return nil, publish_error end
        local new_document = assert(decode_document(bytes))
        return {
            mode = "replace",
            changed = true,
            old_digest = old.digest,
            new_digest = new_digest,
            raw_size = #bytes,
            identity = identity_object(published.snapshot.identity),
            diff = { old_lines = #document.records, new_lines = #new_document.records },
        }
    end

    local function matches_context(records, start, expected)
        for index, line in ipairs(expected) do
            local record = records[start + index - 1]
            if not record or record.text ~= line then return false end
        end
        return true
    end

    local function apply_hunks(document, hunks)
        local records = document.records
        local cursor, output = 1, {}
        for hunk_index, hunk in ipairs(hunks) do
            local start = hunk.start_line
            if start < cursor or start > #records + 1 then
                return nil, failure("PatchConflict", "hunk range overlaps or is outside the file", hunk_index)
            end
            local before_start = start - #hunk.context_before
            if before_start < 1
                or not matches_context(records, before_start, hunk.context_before)
                or not matches_context(records, start, hunk.delete_lines)
                or not matches_context(records, start + #hunk.delete_lines, hunk.context_after)
            then
                return nil, failure("PatchConflict", "structured hunk context does not match", hunk_index)
            end
            for index = cursor, start - 1 do output[#output + 1] = records[index] end
            local after_delete = start + #hunk.delete_lines
            local has_following = after_delete <= #records
            for index, line in ipairs(hunk.insert_lines) do
                local newline = hunk.newline
                if index == #hunk.insert_lines and not has_following and not hunk.final_newline then
                    newline = "none"
                end
                output[#output + 1] = { text = line, newline = newline }
            end
            cursor = after_delete
        end
        for index = cursor, #records do output[#output + 1] = records[index] end
        local parts = {}
        for _, record in ipairs(output) do
            parts[#parts + 1] = record.text
            parts[#parts + 1] = ({
                lf = "\n", crlf = "\r\n", cr = "\r", none = "",
            })[record.newline]
        end
        return table.concat(parts), output
    end

    local function execute_patch(state)
        local arguments, target = state.arguments, state.targets[1]
        local old, old_error = read_bytes(target.snapshot)
        if not old then return nil, old_error end
        if old.digest ~= arguments.expected_raw_digest then
            return nil, failure("TargetChanged", "patch base digest no longer matches")
        end
        local document, classification = decode_document(old.bytes)
        if not document then
            return nil, failure(
                classification == "binary-content" and "BinaryContentDenied"
                    or "UnsupportedOrInvalidTextEncoding",
                "patch base is not supported ordinary text"
            )
        end
        local candidate_text, output_or_error = apply_hunks(document, arguments.hunks)
        if not candidate_text then return nil, output_or_error end
        local bytes, encode_error = encode_document(candidate_text, document.encoding, "preserve")
        if not bytes then return nil, encode_error end
        if #bytes > limits.maximum_file_bytes then
            return nil, failure("FileTooLarge", "patched file exceeds maximum_file_bytes")
        end
        local new_digest = assert(ports.safety.digest(bytes))
        if new_digest == old.digest then
            return {
                changed = false,
                old_digest = old.digest,
                new_digest = new_digest,
                raw_size = #bytes,
                identity = identity_object(target.snapshot.identity),
                diff = { old_lines = #document.records, new_lines = #output_or_error },
            }
        end
        local published, publish_error = publish_replace(state, target, bytes)
        if not published then return nil, publish_error end
        return {
            changed = true,
            old_digest = old.digest,
            new_digest = new_digest,
            raw_size = #bytes,
            identity = identity_object(published.snapshot.identity),
            diff = { old_lines = #document.records, new_lines = #output_or_error },
        }
    end

    local function flush_rename_directories(source_path, target_path)
        local source_directory, target_directory = directory_of(source_path), directory_of(target_path)
        local source_ok, source_error = ports.filesystem.flush_directory(source_directory)
        if not source_ok then return nil, source_error end
        if target_directory ~= source_directory then
            local target_ok, target_error = ports.filesystem.flush_directory(target_directory)
            if not target_ok then return nil, target_error end
        end
        return true
    end

    local function execute_rename(state)
        local arguments, source, target = state.arguments, state.targets[1], state.targets[2]
        if source.snapshot.identity.kind == "file" then
            local old, old_error = read_bytes(source.snapshot)
            if not old then return nil, old_error end
            if old.digest ~= arguments.expected_raw_digest then
                return nil, failure("TargetChanged", "rename source digest no longer matches")
            end
        end
        local renamed, rename_error = ports.filesystem.direct_rename(
            source.snapshot,
            target.snapshot
        )
        if not renamed then
            if rename_error.code == "CrossDevice" or rename_error.code == "EXDEV" then
                return nil, failure(
                    "CrossDeviceRenameUnsupported",
                    "direct rename never falls back to copy and delete"
                )
            end
            if rename_error.code == "Unknown" then
                return nil, failure("RenameUnknown", "direct rename outcome is unknown")
            end
            return nil, rename_error
        end
        local flushed, flush_error = flush_rename_directories(arguments.source, arguments.target)
        if not flushed then
            return nil, failure("RenameUnknown", "rename directory durability is unknown", flush_error.code)
        end
        local source_ok, current_source = ports.filesystem.direct_inspect(arguments.source)
        local target_ok, current_target = ports.filesystem.direct_inspect(arguments.target)
        if not source_ok or not target_ok or current_source.exists or not current_target.exists
            or identity_key(current_target.identity) ~= identity_key(source.snapshot.identity)
        then
            return nil, failure("RenameUnknown", "rename postcondition cannot be proven")
        end
        return {
            source = arguments.source,
            target = arguments.target,
            identity = identity_object(current_target.identity),
            cross_device_fallback = false,
        }
    end

    local function execute_delete(state)
        local arguments, target = state.arguments, state.targets[1]
        if target.snapshot.identity.kind == "file" then
            local old, old_error = read_bytes(target.snapshot)
            if not old then return nil, old_error end
            if old.digest ~= arguments.expected_raw_digest then
                return nil, failure("TargetChanged", "delete target digest no longer matches")
            end
        else
            local walk_ok, walk = ports.filesystem.direct_walk(target.snapshot, 0, 1)
            if not walk_ok then return nil, walk end
            if not walk.complete or #walk.entries ~= 0 then
                return nil, failure("DirectoryNotEmpty", "direct delete only removes an empty directory")
            end
        end
        local deleted, delete_error = ports.filesystem.direct_delete(target.snapshot)
        if not deleted then
            if delete_error.code == "Unknown" then
                return nil, failure("DeleteUnknown", "direct delete outcome is unknown")
            end
            return nil, delete_error
        end
        local flushed, flush_error = ports.filesystem.flush_directory(
            assert(directory_of(arguments.path))
        )
        if not flushed then
            return nil, failure("DeleteUnknown", "delete directory durability is unknown", flush_error.code)
        end
        local inspected, current = ports.filesystem.direct_inspect(arguments.path)
        if not inspected or current.exists then
            return nil, failure("DeleteUnknown", "delete postcondition cannot be proven")
        end
        return {
            path = arguments.path,
            deleted_type = target.snapshot.identity.kind,
            irreversible = true,
        }
    end

    local function reverify_boundaries(state)
        local workspace_ok, current_workspace = ports.filesystem.direct_inspect(
            workspace.requested_path
        )
        if not workspace_ok
            or not current_workspace.exists
            or current_workspace.identity.kind ~= "directory"
            or not current_workspace.ancestry_complete
            or current_workspace.canonical_path ~= workspace.canonical_path
            or identity_key(current_workspace.identity) ~= identity_key(workspace.identity)
        then
            return nil, failure("WorkspaceChanged", "workspace identity is stale")
        end
        for index, reserved in ipairs(reserved_snapshots) do
            local reserved_ok, current = ports.filesystem.direct_inspect(reserved.requested_path)
            if not reserved_ok
                or not current.exists
                or current.identity.kind ~= "directory"
                or not current.ancestry_complete
                or current.canonical_path ~= reserved.canonical_path
                or identity_key(current.identity) ~= identity_key(reserved.identity)
            then
                return nil, failure("ReservedTreeChanged", "reserved root identity is stale")
            end
            if reserved_keys[identity_key(current.identity)] ~= true
                or reserved_logical[index] == nil
            then
                return nil, failure("ReservedTreeChanged", "reserved root binding is incomplete")
            end
        end
        for _, target in ipairs(state.targets) do
            local current_ok, current = ports.filesystem.direct_reverify(target.snapshot)
            if not current_ok then return nil, current end
        end
        return true
    end

    local function unknown_error(error_value)
        if type(error_value) ~= "table" or type(error_value.code) ~= "string" then return false end
        return error_value.code:find("Unknown", 1, true) ~= nil
            or error_value.code == "NativeFailure"
    end

    local function result_targets(state)
        local targets = array({})
        for index, target in ipairs(state.targets) do targets[index] = public_target(target) end
        return targets
    end

    local function build_result(state, outcome, payload, error_value)
        local error_projection = false
        if error_value then
            error_projection = {
                code = type(error_value.code) == "string" and error_value.code or "ToolFailure",
                message = type(error_value.message) == "string"
                    and error_value.message or "tool operation failed",
                detail = type(error_value.detail) == "string" and error_value.detail or false,
            }
        end
        local record = {
            tool = state.public.tool,
            schema_version = SCHEMA_VERSION,
            registry_version = REGISTRY_VERSION,
            registry_digest = registry.digest,
            provider_call_id = state.public.provider_call_id,
            tool_call_id = state.public.tool_call_id,
            operation_id = state.public.operation_id,
            call_digest = state.call_digest,
            canonical_arguments = state.public.canonical_arguments,
            targets = result_targets(state),
            outside_workspace = state.public.outside_workspace,
            outcome = outcome,
            payload = payload or false,
            error = error_projection,
        }
        local bytes, encode_error = canonical_json(record)
        if not bytes then return nil, encode_error end
        if #bytes > limits.maximum_result_bytes then
            record.payload = {
                classification = "result-evidence-omitted",
                original_bytes = #bytes,
            }
            bytes = assert(canonical_json(record))
        end
        local hits, scan_error = scan_result(bytes)
        if not hits then return nil, scan_error end
        if #hits > 0 then
            record.payload = {
                classification = "registered-secret-redacted",
                hit_count = #hits,
            }
            bytes = assert(canonical_json(record))
        end
        local digest, digest_error = ports.safety.digest(bytes)
        if not digest then return nil, digest_error end
        record.result_digest = digest
        local body, body_error = canonical_json(record)
        if not body then return nil, body_error end
        if #body > limits.maximum_result_bytes then
            record.payload = {
                classification = "result-evidence-omitted",
                original_bytes = #body,
            }
            record.result_digest = nil
            bytes = assert(canonical_json(record))
            digest, digest_error = ports.safety.digest(bytes)
            if not digest then return nil, digest_error end
            record.result_digest = digest
            body = assert(canonical_json(record))
            if #body > limits.maximum_result_bytes then
                return nil, failure("ResultLimit", "canonical result envelope exceeds its limit")
            end
        end
        local frozen, freeze_error = ports.safety.freeze(record, "canonical tool result")
        if not frozen then return nil, freeze_error end
        return frozen, body
    end

    local function result_status(outcome)
        if outcome == "success" then return "ok" end
        if outcome == "cancelled" or outcome == "timeout" then return "cancelled" end
        if outcome == "unknown" or outcome == "partial" then return "unknown" end
        if outcome == "skipped" then return "skipped" end
        return "error"
    end

    local function make_result(state, outcome, payload, error_value)
        local frozen, body_or_error = build_result(state, outcome, payload, error_value)
        if not frozen then
            if state.operation_handle ~= nil then halted = true end
            return nil, body_or_error
        end
        local body = body_or_error
        if state.operation_handle ~= nil then
            local body_digest, digest_error = ports.safety.digest(body)
            if not body_digest then halted = true; return nil, digest_error end
            local called, committed, commit_error = pcall(
                ports.operations.finish,
                state.operation_handle,
                {
                    status = result_status(frozen.outcome),
                    evidence = "canonical-result:" .. frozen.result_digest,
                    tool_status = result_status(frozen.outcome),
                    tool_body = body,
                    tool_truncated = false,
                    tool_raw_bytes = #body,
                    tool_digest = body_digest,
                }
            )
            if not called or not valid_string(committed, 256, false) then
                halted = true
                return nil, (called and commit_error) or failure(
                    "OperationResultDurabilityUnknown",
                    "tool result did not cross the durable Context barrier"
                )
            end
        end
        state.result = frozen
        return frozen
    end

    local EXECUTORS = {
        list = execute_list,
        read = execute_read,
        search = execute_search,
        write = execute_write,
        patch = execute_patch,
        rename = execute_rename,
        delete = execute_delete,
    }

    local function authorization_current(authorization)
        local called, current, reverify_error = pcall(
            ports.authorization.reverify,
            authorization.call,
            authorization.facts,
            authorization.authority_digest
        )
        if not called or current ~= true then
            return nil, reverify_error or failure(
                "AuthorizationStale",
                "external authorization is no longer current"
            )
        end
        return true
    end

    local function consume_authorization(token, expected_tool)
        local authorization = authorizations[token]
        if not authorization then
            return nil, failure("InvalidAuthorization", "execution token is forged or foreign")
        end
        if authorization.consumed then
            return nil, failure("AuthorizationConsumed", "execution token is one-shot")
        end
        if halted then
            return nil, failure(
                "OperationBarrierBlocked",
                "a prior result durability failure blocks new effects"
            )
        end
        if executing then return nil, failure("ToolBusy", "all v0.1 tools execute serially") end
        local state = authorization.state
        if state.result ~= nil then
            return nil, failure("ToolResultExists", "accepted call already has a terminal result")
        end
        if expected_tool and state.tool ~= expected_tool then
            return nil, failure("InvalidToolCall", "execution surface does not match the tool")
        end
        authorization.consumed = true
        return authorization, state
    end

    ---Executes one authorized direct call exactly once and returns one result.
    -- Raw exec is driven through execution_port so the single event pump can
    -- continue draining output and admit cancellation without a blocking wait.
    function service:execute(token)
        local pending = authorizations[token]
        if pending and not pending.consumed and pending.state.tool == "exec"
            and ports.processes ~= false
        then
            return nil, failure(
                "AsyncExecutionRequired",
                "raw exec must be driven through its foreground AsyncPort"
            )
        end
        local authorization, state_or_error = consume_authorization(token)
        if not authorization then return nil, state_or_error end
        local state = state_or_error
        executing = true
        local current, current_error = authorization_current(authorization)
        if not current then
            local result, result_error = make_result(state, "failed", nil, current_error)
            executing = false
            return result, result_error
        end
        local boundaries, boundary_error = reverify_boundaries(state)
        if not boundaries then
            local result, result_error = make_result(state, "failed", nil, boundary_error)
            executing = false
            return result, result_error
        end
        local executor = EXECUTORS[state.tool]
        if not executor then
            local result, result_error = make_result(
                state,
                "failed",
                nil,
                failure(
                    "ExecUnavailable",
                    "raw exec is attached by the C25 durable operation node"
                )
            )
            executing = false
            return result, result_error
        end
        local executed, payload, operation_error = pcall(executor, state)
        if not executed then
            operation_error = failure("ToolInternalFailure", "tool execution raised an exception")
            payload = nil
        end
        if not payload then
            local outcome = unknown_error(operation_error) and "unknown" or "failed"
            if not executed and MUTATING_TOOLS[state.tool] then outcome = "unknown" end
            local result, result_error = make_result(state, outcome, nil, operation_error)
            executing = false
            return result, result_error
        end
        local result, result_error = make_result(state, "success", payload)
        executing = false
        return result, result_error
    end

    local BASE64_ALPHABET =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

    local function base64_encode(bytes)
        local output = {}
        for index = 1, #bytes, 3 do
            local first = bytes:byte(index)
            local second = bytes:byte(index + 1)
            local third = bytes:byte(index + 2)
            local value = first * 65536 + (second or 0) * 256 + (third or 0)
            output[#output + 1] = BASE64_ALPHABET:sub((value >> 18 & 63) + 1, (value >> 18 & 63) + 1)
            output[#output + 1] = BASE64_ALPHABET:sub((value >> 12 & 63) + 1, (value >> 12 & 63) + 1)
            output[#output + 1] = second
                and BASE64_ALPHABET:sub((value >> 6 & 63) + 1, (value >> 6 & 63) + 1)
                or "="
            output[#output + 1] = third
                and BASE64_ALPHABET:sub((value & 63) + 1, (value & 63) + 1)
                or "="
        end
        return table.concat(output)
    end

    local function strict_output_text(bytes)
        local codepoints = text.decode_utf8(bytes)
        if not codepoints then return nil end
        for _, codepoint in ipairs(codepoints) do
            local safe = codepoint == 0x09 or codepoint == 0x0A or codepoint == 0x0D
                or (codepoint >= 0x20 and codepoint <= 0xD7FF)
                or (codepoint >= 0xE000 and codepoint <= 0xFFFD)
                or (codepoint >= 0x10000 and codepoint <= 0x10FFFF)
            if not safe then return nil end
        end
        return bytes
    end

    local function validate_exec_policy(policy, authorization)
        if not exact_fields(policy, {
            config_generation = true,
            environment_mode = true,
            environment = true,
            output_limit_bytes = true,
            deadline_ms = true,
            decoder = true,
        })
            or policy.config_generation ~= authorization.facts.config_generation
            or (policy.environment_mode ~= "minimal"
                and policy.environment_mode ~= "inherit_filtered")
            or type(policy.environment) ~= "table"
            or not valid_integer(policy.output_limit_bytes, 1)
            or policy.output_limit_bytes > limits.maximum_exec_output_bytes
            or not valid_integer(policy.deadline_ms, 1)
            or policy.deadline_ms > limits.maximum_exec_deadline_ms
            or not valid_string(policy.decoder, 128, false)
        then
            return nil, failure("InvalidExecPolicy", "raw exec policy is invalid or stale")
        end
        return policy
    end

    local function channel_projection(name, process_result, scanner_receipt, decoder)
        local prefix = name .. "_"
        local bytes = process_result[name]
        local observed = process_result[prefix .. "observed_bytes"]
        local retained = process_result[prefix .. "retained_bytes"]
        local discarded = process_result[prefix .. "discarded_bytes"]
        local quota = process_result[prefix .. "quota_bytes"]
        if type(bytes) ~= "string"
            or not valid_integer(observed, 0)
            or not valid_integer(retained, 0)
            or not valid_integer(discarded, 0)
            or not valid_integer(quota, 0)
            or retained ~= #bytes
            or observed ~= retained + discarded
            or type(process_result[prefix .. "truncated"]) ~= "boolean"
            or (scanner_receipt and scanner_receipt.observed_bytes ~= observed)
        then
            return nil, failure("ProcessContract", "raw exec output accounting is invalid")
        end
        if scanner_receipt and scanner_receipt.redacted then
            return {
                stream = name,
                representation = "registered-secret-redacted",
                text = false,
                base64 = false,
                observed_bytes = observed,
                retained_bytes = 0,
                discarded_bytes = observed,
                quota_bytes = quota,
                truncated = true,
                truncation_reason = "registered-secret",
                decoder = decoder,
                replacement_count = 0,
                digest = false,
                digest_scope = "redacted-canonical",
                registered_secret_hits = scanner_receipt.hit_count,
            }
        end
        local digest, digest_error = ports.safety.digest(bytes)
        if not digest then return nil, digest_error end
        local decoded = strict_output_text(bytes)
        return {
            stream = name,
            representation = decoded and "text" or "base64",
            text = decoded or false,
            base64 = decoded and false or base64_encode(bytes),
            observed_bytes = observed,
            retained_bytes = retained,
            discarded_bytes = discarded,
            quota_bytes = quota,
            truncated = process_result[prefix .. "truncated"],
            truncation_reason = process_result[prefix .. "truncated"]
                and "combined-fixed-channel-quota" or false,
            decoder = decoded and decoder or "binary",
            replacement_count = 0,
            digest = digest,
            digest_scope = "retained-raw-bytes",
            registered_secret_hits = 0,
        }
    end

    ---Returns the five-method foreground AsyncPort for one authorized exec.
    -- Progress events expose byte counts only. Raw bytes stay behind the
    -- cross-chunk secret boundary until the terminal canonical result exists.
    function service:execution_port(token, policy)
        if ports.processes == false then
            return nil, failure("ExecUnavailable", "raw exec process capability is unavailable")
        end
        local authorization, state_or_error = consume_authorization(token, "exec")
        if not authorization then return nil, state_or_error end
        local state = state_or_error
        local admitted_policy, policy_error = validate_exec_policy(policy, authorization)
        if not admitted_policy then
            -- The token has not produced a side effect, but its durable intent
            -- must still be closed before another operation may begin.
            executing = true
            local result, result_error = make_result(state, "failed", nil, policy_error)
            executing = false
            return nil, result_error or failure(
                "InvalidExecPolicy",
                "raw exec policy was rejected",
                result and result.result_digest
            )
        end
        executing = true

        local lifecycle = "created"
        local inner
        local terminal
        local deadline_at
        local timed_out = false
        local user_cancelled = false
        local scan_fault
        local scanners = {}
        local port = {}

        local function settle_without_process(outcome, error_value)
            local result, result_error = make_result(state, outcome, nil, error_value)
            terminal = {
                outcome = outcome == "unknown" and "unknown" or "failed",
                tool_result = result or false,
                error = result_error or false,
            }
            if result_error then halted = true; terminal.outcome = "unknown" end
        end

        local function finish_scanner(name)
            if not scanners[name] then return false end
            local called, receipt, scanner_error = pcall(scanners[name].finish)
            if not called or not receipt then
                scan_fault = called and scanner_error or failure(
                    "SecretScanFailure",
                    "registered-secret scanner raised an exception"
                )
                return false
            end
            return receipt
        end

        local function settle_process(process_result)
            if type(process_result) ~= "table"
                or (process_result.outcome ~= "completed"
                    and process_result.outcome ~= "cancelled"
                    and process_result.outcome ~= "failed"
                    and process_result.outcome ~= "unknown")
                or type(process_result.exit_kind) ~= "string"
                or not valid_integer(process_result.duration_ms, 0)
                or type(process_result.descendants_proven_stopped) ~= "boolean"
                or not valid_integer(process_result.observed_sequences, 0)
            then
                settle_without_process(
                    "unknown",
                    failure("ProcessContract", "raw exec terminal result is invalid")
                )
                return
            end
            local stdout_scan = finish_scanner("stdout")
            local stderr_scan = finish_scanner("stderr")
            local stdout, stdout_error = channel_projection(
                "stdout",
                process_result,
                stdout_scan,
                admitted_policy.decoder
            )
            local stderr, stderr_error = channel_projection(
                "stderr",
                process_result,
                stderr_scan,
                admitted_policy.decoder
            )
            local descendants = process_result.descendants_proven_stopped == true
            local tool_outcome, error_value
            if scan_fault or not stdout or not stderr then
                tool_outcome = "unknown"
                error_value = scan_fault or stdout_error or stderr_error
            elseif process_result.outcome == "unknown" or not descendants then
                tool_outcome = "unknown"
                error_value = failure(
                    "ProcessOutcomeUnknown",
                    "raw exec process-tree outcome is not proven"
                )
            elseif timed_out then
                tool_outcome = "timeout"
                error_value = failure("ExecTimeout", "raw exec reached its frozen deadline")
            elseif process_result.outcome == "cancelled" or user_cancelled then
                tool_outcome = "cancelled"
                error_value = failure("ExecCancelled", "raw exec was cancelled")
            elseif process_result.outcome == "failed" then
                tool_outcome = "failed"
                error_value = failure("ProcessFailed", "raw exec process adapter reported failure")
            else
                tool_outcome = "success"
            end
            local payload = stdout and stderr and {
                cwd = state.arguments.cwd,
                stdin = "closed",
                shell = ports.processes.capabilities
                    and ports.processes.capabilities.shell or "fixed-platform-shell",
                environment_mode = admitted_policy.environment_mode,
                process_outcome = process_result.outcome,
                exit_kind = process_result.exit_kind,
                exit_code = process_result.exit_code or false,
                signal_or_exception = process_result.signal_or_exception or false,
                duration_ms = process_result.duration_ms,
                observed_sequences = process_result.observed_sequences,
                stdout = stdout,
                stderr = stderr,
                descendants_proven_stopped = descendants,
                descendant_state = descendants and "proven-stopped" or "unknown",
                external_effects_unsettled = not descendants
                    or process_result.outcome == "unknown",
                deadline_ms = math.min(
                    admitted_policy.deadline_ms,
                    state.arguments.deadline_ms or admitted_policy.deadline_ms
                ),
            } or nil
            local result, result_error = make_result(
                state,
                tool_outcome,
                payload,
                error_value
            )
            local port_outcome = tool_outcome == "success" and "completed"
                or (tool_outcome == "cancelled" or tool_outcome == "timeout") and "cancelled"
                or tool_outcome == "failed" and "failed"
                or "unknown"
            if result_error then halted = true; port_outcome = "unknown" end
            terminal = {
                outcome = port_outcome,
                tool_result = result or false,
                error = result_error or false,
            }
        end

        function port:start(now)
            if lifecycle ~= "created" then error("exec port is " .. lifecycle, 2) end
            if not valid_integer(now, 0) then error("exec start time is invalid", 2) end
            lifecycle = "started"
            local effective_deadline = math.min(
                admitted_policy.deadline_ms,
                state.arguments.deadline_ms or admitted_policy.deadline_ms
            )
            if effective_deadline > math.maxinteger - now then
                settle_without_process(
                    "failed",
                    failure("InvalidDeadline", "raw exec deadline overflows monotonic time")
                )
                return true
            end
            deadline_at = now + effective_deadline
            if ports.secret_registry ~= false then
                for _, name in ipairs({ "stdout", "stderr" }) do
                    local constructed, scanner = pcall(
                        ports.secret_registry.new_stream_scanner
                    )
                    if not constructed or type(scanner) ~= "table"
                        or type(scanner.push) ~= "function"
                        or type(scanner.finish) ~= "function"
                    then
                        settle_without_process(
                            "failed",
                            failure(
                                "SecretScanFailure",
                                "registered-secret scanner could not start"
                            )
                        )
                        return true
                    end
                    scanners[name] = scanner
                end
            end
            local current, current_error = authorization_current(authorization)
            if not current then settle_without_process("failed", current_error); return true end
            local boundaries, boundary_error = reverify_boundaries(state)
            if not boundaries then settle_without_process("failed", boundary_error); return true end
            local constructed, process_port, process_error = pcall(ports.processes.new_port, {
                command = state.arguments.command,
                cwd = state.arguments.cwd,
                environment_mode = admitted_policy.environment_mode,
                environment = admitted_policy.environment,
                output_limit_bytes = admitted_policy.output_limit_bytes,
            })
            if not constructed then
                settle_without_process(
                    "failed",
                    failure("ProcessContract", "raw exec process factory raised an exception")
                )
                return true
            end
            if not process_port then settle_without_process("failed", process_error); return true end
            inner = process_port
            local started, start_error = pcall(inner.start, inner, now)
            if not started then
                settle_without_process(
                    "unknown",
                    failure("ProcessStartUnknown", "raw exec start outcome is unknown")
                )
                return true
            end
            if start_error ~= true then
                settle_without_process(
                    "unknown",
                    failure("ProcessStartUnknown", "raw exec start was not acknowledged")
                )
            end
            return true
        end

        function port:poll(now, budget)
            if lifecycle ~= "started" then error("exec port is " .. lifecycle, 2) end
            if not valid_integer(now, 0) or not valid_integer(budget, 0) then
                error("exec poll arguments are invalid", 2)
            end
            if terminal then
                if terminal.emitted then return {} end
                if budget == 0 then return {} end
                terminal.emitted = true
                return { { kind = "io_terminal", outcome = terminal.outcome } }
            end
            if now >= deadline_at and not timed_out then
                timed_out = true
                local cancelled, cancel_result = pcall(inner.cancel, inner, now)
                if not cancelled then
                    scan_fault = failure(
                        "ProcessCancelUnknown",
                        "raw exec deadline cancellation raised an exception"
                    )
                elseif type(cancel_result) ~= "boolean" then
                    scan_fault = failure(
                        "ProcessCancelUnknown",
                        "raw exec deadline cancellation was not acknowledged"
                    )
                end
            end
            local called, events = pcall(inner.poll, inner, now, budget)
            if not called then
                error("raw exec process poll failed", 2)
            end
            local public_events = {}
            for _, event in ipairs(events) do
                if event.kind == "io_progress" then
                    local scanner = scanners[event.stream]
                    if scanner then
                        local scanned, hits, scanner_error = pcall(scanner.push, event.bytes)
                        if not scanned or not hits then
                            scan_fault = scanned and scanner_error or failure(
                                "SecretScanFailure",
                                "registered-secret scanner raised an exception"
                            )
                        end
                    end
                    public_events[#public_events + 1] = {
                        kind = "io_progress",
                        key = event.stream,
                        stream = event.stream,
                        observed_sequence = event.observed_sequence,
                        observed_bytes = #event.bytes,
                        content = "withheld-until-terminal-secret-scan",
                    }
                elseif event.kind == "io_terminal" then
                    local joined, process_result = pcall(inner.join, inner, now)
                    if not joined then
                        settle_without_process(
                            "unknown",
                            failure("ProcessJoinUnknown", "raw exec terminal join failed")
                        )
                    else
                        settle_process(process_result)
                    end
                    terminal.emitted = true
                    public_events[#public_events + 1] = {
                        kind = "io_terminal",
                        outcome = terminal.outcome,
                    }
                else
                    error("raw exec process emitted an unknown event", 2)
                end
            end
            return public_events
        end

        function port:cancel(now)
            if lifecycle ~= "started" then error("exec port is " .. lifecycle, 2) end
            if terminal then return false end
            if not valid_integer(now, 0) then error("exec cancel time is invalid", 2) end
            user_cancelled = true
            local called, accepted = pcall(inner.cancel, inner, now)
            if not called then
                scan_fault = failure(
                    "ProcessCancelUnknown",
                    "raw exec cancellation raised an exception"
                )
                return false
            end
            return accepted
        end

        function port:join(deadline)
            if lifecycle ~= "started" then error("exec port is " .. lifecycle, 2) end
            if deadline ~= nil and not valid_integer(deadline, 0) then
                error("exec join deadline is invalid", 2)
            end
            if not terminal then error("exec port has not reached terminal truth", 2) end
            lifecycle = "joined"
            return {
                outcome = terminal.outcome,
                tool_result = terminal.tool_result,
                error = terminal.error,
            }
        end

        function port:close()
            if lifecycle ~= "started" and lifecycle ~= "joined" then
                error("exec port is " .. lifecycle, 2)
            end
            local close_error
            if inner then
                local closed, value = pcall(inner.close, inner)
                if not closed or value ~= true then close_error = value end
            end
            lifecycle = "closed"
            executing = false
            if close_error then error("raw exec process close failed", 2) end
            return true
        end

        return port
    end

    ---Returns the terminal result already paired with an admitted call.
    function service:result(call)
        local state = calls[call]
        if not state then return nil, failure("InvalidToolCall", "result lookup requires an admitted call") end
        return state.result or false
    end

    service.registry_version = REGISTRY_VERSION
    service.schema_version = SCHEMA_VERSION
    service.registry_digest = registry.digest
    service.tool_names = assert(ports.safety.freeze(TOOL_ORDER, "tool names"))
    service.capabilities = assert(ports.safety.freeze({
        closed_registry = true,
        direct_no_follow = true,
        recursive_delete = false,
        binary_mutation = false,
        direct_http = false,
        background_jobs = false,
        git_workflow = false,
        backup_or_undo = false,
        serial_execution = true,
        raw_exec = ports.processes ~= false,
        raw_exec_async = ports.processes ~= false,
        durable_operation_barrier = true,
        unknown_auto_replay = false,
        target_qualified = false,
    }, "tool capabilities"))

    return readonly(service, "tool service")
end

return M
