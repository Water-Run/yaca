--[[
File: context.lua
Date: 2026-08-29
Author: WaterRun
Description: Models, reads, writes, and exports canonical internal Context documents.
]]

local text = require("text")
local xml = require("xml")

local M = {}

local SCHEMA_VERSION = "0.1.0"
local document_states = setmetatable({}, { __mode = "k" })
local schema_service_states = setmetatable({}, { __mode = "k" })

local function event(id, required, optional)
    return { id = id, required = required or {}, optional = optional or {} }
end

local EVENT_DEFINITIONS = {
    event("turn_started", {
        "kind", "configGeneration", "modelSnapshot", "permissionSnapshot",
        "promptSnapshot", "toolRegistrySnapshot",
    }, { "runtimeSnapshot" }),
    event("user_message", { "messageId", "text", "source" }, {
        "replyToMessageId",
    }),
    event("model_request", { "requestId", "purpose", "viewManifestRef" }, {
        "attemptId",
    }),
    event("model_message", { "messageId", "requestId", "role", "status", "body" }, {
        "representation", "rawBytes", "digest",
    }),
    event("model_control", { "requestId", "control", "payload" }),
    event("model_yield", { "requestId", "messageId" }),
    event("tool_call", { "toolCallId", "requestId", "name", "canonicalArguments" }, {
        "providerCallId",
    }),
    event("permission_decision", {
        "toolCallId", "capabilities", "decision", "profileSnapshot",
    }),
    event("approval", { "approvalId", "toolCallId", "decision", "snapshotDigest" }, {
        "operationId",
    }),
    event("operation_intent", {
        "operationId", "toolCallId", "kind", "targetIdentity", "expectedDigest",
    }),
    event("operation_result", { "operationId", "status", "evidence" }, {
        "errorId",
    }),
    event("tool_result", { "toolCallId", "status", "body", "truncated" }, {
        "rawBytes", "digest", "errorId",
    }),
    event("action_review", { "reviewId", "toolCallId", "verdict", "bindingDigest" }, {
        "reason",
    }),
    event("termination_review", {
        "reviewId", "requestId", "verdict", "bindingDigest",
    }, { "gap", "reason" }),
    event("turn_ended", { "outcome" }, { "reason", "errorId" }),
    event("cancel", { "targetKind", "targetId", "reason" }, { "result" }),
    event("steer", { "messageId", "targetTurnId", "summary" }),
    event("compaction", {
        "compactionId", "sourceFirstSeq", "sourceLastSeq", "sourceDigest", "status",
    }, { "summary", "errorId" }),
    event("model_view_published", {
        "manifestDigest", "firstEventSeq", "lastEventSeq",
    }, { "replacesManifestDigest" }),
    event("session_override", { "name", "oldValueDigest", "newValueDigest" }, {
        "effectiveAt",
    }),
    event("rename", { "oldName", "newName", "manual", "autoRenameDisabled" }, {
        "oldLogicalPath", "newLogicalPath",
    }),
    event("rebind", {
        "oldLogicalPath", "newLogicalPath", "oldRootIdentity", "newRootIdentity",
    }),
    event("auto_name", { "requestId", "status", "waterline", "baseline" }, {
        "candidateName", "adopted", "errorId",
    }),
    event("config_generation_ref", { "publicDigest" }),
    event("warning", { "errorId", "summary" }, { "causeId" }),
    event("unknown_side_effect", { "operationId", "reason", "requiredAction" }),
    event("import_mapping", {
        "sourceSchema", "modelMappings", "permissionMappings", "decision",
    }, { "notes" }),
}

local EVENT_BY_ID = {}
for _, definition in ipairs(EVENT_DEFINITIONS) do EVENT_BY_ID[definition.id] = definition end

local TURN_OUTCOMES = {
    completed = true,
    waiting_user = true,
    refused = true,
    cancelled = true,
    budget_exhausted = true,
    stuck = true,
    partial = true,
    error = true,
    unknown_side_effect = true,
}
local RESULT_STATUSES = {
    ok = true, error = true, cancelled = true, unknown = true, skipped = true,
}
local MODEL_STATUSES = { complete = true, interrupted = true }
local MODEL_PURPOSES = {
    main = true,
    side = true,
    ["action-review"] = true,
    ["termination-review"] = true,
    compaction = true,
    ["self-test"] = true,
    ["context-name"] = true,
}
local MODEL_CONTROLS = { finish = true, ["ask-user"] = true, refuse = true }
local BOOLEAN_FIELDS = {
    truncated = true,
    manual = true,
    autoRenameDisabled = true,
    adopted = true,
}
local DECIMAL_FIELDS = {
    rawBytes = true,
    sourceFirstSeq = true,
    sourceLastSeq = true,
    firstEventSeq = true,
    lastEventSeq = true,
    waterline = true,
    baseline = true,
}
local IDENTIFIER_FIELDS = {
    messageId = true,
    replyToMessageId = true,
    requestId = true,
    attemptId = true,
    toolCallId = true,
    providerCallId = true,
    approvalId = true,
    operationId = true,
    reviewId = true,
    targetId = true,
    targetTurnId = true,
    compactionId = true,
    errorId = true,
    causeId = true,
}

local function failure(code, message, reason, path, detail)
    local result = { code = code, message = message }
    if reason ~= nil then result.reason = reason end
    if path ~= nil then result.path = path end
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

local function freeze(value, label, visiting)
    if type(value) ~= "table" then return value end
    visiting = visiting or {}
    if visiting[value] then
        return nil, failure("InvalidContextValue", "Context values must not contain cycles")
    end
    visiting[value] = true
    local copied = {}
    for key, item in pairs(value) do
        if type(key) ~= "string" and type(key) ~= "number" then
            visiting[value] = nil
            return nil, failure("InvalidContextValue", "Context table keys are malformed")
        end
        local frozen, freeze_error = freeze(item, label, visiting)
        if frozen == nil and freeze_error then
            visiting[value] = nil
            return nil, freeze_error
        end
        copied[key] = frozen
    end
    visiting[value] = nil
    return readonly(copied, label)
end

local function dense_count(values)
    if type(values) ~= "table" then return nil end
    local count = 0
    for key in pairs(values) do
        if math.type(key) ~= "integer" or key < 1 then return nil end
        count = count + 1
    end
    for index = 1, count do if values[index] == nil then return nil end end
    return count
end

local function valid_integer(value, minimum)
    return math.type(value) == "integer" and value >= minimum
end

local function check_keys(value, allowed, path)
    if type(value) ~= "table" then
        return nil, failure("ContextSchema", "Context object is required", "type", path)
    end
    for key in pairs(value) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure(
                "ContextSchema",
                "Context object contains an unknown field",
                "unknown-field",
                path,
                tostring(key)
            )
        end
    end
    return true
end

local function strict_text(value, maximum_bytes, path, empty)
    if type(value) ~= "string" then
        return nil, failure("ContextSchema", "Context text must be bytes", "type", path)
    end
    if not empty and value == "" then
        return nil, failure("ContextSchema", "Context text must not be empty", "empty", path)
    end
    if #value > maximum_bytes then
        return nil, failure("ContextLimit", "Context text exceeds its byte limit", "bytes", path)
    end
    local carrier, carrier_error = text.text(value)
    if not carrier then
        return nil, failure(
            "ContextSchema",
            "Context text must be strict NUL-free UTF-8",
            carrier_error.code,
            path
        )
    end
    return value
end

local function xml_text(value, maximum_bytes, path, empty)
    local admitted, admitted_error = strict_text(value, maximum_bytes, path, empty)
    if not admitted then return nil, admitted_error end
    if text.xml_carrier_kind(value) ~= "text" then
        return nil, failure(
            "ContextSchema",
            "Context structural text is not lossless XML 1.0 text",
            "xml-text",
            path
        )
    end
    return value
end

local function attribute_text(value, maximum_bytes, path, empty)
    local admitted, admitted_error = xml_text(value, maximum_bytes, path, empty)
    if not admitted then return nil, admitted_error end
    if value:find("[\t\r\n]") then
        return nil, failure(
            "ContextSchema",
            "Context attribute text contains whitespace controls",
            "attribute-control",
            path
        )
    end
    return value
end

