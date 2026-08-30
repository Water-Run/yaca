--[[
File: context_schema_test.lua
Date: 2026-08-29
Author: WaterRun
Description: Verifies the canonical Context event and document model.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

local function load_module(name, cache)
    cache = cache or {}
    if cache[name] then return cache[name] end
    local environment = { require = function(dependency)
        return load_module(dependency, cache)
    end }
    environment._G = environment
    setmetatable(environment, { __index = _ENV })
    local chunk, load_error = loadfile(
        YACA_TEST_ROOT .. "/src/" .. name .. ".lua",
        "t",
        environment
    )
    A.truthy(chunk, load_error)
    local value = chunk()
    cache[name] = value
    return value
end

local function load_table(relative_path)
    local chunk, load_error = loadfile(YACA_TEST_ROOT .. "/" .. relative_path, "t", _ENV)
    A.truthy(chunk, load_error)
    return chunk()
end

local cache = {}
local context = load_module("context", cache)
local xml = load_module("xml", cache)
local fake_lxp = load_table("test/support/fake_lxp.lua")
local sha256 = load_table("test/support/sha256_reference.lua")
local contract = load_table(".develope-docs/contracts/context.lua")

local function new_service(overrides, lxp_override)
    local lxp = lxp_override or fake_lxp(function()
        return false, "schema test reader is not configured", 1, 1, 1
    end)
    local codec = assert(xml.new({
        lxp = lxp,
        maximum_bytes = 1024 * 1024,
        maximum_depth = 32,
        maximum_elements = 4096,
        maximum_attributes_per_element = 8,
        maximum_text_node_bytes = 131072,
        maximum_total_text_bytes = 512 * 1024,
        maximum_sax_events = 16384,
        maximum_context_events = 256,
        maximum_carrier_bytes = 65536,
        maximum_chunk_bytes = 31,
    }))
    local options = {
        xml = codec,
        safety = { digest = sha256.hex },
        maximum_name_bytes = 256,
        maximum_identifier_bytes = 256,
        maximum_field_name_bytes = 64,
        maximum_field_bytes = 65536,
        maximum_events = 256,
        maximum_compaction_records = 64,
        maximum_export_bytes = 1024 * 1024,
    }
    for key, value in pairs(overrides or {}) do options[key] = value end
    return assert(context.new(options)), options
end

local function minimal()
    return {
        schema_version = "0.1.0",
        generation = 1,
        header = {
            name = "Untitled Conversation [0A1B]",
            created_at = "2026-08-29T00:00:00Z",
            updated_at = "2026-08-29T00:00:01Z",
            auto_rename_disabled = false,
            naming_waterline = 0,
            auto_name_baseline = 0,
        },
        session = {
            current_model = { name = "Local", snapshot_digest = "sha256:model-snapshot" },
            current_permission = {
                name = "Std", snapshot_digest = "sha256:permission-snapshot",
            },
            double_check_override = "inherit",
            double_check_goal_override = { mode = "inherit" },
            context_prompt = "",
        },
        facts = {
            {
                seq = 1,
                type = "turn_started",
                at = "2026-08-29T00:00:00Z",
                turn_id = "turn-1",
                fields = {
                    kind = "main",
                    configGeneration = "sha256:config-generation",
                    modelSnapshot = "sha256:model-snapshot",
                    permissionSnapshot = "sha256:permission-snapshot",
                    promptSnapshot = "sha256:prompt-snapshot",
                    toolRegistrySnapshot = "sha256:tool-registry",
                    runtimeSnapshot = "yaca-runtime-snapshot-v1;hard=manifest-v1",
                },
            },
            {
                seq = 2,
                type = "user_message",
                at = "2026-08-29T00:00:01Z",
                turn_id = "turn-1",
                fields = { messageId = "message-1", text = "hello", source = "main" },
            },
        },
        model_view = {
            active_manifest = {
                digest = "sha256:view-manifest",
                first_event_seq = 1,
                last_event_seq = 2,
            },
            compaction_records = {},
        },
    }
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function append(candidate, type_name, fields, extras)
    local item = {
        seq = #candidate.facts + 1,
        type = type_name,
        at = "2026-08-29T00:00:01Z",
        turn_id = "turn-1",
        fields = fields,
    }
    for key, value in pairs(extras or {}) do item[key] = value end
    candidate.facts[#candidate.facts + 1] = item
    candidate.model_view.active_manifest.last_event_seq = #candidate.facts
    return item
end

local EXPECTED_EVENTS = {
    "turn_started", "user_message", "queue_item", "model_request", "model_message",
    "model_control", "model_yield", "tool_call", "permission_decision", "approval",
    "operation_intent", "operation_result", "tool_result", "action_review",
    "termination_review", "turn_ended", "cancel", "steer", "compaction",
    "model_view_published", "session_override", "rename", "rebind", "auto_name",
    "config_generation_ref", "warning", "unknown_side_effect", "import_mapping",
}

local function incremental_header_lxp(observations)
    local function emit(callbacks, name, value)
        callbacks.StartElement(nil, name, {})
        callbacks.CharacterData(nil, value)
        callbacks.EndElement(nil, name)
    end
    local module = {
        _VERSION = "LuaExpat 1.5.2",
        _EXPAT_VERSION = "expat_2.8.2",
        _EXPAT_FEATURES = { sizeof_XML_Char = 1 },
    }
    function module.new(callbacks)
        local parser = { closed = false, emitted = false }
        function parser.parse(self, chunk)
            if chunk ~= nil and not self.emitted then
                self.emitted = true
                observations.feeds = observations.feeds + 1
                callbacks.XmlDecl(nil, "1.0", "UTF-8")
                callbacks.StartElement(nil, "YacaContext", {
                    schemaVersion = "0.1.0",
                    generation = "7",
                })
                callbacks.CharacterData(nil, "\n  ")
                callbacks.StartElement(nil, "Header", {})
                emit(callbacks, "Name", "Task")
                emit(callbacks, "CreatedAt", "2026-08-29T00:00:00Z")
                emit(callbacks, "UpdatedAt", "2026-08-29T00:00:01Z")
                callbacks.EndElement(nil, "Header")
                return true
            end
            if chunk ~= nil then observations.feeds = observations.feeds + 1 end
            return true
        end
        function parser.pos() return 1, 1, 1 end
        function parser.close(self)
            self.closed = true
            observations.closes = observations.closes + 1
            return true
        end
        return parser
    end
    return module
end

return {
    name = "unit/context-schema",
    cases = {
        {
            name = "event registry is the exact frozen 28-type semantic schema",
            run = function()
                local service = new_service()
                A.deep_equal(service.event_types, EXPECTED_EVENTS)
                local contract_types = {}
                for index, definition in ipairs(contract.event_types) do
                    contract_types[index] = definition.id
                    local runtime = assert(service.event_schema(definition.id))
                    A.deep_equal(runtime.required, definition.required, definition.id)
                    A.deep_equal(runtime.optional, definition.optional, definition.id)
                end
                A.deep_equal(service.event_types, contract_types)
                A.deep_equal(service.event_schema("user_message").required, {
                    "messageId", "text", "source",
                })
                A.deep_equal(service.event_schema("user_message").optional, {
                    "replyToMessageId",
                })
                A.deep_equal(service.event_schema("tool_result").required, {
                    "toolCallId", "status", "body", "truncated",
                })
                A.deep_equal(service.event_schema("tool_result").optional, {
                    "rawBytes", "digest", "errorId",
                })
                local unknown, unknown_error = service.event_schema("token_delta")
                A.falsy(unknown)
                A.equal(unknown_error.code, "UnknownContextEvent")
                A.raises(function() service.event_types[1] = "changed" end,
                    "cannot be modified")
                A.raises(function() service.extra = true end, "cannot be modified")
            end,
        },
        {
            name = "minimal documents freeze exact header session Facts and empty identity",
            run = function()
                local service = new_service()
                local candidate = minimal()
                append(candidate, "turn_ended", {
                    outcome = "completed",
                    reason = "",
                })
                local document = assert(service.build(candidate))
                A.equal(document.schema_version, "0.1.0")
                A.equal(document.generation, 1)
                A.equal(document.header.name, "Untitled Conversation [0A1B]")
                A.falsy(document.header.auto_rename_disabled)
                A.equal(document.session.context_prompt, "")
                A.equal(document.facts[3].fields.reason, "")
                A.equal(document.facts[3].fields.errorId, nil)
                A.equal(
                    document.facts[1].fields.runtimeSnapshot,
                    "yaca-runtime-snapshot-v1;hard=manifest-v1"
                )
                A.equal(document.event_count, 3)
                A.equal(document.last_event_seq, 3)
                A.equal(document.recovery.model_view_status, "current")
                A.truthy(document.recovery.auto_continue)
                A.raises(function() document.header.name = "changed" end,
                    "cannot be modified")
                A.raises(function() document.facts[1].fields.kind = "side" end,
                    "cannot be modified")

                candidate.header.name = "mutated after build"
                candidate.facts[1].fields.kind = "side"
                A.equal(document.header.name, "Untitled Conversation [0A1B]")
                A.equal(document.facts[1].fields.kind, "main")
            end,
        },
        {
            name = "recovery projects unfinished lanes and every canonical Runtime serial waterline",
            run = function()
                local service = new_service()
                local unfinished = assert(service.build(minimal()))
                A.falsy(unfinished.recovery.auto_continue)
                A.deep_equal(unfinished.recovery.unfinished_turn_ids, { "turn-1" })
                A.deep_equal(unfinished.recovery.active_queue_item_ids, {})

                local queued_candidate = minimal()
                append(queued_candidate, "queue_item", {
                    queueItemId = "queue-item-3",
                    displayId = "#2",
                    action = "enqueue",
                    text = "later",
                })
                queued_candidate.facts[#queued_candidate.facts].turn_id = nil
                local queued = assert(service.build(queued_candidate))
                A.deep_equal(queued.recovery.active_queue_item_ids, { "queue-item-3" })
                A.falsy(queued.recovery.auto_continue)

                local candidate = minimal()
                candidate.facts[1].turn_id = "turn-12"
                candidate.facts[2].turn_id = "turn-12"
                candidate.facts[2].fields.messageId = "turn-12:message:31"
                local function add(type_name, fields, turn_id)
                    append(candidate, type_name, fields)
                    candidate.facts[#candidate.facts].turn_id = turn_id
                end
                add("model_request", {
                    requestId = "turn-12:request:17",
                    purpose = "main",
                    viewManifestRef = "sha256:view-manifest",
                }, "turn-12")
                add("tool_call", {
                    toolCallId = "turn-12:tool:8",
                    requestId = "turn-12:request:17",
                    name = "exec",
                    canonicalArguments = "{}",
                }, "turn-12")
                add("operation_intent", {
                    operationId = "turn-12:operation:7",
                    toolCallId = "turn-12:tool:8",
                    kind = "exec",
                    targetIdentity = "workspace",
                    expectedDigest = "opaque",
                }, "turn-12")
                add("operation_result", {
                    operationId = "turn-12:operation:7",
                    status = "ok",
                    evidence = "complete",
                }, "turn-12")
                add("tool_result", {
                    toolCallId = "turn-12:tool:8",
                    status = "ok",
                    body = "done",
                    truncated = "false",
                }, "turn-12")
                add("model_message", {
                    messageId = "turn-12:message:32",
                    requestId = "turn-12:request:17",
                    role = "assistant",
                    status = "complete",
                    body = "done",
                }, "turn-12")
                add("turn_ended", { outcome = "completed", reason = "" }, "turn-12")
                add("queue_item", {
                    queueItemId = "queue-item-9",
                    displayId = "#4",
                    action = "enqueue",
                    text = "queued",
                }, nil)
                add("queue_item", {
                    queueItemId = "queue-item-9",
                    displayId = "#4",
                    action = "drop",
                    text = "queued",
                    reason = "test",
                }, nil)
                add("turn_started", {
                    kind = "side",
                    configGeneration = "sha256:config-generation",
                    modelSnapshot = "sha256:model-snapshot",
                    permissionSnapshot = "sha256:permission-snapshot",
                    promptSnapshot = "sha256:prompt-snapshot",
                    toolRegistrySnapshot = "sha256:tool-registry",
                }, "side-6")
                add("user_message", {
                    messageId = "side-6:message:33",
                    text = "inspect",
                    source = "side",
                }, "side-6")
                add("model_request", {
                    requestId = "side-6:request:18",
                    purpose = "side",
                    viewManifestRef = "sha256:view-manifest",
                }, "side-6")
                add("model_message", {
                    messageId = "side-6:message:34",
                    requestId = "side-6:request:18",
                    role = "assistant",
                    status = "complete",
                    body = "observed",
                }, "side-6")
                add("turn_ended", { outcome = "completed", reason = "" }, "side-6")

                local recovered = assert(service.build(candidate))
                A.truthy(recovered.recovery.auto_continue)
                A.deep_equal(recovered.recovery.unfinished_turn_ids, {})
                A.deep_equal(recovered.recovery.active_queue_item_ids, {})
                A.deep_equal(recovered.recovery.runtime_initial_serials, {
                    turn = 12,
                    message = 34,
                    request = 18,
                    tool = 8,
                    operation = 7,
                    queue = 9,
                    queue_display = 4,
                    side = 6,
                })
            end,
        },
        {
            name = "writer follows root section and event field order without forbidden authority",
            run = function()
                local service = new_service()
                local document = assert(service.build(minimal()))
                local encoded, stats = assert(service.encode(document))
                A.truthy(stats.bytes > 0)
                A.contains(encoded, '<?xml version="1.0" encoding="UTF-8"?>\n')
                local root = assert(encoded:find("<YacaContext", 1, true))
                local header = assert(encoded:find("<Header>", 1, true))
                local session = assert(encoded:find("<Session>", 1, true))
                local facts = assert(encoded:find("<Facts>", 1, true))
                local view = assert(encoded:find("<ModelView>", 1, true))
                A.truthy(root < header and header < session and session < facts and facts < view)
                local kind = assert(encoded:find('name="kind"', 1, true))
                local generation = assert(encoded:find('name="configGeneration"', 1, true))
                local model = assert(encoded:find('name="modelSnapshot"', 1, true))
                A.truthy(kind < generation and generation < model)
                for _, forbidden in ipairs({
                    "WorkspaceRoot", "WorkspaceRoots", "ContextId", "<Key>",
                    "Authorization", "ApprovalGrant", "<Wal>", "<Archive>",
                }) do
                    A.falsy(encoded:find(forbidden, 1, true), forbidden)
                end

                local forged = minimal()
                forged.workspace_root = "/secret/root"
                local invalid, invalid_error = service.build(forged)
                A.falsy(invalid)
                A.equal(invalid_error.code, "ContextSchema")
                A.equal(invalid_error.reason, "unknown-field")
                local fake, fake_error = service.encode({})
                A.falsy(fake)
                A.equal(fake_error.code, "InvalidContextDocument")
            end,
        },
        {
            name = "binary event fields use canonical base64 size and SHA-256 metadata",
            run = function()
                local service = new_service()
                local candidate = minimal()
                append(candidate, "model_request", {
                    requestId = "request-1",
                    purpose = "main",
                    viewManifestRef = "sha256:view-manifest",
                })
                append(candidate, "tool_call", {
                    toolCallId = "tool-1",
                    requestId = "request-1",
                    name = "read",
                    canonicalArguments = "{}",
                })
                append(candidate, "permission_decision", {
                    toolCallId = "tool-1",
                    capabilities = "read",
                    decision = "allow",
                    profileSnapshot = "sha256:permission-snapshot",
                })
                append(candidate, "operation_intent", {
                    operationId = "operation-1",
                    toolCallId = "tool-1",
                    kind = "read",
                    targetIdentity = "target-1",
                    expectedDigest = "missing",
                })
                append(candidate, "operation_result", {
                    operationId = "operation-1",
                    status = "ok",
                    evidence = "read-complete",
                })
                local binary = "\0\255\rbytes"
                append(candidate, "tool_result", {
                    toolCallId = "tool-1",
                    status = "ok",
                    body = binary,
                    truncated = "false",
                })
                append(candidate, "turn_ended", { outcome = "completed" })

                local document = assert(service.build(candidate))
                local result = document.facts[8]
                A.equal(result.fields.body, binary)
                A.equal(result.field_metadata.body.representation, "base64")
                A.equal(result.field_metadata.body.raw_bytes, #binary)
                A.equal(result.field_metadata.body.digest, sha256.hex(binary))
                local encoded = assert(service.encode(document))
                A.contains(encoded, 'name="body" representation="base64" rawBytes="8"')
                A.contains(encoded, 'digest="' .. sha256.hex(binary) .. '"')
                A.contains(encoded, "AP8NYnl0ZXM=")
                A.falsy(encoded:find(binary, 1, true))

                local exported = assert(service.export(document))
                A.contains(exported, "base64, 8 bytes")
                A.contains(exported, "sha256=" .. sha256.hex(binary))
                A.contains(exported, "AP8NYnl0ZXM=")
                A.falsy(exported:find("WorkspaceRoot", 1, true))
            end,
        },
        {
            name = "relations expose unresolved side effects and reject duplicate terminal truth",
            run = function()
                local service = new_service()
                local candidate = minimal()
                append(candidate, "model_request", {
                    requestId = "request-1", purpose = "main", viewManifestRef = "view-1",
                })
                append(candidate, "tool_call", {
                    toolCallId = "tool-1", requestId = "request-1", name = "write",
                    canonicalArguments = "{}",
                })
                append(candidate, "operation_intent", {
                    operationId = "operation-1", toolCallId = "tool-1", kind = "write",
                    targetIdentity = "target-1", expectedDigest = "old",
                })
                local pending = assert(service.build(candidate))
                A.deep_equal(pending.recovery.unresolved_operation_ids, { "operation-1" })
                A.deep_equal(pending.recovery.unresolved_tool_call_ids, { "tool-1" })
                A.falsy(pending.recovery.auto_continue)
                A.truthy(service.encode(pending))

                append(candidate, "unknown_side_effect", {
                    operationId = "operation-1",
                    reason = "crash boundary",
                    requiredAction = "inspect",
                })
                local unknown = assert(service.build(candidate))
                A.deep_equal(unknown.recovery.unknown_operation_ids, { "operation-1" })
                A.falsy(unknown.recovery.auto_continue)

                local duplicate = copy(candidate)
                duplicate.facts[#duplicate.facts] = nil
                append(duplicate, "operation_result", {
                    operationId = "operation-1", status = "ok", evidence = "first",
                })
                append(duplicate, "operation_result", {
                    operationId = "operation-1", status = "error", evidence = "second",
                })
                local rejected, relation_error = service.build(duplicate)
                A.falsy(rejected)
                A.equal(relation_error.code, "ContextRelation")
                A.equal(relation_error.reason, "duplicate-operation-result")
            end,
        },
        {
            name = "bound compaction requests expose exact crash recovery state",
            run = function()
                local service = new_service()
                local candidate = minimal()
                append(candidate, "model_request", {
                    requestId = "compaction-41:request:1",
                    purpose = "compaction",
                    viewManifestRef = "view-before-compaction",
                    attemptId = "1",
                    compactionId = "compaction-41",
                    compactionMode = "automatic",
                    sourceFirstSeq = "1",
                    sourceLastSeq = "2",
                    sourceDigest = "source-digest-41",
                    sourceEventCount = "2",
                    configSnapshot = "config-snapshot-41",
                    modelSnapshot = "model-snapshot-41",
                    promptSnapshot = "prompt-snapshot-41",
                    manifestSnapshot = "manifest-compaction-v1",
                    viewContextGeneration = "1",
                })
                local pending = assert(service.build(candidate))
                A.falsy(pending.recovery.auto_continue)
                A.equal(pending.recovery.compaction_initial_serial, 41)
                A.equal(#pending.recovery.pending_compactions, 1)
                local recovered = pending.recovery.pending_compactions[1]
                A.equal(recovered.compaction_id, "compaction-41")
                A.equal(recovered.request_id, "compaction-41:request:1")
                A.equal(recovered.mode, "automatic")
                A.equal(recovered.source_event_count, 2)
                A.equal(recovered.prompt_snapshot, "prompt-snapshot-41")
                A.equal(recovered.response_status, false)
                A.falsy(recovered.cancel_requested)

                append(candidate, "cancel", {
                    targetKind = "compaction-request",
                    targetId = "compaction-41:request:1",
                    reason = "process-recovery",
                    result = "pending",
                })
                local cancelling = assert(service.build(candidate))
                recovered = cancelling.recovery.pending_compactions[1]
                A.truthy(recovered.cancel_requested)
                A.equal(recovered.cancel_reason, "process-recovery")

                local partial = minimal()
                append(partial, "model_request", {
                    requestId = "compaction-42:request:1",
                    purpose = "compaction",
                    viewManifestRef = "view-before-compaction",
                    attemptId = "1",
                    compactionId = "compaction-42",
                })
                local rejected, binding_error = service.build(partial)
                A.falsy(rejected)
                A.equal(binding_error.code, "ContextSchema")
                A.equal(binding_error.reason, "required-field")

                local legacy = minimal()
                append(legacy, "model_request", {
                    requestId = "compaction-77:request:1",
                    purpose = "compaction",
                    viewManifestRef = "legacy-view",
                    attemptId = "1",
                })
                local legacy_pending = assert(service.build(legacy))
                A.deep_equal(
                    legacy_pending.recovery.legacy_pending_compaction_request_ids,
                    { "compaction-77:request:1" }
                )
                A.equal(legacy_pending.recovery.compaction_initial_serial, 77)
                A.falsy(legacy_pending.recovery.auto_continue)
            end,
        },
        {
            name = "durable compaction terminals reconstruct the automatic failure streak",
            run = function()
                local service = new_service()
                local candidate = minimal()
                local function append_failure(serial)
                    local compaction_id = "compaction-" .. tostring(serial)
                    local request_id = compaction_id .. ":request:1"
                    append(candidate, "model_request", {
                        requestId = request_id,
                        purpose = "compaction",
                        viewManifestRef = "view-before-compaction",
                        attemptId = "1",
                        compactionId = compaction_id,
                        compactionMode = "automatic",
                        sourceFirstSeq = "1",
                        sourceLastSeq = "2",
                        sourceDigest = "source-digest",
                        sourceEventCount = "2",
                        configSnapshot = "config-snapshot",
                        modelSnapshot = "model-snapshot",
                        promptSnapshot = "prompt-snapshot",
                        manifestSnapshot = "manifest-compaction-v1",
                        viewContextGeneration = "1",
                    })
                    append(candidate, "model_message", {
                        messageId = request_id .. ":rejected",
                        requestId = request_id,
                        role = "assistant",
                        status = "interrupted",
                        body = "",
                    })
                    append(candidate, "compaction", {
                        compactionId = compaction_id,
                        sourceFirstSeq = "1",
                        sourceLastSeq = "2",
                        sourceDigest = "source-digest",
                        status = "error",
                        errorId = "CompactionRejected",
                        requestId = request_id,
                        attemptId = "1",
                        compactionMode = "automatic",
                        automaticFailure = "true",
                    })
                end
                append_failure(41)
                append_failure(42)
                local recovered = assert(service.build(candidate)).recovery
                A.equal(recovered.automatic_compaction_failure_count, 2)
                A.truthy(recovered.automatic_compaction_failure_history_complete)
                A.equal(recovered.compaction_initial_serial, 42)
                A.equal(#recovered.pending_compactions, 0)
            end,
        },
        {
            name = "queue side steer and yield continuations preserve ordered local causality",
            run = function()
                local service = new_service()
                local candidate = minimal()
                append(candidate, "model_request", {
                    requestId = "request-1", purpose = "main", viewManifestRef = "view-1",
                })
                append(candidate, "model_message", {
                    messageId = "message-yield", requestId = "request-1",
                    role = "assistant", status = "complete", body = "first response",
                })
                append(candidate, "model_yield", {
                    requestId = "request-1", messageId = "message-yield",
                })
                append(candidate, "turn_ended", {
                    outcome = "partial", reason = "superseded-by-new-input",
                })
                local queued = append(candidate, "queue_item", {
                    queueItemId = "queue-item-1", displayId = "#1",
                    action = "enqueue", text = "next",
                })
                queued.turn_id = nil
                local edited = append(candidate, "queue_item", {
                    queueItemId = "queue-item-1", displayId = "#1",
                    action = "edit", text = "next edited",
                })
                edited.turn_id = nil
                local consumed = append(candidate, "queue_item", {
                    queueItemId = "queue-item-1", displayId = "#1",
                    action = "consume", text = "next edited",
                })
                consumed.turn_id = nil
                append(candidate, "turn_started", {
                    kind = "main",
                    configGeneration = "config-2",
                    modelSnapshot = "model-2",
                    permissionSnapshot = "permission-2",
                    promptSnapshot = "prompt-2",
                    toolRegistrySnapshot = "tools-2",
                    queueItemId = "queue-item-1",
                    supersedesResponseId = "message-yield",
                }, { turn_id = "turn-2" })
                append(candidate, "user_message", {
                    messageId = "message-2", text = "next edited", source = "user",
                }, { turn_id = "turn-2" })
                append(candidate, "turn_started", {
                    kind = "side",
                    configGeneration = "config-2",
                    modelSnapshot = "model-2",
                    permissionSnapshot = "permission-2",
                    promptSnapshot = "prompt-2",
                    toolRegistrySnapshot = "tools-2",
                }, { turn_id = "side-1" })
                append(candidate, "user_message", {
                    messageId = "side-message-1", text = "side question", source = "user",
                }, { turn_id = "side-1" })
                append(candidate, "model_request", {
                    requestId = "side-request-1", purpose = "side", viewManifestRef = "view-2",
                }, { turn_id = "side-1" })
                append(candidate, "model_message", {
                    messageId = "side-message-2", requestId = "side-request-1",
                    role = "assistant", status = "complete", body = "side answer",
                }, { turn_id = "side-1" })
                append(candidate, "turn_ended", { outcome = "completed" }, {
                    turn_id = "side-1",
                })
                append(candidate, "steer", {
                    messageId = "steer-message-1", targetTurnId = "turn-2",
                    summary = "use side", sideId = "side-1",
                }, { turn_id = "turn-2" })
                local side_queue = append(candidate, "queue_item", {
                    queueItemId = "queue-item-2", displayId = "#2",
                    action = "enqueue", text = "side answer", sideId = "side-1",
                })
                side_queue.turn_id = nil

                local document = assert(service.build(candidate))
                A.equal(document.facts[10].fields.supersedesResponseId, "message-yield")
                A.equal(document.facts[17].fields.sideId, "side-1")
                A.equal(document.facts[18].fields.sideId, "side-1")

                local forged = copy(candidate)
                forged.facts[#forged.facts].fields.sideId = "turn-2"
                local rejected, relation_error = service.build(forged)
                A.falsy(rejected)
                A.equal(relation_error.code, "ContextRelation")
            end,
        },
        {
            name = "stale ModelView remains readable and exportable but cannot be published",
            run = function()
                local service = new_service()
                local candidate = minimal()
                candidate.model_view.active_manifest.last_event_seq = 99
                local document = assert(service.build(candidate))
                A.equal(document.recovery.model_view_status, "stale")
                A.truthy(document.recovery.rebuild_model_view)
                A.falsy(document.recovery.auto_continue)
                local encoded, stale_error = service.encode(document)
                A.falsy(encoded)
                A.equal(stale_error.code, "StaleModelView")
                A.contains(assert(service.export(document)), "- Status: `stale`")
            end,
        },
        {
            name = "accepted compaction record and ModelView publish atomically",
            run = function()
                local service = new_service()
                local original = assert(service.build(minimal()))
                local summary = "structured durable summary"
                local record = {
                    id = "compaction-1",
                    source_first_seq = 1,
                    source_last_seq = 2,
                    source_digest = "source-digest",
                    status = "ok",
                    summary = summary,
                }
                local mutation = {
                    updated_at = "2026-08-29T00:00:02Z",
                    events = {
                        {
                            seq = 3,
                            type = "compaction",
                            fields = {
                                compactionId = "compaction-1",
                                sourceFirstSeq = "1",
                                sourceLastSeq = "2",
                                sourceDigest = "source-digest",
                                status = "ok",
                                summary = summary,
                                sourceEventCount = "2",
                                summaryDigest = "summary-digest",
                                manifestDigest = "compacted-manifest",
                                builderAlgorithm = "structured-prefix-v1",
                                modelSnapshot = "model-snapshot",
                                promptSnapshot = "prompt-snapshot",
                                viewContextGeneration = "1",
                            },
                        },
                        {
                            seq = 4,
                            type = "model_view_published",
                            fields = {
                                manifestDigest = "compacted-manifest",
                                firstEventSeq = "1",
                                lastEventSeq = "4",
                                replacesManifestDigest = "sha256:view-manifest",
                                compactionId = "compaction-1",
                                viewContextGeneration = "1",
                            },
                        },
                    },
                    compaction_record = record,
                }
                local compacted = assert(service.append_events(original, mutation))
                A.equal(compacted.generation, 2)
                A.equal(compacted.event_count, 4)
                A.equal(compacted.model_view.active_manifest.digest, "compacted-manifest")
                A.equal(compacted.model_view.active_manifest.compaction_id, "compaction-1")
                A.equal(compacted.model_view.compaction_records[1].summary, summary)
                local encoded = assert(service.encode(compacted))
                A.contains(encoded, 'compactionId="compaction-1"')

                local mismatched = copy(mutation)
                mismatched.compaction_record.source_digest = "forged-source"
                local rejected, mutation_error = service.append_events(original, mismatched)
                A.falsy(rejected)
                A.equal(mutation_error.code, "InvalidEventMutation")
                A.equal(original.generation, 1)
                A.equal(#original.model_view.compaction_records, 0)
            end,
        },
        {
            name = "catalog Header reader stops pulling before the Context body",
            run = function()
                local observations = { feeds = 0, closes = 0 }
                local service = new_service(nil, incremental_header_lxp(observations))
                local pulls = 0
                local header, stats = assert(service.read_header_stream(function()
                    pulls = pulls + 1
                    return true, { bytes = "header-prefix", eof = false }
                end))
                A.equal(pulls, 1)
                A.equal(observations.feeds, 1)
                A.equal(observations.closes, 1)
                A.equal(header.schema_version, "0.1.0")
                A.equal(header.generation, 7)
                A.equal(header.header.name, "Task")
                A.equal(header.header.created_at, "2026-08-29T00:00:00Z")
                A.equal(header.header.updated_at, "2026-08-29T00:00:01Z")
                A.equal(stats.bytes, #"header-prefix")
                A.equal(stats.header_complete, true)
            end,
        },
        {
            name = "schema time identifiers enums limits and construction fail closed",
            run = function()
                local service, options = new_service()
                local cases = {
                    { function(value) value.header.updated_at = "2026-02-30T00:00:00Z" end,
                        "ContextSchema" },
                    { function(value) value.facts[1].seq = 2 end, "ContextSequence" },
                    { function(value) value.facts[2].fields.extra = "x" end,
                        "ContextSchema" },
                    { function(value) value.facts[2].fields.messageId = "" end,
                        "ContextSchema" },
                    { function(value) value.facts[1].type = "token_delta" end,
                        "ContextSchema" },
                    { function(value) value.model_view.compaction_records = { false } end,
                        "ContextSchema" },
                }
                for _, case in ipairs(cases) do
                    local candidate = minimal()
                    case[1](candidate)
                    local built, build_error = service.build(candidate)
                    A.falsy(built)
                    A.equal(build_error.code, case[2])
                end

                local invalid = copy(options)
                invalid.maximum_events = invalid.xml.limits.maximum_context_events + 1
                local unavailable, options_error = context.new(invalid)
                A.falsy(unavailable)
                A.equal(options_error.code, "InvalidContextOptions")
                unavailable, options_error = context.new({})
                A.falsy(unavailable)
                A.equal(options_error.code, "InvalidContextDependency")
            end,
        },
    },
}
