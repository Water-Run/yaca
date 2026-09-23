--[[
Author: WaterRun
Date: 2026-09-23
File: context.lua
Description: Models, reads, writes, and exports canonical internal Context documents.
]]

local text = require("text")
local xml = require("xml")
local filesystem_util = require("fs")

local M = {}

local SCHEMA_VERSION = "0.1.0"
--@metatable document_states Associates validated Context document proxies with canonical document state.
--@field __mode string Fixed k mode: keys are weak; entries remain mutable within their owning module.
local document_states = setmetatable({}, { __mode = "k" })
--@metatable schema_service_states Associates schema service facades with their admitted private schema configuration.
--@field __mode string Fixed k mode: keys are weak; entries remain mutable within their owning module.
local schema_service_states = setmetatable({}, { __mode = "k" })

-- Define one closed Context event type and its required/optional fields.
--@param id string Event type identifier.
--@param required table|nil Ordered required field names.
--@param optional table|nil Ordered optional field names.
--@return table Event schema definition.
local function event(id, required, optional)
    return { id = id, required = required or {}, optional = optional or {} }
end

local EVENT_DEFINITIONS = {
    event("turn_started", {
        "kind", "configGeneration", "modelSnapshot", "permissionSnapshot",
        "promptSnapshot", "toolRegistrySnapshot",
    }, { "runtimeSnapshot", "contextDocumentGeneration", "queueItemId",
        "continuesResponseId", "supersedesResponseId" }),
    event("user_message", { "messageId", "text", "source" }, {
        "replyToMessageId",
    }),
    event("queue_item", {
        "queueItemId", "displayId", "action", "text",
    }, { "beforeQueueItemId", "askId", "reason" }),
    event("model_request", { "requestId", "purpose", "viewManifestRef" }, {
        "attemptId", "compactionId", "compactionMode", "sourceFirstSeq",
        "sourceLastSeq", "sourceDigest", "sourceEventCount", "configSnapshot",
        "modelSnapshot", "promptSnapshot", "manifestSnapshot",
        "viewContextGeneration",
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
    event("steer", { "messageId", "targetTurnId", "summary" }, { "askId" }),
    event("compaction", {
        "compactionId", "sourceFirstSeq", "sourceLastSeq", "sourceDigest", "status",
    }, {
        "summary", "errorId", "sourceEventCount", "summaryDigest",
        "manifestDigest", "builderAlgorithm", "modelSnapshot",
        "promptSnapshot", "viewContextGeneration", "requestId", "attemptId",
        "compactionMode", "automaticFailure",
    }),
    event("model_view_published", {
        "manifestDigest", "firstEventSeq", "lastEventSeq",
    }, { "replacesManifestDigest", "compactionId", "viewContextGeneration" }),
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
    ask = true,
    ["action-review"] = true,
    ["termination-review"] = true,
    compaction = true,
    ["self-test"] = true,
    ["context-name"] = true,
}
local QUEUE_ACTIONS = {
    enqueue = true, edit = true, move = true, drop = true, consume = true,
}
local MODEL_CONTROLS = { finish = true, ["ask-user"] = true, refuse = true }
local BOOLEAN_FIELDS = {
    truncated = true,
    manual = true,
    autoRenameDisabled = true,
    adopted = true,
    automaticFailure = true,
}
local DECIMAL_FIELDS = {
    rawBytes = true,
    sourceFirstSeq = true,
    sourceLastSeq = true,
    firstEventSeq = true,
    lastEventSeq = true,
    waterline = true,
    baseline = true,
    contextDocumentGeneration = true,
    sourceEventCount = true,
    viewContextGeneration = true,
    attemptId = true,
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
    queueItemId = true,
    beforeQueueItemId = true,
    askId = true,
    continuesResponseId = true,
    supersedesResponseId = true,
    manifestSnapshot = true,
}

-- Construct a structured diagnostic without throwing or formatting its optional fields.
--@param code string Stable diagnostic code used by callers to choose recovery behavior.
--@param message string Human-readable summary supplied by the failing operation.
--@param reason string|nil Optional machine-readable cause or validation rule.
--@param path string|nil Optional document or filesystem path associated with the failure.
--@param detail any|nil Optional underlying cause or contextual diagnostic data; retained as supplied.
--@return table New diagnostic record; optional non-nil fields are retained without deep copying.
local function failure(code, message, reason, path, detail)
    local result = { code = code, message = message }
    if reason ~= nil then result.reason = reason end
    if path ~= nil then result.path = path end
    if detail ~= nil then result.detail = detail end
    return result
end

-- Create a shallow read-only view without copying the backing table.
--@param values table Backing fields retained by reference; the caller owns their stability.
--@param label string|nil Diagnostic label; defaults to "readonly value".
--@return table Empty proxy exposing the backing fields through its locked metatable.
--@ownership Retains values by reference; nested values and the backing table are not frozen.
local function readonly(values, label)
    --@metatable readonly_proxy Forwards reads and iteration; ordinary assignments raise an error.
    --@field __index table Backing values used for missing-key reads.
    --@field __newindex function Rejects ordinary assignments without changing the backing values.
    --@field __pairs function Enumerates the backing table with next.
    --@field __len function Reports the backing table sequence length.
    --@field __metatable string Hides this metatable behind the fixed "locked" marker.
    return setmetatable({}, {
        __index = values,
        -- Reject a write through the proxy before it can create an ordinary field.
        --@param _ table Proxy receiving the assignment; its contents are not consulted.
        --@param key any Attempted field name included in the diagnostic.
        --@return nil Does not return normally.
        --@error Always raises a read-only assignment error at the caller frame.
        __newindex = function(_, key)
            error((label or "readonly value") .. " cannot be modified: " .. tostring(key), 2)
        end,
        -- Iterate the backing fields instead of the empty proxy table.
        --@param none The proxy argument supplied by pairs is ignored.
        --@return function The standard next iterator.
        --@return table Backing values used as iterator state.
        --@return nil Initial key used to start iteration.
        __pairs = function()
            return next, values, nil
        end,
        -- Forward sequence-length queries to the backing table.
        --@param none The proxy operand supplied by Lua is ignored.
        --@return integer Length of the backing sequence under the Lua length operator.
        __len = function()
            return #values
        end,
        __metatable = "locked",
    })
end

-- Copy Context values into read-only proxies while rejecting cycles and bad keys.
--@param value any Candidate scalar or table.
--@param label string Diagnostic label for each proxy.
--@param visiting table|nil Recursion stack for cycle detection.
--@return any|nil Frozen recursive copy or unchanged scalar.
--@return table|nil InvalidContextValue diagnostic.
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

-- Count a dense one-based array while rejecting holes and extra key kinds.
--@param values any Candidate table; every key must belong to the sequence 1 through count.
--@return integer|nil Sequence length, including zero for an empty table; nil for an invalid shape.
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

-- Check the Lua integer subtype and the caller's inclusive lower bound.
--@param value any Candidate value; floats and non-numeric values are rejected.
--@param minimum integer Inclusive minimum accepted by this check.
--@return boolean True only for an integer at least minimum.
local function valid_integer(value, minimum)
    return math.type(value) == "integer" and value >= minimum
end

-- Require a Context object with no fields outside its schema.
--@param value any Candidate object.
--@param allowed table Set of admitted string keys.
--@param path string Diagnostic Context path.
--@return boolean|nil True for an exact-key object.
--@return table|nil ContextSchema diagnostic.
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

-- Admit bounded strict NUL-free UTF-8 as a Context text carrier.
--@param value any Candidate field bytes.
--@param maximum_bytes integer Inclusive field byte cap.
--@param path string Diagnostic Context path.
--@param empty boolean Whether empty text is allowed.
--@return string|nil Original admitted text.
--@return table|nil Schema, UTF-8, or limit error.
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

-- Admit structural text that survives XML 1.0 encoding losslessly.
--@param value any Candidate field bytes.
--@param maximum_bytes integer Inclusive byte cap.
--@param path string Diagnostic Context path.
--@param empty boolean Whether empty text is allowed.
--@return string|nil Admitted XML text.
--@return table|nil Text or XML compatibility error.
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

-- Admit XML attribute text without normalized whitespace controls.
--@param value any Candidate attribute value.
--@param maximum_bytes integer Inclusive byte cap.
--@param path string Diagnostic Context path.
--@param empty boolean Whether empty text is allowed.
--@return string|nil Admitted attribute value.
--@return table|nil Text or attribute-control error.
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

-- Parse a canonical nonnegative decimal within Lua's exact integer range.
--@param value any Candidate decimal text.
--@param minimum integer Inclusive accepted lower bound.
--@param path string Diagnostic Context path.
--@return integer|nil Parsed value.
--@return table|nil Schema or integer-limit error.
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

-- Apply Gregorian leap-year rules for Context UTC fields.
--@param year integer Calendar year.
--@return boolean True for a leap year.
local function leap_year(year)
    return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

-- Validate an exact UTC timestamp and its Gregorian calendar date.
--@param value any Candidate YYYY-MM-DDTHH:MM:SSZ text.
--@param path string Diagnostic Context path.
--@return string|nil Original canonical timestamp.
--@return table|nil ContextSchema time/date diagnostic.
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

-- Copy the contiguous array prefix while retaining element references.
--@param values table Sequence copied with ipairs.
--@return table New sequence containing the original element values through the first hole.
--@ownership Copies the outer table only; nested objects retain their original owners.
local function copy_array(values)
    local copied = {}
    for index, value in ipairs(values) do copied[index] = value end
    return copied
end

-- Admit XML, safety, and hard Context schema limits as one dependency set.
--@param options any Candidate schema dependencies and limits.
--@return table|nil Validated dependency record.
--@return table|nil InvalidContextOptions diagnostic.
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

-- Validate Context header name, chronological UTC times, and naming waterlines.
--@param candidate table Candidate header fields.
--@param admitted table Schema limits and dependencies.
--@return table|nil Normalized header.
--@return table|nil Schema or limit error.
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

-- Validate a Model or Permission selector with its exact snapshot digest.
--@param candidate table Candidate selector record.
--@param admitted table Schema limits.
--@param path string Diagnostic Context path.
--@return table|nil Normalized name/digest selector.
--@return table|nil Schema or text error.
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

-- Normalize durable Session selectors, overrides, and ContextPrompt.
--@param candidate table Candidate Session element.
--@param admitted table Schema limits.
--@return table|nil Normalized Session record.
--@return table|nil Schema, text, or limit error.
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

-- Classify a Fact field as XML text or Base64 with exact raw-byte metadata.
--@param value any Candidate field bytes.
--@param admitted table XML and safety services with byte caps.
--@param path string Diagnostic field path.
--@return table|nil Carrier, representation, raw size, and optional digest.
--@return table|nil Schema, carrier, limit, or digest error.
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

-- Validate one Fact's event schema, exact sequence, typed fields, and carrier.
--@param candidate table Candidate Context Fact event.
--@param expected_seq integer Required one-based durable sequence.
--@param admitted table Schema, XML, and safety limits.
--@return table|nil Normalized event and field metadata.
--@return table|nil Schema, sequence, relation, or limit error.
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
    if candidate.type == "model_request" then
        local compaction_fields = {
            "compactionId", "compactionMode", "sourceFirstSeq", "sourceLastSeq",
            "sourceDigest", "sourceEventCount", "configSnapshot", "modelSnapshot",
            "promptSnapshot", "manifestSnapshot", "viewContextGeneration",
        }
        local has_compaction_binding = fields.compactionId ~= nil
        if fields.purpose == "compaction" and has_compaction_binding then
            for _, name in ipairs(compaction_fields) do
                if fields[name] == nil then
                    return nil, failure(
                        "ContextSchema",
                        "bound compaction request omits durable recovery data",
                        "required-field",
                        path,
                        name
                    )
                end
            end
            local first = tonumber(fields.sourceFirstSeq)
            local last = tonumber(fields.sourceLastSeq)
            local count = tonumber(fields.sourceEventCount)
            local generation = tonumber(fields.viewContextGeneration)
            if fields.attemptId == nil
                or (fields.compactionMode ~= "manual"
                    and fields.compactionMode ~= "automatic")
                or first < 1 or first > last
                or count < last or count >= candidate.seq
                or generation < 1
                or fields.sourceDigest == ""
                or fields.configSnapshot == ""
                or fields.modelSnapshot == ""
                or fields.promptSnapshot == ""
                or fields.manifestSnapshot == ""
            then
                return nil, failure(
                    "ContextSchema",
                    "bound compaction request recovery data is invalid",
                    "compaction-request-binding",
                    path
                )
            end
        elseif fields.purpose == "compaction" then
            for _, name in ipairs(compaction_fields) do
                if fields[name] ~= nil then
                    return nil, failure(
                        "ContextSchema",
                        "legacy compaction request has a partial recovery binding",
                        "conditional-field",
                        path,
                        name
                    )
                end
            end
        else
            for _, name in ipairs(compaction_fields) do
                if fields[name] ~= nil then
                    return nil, failure(
                        "ContextSchema",
                        "non-compaction request carries compaction recovery data",
                        "conditional-field",
                        path,
                        name
                    )
                end
            end
        end
    end
    if candidate.type == "model_control" and not MODEL_CONTROLS[fields.control] then
        return nil, failure("ContextSchema", "model control is invalid", "enum", path)
    end
    if candidate.type == "queue_item" and not QUEUE_ACTIONS[fields.action] then
        return nil, failure(
            "ContextSchema",
            "queue item action is invalid",
            "enum",
            path
        )
    end
    if candidate.type == "turn_started"
        and fields.kind ~= "main" and fields.kind ~= "ask"
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
    if candidate.type == "compaction" then
        local bound_terminal = fields.requestId ~= nil
            or fields.attemptId ~= nil
            or fields.compactionMode ~= nil
            or fields.automaticFailure ~= nil
        if bound_terminal and (fields.requestId == nil
            or fields.attemptId == nil
            or fields.compactionMode == nil
            or fields.automaticFailure == nil)
        then
            return nil, failure(
                "ContextSchema",
                "compaction terminal has a partial recovery binding",
                "conditional-field",
                path
            )
        end
        if bound_terminal and ((fields.compactionMode ~= "manual"
                and fields.compactionMode ~= "automatic")
            or (fields.status == "ok" and fields.automaticFailure ~= "false")
            or (fields.automaticFailure == "true"
                and fields.compactionMode ~= "automatic"))
        then
            return nil, failure(
                "ContextSchema",
                "compaction terminal recovery data is invalid",
                "compaction-terminal-binding",
                path
            )
        end
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

-- Describe a Context relation that points to an absent or later identifier.
--@param kind string Referenced entity kind.
--@param identifier string Missing identifier.
--@param path string Failing Fact path.
--@return table ContextRelation diagnostic.
local function reference_error(kind, identifier, path)
    return failure(
        "ContextRelation",
        "Context event refers to an absent or out-of-order " .. kind,
        "missing-reference",
        path,
        identifier
    )
end

-- Admit an identifier once within its Context relation namespace.
--@param registry table Mutable set of previously seen identifiers.
--@param identifier string Candidate local identifier.
--@param kind string Entity label for duplicate diagnostics.
--@param path string Failing Fact path.
--@return boolean|nil True after first admission.
--@return table|nil Duplicate ContextRelation error.
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

-- Validate ordered Fact references and derive crash-recovery waterlines.
--@param events table Chronological normalized Context events.
--@return table|nil Recovery IDs, pending lifecycles, counters, and active queue/view facts.
--@return table|nil ContextRelation diagnostic for duplicate or out-of-order facts.
local function validate_relations(events)
    local requests, messages, tool_calls, operations = {}, {}, {}, {}
    local approvals, reviews, compactions, turns = {}, {}, {}, {}
    local turn_kinds, ended_turns = {}, {}
    local turn_order = {}
    local queue_items = {}
    local tool_results, operation_results, permission_decisions = {}, {}, {}
    local unknown_operations = {}
    local published_views = {}
    local compaction_requests = {}
    local compaction_lifecycles = {}
    local legacy_compaction_requests = {}
    local automatic_failure_count = 0
    local automatic_failure_history_complete = true
    local compaction_initial_serial = 0
    local approval_initial_serial = 0
    local runtime_initial_serials = {
        turn = 0,
        message = 0,
        request = 0,
        tool = 0,
        operation = 0,
        queue = 0,
        queue_display = 0,
        ask = 0,
    }

    -- Raise a recovered Runtime ID counter from one canonical identifier.
    --@param name string Counter field to update.
    --@param identifier string|nil Candidate Runtime identity.
    --@param pattern string Anchored serial capture pattern.
    --@return nil Updates the maximum observed serial in place.
    local function observe_runtime_serial(name, identifier, pattern)
        local serial = type(identifier) == "string" and identifier:match(pattern)
        serial = tonumber(serial)
        if valid_integer(serial, 1) and serial > runtime_initial_serials[name] then
            runtime_initial_serials[name] = serial
        end
    end

    -- Observe every Runtime-owned serial represented by one Fact.
    --@param item table Normalized Context event.
    --@param fields table Its normalized field map.
    --@return nil Advances only the matching recovered counters.
    local function observe_runtime_identities(item, fields)
        observe_runtime_serial("turn", item.turn_id, "^turn%-([1-9][0-9]*)$")
        observe_runtime_serial("ask", item.turn_id, "^ask%-([1-9][0-9]*)$")
        observe_runtime_serial(
            "message",
            fields.messageId,
            "^[^:]+:message:([1-9][0-9]*)$"
        )
        observe_runtime_serial(
            "request",
            fields.requestId,
            "^[^:]+:request:([1-9][0-9]*)$"
        )
        observe_runtime_serial(
            "tool",
            fields.toolCallId,
            "^[^:]+:tool:([1-9][0-9]*)$"
        )
        observe_runtime_serial(
            "operation",
            fields.operationId,
            "^[^:]+:operation:([1-9][0-9]*)$"
        )
        observe_runtime_serial(
            "queue",
            fields.queueItemId,
            "^queue%-item%-([1-9][0-9]*)$"
        )
        observe_runtime_serial(
            "queue_display",
            fields.displayId,
            "^#([1-9][0-9]*)$"
        )
        observe_runtime_serial("ask", fields.askId, "^ask%-([1-9][0-9]*)$")
    end

    -- Raise the recovered compaction serial from a canonical compaction ID.
    --@param identifier string|nil Candidate compaction ID.
    --@return nil Updates the maximum observed compaction serial.
    local function observe_compaction_serial(identifier)
        local serial = type(identifier) == "string"
            and identifier:match("^compaction%-([1-9][0-9]*)$")
        serial = tonumber(serial)
        if valid_integer(serial, 1) and serial > compaction_initial_serial then
            compaction_initial_serial = serial
        end
    end

    for _, item in ipairs(events) do
        local fields = item.fields
        local path = "/YacaContext/Facts/Event[" .. tostring(item.seq) .. "]"
        observe_runtime_identities(item, fields)
        if item.type == "turn_started" and item.turn_id then
            local ok, id_error = unique_id(turns, item.turn_id, "turn", path)
            if not ok then return nil, id_error end
            turn_kinds[item.turn_id] = fields.kind
            turn_order[#turn_order + 1] = item.turn_id
            if fields.queueItemId and not queue_items[fields.queueItemId] then
                return nil, reference_error("queue item", fields.queueItemId, path)
            end
            for _, name in ipairs({ "continuesResponseId", "supersedesResponseId" }) do
                if fields[name] and not messages[fields[name]] then
                    return nil, reference_error("message", fields[name], path)
                end
            end
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
        elseif item.type == "queue_item" then
            if fields.askId and turn_kinds[fields.askId] ~= "ask" then
                return nil, reference_error("ask turn", fields.askId, path)
            end
            local prior = queue_items[fields.queueItemId]
            if fields.action == "enqueue" then
                if prior ~= nil then
                    return nil, failure(
                        "ContextRelation",
                        "queue item identity is duplicated",
                        "duplicate-queue-item",
                        path
                    )
                end
                queue_items[fields.queueItemId] = "active"
            else
                if prior ~= "active" then
                    return nil, reference_error(
                        "active queue item",
                        fields.queueItemId,
                        path
                    )
                end
                if fields.action == "drop" or fields.action == "consume" then
                    queue_items[fields.queueItemId] = fields.action
                end
            end
            if fields.beforeQueueItemId
                and queue_items[fields.beforeQueueItemId] ~= "active"
            then
                return nil, reference_error(
                    "active queue item",
                    fields.beforeQueueItemId,
                    path
                )
            end
        elseif item.type == "model_request" then
            local ok, id_error = unique_id(requests, fields.requestId, "request", path)
            if not ok then return nil, id_error end
            if fields.purpose == "compaction" then
                if fields.compactionId == nil then
                    local inferred = fields.requestId:match(
                        "^(compaction%-[1-9][0-9]*):request:[1-9][0-9]*$"
                    )
                    observe_compaction_serial(inferred)
                    local legacy = {
                        legacy = true,
                        request_id = fields.requestId,
                        sequence = item.seq,
                        response_status = false,
                        cancel_requested = false,
                        cancel_result = false,
                    }
                    legacy_compaction_requests[#legacy_compaction_requests + 1] = legacy
                    compaction_requests[fields.requestId] = legacy
                else
                    observe_compaction_serial(fields.compactionId)
                    local attempt = tonumber(fields.attemptId)
                    local request = {
                        compaction_id = fields.compactionId,
                        mode = fields.compactionMode,
                        request_id = fields.requestId,
                        request_sequence = item.seq,
                        attempt = attempt,
                        source_first_seq = tonumber(fields.sourceFirstSeq),
                        source_last_seq = tonumber(fields.sourceLastSeq),
                        source_digest = fields.sourceDigest,
                        source_event_count = tonumber(fields.sourceEventCount),
                        config_snapshot = fields.configSnapshot,
                        model_snapshot = fields.modelSnapshot,
                        prompt_snapshot = fields.promptSnapshot,
                        manifest_snapshot = fields.manifestSnapshot,
                        manifest_digest = fields.viewManifestRef,
                        view_context_generation = tonumber(
                            fields.viewContextGeneration
                        ),
                        response_status = false,
                        cancel_requested = false,
                        cancel_result = false,
                    }
                    local lifecycle = compaction_lifecycles[fields.compactionId]
                    if lifecycle then
                        local previous = lifecycle.latest
                        if lifecycle.terminal
                            or previous.response_status ~= "interrupted"
                            or attempt ~= previous.attempt + 1
                            or request.mode ~= previous.mode
                            or request.source_first_seq ~= previous.source_first_seq
                            or request.source_last_seq ~= previous.source_last_seq
                            or request.source_digest ~= previous.source_digest
                            or request.source_event_count ~= previous.source_event_count
                            or request.config_snapshot ~= previous.config_snapshot
                            or request.model_snapshot ~= previous.model_snapshot
                            or request.prompt_snapshot ~= previous.prompt_snapshot
                            or request.manifest_snapshot ~= previous.manifest_snapshot
                            or request.manifest_digest ~= previous.manifest_digest
                        then
                            return nil, failure(
                                "ContextRelation",
                                "compaction retry does not continue its durable lifecycle",
                                "compaction-retry-binding",
                                path
                            )
                        end
                        lifecycle.latest = request
                    else
                        if attempt ~= 1 then
                            return nil, failure(
                                "ContextRelation",
                                "first bound compaction request must be attempt one",
                                "compaction-attempt",
                                path
                            )
                        end
                        lifecycle = {
                            compaction_id = fields.compactionId,
                            latest = request,
                            terminal = false,
                        }
                        compaction_lifecycles[fields.compactionId] = lifecycle
                    end
                    request.lifecycle = lifecycle
                    compaction_requests[fields.requestId] = request
                end
            end
        elseif item.type == "model_message" then
            if not requests[fields.requestId] then
                return nil, reference_error("request", fields.requestId, path)
            end
            local ok, id_error = unique_id(messages, fields.messageId, "message", path)
            if not ok then return nil, id_error end
            local compaction_request = compaction_requests[fields.requestId]
            if compaction_request then
                if compaction_request.response_status then
                    return nil, failure(
                        "ContextRelation",
                        "compaction request has more than one durable response",
                        "duplicate-compaction-response",
                        path
                    )
                end
                compaction_request.response_status = fields.status
            end
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
            local serial = tonumber(fields.approvalId:match("^approval%-([1-9][0-9]*)$"))
            if valid_integer(serial, 1) and serial > approval_initial_serial then
                approval_initial_serial = serial
            end
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
            if fields.askId and turn_kinds[fields.askId] ~= "ask" then
                return nil, reference_error("ask turn", fields.askId, path)
            end
            local ok, id_error = unique_id(messages, fields.messageId, "message", path)
            if not ok then return nil, id_error end
        elseif item.type == "turn_ended" then
            if not item.turn_id or ended_turns[item.turn_id] then
                return nil, failure(
                    "ContextRelation",
                    "turn must have exactly one ordered terminal event",
                    "duplicate-or-unbound-turn-end",
                    path
                )
            end
            ended_turns[item.turn_id] = true
        elseif item.type == "cancel" and fields.targetKind == "compaction-request" then
            local request = compaction_requests[fields.targetId]
            if not request then
                return nil, reference_error(
                    "bound compaction request",
                    fields.targetId,
                    path
                )
            end
            if fields.result == "pending" then
                if request.cancel_requested or request.cancel_result then
                    return nil, failure(
                        "ContextRelation",
                        "compaction cancellation request is duplicated",
                        "duplicate-compaction-cancel",
                        path
                    )
                end
                request.cancel_requested = true
                request.cancel_reason = fields.reason
            elseif fields.result == "cancelled" or fields.result == "unknown" then
                if not request.cancel_requested
                    or request.cancel_result
                    or request.cancel_reason ~= fields.reason
                then
                    return nil, failure(
                        "ContextRelation",
                        "compaction cancellation result has no exact pending request",
                        "compaction-cancel-binding",
                        path
                    )
                end
                request.cancel_result = fields.result
            else
                return nil, failure(
                    "ContextRelation",
                    "compaction cancellation result is invalid",
                    "compaction-cancel-result",
                    path
                )
            end
        elseif item.type == "compaction" then
            local ok, id_error = unique_id(
                compactions,
                fields.compactionId,
                "compaction",
                path
            )
            if not ok then return nil, id_error end
            compactions[fields.compactionId] = fields
            observe_compaction_serial(fields.compactionId)
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
            if fields.requestId ~= nil then
                local request = compaction_requests[fields.requestId]
                local lifecycle = request and request.lifecycle or nil
                local expected_failure = request and request.mode == "automatic"
                    and ((request.cancel_requested
                            and (request.cancel_reason == "compaction-active-time"
                                or request.cancel_reason
                                    == "compaction-process-recovery"))
                        or (not request.cancel_requested
                            and fields.status == "error"))
                if not request
                    or not lifecycle
                    or lifecycle.latest ~= request
                    or lifecycle.terminal
                    or fields.compactionId ~= request.compaction_id
                    or fields.compactionMode ~= request.mode
                    or tonumber(fields.attemptId) ~= request.attempt
                    or first ~= request.source_first_seq
                    or last ~= request.source_last_seq
                    or fields.sourceDigest ~= request.source_digest
                    or (fields.status == "ok"
                        and request.response_status ~= "complete")
                    or (fields.status == "cancelled"
                        and request.cancel_result ~= "cancelled")
                    or (fields.status == "error"
                        and request.response_status ~= "interrupted"
                        and request.cancel_result ~= "unknown")
                    or (fields.automaticFailure == "true") ~= expected_failure
                then
                    return nil, failure(
                        "ContextRelation",
                        "compaction terminal does not close its exact durable request",
                        "compaction-terminal-binding",
                        path
                    )
                end
                lifecycle.terminal = true
                if fields.status == "ok" then
                    automatic_failure_count = 0
                    automatic_failure_history_complete = true
                elseif fields.automaticFailure == "true" then
                    automatic_failure_count = automatic_failure_count + 1
                end
            elseif fields.status == "ok" then
                -- A successful legacy compaction is still an unambiguous reset.
                automatic_failure_count = 0
                automatic_failure_history_complete = true
            else
                -- Legacy terminal facts did not persist mode/circuit semantics.
                automatic_failure_history_complete = false
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
                compaction_id = fields.compactionId,
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
    local unfinished_turn_ids = {}
    for _, turn_id in ipairs(turn_order) do
        if not ended_turns[turn_id] then
            unfinished_turn_ids[#unfinished_turn_ids + 1] = turn_id
        end
    end
    local active_queue_item_ids = {}
    for queue_item_id, state in pairs(queue_items) do
        if state == "active" then
            active_queue_item_ids[#active_queue_item_ids + 1] = queue_item_id
        end
    end
    table.sort(active_queue_item_ids)
    local pending_compactions = {}
    for _, lifecycle in pairs(compaction_lifecycles) do
        if not lifecycle.terminal then
            local request = lifecycle.latest
            pending_compactions[#pending_compactions + 1] = {
                compaction_id = request.compaction_id,
                mode = request.mode,
                request_id = request.request_id,
                request_sequence = request.request_sequence,
                attempt = request.attempt,
                source_first_seq = request.source_first_seq,
                source_last_seq = request.source_last_seq,
                source_digest = request.source_digest,
                source_event_count = request.source_event_count,
                config_snapshot = request.config_snapshot,
                model_snapshot = request.model_snapshot,
                prompt_snapshot = request.prompt_snapshot,
                manifest_snapshot = request.manifest_snapshot,
                manifest_digest = request.manifest_digest,
                view_context_generation = request.view_context_generation,
                response_status = request.response_status,
                cancel_requested = request.cancel_requested,
                cancel_reason = request.cancel_reason or false,
            }
        end
    end
    table.sort(pending_compactions,
        -- Reopen pending compactions in their durable request order.
        --@param left table Pending lifecycle.
        --@param right table Pending lifecycle.
        --@return boolean True when left was requested earlier.
        function(left, right)
        return left.request_sequence < right.request_sequence
    end)
    local legacy_pending_compaction_request_ids = {}
    for _, request in ipairs(legacy_compaction_requests) do
        local inferred = request.request_id:match("^(.-):request:[1-9][0-9]*$")
        if (not inferred or not compactions[inferred])
            and request.cancel_result ~= "cancelled"
            and request.cancel_result ~= "unknown"
        then
            legacy_pending_compaction_request_ids[
                #legacy_pending_compaction_request_ids + 1
            ] = request.request_id
        end
    end
    return {
        unresolved_operations = unresolved_operations,
        unresolved_tool_calls = unresolved_tool_calls,
        unknown_operations = known_unknown,
        published_views = published_views,
        compactions = compactions,
        pending_compactions = pending_compactions,
        legacy_pending_compaction_request_ids = legacy_pending_compaction_request_ids,
        automatic_failure_count = automatic_failure_count,
        automatic_failure_history_complete = automatic_failure_history_complete,
        compaction_initial_serial = compaction_initial_serial,
        approval_initial_serial = approval_initial_serial,
        unfinished_turn_ids = unfinished_turn_ids,
        active_queue_item_ids = active_queue_item_ids,
        runtime_initial_serials = runtime_initial_serials,
    }
end

-- Validate an active Model view manifest against the available Fact count.
--@param candidate table Candidate digest, range, and compaction identity.
--@param admitted table Schema text limits.
--@param event_count integer Number of durable Facts.
--@return table|nil Normalized manifest.
--@return table|nil Schema, range, or text error.
local function normalize_manifest(candidate, admitted, event_count)
    local path = "/YacaContext/ModelView/ActiveManifest"
    local valid, valid_error = check_keys(candidate, {
        digest = true, first_event_seq = true, last_event_seq = true,
        compaction_id = true,
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
    local compaction_id
    if candidate.compaction_id ~= nil then
        compaction_id, digest_error = attribute_text(
            candidate.compaction_id,
            admitted.maximum_identifier_bytes,
            path .. "/@compactionId",
            false
        )
        if not compaction_id then return nil, digest_error end
    end
    -- A published empty prefix remains a valid view when the first Ask
    -- appends its admission facts. Like any earlier nonempty prefix, it is
    -- retained until an explicit model_view_published event advances it.
    local current = (first == 0 and last == 0 and compaction_id == nil)
        or (event_count > 0 and first >= 1 and first <= last and last <= event_count)
    return {
        digest = digest,
        first_event_seq = first,
        last_event_seq = last,
        compaction_id = compaction_id,
    }, current
end

-- Validate active manifest and compaction records against terminal Facts.
--@param candidate table Candidate ModelView element.
--@param admitted table Schema text and count limits.
--@param events table Normalized chronological Facts.
--@param relations table Derived publication and compaction relations.
--@return table|nil Normalized ModelView.
--@return boolean|table Whether view is current, or structured error on failure.
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
    for _, record in ipairs(records) do
        local terminal = relations.compactions[record.id]
        if type(terminal) ~= "table"
            or terminal.sourceFirstSeq ~= tostring(record.source_first_seq)
            or terminal.sourceLastSeq ~= tostring(record.source_last_seq)
            or terminal.sourceDigest ~= record.source_digest
            or terminal.status ~= record.status
            or terminal.summary ~= record.summary
        then
            return nil, failure(
                "ContextRelation",
                "CompactionRecord has no exact terminal compaction fact",
                "missing-compaction-terminal",
                "/YacaContext/ModelView"
            )
        end
    end
    local latest = relations.published_views[#relations.published_views]
    local published_current = (latest == nil and manifest.compaction_id == nil) or (
        latest.digest == manifest.digest
        and latest.first_event_seq == manifest.first_event_seq
        and latest.last_event_seq == manifest.last_event_seq
        and latest.compaction_id == manifest.compaction_id
    )
    if manifest.compaction_id ~= nil then
        local accepted
        for _, record in ipairs(records) do
            if record.id == manifest.compaction_id and record.status == "ok" then
                accepted = true
                break
            end
        end
        if not accepted then
            return nil, failure(
                "ContextRelation",
                "active compacted manifest has no accepted CompactionRecord",
                "missing-active-compaction",
                "/YacaContext/ModelView/ActiveManifest"
            )
        end
    end
    return {
        active_manifest = manifest,
        compaction_records = records,
    }, range_current and published_current
end

-- Remove private XML carrier objects from a normalized Fact projection.
--@param item table Internal normalized event and field metadata.
--@return table Public event with representation, size, and digest metadata.
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

-- Freeze a canonical Context document and retain its private normalized state.
--@param canonical table Internal validated Context state.
--@return table|nil Public immutable document facade.
--@return table|nil Freeze error.
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

-- Validate a full Context document and derive its safe recovery state.
--@param candidate table Candidate Context structure.
--@param admitted table Schema dependencies and hard limits.
--@return table|nil Immutable canonical Context document.
--@return table|nil Schema, relation, view, or limit error.
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
        unfinished_turn_ids = copy_array(relations.unfinished_turn_ids),
        active_queue_item_ids = copy_array(relations.active_queue_item_ids),
        pending_compactions = copy_array(relations.pending_compactions),
        legacy_pending_compaction_request_ids = copy_array(
            relations.legacy_pending_compaction_request_ids
        ),
        automatic_compaction_failure_count = relations.automatic_failure_count,
        automatic_compaction_failure_history_complete =
            relations.automatic_failure_history_complete,
        compaction_initial_serial = relations.compaction_initial_serial,
        approval_initial_serial = relations.approval_initial_serial,
        runtime_initial_serials = {
            turn = relations.runtime_initial_serials.turn,
            message = relations.runtime_initial_serials.message,
            request = relations.runtime_initial_serials.request,
            tool = relations.runtime_initial_serials.tool,
            operation = relations.runtime_initial_serials.operation,
            queue = relations.runtime_initial_serials.queue,
            queue_display = relations.runtime_initial_serials.queue_display,
            ask = relations.runtime_initial_serials.ask,
        },
        auto_continue = view_current
            and #relations.unresolved_operations == 0
            and #relations.unresolved_tool_calls == 0
            and #relations.unknown_operations == 0
            and #relations.unfinished_turn_ids == 0
            and #relations.active_queue_item_ids == 0
            and #relations.pending_compactions == 0
            and #relations.legacy_pending_compaction_request_ids == 0,
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

-- Build one XML attribute pair for the canonical writer.
--@param name string Attribute name.
--@param value string Attribute value.
--@return table Name/value writer argument.
local function attr(name, value)
    return { name = name, value = value }
end

-- Forward a canonical XML writer method and preserve its typed failure.
--@param writer table Bounded XML writer.
--@param method string Writer method name.
--@param ... any Method-specific arguments.
--@return boolean|nil True after the method succeeds.
--@return table|nil XML writer error.
local function writer_call(writer, method, ...)
    local accepted, writer_error = writer[method](...)
    if not accepted then return nil, writer_error end
    return true
end

-- Write one complete XML leaf with optional attributes and text carrier.
--@param writer table Bounded XML writer.
--@param name string Element name.
--@param value string|nil Text content.
--@param attributes table|nil Ordered attribute pairs.
--@return boolean|nil True after closing the leaf.
--@return table|nil XML writer error.
local function write_leaf(writer, name, value, attributes)
    local accepted, write_error = writer_call(writer, "start_element", name, attributes)
    if not accepted then return nil, write_error end
    if value ~= nil then
        accepted, write_error = writer_call(writer, "text", value)
        if not accepted then return nil, write_error end
    end
    return writer_call(writer, "end_element", name)
end

-- Stream one canonical Context document through the bounded XML writer.
--@param codec table XML codec providing new_writer.
--@param canonical table Private normalized Context state.
--@param sink function XML byte sink.
--@return boolean|nil True after writing a complete document.
--@return table|nil Writer or sink error.
--@effect Emits XML bytes to the caller's sink.
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
    local manifest_attributes = {
        attr("digest", manifest.digest),
        attr("firstEventSeq", tostring(manifest.first_event_seq)),
        attr("lastEventSeq", tostring(manifest.last_event_seq)),
    }
    if manifest.compaction_id then
        manifest_attributes[#manifest_attributes + 1] = attr(
            "compactionId",
            manifest.compaction_id
        )
    end
    accepted, writer_error = writer_call(
        writer,
        "empty_element",
        "ActiveManifest",
        manifest_attributes
    )
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

-- Require exact XML attributes and copy them before semantic parsing.
--@param attributes table Parsed attribute map.
--@param required table Ordered required attribute names.
--@param optional table|nil Optional attribute names.
--@param path string Diagnostic element path.
--@return table|nil Copied admitted attributes.
--@return table|nil Missing or unknown attribute diagnostic.
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

-- Parse complete Context XML or a bounded stream into a candidate structure.
--@param codec table XML parser and carrier decoder.
--@param safety_service table Raw digest service for binary fields.
--@param source string|function XML bytes or next-chunk callback.
--@param admitted table Context schema limits.
--@return table|nil Parsed candidate structure.
--@return table|nil Parser statistics on success, or semantic/stream error on failure.
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

    -- Latch the first semantic XML error for parser callback propagation.
    --@param error_value table Structured Context error.
    --@return boolean False to stop parsing.
    --@return string Diagnostic message for the XML parser.
    local function reject(error_value)
        semantic_error = semantic_error or error_value
        return false, error_value.message
    end

    -- Peek at the current XML element frame.
    --@param none This parser closure takes no arguments.
    --@return table|nil Top frame, or nil outside the root.
    local function parent()
        return frames[#frames]
    end

    -- Admit an XML start tag in canonical section and child order.
    --@param name string Element name.
    --@param attributes table Parsed attribute map.
    --@param path string XML diagnostic path.
    --@return boolean Accepted start-tag status.
    --@return string|nil Rejection message.
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
                }, { "compactionId" }, path)
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

    -- Collect leaf text and reject non-whitespace container content.
    --@param value string Parsed XML text fragment.
    --@param path string XML diagnostic path.
    --@return boolean Accepted text status.
    --@return string|nil Rejection message.
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

    -- Finish one XML element and assign its canonical candidate field.
    --@param name string Closing element name.
    --@param path string XML diagnostic path.
    --@return boolean Accepted closing-tag status.
    --@return string|nil Rejection message.
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
                compaction_id = frame.attributes.compactionId,
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

-- Parse only the Context root and Header from a bounded input stream.
--@param codec table XML incremental reader.
--@param source function Next-chunk callback.
--@param admitted table Header and XML limits.
--@return table|nil Parsed header candidate without reading the full body.
--@return table|nil Stream/parser error.
local function read_header_candidate(codec, source, admitted)
    if type(source) ~= "function" then
        return nil, failure("InvalidContextInput", "Context header stream is required")
    end
    local candidate = { header = {} }
    local frames = {}
    local semantic_error
    local completed = false
    local reader_finished = false
    local header_stage = 0
    local bytes_read = 0

    -- Latch the first header semantic error for XML reader propagation.
    --@param error_value table Structured header error.
    --@return boolean False to stop parsing.
    --@return string Diagnostic message.
    local function reject(error_value)
        semantic_error = semantic_error or error_value
        return false, error_value.message
    end

    -- Peek at the current header XML frame.
    --@param none This header parser closure takes no arguments.
    --@return table|nil Top frame, or nil before root.
    local function parent()
        return frames[#frames]
    end

    -- Admit only the root, first Header, and ordered Header leaves.
    --@param name string Element name.
    --@param attributes table Parsed attribute map.
    --@param path string XML diagnostic path.
    --@return boolean Accepted start-tag status.
    --@return string|nil Rejection message.
    local function start_element(name, attributes, path)
        if completed then return true end
        if semantic_error then return false, semantic_error.message end
        local parent_frame = parent()
        local parent_name = parent_frame and parent_frame.name or nil
        local parsed, parsed_error
        if not parent_name then
            if name ~= "YacaContext" or #frames ~= 0 or candidate.schema_version ~= nil then
                return reject(failure(
                    "ContextSchema",
                    "Context document must start with one YacaContext root",
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
            candidate.generation, parsed_error = canonical_decimal(
                parsed.generation,
                1,
                path .. "/@generation"
            )
            if not candidate.generation then return reject(parsed_error) end
        elseif parent_name == "YacaContext" then
            if name ~= "Header" then
                return reject(failure(
                    "ContextSchema",
                    "Context Header must be the first root child",
                    "child-order",
                    path
                ))
            end
            parsed, parsed_error = exact_attributes(attributes, {}, {}, path)
            if not parsed then return reject(parsed_error) end
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
        else
            return reject(failure(
                "ContextSchema",
                "Context Header leaf elements cannot contain children",
                "nested-element",
                path
            ))
        end
        frames[#frames + 1] = {
            name = name,
            text = {},
            text_seen = false,
        }
        return true
    end

    -- Collect Header leaf text and reject non-whitespace container data.
    --@param value string Parsed XML text fragment.
    --@param path string XML diagnostic path.
    --@return boolean Accepted text status.
    --@return string|nil Rejection message.
    local function character_data(value, path)
        if completed then return true end
        if semantic_error then return false, semantic_error.message end
        local frame = parent()
        if not frame then
            return reject(failure(
                "ContextSchema",
                "Context Header text is outside the root",
                "text",
                path
            ))
        end
        if frame.name == "YacaContext" or frame.name == "Header" then
            if value:find("[^ \t\r\n]") then
                return reject(failure(
                    "ContextSchema",
                    "Context Header containers accept only formatting whitespace",
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

    -- Finish a Header leaf or stop after the complete Header closes.
    --@param name string Closing element name.
    --@param path string XML diagnostic path.
    --@return boolean Accepted closing-tag status.
    --@return string|nil Rejection message.
    local function end_element(name, path)
        if completed then return true end
        if semantic_error then return false, semantic_error.message end
        local frame = frames[#frames]
        if not frame or frame.name ~= name then
            return reject(failure(
                "ContextSchema",
                "Context Header element stack is inconsistent",
                "element-stack",
                path
            ))
        end
        local parent_frame = frames[#frames - 1]
        local parent_name = parent_frame and parent_frame.name or nil
        local value = table.concat(frame.text)
        local parsed_error
        if name == "Header" then
            if header_stage < 3 then
                return reject(failure(
                    "ContextSchema",
                    "Header omits required fields",
                    "required-element",
                    path
                ))
            end
            frames[#frames] = nil
            completed = true
            return true
        end
        if name == "YacaContext" then
            return reject(failure(
                "ContextSchema",
                "Context ended before its Header was complete",
                "required-section",
                path
            ))
        end
        if parent_name == "Header" then
            if name == "Name" then
                candidate.header.name = value
            elseif name == "CreatedAt" then
                candidate.header.created_at = value
            elseif name == "UpdatedAt" then
                candidate.header.updated_at = value
            elseif name == "AutoRenameDisabled" then
                if value ~= "true" and value ~= "false" then
                    return reject(failure(
                        "ContextSchema",
                        "AutoRenameDisabled is invalid",
                        "boolean",
                        path
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
        end
        frames[#frames] = nil
        return true
    end

    local reader, reader_error = codec.new_reader({
        start_element = start_element,
        text = character_data,
        end_element = end_element,
    })
    if not reader then return nil, reader_error end
    while not completed do
        local called, ok, chunk_or_error = pcall(source)
        if not called then
            reader.close()
            return nil, failure("ContextStream", "Context header source raised an error")
        end
        if ok ~= true
            or type(chunk_or_error) ~= "table"
            or type(chunk_or_error.bytes) ~= "string"
            or type(chunk_or_error.eof) ~= "boolean"
        then
            reader.close()
            return nil, ok == false and chunk_or_error or failure(
                "ContextStream",
                "Context header source returned a malformed chunk"
            )
        end
        if #chunk_or_error.bytes == 0 and not chunk_or_error.eof then
            reader.close()
            return nil, failure("ContextStream", "Context header stream made no progress")
        end
        bytes_read = bytes_read + #chunk_or_error.bytes
        local accepted, feed_error = reader.feed(chunk_or_error.bytes)
        if not accepted then return nil, semantic_error or feed_error end
        if chunk_or_error.eof and not completed then
            local finished, finish_error = reader.finish()
            if not finished then return nil, semantic_error or finish_error end
            reader_finished = true
            if not completed then
                return nil, semantic_error or failure(
                    "ContextSchema",
                    "Context ended before its Header was complete",
                    "incomplete-header"
                )
            end
        end
    end
    if not reader_finished then reader.close() end
    if candidate.schema_version ~= SCHEMA_VERSION then
        return nil, failure(
            "UnsupportedContextSchema",
            "Context schema version is unsupported",
            "schema-version",
            "/YacaContext/@schemaVersion",
            candidate.schema_version
        )
    end
    local header, header_error = normalize_header(candidate.header, admitted)
    if not header then return nil, header_error end
    return readonly({
        schema_version = candidate.schema_version,
        generation = candidate.generation,
        header = readonly(header, "Context catalog Header"),
    }, "Context catalog header"), readonly({
        bytes = bytes_read,
        header_complete = true,
    }, "Context catalog header statistics")
end

-- Render arbitrary Context text visibly inside a single Markdown code span.
--@param value string Source bytes for lossy display.
--@return string|nil Escaped one-line code span.
--@return table|nil Display conversion error.
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

-- Checks decoded values before escaping or Base64 can hide a registered secret.
-- Canonical documents are bounded, acyclic tables produced by schema validation.
--@param value any Canonical document subtree, including map keys.
--@param scan function Current config secret scanner.
--@return boolean|nil True when no registered secret is present.
--@return table|nil Secret or scanner error.
local function scan_export_value(value, scan)
    if type(value) == "table" then
        for key, item in pairs(value) do
            local accepted, scan_error = scan_export_value(key, scan)
            if not accepted then return nil, scan_error end
            accepted, scan_error = scan_export_value(item, scan)
            if not accepted then return nil, scan_error end
        end
    elseif type(value) == "string" then
        local called, hits = pcall(scan, value)
        if not called or type(hits) ~= "table" then
            return nil, failure("ContextExportSecretScan", "Context export secret scan failed")
        end
        for _ in pairs(hits) do
            return nil, failure("RegisteredSecret", "Context export contains a registered secret")
        end
    end
    return true
end

-- Emit a bounded Markdown export of verified Context data.
--@param canonical table Private normalized Context document.
--@param admitted table Export byte cap and schema options.
--@param sink function|nil Optional streaming sink; nil buffers output.
--@return string|boolean|nil Export text or successful streaming marker.
--@return table|nil Rendering, limit, or sink error.
--@effect Writes to the caller's sink when supplied.
local function export_document(canonical, admitted, sink)
    if sink ~= nil and type(sink) ~= "function" then
        return nil, failure("InvalidContextExport", "Context export sink must be a function")
    end
    local output = sink == nil and {} or nil
    local bytes_written = 0
    -- Write one Markdown fragment while preserving the export byte cap.
    --@param bytes string Export fragment.
    --@return boolean|nil True after buffering or sink acceptance.
    --@return table|nil Limit or uncertain sink error.
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
    -- Render one labeled export field as a safe Markdown line.
    --@param label string Human-readable field label.
    --@param value string Field bytes to display.
    --@return boolean|nil True after emission.
    --@return table|nil Display or sink error.
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

---Copies a Context candidate into mutable tables while rejecting cyclic values.
--@param value any Value to copy recursively.
--@param visiting table|nil Ancestor set shared by recursive calls.
--@return any|nil Copied value, or nil when a cycle is found.
--@return table|nil err Structured cycle failure.
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

---Reconstructs an editable candidate from a canonical lifecycle document.
--@param document table Immutable document issued by this schema service.
--@return table|nil candidate Mutable candidate retaining every durable Fact.
--@return table|nil canonical_or_error Original canonical state or structured failure.
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

---Appends a validated Agent event batch and its prepared view publication.
--@param document table Current immutable Context document.
--@param mutation table Event batch, timestamp, and optional compaction record.
--@param admitted table Validated schema dependencies and limits.
--@return table|nil document Next canonical generation, or nil on failure.
--@return table|nil err Structured mutation or validation failure.
local function build_event_document(document, mutation, admitted)
    if type(mutation) ~= "table" then
        return nil, failure("InvalidEventMutation", "Context event mutation is required")
    end
    local allowed = {
        updated_at = true,
        events = true,
        compaction_record = true,
    }
    for key in pairs(mutation) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure(
                "InvalidEventMutation",
                "Context event mutation contains an unknown field"
            )
        end
    end
    local updated_at, time_error = canonical_time(
        mutation.updated_at,
        "/EventMutation/UpdatedAt"
    )
    if not updated_at then return nil, time_error end
    local event_count = dense_count(mutation.events)
    if event_count == nil or event_count < 1 then
        return nil, failure(
            "InvalidEventMutation",
            "Context event mutation requires a non-empty dense batch"
        )
    end
    local candidate, canonical_or_error = lifecycle_candidate(document)
    if not candidate then return nil, canonical_or_error end
    local canonical = canonical_or_error
    if updated_at <= canonical.header.updated_at then
        return nil, failure(
            "ContextGeneration",
            "Context event mutation must advance UpdatedAt"
        )
    end
    if #candidate.facts + event_count > admitted.maximum_events then
        return nil, failure("ContextLimit", "Context event batch exceeds the event limit")
    end
    candidate.generation = canonical.generation + 1
    candidate.header.updated_at = updated_at
    local published_view
    local terminal_compaction
    for index, event_candidate in ipairs(mutation.events) do
        if type(event_candidate) ~= "table" then
            return nil, failure("InvalidEventMutation", "Context event must be a table")
        end
        local event_allowed = { seq = true, type = true, turn_id = true, fields = true }
        for key in pairs(event_candidate) do
            if type(key) ~= "string" or not event_allowed[key] then
                return nil, failure(
                    "InvalidEventMutation",
                    "Context event contains an unknown mutation field"
                )
            end
        end
        local expected_sequence = #candidate.facts + 1
        if event_candidate.seq ~= expected_sequence
            or type(event_candidate.type) ~= "string"
            or type(event_candidate.fields) ~= "table"
        then
            return nil, failure(
                "ContextSequence",
                "Context event mutation sequence or shape is invalid"
            )
        end
        candidate.facts[expected_sequence] = {
            seq = expected_sequence,
            type = event_candidate.type,
            at = updated_at,
            turn_id = event_candidate.turn_id ~= false and event_candidate.turn_id or nil,
            fields = event_candidate.fields,
        }
        if event_candidate.type == "compaction" then
            if terminal_compaction then
                return nil, failure(
                    "InvalidEventMutation",
                    "one Context generation cannot terminate two compactions"
                )
            end
            terminal_compaction = event_candidate
        elseif event_candidate.type == "model_view_published" then
            local fields = event_candidate.fields
            local first = canonical_decimal(
                fields.firstEventSeq,
                0,
                "/EventMutation/ModelView/FirstEventSeq"
            )
            local last = canonical_decimal(
                fields.lastEventSeq,
                0,
                "/EventMutation/ModelView/LastEventSeq"
            )
            if published_view or not first or not last
                or first > last
                or last > expected_sequence
                or (first == 0 and last ~= 0)
                or fields.replacesManifestDigest
                    ~= candidate.model_view.active_manifest.digest
                or type(fields.manifestDigest) ~= "string"
                or fields.manifestDigest == ""
            then
                return nil, failure(
                    "InvalidEventMutation",
                    "Context model-view publication is invalid"
                )
            end
            published_view = event_candidate
            candidate.model_view.active_manifest = {
                digest = fields.manifestDigest,
                first_event_seq = first,
                last_event_seq = last,
                compaction_id = fields.compactionId,
            }
        end
    end
    local record = mutation.compaction_record
    if terminal_compaction and type(record) ~= "table" then
        return nil, failure(
            "InvalidEventMutation",
            "terminal compaction facts require one matching CompactionRecord"
        )
    end
    if record ~= nil then
        local fields = terminal_compaction and terminal_compaction.fields or nil
        if type(record) ~= "table"
            or type(fields) ~= "table"
            or fields.compactionId ~= record.id
            or fields.sourceFirstSeq ~= tostring(record.source_first_seq)
            or fields.sourceLastSeq ~= tostring(record.source_last_seq)
            or fields.sourceDigest ~= record.source_digest
            or fields.status ~= record.status
            or fields.summary ~= record.summary
            or (record.status == "ok" and (
                not published_view
                or published_view.fields.compactionId ~= record.id
                or published_view.fields.manifestDigest ~= fields.manifestDigest
            ))
            or (record.status ~= "ok" and published_view ~= nil)
        then
            return nil, failure(
                "InvalidEventMutation",
                "CompactionRecord does not match its terminal facts"
            )
        end
        candidate.model_view.compaction_records[
            #candidate.model_view.compaction_records + 1
        ] = record
    end
    return normalize_document(candidate, admitted)
end

local SESSION_OVERRIDE_NAMES = {
    CurrentModel = true,
    CurrentPermission = true,
    DoubleCheckOverride = true,
    DoubleCheckGoalOverride = true,
    ContextPrompt = true,
}

---Applies one typed Session override with its audit Fact and view update.
--@param document table Current immutable Context document.
--@param mutation table Validated override input and prepared view metadata.
--@param admitted table Validated schema dependencies and limits.
--@return table|nil document Next canonical generation, or nil on failure.
--@return table|nil err Structured mutation or validation failure.
local function build_session_document(document, mutation, admitted)
    if type(mutation) ~= "table" then
        return nil, failure("InvalidSessionMutation", "typed session mutation is required")
    end
    local allowed = {
        updated_at = true,
        name = true,
        value = true,
        mode = true,
        snapshot_digest = true,
        old_value_digest = true,
        new_value_digest = true,
        effective_at = true,
        view_manifest_digest = true,
        view_compaction_id = true,
        view_context_generation = true,
    }
    for key in pairs(mutation) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure(
                "InvalidSessionMutation",
                "Context session mutation contains an unknown field"
            )
        end
    end
    if not SESSION_OVERRIDE_NAMES[mutation.name] then
        return nil, failure(
            "InvalidSessionMutation",
            "Context session mutation name is unavailable"
        )
    end
    local updated_at, time_error = canonical_time(
        mutation.updated_at,
        "/SessionMutation/UpdatedAt"
    )
    if not updated_at then return nil, time_error end
    local old_digest, digest_error = attribute_text(
        mutation.old_value_digest,
        admitted.maximum_field_bytes,
        "/SessionMutation/OldValueDigest",
        false
    )
    if not old_digest then return nil, digest_error end
    local new_digest
    new_digest, digest_error = attribute_text(
        mutation.new_value_digest,
        admitted.maximum_field_bytes,
        "/SessionMutation/NewValueDigest",
        false
    )
    if not new_digest then return nil, digest_error end
    if mutation.effective_at ~= "next-turn" then
        return nil, failure(
            "InvalidSessionMutation",
            "Context session mutation must become effective at the next turn"
        )
    end
    local manifest_digest
    manifest_digest, digest_error = attribute_text(
        mutation.view_manifest_digest,
        admitted.maximum_field_bytes,
        "/SessionMutation/ViewManifestDigest",
        false
    )
    if not manifest_digest then return nil, digest_error end
    local compaction_id
    if mutation.view_compaction_id ~= nil then
        compaction_id, digest_error = attribute_text(
            mutation.view_compaction_id,
            admitted.maximum_identifier_bytes,
            "/SessionMutation/ViewCompactionId",
            false
        )
        if not compaction_id then return nil, digest_error end
        if not valid_integer(mutation.view_context_generation, 1) then
            return nil, failure(
                "InvalidSessionMutation",
                "compacted session view requires its Context generation"
            )
        end
    elseif mutation.view_context_generation ~= nil then
        return nil, failure(
            "InvalidSessionMutation",
            "plain session view cannot carry a compaction Context generation"
        )
    end

    local candidate, canonical_or_error = lifecycle_candidate(document)
    if not candidate then return nil, canonical_or_error end
    local canonical = canonical_or_error
    if updated_at <= canonical.header.updated_at then
        return nil, failure(
            "ContextGeneration",
            "session mutation must advance UpdatedAt"
        )
    end

    local name = mutation.name
    if name == "CurrentModel" or name == "CurrentPermission" then
        if mutation.mode ~= nil then
            return nil, failure(
                "InvalidSessionMutation",
                "selector session mutation cannot carry a mode"
            )
        end
        local value, value_error = attribute_text(
            mutation.value,
            admitted.maximum_identifier_bytes,
            "/SessionMutation/Value",
            false
        )
        if not value then return nil, value_error end
        local snapshot, snapshot_error = attribute_text(
            mutation.snapshot_digest,
            admitted.maximum_field_bytes,
            "/SessionMutation/SnapshotDigest",
            false
        )
        if not snapshot then return nil, snapshot_error end
        candidate.session[name == "CurrentModel"
            and "current_model" or "current_permission"] = {
            name = value,
            snapshot_digest = snapshot,
        }
    elseif name == "DoubleCheckOverride" then
        if mutation.snapshot_digest ~= nil or mutation.mode ~= nil
            or (mutation.value ~= "inherit" and type(mutation.value) ~= "boolean")
        then
            return nil, failure(
                "InvalidSessionMutation",
                "DoubleCheck session mutation is invalid"
            )
        end
        candidate.session.double_check_override = mutation.value
    elseif name == "DoubleCheckGoalOverride" then
        if mutation.snapshot_digest ~= nil
            or (mutation.mode ~= "inherit" and mutation.mode ~= "value")
            or (mutation.mode == "inherit" and mutation.value ~= nil)
        then
            return nil, failure(
                "InvalidSessionMutation",
                "DoubleCheck goal session mutation is invalid"
            )
        end
        local value
        if mutation.mode == "value" then
            local value_error
            value, value_error = xml_text(
                mutation.value,
                admitted.maximum_field_bytes,
                "/SessionMutation/Value",
                true
            )
            if not value then return nil, value_error end
        end
        candidate.session.double_check_goal_override = {
            mode = mutation.mode,
            value = value,
        }
    else
        if mutation.snapshot_digest ~= nil or mutation.mode ~= nil then
            return nil, failure(
                "InvalidSessionMutation",
                "ContextPrompt session mutation has incompatible metadata"
            )
        end
        local value, value_error = xml_text(
            mutation.value,
            admitted.maximum_field_bytes,
            "/SessionMutation/Value",
            true
        )
        if not value then return nil, value_error end
        candidate.session.context_prompt = value
    end

    candidate.generation = canonical.generation + 1
    candidate.header.updated_at = updated_at
    candidate.facts[#candidate.facts + 1] = {
        seq = #candidate.facts + 1,
        type = "session_override",
        at = updated_at,
        fields = {
            name = name,
            oldValueDigest = old_digest,
            newValueDigest = new_digest,
            effectiveAt = mutation.effective_at,
        },
    }
    local view_last_sequence = #candidate.facts
    local view_fields = {
        manifestDigest = manifest_digest,
        firstEventSeq = view_last_sequence == 0 and "0" or "1",
        lastEventSeq = tostring(view_last_sequence),
        replacesManifestDigest = canonical.model_view.active_manifest.digest,
    }
    if compaction_id then
        view_fields.compactionId = compaction_id
        view_fields.viewContextGeneration = tostring(
            mutation.view_context_generation
        )
    end
    candidate.facts[#candidate.facts + 1] = {
        seq = #candidate.facts + 1,
        type = "model_view_published",
        at = updated_at,
        fields = view_fields,
    }
    candidate.model_view.active_manifest = {
        digest = manifest_digest,
        first_event_seq = view_last_sequence == 0 and 0 or 1,
        last_event_seq = view_last_sequence,
        compaction_id = compaction_id,
    }
    return normalize_document(candidate, admitted)
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
        model_name = true,
        model_snapshot_digest = true,
        permission_name = true,
        permission_snapshot_digest = true,
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

---Changes lifecycle fields and builds the corresponding durable Fact payload.
--@param candidate table Mutable canonical candidate to update.
--@param mutation table Typed lifecycle input.
--@return string|nil event_type Lifecycle Fact type, or nil on failure.
--@return table fields_or_error Fact fields or structured mutation failure.
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
        local mapped = mutation.model_name ~= nil or mutation.model_snapshot_digest ~= nil
            or mutation.permission_name ~= nil or mutation.permission_snapshot_digest ~= nil
        if mapped then
            for _, name in ipairs({ "model_name", "model_snapshot_digest",
                "permission_name", "permission_snapshot_digest" }) do
                if type(mutation[name]) ~= "string" or mutation[name] == "" then
                    return nil, failure("InvalidLifecycleMutation", "import requires both complete local mappings")
                end
            end
            candidate.session.current_model = {
                name = mutation.model_name, snapshot_digest = mutation.model_snapshot_digest,
            }
            candidate.session.current_permission = {
                name = mutation.permission_name, snapshot_digest = mutation.permission_snapshot_digest,
            }
        end
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

---Builds a new Context generation for a lifecycle mutation and view publication.
--@param document table Current immutable Context document.
--@param mutation table Typed lifecycle input and prepared view metadata.
--@param admitted table Validated schema dependencies and limits.
--@return table|nil document Next canonical generation, or nil on failure.
--@return table|nil err Structured mutation or validation failure.
local function build_lifecycle_document(document, mutation, admitted)
    if type(mutation) ~= "table" or type(mutation.kind) ~= "string" then
        return nil, failure("InvalidLifecycleMutation", "typed lifecycle mutation is required")
    end
    local kind_fields = LIFECYCLE_FIELDS[mutation.kind]
    if not kind_fields then
        return nil, failure("InvalidLifecycleMutation", "Context lifecycle kind is unknown")
    end
    local allowed = {
        kind = true, updated_at = true, view_manifest_digest = true,
        view_compaction_id = true, view_context_generation = true,
    }
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

    local compaction_id = mutation.view_compaction_id
    if compaction_id ~= nil then
        local compaction_error
        compaction_id, compaction_error = attribute_text(
            compaction_id, admitted.maximum_identifier_bytes, "/Lifecycle/ViewCompactionId", false
        )
        if not compaction_id then return nil, compaction_error end
        if not valid_integer(mutation.view_context_generation, 1) then
            return nil, failure("InvalidLifecycleMutation", "compacted lifecycle view needs its generation")
        end
    elseif mutation.view_context_generation ~= nil then
        return nil, failure("InvalidLifecycleMutation", "plain lifecycle view cannot carry compaction generation")
    end

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

    -- Hash the complete fact prefix before the publication event. Including
    -- the event's own digest in that prefix would create a circular manifest.
    local view_last_sequence = #candidate.facts
    local view_fields = {
        manifestDigest = manifest_digest,
        firstEventSeq = view_last_sequence == 0 and "0" or "1",
        lastEventSeq = tostring(view_last_sequence),
        replacesManifestDigest = canonical.model_view.active_manifest.digest,
    }
    if compaction_id then
        view_fields.compactionId = compaction_id
        view_fields.viewContextGeneration = tostring(mutation.view_context_generation)
    end
    candidate.facts[#candidate.facts + 1] = {
        seq = #candidate.facts + 1,
        type = "model_view_published",
        at = updated_at,
        fields = view_fields,
    }
    candidate.model_view.active_manifest = {
        digest = manifest_digest,
        first_event_seq = view_last_sequence == 0 and 0 or 1,
        last_event_seq = view_last_sequence,
        compaction_id = compaction_id,
    }
    return normalize_document(candidate, admitted)
end

---Creates the internal v0.1 Context document service.
-- The XML codec and SHA-256 service are injected from the release loader. All
-- dimensions are mandatory release limits; callers cannot disable them.
--@param options table Bounded XML/safety services and Context hard limits.
--@return table|nil service Immutable Context schema service.
--@return table|nil err Structured dependency or limit failure.
function M.new(options)
    local admitted, options_error = validate_dependency(options)
    if not admitted then return nil, options_error end
    local service = {}

    ---Validates and freezes one semantic Context candidate.
    --@param candidate table Untrusted semantic Context fields and Facts.
    --@return table|nil document Immutable canonical Context document.
    --@return table|nil err Structured schema failure.
    function service.build(candidate)
        return normalize_document(candidate, admitted)
    end

    ---Appends one already-sequenced durable Agent batch as a new full XML
    -- generation without rewriting prior Facts or changing the active view.
    --@param document table Current immutable Context document.
    --@param mutation table Sequenced Fact batch and prepared view metadata.
    --@return table|nil document Next immutable Context generation.
    --@return table|nil err Structured mutation or schema failure.
    function service.append_events(document, mutation)
        return build_event_document(document, mutation, admitted)
    end

    ---Builds one atomic Session override generation, its privacy-preserving
    -- audit event, and the matching already-prepared Model-view publication.
    --@param document table Current immutable Context document.
    --@param mutation table Typed Session override and prepared view metadata.
    --@return table|nil document Next immutable Context generation.
    --@return table|nil err Structured mutation or schema failure.
    function service.session_document(document, mutation)
        return build_session_document(document, mutation, admitted)
    end

    ---Builds one full lifecycle generation without rewriting durable Facts.
    -- Supported kinds are rename, rebind, import, repair,
    -- set_auto_rename_disabled, and resolve_operation.
    --@param document table Current immutable Context document.
    --@param mutation table Typed lifecycle change and prepared view metadata.
    --@return table|nil document Next immutable Context generation.
    --@return table|nil err Structured mutation or schema failure.
    function service.lifecycle_document(document, mutation)
        return build_lifecycle_document(document, mutation, admitted)
    end

    ---Reads one untrusted internal Context XML source through the bounded SAX codec.
    --@param source string|table XML bytes or dense byte-chunk array.
    --@return table|nil document Immutable validated Context document.
    --@return table stats_or_error Parse statistics or structured failure.
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
    --@param next_chunk function Pull callback yielding bounded XML chunks.
    --@return table|nil document Immutable validated Context document.
    --@return table stats_or_error Parse statistics or structured failure.
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

    ---Reads only the bounded canonical Header prefix of one Context stream.
    -- The pull source is not called again after `</Header>` is observed. Full
    -- document validation remains the responsibility of normal Context open.
    --@param next_chunk function Pull callback yielding bounded XML chunks.
    --@return table|nil header Canonical Context Header on success.
    --@return table|nil err Structured parse or schema failure.
    function service.read_header_stream(next_chunk)
        return read_header_candidate(admitted.codec, next_chunk, admitted)
    end

    ---Streams deterministic internal XML for a document with a current ModelView.
    --@param document table Immutable canonical Context document.
    --@param sink function Consumer of each deterministic XML byte chunk.
    --@return table|nil stats Written byte and event counts.
    --@return table|nil err Structured validation, codec, or sink failure.
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
    --@param document table Immutable canonical Context document.
    --@return string|nil bytes Serialized XML, or nil on failure.
    --@return table stats_or_error Write statistics or structured failure.
    function service.encode(document)
        local parts = {}
        ---Collects one XML chunk for the in-memory encoding result.
        --@param bytes string Encoded XML chunk.
        --@return boolean accepted Always true for this local collector.
        local stats, encode_error = service.write(document, function(bytes)
            parts[#parts + 1] = bytes
            return true
        end)
        if not stats then return nil, encode_error end
        return table.concat(parts), stats
    end

    ---Projects a bounded Markdown transfer view from canonical Facts.
    -- An optional secret scanner checks decoded data before any sink output.
    -- Without a sink, the complete rendered bytes are checked before return too.
    --@param document table Validated immutable Context document.
    --@param sink function|nil Optional streaming output; failures may be partial.
    --@param secret_scan function|nil Current ConfigGeneration secret scanner.
    --@return string|table|nil Markdown bytes, sink statistics, or nil on failure.
    --@return table|nil err Structured validation, secret, limit, or sink failure.
    function service.export(document, sink, secret_scan)
        local canonical = document_states[document]
        if not canonical then
            return nil, failure(
                "InvalidContextDocument",
                "Context export requires a document from this module"
            )
        end
        if secret_scan ~= nil then
            if type(secret_scan) ~= "function" then
                return nil, failure("ContextExportSecretScan", "Context export secret scanner is invalid")
            end
            local safe, scan_error = scan_export_value(canonical, secret_scan)
            if not safe then return nil, scan_error end
        end
        local rendered, export_error = export_document(canonical, admitted, sink)
        if not rendered then return nil, export_error end
        if secret_scan and type(rendered) == "string" then
            local safe, scan_error = scan_export_value(rendered, secret_scan)
            if not safe then return nil, scan_error end
        end
        return rendered
    end

    ---Returns the fixed required/optional payload names for one event type.
    --@param event_type string Context Fact type identifier.
    --@return table|nil schema Immutable field definition for the Fact type.
    --@return table|nil err Structured unknown-type failure.
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
--@param document table Current immutable Context document.
--@param mutation table Typed begin or finish operation record.
--@param admitted table Validated schema dependencies and limits.
--@return table|nil document Next immutable Context generation.
--@return table|nil err Structured mutation or schema failure.
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
--@param schema table Context schema service issued by this module.
--@param document table Current immutable Context document.
--@param mutation table Typed operation begin or finish record.
--@return table|nil document Next immutable Context generation.
--@return table|nil err Structured dependency or mutation failure.
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
--@param ports table Safety digest/freezer and durable journal ports.
--@param options table Identifier/evidence limits and unresolved operation IDs.
--@return table|nil service Read-only operation barrier service.
--@return table|nil err Structured dependency or option failure.
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

    ---Checks bounded UTF-8 journal text and its empty-value policy.
    --@param value any Candidate journal text.
    --@param maximum integer Maximum encoded byte count.
    --@param empty boolean Whether an empty string is permitted.
    --@return boolean valid Whether the text satisfies journal limits.
    local function valid_string(value, maximum, empty)
        return type(value) == "string"
            and (empty or value ~= "")
            and #value <= maximum
            and not value:find("\0", 1, true)
            and text.validate_utf8(value) == true
    end
    ---Checks a bounded operation or tool-call identifier.
    --@param value any Candidate identifier.
    --@return boolean valid Whether the identifier is canonical.
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

    --@metatable operation_states Associates durable operation handles with their private generation and outcome state.
    --@field __mode string Fixed k mode: keys are weak; entries remain mutable within their owning module.
    local operation_states = setmetatable({}, { __mode = "k" })
    local active
    local blocked = unresolved_count > 0
    local service = {}

    ---Commits a journal record and requires acknowledgement of its exact digest.
    --@param method string Journal commit port name.
    --@param record table Immutable intent or result record.
    --@param digest_value string Binding digest to acknowledge.
    --@return boolean|nil committed True only after exact durable acknowledgement.
    --@return table|nil err Structured journal failure.
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

    ---Records an operation intent before its external effect is allowed.
    --@param intent table Operation identity, tool call, target, and expected digest.
    --@return table|nil handle Opaque active-operation handle.
    --@return string|table digest_or_error Intent digest or structured failure.
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

    ---Records the matching result before another external effect is allowed.
    --@param handle table Opaque handle returned by begin.
    --@param result table Observed effect and tool result evidence.
    --@return string|nil digest Committed result binding digest.
    --@return table|nil err Structured validation or durability failure.
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

    ---Reports current barrier and unresolved operation state without replaying effects.
    --@param none No arguments.
    --@return table status Immutable barrier state snapshot.
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

---Checks an absolute Context path without dot segments or NUL bytes.
--@param value any Candidate physical path.
--@return boolean valid Whether the path is absolute and canonical enough for storage.
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

---Extracts the parent directory while preserving the host path separator.
--@param path string Candidate physical path.
--@return string|nil directory Parent directory, or nil for an invalid path.
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

---Extracts the final path component across slash styles.
--@param path string Candidate physical path.
--@return string|nil basename Final path component, or nil for invalid input.
local function basename_of(path)
    if type(path) ~= "string" then return nil end
    local normalized = path:gsub("\\", "/")
    return normalized:match("([^/]+)$")
end

---Checks that two Context paths share the same textual parent directory.
--@param left string First physical path.
--@param right string Second physical path.
--@return boolean same Whether both parents match after separator normalization.
local function same_directory(left, right)
    local left_directory, right_directory = directory_of(left), directory_of(right)
    if not left_directory or not right_directory then return false end
    return left_directory:gsub("\\", "/") == right_directory:gsub("\\", "/")
end

---Compares the complete filesystem identity fields used by Context storage.
--@param left table First observed file identity.
--@param right table Second observed file identity.
--@return boolean equal Whether kind, volume, object, size, and modification agree.
local function identity_equal(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then return false end
    for _, key in ipairs({ "kind", "volume", "object", "size", "modified" }) do
        if left[key] ~= right[key] then return false end
    end
    return true
end

---Compares nested immutable proposal values with cycle-safe pair tracking.
--@param left any First value.
--@param right any Second value.
--@param visited table|nil Previously compared table pairs.
--@return boolean equal Whether both structures contain equal keys and values.
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

---Validates an optional observed target credential before opening a writer.
--@param credential table|nil Expected physical identity and Header fields.
--@param path string Physical target path to bind.
--@return boolean|nil valid True for an admissible credential.
--@return table|nil err Structured credential failure.
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

---Matches a bound target credential to observed file and Context state.
--@param credential table|nil Optional expected target state.
--@param path string Observed physical path.
--@param identity table Observed filesystem identity.
--@param document table|nil Parsed Context document when available.
--@return boolean matches Whether all supplied expectations still hold.
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

---Checks Context store limits against the schema codec and reserve policy.
--@param options table Candidate size, permission, and settlement limits.
--@param schema_state table Validated schema state containing codec bounds.
--@return table|nil limits Normalized store limits.
--@return table|nil err Structured option failure.
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
        settlement_reserve = true,
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
    local reserve = options.settlement_reserve
    if reserve ~= nil then
        if type(reserve) ~= "table" then
            return nil, failure("InvalidContextStoreOptions", "settlement reserve must be a table")
        end
        for name, value in pairs(reserve) do
            if name ~= "model_calls" and name ~= "model_bytes"
                and name ~= "message_bytes" and name ~= "result_bytes"
                or not valid_integer(value, 1)
            then
                return nil, failure("InvalidContextStoreOptions", "invalid settlement reserve")
            end
        end
        for _, name in ipairs({ "model_calls", "model_bytes", "message_bytes", "result_bytes" }) do
            if not valid_integer(reserve[name], 1)
                or reserve[name] > schema_state.maximum_field_bytes
            then
                return nil, failure("InvalidContextStoreOptions", "settlement reserve exceeds schema")
            end
        end
        reserve = assert(freeze(reserve, "Context settlement reserve"))
    end
    return {
        maximum_context_bytes = options.maximum_context_bytes,
        maximum_lock_hostname_bytes = options.maximum_lock_hostname_bytes,
        maximum_temp_nonce_bytes = options.maximum_temp_nonce_bytes,
        context_permissions = options.context_permissions,
        lock_permissions = options.lock_permissions,
        settlement_reserve = reserve,
    }
end

---Creates a capacity failure naming the exhausted publication dimension.
--@param dimension string Exhausted byte, text, element, SAX, or Fact dimension.
--@return table err Structured Context capacity failure.
local function capacity_failure(dimension)
    local error_value = failure("ContextCapacity",
        "Context has no capacity for new work and its pending results; start a new Context",
        dimension)
    error_value.publication_started = false
    return error_value
end

-- Space belongs to accepted obligations until their matching durable result.
-- Estimate their worst XML expansion (six bytes per raw byte, or base64),
-- including event/field markup. No reservation is an ephemeral runtime token:
-- the same calculation works after reopening the durable Context.
--@param schema_state table Validated codec and semantic limits.
--@param canonical table Canonical Context generation being published.
--@param limits table Store byte limit and optional settlement reserve.
--@return boolean|nil fits True if publication and reserved settlement fit.
--@return table|nil err Structured capacity or serialization failure.
local function check_publication_capacity(schema_state, canonical, limits)
    ---Counts serialized XML without retaining its output chunks.
    --@param none No callback arguments are consumed.
    --@return boolean accepted Always true for capacity accounting.
    local stats, write_error = write_document(schema_state.codec, canonical, function() return true end)
    if not stats then
        if write_error and write_error.code == "XmlLimit" then
            return nil, capacity_failure(write_error.reason or "xml")
        end
        return nil, write_error
    end
    local raw, events = 0, 0
    local policy = limits.settlement_reserve
    if policy then
        local turns, requests, calls = {}, {}, {}
        for _, event in ipairs(canonical.events) do
            local fields = event.fields
            if event.type == "turn_started" then turns[event.turn_id] = true
            elseif event.type == "turn_ended" then turns[event.turn_id] = nil
            elseif event.type == "model_request" then
                requests[fields.requestId] = { turn = event.turn_id, purpose = fields.purpose }
            elseif event.type == "model_message" then requests[fields.requestId] = nil
            elseif event.type == "action_review" or event.type == "termination_review" then
                requests[fields.reviewId] = nil
            elseif event.type == "tool_call" then
                calls[fields.toolCallId] = { permission = true, intent = true, approval = true, cancels = 2 }
            elseif event.type == "tool_result" then calls[fields.toolCallId] = nil
            elseif event.type == "permission_decision" and calls[fields.toolCallId] then
                calls[fields.toolCallId].permission = false
            elseif event.type == "operation_intent" and calls[fields.toolCallId] then
                calls[fields.toolCallId].intent = false
            elseif event.type == "approval" and fields.decision ~= "defer" and calls[fields.toolCallId] then
                calls[fields.toolCallId].approval = false
            elseif event.type == "cancel" and fields.targetKind == "ToolCall" and calls[fields.targetId] then
                local call = calls[fields.targetId]
                call.cancels = math.max(0, call.cancels - 1)
            end
        end
        ---Adds conservative serialized bytes and Fact count for pending settlement.
        --@param bytes integer Raw pending payload bytes.
        --@param count integer Pending Fact count.
        --@return nil Accumulates bounds in the enclosing scope.
        local function add(bytes, count)
            raw, events = raw + bytes + 8192 * count, events + count
        end
        ---Reserves the remaining permission, journal, approval, and result Facts.
        --@param call table Outstanding tool-call settlement state.
        --@return nil Updates the enclosing reserve counters.
        local function add_call(call)
            add(policy.result_bytes, 2) -- atomic operation_result + tool_result
            if call.permission then add(2 * policy.message_bytes, 1) end
            if call.intent then add(policy.message_bytes, 1) end
            if call.approval then add(4096, 1) end
            add(call.cancels * policy.message_bytes, call.cancels)
        end
        for _ in pairs(turns) do add(4 * policy.message_bytes, 4) end
        for _, request in pairs(requests) do
            if request.turn == nil or request.turn == false or turns[request.turn] then
                add(3 * policy.model_bytes + 2 * policy.message_bytes, 8)
                if request.purpose == "main" or request.purpose == "escape" then
                    for _ = 1, policy.model_calls do
                        add(policy.message_bytes, 1) -- accepted tool_call
                        add_call({ permission = true, intent = true, approval = true, cancels = 2 })
                    end
                end
            end
        end
        for _, call in pairs(calls) do add_call(call) end
        for _ in ipairs(canonical.recovery.pending_compactions or {}) do
            add(4 * policy.model_bytes + 4 * policy.message_bytes, 16)
        end
    end
    local codec = schema_state.codec.limits
    local required = {
        bytes = stats.bytes + 6 * raw + 4096 * events,
        text_bytes = stats.text_bytes + ((raw + 2) // 3) * 4,
        elements = stats.elements + 64 * events,
        sax_events = stats.sax_events + 192 * events,
        events = #canonical.events + events,
    }
    local maximum = {
        bytes = limits.maximum_context_bytes,
        text_bytes = codec.maximum_total_text_bytes,
        elements = codec.maximum_elements,
        sax_events = codec.maximum_sax_events,
        events = schema_state.maximum_events,
    }
    for _, dimension in ipairs({ "bytes", "text_bytes", "elements", "sax_events", "events" }) do
        if required[dimension] > maximum[dimension] then
            return nil, capacity_failure(dimension)
        end
    end
    return true
end

---Snapshots the bounded filesystem methods and declared target capabilities.
--@param filesystem table Candidate Context filesystem port.
--@return table|nil port Stable method snapshot and capability record.
--@return table|nil err Structured missing-port or capability failure.
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
    for _, name in ipairs({ "direct_inspect", "direct_reverify", "direct_replace", "direct_rename" }) do
        if type(filesystem[name]) == "function" then snapshot[name] = filesystem[name] end
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

---Checks the absolute canonical .xml target and extracts its Context name.
--@param path string Physical Context target path.
--@return string|nil name Context name derived from the basename.
--@return table|nil err Structured path failure.
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

---Encodes bounded lock-owner metadata for a new exclusive lease.
--@param metadata table Process identity, start time, and optional hostname.
--@param limits table Store hostname and lease byte limits.
--@return string|nil bytes Canonical lock metadata bytes.
--@return table|nil err Structured metadata failure.
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

---Binds a temporary path to its same-directory target and nonce limit.
--@param target_path string Canonical target XML path.
--@param temporary_path string Candidate new temporary path.
--@param limits table Maximum temporary nonce length.
--@return string|nil path Validated temporary path.
--@return table|nil err Structured path failure.
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

---Checks that a create destination is absent without masking read failures.
--@param filesystem table Bounded filesystem port.
--@param path string Candidate destination path.
--@return boolean|nil absent True only for an observed NotFound result.
--@return table|nil err Existing-target or filesystem failure.
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

---Deletes a temporary only while its observed object identity still matches.
--@param filesystem table Bounded filesystem port.
--@param path string Temporary path to clean up.
--@param identity table|nil Previously observed object identity.
--@return boolean|nil cleaned True when absent or safely deleted.
--@return table|nil err Structured cleanup failure.
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

---Reads a complete Context while checking pre/post file identity and size.
--@param schema table Context schema reader.
--@param filesystem table Bounded filesystem port.
--@param path string Absolute Context path.
--@param limits table Maximum Context byte limit.
--@return table|nil document Immutable parsed Context document.
--@return table identity_or_error Stable file identity or structured failure.
--@return table|nil stats Parse statistics on success.
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
    ---Pulls bounded XML chunks and enforces the store byte ceiling.
    --@param none No callback arguments.
    --@return boolean read Whether the next chunk was read.
    --@return table chunk_or_error Chunk/eof record or structured failure.
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

---Reads only a Context Header under the same identity and byte checks.
--@param schema table Context schema Header reader.
--@param filesystem table Bounded filesystem port.
--@param path string Absolute Context path.
--@param limits table Maximum Context byte limit.
--@return table|nil header Canonical parsed Header.
--@return table identity_or_error Stable file identity or structured failure.
--@return table|nil stats Prefix parse statistics on success.
local function stable_header_read(schema, filesystem, path, limits)
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
    local chunk_limit = math.min(filesystem.capabilities.maximum_chunk_bytes, 4096)
    ---Pulls small XML chunks until the canonical Header is complete.
    --@param none No callback arguments.
    --@return boolean read Whether the next chunk was read.
    --@return table chunk_or_error Chunk/eof record or structured failure.
    local header, stats_or_error = schema.read_header_stream(function()
        local read, chunk_or_error = filesystem.stream_read(handle, chunk_limit)
        if not read then return false, chunk_or_error end
        total = total + #chunk_or_error.bytes
        if total > limits.maximum_context_bytes then
            return false, failure("ContextLimit", "Context stream exceeds its byte limit")
        end
        return true, chunk_or_error
    end)
    local restated, final_or_error = filesystem.stat_identity(handle)
    local closed, close_error = filesystem.close(handle)
    if not header then return nil, stats_or_error end
    if not restated then return nil, final_or_error end
    if not closed then return nil, close_error end
    if not identity_equal(initial_or_error, final_or_error) then
        return nil, failure("TargetChanged", "Context changed while its Header was read")
    end
    return header, initial_or_error, stats_or_error
end

-- Serialize and flush a fresh canonical Context temporary, then bind its
-- post-close identity. The caller must verify canonical bytes before publishing.
--@param schema table Context codec owning document.
--@param filesystem table Bounded filesystem port.
--@param path string New absolute temporary path; existing paths are refused.
--@param document table Canonical immutable Context generation.
--@param limits table Context size and file permission limits.
--@return table|nil Post-close file identity, or nil on failure.
--@return table|nil Serialization statistics on success; structured failure otherwise.
--@effect Creates, writes and flushes the temporary; attempts identity-bound cleanup on failure.
local function write_new_document(schema, filesystem, path, document, limits)
    local created, handle_or_error = filesystem.create_new(path, limits.context_permissions)
    if not created then return nil, handle_or_error end
    local handle = handle_or_error
    local write_failure
    ---Writes one canonical XML chunk in filesystem-sized pieces.
    --@param bytes string Canonical encoded XML chunk.
    --@return boolean accepted Whether every piece was written.
    --@return string|nil reason Filesystem failure message for the codec.
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
    local final_identity, final_error = filesystem_util.observe_closed_write(filesystem, path, identity_or_error)
    if not final_identity then
        cleanup_file(filesystem, path, identity_or_error)
        return nil, failure("ContextTemporaryMismatch", "Context temporary changed at close", final_error.code)
    end
    return final_identity, stats
end

---Compares a closed file with canonical XML bytes and stable identity.
--@param schema table Context schema writer.
--@param filesystem table Bounded filesystem port.
--@param path string File path to verify.
--@param document table Expected canonical Context generation.
--@param expected_identity table|nil Optional prebound file identity.
--@return table|nil identity Exact verified file identity.
--@return table|nil stats_or_error Write statistics or structured failure.
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
    ---Refills the comparison buffer from the opened file.
    --@param none No arguments.
    --@return boolean|nil filled True when buffered or EOF is observed.
    --@return table|nil err Structured read or progress failure.
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
    ---Checks one canonical output chunk against the streamed file bytes.
    --@param expected string Next canonical XML chunk.
    --@return boolean matched Whether the chunk matches exactly.
    --@return string|nil reason Mismatch or read failure message.
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

---Verifies byte identity and a second semantic parse before publication.
--@param schema table Context schema reader/writer.
--@param filesystem table Bounded filesystem port.
--@param path string Candidate file path.
--@param document table Expected canonical Context generation.
--@param expected_identity table|nil Optional bound file identity.
--@param limits table Maximum Context byte limit.
--@return table|nil identity Stable verified file identity.
--@return table parsed_or_error Parsed Context document or structured failure.
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

---Copies a stable Context generation into a new identity-bound previous file.
--@param filesystem table Bounded filesystem port.
--@param source_path string Current Context source path.
--@param source_identity table Expected source file identity.
--@param target_path string New previous-generation path.
--@param limits table Maximum bytes and file permissions.
--@return table|nil identity Verified copy identity.
--@return table|nil err Structured copy or identity failure.
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

---Checks generation, name, view, and immutable Fact prefix before publication.
--@param state table Active writer state and base document.
--@param document table Candidate canonical next generation.
--@param expected_name string|nil Override for a move destination name.
--@return table|nil canonical Internal canonical state on success.
--@return table|nil err Structured history or generation failure.
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

---Observes whether a control path exists and records its file identity.
--@param filesystem table Bounded filesystem port.
--@param path string Lock or previous-generation path.
--@return string|nil state Present or absent observation.
--@return table|nil identity_or_error File identity or structured failure.
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
--@param schema table Context schema service returned by M.new.
--@param ports table Contains the bounded filesystem service.
--@param options table Mandatory release storage limits and permissions.
--@return table|nil store Immutable Context store service.
--@return table|nil err Structured dependency or limit failure.
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
    --@metatable writer_states Associates writer proxies with their private store, document and lease state; collection does not release leases.
    --@field __mode string Fixed k mode: keys are weak; entries remain mutable within their owning module.
    local writer_states = setmetatable({}, { __mode = "k" })
    --@metatable repair_plans Associates proposed repairs with private inspected facts used to reject stale or foreign plans.
    --@field __mode string Fixed k mode: keys are weak; entries remain mutable within their owning module.
    local repair_plans = setmetatable({}, { __mode = "k" })

    ---Wraps a leased Context writer state in an opaque read-only handle.
    --@param state table Active lease and target generation state.
    --@return table writer Opaque writer handle owned by this store.
    local function new_writer(state)
        local writer = readonly({}, "Context writer")
        state.owner = owner
        state.status = "active"
        state.commit_active = false
        state.leases = state.leases or { state.lease }
        writer_states[writer] = state
        return writer
    end

    ---Releases a failed setup lease while preserving uncertain-release evidence.
    --@param lease table Lease acquired before writer setup failed.
    --@param original_error table Structured setup failure.
    --@return nil No writer is returned after setup failure.
    --@return table err Original failure or unknown-lease failure.
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

    ---Limits previous-generation recovery to missing or malformed official XML.
    --@param error_value table Read failure for the official Context.
    --@return boolean recoverable Whether previous-valid recovery may be attempted.
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

    ---Restores a valid previous generation under the already-held writer lease.
    --@param path string Official Context path.
    --@param previous_path string Previous-valid control path.
    --@param official_error table Original official-file read failure.
    --@return table|nil document Restored canonical Context.
    --@return table identity_or_error Restored identity or structured failure.
    --@return boolean retain_lease Whether uncertainty requires retaining the lease.
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

    ---Acquires the writer lease and binds a create or replace target generation.
    --@param path string Official Context path.
    --@param metadata table Lock-owner metadata.
    --@param mode string Create or replace writer mode.
    --@param expected_credential table|nil Selected target identity and Header.
    --@return table|nil writer Opaque active writer handle.
    --@return table|nil document_or_error Current document or structured failure.
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

    ---Acquires a deletion lease bound to the exact file object without XML parse.
    --@param path string Official Context path.
    --@param metadata table Lock-owner metadata.
    --@param expected_credential table|nil Selected file identity.
    --@return table|nil writer Opaque deletion writer handle.
    --@return table|nil err Structured path, lease, or identity failure.
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
    --@param path string In-place imported Context path.
    --@param expected_credential table|nil Selected target identity and Header.
    --@return table|nil document Immutable validated imported Context.
    --@return table report_or_error Read-only audit report or structured failure.
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
        local restated, current_identity = filesystem.stat_identity(path)
        if not restated or not identity_equal(identity_or_error, current_identity) then
            return nil, failure("TargetChanged", "Context path changed during read-only validation")
        end
        lock_state, lock_identity_or_error = control_path_state(filesystem, path .. ".yaca-lock")
        if not lock_state then return nil, lock_identity_or_error end
        if lock_state == "present" then
            return nil, failure("LockConflict", "a Context writer started during read-only validation")
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

    ---Reads only canonical catalog metadata when no writer lease is present.
    -- This never parses Session, Facts, or ModelView and never acquires a lock.
    --@param path string Context path to inspect.
    --@param expected_credential table|nil Selected target identity and Header.
    --@return table|nil header Canonical Context Header.
    --@return table report_or_error Header-only report or structured failure.
    function store.inspect_catalog_header(path, expected_credential)
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
                "active Context writer blocks catalog Header inspection"
            )
        end
        local header, identity_or_error, stats = stable_header_read(
            schema,
            filesystem,
            path,
            limits
        )
        if not header then return nil, identity_or_error end
        if header.header.name ~= target.name then
            return nil, failure(
                "ContextNameMismatch",
                "Context Header Name does not match its catalog basename"
            )
        end
        if expected_credential ~= nil
            and not credential_matches(
                expected_credential,
                path,
                identity_or_error,
                header
            )
        then
            return nil, failure(
                "TargetChanged",
                "catalog Context changed during Header inspection"
            )
        end
        return header.header, assert(freeze({
            outcome = "header-validated-readonly",
            path = path,
            generation = header.generation,
            schema_version = header.schema_version,
            bytes_read = stats.bytes,
            body_opened = false,
        }, "Context catalog inspection"))
    end

    ---Acquires a long-lived writer lease before reading an existing Context body.
    --@param path string Existing official Context path.
    --@param metadata table Lock-owner metadata.
    --@param expected_credential table|nil Selected target identity and Header.
    --@return table|nil writer Opaque active writer handle.
    --@return table document_or_error Current document or structured failure.
    function store.open_writer(path, metadata, expected_credential)
        return acquire(path, metadata, "replace", expected_credential)
    end

    ---Acquires a long-lived writer lease for a not-yet-published Context path.
    --@param path string New official Context path.
    --@param metadata table Lock-owner metadata.
    --@return table|nil writer Opaque active writer handle.
    --@return table|nil err Structured path, lease, or target failure.
    function store.create_writer(path, metadata)
        return acquire(path, metadata, "create")
    end

    ---Acquires a mutation lease and exact identity without parsing the XML body.
    -- This permits confirmed deletion of a corrupt Context while still binding
    -- the operation to the selected file object.
    --@param path string Existing official Context path.
    --@param metadata table Lock-owner metadata.
    --@param expected_credential table|nil Selected file identity.
    --@return table|nil writer Opaque identity-bound delete writer.
    --@return table|nil err Structured path, lease, or identity failure.
    function store.open_delete_writer(path, metadata, expected_credential)
        return acquire_delete(path, metadata, expected_credential)
    end

    ---Inspects one repair path and rejects redirected ancestry or non-file targets.
    --@param path string Official, previous, lock, or temporary path.
    --@return table|nil snapshot Direct filesystem observation.
    --@return table|nil err Structured unsafe-path or inspection failure.
    local function repair_file(path)
        local inspected, snapshot = filesystem.direct_inspect(path)
        if not inspected then return nil, snapshot end
        if snapshot.requested_path ~= path or snapshot.canonical_path ~= path
            or snapshot.ancestry_complete ~= true
            or type(snapshot.parent_identity) ~= "table" or snapshot.parent_identity.kind ~= "directory"
            or type(snapshot.ancestors) ~= "table" or #snapshot.ancestors == 0
        then
            return nil, failure("NoSafeRepair", "repair path has unverified ancestry")
        end
        for _, ancestor in ipairs(snapshot.ancestors) do
            if type(ancestor.identity) ~= "table" or ancestor.identity.kind ~= "directory" then
                return nil, failure("NoSafeRepair", "repair path contains a redirected ancestor")
            end
        end
        if snapshot.exists and (snapshot.identity.kind ~= "file"
            or type(snapshot.metadata) ~= "table" or snapshot.metadata.link_target ~= false)
        then
            return nil, failure("NoSafeRepair", "repair requires ordinary files without redirection")
        end
        return snapshot
    end

    ---Rechecks every repair identity and exact source document before mutation.
    --@param plan table Opaque inspection facts bound to a repair proposal.
    --@param own_lease boolean|nil Whether this transaction owns the lock path.
    --@return boolean|nil valid True while all inspected facts remain current.
    --@return table|nil err Structured changed-target or read failure.
    local function verify_repair_plan(plan, own_lease)
        for _, snapshot in ipairs(own_lease and { plan.official, plan.previous }
            or { plan.lock, plan.official, plan.previous }) do
            local current, current_error = filesystem.direct_reverify(snapshot)
            if not current then
                return nil, failure("TargetChanged", "repair source or target changed after inspection",
                    current_error and current_error.code)
            end
        end
        local source_path = plan.action == "restore-previous" and plan.previous.requested_path or plan.path
        local document, document_error = stable_read(schema, filesystem, source_path, limits)
        if not document then return nil, document_error end
        if not deep_equal(document_states[document], document_states[plan.document]) then
            return nil, failure("TargetChanged", "repair source body changed after inspection")
        end
        for _, snapshot in ipairs(own_lease and { plan.official, plan.previous }
            or { plan.lock, plan.official, plan.previous }) do
            local current, current_error = filesystem.direct_reverify(snapshot)
            if not current then
                return nil, failure("TargetChanged", "repair files changed during source validation",
                    current_error and current_error.code)
            end
        end
        return true
    end

    ---Inspects only the official and its named previous file, without a lease
    -- or recovery. The returned opaque plan binds every source and destination.
    --@param path string Official Context path.
    --@param credential table Selected target identity and Header evidence.
    --@return table|nil proposal Immutable repair proposal.
    --@return table document_or_error Source document or structured failure.
    function store.plan_repair(path, credential)
        for _, name in ipairs({ "direct_inspect", "direct_reverify", "direct_replace", "direct_rename" }) do
            if type(filesystem[name]) ~= "function" then
                return nil, failure("NoSafeRepair", "verified repair filesystem operations are unavailable")
            end
        end
        local target, target_error = validate_context_target(path)
        if not target then return nil, target_error end
        local lock, lock_error = repair_file(path .. ".yaca-lock")
        if not lock then return nil, lock_error end
        if lock.exists then return nil, failure("LockConflict", "repair never breaks an existing writer lock") end
        local official, official_error = repair_file(path)
        if not official then return nil, official_error end
        local previous, previous_error = repair_file(path .. ".yaca-prev")
        if not previous then return nil, previous_error end
        if type(credential) ~= "table" or credential.physical_path ~= path then
            return nil, failure("InvalidTargetCredential", "repair requires an exact selected target")
        end
        if official.exists then
            local valid, valid_error = validate_target_credential(credential, path)
            if not valid then return nil, valid_error end
            if not credential_matches(credential, path, official.identity) then
                return nil, failure("TargetChanged", "selected repair target changed")
            end
        else
            local valid, valid_error = validate_target_credential({ physical_path = path,
                logical_path = credential.logical_path, observed_stat = credential.recovery_stat }, path)
            if not valid then return nil, valid_error end
            if credential.observed_stat ~= nil or not previous.exists
                or not identity_equal(credential.recovery_stat, previous.identity)
            then
                return nil, failure("TargetChanged", "selected previous-only target changed")
            end
        end
        local document, read_error
        if official.exists then document, read_error = stable_read(schema, filesystem, path, limits)
        else read_error = failure("NotFound", "official XML is missing") end
        if not document and not recoverable_official_error(read_error) then
            return nil, failure("NoSafeRepair", "official XML failure has no safe automatic repair", read_error.code)
        end
        local prior
        if previous.exists then
            prior, previous_error = stable_read(schema, filesystem, previous.requested_path, limits)
            if not prior then
                return nil, failure("NoSafeRepair", "previous file is not a valid Context", previous_error.code)
            end
            if prior.header.name ~= target.name
                or (credential.created_at and prior.header.created_at ~= credential.created_at)
            then
                return nil, failure("NoSafeRepair", "previous file belongs to another Context")
            end
        end
        local action
        if document then
            if document.header.name ~= target.name or not credential_matches(credential, path, official.identity, document) then
                return nil, failure("TargetChanged", "repair target header changed")
            end
            action = prior and "clean-previous" or "no-repair-needed"
            if prior then
                if prior.header.created_at ~= document.header.created_at or prior.generation > document.generation
                    or prior.event_count > document.event_count
                then
                    return nil, failure("NoSafeRepair", "previous file is not an earlier generation of this Context")
                end
                for index = 1, prior.event_count do
                    if not deep_equal(prior.facts[index], document.facts[index]) then
                        return nil, failure("NoSafeRepair", "previous history is not a prefix of the official history")
                    end
                end
            end
        elseif prior then
            action, document = "restore-previous", prior
        else
            return nil, failure("NoSafeRepair", "no validated previous generation is available")
        end
        local plan = { path = path, target = target, official = official, previous = previous,
            lock = lock, document = document, action = action }
        local valid, valid_error = verify_repair_plan(plan)
        if not valid then return nil, valid_error end
        local proposal = assert(freeze({ action = action, path = path,
            source_path = action == "restore-previous" and previous.requested_path or path,
            previous_path = previous.requested_path, official_exists = official.exists,
            generation = document.generation, auto_replay = false,
        }, "read-only Context repair plan"))
        repair_plans[proposal] = plan
        return proposal, document
    end

    ---Publishes one confirmed repair generation while retaining the previous
    -- source until the new official has been flushed and verified.
    --@param proposal table Opaque proposal returned by plan_repair.
    --@param document table Audited next canonical repair generation.
    --@param temporary_path string New same-directory Context temporary path.
    --@param metadata table Lock-owner metadata.
    --@return table|nil receipt Confirmed repair outcome.
    --@return table|nil err Structured failure or unknown-publication result.
    function store.apply_repair(proposal, document, temporary_path, metadata)
        local plan = repair_plans[proposal]
        if not plan then return nil, failure("InvalidRepairPlan", "repair plan is stale or foreign") end
        repair_plans[proposal] = nil
        local verified, verify_error = verify_repair_plan(plan)
        if not verified then return nil, verify_error end
        if plan.action == "no-repair-needed" then
            return assert(freeze({ outcome = "unchanged", path = plan.path,
                generation = plan.document.generation, auto_replay = false }, "Context repair receipt"))
        end
        local canonical, canonical_error = validate_publication_document({ mode = "replace",
            target = plan.target, base_document = plan.document }, document)
        if not canonical then return nil, canonical_error end
        local warning = document.facts[plan.document.event_count + 1]
        local expected_error = plan.action == "restore-previous" and "PreviousValidRestored" or "PreviousValidCleaned"
        if document.event_count ~= plan.document.event_count + 2 or warning.type ~= "warning"
            or warning.fields.errorId ~= expected_error
        then
            return nil, failure("InvalidRepairPlan", "repair generation omits the confirmed repair audit")
        end
        local valid_temp, temp_error = validate_temp_path(plan.path, temporary_path, limits)
        if not valid_temp then return nil, temp_error end
        local lock_bytes, metadata_error = encode_lock_metadata(metadata, limits)
        if not lock_bytes then return nil, metadata_error end
        local acquired, lease = filesystem.acquire_lease(plan.lock.requested_path, lock_bytes, limits.lock_permissions)
        if not acquired then return nil, lease end
        local temporary_identity, publication_attempted, published = nil, false, false
        ---Executes a repair after renewed identity checks under the lease.
        --@param none No arguments; uses bound repair proposal and paths.
        --@return table|nil receipt Confirmed repaired Context outcome.
        --@return table|nil err Structured transaction failure.
        local function transact()
            local current, current_error = verify_repair_plan(plan, true)
            if not current then return nil, current_error end
            local written, write_error = write_new_document(schema, filesystem, temporary_path, document, limits)
            if not written then return nil, write_error end
            temporary_identity = written
            local checked, check_error = verify_document_path(schema, filesystem, temporary_path,
                document, temporary_identity, limits)
            if not checked then return nil, check_error end
            local temporary, inspect_error = repair_file(temporary_path)
            if not temporary then return nil, inspect_error end
            if not identity_equal(temporary.identity, checked) then
                return nil, failure("TargetChanged", "repair temporary changed before publication")
            end
            current, current_error = verify_repair_plan(plan, true)
            if not current then return nil, current_error end
            publication_attempted = true
            local moved, move_error
            if plan.official.exists then moved, move_error = filesystem.direct_replace(temporary, plan.official)
            else moved, move_error = filesystem.direct_rename(temporary, plan.official) end
            if not moved then
                if move_error.code == "TargetChanged" or move_error.code == "IdentityChanged"
                    or move_error.code == "DestinationExists"
                then publication_attempted = false end
                return nil, move_error
            end
            published = true
            local flushed, flush_error = filesystem.flush_directory(plan.target.directory)
            if not flushed then return nil, flush_error end
            checked, check_error = verify_document_path(schema, filesystem, plan.path, document, nil, limits)
            if not checked then return nil, check_error end
            current, current_error = filesystem.direct_reverify(plan.previous)
            if not current then return nil, current_error end
            local cleaned, cleanup_error = filesystem.delete_verified(plan.previous.requested_path, plan.previous.identity)
            if not cleaned then return nil, cleanup_error end
            flushed, flush_error = filesystem.flush_directory(plan.target.directory)
            if not flushed then return nil, flush_error end
            local final_identity, final_error = verify_document_path(schema, filesystem, plan.path,
                document, checked, limits)
            if not final_identity then return nil, final_error end
            return assert(freeze({ outcome = plan.action == "restore-previous" and "restored-previous" or "cleaned-previous",
                path = plan.path, generation = document.generation, event_count = document.event_count,
                auto_replay = false, auto_continue = false }, "Context repair receipt"))
        end
        local called, receipt, repair_error = pcall(transact)
        if not publication_attempted and temporary_identity then
            local clean_called, cleaned = pcall(cleanup_file, filesystem, temporary_path, temporary_identity)
            if not clean_called or not cleaned then publication_attempted = true end
        end
        local release_called, released = pcall(filesystem.release_lease, lease)
        if not called or not release_called or not released or (not receipt and (publication_attempted or published)) then
            return nil, failure("ContextRepairUnknown", "repair publication or cleanup is uncertain",
                type(repair_error) == "table" and repair_error.code or nil)
        end
        return receipt, repair_error
    end

    ---Runs only evidence-safe previous-valid recovery under the normal lease.
    -- A stale-looking lock remains a conflict; age is never repair evidence.
    --@param path string Official Context path.
    --@param metadata table Lock-owner metadata.
    --@param expected_credential table|nil Selected target identity and Header.
    --@return table|nil writer Active repaired Context writer.
    --@return table document_or_error Current document or structured failure.
    --@return table|nil receipt Recovery outcome on success.
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
    --@param writer table Active writer issued by this store.
    --@param document table Canonical next Context generation.
    --@param temporary_path string New same-directory temporary path.
    --@return table|nil receipt Confirmed publication outcome.
    --@return table|nil err Structured failure or unknown-publication result.
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
        local capacity, capacity_error = check_publication_capacity(schema_state, canonical, limits)
        if not capacity then return nil, capacity_error end
        state.commit_active = true

        ---Clears the publication mutex before returning a result.
        --@param value any Success value or nil.
        --@param error_value table|nil Structured failure.
        --@return any value Unchanged transaction result.
        --@return table|nil err Unchanged failure.
        local function finish(value, error_value)
            state.commit_active = false
            return value, error_value
        end
        ---Faults the writer after an unsafe publication state.
        --@param code string Structured failure code.
        --@param message string Human-readable failure message.
        --@param reason string|nil Underlying reason code.
        --@return nil No receipt is issued.
        --@return table err Structured fault result.
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
            unfinished_turn_ids = document.recovery.unfinished_turn_ids,
            active_queue_item_ids = document.recovery.active_queue_item_ids,
            target_qualified = filesystem.capabilities.target_qualified,
        }, "Context publication receipt"))
        return finish(receipt)
    end

    ---Moves a complete lifecycle generation to a new official path no-replace.
    -- Same-directory moves are rename transactions; cross-directory moves are
    -- explicit rebind transactions. The old official is hidden as the one
    -- recognized previous-valid generation before the new path is published,
    -- so Catalog observation never treats both paths as active Contexts.
    --@param writer table Active replace writer issued by this store.
    --@param document table Canonical lifecycle generation with move Fact.
    --@param destination_path string New official Context path.
    --@param temporary_path string New destination-side temporary path.
    --@param action string|nil Rename or rebind; inferred from parent directory.
    --@return table|nil receipt Confirmed move outcome.
    --@return table|nil err Structured failure or unknown-move result.
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
        local capacity, capacity_error = check_publication_capacity(schema_state, canonical, limits)
        if not capacity then return nil, capacity_error end
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

        ---Clears the move publication mutex before returning a result.
        --@param value any Success value or nil.
        --@param error_value table|nil Structured failure.
        --@return any value Unchanged transaction result.
        --@return table|nil err Unchanged failure.
        local function finish(value, error_value)
            state.commit_active = false
            return value, error_value
        end
        ---Faults a writer after unsafe move or destination state.
        --@param code string Structured failure code.
        --@param message string Human-readable failure message.
        --@param reason string|nil Underlying reason code.
        --@return nil No receipt is issued.
        --@return table err Structured fault result.
        local function fault(code, message, reason)
            state.status = "faulted"
            return finish(nil, failure(code, message, reason))
        end
        ---Keeps the destination lease when move outcome cannot be established.
        --@param none No arguments.
        --@return nil Moves lease ownership into writer state if present.
        local function retain_destination_lease()
            if destination_lease then
                state.leases[#state.leases + 1] = destination_lease
                destination_lease = nil
            end
        end
        ---Reports an uncertain move while retaining both relevant leases.
        --@param message string Human-readable uncertainty message.
        --@param reason string|nil Underlying reason code.
        --@return nil No confirmed move receipt.
        --@return table err Structured unknown-move failure.
        local function move_unknown(message, reason)
            retain_destination_lease()
            return fault("ContextMoveUnknown", message, reason)
        end
        ---Releases destination lease after a confirmed pre-publication failure.
        --@param original_error table Structured transaction failure.
        --@return nil No move receipt.
        --@return table err Original failure or unknown-lease failure.
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
    --@param writer table Active replace or delete writer.
    --@param temporary_or_options string|table|nil Optional delete temporary path.
    --@return table|nil receipt Confirmed per-target deletion or partial outcome.
    --@return table|nil err Structured pre-deletion failure.
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
        ---Captures the exact identity or absence of one deletion target.
        --@param role string Official, temporary, or previous-valid role.
        --@param path string Physical path for that role.
        --@param known_identity table|nil Already verified official identity.
        --@return table observation Role, path, and identity or observation error.
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
    --@param writer table Writer issued by this store.
    --@return boolean|nil closed True when all owned leases were released.
    --@return table|nil err Structured stale-writer or lease-release failure.
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
    --@param writer table Writer issued by this store.
    --@return table|nil status Immutable lifecycle status.
    --@return table|nil err Structured foreign-writer failure.
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

    ---Revalidates the owned official file without scanning, recovery, or writes.
    -- A changed identity or canonical document permanently faults this writer;
    -- the caller must stop admission and close it, never follow another path.
    --@param writer table Opaque writer issued by this store.
    --@return table|nil status Current path and generation when still exact.
    --@return table|nil err Stale writer, active publication, or target failure.
    function store.verify_writer(writer)
        local state = writer_states[writer]
        if not state or state.owner ~= owner or state.status ~= "active"
            or not state.base_document
        then
            return nil, failure("InvalidContextWriter", "Context writer is stale or foreign")
        end
        if state.commit_active then
            return nil, failure("ContextCommitConflict", "Context publication is active")
        end
        local current, identity_or_error = stable_read(schema, filesystem, state.path, limits)
        if not current or not identity_equal(state.base_identity, identity_or_error)
            or not deep_equal(document_states[current], document_states[state.base_document])
        then
            state.status = "faulted"
            return nil, failure(
                "TargetChanged",
                "the active Context file changed; close and select it again",
                current and "identity-or-document" or identity_or_error.code
            )
        end
        -- The reader handle can still refer to an unlinked or replaced file.
        local stated, path_identity = filesystem.stat_identity(state.path)
        if not stated or not identity_equal(state.base_identity, path_identity) then
            state.status = "faulted"
            return nil, failure("TargetChanged", "the active Context path changed during inspection")
        end
        return store.writer_status(writer)
    end

    ---Inspects only bounded public lease metadata and never opens Context XML.
    -- A malformed or unreadable lease remains busy with an unknown PID; this
    -- method never treats age, hostname, or parse failure as stale evidence.
    --@param path string Official Context path whose lock is inspected.
    --@return table|nil inspection Bounded busy state and public lock metadata.
    --@return table|nil err Structured target-path failure.
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
        bounded_header_inspection = true,
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
