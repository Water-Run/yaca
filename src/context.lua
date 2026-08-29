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

local function event(id, required, optional)
    return { id = id, required = required or {}, optional = optional or {} }
end

local EVENT_DEFINITIONS = {
    event("turn_started", {
        "kind", "configGeneration", "modelSnapshot", "permissionSnapshot",
        "promptSnapshot", "toolRegistrySnapshot",
    }),
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

    local stats, parse_error = codec.parse(source, {
        start_element = start_element,
        text = character_data,
        end_element = end_element,
    })
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

    ---Reads one untrusted internal Context XML source through the bounded SAX codec.
    function service.read(source)
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

    return readonly(service, "Context service")
end

return M