local function canonical_decimal(value, minimum, path)
    if type(value) ~= "string" or not value:match("^[0-9]+$")
        or (#value > 1 and value:sub(1, 1) == "0")
    then
        return nil, failure("ContextSchema", "Context decimal is not canonical", "decimal", path)
    end
    local maximum = tostring(math.maxinteger)
    if #value > #maximum or (#value == #maximum and value > maximum) then
        return nil, failure("ContextLimit", "Context decimal exceeds integer range", "integer", path)
    end
    local number = tonumber(value)
    if not valid_integer(number, minimum) then
        return nil, failure("ContextSchema", "Context decimal is outside its range", "range", path)
    end
    return number
end

local function leap_year(year)
    return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

local function canonical_time(value, path)
    if type(value) ~= "string" then
        return nil, failure("ContextSchema", "Context time must be text", "time", path)
    end
    local year, month, day, hour, minute, second = value:match(
        "^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)Z$"
    )
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
    hour, minute, second = tonumber(hour), tonumber(minute), tonumber(second)
    if not year or year == 0 or month < 1 or month > 12
        or hour > 23 or minute > 59 or second > 59
    then
        return nil, failure("ContextSchema", "Context time is not canonical UTC", "time", path)
    end
    local days = { 31, leap_year(year) and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if day < 1 or day > days[month] then
        return nil, failure("ContextSchema", "Context time has an invalid date", "date", path)
    end
    return value
end

local function copy_array(values)
    local copied = {}
    for index, value in ipairs(values) do copied[index] = value end
    return copied
end

local function validate_dependency(options)
    if type(options) ~= "table" then
        return nil, failure("InvalidContextOptions", "Context dependencies and limits are required")
    end
    local allowed = {
        xml = true,
        safety = true,
        maximum_name_bytes = true,
        maximum_identifier_bytes = true,
        maximum_field_name_bytes = true,
        maximum_field_bytes = true,
        maximum_events = true,
        maximum_compaction_records = true,
        maximum_export_bytes = true,
    }
    for key in pairs(options) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure("InvalidContextOptions", "Context options contain an unknown field")
        end
    end
    local codec = options.xml
    if type(codec) ~= "table"
        or type(codec.parse) ~= "function"
        or type(codec.new_writer) ~= "function"
        or type(codec.decode_carrier) ~= "function"
        or type(codec.limits) ~= "table"
    then
        return nil, failure("InvalidContextDependency", "a bounded XML codec is required")
    end
    local safety_service = options.safety
    if type(safety_service) ~= "table" or type(safety_service.digest) ~= "function" then
        return nil, failure("InvalidContextDependency", "a SHA-256 safety service is required")
    end
    for _, name in ipairs({
        "maximum_name_bytes",
        "maximum_identifier_bytes",
        "maximum_field_name_bytes",
        "maximum_field_bytes",
        "maximum_events",
        "maximum_compaction_records",
        "maximum_export_bytes",
    }) do
        if not valid_integer(options[name], 1) then
            return nil, failure("InvalidContextOptions", name .. " must be a positive integer")
        end
    end
    if options.maximum_name_bytes > options.maximum_field_bytes
        or options.maximum_identifier_bytes > options.maximum_field_bytes
        or options.maximum_field_bytes > codec.limits.maximum_carrier_bytes
        or ((options.maximum_field_bytes + 2) // 3) * 4
            > codec.limits.maximum_text_node_bytes
        or options.maximum_events > codec.limits.maximum_context_events
    then
        return nil, failure("InvalidContextOptions", "Context limits exceed XML codec limits")
    end
    return {
        codec = codec,
        safety = safety_service,
        maximum_name_bytes = options.maximum_name_bytes,
        maximum_identifier_bytes = options.maximum_identifier_bytes,
        maximum_field_name_bytes = options.maximum_field_name_bytes,
        maximum_field_bytes = options.maximum_field_bytes,
        maximum_events = options.maximum_events,
        maximum_compaction_records = options.maximum_compaction_records,
        maximum_export_bytes = options.maximum_export_bytes,
    }
end

local function normalize_header(candidate, admitted)
    local valid, valid_error = check_keys(candidate, {
        name = true,
        created_at = true,
        updated_at = true,
        auto_rename_disabled = true,
        naming_waterline = true,
        auto_name_baseline = true,
    }, "/YacaContext/Header")
    if not valid then return nil, valid_error end
    local name, name_error = xml_text(
        candidate.name,
        admitted.maximum_name_bytes,
        "/YacaContext/Header/Name",
        false
    )
    if not name then return nil, name_error end
    local created, created_error = canonical_time(
        candidate.created_at,
        "/YacaContext/Header/CreatedAt"
    )
    if not created then return nil, created_error end
    local updated, updated_error = canonical_time(
        candidate.updated_at,
        "/YacaContext/Header/UpdatedAt"
    )
    if not updated then return nil, updated_error end
    if updated < created then
        return nil, failure(
            "ContextSchema",
            "UpdatedAt precedes CreatedAt",
            "time-order",
            "/YacaContext/Header/UpdatedAt"
        )
    end
    if candidate.auto_rename_disabled ~= nil
        and type(candidate.auto_rename_disabled) ~= "boolean"
    then
        return nil, failure(
            "ContextSchema",
            "AutoRenameDisabled must be boolean when present",
            "boolean",
            "/YacaContext/Header/AutoRenameDisabled"
        )
    end
    for key, element in pairs({
        naming_waterline = "NamingWaterline",
        auto_name_baseline = "AutoNameBaseline",
    }) do
        if candidate[key] ~= nil and not valid_integer(candidate[key], 0) then
            return nil, failure(
                "ContextSchema",
                element .. " must be a non-negative integer",
                "integer",
                "/YacaContext/Header/" .. element
            )
        end
    end
    if candidate.naming_waterline ~= nil and candidate.auto_name_baseline ~= nil
        and candidate.auto_name_baseline > candidate.naming_waterline
    then
        return nil, failure(
            "ContextSchema",
            "AutoNameBaseline exceeds NamingWaterline",
            "waterline-order",
            "/YacaContext/Header/AutoNameBaseline"
        )
    end
    return {
        name = name,
        created_at = created,
        updated_at = updated,
        auto_rename_disabled = candidate.auto_rename_disabled,
        naming_waterline = candidate.naming_waterline,
        auto_name_baseline = candidate.auto_name_baseline,
    }
end

local function normalize_selector(candidate, admitted, path)
    local valid, valid_error = check_keys(candidate, {
        name = true, snapshot_digest = true,
    }, path)
    if not valid then return nil, valid_error end
    local name, name_error = attribute_text(
        candidate.name,
        admitted.maximum_identifier_bytes,
        path .. "/@name",
        false
    )
    if not name then return nil, name_error end
    local digest, digest_error = attribute_text(
        candidate.snapshot_digest,
        admitted.maximum_field_bytes,
        path .. "/@snapshotDigest",
        false
    )
    if not digest then return nil, digest_error end
    return { name = name, snapshot_digest = digest }
end

local function normalize_session(candidate, admitted)
    local valid, valid_error = check_keys(candidate, {
        current_model = true,
        current_permission = true,
        double_check_override = true,
        double_check_goal_override = true,
        context_prompt = true,
    }, "/YacaContext/Session")
    if not valid then return nil, valid_error end
    local current_model, model_error = normalize_selector(
        candidate.current_model,
        admitted,
        "/YacaContext/Session/CurrentModel"
    )
    if not current_model then return nil, model_error end
    local current_permission, permission_error = normalize_selector(
        candidate.current_permission,
        admitted,
        "/YacaContext/Session/CurrentPermission"
    )
    if not current_permission then return nil, permission_error end
    local override = candidate.double_check_override
    if override ~= "inherit" and override ~= true and override ~= false then
        return nil, failure(
            "ContextSchema",
            "DoubleCheckOverride must be inherit, true, or false",
            "enum",
            "/YacaContext/Session/DoubleCheckOverride"
        )
    end
    local goal = candidate.double_check_goal_override
    local goal_valid, goal_valid_error = check_keys(goal, { mode = true, value = true },
        "/YacaContext/Session/DoubleCheckGoalOverride")
    if not goal_valid then return nil, goal_valid_error end
    if goal.mode ~= "inherit" and goal.mode ~= "value" then
        return nil, failure(
            "ContextSchema",
            "DoubleCheckGoalOverride mode is invalid",
            "enum",
            "/YacaContext/Session/DoubleCheckGoalOverride/@mode"
        )
    end
    local goal_value
    if goal.mode == "inherit" then
        if goal.value ~= nil then
            return nil, failure(
                "ContextSchema",
                "inherited DoubleCheck goal cannot carry a value",
                "conditional-field",
                "/YacaContext/Session/DoubleCheckGoalOverride"
            )
        end
    else
        goal_value, goal_valid_error = xml_text(
            goal.value,
            admitted.maximum_field_bytes,
            "/YacaContext/Session/DoubleCheckGoalOverride",
            true
        )
        if not goal_value then return nil, goal_valid_error end
    end
    local context_prompt, prompt_error = xml_text(
        candidate.context_prompt,
        admitted.maximum_field_bytes,
        "/YacaContext/Session/ContextPrompt",
        true
    )
    if not context_prompt then return nil, prompt_error end
    return {
        current_model = current_model,
        current_permission = current_permission,
        double_check_override = override,
        double_check_goal_override = { mode = goal.mode, value = goal_value },
        context_prompt = context_prompt,
    }
end

local function field_metadata(value, admitted, path)
    if type(value) ~= "string" then
        return nil, failure("ContextSchema", "Event fields must contain bytes", "type", path)
    end
    if #value > admitted.maximum_field_bytes then
        return nil, failure("ContextLimit", "Event field exceeds its byte limit", "field", path)
    end
    local carrier, carrier_error = xml.carrier(value)
    if not carrier then return nil, carrier_error end
    local info, info_error = xml.carrier_info(carrier)
    if not info then return nil, info_error end
    local digest
    if info.representation == "base64" then
        digest, carrier_error = admitted.safety.digest(value)
        if not digest then return nil, carrier_error end
        if type(digest) ~= "string" or not digest:match("^[0-9a-f]+$") or #digest ~= 64 then
            return nil, failure(
                "InvalidContextDependency",
                "safety service returned a malformed SHA-256 digest"
            )
        end
    end
    return {
        carrier = carrier,
        representation = info.representation,
        raw_bytes = info.raw_bytes,
        digest = digest,
    }
end

local function normalize_event(candidate, expected_seq, admitted)
    local path = "/YacaContext/Facts/Event[" .. tostring(expected_seq) .. "]"
    local valid, valid_error = check_keys(candidate, {
        seq = true, type = true, at = true, turn_id = true, fields = true,
    }, path)
    if not valid then return nil, valid_error end
    if candidate.seq ~= expected_seq then
        return nil, failure(
            "ContextSequence",
            "Context event sequence must start at one and increment by one",
            "event-sequence",
            path .. "/@seq"
        )
    end
    local definition = EVENT_BY_ID[candidate.type]
    if not definition then
        return nil, failure(
            "ContextSchema",
            "Context event type is unknown",
            "event-type",
            path .. "/@type"
        )
    end
    local at, at_error = canonical_time(candidate.at, path .. "/@at")
    if not at then return nil, at_error end
    local turn_id
    if candidate.turn_id ~= nil then
        turn_id, valid_error = attribute_text(
            candidate.turn_id,
            admitted.maximum_identifier_bytes,
            path .. "/@turnId",
            false
        )
        if not turn_id then return nil, valid_error end
    end
    if type(candidate.fields) ~= "table" then
        return nil, failure("ContextSchema", "Event fields must be a map", "type", path)
    end
    local allowed, order = {}, {}
    for _, name in ipairs(definition.required) do
        allowed[name] = true
        order[#order + 1] = name
        if candidate.fields[name] == nil then
            return nil, failure(
                "ContextSchema",
                "Context event omits a required field",
                "required-field",
                path,
                name
            )
        end
    end
    for _, name in ipairs(definition.optional) do
        allowed[name] = true
        if candidate.fields[name] ~= nil then order[#order + 1] = name end
    end
    for name in pairs(candidate.fields) do
        if type(name) ~= "string" or not allowed[name] then
            return nil, failure(
                "ContextSchema",
                "Context event contains an unknown field",
                "unknown-field",
                path,
                tostring(name)
            )
        end
        if #name > admitted.maximum_field_name_bytes then
            return nil, failure("ContextLimit", "Event field name is too large", "field-name", path)
        end
    end
    local fields, metadata = {}, {}
    for _, name in ipairs(order) do
        local value = candidate.fields[name]
        local field_path = path .. "/Field[@name='" .. name .. "']"
        if IDENTIFIER_FIELDS[name] then
            local identifier, identifier_error = strict_text(
                value,
                admitted.maximum_identifier_bytes,
                field_path,
                false
            )
            if not identifier then return nil, identifier_error end
        end
        if BOOLEAN_FIELDS[name] and value ~= "true" and value ~= "false" then
            return nil, failure(
                "ContextSchema",
                "Context boolean field is invalid",
                "boolean",
                field_path
            )
        end
        if DECIMAL_FIELDS[name] then
            local decimal, decimal_error = canonical_decimal(value, 0, field_path)
            if not decimal then return nil, decimal_error end
        end
        local info, info_error = field_metadata(value, admitted, field_path)
        if not info then return nil, info_error end
        fields[name] = value
        metadata[name] = info
    end
    if candidate.type == "turn_ended" and not TURN_OUTCOMES[fields.outcome] then
        return nil, failure("ContextSchema", "turn outcome is invalid", "enum", path)
    end
    if (candidate.type == "tool_result" or candidate.type == "operation_result")
        and not RESULT_STATUSES[fields.status]
    then
        return nil, failure("ContextSchema", "result status is invalid", "enum", path)
    end
    if candidate.type == "model_message" and not MODEL_STATUSES[fields.status] then
        return nil, failure("ContextSchema", "model message status is invalid", "enum", path)
    end
    if candidate.type == "model_request" and not MODEL_PURPOSES[fields.purpose] then
        return nil, failure("ContextSchema", "model purpose is invalid", "enum", path)
    end
    if candidate.type == "model_control" and not MODEL_CONTROLS[fields.control] then
        return nil, failure("ContextSchema", "model control is invalid", "enum", path)
    end
    if candidate.type == "turn_started"
        and fields.kind ~= "main" and fields.kind ~= "side"
    then
        return nil, failure("ContextSchema", "turn kind is invalid", "enum", path)
    end
    if candidate.type == "permission_decision"
        and fields.decision ~= "allow"
        and fields.decision ~= "confirm"
        and fields.decision ~= "deny"
    then
        return nil, failure("ContextSchema", "permission decision is invalid", "enum", path)
    end
    if candidate.type == "model_message" and fields.representation ~= nil
        and fields.representation ~= "text" and fields.representation ~= "base64"
    then
        return nil, failure(
            "ContextSchema",
            "model representation field is invalid",
            "enum",
            path
        )
    end
    if candidate.type == "compaction" and not ({
        ok = true, error = true, cancelled = true,
    })[fields.status] then
        return nil, failure("ContextSchema", "compaction status is invalid", "enum", path)
    end
    return {
        seq = expected_seq,
        type = candidate.type,
        at = at,
        turn_id = turn_id,
        fields = fields,
        field_order = order,
        field_metadata = metadata,
    }
end

local function reference_error(kind, identifier, path)
    return failure(
        "ContextRelation",
        "Context event refers to an absent or out-of-order " .. kind,
        "missing-reference",
        path,
        identifier
    )
end

local function unique_id(registry, identifier, kind, path)
    if registry[identifier] then
        return nil, failure(
            "ContextRelation",
            "Context local identifier is duplicated",
            "duplicate-" .. kind,
            path,
            identifier
        )
    end
    registry[identifier] = true
    return true
end

local function validate_relations(events)
    local requests, messages, tool_calls, operations = {}, {}, {}, {}
    local approvals, reviews, compactions, turns = {}, {}, {}, {}
    local tool_results, operation_results, permission_decisions = {}, {}, {}
    local unknown_operations = {}
    local published_views = {}

    for _, item in ipairs(events) do
        local fields = item.fields
        local path = "/YacaContext/Facts/Event[" .. tostring(item.seq) .. "]"
        if item.type == "turn_started" and item.turn_id then
            local ok, id_error = unique_id(turns, item.turn_id, "turn", path)
            if not ok then return nil, id_error end
        elseif item.turn_id and not turns[item.turn_id] then
            return nil, reference_error("turn", item.turn_id, path .. "/@turnId")
        end

        if item.type == "user_message" then
            if fields.replyToMessageId and not messages[fields.replyToMessageId] then
                return nil, reference_error(
                    "message",
                    fields.replyToMessageId,
                    path .. "/Field[@name='replyToMessageId']"
                )
            end
            local ok, id_error = unique_id(messages, fields.messageId, "message", path)
            if not ok then return nil, id_error end
        elseif item.type == "model_request" then
            local ok, id_error = unique_id(requests, fields.requestId, "request", path)
            if not ok then return nil, id_error end
        elseif item.type == "model_message" then
            if not requests[fields.requestId] then
                return nil, reference_error("request", fields.requestId, path)
            end
            local ok, id_error = unique_id(messages, fields.messageId, "message", path)
            if not ok then return nil, id_error end
        elseif item.type == "model_control" or item.type == "model_yield" then
            if not requests[fields.requestId] then
                return nil, reference_error("request", fields.requestId, path)
            end
            if item.type == "model_yield" and not messages[fields.messageId] then
                return nil, reference_error("message", fields.messageId, path)
            end
        elseif item.type == "tool_call" then
            if not requests[fields.requestId] then
                return nil, reference_error("request", fields.requestId, path)
            end
            local ok, id_error = unique_id(tool_calls, fields.toolCallId, "tool-call", path)
            if not ok then return nil, id_error end
        elseif item.type == "permission_decision" then
            if not tool_calls[fields.toolCallId] then
                return nil, reference_error("tool call", fields.toolCallId, path)
            end
            if permission_decisions[fields.toolCallId] then
                return nil, failure(
                    "ContextRelation",
                    "tool call has multiple permission decisions",
                    "duplicate-permission-decision",
                    path
                )
            end
            permission_decisions[fields.toolCallId] = true
        elseif item.type == "approval" then
            if not tool_calls[fields.toolCallId] then
                return nil, reference_error("tool call", fields.toolCallId, path)
            end
            local ok, id_error = unique_id(approvals, fields.approvalId, "approval", path)
            if not ok then return nil, id_error end
            if fields.operationId and operations[fields.operationId] == nil then
                -- An approval can bind the operation identity before its intent
                -- is published. Reserve it without treating it as an intent.
                operations[fields.operationId] = false
            end
        elseif item.type == "operation_intent" then
            if not tool_calls[fields.toolCallId] then
                return nil, reference_error("tool call", fields.toolCallId, path)
            end
            if operations[fields.operationId] == true then
                return nil, failure(
                    "ContextRelation",
                    "operation identity is duplicated",
                    "duplicate-operation",
                    path
                )
            end
            operations[fields.operationId] = true
        elseif item.type == "operation_result" then
            if operations[fields.operationId] ~= true then
                return nil, reference_error("operation intent", fields.operationId, path)
            end
            if operation_results[fields.operationId] ~= nil
                or unknown_operations[fields.operationId]
            then
                return nil, failure(
                    "ContextRelation",
                    "operation has more than one terminal result",
                    "duplicate-operation-result",
                    path
                )
            end
            operation_results[fields.operationId] = fields.status
        elseif item.type == "tool_result" then
            if not tool_calls[fields.toolCallId] then
                return nil, reference_error("tool call", fields.toolCallId, path)
            end
            if tool_results[fields.toolCallId] then
                return nil, failure(
                    "ContextRelation",
                    "tool call has more than one terminal result",
                    "duplicate-tool-result",
                    path
                )
            end
            tool_results[fields.toolCallId] = true
        elseif item.type == "action_review" then
            if not tool_calls[fields.toolCallId] then
                return nil, reference_error("tool call", fields.toolCallId, path)
            end
            local ok, id_error = unique_id(reviews, fields.reviewId, "review", path)
            if not ok then return nil, id_error end
        elseif item.type == "termination_review" then
            if not requests[fields.requestId] then
                return nil, reference_error("request", fields.requestId, path)
            end
            local ok, id_error = unique_id(reviews, fields.reviewId, "review", path)
            if not ok then return nil, id_error end
        elseif item.type == "steer" then
            if not turns[fields.targetTurnId] then
                return nil, reference_error("turn", fields.targetTurnId, path)
            end
            local ok, id_error = unique_id(messages, fields.messageId, "message", path)
            if not ok then return nil, id_error end
        elseif item.type == "compaction" then
            local ok, id_error = unique_id(
                compactions,
                fields.compactionId,
                "compaction",
                path
            )
            if not ok then return nil, id_error end
            local first = tonumber(fields.sourceFirstSeq)
            local last = tonumber(fields.sourceLastSeq)
            if first < 1 or first > last or last >= item.seq then
                return nil, failure(
                    "ContextRelation",
                    "compaction source range is invalid",
                    "compaction-range",
                    path
                )
            end
        elseif item.type == "model_view_published" then
            local first = tonumber(fields.firstEventSeq)
            local last = tonumber(fields.lastEventSeq)
            if first > last or last > item.seq
                or (first == 0 and last ~= 0)
                or (first ~= 0 and last == 0)
            then
                return nil, failure(
                    "ContextRelation",
                    "published model-view range is invalid",
                    "model-view-range",
                    path
                )
            end
            published_views[#published_views + 1] = {
                digest = fields.manifestDigest,
                first_event_seq = first,
                last_event_seq = last,
            }
        elseif item.type == "auto_name" then
            if not requests[fields.requestId] then
                return nil, reference_error("request", fields.requestId, path)
            end
        elseif item.type == "unknown_side_effect" then
            if operations[fields.operationId] ~= true
                or operation_results[fields.operationId] ~= nil
                or unknown_operations[fields.operationId]
            then
                return nil, reference_error("unresolved operation", fields.operationId, path)
            end
            unknown_operations[fields.operationId] = true
        end
    end

    local unresolved_operations, unresolved_tool_calls, known_unknown = {}, {}, {}
    for _, item in ipairs(events) do
        if item.type == "operation_intent" then
            local id = item.fields.operationId
            if operation_results[id] == nil then
                unresolved_operations[#unresolved_operations + 1] = id
            end
        elseif item.type == "tool_call" then
            local id = item.fields.toolCallId
            if not tool_results[id] then unresolved_tool_calls[#unresolved_tool_calls + 1] = id end
        elseif item.type == "unknown_side_effect" then
            known_unknown[#known_unknown + 1] = item.fields.operationId
        elseif item.type == "operation_result" and item.fields.status == "unknown" then
            known_unknown[#known_unknown + 1] = item.fields.operationId
        end
    end
    return {
        unresolved_operations = unresolved_operations,
        unresolved_tool_calls = unresolved_tool_calls,
        unknown_operations = known_unknown,
        published_views = published_views,
    }
end

local function normalize_manifest(candidate, admitted, event_count)
    local path = "/YacaContext/ModelView/ActiveManifest"
    local valid, valid_error = check_keys(candidate, {
        digest = true, first_event_seq = true, last_event_seq = true,
    }, path)
    if not valid then return nil, valid_error end
    local digest, digest_error = attribute_text(
        candidate.digest,
        admitted.maximum_field_bytes,
        path .. "/@digest",
        false
    )
    if not digest then return nil, digest_error end
    if not valid_integer(candidate.first_event_seq, 0)
        or not valid_integer(candidate.last_event_seq, 0)
    then
        return nil, failure(
            "ContextSchema",
            "ActiveManifest ranges must be non-negative integers",
            "integer",
            path
        )
    end
    local first, last = candidate.first_event_seq, candidate.last_event_seq
    local current = (event_count == 0 and first == 0 and last == 0)
        or (event_count > 0 and first >= 1 and first <= last and last <= event_count)
    return {
        digest = digest,
        first_event_seq = first,
        last_event_seq = last,
    }, current
end

local function normalize_model_view(candidate, admitted, events, relations)
    local valid, valid_error = check_keys(candidate, {
        active_manifest = true, compaction_records = true,
    }, "/YacaContext/ModelView")
    if not valid then return nil, valid_error end
    local manifest, range_current_or_error = normalize_manifest(
        candidate.active_manifest,
        admitted,
        #events
    )
    if not manifest then return nil, range_current_or_error end
    local range_current = range_current_or_error
    local count = dense_count(candidate.compaction_records)
    if count == nil then
        return nil, failure(
            "ContextSchema",
            "CompactionRecord collection must be a dense array",
            "array",
            "/YacaContext/ModelView"
        )
    end
    if count > admitted.maximum_compaction_records then
        return nil, failure(
            "ContextLimit",
            "Context has too many compaction records",
            "compaction-records",
            "/YacaContext/ModelView"
        )
    end
    local records, seen = {}, {}
    for index, record in ipairs(candidate.compaction_records) do
        local path = "/YacaContext/ModelView/CompactionRecord[" .. tostring(index) .. "]"
        local record_valid, record_error = check_keys(record, {
            id = true,
            source_first_seq = true,
            source_last_seq = true,
            source_digest = true,
            status = true,
            summary = true,
        }, path)
        if not record_valid then return nil, record_error end
        local id, id_error = attribute_text(
            record.id,
            admitted.maximum_identifier_bytes,
            path .. "/@id",
            false
        )
        if not id then return nil, id_error end
        if seen[id] then
            return nil, failure(
                "ContextRelation",
                "CompactionRecord identity is duplicated",
                "duplicate-compaction",
                path
            )
        end
        seen[id] = true
        if not valid_integer(record.source_first_seq, 1)
            or not valid_integer(record.source_last_seq, 1)
            or record.source_first_seq > record.source_last_seq
            or record.source_last_seq > #events
        then
            return nil, failure(
                "ContextRelation",
                "CompactionRecord source range is invalid",
                "compaction-range",
                path
            )
        end
        local source_digest, source_error = attribute_text(
            record.source_digest,
            admitted.maximum_field_bytes,
            path .. "/@sourceDigest",
            false
        )
        if not source_digest then return nil, source_error end
        if record.status ~= "ok" and record.status ~= "error"
            and record.status ~= "cancelled"
        then
            return nil, failure(
                "ContextSchema",
                "CompactionRecord status is invalid",
                "enum",
                path
            )
        end
        local summary
        if record.summary ~= nil then
            summary, record_error = xml_text(
                record.summary,
                admitted.maximum_field_bytes,
                path,
                false
            )
            if not summary then return nil, record_error end
        end
        records[index] = {
            id = id,
            source_first_seq = record.source_first_seq,
            source_last_seq = record.source_last_seq,
            source_digest = source_digest,
            status = record.status,
            summary = summary,
        }
    end
    local latest = relations.published_views[#relations.published_views]
    local published_current = latest == nil or (
        latest.digest == manifest.digest
        and latest.first_event_seq == manifest.first_event_seq
        and latest.last_event_seq == manifest.last_event_seq
    )
    return {
        active_manifest = manifest,
        compaction_records = records,
    }, range_current and published_current
end

local function public_event(item)
    local metadata = {}
    for name, info in pairs(item.field_metadata) do
        metadata[name] = {
            representation = info.representation,
            raw_bytes = info.raw_bytes,
            digest = info.digest,
        }
    end
    return {
        seq = item.seq,
        type = item.type,
        at = item.at,
        turn_id = item.turn_id,
        fields = item.fields,
        field_order = item.field_order,
        field_metadata = metadata,
    }
end

local function create_document(canonical)
    local public_events = {}
    for index, item in ipairs(canonical.events) do public_events[index] = public_event(item) end
    local public = {
        schema_version = SCHEMA_VERSION,
        generation = canonical.generation,
        header = canonical.header,
        session = canonical.session,
        facts = public_events,
        model_view = canonical.model_view,
        event_count = #canonical.events,
        last_event_seq = #canonical.events,
        recovery = canonical.recovery,
    }
    local frozen, freeze_error = freeze(public, "Context document")
    if not frozen then return nil, freeze_error end
    document_states[frozen] = canonical
    return frozen
end

local function normalize_document(candidate, admitted)
    local valid, valid_error = check_keys(candidate, {
        schema_version = true,
        generation = true,
        header = true,
        session = true,
        facts = true,
        model_view = true,
    }, "/YacaContext")
    if not valid then return nil, valid_error end
    local schema_version = candidate.schema_version or SCHEMA_VERSION
    if schema_version ~= SCHEMA_VERSION then
        return nil, failure(
            "UnsupportedContextSchema",
            "Context schema version is unsupported",
            "schema-version",
            "/YacaContext/@schemaVersion",
            schema_version
        )
    end
    if not valid_integer(candidate.generation, 1) then
        return nil, failure(
            "ContextSchema",
            "Context generation must be a positive integer",
            "generation",
            "/YacaContext/@generation"
        )
    end
    local header, header_error = normalize_header(candidate.header, admitted)
    if not header then return nil, header_error end
    local session, session_error = normalize_session(candidate.session, admitted)
    if not session then return nil, session_error end
    local event_count = dense_count(candidate.facts)
    if event_count == nil then
        return nil, failure(
            "ContextSchema",
            "Context Facts must be a dense event array",
            "array",
            "/YacaContext/Facts"
        )
    end
    if event_count > admitted.maximum_events then
        return nil, failure(
            "ContextLimit",
            "Context exceeds its event limit",
            "events",
            "/YacaContext/Facts"
        )
    end
    local events = {}
    for index, event_candidate in ipairs(candidate.facts) do
        local normalized, event_error = normalize_event(event_candidate, index, admitted)
        if not normalized then return nil, event_error end
        events[index] = normalized
    end
    local relations, relation_error = validate_relations(events)
    if not relations then return nil, relation_error end
    local model_view, view_current_or_error = normalize_model_view(
        candidate.model_view,
        admitted,
        events,
        relations
    )
    if not model_view then return nil, view_current_or_error end
    local view_current = view_current_or_error
    local recovery = {
        model_view_status = view_current and "current" or "stale",
        rebuild_model_view = not view_current,
        unresolved_operation_ids = copy_array(relations.unresolved_operations),
        unresolved_tool_call_ids = copy_array(relations.unresolved_tool_calls),
        unknown_operation_ids = copy_array(relations.unknown_operations),
        auto_continue = view_current
            and #relations.unresolved_operations == 0
            and #relations.unresolved_tool_calls == 0
            and #relations.unknown_operations == 0,
    }
    local canonical = {
        generation = candidate.generation,
        header = header,
        session = session,
        events = events,
        model_view = model_view,
        recovery = recovery,
    }
    return create_document(canonical)
end

local function attr(name, value)
    return { name = name, value = value }
end

local function writer_call(writer, method, ...)
    local accepted, writer_error = writer[method](...)
    if not accepted then return nil, writer_error end
    return true
end

local function write_leaf(writer, name, value, attributes)
    local accepted, write_error = writer_call(writer, "start_element", name, attributes)
    if not accepted then return nil, write_error end
    if value ~= nil then
        accepted, write_error = writer_call(writer, "text", value)
        if not accepted then return nil, write_error end
    end
    return writer_call(writer, "end_element", name)
end

local function write_document(codec, canonical, sink)
    local writer, writer_error = codec.new_writer(sink)
    if not writer then return nil, writer_error end
    local accepted
    accepted, writer_error = writer_call(writer, "declaration")
    if not accepted then return nil, writer_error end
    accepted, writer_error = writer_call(writer, "start_element", "YacaContext", {
        attr("schemaVersion", SCHEMA_VERSION),
        attr("generation", tostring(canonical.generation)),
    })
    if not accepted then return nil, writer_error end

    accepted, writer_error = writer_call(writer, "start_element", "Header")
    if not accepted then return nil, writer_error end
    for _, leaf in ipairs({
        { "Name", canonical.header.name },
        { "CreatedAt", canonical.header.created_at },
        { "UpdatedAt", canonical.header.updated_at },
    }) do
        accepted, writer_error = write_leaf(writer, leaf[1], leaf[2])
        if not accepted then return nil, writer_error end
    end
    if canonical.header.auto_rename_disabled ~= nil then
        accepted, writer_error = write_leaf(
            writer,
            "AutoRenameDisabled",
            canonical.header.auto_rename_disabled and "true" or "false"
        )
        if not accepted then return nil, writer_error end
    end
    if canonical.header.naming_waterline ~= nil then
        accepted, writer_error = write_leaf(
            writer,
            "NamingWaterline",
            tostring(canonical.header.naming_waterline)
        )
        if not accepted then return nil, writer_error end
    end
    if canonical.header.auto_name_baseline ~= nil then
        accepted, writer_error = write_leaf(
            writer,
            "AutoNameBaseline",
            tostring(canonical.header.auto_name_baseline)
        )
        if not accepted then return nil, writer_error end
    end
    accepted, writer_error = writer_call(writer, "end_element", "Header")
    if not accepted then return nil, writer_error end

    accepted, writer_error = writer_call(writer, "start_element", "Session")
    if not accepted then return nil, writer_error end
    for _, selector in ipairs({
        { "CurrentModel", canonical.session.current_model },
        { "CurrentPermission", canonical.session.current_permission },
    }) do
        accepted, writer_error = writer_call(writer, "empty_element", selector[1], {
            attr("name", selector[2].name),
            attr("snapshotDigest", selector[2].snapshot_digest),
        })
        if not accepted then return nil, writer_error end
    end
    local override = canonical.session.double_check_override
    accepted, writer_error = write_leaf(
        writer,
        "DoubleCheckOverride",
        override == "inherit" and override or tostring(override)
    )
    if not accepted then return nil, writer_error end
    local goal = canonical.session.double_check_goal_override
    accepted, writer_error = write_leaf(writer, "DoubleCheckGoalOverride", goal.value, {
        attr("mode", goal.mode),
    })
    if not accepted then return nil, writer_error end
    accepted, writer_error = write_leaf(
        writer,
        "ContextPrompt",
        canonical.session.context_prompt
    )
    if not accepted then return nil, writer_error end
    accepted, writer_error = writer_call(writer, "end_element", "Session")
    if not accepted then return nil, writer_error end

    accepted, writer_error = writer_call(writer, "start_element", "Facts")
    if not accepted then return nil, writer_error end
    for _, item in ipairs(canonical.events) do
        local attributes = {
            attr("seq", tostring(item.seq)),
            attr("type", item.type),
            attr("at", item.at),
        }
        if item.turn_id then attributes[#attributes + 1] = attr("turnId", item.turn_id) end
        accepted, writer_error = writer_call(writer, "start_element", "Event", attributes)
        if not accepted then return nil, writer_error end
        for _, name in ipairs(item.field_order) do
            local info = item.field_metadata[name]
            local field_attributes = { attr("name", name) }
            if info.representation == "base64" then
                field_attributes[#field_attributes + 1] = attr("representation", "base64")
                field_attributes[#field_attributes + 1] = attr("rawBytes", tostring(info.raw_bytes))
                field_attributes[#field_attributes + 1] = attr("digest", info.digest)
            end
            accepted, writer_error = writer_call(
                writer,
                "start_element",
                "Field",
                field_attributes
            )
            if not accepted then return nil, writer_error end
            accepted, writer_error = writer_call(writer, "carrier", info.carrier)
            if not accepted then return nil, writer_error end
            accepted, writer_error = writer_call(writer, "end_element", "Field")
            if not accepted then return nil, writer_error end
        end
        accepted, writer_error = writer_call(writer, "end_element", "Event")
        if not accepted then return nil, writer_error end
    end
    accepted, writer_error = writer_call(writer, "end_element", "Facts")
    if not accepted then return nil, writer_error end

    accepted, writer_error = writer_call(writer, "start_element", "ModelView")
    if not accepted then return nil, writer_error end
    local manifest = canonical.model_view.active_manifest
    accepted, writer_error = writer_call(writer, "empty_element", "ActiveManifest", {
        attr("digest", manifest.digest),
        attr("firstEventSeq", tostring(manifest.first_event_seq)),
        attr("lastEventSeq", tostring(manifest.last_event_seq)),
    })
    if not accepted then return nil, writer_error end
    for _, record in ipairs(canonical.model_view.compaction_records) do
        local attributes = {
            attr("id", record.id),
            attr("sourceFirstSeq", tostring(record.source_first_seq)),
            attr("sourceLastSeq", tostring(record.source_last_seq)),
            attr("sourceDigest", record.source_digest),
            attr("status", record.status),
        }
        if record.summary == nil then
            accepted, writer_error = writer_call(
                writer,
                "empty_element",
                "CompactionRecord",
                attributes
            )
        else
            accepted, writer_error = write_leaf(
                writer,
                "CompactionRecord",
                record.summary,
                attributes
            )
        end
        if not accepted then return nil, writer_error end
    end
    accepted, writer_error = writer_call(writer, "end_element", "ModelView")
    if not accepted then return nil, writer_error end
    accepted, writer_error = writer_call(writer, "end_element", "YacaContext")
    if not accepted then return nil, writer_error end
    return writer.finish()
end

local function exact_attributes(attributes, required, optional, path)
    local allowed, copied = {}, {}
    for _, name in ipairs(required) do allowed[name] = true end
    for _, name in ipairs(optional or {}) do allowed[name] = true end
    for name, value in pairs(attributes) do
        if type(name) ~= "string" or not allowed[name] then
            return nil, failure(
                "ContextSchema",
                "Context element contains an unknown attribute",
                "unknown-attribute",
                path,
                tostring(name)
            )
        end
        copied[name] = value
    end
    for _, name in ipairs(required) do
        if copied[name] == nil then
            return nil, failure(
                "ContextSchema",
                "Context element omits a required attribute",
                "required-attribute",
                path,
                name
            )
        end
    end
    return copied
end

local CONTAINERS = {
    YacaContext = true,
    Header = true,
    Session = true,
    Facts = true,
    Event = true,
    ModelView = true,
}

local HEADER_RANK = {
    Name = 1,
    CreatedAt = 2,
    UpdatedAt = 3,
    AutoRenameDisabled = 4,
    NamingWaterline = 5,
    AutoNameBaseline = 6,
}
local SESSION_RANK = {
    CurrentModel = 1,
    CurrentPermission = 2,
    DoubleCheckOverride = 3,
    DoubleCheckGoalOverride = 4,
    ContextPrompt = 5,
}

local function read_candidate(codec, safety_service, source, admitted)
    local candidate = {
        header = {},
        session = {},
        facts = {},
        model_view = { compaction_records = {} },
    }
    local frames = {}
    local semantic_error
    local root_stage, header_stage, session_stage, model_stage = 0, 0, 0, 0

    local function reject(error_value)
        semantic_error = semantic_error or error_value
        return false, error_value.message
    end

    local function parent()
        return frames[#frames]
    end

    local function start_element(name, attributes, path)
        if semantic_error then return false, semantic_error.message end
        local parent_frame = parent()
        local parent_name = parent_frame and parent_frame.name or nil
        local parsed, parsed_error

        if parent_frame and not CONTAINERS[parent_name] then
            return reject(failure(
                "ContextSchema",
                "Context leaf elements cannot contain children",
                "nested-element",
                path
            ))
        end

        if not parent_name then
            if name ~= "YacaContext" or #frames ~= 0 or candidate.schema_version ~= nil then
                return reject(failure(
                    "ContextSchema",
                    "Context document must have exactly one YacaContext root",
                    "root",
                    path
                ))
            end
            parsed, parsed_error = exact_attributes(
                attributes,
                { "schemaVersion", "generation" },
                {},
                path
            )
            if not parsed then return reject(parsed_error) end
            candidate.schema_version = parsed.schemaVersion
            local generation
            generation, parsed_error = canonical_decimal(
                parsed.generation,
                1,
                path .. "/@generation"
            )
            if not generation then return reject(parsed_error) end
            candidate.generation = generation
        elseif parent_name == "YacaContext" then
            local expected = ({ "Header", "Session", "Facts", "ModelView" })[root_stage + 1]
            if name ~= expected then
                return reject(failure(
                    "ContextSchema",
                    "YacaContext children are missing, duplicated, or out of order",
                    "child-order",
                    path
                ))
            end
            parsed, parsed_error = exact_attributes(attributes, {}, {}, path)
            if not parsed then return reject(parsed_error) end
            root_stage = root_stage + 1
        elseif parent_name == "Header" then
            local rank = HEADER_RANK[name]
            if not rank or rank <= header_stage
                or (header_stage < 3 and rank ~= header_stage + 1)
            then
                return reject(failure(
                    "ContextSchema",
                    "Header children are missing, duplicated, or out of order",
                    "child-order",
                    path
                ))
            end
            parsed, parsed_error = exact_attributes(attributes, {}, {}, path)
            if not parsed then return reject(parsed_error) end
            header_stage = rank
        elseif parent_name == "Session" then
            local rank = SESSION_RANK[name]
            if not rank or rank ~= session_stage + 1 then
                return reject(failure(
                    "ContextSchema",
                    "Session children are missing, duplicated, or out of order",
                    "child-order",
                    path
                ))
            end
            if name == "CurrentModel" or name == "CurrentPermission" then
                parsed, parsed_error = exact_attributes(
                    attributes,
                    { "name", "snapshotDigest" },
                    {},
                    path
                )
            elseif name == "DoubleCheckGoalOverride" then
                parsed, parsed_error = exact_attributes(attributes, { "mode" }, {}, path)
            else
                parsed, parsed_error = exact_attributes(attributes, {}, {}, path)
            end
            if not parsed then return reject(parsed_error) end
            session_stage = rank
        elseif parent_name == "Facts" then
            if name ~= "Event" then
                return reject(failure(
                    "ContextSchema",
                    "Facts accepts only Event children",
                    "unknown-element",
                    path
                ))
            end
            parsed, parsed_error = exact_attributes(
                attributes,
                { "seq", "type", "at" },
                { "turnId" },
                path
            )
            if not parsed then return reject(parsed_error) end
            local seq
            seq, parsed_error = canonical_decimal(parsed.seq, 1, path .. "/@seq")
            if not seq then return reject(parsed_error) end
            parent_frame = {
                name = name,
                text = {},
                text_seen = false,
                event = {
                    seq = seq,
                    type = parsed.type,
                    at = parsed.at,
                    turn_id = parsed.turnId,
                    fields = {},
                },
                field_names = {},
            }
            frames[#frames + 1] = parent_frame
            return true
        elseif parent_name == "Event" then
            if name ~= "Field" then
                return reject(failure(
                    "ContextSchema",
                    "Event accepts only Field children",
                    "unknown-element",
                    path
                ))
            end
            parsed, parsed_error = exact_attributes(
                attributes,
                { "name" },
                { "representation", "rawBytes", "digest" },
                path
            )
            if not parsed then return reject(parsed_error) end
            if parent_frame.field_names[parsed.name] then
                return reject(failure(
                    "ContextSchema",
                    "Event Field name is duplicated",
                    "duplicate-field",
                    path,
                    parsed.name
                ))
            end
            parent_frame.field_names[parsed.name] = true
        elseif parent_name == "ModelView" then
            if name == "ActiveManifest" and model_stage == 0 then
                parsed, parsed_error = exact_attributes(attributes, {
                    "digest", "firstEventSeq", "lastEventSeq",
                }, {}, path)
                model_stage = 1
            elseif name == "CompactionRecord" and model_stage >= 1 then
                parsed, parsed_error = exact_attributes(attributes, {
                    "id", "sourceFirstSeq", "sourceLastSeq", "sourceDigest", "status",
                }, {}, path)
                model_stage = model_stage + 1
            else
                return reject(failure(
                    "ContextSchema",
                    "ModelView children are missing or out of order",
                    "child-order",
                    path
                ))
            end
            if not parsed then return reject(parsed_error) end
        else
            return reject(failure(
                "ContextSchema",
                "Context contains an unknown structure",
                "unknown-element",
                path
            ))
        end

        frames[#frames + 1] = {
            name = name,
            attributes = parsed or {},
            text = {},
            text_seen = false,
        }
        return true
    end

    local function character_data(value, path)
        if semantic_error then return false, semantic_error.message end
        local frame = parent()
        if not frame then
            return reject(failure("ContextSchema", "Context text is outside the root", "text", path))
        end
        if CONTAINERS[frame.name] then
            if value:find("[^ \t\r\n]") then
                return reject(failure(
                    "ContextSchema",
                    "Context containers accept only formatting whitespace",
                    "mixed-content",
                    path
                ))
            end
            return true
        end
        frame.text[#frame.text + 1] = value
        frame.text_seen = true
        return true
    end

    local function end_element(name, path)
        if semantic_error then return false, semantic_error.message end
        local frame = frames[#frames]
        if not frame or frame.name ~= name then
            return reject(failure(
                "ContextSchema",
                "Context element stack is inconsistent",
                "element-stack",
                path
            ))
        end
        local value = table.concat(frame.text)
        local parent_frame = frames[#frames - 1]
        local parent_name = parent_frame and parent_frame.name or nil
        local parsed_error

        if name == "YacaContext" then
            if root_stage ~= 4 then
                return reject(failure(
                    "ContextSchema",
                    "YacaContext omits required sections",
                    "required-section",
                    path
                ))
            end
        elseif name == "Header" then
            if header_stage < 3 then
                return reject(failure(
                    "ContextSchema",
                    "Header omits required fields",
                    "required-element",
                    path
                ))
            end
        elseif name == "Session" then
            if session_stage ~= 5 then
                return reject(failure(
                    "ContextSchema",
                    "Session omits required fields",
                    "required-element",
                    path
                ))
            end
        elseif name == "ModelView" then
            if model_stage < 1 then
                return reject(failure(
                    "ContextSchema",
                    "ModelView omits ActiveManifest",
                    "required-element",
                    path
                ))
            end
        elseif parent_name == "Header" then
            if name == "Name" then candidate.header.name = value
            elseif name == "CreatedAt" then candidate.header.created_at = value
            elseif name == "UpdatedAt" then candidate.header.updated_at = value
            elseif name == "AutoRenameDisabled" then
                if value ~= "true" and value ~= "false" then
                    return reject(failure(
                        "ContextSchema", "AutoRenameDisabled is invalid", "boolean", path
                    ))
                end
                candidate.header.auto_rename_disabled = value == "true"
            elseif name == "NamingWaterline" or name == "AutoNameBaseline" then
                local number
                number, parsed_error = canonical_decimal(value, 0, path)
                if not number then return reject(parsed_error) end
                candidate.header[name == "NamingWaterline"
                    and "naming_waterline" or "auto_name_baseline"] = number
            end
        elseif parent_name == "Session" then
            if name == "CurrentModel" or name == "CurrentPermission" then
                if frame.text_seen then
                    return reject(failure(
                        "ContextSchema",
                        name .. " must be empty",
                        "mixed-content",
                        path
                    ))
                end
                candidate.session[name == "CurrentModel"
                    and "current_model" or "current_permission"] = {
                    name = frame.attributes.name,
                    snapshot_digest = frame.attributes.snapshotDigest,
                }
            elseif name == "DoubleCheckOverride" then
                if value == "true" then candidate.session.double_check_override = true
                elseif value == "false" then candidate.session.double_check_override = false
                elseif value == "inherit" then candidate.session.double_check_override = "inherit"
                else
                    return reject(failure(
                        "ContextSchema", "DoubleCheckOverride is invalid", "enum", path
                    ))
                end
            elseif name == "DoubleCheckGoalOverride" then
                candidate.session.double_check_goal_override = {
                    mode = frame.attributes.mode,
                    value = frame.attributes.mode == "value" and value or nil,
                }
                if frame.attributes.mode == "inherit" and frame.text_seen then
                    return reject(failure(
                        "ContextSchema",
                        "inherited DoubleCheck goal must be empty",
                        "conditional-field",
                        path
                    ))
                end
            elseif name == "ContextPrompt" then
                candidate.session.context_prompt = value
            end
        elseif name == "Field" and parent_name == "Event" then
            local attributes = frame.attributes
            local representation = attributes.representation or "text"
            local raw_bytes
            if representation == "text" then
                if attributes.rawBytes ~= nil or attributes.digest ~= nil then
                    return reject(failure(
                        "ContextSchema",
                        "text Field cannot carry binary metadata",
                        "carrier-attributes",
                        path
                    ))
                end
            elseif representation == "base64" then
                if attributes.rawBytes == nil or attributes.digest == nil then
                    return reject(failure(
                        "ContextSchema",
                        "base64 Field requires rawBytes and digest",
                        "carrier-attributes",
                        path
                    ))
                end
                raw_bytes, parsed_error = canonical_decimal(attributes.rawBytes, 0, path)
                if not raw_bytes then return reject(parsed_error) end
                if not attributes.digest:match("^[0-9a-f]+$") or #attributes.digest ~= 64 then
                    return reject(failure(
                        "ContextSchema",
                        "base64 Field digest is malformed",
                        "digest",
                        path
                    ))
                end
            else
                return reject(failure(
                    "ContextSchema", "Field representation is invalid", "carrier", path
                ))
            end
            local carrier
            carrier, parsed_error = codec.decode_carrier(representation, value, raw_bytes)
            if not carrier then return reject(parsed_error) end
            local bytes
            bytes, parsed_error = xml.carrier_bytes(carrier)
            if not bytes then return reject(parsed_error) end
            local canonical_carrier = assert(xml.carrier(bytes))
            local canonical_info = assert(xml.carrier_info(canonical_carrier))
            if canonical_info.representation ~= representation then
                return reject(failure(
                    "ContextSchema",
                    "Field representation is not canonical for its bytes",
                    "noncanonical-carrier",
                    path
                ))
            end
            if representation == "base64" then
                local digest
                digest, parsed_error = safety_service.digest(bytes)
                if not digest then return reject(parsed_error) end
                if digest ~= attributes.digest then
                    return reject(failure(
                        "ContextIntegrity",
                        "base64 Field digest does not match exact bytes",
                        "digest-mismatch",
                        path
                    ))
                end
            end
            parent_frame.event.fields[attributes.name] = bytes
        elseif name == "Event" and parent_name == "Facts" then
            candidate.facts[#candidate.facts + 1] = frame.event
        elseif name == "ActiveManifest" and parent_name == "ModelView" then
            if frame.text_seen then
                return reject(failure(
                    "ContextSchema", "ActiveManifest must be empty", "mixed-content", path
                ))
            end
            local first, last
            first, parsed_error = canonical_decimal(frame.attributes.firstEventSeq, 0, path)
            if not first then return reject(parsed_error) end
            last, parsed_error = canonical_decimal(frame.attributes.lastEventSeq, 0, path)
            if not last then return reject(parsed_error) end
            candidate.model_view.active_manifest = {
                digest = frame.attributes.digest,
                first_event_seq = first,
                last_event_seq = last,
            }
        elseif name == "CompactionRecord" and parent_name == "ModelView" then
            local first, last
            first, parsed_error = canonical_decimal(frame.attributes.sourceFirstSeq, 1, path)
            if not first then return reject(parsed_error) end
            last, parsed_error = canonical_decimal(frame.attributes.sourceLastSeq, 1, path)
            if not last then return reject(parsed_error) end
            candidate.model_view.compaction_records[#candidate.model_view.compaction_records + 1] = {
                id = frame.attributes.id,
                source_first_seq = first,
                source_last_seq = last,
                source_digest = frame.attributes.sourceDigest,
                status = frame.attributes.status,
                summary = frame.text_seen and value or nil,
            }
        end

        frames[#frames] = nil
        return true
    end

    local sink = {
        start_element = start_element,
        text = character_data,
        end_element = end_element,
    }
    local stats, parse_error
    if type(source) == "function" then
        local reader
        reader, parse_error = codec.new_reader(sink)
        if not reader then return nil, parse_error end
        while true do
            local called, ok, chunk_or_error = pcall(source)
            if not called then
                reader.close()
                return nil, failure("ContextStream", "Context stream source raised an error")
            end
            if ok ~= true
                or type(chunk_or_error) ~= "table"
                or type(chunk_or_error.bytes) ~= "string"
                or type(chunk_or_error.eof) ~= "boolean"
            then
                reader.close()
                return nil, ok == false and chunk_or_error or failure(
                    "ContextStream",
                    "Context stream source returned a malformed chunk"
                )
            end
            if #chunk_or_error.bytes == 0 and not chunk_or_error.eof then
                reader.close()
                return nil, failure("ContextStream", "Context stream made no progress")
            end
            local accepted, feed_error = reader.feed(chunk_or_error.bytes)
            if not accepted then return nil, semantic_error or feed_error end
            if chunk_or_error.eof then break end
        end
        stats, parse_error = reader.finish()
    else
        stats, parse_error = codec.parse(source, sink)
    end
    if not stats then return nil, semantic_error or parse_error end
    if semantic_error then return nil, semantic_error end
    if #frames ~= 0 or candidate.schema_version == nil then
        return nil, failure("ContextSchema", "Context document is incomplete", "incomplete")
    end
    return candidate, stats
end

local function markdown_code(value)
    local visible, visible_error = text.display_lossy(value, {
        ascii_only = false,
        allow_newline = false,
    })
    if not visible then return nil, visible_error end
    visible = visible
        :gsub("`", "\\x60")
        :gsub("<", "\\x3C")
        :gsub(">", "\\x3E")
    return "`" .. visible .. "`"
end

local function export_document(canonical, admitted, sink)
    if sink ~= nil and type(sink) ~= "function" then
        return nil, failure("InvalidContextExport", "Context export sink must be a function")
    end
    local output = sink == nil and {} or nil
    local bytes_written = 0
    local function emit(bytes)
        if bytes_written > admitted.maximum_export_bytes - #bytes then
            return nil, failure(
                "ContextExportLimit",
                "Context export exceeds its byte limit",
                "bytes"
            )
        end
        if sink then
            local called, accepted, sink_error = pcall(sink, bytes)
            if not called then
                return nil, failure(
                    "ContextExportSink",
                    "Context export sink raised an error",
                    "sink",
                    nil,
                    { output_unknown = true }
                )
            end
            if accepted ~= true and accepted ~= #bytes then
                return nil, failure(
                    "ContextExportSink",
                    type(sink_error) == "string" and sink_error
                        or "Context export sink rejected bytes",
                    "sink",
                    nil,
                    { output_unknown = true }
                )
            end
        else
            output[#output + 1] = bytes
        end
        bytes_written = bytes_written + #bytes
        return true
    end
    local function line(label, value)
        local rendered, render_error = markdown_code(value)
        if not rendered then return nil, render_error end
        return emit("- " .. label .. ": " .. rendered .. "\n")
    end

    local accepted, export_error = emit("# yaca Context export v1\n\n")
    if not accepted then return nil, export_error end
    for _, item in ipairs({
        { "Name", canonical.header.name },
        { "Schema", SCHEMA_VERSION },
        { "Generation", tostring(canonical.generation) },
        { "Created", canonical.header.created_at },
        { "Updated", canonical.header.updated_at },
    }) do
        accepted, export_error = line(item[1], item[2])
        if not accepted then return nil, export_error end
    end

    accepted, export_error = emit("\n## Session\n\n")
    if not accepted then return nil, export_error end
    for _, item in ipairs({
        { "Model", canonical.session.current_model.name },
        { "Model snapshot", canonical.session.current_model.snapshot_digest },
        { "Permission", canonical.session.current_permission.name },
        { "Permission snapshot", canonical.session.current_permission.snapshot_digest },
        {
            "DoubleCheck",
            canonical.session.double_check_override == "inherit"
                and "inherit"
                or tostring(canonical.session.double_check_override),
        },
        {
            "DoubleCheck goal mode",
            canonical.session.double_check_goal_override.mode,
        },
        {
            "Context prompt",
            canonical.session.context_prompt,
        },
    }) do
        accepted, export_error = line(item[1], item[2])
        if not accepted then return nil, export_error end
    end
    if canonical.session.double_check_goal_override.mode == "value" then
        accepted, export_error = line(
            "DoubleCheck goal",
            canonical.session.double_check_goal_override.value
        )
        if not accepted then return nil, export_error end
    end

    accepted, export_error = emit("\n## Facts\n")
    if not accepted then return nil, export_error end
    for _, item in ipairs(canonical.events) do
        accepted, export_error = emit(
            "\n### Event " .. tostring(item.seq) .. " `" .. item.type .. "`\n\n"
        )
        if not accepted then return nil, export_error end
        accepted, export_error = line("At", item.at)
        if not accepted then return nil, export_error end
        if item.turn_id then
            accepted, export_error = line("Turn ID", item.turn_id)
            if not accepted then return nil, export_error end
        end
        for _, name in ipairs(item.field_order) do
            local info = item.field_metadata[name]
            local label = "Field " .. name .. " (" .. info.representation
                .. ", " .. tostring(info.raw_bytes) .. " bytes)"
            local value
            if info.representation == "base64" then
                local carrier_info
                carrier_info, export_error = xml.carrier_info(info.carrier)
                if not carrier_info then return nil, export_error end
                value = carrier_info.encoded
                label = label .. " sha256=" .. info.digest
            else
                value = item.fields[name]
            end
            accepted, export_error = line(label, value)
            if not accepted then return nil, export_error end
        end
    end

    accepted, export_error = emit("\n## Model view\n\n")
    if not accepted then return nil, export_error end
    local manifest = canonical.model_view.active_manifest
    for _, item in ipairs({
        { "Manifest", manifest.digest },
        { "First event", tostring(manifest.first_event_seq) },
        { "Last event", tostring(manifest.last_event_seq) },
        { "Status", canonical.recovery.model_view_status },
    }) do
        accepted, export_error = line(item[1], item[2])
        if not accepted then return nil, export_error end
    end
    for _, record in ipairs(canonical.model_view.compaction_records) do
        local rendered_id
        rendered_id, export_error = markdown_code(record.id)
        if not rendered_id then return nil, export_error end
        accepted, export_error = emit("\n### Compaction " .. rendered_id .. "\n\n")
        if not accepted then return nil, export_error end
        for _, item in ipairs({
            { "Source first", tostring(record.source_first_seq) },
            { "Source last", tostring(record.source_last_seq) },
            { "Source digest", record.source_digest },
            { "Status", record.status },
        }) do
            accepted, export_error = line(item[1], item[2])
            if not accepted then return nil, export_error end
        end
        if record.summary ~= nil then
            accepted, export_error = line("Summary", record.summary)
            if not accepted then return nil, export_error end
        end
    end
    if sink then
        return readonly({ bytes = bytes_written, events = #canonical.events },
            "Context export statistics")
    end
    return table.concat(output)
end

local function mutable_copy(value, visiting)
    if type(value) ~= "table" then return value end
    visiting = visiting or {}
    if visiting[value] then
        return nil, failure("InvalidContextValue", "Context values must not contain cycles")
    end
    visiting[value] = true
    local copied = {}
    for key, item in pairs(value) do
        local mutable, copy_error = mutable_copy(item, visiting)
        if mutable == nil and copy_error then
            visiting[value] = nil
            return nil, copy_error
        end
        copied[key] = mutable
    end
    visiting[value] = nil
    return copied
end

local function lifecycle_candidate(document)
    local canonical = document_states[document]
    if not canonical then
        return nil, failure(
            "InvalidContextDocument",
            "Context lifecycle mutation requires a canonical document"
        )
    end
    local facts = {}
    for index, item in ipairs(canonical.events) do
        facts[index] = {
            seq = item.seq,
            type = item.type,
            at = item.at,
            turn_id = item.turn_id,
            fields = item.fields,
        }
    end
    local candidate, copy_error = mutable_copy({
        schema_version = SCHEMA_VERSION,
        generation = canonical.generation,
        header = canonical.header,
        session = canonical.session,
        facts = facts,
        model_view = canonical.model_view,
    })
    if not candidate then return nil, copy_error end
    return candidate, canonical
end

local LIFECYCLE_FIELDS = {
    rename = {
        new_name = true,
        manual = true,
        old_logical_path = true,
        new_logical_path = true,
    },
    rebind = {
        old_logical_path = true,
        new_logical_path = true,
        old_root_identity = true,
        new_root_identity = true,
    },
    import = {
        source_schema = true,
        model_mappings = true,
        permission_mappings = true,
        decision = true,
        notes = true,
    },
    repair = {
        error_id = true,
        summary = true,
        cause_id = true,
    },
    set_auto_rename_disabled = {
        value = true,
        old_value_digest = true,
        new_value_digest = true,
        effective_at = true,
        naming_waterline = true,
    },
    resolve_operation = {
        operation_id = true,
        status = true,
        evidence = true,
        error_id = true,
    },
}

local function lifecycle_event(candidate, mutation)
    local kind = mutation.kind
    if kind == "rename" then
        if type(mutation.manual) ~= "boolean" then
            return nil, failure("InvalidLifecycleMutation", "rename manual must be boolean")
        end
        if mutation.manual then
            candidate.header.auto_rename_disabled = true
        elseif candidate.header.auto_rename_disabled == true then
            return nil, failure(
                "AutoRenameDisabled",
                "automatic rename is disabled for this Context"
            )
        end
        local old_name = candidate.header.name
        candidate.header.name = mutation.new_name
        return "rename", {
            oldName = old_name,
            newName = mutation.new_name,
            manual = tostring(mutation.manual),
            autoRenameDisabled = tostring(candidate.header.auto_rename_disabled == true),
            oldLogicalPath = mutation.old_logical_path,
            newLogicalPath = mutation.new_logical_path,
        }
    end
    if kind == "rebind" then
        return "rebind", {
            oldLogicalPath = mutation.old_logical_path,
            newLogicalPath = mutation.new_logical_path,
            oldRootIdentity = mutation.old_root_identity,
            newRootIdentity = mutation.new_root_identity,
        }
    end
    if kind == "import" then
        local fields = {
            sourceSchema = mutation.source_schema,
            modelMappings = mutation.model_mappings,
            permissionMappings = mutation.permission_mappings,
            decision = mutation.decision,
        }
        if mutation.notes ~= nil then fields.notes = mutation.notes end
        return "import_mapping", fields
    end
    if kind == "repair" then
        local fields = { errorId = mutation.error_id, summary = mutation.summary }
        if mutation.cause_id ~= nil then fields.causeId = mutation.cause_id end
        return "warning", fields
    end
    if kind == "set_auto_rename_disabled" then
        if type(mutation.value) ~= "boolean" then
            return nil, failure(
                "InvalidLifecycleMutation",
                "AutoRenameDisabled value must be boolean"
            )
        end
        candidate.header.auto_rename_disabled = mutation.value
        if mutation.naming_waterline ~= nil then
            if not valid_integer(mutation.naming_waterline, 0) then
                return nil, failure(
                    "InvalidLifecycleMutation",
                    "naming waterline must be a non-negative integer"
                )
            end
            candidate.header.naming_waterline = mutation.naming_waterline
            if not mutation.value then
                candidate.header.auto_name_baseline = mutation.naming_waterline
            end
        end
        local fields = {
            name = "AutoRenameDisabled",
            oldValueDigest = mutation.old_value_digest,
            newValueDigest = mutation.new_value_digest,
        }
        if mutation.effective_at ~= nil then fields.effectiveAt = mutation.effective_at end
        return "session_override", fields
    end
    if kind == "resolve_operation" then
        local fields = {
            operationId = mutation.operation_id,
            status = mutation.status,
            evidence = mutation.evidence,
        }
        if mutation.error_id ~= nil then fields.errorId = mutation.error_id end
        return "operation_result", fields
    end
    return nil, failure("InvalidLifecycleMutation", "Context lifecycle kind is unknown")
end

local function build_lifecycle_document(document, mutation, admitted)
    if type(mutation) ~= "table" or type(mutation.kind) ~= "string" then
        return nil, failure("InvalidLifecycleMutation", "typed lifecycle mutation is required")
    end
    local kind_fields = LIFECYCLE_FIELDS[mutation.kind]
    if not kind_fields then
        return nil, failure("InvalidLifecycleMutation", "Context lifecycle kind is unknown")
    end
    local allowed = { kind = true, updated_at = true, view_manifest_digest = true }
    for name in pairs(kind_fields) do allowed[name] = true end
    for key in pairs(mutation) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure(
                "InvalidLifecycleMutation",
                "Context lifecycle mutation contains an unknown field",
                nil,
                nil,
                tostring(key)
            )
        end
    end
    local updated_at, time_error = canonical_time(
        mutation.updated_at,
        "/Lifecycle/UpdatedAt"
    )
    if not updated_at then return nil, time_error end
    local manifest_digest, digest_error = attribute_text(
        mutation.view_manifest_digest,
        admitted.maximum_field_bytes,
        "/Lifecycle/ViewManifestDigest",
        false
    )
    if not manifest_digest then return nil, digest_error end

    local candidate, canonical_or_error = lifecycle_candidate(document)
    if not candidate then return nil, canonical_or_error end
    local canonical = canonical_or_error
    if updated_at <= canonical.header.updated_at then
        return nil, failure(
            "ContextGeneration",
            "lifecycle mutation must advance UpdatedAt"
        )
    end
    local event_type, fields_or_error = lifecycle_event(candidate, mutation)
    if not event_type then return nil, fields_or_error end

    candidate.generation = canonical.generation + 1
    candidate.header.updated_at = updated_at
    candidate.facts[#candidate.facts + 1] = {
        seq = #candidate.facts + 1,
        type = event_type,
        at = updated_at,
        fields = fields_or_error,
    }

    -- A lifecycle mutation publishes a new complete model-view generation.
    -- Recording the publication event prevents an older manifest event from
    -- making the rebuilt document stale after import or compaction history.
    candidate.facts[#candidate.facts + 1] = {
        seq = #candidate.facts + 1,
        type = "model_view_published",
        at = updated_at,
        fields = {
            manifestDigest = manifest_digest,
            firstEventSeq = #candidate.facts == 0 and "0" or "1",
            lastEventSeq = tostring(#candidate.facts + 1),
            replacesManifestDigest = canonical.model_view.active_manifest.digest,
        },
    }
    candidate.model_view.active_manifest = {
        digest = manifest_digest,
        first_event_seq = #candidate.facts == 0 and 0 or 1,
        last_event_seq = #candidate.facts,
    }
    return normalize_document(candidate, admitted)
end

---Creates the internal v0.1 Context document service.
-- The XML codec and SHA-256 service are injected from the release loader. All
-- dimensions are mandatory release limits; callers cannot disable them.
-- @param options table Bounded XML/safety services and Context hard limits.
-- @return table|nil service Immutable Context schema service.
-- @return table|nil err Structured dependency or limit failure.
function M.new(options)
    local admitted, options_error = validate_dependency(options)
    if not admitted then return nil, options_error end
    local service = {}

    ---Validates and freezes one semantic Context candidate.
    function service.build(candidate)
        return normalize_document(candidate, admitted)
    end

    ---Builds one full lifecycle generation without rewriting durable Facts.
    -- Supported kinds are rename, rebind, import, repair,
    -- set_auto_rename_disabled, and resolve_operation.
    function service.lifecycle_document(document, mutation)
        return build_lifecycle_document(document, mutation, admitted)
    end

    ---Reads one untrusted internal Context XML source through the bounded SAX codec.
    function service.read(source)
        if type(source) ~= "string" and type(source) ~= "table" then
            return nil, failure(
                "InvalidContextInput",
                "Context reader requires bytes or a dense byte chunk array"
            )
        end
        local candidate, stats_or_error = read_candidate(
            admitted.codec,
            admitted.safety,
            source,
            admitted
        )
        if not candidate then return nil, stats_or_error end
        local document, document_error = normalize_document(candidate, admitted)
        if not document then return nil, document_error end
        return document, stats_or_error
    end

    ---Reads one untrusted Context from a bounded pull source without buffering XML bytes.
    -- The callback returns `true, {bytes=string, eof=boolean}` or
    -- `false, structured_error` on every invocation.
    function service.read_stream(next_chunk)
        if type(next_chunk) ~= "function" then
            return nil, failure("InvalidContextInput", "Context stream callback is required")
        end
        local candidate, stats_or_error = read_candidate(
            admitted.codec,
            admitted.safety,
            next_chunk,
            admitted
        )
        if not candidate then return nil, stats_or_error end
        local document, document_error = normalize_document(candidate, admitted)
        if not document then return nil, document_error end
        return document, stats_or_error
    end

    ---Streams deterministic internal XML for a document with a current ModelView.
    function service.write(document, sink)
        local canonical = document_states[document]
        if not canonical then
            return nil, failure(
                "InvalidContextDocument",
                "Context writer requires a document from this module"
            )
        end
        if canonical.recovery.model_view_status ~= "current" then
            return nil, failure(
                "StaleModelView",
                "stale ModelView must be rebuilt before Context publication"
            )
        end
        return write_document(admitted.codec, canonical, sink)
    end

    ---Returns deterministic internal XML bytes without exposing a filesystem path.
    function service.encode(document)
        local parts = {}
        local stats, encode_error = service.write(document, function(bytes)
            parts[#parts + 1] = bytes
            return true
        end)
        if not stats then return nil, encode_error end
        return table.concat(parts), stats
    end

    ---Projects a non-API Markdown transfer view from canonical Facts.
    function service.export(document, sink)
        local canonical = document_states[document]
        if not canonical then
            return nil, failure(
                "InvalidContextDocument",
                "Context export requires a document from this module"
            )
        end
        return export_document(canonical, admitted, sink)
    end

    ---Returns the fixed required/optional payload names for one event type.
    function service.event_schema(event_type)
        local definition = EVENT_BY_ID[event_type]
        if not definition then
            return nil, failure("UnknownContextEvent", "Context event type is unknown")
        end
        return assert(freeze({
            id = definition.id,
            required = copy_array(definition.required),
            optional = copy_array(definition.optional),
        }, "Context event schema"))
    end

    local event_types = {}
    for index, definition in ipairs(EVENT_DEFINITIONS) do event_types[index] = definition.id end
    service.schema_version = SCHEMA_VERSION
    service.event_types = assert(freeze(event_types, "Context event types"))
    service.limits = readonly({
        maximum_name_bytes = admitted.maximum_name_bytes,
        maximum_identifier_bytes = admitted.maximum_identifier_bytes,
        maximum_field_name_bytes = admitted.maximum_field_name_bytes,
        maximum_field_bytes = admitted.maximum_field_bytes,
        maximum_events = admitted.maximum_events,
        maximum_compaction_records = admitted.maximum_compaction_records,
        maximum_export_bytes = admitted.maximum_export_bytes,
    }, "Context limits")

    local exposed = readonly(service, "Context service")
    schema_service_states[exposed] = admitted
    return exposed
end

---Creates the next canonical generation for one durable operation barrier.
-- `begin` appends an operation_intent. `finish` appends the matching
-- operation_result and tool_result in the same generation, so a result cannot
-- become visible to the next model request without closing both relations.
-- The caller still publishes the returned full document through new_store.
local function build_operation_document(document, mutation, admitted)
    if type(mutation) ~= "table" or type(mutation.kind) ~= "string" then
        return nil, failure("InvalidOperationMutation", "typed operation mutation is required")
    end
    local common = {
        kind = true,
        updated_at = true,
        view_manifest_digest = true,
    }
    local begin_fields = {
        operation_id = true,
        tool_call_id = true,
        operation_kind = true,
        target_identity = true,
        expected_digest = true,
    }
    local finish_fields = {
        operation_id = true,
        tool_call_id = true,
        status = true,
        evidence = true,
        error_id = true,
        tool_status = true,
        tool_body = true,
        tool_truncated = true,
        tool_raw_bytes = true,
        tool_digest = true,
        tool_error_id = true,
    }
    local fields = mutation.kind == "begin" and begin_fields
        or mutation.kind == "finish" and finish_fields
        or nil
    if not fields then
        return nil, failure("InvalidOperationMutation", "operation mutation kind is unknown")
    end
    local allowed = {}
    for key in pairs(common) do allowed[key] = true end
    for key in pairs(fields) do allowed[key] = true end
    for key in pairs(mutation) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure(
                "InvalidOperationMutation",
                "operation mutation contains an unknown field"
            )
        end
    end
    local updated_at, time_error = canonical_time(
        mutation.updated_at,
        "/Operation/UpdatedAt"
    )
    if not updated_at then return nil, time_error end
    local manifest_digest, digest_error = attribute_text(
        mutation.view_manifest_digest,
        admitted.maximum_field_bytes,
        "/Operation/ViewManifestDigest",
        false
    )
    if not manifest_digest then return nil, digest_error end

    local candidate, canonical_or_error = lifecycle_candidate(document)
    if not candidate then return nil, canonical_or_error end
    local canonical = canonical_or_error
    if updated_at <= canonical.header.updated_at then
        return nil, failure(
            "ContextGeneration",
            "operation mutation must advance UpdatedAt"
        )
    end
    local events = {}
    if mutation.kind == "begin" then
        events[1] = {
            type = "operation_intent",
            fields = {
                operationId = mutation.operation_id,
                toolCallId = mutation.tool_call_id,
                kind = mutation.operation_kind,
                targetIdentity = mutation.target_identity,
                expectedDigest = mutation.expected_digest,
            },
        }
    else
        if not RESULT_STATUSES[mutation.status]
            or not RESULT_STATUSES[mutation.tool_status]
            or mutation.status ~= mutation.tool_status
            or type(mutation.tool_truncated) ~= "boolean"
            or not valid_integer(mutation.tool_raw_bytes, 0)
            or type(mutation.tool_body) ~= "string"
            or mutation.tool_raw_bytes ~= #mutation.tool_body
        then
            return nil, failure(
                "InvalidOperationMutation",
                "operation result status or tool metadata is invalid"
            )
        end
        local operation_fields = {
            operationId = mutation.operation_id,
            status = mutation.status,
            evidence = mutation.evidence,
        }
        if mutation.error_id ~= nil then operation_fields.errorId = mutation.error_id end
        local tool_fields = {
            toolCallId = mutation.tool_call_id,
            status = mutation.tool_status,
            body = mutation.tool_body,
            truncated = tostring(mutation.tool_truncated),
            rawBytes = tostring(mutation.tool_raw_bytes),
        }
        if mutation.tool_digest ~= nil then tool_fields.digest = mutation.tool_digest end
        if mutation.tool_error_id ~= nil then tool_fields.errorId = mutation.tool_error_id end
        events[1] = { type = "operation_result", fields = operation_fields }
        events[2] = { type = "tool_result", fields = tool_fields }

        local bound_tool_call
        for _, item in ipairs(canonical.events) do
            if item.type == "operation_intent"
                and item.fields.operationId == mutation.operation_id
            then
                bound_tool_call = item.fields.toolCallId
                break
            end
        end
        if bound_tool_call ~= mutation.tool_call_id then
            return nil, failure(
                "ContextRelation",
                "operation result does not bind its original tool call"
            )
        end
    end

    candidate.generation = canonical.generation + 1
    candidate.header.updated_at = updated_at
    for _, item in ipairs(events) do
        candidate.facts[#candidate.facts + 1] = {
            seq = #candidate.facts + 1,
            type = item.type,
            at = updated_at,
            fields = item.fields,
        }
    end
    candidate.facts[#candidate.facts + 1] = {
        seq = #candidate.facts + 1,
        type = "model_view_published",
        at = updated_at,
        fields = {
            manifestDigest = manifest_digest,
            firstEventSeq = #candidate.facts == 0 and "0" or "1",
            lastEventSeq = tostring(#candidate.facts + 1),
            replacesManifestDigest = canonical.model_view.active_manifest.digest,
        },
    }
    candidate.model_view.active_manifest = {
        digest = manifest_digest,
        first_event_seq = #candidate.facts == 0 and 0 or 1,
        last_event_seq = #candidate.facts,
    }
    return normalize_document(candidate, admitted)
end

---Builds a full canonical operation generation for a schema service.
function M.operation_document(schema, document, mutation)
    local admitted = schema_service_states[schema]
    if not admitted then
        return nil, failure(
            "InvalidContextDocument",
            "operation mutation requires a schema service from this module"
        )
    end
    return build_operation_document(document, mutation, admitted)
end

---Creates a current-process operation barrier over a durable Context journal.
-- The journal must acknowledge the exact binding digest supplied with each
-- commit.  A result-commit ambiguity permanently blocks new effects in this
-- service instance; recovery data is audit-only and is never replayed.
function M.new_operation_service(ports, options)
    if type(ports) ~= "table"
        or type(ports.safety) ~= "table"
        or type(ports.safety.binding_digest) ~= "function"
        or type(ports.safety.freeze) ~= "function"
        or type(ports.journal) ~= "table"
        or type(ports.journal.commit_intent) ~= "function"
        or type(ports.journal.commit_result) ~= "function"
    then
        return nil, failure(
            "InvalidOperationPorts",
            "safety and durable Context journal ports are required"
        )
    end
    for key in pairs(ports) do
        if key ~= "safety" and key ~= "journal" then
            return nil, failure("InvalidOperationPorts", "operation ports are ambiguous")
        end
    end
    if type(options) ~= "table" then
        return nil, failure("InvalidOperationOptions", "operation limits are required")
    end
    local option_fields = {
        maximum_identifier_bytes = true,
        maximum_evidence_bytes = true,
        unresolved_operation_ids = true,
    }
    for key in pairs(options) do
        if type(key) ~= "string" or not option_fields[key] then
            return nil, failure("InvalidOperationOptions", "operation options are ambiguous")
        end
    end
    if not valid_integer(options.maximum_identifier_bytes, 1)
        or not valid_integer(options.maximum_evidence_bytes, 1)
    then
        return nil, failure("InvalidOperationOptions", "operation limits must be positive")
    end

    local function valid_string(value, maximum, empty)
        return type(value) == "string"
            and (empty or value ~= "")
            and #value <= maximum
            and not value:find("\0", 1, true)
            and text.validate_utf8(value) == true
    end
    local function valid_id(value)
        return valid_string(value, options.maximum_identifier_bytes, false)
            and value:match("^[A-Za-z0-9][A-Za-z0-9._:-]*$") ~= nil
    end
    local unresolved = options.unresolved_operation_ids or {}
    local unresolved_count = dense_count(unresolved)
    if unresolved_count == nil then
        return nil, failure("InvalidOperationOptions", "unresolved operations must be an array")
    end
    local seen = {}
    local recovery_ids = {}
    for index, operation_id in ipairs(unresolved) do
        if not valid_id(operation_id) or seen[operation_id] then
            return nil, failure("InvalidOperationOptions", "unresolved operation identity is invalid")
        end
        seen[operation_id] = true
        recovery_ids[index] = operation_id
    end

    local operation_states = setmetatable({}, { __mode = "k" })
    local active
    local blocked = unresolved_count > 0
    local service = {}

    local function journal_commit(method, record, digest_value)
        local called, ok, receipt = pcall(
            ports.journal[method],
            record,
            digest_value
        )
        if not called then
            return nil, failure(
                "OperationJournalFailure",
                "durable Context journal raised an exception"
            )
        end
        if ok ~= true or receipt ~= digest_value then
            return nil, type(receipt) == "table" and receipt or failure(
                "OperationJournalContract",
                "durable Context journal did not acknowledge the exact binding"
            )
        end
        return true
    end

    function service.begin(intent)
        if blocked then
            return nil, failure(
                "OperationBarrierBlocked",
                "an unresolved durable operation blocks new side effects"
            )
        end
        if active then
            return nil, failure("OperationBusy", "one durable operation is already active")
        end
        local allowed = {
            operation_id = true,
            tool_call_id = true,
            kind = true,
            target_identity = true,
            expected_digest = true,
            call_digest = true,
        }
        if type(intent) ~= "table" then
            return nil, failure("InvalidOperationIntent", "operation intent is required")
        end
        for key in pairs(intent) do
            if type(key) ~= "string" or not allowed[key] then
                return nil, failure("InvalidOperationIntent", "operation intent is ambiguous")
            end
        end
        if not valid_id(intent.operation_id)
            or not valid_id(intent.tool_call_id)
            or not valid_string(intent.kind, options.maximum_identifier_bytes, false)
            or not valid_string(intent.target_identity, options.maximum_evidence_bytes, false)
            or not valid_string(intent.expected_digest, options.maximum_evidence_bytes, false)
            or not valid_string(intent.call_digest, options.maximum_evidence_bytes, false)
            or seen[intent.operation_id]
        then
            return nil, failure("InvalidOperationIntent", "operation intent fields are invalid")
        end
        local digest_value, digest_error = ports.safety.binding_digest(
            "yaca-operation-intent-v1",
            {
                { name = "operation_id", value = intent.operation_id },
                { name = "tool_call_id", value = intent.tool_call_id },
                { name = "kind", value = intent.kind },
                { name = "target_identity", value = intent.target_identity },
                { name = "expected_digest", value = intent.expected_digest },
                { name = "call_digest", value = intent.call_digest },
            }
        )
        if not digest_value then return nil, digest_error end
        local record, freeze_error = ports.safety.freeze({
            operation_id = intent.operation_id,
            tool_call_id = intent.tool_call_id,
            kind = intent.kind,
            target_identity = intent.target_identity,
            expected_digest = intent.expected_digest,
            call_digest = intent.call_digest,
            intent_digest = digest_value,
        }, "durable operation intent")
        if not record then return nil, freeze_error end
        seen[intent.operation_id] = true
        local committed, commit_error = journal_commit("commit_intent", record, digest_value)
        if not committed then
            if type(commit_error) ~= "table"
                or type(commit_error.code) ~= "string"
                or commit_error.code:find("Unknown", 1, true)
                or commit_error.code == "OperationJournalContract"
            then
                blocked = true
            end
            return nil, commit_error
        end
        local handle = readonly({}, "operation handle")
        local state = {
            handle = handle,
            record = record,
            digest = digest_value,
            finished = false,
        }
        operation_states[handle] = state
        active = state
        return handle, digest_value
    end

    function service.finish(handle, result)
        local state = operation_states[handle]
        if not state or state ~= active or state.finished then
            return nil, failure("InvalidOperationHandle", "operation handle is stale or foreign")
        end
        local allowed = {
            status = true,
            evidence = true,
            error_id = true,
            tool_status = true,
            tool_body = true,
            tool_truncated = true,
            tool_raw_bytes = true,
            tool_digest = true,
            tool_error_id = true,
        }
        if type(result) ~= "table" then
            return nil, failure("InvalidOperationResult", "operation result is required")
        end
        for key in pairs(result) do
            if type(key) ~= "string" or not allowed[key] then
                return nil, failure("InvalidOperationResult", "operation result is ambiguous")
            end
        end
        if not RESULT_STATUSES[result.status]
            or not RESULT_STATUSES[result.tool_status]
            or not valid_string(result.evidence, options.maximum_evidence_bytes, false)
            or not valid_string(result.tool_body, options.maximum_evidence_bytes, true)
            or type(result.tool_truncated) ~= "boolean"
            or not valid_integer(result.tool_raw_bytes, 0)
            or result.tool_raw_bytes ~= #result.tool_body
            or (result.error_id ~= nil and not valid_id(result.error_id))
            or (result.tool_error_id ~= nil and not valid_id(result.tool_error_id))
            or (result.tool_digest ~= nil
                and not valid_string(result.tool_digest, options.maximum_evidence_bytes, false))
        then
            return nil, failure("InvalidOperationResult", "operation result fields are invalid")
        end
        local digest_value, digest_error = ports.safety.binding_digest(
            "yaca-operation-result-v1",
            {
                { name = "intent_digest", value = state.digest },
                { name = "status", value = result.status },
                { name = "evidence", value = result.evidence },
                { name = "error_id", value = result.error_id or "" },
                { name = "tool_status", value = result.tool_status },
                { name = "tool_body", value = result.tool_body },
                { name = "tool_truncated", value = tostring(result.tool_truncated) },
                { name = "tool_raw_bytes", value = tostring(result.tool_raw_bytes) },
                { name = "tool_digest", value = result.tool_digest or "" },
                { name = "tool_error_id", value = result.tool_error_id or "" },
            }
        )
        if not digest_value then return nil, digest_error end
        local record, freeze_error = ports.safety.freeze({
            operation_id = state.record.operation_id,
            tool_call_id = state.record.tool_call_id,
            status = result.status,
            evidence = result.evidence,
            error_id = result.error_id or false,
            tool_status = result.tool_status,
            tool_body = result.tool_body,
            tool_truncated = result.tool_truncated,
            tool_raw_bytes = result.tool_raw_bytes,
            tool_digest = result.tool_digest or false,
            tool_error_id = result.tool_error_id or false,
            intent_digest = state.digest,
            result_digest = digest_value,
        }, "durable operation result")
        if not record then return nil, freeze_error end
        state.finished = true
        local committed, commit_error = journal_commit("commit_result", record, digest_value)
        if not committed then
            blocked = true
            return nil, failure(
                "OperationResultDurabilityUnknown",
                "operation result did not cross the durable Context barrier",
                type(commit_error) == "table" and commit_error.code or nil
            )
        end
        active = nil
        return digest_value
    end

    function service.status()
        return assert(ports.safety.freeze({
            blocked = blocked,
            active_operation_id = active and active.record.operation_id or false,
            unresolved_operation_ids = recovery_ids,
            auto_replay = false,
        }, "operation barrier status"))
    end

    service.capabilities = assert(ports.safety.freeze({
        durable_intent_before_effect = true,
        durable_result_before_next_effect = true,
        serial = true,
        auto_replay = false,
        backup = false,
        undo = false,
        rollback = false,
    }, "operation barrier capabilities"))
    return readonly(service, "operation service")
end

local STORE_FILESYSTEM_METHODS = {
    "open_read",
    "create_new",
    "stat_identity",
    "stream_read",
    "stream_write",
    "flush_file",
    "flush_directory",
    "replace",
    "rename_no_replace",
    "delete_verified",
    "close",
    "acquire_lease",
    "release_lease",
}

local function valid_absolute_path(value)
    if type(value) ~= "string" or value == "" or value:find("\0", 1, true) then
        return false
    end
    local normalized = value:gsub("\\", "/")
    local absolute = normalized:sub(1, 1) == "/"
        or normalized:match("^[A-Za-z]:/") ~= nil
        or normalized:match("^//[^/]+/[^/]+") ~= nil
    if not absolute then return false end
    for segment in normalized:gmatch("[^/]+") do
        if segment == "." or segment == ".." then return false end
    end
    return true
end

local function directory_of(path)
    if type(path) ~= "string" then return nil end
    local separator
    for index = #path, 1, -1 do
        local byte = path:byte(index)
        if byte == 0x2F or byte == 0x5C then
            separator = index
            break
        end
    end
    if not separator then return nil end
    if separator == 1 then return path:sub(1, 1) end
    if separator == 3 and path:sub(2, 2) == ":" then return path:sub(1, 3) end
    return path:sub(1, separator - 1)
end

local function basename_of(path)
    if type(path) ~= "string" then return nil end
    local normalized = path:gsub("\\", "/")
    return normalized:match("([^/]+)$")
end

local function same_directory(left, right)
    local left_directory, right_directory = directory_of(left), directory_of(right)
    if not left_directory or not right_directory then return false end
    return left_directory:gsub("\\", "/") == right_directory:gsub("\\", "/")
end

local function identity_equal(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then return false end
    for _, key in ipairs({ "kind", "volume", "object", "size", "modified" }) do
        if left[key] ~= right[key] then return false end
    end
    return true
end

local function deep_equal(left, right, visited)
    if left == right then return true end
    if type(left) ~= type(right) or type(left) ~= "table" then return false end
    visited = visited or {}
    visited[left] = visited[left] or {}
    if visited[left][right] then return true end
    visited[left][right] = true
    for key, value in pairs(left) do
        if not deep_equal(value, right[key], visited) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function validate_target_credential(credential, path)
    if credential == nil then return true end
    if type(credential) ~= "table" then
        return nil, failure("InvalidTargetCredential", "target credential must be a table")
    end
    local allowed = {
        physical_path = true,
        logical_path = true,
        observed_stat = true,
        canonical_name = true,
        created_at = true,
        updated_at = true,
        header_state = true,
    }
    for key in pairs(credential) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure(
                "InvalidTargetCredential",
                "target credential contains an unknown field"
            )
        end
    end
    if credential.physical_path ~= path
        or type(credential.logical_path) ~= "string"
        or type(credential.observed_stat) ~= "table"
    then
        return nil, failure(
            "InvalidTargetCredential",
            "target credential does not bind the requested path"
        )
    end
    local identity = credential.observed_stat
    if identity.kind ~= "file"
        or type(identity.volume) ~= "string"
        or type(identity.object) ~= "string"
        or not valid_integer(identity.size, 0)
        or type(identity.modified) ~= "string"
    then
        return nil, failure(
            "InvalidTargetCredential",
            "target credential has an incomplete file identity"
        )
    end
    for _, name in ipairs({ "canonical_name", "created_at", "updated_at" }) do
        if credential[name] ~= nil and type(credential[name]) ~= "string" then
            return nil, failure(
                "InvalidTargetCredential",
                "target credential header fields are malformed"
            )
        end
    end
    return true
end

local function credential_matches(credential, path, identity, document)
    if credential == nil then return true end
    if credential.physical_path ~= path
        or not identity_equal(credential.observed_stat, identity)
    then
        return false
    end
    if document then
        if credential.canonical_name ~= nil
            and credential.canonical_name ~= document.header.name
        then
            return false
        end
        if credential.created_at ~= nil
            and credential.created_at ~= document.header.created_at
        then
            return false
        end
        if credential.updated_at ~= nil
            and credential.updated_at ~= document.header.updated_at
        then
            return false
        end
    end
    return true
end

local function validate_store_options(options, schema_state)
    if type(options) ~= "table" then
        return nil, failure("InvalidContextStoreOptions", "Context store limits are required")
    end
    local allowed = {
        maximum_context_bytes = true,
        maximum_lock_hostname_bytes = true,
        maximum_temp_nonce_bytes = true,
        context_permissions = true,
        lock_permissions = true,
    }
    for key in pairs(options) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure(
                "InvalidContextStoreOptions",
                "Context store options contain an unknown field"
            )
        end
    end
    for _, name in ipairs({
        "maximum_context_bytes",
        "maximum_lock_hostname_bytes",
        "maximum_temp_nonce_bytes",
    }) do
        if not valid_integer(options[name], 1) then
            return nil, failure("InvalidContextStoreOptions", name .. " must be positive")
        end
    end
    for _, name in ipairs({ "context_permissions", "lock_permissions" }) do
        if not valid_integer(options[name], 0) or options[name] > 511 then
            return nil, failure("InvalidContextStoreOptions", name .. " is invalid")
        end
    end
    if options.maximum_context_bytes > schema_state.codec.limits.maximum_bytes then
        return nil, failure(
            "InvalidContextStoreOptions",
            "Context byte limit exceeds the XML codec limit"
        )
    end
    return {
        maximum_context_bytes = options.maximum_context_bytes,
        maximum_lock_hostname_bytes = options.maximum_lock_hostname_bytes,
        maximum_temp_nonce_bytes = options.maximum_temp_nonce_bytes,
        context_permissions = options.context_permissions,
        lock_permissions = options.lock_permissions,
    }
end

local function validate_store_filesystem(filesystem)
    if type(filesystem) ~= "table" then
        return nil, failure("InvalidContextStorePort", "filesystem service is required")
    end
    local snapshot = {}
    for _, name in ipairs(STORE_FILESYSTEM_METHODS) do
        if type(filesystem[name]) ~= "function" then
            return nil, failure(
                "InvalidContextStorePort",
                "filesystem service omits " .. name
            )
        end
        snapshot[name] = filesystem[name]
    end
    local capabilities = filesystem.capabilities
    if type(capabilities) ~= "table"
        or not valid_integer(capabilities.maximum_chunk_bytes, 1)
        or not valid_integer(capabilities.maximum_lease_bytes, 1)
    then
        return nil, failure(
            "InvalidContextStorePort",
            "filesystem capabilities are incomplete"
        )
    end
    snapshot.capabilities = {
        maximum_chunk_bytes = capabilities.maximum_chunk_bytes,
        maximum_lease_bytes = capabilities.maximum_lease_bytes,
        target_qualified = capabilities.target_qualified == true,
        atomic_replace_candidate = capabilities.atomic_replace_candidate == true,
        rename_no_replace_candidate = capabilities.rename_no_replace_candidate == true,
        exclusive_create_lease_candidate = capabilities.exclusive_create_lease_candidate == true,
    }
    return snapshot
end

local function validate_context_target(path)
    if not valid_absolute_path(path) then
        return nil, failure("InvalidContextPath", "Context target must be absolute")
    end
    local basename = basename_of(path)
    if not basename or #basename <= 4 or basename:sub(-4) ~= ".xml" then
        return nil, failure("InvalidContextPath", "Context target must end in exact .xml")
    end
    local name = basename:sub(1, -5)
    if name == "" then
        return nil, failure("InvalidContextPath", "Context target name must not be empty")
    end
    return { basename = basename, name = name, directory = assert(directory_of(path)) }
end

local function encode_lock_metadata(metadata, limits)
    if type(metadata) ~= "table" then
        return nil, failure("InvalidWriterMetadata", "writer metadata is required")
    end
    local allowed = { pid = true, started_at = true, hostname = true }
    for key in pairs(metadata) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure("InvalidWriterMetadata", "writer metadata has an unknown field")
        end
    end
    if not valid_integer(metadata.pid, 1) then
        return nil, failure("InvalidWriterMetadata", "writer pid must be positive")
    end
    local started_at, time_error = canonical_time(metadata.started_at, "/Writer/startedAt")
    if not started_at then return nil, time_error end
    if metadata.hostname ~= nil then
        local hostname, hostname_error = strict_text(
            metadata.hostname,
            limits.maximum_lock_hostname_bytes,
            "/Writer/hostname",
            false
        )
        if not hostname then return nil, hostname_error end
        if hostname:find("[=\r\n]") then
            return nil, failure(
                "InvalidWriterMetadata",
                "writer hostname is unsafe for lock metadata"
            )
        end
    end
    local lines = {
        "version=1",
        "pid=" .. tostring(metadata.pid),
        "startedAt=" .. started_at,
    }
    if metadata.hostname ~= nil then lines[#lines + 1] = "hostname=" .. metadata.hostname end
    return table.concat(lines, "\n") .. "\n"
end

local function validate_temp_path(target_path, temporary_path, limits)
    if not valid_absolute_path(temporary_path)
        or not same_directory(target_path, temporary_path)
    then
        return nil, failure(
            "InvalidContextPath",
            "Context temporary must be a same-directory absolute path"
        )
    end
    local prefix = target_path .. ".yaca-tmp-"
    if temporary_path:sub(1, #prefix) ~= prefix then
        return nil, failure("InvalidContextPath", "Context temporary name is not canonical")
    end
    local nonce = temporary_path:sub(#prefix + 1)
    if nonce == ""
        or #nonce > limits.maximum_temp_nonce_bytes
        or nonce:match("^[A-Za-z0-9]+$") == nil
    then
        return nil, failure("InvalidContextPath", "Context temporary nonce is invalid")
    end
    return temporary_path
end

local function target_absent(filesystem, path)
    local opened, handle_or_error = filesystem.open_read(path)
    if opened then
        filesystem.close(handle_or_error)
        return false, failure("DestinationExists", "Context target already exists")
    end
    if type(handle_or_error) == "table" and handle_or_error.code == "NotFound" then
        return true
    end
    return nil, handle_or_error
end

local function cleanup_file(filesystem, path, identity)
    local stated, observed = filesystem.stat_identity(path)
    if stated then
        if identity == nil
            or (identity.kind == observed.kind
                and identity.volume == observed.volume
                and identity.object == observed.object)
        then
            identity = observed
        end
    end
    if not identity then return true end
    local deleted, delete_error = filesystem.delete_verified(path, identity)
    if not deleted then return nil, delete_error end
    local flushed, flush_error = filesystem.flush_directory(assert(directory_of(path)))
    if not flushed then return nil, flush_error end
    return true
end

local function stable_read(schema, filesystem, path, limits)
    local opened, handle_or_error = filesystem.open_read(path)
    if not opened then return nil, handle_or_error end
    local handle = handle_or_error
    local stated, initial_or_error = filesystem.stat_identity(handle)
    if not stated then
        filesystem.close(handle)
        return nil, initial_or_error
    end
    if initial_or_error.kind ~= "file" then
        filesystem.close(handle)
        return nil, failure("ContextUnavailable", "Context target is not a regular file")
    end
    if initial_or_error.size > limits.maximum_context_bytes then
        filesystem.close(handle)
        return nil, failure("ContextLimit", "Context file exceeds its byte limit")
    end
    local total = 0
    local document, stats_or_error = schema.read_stream(function()
        local read, chunk_or_error = filesystem.stream_read(
            handle,
            filesystem.capabilities.maximum_chunk_bytes
        )
        if not read then return false, chunk_or_error end
        total = total + #chunk_or_error.bytes
        if total > limits.maximum_context_bytes then
            return false, failure("ContextLimit", "Context stream exceeds its byte limit")
        end
        return true, chunk_or_error
    end)
    local restated, final_or_error = filesystem.stat_identity(handle)
    local closed, close_error = filesystem.close(handle)
    if not document then return nil, stats_or_error end
    if not restated then return nil, final_or_error end
    if not closed then return nil, close_error end
    if not identity_equal(initial_or_error, final_or_error) then
        return nil, failure("TargetChanged", "Context changed while it was read")
    end
    return document, initial_or_error, stats_or_error
end

local function write_new_document(schema, filesystem, path, document, limits)
    local created, handle_or_error = filesystem.create_new(path, limits.context_permissions)
    if not created then return nil, handle_or_error end
    local handle = handle_or_error
    local write_failure
    local stats, write_error = schema.write(document, function(bytes)
        for offset = 1, #bytes, filesystem.capabilities.maximum_chunk_bytes do
            local chunk = bytes:sub(
                offset,
                offset + filesystem.capabilities.maximum_chunk_bytes - 1
            )
            local written, chunk_error = filesystem.stream_write(handle, chunk)
            if not written then
                write_failure = chunk_error
                return false, chunk_error.message
            end
        end
        return true
    end)
    if not stats then
        filesystem.close(handle)
        cleanup_file(filesystem, path)
        return nil, write_failure or write_error
    end
    if stats.bytes > limits.maximum_context_bytes then
        filesystem.close(handle)
        cleanup_file(filesystem, path)
        return nil, failure("ContextLimit", "Context publication exceeds its byte limit")
    end
    local flushed, flush_error = filesystem.flush_file(handle)
    if not flushed then
        filesystem.close(handle)
        cleanup_file(filesystem, path)
        return nil, flush_error
    end
    local stated, identity_or_error = filesystem.stat_identity(handle)
    if not stated then
        filesystem.close(handle)
        cleanup_file(filesystem, path)
        return nil, identity_or_error
    end
    local closed, close_error = filesystem.close(handle)
    if not closed then
        cleanup_file(filesystem, path, identity_or_error)
        return nil, close_error
    end
    return identity_or_error, stats
end

local function compare_document_bytes(schema, filesystem, path, document, expected_identity)
    local opened, handle_or_error = filesystem.open_read(path)
    if not opened then return nil, handle_or_error end
    local handle = handle_or_error
    local stated, initial_or_error = filesystem.stat_identity(handle)
    if not stated then
        filesystem.close(handle)
        return nil, initial_or_error
    end
    if expected_identity and not identity_equal(expected_identity, initial_or_error) then
        filesystem.close(handle)
        return nil, failure("ContextTemporaryMismatch", "Context file identity changed")
    end
    local buffer, eof, comparison_error = "", false, nil
    local function fill()
        if eof then return true end
        local read, chunk_or_error = filesystem.stream_read(
            handle,
            filesystem.capabilities.maximum_chunk_bytes
        )
        if not read then return nil, chunk_or_error end
        if #chunk_or_error.bytes == 0 and not chunk_or_error.eof then
            return nil, failure("ContextFilesystemContract", "Context read made no progress")
        end
        buffer = buffer .. chunk_or_error.bytes
        eof = chunk_or_error.eof
        return true
    end
    local stats, write_error = schema.write(document, function(expected)
        local offset = 1
        while offset <= #expected do
            if #buffer == 0 then
                local filled, fill_error = fill()
                if not filled then
                    comparison_error = fill_error
                    return false, fill_error.message
                end
                if #buffer == 0 and eof then
                    comparison_error = failure(
                        "ContextTemporaryMismatch",
                        "Context file is shorter than canonical bytes"
                    )
                    return false, comparison_error.message
                end
            end
            local count = math.min(#buffer, #expected - offset + 1)
            if buffer:sub(1, count) ~= expected:sub(offset, offset + count - 1) then
                comparison_error = failure(
                    "ContextTemporaryMismatch",
                    "Context file differs from canonical bytes"
                )
                return false, comparison_error.message
            end
            buffer = buffer:sub(count + 1)
            offset = offset + count
        end
        return true
    end)
    if stats and #buffer == 0 and not eof then
        local filled, fill_error = fill()
        if not filled then comparison_error = fill_error end
    end
    if stats and not comparison_error and (#buffer > 0 or not eof) then
        comparison_error = failure(
            "ContextTemporaryMismatch",
            "Context file is longer than canonical bytes"
        )
    end
    local restated, final_or_error = filesystem.stat_identity(handle)
    local closed, close_error = filesystem.close(handle)
    if not stats then return nil, comparison_error or write_error end
    if comparison_error then return nil, comparison_error end
    if not restated then return nil, final_or_error end
    if not closed then return nil, close_error end
    if not identity_equal(initial_or_error, final_or_error) then
        return nil, failure("ContextTemporaryMismatch", "Context file changed during validation")
    end
    return initial_or_error, stats
end

local function verify_document_path(schema, filesystem, path, document, expected_identity, limits)
    local exact_identity, exact_error = compare_document_bytes(
        schema,
        filesystem,
        path,
        document,
        expected_identity
    )
    if not exact_identity then return nil, exact_error end
    local parsed, parsed_identity_or_error = stable_read(schema, filesystem, path, limits)
    if not parsed then return nil, parsed_identity_or_error end
    if not identity_equal(exact_identity, parsed_identity_or_error) then
        return nil, failure("ContextTemporaryMismatch", "Context validation identity changed")
    end
    if parsed.generation ~= document.generation
        or parsed.header.name ~= document.header.name
        or parsed.event_count ~= document.event_count
    then
        return nil, failure("ContextTemporaryMismatch", "Context semantic validation changed")
    end
    return parsed_identity_or_error, parsed
end

local function copy_file_verified(filesystem, source_path, source_identity, target_path, limits)
    local opened, source_or_error = filesystem.open_read(source_path)
    if not opened then return nil, source_or_error end
    local source = source_or_error
    local stated, initial_or_error = filesystem.stat_identity(source)
    if not stated or not identity_equal(source_identity, initial_or_error) then
        filesystem.close(source)
        return nil, stated and failure(
            "TargetChanged",
            "Context source changed before previous generation copy"
        ) or initial_or_error
    end
    local created, target_or_error = filesystem.create_new(
        target_path,
        limits.context_permissions
    )
    if not created then
        filesystem.close(source)
        return nil, target_or_error
    end
    local target = target_or_error
    local total, copy_error = 0, nil
    while true do
        local read, chunk_or_error = filesystem.stream_read(
            source,
            filesystem.capabilities.maximum_chunk_bytes
        )
        if not read then
            copy_error = chunk_or_error
            break
        end
        total = total + #chunk_or_error.bytes
        if total > limits.maximum_context_bytes then
            copy_error = failure("ContextLimit", "Context copy exceeds its byte limit")
            break
        end
        if #chunk_or_error.bytes > 0 then
            local written, write_error = filesystem.stream_write(target, chunk_or_error.bytes)
            if not written then
                copy_error = write_error
                break
            end
        elseif not chunk_or_error.eof then
            copy_error = failure("ContextFilesystemContract", "Context copy made no progress")
            break
        end
        if chunk_or_error.eof then break end
    end
    if not copy_error then
        local flushed, flush_error = filesystem.flush_file(target)
        if not flushed then copy_error = flush_error end
    end
    local source_restat, final_source_or_error = filesystem.stat_identity(source)
    local target_stated, target_identity_or_error = filesystem.stat_identity(target)
    local source_closed, source_close_error = filesystem.close(source)
    local target_closed, target_close_error = filesystem.close(target)
    if copy_error then
        cleanup_file(filesystem, target_path, target_stated and target_identity_or_error or nil)
        return nil, copy_error
    end
    if not source_restat then
        cleanup_file(filesystem, target_path, target_stated and target_identity_or_error or nil)
        return nil, final_source_or_error
    end
    if not target_stated then
        cleanup_file(filesystem, target_path)
        return nil, target_identity_or_error
    end
    if not source_closed then
        cleanup_file(filesystem, target_path, target_identity_or_error)
        return nil, source_close_error
    end
    if not target_closed then
        cleanup_file(filesystem, target_path, target_identity_or_error)
        return nil, target_close_error
    end
    if not identity_equal(initial_or_error, final_source_or_error) then
        cleanup_file(filesystem, target_path, target_identity_or_error)
        return nil, failure("TargetChanged", "Context changed while previous was copied")
    end
    local flushed, flush_error = filesystem.flush_directory(assert(directory_of(target_path)))
    if not flushed then
        cleanup_file(filesystem, target_path, target_identity_or_error)
        return nil, flush_error
    end
    return target_identity_or_error
end

local function validate_publication_document(state, document, expected_name)
    local canonical = document_states[document]
    if not canonical then
        return nil, failure(
            "InvalidContextDocument",
            "Context publication requires a canonical document"
        )
    end
    expected_name = expected_name or state.target.name
    if document.header.name ~= expected_name then
        return nil, failure(
            "ContextNameMismatch",
            "Context Header Name does not match the official basename"
        )
    end
    if document.recovery.model_view_status ~= "current" then
        return nil, failure(
            "StaleModelView",
            "Context ModelView must be rebuilt before publication"
        )
    end
    if state.mode == "create" then
        if document.generation ~= 1 then
            return nil, failure(
                "ContextGeneration",
                "new Context publication must start at generation one"
            )
        end
        return canonical
    end
    local base = state.base_document
    if document.generation ~= base.generation + 1 then
        return nil, failure(
            "ContextGeneration",
            "Context publication must increment generation exactly once"
        )
    end
    if document.header.created_at ~= base.header.created_at
        or document.header.updated_at <= base.header.updated_at
    then
        return nil, failure(
            "ContextGeneration",
            "Context publication must preserve CreatedAt and advance UpdatedAt"
        )
    end
    if document.event_count < base.event_count then
        return nil, failure("ContextHistoryRewrite", "Context publication removed durable Facts")
    end
    for index = 1, base.event_count do
        if not deep_equal(document.facts[index], base.facts[index]) then
            return nil, failure(
                "ContextHistoryRewrite",
                "Context publication rewrote a durable Fact"
            )
        end
    end
    return canonical
end

local function control_path_state(filesystem, path)
    local opened, handle_or_error = filesystem.open_read(path)
    if not opened then
        if type(handle_or_error) == "table" and handle_or_error.code == "NotFound" then
            return "absent"
        end
        return nil, handle_or_error
    end
    local stated, identity_or_error = filesystem.stat_identity(handle_or_error)
    local closed, close_error = filesystem.close(handle_or_error)
    if not stated then return nil, identity_or_error end
    if not closed then return nil, close_error end
    return "present", identity_or_error
end

---Creates a durable single-XML Context store around one schema and filesystem.
-- Writer leases are long lived; the per-writer publication mutex exists only
-- in memory and is held for the full write/validate/publish/confirm sequence.
-- @param schema table Context schema service returned by M.new.
-- @param ports table Contains the bounded filesystem service.
-- @param options table Mandatory release storage limits and permissions.
-- @return table|nil store Immutable Context store service.
-- @return table|nil err Structured dependency or limit failure.
function M.new_store(schema, ports, options)
    local schema_state = schema_service_states[schema]
    if not schema_state then
        return nil, failure(
            "InvalidContextStorePort",
            "Context store requires a schema service from this module"
        )
    end
    if type(schema_state.codec.new_reader) ~= "function" then
        return nil, failure(
            "InvalidContextStorePort",
            "Context XML codec does not expose incremental reading"
        )
    end
    if type(ports) ~= "table" or type(ports.filesystem) ~= "table" then
        return nil, failure("InvalidContextStorePort", "filesystem port is required")
    end
    for key in pairs(ports) do
        if key ~= "filesystem" then
            return nil, failure(
                "InvalidContextStorePort",
                "Context store ports contain an unknown field"
            )
        end
    end
    local filesystem, filesystem_error = validate_store_filesystem(ports.filesystem)
    if not filesystem then return nil, filesystem_error end
    local limits, limits_error = validate_store_options(options, schema_state)
    if not limits then return nil, limits_error end
    if filesystem.capabilities.maximum_lease_bytes
        < 64 + limits.maximum_lock_hostname_bytes
    then
        return nil, failure(
            "InvalidContextStoreOptions",
            "filesystem lease limit cannot carry writer metadata"
        )
    end

    local store = {}
    local owner = {}
    local writer_states = setmetatable({}, { __mode = "k" })

    local function new_writer(state)
        local writer = readonly({}, "Context writer")
        state.owner = owner
        state.status = "active"
        state.commit_active = false
        state.leases = state.leases or { state.lease }
        writer_states[writer] = state
        return writer
    end

    local function release_after_failure(lease, original_error)
        local released, release_error = filesystem.release_lease(lease)
        if not released then
            return nil, failure(
                "ContextLeaseUnknown",
                "writer setup failed and lease release is unknown",
                release_error.code,
                nil,
                original_error.code
            )
        end
        return nil, original_error
    end

    local function recoverable_official_error(error_value)
        if type(error_value) ~= "table" or type(error_value.code) ~= "string" then
            return false
        end
        return error_value.code == "NotFound"
            or error_value.code:match("^Xml") ~= nil
            or ({
                ContextSchema = true,
                ContextIntegrity = true,
                ContextSequence = true,
                ContextRelation = true,
            })[error_value.code] == true
    end

    local function recover_previous(path, previous_path, official_error)
        if not recoverable_official_error(official_error) then
            return nil, official_error, false
        end
        local previous_state, previous_identity_or_error = control_path_state(
            filesystem,
            previous_path
        )
        if not previous_state then return nil, previous_identity_or_error, false end
        if previous_state == "absent" then return nil, official_error, false end
        local previous_document, previous_read_identity_or_error = stable_read(
            schema,
            filesystem,
            previous_path,
            limits
        )
        if not previous_document then
            return nil, failure(
                "ContextRecoveryRequired",
                "official and previous-valid Context generations are unusable",
                previous_read_identity_or_error.code
            ), false
        end
        if not identity_equal(previous_identity_or_error, previous_read_identity_or_error) then
            return nil, failure(
                "ContextRecoveryRequired",
                "previous-valid Context changed during recovery"
            ), false
        end
        local official_state, official_identity_or_error = control_path_state(filesystem, path)
        if not official_state then return nil, official_identity_or_error, false end
        local restored, restore_error
        if official_state == "present" then
            restored, restore_error = filesystem.replace(previous_path, path)
        else
            restored, restore_error = filesystem.rename_no_replace(previous_path, path)
        end
        if not restored then
            return nil, failure(
                "ContextRecoveryUnknown",
                "previous-valid Context could not be restored",
                restore_error.code
            ), true
        end
        local flushed, flush_error = filesystem.flush_directory(assert(directory_of(path)))
        if not flushed then
            return nil, failure(
                "ContextRecoveryUnknown",
                "restored Context directory durability is unknown",
                flush_error.code
            ), true
        end
        local recovered, recovered_identity_or_error = stable_read(
            schema,
            filesystem,
            path,
            limits
        )
        if not recovered then
            return nil, failure(
                "ContextRecoveryUnknown",
                "restored Context could not be confirmed",
                recovered_identity_or_error.code
            ), true
        end
        return recovered, recovered_identity_or_error, false
    end

    local function acquire(path, metadata, mode, expected_credential)
        local target, target_error = validate_context_target(path)
        if not target then return nil, target_error end
        local credential_valid, credential_error = validate_target_credential(
            expected_credential,
            path
        )
        if not credential_valid then return nil, credential_error end
        local lock_bytes, metadata_error = encode_lock_metadata(metadata, limits)
        if not lock_bytes then return nil, metadata_error end
        if #lock_bytes > filesystem.capabilities.maximum_lease_bytes then
            return nil, failure("LeaseLimit", "writer metadata exceeds filesystem lease limit")
        end
        local lock_path = path .. ".yaca-lock"
        local acquired, lease_or_error = filesystem.acquire_lease(
            lock_path,
            lock_bytes,
            limits.lock_permissions
        )
        if not acquired then return nil, lease_or_error end

        if expected_credential ~= nil then
            local stated, observed_or_error = filesystem.stat_identity(path)
            if not stated
                or not credential_matches(
                    expected_credential,
                    path,
                    observed_or_error,
                    nil
                )
            then
                return release_after_failure(lease_or_error, failure(
                    "TargetChanged",
                    "selected Context changed before its body was opened",
                    stated and "identity" or observed_or_error.code
                ))
            end
        end

        local previous_path = path .. ".yaca-prev"
        if mode == "create" then
            local absent, absence_error = target_absent(filesystem, path)
            if not absent then return release_after_failure(lease_or_error, absence_error) end
            local previous_state, previous_error = control_path_state(filesystem, previous_path)
            if not previous_state then
                return release_after_failure(lease_or_error, previous_error)
            end
            if previous_state ~= "absent" then
                return release_after_failure(lease_or_error, failure(
                    "ContextRecoveryRequired",
                    "new Context path has a previous-valid control file"
                ))
            end
            return new_writer({
                mode = "create",
                path = path,
                target = target,
                lock_path = lock_path,
                previous_path = previous_path,
                lease = lease_or_error,
            })
        end

        local recovered_previous = false
        local document, identity_or_error = stable_read(schema, filesystem, path, limits)
        if not document then
            local recovered, recovered_identity_or_error, retain_lease = recover_previous(
                path,
                previous_path,
                identity_or_error
            )
            if not recovered then
                if retain_lease then return nil, recovered_identity_or_error end
                return release_after_failure(lease_or_error, recovered_identity_or_error)
            end
            document, identity_or_error = recovered, recovered_identity_or_error
            recovered_previous = true
        end
        if expected_credential ~= nil
            and not credential_matches(
                expected_credential,
                path,
                identity_or_error,
                document
            )
        then
            return release_after_failure(lease_or_error, failure(
                "TargetChanged",
                "selected Context header or identity changed before mutation"
            ))
        end
        if document.header.name ~= target.name then
            return release_after_failure(lease_or_error, failure(
                "ContextNameMismatch",
                "Context Header Name does not match the official basename"
            ))
        end
        local previous_state, previous_identity_or_error = control_path_state(
            filesystem,
            previous_path
        )
        if not previous_state then
            return release_after_failure(lease_or_error, previous_identity_or_error)
        end
        local cleaned_previous = false
        if previous_state == "present" then
            local cleaned, cleanup_error = cleanup_file(
                filesystem,
                previous_path,
                previous_identity_or_error
            )
            if not cleaned then
                return release_after_failure(lease_or_error, failure(
                    "ContextRecoveryRequired",
                    "previous-valid cleanup failed",
                    cleanup_error.code
                ))
            end
            cleaned_previous = true
        end
        local writer = new_writer({
            mode = "replace",
            path = path,
            target = target,
            lock_path = lock_path,
            previous_path = previous_path,
            lease = lease_or_error,
            base_document = document,
            base_identity = identity_or_error,
            recovered_previous = recovered_previous,
            cleaned_previous = cleaned_previous,
            lock_bytes = lock_bytes,
        })
        return writer, document
    end

    local function acquire_delete(path, metadata, expected_credential)
        local target, target_error = validate_context_target(path)
        if not target then return nil, target_error end
        local credential_valid, credential_error = validate_target_credential(
            expected_credential,
            path
        )
        if not credential_valid then return nil, credential_error end
        if expected_credential ~= nil
            and expected_credential.canonical_name ~= nil
            and expected_credential.canonical_name ~= target.name
        then
            return nil, failure(
                "TargetChanged",
                "selected Context name no longer matches its basename"
            )
        end
        local lock_bytes, metadata_error = encode_lock_metadata(metadata, limits)
        if not lock_bytes then return nil, metadata_error end
        if #lock_bytes > filesystem.capabilities.maximum_lease_bytes then
            return nil, failure("LeaseLimit", "writer metadata exceeds filesystem lease limit")
        end
        local lock_path = path .. ".yaca-lock"
        local acquired, lease_or_error = filesystem.acquire_lease(
            lock_path,
            lock_bytes,
            limits.lock_permissions
        )
        if not acquired then return nil, lease_or_error end
        local stated, identity_or_error = filesystem.stat_identity(path)
        if not stated then return release_after_failure(lease_or_error, identity_or_error) end
        if identity_or_error.kind ~= "file" then
            return release_after_failure(lease_or_error, failure(
                "ContextUnavailable",
                "Context target is not a regular file"
            ))
        end
        if expected_credential ~= nil
            and not credential_matches(
                expected_credential,
                path,
                identity_or_error,
                nil
            )
        then
            return release_after_failure(lease_or_error, failure(
                "TargetChanged",
                "selected Context changed before permanent deletion"
            ))
        end
        return new_writer({
            mode = "delete",
            path = path,
            target = target,
            lock_path = lock_path,
            previous_path = path .. ".yaca-prev",
            lease = lease_or_error,
            lock_bytes = lock_bytes,
            base_identity = identity_or_error,
        })
    end

    ---Validates an in-place foreign Context without acquiring a writer lease.
    -- Historical approvals remain data only; this report never activates a
    -- local Model, Permission, mapping, or pending operation.
    function store.inspect_import(path, expected_credential)
        local target, target_error = validate_context_target(path)
        if not target then return nil, target_error end
        local credential_valid, credential_error = validate_target_credential(
            expected_credential,
            path
        )
        if not credential_valid then return nil, credential_error end
        local lock_state, lock_identity_or_error = control_path_state(
            filesystem,
            path .. ".yaca-lock"
        )
        if not lock_state then return nil, lock_identity_or_error end
        if lock_state == "present" then
            return nil, failure(
                "LockConflict",
                "active Context writer blocks in-place import inspection"
            )
        end
        local document, identity_or_error = stable_read(schema, filesystem, path, limits)
        if not document then return nil, identity_or_error end
        if document.header.name ~= target.name then
            return nil, failure(
                "ContextNameMismatch",
                "imported Context Header Name does not match its in-place basename"
            )
        end
        if expected_credential ~= nil
            and not credential_matches(
                expected_credential,
                path,
                identity_or_error,
                document
            )
        then
            return nil, failure(
                "TargetChanged",
                "in-place imported Context changed during read-only validation"
            )
        end
        local report = assert(freeze({
            outcome = "validated-readonly",
            path = path,
            generation = document.generation,
            event_count = document.event_count,
            schema_version = document.schema_version,
            history_approvals = "audit-only",
            local_mapping_required = true,
            auto_replay = false,
            auto_continue = false,
            unresolved_operation_ids = document.recovery.unresolved_operation_ids,
            unresolved_tool_call_ids = document.recovery.unresolved_tool_call_ids,
            unknown_operation_ids = document.recovery.unknown_operation_ids,
        }, "Context import inspection"))
        return document, report
    end

    ---Acquires a long-lived writer lease before reading an existing Context body.
    function store.open_writer(path, metadata, expected_credential)
        return acquire(path, metadata, "replace", expected_credential)
    end

    ---Acquires a long-lived writer lease for a not-yet-published Context path.
    function store.create_writer(path, metadata)
        return acquire(path, metadata, "create")
    end

    ---Acquires a mutation lease and exact identity without parsing the XML body.
    -- This permits confirmed deletion of a corrupt Context while still binding
    -- the operation to the selected file object.
    function store.open_delete_writer(path, metadata, expected_credential)
        return acquire_delete(path, metadata, expected_credential)
    end

    ---Runs only evidence-safe previous-valid recovery under the normal lease.
    -- A stale-looking lock remains a conflict; age is never repair evidence.
    function store.repair(path, metadata, expected_credential)
        local writer, document_or_error = acquire(
            path,
            metadata,
            "replace",
            expected_credential
        )
        if not writer then
            if document_or_error.code == "LockConflict" then return nil, document_or_error end
            return nil, failure(
                "NoSafeRepair",
                "no evidence-safe Context repair could be applied",
                document_or_error.code
            )
        end
        local state = writer_states[writer]
        local outcome = state.recovered_previous and "restored-previous"
            or state.cleaned_previous and "cleaned-previous"
            or "no-repair-needed"
        return writer, document_or_error, assert(freeze({
            outcome = outcome,
            path = path,
            generation = document_or_error.generation,
            requires_repair_generation = state.recovered_previous == true,
            auto_replay = false,
        }, "Context repair receipt"))
    end

    ---Publishes one full canonical generation through the fixed commit state machine.
    function store.publish(writer, document, temporary_path)
        local state = writer_states[writer]
        if not state or state.owner ~= owner or state.status ~= "active" then
            return nil, failure("InvalidContextWriter", "Context writer is stale or foreign")
        end
        if state.commit_active then
            return nil, failure("ContextCommitConflict", "Context publication is already active")
        end
        local valid_temp, temp_error = validate_temp_path(state.path, temporary_path, limits)
        if not valid_temp then return nil, temp_error end
        local canonical, document_error = validate_publication_document(state, document)
        if not canonical then return nil, document_error end
        state.commit_active = true

        local function finish(value, error_value)
            state.commit_active = false
            return value, error_value
        end
        local function fault(code, message, reason)
            state.status = "faulted"
            return finish(nil, failure(code, message, reason))
        end

        if state.mode == "replace" then
            local current, current_identity_or_error = stable_read(
                schema,
                filesystem,
                state.path,
                limits
            )
            if not current
                or not identity_equal(state.base_identity, current_identity_or_error)
                or current.generation ~= state.base_document.generation
            then
                return fault(
                    "TargetChanged",
                    "Context target changed before publication",
                    current and "identity" or current_identity_or_error.code
                )
            end
        else
            local absent, absence_error = target_absent(filesystem, state.path)
            if not absent then
                if absence_error and absence_error.code == "DestinationExists" then
                    state.status = "faulted"
                end
                return finish(nil, absence_error)
            end
        end

        local temporary_identity, write_error = write_new_document(
            schema,
            filesystem,
            temporary_path,
            document,
            limits
        )
        if not temporary_identity then return finish(nil, write_error) end
        local verified_identity, verify_error = verify_document_path(
            schema,
            filesystem,
            temporary_path,
            document,
            temporary_identity,
            limits
        )
        if not verified_identity then
            cleanup_file(filesystem, temporary_path, temporary_identity)
            return finish(nil, verify_error)
        end

        local previous_identity
        if state.mode == "replace" then
            local current, current_identity_or_error = stable_read(
                schema,
                filesystem,
                state.path,
                limits
            )
            if not current
                or not identity_equal(state.base_identity, current_identity_or_error)
                or current.generation ~= state.base_document.generation
            then
                cleanup_file(filesystem, temporary_path, verified_identity)
                return fault(
                    "TargetChanged",
                    "Context target changed after temporary validation",
                    current and "identity" or current_identity_or_error.code
                )
            end
            previous_identity, write_error = copy_file_verified(
                filesystem,
                state.path,
                state.base_identity,
                state.previous_path,
                limits
            )
            if not previous_identity then
                cleanup_file(filesystem, temporary_path, verified_identity)
                return finish(nil, write_error)
            end
            local previous_document, previous_read_error = stable_read(
                schema,
                filesystem,
                state.previous_path,
                limits
            )
            if not previous_document
                or previous_document.generation ~= state.base_document.generation
            then
                cleanup_file(filesystem, temporary_path, verified_identity)
                cleanup_file(filesystem, state.previous_path, previous_identity)
                return finish(nil, previous_read_error or failure(
                    "ContextPreviousMismatch",
                    "previous-valid generation failed validation"
                ))
            end
            local restated, final_target_or_error = filesystem.stat_identity(state.path)
            if not restated or not identity_equal(state.base_identity, final_target_or_error) then
                cleanup_file(filesystem, temporary_path, verified_identity)
                cleanup_file(filesystem, state.previous_path, previous_identity)
                return fault(
                    "TargetChanged",
                    "Context target changed before replace",
                    restated and "identity" or final_target_or_error.code
                )
            end
        end

        local restated, final_temporary_or_error = filesystem.stat_identity(temporary_path)
        if not restated or not identity_equal(verified_identity, final_temporary_or_error) then
            cleanup_file(filesystem, temporary_path, verified_identity)
            if previous_identity then
                cleanup_file(filesystem, state.previous_path, previous_identity)
            end
            return finish(nil, restated and failure(
                "ContextTemporaryMismatch",
                "Context temporary changed before publication"
            ) or final_temporary_or_error)
        end

        local published, publish_error
        if state.mode == "replace" then
            published, publish_error = filesystem.replace(temporary_path, state.path)
        else
            published, publish_error = filesystem.rename_no_replace(
                temporary_path,
                state.path
            )
        end
        if not published then
            cleanup_file(filesystem, temporary_path, verified_identity)
            if previous_identity then
                cleanup_file(filesystem, state.previous_path, previous_identity)
            end
            return finish(nil, publish_error)
        end

        local directory_flushed, directory_error = filesystem.flush_directory(
            state.target.directory
        )
        if not directory_flushed then
            return fault(
                "ContextPublishUnknown",
                "Context was published but directory durability is unknown",
                directory_error.code
            )
        end
        local published_identity, confirm_error = verify_document_path(
            schema,
            filesystem,
            state.path,
            document,
            nil,
            limits
        )
        if not published_identity then
            return fault(
                "ContextPublishUnknown",
                "published Context generation could not be confirmed",
                confirm_error.code
            )
        end

        if previous_identity then
            local cleaned, cleanup_error = cleanup_file(
                filesystem,
                state.previous_path,
                previous_identity
            )
            if not cleaned then
                return fault(
                    "ContextCleanupRequired",
                    "new Context generation is valid but previous cleanup failed",
                    cleanup_error.code
                )
            end
        end
        state.mode = "replace"
        state.base_document = document
        state.base_identity = published_identity
        local receipt = assert(freeze({
            outcome = "published",
            path = state.path,
            generation = document.generation,
            event_count = document.event_count,
            auto_continue = document.recovery.auto_continue,
            unresolved_operation_ids = document.recovery.unresolved_operation_ids,
            unresolved_tool_call_ids = document.recovery.unresolved_tool_call_ids,
            unknown_operation_ids = document.recovery.unknown_operation_ids,
            target_qualified = filesystem.capabilities.target_qualified,
        }, "Context publication receipt"))
        return finish(receipt)
    end

    ---Moves a complete lifecycle generation to a new official path no-replace.
    -- Same-directory moves are rename transactions; cross-directory moves are
    -- explicit rebind transactions. The old official is hidden as the one
    -- recognized previous-valid generation before the new path is published,
    -- so Catalog observation never treats both paths as active Contexts.
    function store.move(writer, document, destination_path, temporary_path, action)
        local state = writer_states[writer]
        if not state or state.owner ~= owner or state.status ~= "active"
            or state.mode ~= "replace"
        then
            return nil, failure("InvalidContextWriter", "Context move requires an active writer")
        end
        if state.commit_active then
            return nil, failure("ContextCommitConflict", "Context publication is already active")
        end
        local destination, destination_error = validate_context_target(destination_path)
        if not destination then return nil, destination_error end
        local source_path = state.path
        local source_target = state.target
        local source_previous_path = state.previous_path
        if destination_path == state.path then
            return nil, failure("InvalidLifecycleMove", "Context move destination is unchanged")
        end
        action = action or (same_directory(state.path, destination_path) and "rename" or "rebind")
        if action ~= "rename" and action ~= "rebind" then
            return nil, failure("InvalidLifecycleMove", "Context move action is invalid")
        end
        if (action == "rename") ~= same_directory(state.path, destination_path) then
            return nil, failure(
                "InvalidLifecycleMove",
                action == "rename"
                    and "rename must remain in the same mirror directory"
                    or "rebind must change the mirror directory"
            )
        end
        local valid_temp, temp_error = validate_temp_path(
            destination_path,
            temporary_path,
            limits
        )
        if not valid_temp then return nil, temp_error end
        local canonical, document_error = validate_publication_document(
            state,
            document,
            destination.name
        )
        if not canonical then return nil, document_error end
        local lifecycle_found = false
        for index = state.base_document.event_count + 1, document.event_count do
            if document.facts[index].type == action then
                lifecycle_found = true
                break
            end
        end
        if not lifecycle_found then
            return nil, failure(
                "ContextLifecycleMissing",
                "Context move generation omits its durable lifecycle event"
            )
        end

        state.commit_active = true
        local destination_lock_path = destination_path .. ".yaca-lock"
        local destination_previous_path = destination_path .. ".yaca-prev"
        local destination_lease

        local function finish(value, error_value)
            state.commit_active = false
            return value, error_value
        end
        local function fault(code, message, reason)
            state.status = "faulted"
            return finish(nil, failure(code, message, reason))
        end
        local function retain_destination_lease()
            if destination_lease then
                state.leases[#state.leases + 1] = destination_lease
                destination_lease = nil
            end
        end
        local function move_unknown(message, reason)
            retain_destination_lease()
            return fault("ContextMoveUnknown", message, reason)
        end
        local function release_destination(original_error)
            if not destination_lease then return finish(nil, original_error) end
            local released, release_error = filesystem.release_lease(destination_lease)
            if not released then
                retain_destination_lease()
                return fault(
                    "ContextLeaseUnknown",
                    "Context move failed and destination lease release is unknown",
                    release_error.code
                )
            end
            destination_lease = nil
            return finish(nil, original_error)
        end

        local acquired, lease_or_error = filesystem.acquire_lease(
            destination_lock_path,
            state.lock_bytes,
            limits.lock_permissions
        )
        if not acquired then return finish(nil, lease_or_error) end
        destination_lease = lease_or_error

        local absent, absence_error = target_absent(filesystem, destination_path)
        if not absent then return release_destination(absence_error) end
        local previous_state, previous_error = control_path_state(
            filesystem,
            destination_previous_path
        )
        if not previous_state then return release_destination(previous_error) end
        if previous_state ~= "absent" then
            return release_destination(failure(
                "ContextRecoveryRequired",
                "move destination has a previous-valid control file"
            ))
        end

        local current, current_identity_or_error = stable_read(
            schema,
            filesystem,
            state.path,
            limits
        )
        if not current
            or not identity_equal(state.base_identity, current_identity_or_error)
            or current.generation ~= state.base_document.generation
        then
            state.status = "faulted"
            return release_destination(failure(
                "TargetChanged",
                "Context source changed before lifecycle move",
                current and "identity" or current_identity_or_error.code
            ))
        end

        local temporary_identity, write_error = write_new_document(
            schema,
            filesystem,
            temporary_path,
            document,
            limits
        )
        if not temporary_identity then return release_destination(write_error) end
        local verified_identity, verify_error = verify_document_path(
            schema,
            filesystem,
            temporary_path,
            document,
            temporary_identity,
            limits
        )
        if not verified_identity then
            cleanup_file(filesystem, temporary_path, temporary_identity)
            return release_destination(verify_error)
        end

        current, current_identity_or_error = stable_read(
            schema,
            filesystem,
            state.path,
            limits
        )
        if not current
            or not identity_equal(state.base_identity, current_identity_or_error)
            or current.generation ~= state.base_document.generation
        then
            cleanup_file(filesystem, temporary_path, verified_identity)
            state.status = "faulted"
            return release_destination(failure(
                "TargetChanged",
                "Context source changed after move generation validation",
                current and "identity" or current_identity_or_error.code
            ))
        end
        local source_previous_state, source_previous_error = control_path_state(
            filesystem,
            state.previous_path
        )
        if not source_previous_state then
            cleanup_file(filesystem, temporary_path, verified_identity)
            return release_destination(source_previous_error)
        end
        if source_previous_state ~= "absent" then
            cleanup_file(filesystem, temporary_path, verified_identity)
            return release_destination(failure(
                "ContextRecoveryRequired",
                "move source already has a previous-valid generation"
            ))
        end

        local hidden, hide_error = filesystem.rename_no_replace(
            state.path,
            state.previous_path
        )
        if not hidden then
            cleanup_file(filesystem, temporary_path, verified_identity)
            return release_destination(hide_error)
        end
        local hidden_stated, hidden_identity_or_error = filesystem.stat_identity(
            state.previous_path
        )
        if not hidden_stated or not identity_equal(state.base_identity, hidden_identity_or_error) then
            local restored = filesystem.rename_no_replace(state.previous_path, state.path)
            cleanup_file(filesystem, temporary_path, verified_identity)
            if not restored then
                return move_unknown(
                    "source identity changed and its official path could not be restored",
                    hidden_stated and "identity" or hidden_identity_or_error.code
                )
            end
            filesystem.flush_directory(state.target.directory)
            return release_destination(failure(
                "TargetChanged",
                "Context source identity changed during lifecycle move"
            ))
        end
        local source_flushed, source_flush_error = filesystem.flush_directory(
            state.target.directory
        )
        if not source_flushed then
            local restored = filesystem.rename_no_replace(state.previous_path, state.path)
            cleanup_file(filesystem, temporary_path, verified_identity)
            if restored then filesystem.flush_directory(state.target.directory) end
            if not restored then
                return move_unknown(
                    "source publication state is unknown after directory failure",
                    source_flush_error.code
                )
            end
            return release_destination(source_flush_error)
        end

        absent, absence_error = target_absent(filesystem, destination_path)
        if not absent then
            local restored, restore_error = filesystem.rename_no_replace(
                state.previous_path,
                state.path
            )
            cleanup_file(filesystem, temporary_path, verified_identity)
            if restored then filesystem.flush_directory(state.target.directory) end
            if not restored then
                return move_unknown(
                    "destination collision occurred and source restoration failed",
                    restore_error.code
                )
            end
            return release_destination(absence_error)
        end
        local restated, final_temporary_or_error = filesystem.stat_identity(temporary_path)
        if not restated or not identity_equal(verified_identity, final_temporary_or_error) then
            local restored = filesystem.rename_no_replace(state.previous_path, state.path)
            cleanup_file(filesystem, temporary_path, verified_identity)
            if restored then filesystem.flush_directory(state.target.directory) end
            if not restored then
                return move_unknown(
                    "temporary changed and source restoration failed",
                    restated and "identity" or final_temporary_or_error.code
                )
            end
            return release_destination(restated and failure(
                "ContextTemporaryMismatch",
                "Context temporary changed before lifecycle publication"
            ) or final_temporary_or_error)
        end

        local published, publish_error = filesystem.rename_no_replace(
            temporary_path,
            destination_path
        )
        if not published then
            local restored, restore_error = filesystem.rename_no_replace(
                state.previous_path,
                state.path
            )
            cleanup_file(filesystem, temporary_path, verified_identity)
            if restored then filesystem.flush_directory(state.target.directory) end
            if not restored then
                return move_unknown(
                    "new path publication failed and source restoration is unknown",
                    restore_error.code
                )
            end
            return release_destination(publish_error)
        end

        local destination_flushed, destination_flush_error = filesystem.flush_directory(
            destination.directory
        )
        if destination_flushed and destination.directory ~= state.target.directory then
            destination_flushed, destination_flush_error = filesystem.flush_directory(
                state.target.directory
            )
        end
        local published_identity, confirm_error = verify_document_path(
            schema,
            filesystem,
            destination_path,
            document,
            nil,
            limits
        )
        if not destination_flushed or not published_identity then
            state.path = destination_path
            state.target = destination
            state.base_document = document
            state.base_identity = published_identity
            state.leases[#state.leases + 1] = destination_lease
            destination_lease = nil
            return fault(
                "ContextMoveUnknown",
                "new Context path exists but lifecycle move could not be confirmed durable",
                not destination_flushed and destination_flush_error.code or confirm_error.code
            )
        end

        state.path = destination_path
        state.target = destination
        state.base_document = document
        state.base_identity = published_identity
        state.previous_path = destination_previous_path
        state.lock_path = destination_lock_path
        state.leases[#state.leases + 1] = destination_lease
        destination_lease = nil

        local cleaned, cleanup_error = filesystem.delete_verified(
            source_previous_path,
            hidden_identity_or_error
        )
        if not cleaned then
            return fault(
                "ContextCleanupRequired",
                "new Context path is valid but source previous cleanup failed",
                cleanup_error.code
            )
        end
        local cleanup_flushed, cleanup_flush_error = filesystem.flush_directory(
            source_target.directory
        )
        if not cleanup_flushed then
            return fault(
                "ContextCleanupRequired",
                "source previous was removed but directory durability is unknown",
                cleanup_flush_error.code
            )
        end

        return finish(assert(freeze({
            outcome = "moved",
            action = action,
            old_path = source_path,
            path = destination_path,
            generation = document.generation,
            event_count = document.event_count,
            target_qualified = filesystem.capabilities.target_qualified,
        }, "Context lifecycle receipt")))
    end

    ---Permanently deletes the four known Context storage targets best-effort.
    -- There is no trash, archive, restore, tombstone, secure-erase, or remote
    -- provider withdrawal claim. Every directory entry is removed only against
    -- the identity observed for that exact role.
    function store.delete(writer, temporary_or_options)
        local state = writer_states[writer]
        if not state or state.owner ~= owner or state.status ~= "active"
            or (state.mode ~= "replace" and state.mode ~= "delete")
        then
            return nil, failure(
                "InvalidContextWriter",
                "permanent deletion requires an active mutation writer"
            )
        end
        if state.commit_active then
            return nil, failure("ContextCommitConflict", "Context publication is already active")
        end
        local temporary_path
        if temporary_or_options == nil then
            temporary_path = state.path .. ".yaca-tmp-delete"
        elseif type(temporary_or_options) == "string" then
            temporary_path = temporary_or_options
        elseif type(temporary_or_options) == "table" then
            for key in pairs(temporary_or_options) do
                if key ~= "temporary_path" then
                    return nil, failure(
                        "InvalidContextDelete",
                        "Context delete options contain an unknown field"
                    )
                end
            end
            temporary_path = temporary_or_options.temporary_path
        else
            return nil, failure("InvalidContextDelete", "Context delete options are invalid")
        end
        local valid_temp, temp_error = validate_temp_path(
            state.path,
            temporary_path,
            limits
        )
        if not valid_temp then return nil, temp_error end

        local stated, current_identity_or_error = filesystem.stat_identity(state.path)
        if not stated or not identity_equal(state.base_identity, current_identity_or_error) then
            state.status = "faulted"
            return nil, failure(
                "TargetChanged",
                "Context target changed before permanent deletion",
                stated and "identity" or current_identity_or_error.code
            )
        end

        state.commit_active = true
        local targets = {}
        local function observed_role(role, path, known_identity)
            if known_identity ~= nil then
                return { role = role, path = path, identity = known_identity }
            end
            local path_state, identity_or_error = control_path_state(filesystem, path)
            if not path_state then
                return {
                    role = role,
                    path = path,
                    observation_error = identity_or_error,
                }
            end
            if path_state == "absent" then return { role = role, path = path } end
            return { role = role, path = path, identity = identity_or_error }
        end
        local observed = {
            observed_role("official", state.path, current_identity_or_error),
            observed_role("temporary", temporary_path),
            observed_role("previous-valid", state.previous_path),
        }
        local all_complete = true
        for _, item in ipairs(observed) do
            local outcome, error_code
            if item.observation_error then
                outcome = "unavailable"
                error_code = item.observation_error.code
                all_complete = false
            elseif item.identity == nil then
                outcome = "absent"
            else
                local deleted, delete_error = filesystem.delete_verified(
                    item.path,
                    item.identity
                )
                if deleted then
                    local flushed, flush_error = filesystem.flush_directory(
                        assert(directory_of(item.path))
                    )
                    if flushed then
                        outcome = "deleted"
                    else
                        outcome = "durability-unknown"
                        error_code = flush_error.code
                        all_complete = false
                    end
                else
                    outcome = delete_error.code == "IdentityChanged"
                        and "changed" or "failed"
                    error_code = delete_error.code
                    all_complete = false
                end
            end
            local target = { role = item.role, path = item.path, outcome = outcome }
            if error_code then target.error = error_code end
            targets[#targets + 1] = target
        end

        local lock_outcome, lock_error_code = "deleted", nil
        local remaining_leases = {}
        local released_any = false
        local seen = {}
        for _, lease in ipairs(state.leases or { state.lease }) do
            if lease ~= nil and not seen[lease] then
                seen[lease] = true
                local released, release_error = filesystem.release_lease(lease)
                if released then
                    released_any = true
                else
                    remaining_leases[#remaining_leases + 1] = lease
                    lock_outcome = release_error.code == "IdentityChanged"
                        and "changed" or "failed"
                    lock_error_code = lock_error_code or release_error.code
                    all_complete = false
                end
            end
        end
        if not released_any and #remaining_leases == 0 then lock_outcome = "absent" end
        state.leases = remaining_leases
        local lock_target = {
            role = "writer-lock",
            path = state.lock_path,
            outcome = lock_outcome,
        }
        if lock_error_code then lock_target.error = lock_error_code end
        targets[#targets + 1] = lock_target

        state.commit_active = false
        state.status = all_complete and "deleted" or "faulted"
        local receipt = assert(freeze({
            outcome = all_complete and "deleted" or "partial",
            path = state.path,
            permanent = true,
            recoverable = false,
            secure_erase = false,
            provider_withdrawal = false,
            targets = targets,
            target_qualified = filesystem.capabilities.target_qualified,
        }, "Context permanent deletion receipt"))
        return receipt
    end

    ---Releases one writer lease after all synchronous publication work ends.
    function store.close_writer(writer)
        local state = writer_states[writer]
        if not state or state.owner ~= owner or state.status == "closed" then
            return nil, failure("InvalidContextWriter", "Context writer is stale or foreign")
        end
        if state.commit_active then
            return nil, failure(
                "ContextCommitConflict",
                "Context writer cannot close during publication"
            )
        end
        local release_error
        local seen = {}
        for _, lease in ipairs(state.leases or { state.lease }) do
            if lease ~= nil and not seen[lease] then
                seen[lease] = true
                local released, current_error = filesystem.release_lease(lease)
                if not released and not release_error then release_error = current_error end
            end
        end
        state.status = "closed"
        if release_error then return nil, release_error end
        return true
    end

    ---Returns non-secret writer lifecycle state for status and fault handling.
    function store.writer_status(writer)
        local state = writer_states[writer]
        if not state or state.owner ~= owner then
            return nil, failure("InvalidContextWriter", "Context writer is foreign")
        end
        return assert(freeze({
            status = state.status,
            path = state.path,
            generation = state.base_document and state.base_document.generation or 0,
            publication_active = state.commit_active,
        }, "Context writer status"))
    end

    ---Inspects only bounded public lease metadata and never opens Context XML.
    -- A malformed or unreadable lease remains busy with an unknown PID; this
    -- method never treats age, hostname, or parse failure as stale evidence.
    function store.inspect_writer(path)
        local target, target_error = validate_context_target(path)
        if not target then return nil, target_error end
        local lock_path = path .. ".yaca-lock"
        local opened, handle_or_error = filesystem.open_read(lock_path)
        if not opened then
            if type(handle_or_error) == "table" and handle_or_error.code == "NotFound" then
                return assert(freeze({
                    busy = false,
                    pid = "unknown",
                    metadata_state = "absent",
                }, "Context writer inspection"))
            end
            return assert(freeze({
                busy = true,
                pid = "unknown",
                metadata_state = "unavailable",
            }, "Context writer inspection"))
        end
        local handle = handle_or_error
        local stated, initial_or_error = filesystem.stat_identity(handle)
        if not stated then
            filesystem.close(handle)
            return assert(freeze({
                busy = true,
                pid = "unknown",
                metadata_state = "unavailable",
            }, "Context writer inspection"))
        end
        local parts, total, read_error = {}, 0, nil
        if initial_or_error.size > filesystem.capabilities.maximum_lease_bytes then
            read_error = failure("LeaseLimit", "writer metadata exceeds its byte limit")
        end
        while not read_error do
            local read, chunk_or_error = filesystem.stream_read(
                handle,
                filesystem.capabilities.maximum_chunk_bytes
            )
            if not read then
                read_error = chunk_or_error
                break
            end
            total = total + #chunk_or_error.bytes
            if total > filesystem.capabilities.maximum_lease_bytes then
                read_error = failure("LeaseLimit", "writer metadata exceeds its byte limit")
                break
            end
            parts[#parts + 1] = chunk_or_error.bytes
            if chunk_or_error.eof then break end
            if #chunk_or_error.bytes == 0 then
                read_error = failure("ContextFilesystemContract", "lease read made no progress")
                break
            end
        end
        local restated, final_or_error = filesystem.stat_identity(handle)
        local closed = filesystem.close(handle)
        if read_error or not restated or not closed
            or not identity_equal(initial_or_error, final_or_error)
        then
            return assert(freeze({
                busy = true,
                pid = "unknown",
                metadata_state = "unavailable",
            }, "Context writer inspection"))
        end
        local bytes = table.concat(parts)
        local version, pid_text, started_at, hostname = bytes:match(
            "^version=([^\n]+)\npid=([^\n]+)\nstartedAt=([^\n]+)\n"
                .. "hostname=([^\n]+)\n$"
        )
        if not version then
            version, pid_text, started_at = bytes:match(
                "^version=([^\n]+)\npid=([^\n]+)\nstartedAt=([^\n]+)\n$"
            )
        end
        local pid = pid_text and canonical_decimal(pid_text, 1, "/Writer/pid") or nil
        local valid_time = started_at and canonical_time(started_at, "/Writer/startedAt") or nil
        local valid_hostname = hostname
        if hostname ~= nil then
            valid_hostname = strict_text(
                hostname,
                limits.maximum_lock_hostname_bytes,
                "/Writer/hostname",
                false
            )
        end
        if version ~= "1" or not pid or not valid_time
            or (hostname ~= nil and (not valid_hostname or hostname:find("[=\r\n]")))
        then
            return assert(freeze({
                busy = true,
                pid = "unknown",
                metadata_state = "invalid",
            }, "Context writer inspection"))
        end
        return assert(freeze({
            busy = true,
            pid = pid,
            started_at = valid_time,
            hostname = valid_hostname,
            metadata_state = "valid",
        }, "Context writer inspection"))
    end

    store.capabilities = readonly({
        single_writer = true,
        publication_mutex = true,
        full_stream_rewrite = true,
        previous_valid_generation = true,
        identity_bound_lifecycle = true,
        no_replace_move = true,
        in_place_import = true,
        permanent_delete = true,
        trash_restore_surface = false,
        secure_erase_claim = false,
        atomic_replace_candidate = filesystem.capabilities.atomic_replace_candidate,
        rename_no_replace_candidate = filesystem.capabilities.rename_no_replace_candidate,
        target_qualified = filesystem.capabilities.target_qualified,
    }, "Context store capabilities")
    store.limits = readonly({
        maximum_context_bytes = limits.maximum_context_bytes,
        maximum_lock_hostname_bytes = limits.maximum_lock_hostname_bytes,
        maximum_temp_nonce_bytes = limits.maximum_temp_nonce_bytes,
        context_permissions = limits.context_permissions,
        lock_permissions = limits.lock_permissions,
    }, "Context store limits")

    return readonly(store, "Context store")
end

return M
