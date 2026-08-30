--[[
File: context_store_harness.lua
Date: 2026-08-29
Author: WaterRun
Description: Builds deterministic schema and identity-aware filesystem storage fixtures.
]]

local M = {}

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function emit_leaf(callbacks, name, value, attributes)
    callbacks.StartElement(nil, name, attributes or {})
    if value ~= nil and value ~= "" then callbacks.CharacterData(nil, value) end
    callbacks.EndElement(nil, name)
end

local function emit_candidate(callbacks, candidate, schema, xml, sha256)
    callbacks.XmlDecl(nil, "1.0", "UTF-8")
    callbacks.StartElement(nil, "YacaContext", {
        schemaVersion = candidate.schema_version,
        generation = tostring(candidate.generation),
    })
    callbacks.StartElement(nil, "Header", {})
    emit_leaf(callbacks, "Name", candidate.header.name)
    emit_leaf(callbacks, "CreatedAt", candidate.header.created_at)
    emit_leaf(callbacks, "UpdatedAt", candidate.header.updated_at)
    if candidate.header.auto_rename_disabled ~= nil then
        emit_leaf(callbacks, "AutoRenameDisabled",
            candidate.header.auto_rename_disabled and "true" or "false")
    end
    if candidate.header.naming_waterline ~= nil then
        emit_leaf(callbacks, "NamingWaterline", tostring(candidate.header.naming_waterline))
    end
    if candidate.header.auto_name_baseline ~= nil then
        emit_leaf(callbacks, "AutoNameBaseline", tostring(candidate.header.auto_name_baseline))
    end
    callbacks.EndElement(nil, "Header")

    callbacks.StartElement(nil, "Session", {})
    emit_leaf(callbacks, "CurrentModel", nil, {
        name = candidate.session.current_model.name,
        snapshotDigest = candidate.session.current_model.snapshot_digest,
    })
    emit_leaf(callbacks, "CurrentPermission", nil, {
        name = candidate.session.current_permission.name,
        snapshotDigest = candidate.session.current_permission.snapshot_digest,
    })
    local override = candidate.session.double_check_override
    emit_leaf(callbacks, "DoubleCheckOverride",
        override == "inherit" and override or tostring(override))
    local goal = candidate.session.double_check_goal_override
    emit_leaf(callbacks, "DoubleCheckGoalOverride", goal.value, { mode = goal.mode })
    emit_leaf(callbacks, "ContextPrompt", candidate.session.context_prompt)
    callbacks.EndElement(nil, "Session")

    callbacks.StartElement(nil, "Facts", {})
    for _, event in ipairs(candidate.facts) do
        local attributes = {
            seq = tostring(event.seq), type = event.type, at = event.at,
        }
        if event.turn_id then attributes.turnId = event.turn_id end
        callbacks.StartElement(nil, "Event", attributes)
        local event_schema = assert(schema.event_schema(event.type))
        local ordered = {}
        for _, name in ipairs(event_schema.required) do ordered[#ordered + 1] = name end
        for _, name in ipairs(event_schema.optional) do
            if event.fields[name] ~= nil then ordered[#ordered + 1] = name end
        end
        for _, name in ipairs(ordered) do
            local bytes = event.fields[name]
            local carrier = assert(xml.carrier(bytes))
            local info = assert(xml.carrier_info(carrier))
            local field_attributes = { name = name }
            local encoded = bytes
            if info.representation == "base64" then
                field_attributes.representation = "base64"
                field_attributes.rawBytes = tostring(#bytes)
                field_attributes.digest = sha256.hex(bytes)
                encoded = info.encoded
            end
            emit_leaf(callbacks, "Field", encoded, field_attributes)
        end
        callbacks.EndElement(nil, "Event")
    end
    callbacks.EndElement(nil, "Facts")

    callbacks.StartElement(nil, "ModelView", {})
    local manifest = candidate.model_view.active_manifest
    emit_leaf(callbacks, "ActiveManifest", nil, {
        digest = manifest.digest,
        firstEventSeq = tostring(manifest.first_event_seq),
        lastEventSeq = tostring(manifest.last_event_seq),
        compactionId = manifest.compaction_id,
    })
    for _, record in ipairs(candidate.model_view.compaction_records) do
        emit_leaf(callbacks, "CompactionRecord", record.summary, {
            id = record.id,
            sourceFirstSeq = tostring(record.source_first_seq),
            sourceLastSeq = tostring(record.source_last_seq),
            sourceDigest = record.source_digest,
            status = record.status,
        })
    end
    callbacks.EndElement(nil, "ModelView")
    callbacks.EndElement(nil, "YacaContext")
end

function M.minimal(name)
    return {
        schema_version = "0.1.0",
        generation = 1,
        header = {
            name = name or "Task",
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

function M.next_generation(candidate, settings)
    settings = settings or {}
    local result = copy(candidate)
    result.generation = result.generation + 1
    result.header.updated_at = settings.updated_at or "2026-08-29T00:00:02Z"
    local event = settings.event or {
        type = "warning",
        fields = { errorId = "StorageProof", summary = "durable update" },
    }
    result.facts[#result.facts + 1] = {
        seq = #result.facts + 1,
        type = event.type,
        at = result.header.updated_at,
        turn_id = event.turn_id,
        fields = copy(event.fields),
    }
    result.model_view.active_manifest.last_event_seq = #result.facts
    result.model_view.active_manifest.digest = "sha256:view-" .. tostring(result.generation)
    return result
end

function M.unresolved(name)
    local result = M.minimal(name)
    local events = {
        {
            type = "model_request",
            fields = {
                requestId = "request-1",
                purpose = "main",
                viewManifestRef = "sha256:view-manifest",
            },
        },
        {
            type = "tool_call",
            fields = {
                toolCallId = "tool-1",
                requestId = "request-1",
                name = "exec",
                canonicalArguments = "{}",
            },
        },
        {
            type = "operation_intent",
            fields = {
                operationId = "operation-1",
                toolCallId = "tool-1",
                kind = "exec",
                targetIdentity = "workspace-object",
                expectedDigest = "sha256:expected",
            },
        },
    }
    for _, event in ipairs(events) do
        result.facts[#result.facts + 1] = {
            seq = #result.facts + 1,
            type = event.type,
            at = "2026-08-29T00:00:01Z",
            turn_id = "turn-1",
            fields = event.fields,
        }
    end
    result.model_view.active_manifest.last_event_seq = #result.facts
    return result
end

local function wrap_native(raw, hooks)
    local native = {}
    local mappings = {
        fs_open_read = "open_read",
        fs_create_new = "create_new",
        fs_stat_identity = "stat_identity",
        fs_read = "stream_read",
        fs_write = "stream_write",
        fs_flush_file = "flush_file",
        fs_flush_directory = "flush_directory",
        fs_replace = "replace",
        fs_rename_no_replace = "rename_no_replace",
        fs_delete_verified = "delete_verified",
        fs_close = "close",
    }
    for native_name, service_name in pairs(mappings) do
        native[native_name] = function(...)
            hooks.counts[native_name] = (hooks.counts[native_name] or 0) + 1
            local before = hooks.before[native_name]
            if before then before(...) end
            local ok, value = raw[service_name](...)
            local after = hooks.after[native_name]
            if after then after(ok, value, ...) end
            return ok, value
        end
    end
    return native
end

function M.new(modules, initial_candidates)
    local context, xml, fs = modules.context, modules.xml, modules.fs
    local fake_lxp, sha256 = modules.fake_lxp, modules.sha256
    local fake_filesystem = modules.fake_filesystem
    local documents = {}
    local schema
    local lxp = fake_lxp(function(document, callbacks)
        local candidate = documents[document]
        if not candidate then return false, "unregistered Context bytes", 1, 1, 1 end
        emit_candidate(callbacks, candidate, schema, xml, sha256)
        return true
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
        maximum_chunk_bytes = 13,
    }))
    schema = assert(context.new({
        xml = codec,
        safety = { digest = sha256.hex },
        maximum_name_bytes = 256,
        maximum_identifier_bytes = 256,
        maximum_field_name_bytes = 64,
        maximum_field_bytes = 65536,
        maximum_events = 256,
        maximum_compaction_records = 64,
        maximum_export_bytes = 1024 * 1024,
    }))

    local function semantic_candidate(built)
        local facts = {}
        for index, event in ipairs(built.facts) do
            facts[index] = {
                seq = event.seq,
                type = event.type,
                at = event.at,
                turn_id = event.turn_id,
                fields = copy(event.fields),
            }
        end
        return {
            schema_version = built.schema_version,
            generation = built.generation,
            header = copy(built.header),
            session = copy(built.session),
            facts = facts,
            model_view = copy(built.model_view),
        }
    end

    local function register_document(built, candidate)
        local bytes = assert(schema.encode(built))
        documents[bytes] = candidate and copy(candidate) or semantic_candidate(built)
        return bytes
    end

    local function document(candidate)
        local stable = copy(candidate)
        local built = assert(schema.build(stable))
        local bytes = register_document(built, stable)
        return built, bytes
    end

    local initial = {}
    for path, candidate in pairs(initial_candidates or {}) do
        local _, bytes = document(candidate)
        initial[path] = bytes
    end
    local raw, raw_controls = fake_filesystem.new(initial, 11)
    local hooks = { before = {}, after = {}, counts = {} }
    local filesystem = assert(fs.new(wrap_native(raw, hooks), {
        maximum_chunk_bytes = 11,
        maximum_lease_bytes = 512,
    }))
    local store = assert(context.new_store(schema, { filesystem = filesystem }, {
        maximum_context_bytes = 1024 * 1024,
        maximum_lock_hostname_bytes = 64,
        maximum_temp_nonce_bytes = 32,
        context_permissions = 384,
        lock_permissions = 384,
    }))
    return {
        schema = schema,
        store = store,
        filesystem = filesystem,
        raw = raw,
        controls = raw_controls,
        hooks = hooks,
        documents = documents,
        document = document,
        register_document = register_document,
        copy = copy,
        metadata = function(pid)
            return {
                pid = pid or 100,
                started_at = "2026-08-29T00:00:00Z",
                hostname = "test-host",
            }
        end,
        new_store = function()
            return assert(context.new_store(schema, { filesystem = filesystem }, {
                maximum_context_bytes = 1024 * 1024,
                maximum_lock_hostname_bytes = 64,
                maximum_temp_nonce_bytes = 32,
                context_permissions = 384,
                lock_permissions = 384,
            }))
        end,
    }
end

return M
