--[[
File: context_reader_test.lua
Date: 2026-08-29
Author: WaterRun
Description: Verifies the independent SAX reader and Context transfer projection.
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

local function read_file(relative_path)
    local handle, open_error = io.open(YACA_TEST_ROOT .. "/" .. relative_path, "rb")
    A.truthy(handle, open_error)
    local value = handle:read("a")
    handle:close()
    return value
end

local cache = {}
local context = load_module("context", cache)
local xml = load_module("xml", cache)
local fake_lxp = load_table("test/support/fake_lxp.lua")
local sha256 = load_table("test/support/sha256_reference.lua")
local fixture = read_file(".develope-docs/contracts/fixtures/context-minimal.xml")

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

local function append(candidate, type_name, fields)
    candidate.facts[#candidate.facts + 1] = {
        seq = #candidate.facts + 1,
        type = type_name,
        at = "2026-08-29T00:00:01Z",
        turn_id = "turn-1",
        fields = fields,
    }
    candidate.model_view.active_manifest.last_event_seq = #candidate.facts
end

local function rich()
    local candidate = minimal()
    append(candidate, "model_request", {
        requestId = "request-1", purpose = "main", viewManifestRef = "sha256:view-manifest",
    })
    append(candidate, "tool_call", {
        toolCallId = "tool-1", requestId = "request-1", name = "exec",
        canonicalArguments = "{}",
    })
    append(candidate, "operation_intent", {
        operationId = "operation-1", toolCallId = "tool-1", kind = "exec",
        targetIdentity = "workspace", expectedDigest = "missing",
    })
    append(candidate, "operation_result", {
        operationId = "operation-1", status = "ok", evidence = "complete",
    })
    append(candidate, "tool_result", {
        toolCallId = "tool-1", status = "ok", body = "\0\255\rbytes", truncated = "false",
    })
    append(candidate, "turn_ended", { outcome = "completed", reason = "" })
    return candidate
end

local function emit_leaf(callbacks, name, value, attributes)
    callbacks.StartElement(nil, name, attributes or {})
    if value ~= nil and value ~= "" then callbacks.CharacterData(nil, value) end
    callbacks.EndElement(nil, name)
end

local function emit_candidate(callbacks, candidate, service, settings)
    settings = settings or {}
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
        local schema = assert(service.event_schema(event.type))
        local ordered = {}
        for _, name in ipairs(schema.required) do ordered[#ordered + 1] = name end
        for _, name in ipairs(schema.optional) do
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
                field_attributes.digest = settings.bad_digest and name == "body"
                    and string.rep("0", 64) or sha256.hex(bytes)
                encoded = info.encoded
            end
            callbacks.StartElement(nil, "Field", field_attributes)
            if encoded ~= "" then callbacks.CharacterData(nil, encoded) end
            callbacks.EndElement(nil, "Field")
            if settings.duplicate_field and name == "kind" then
                emit_leaf(callbacks, "Field", "side", { name = "kind" })
            end
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

local function harness()
    local documents = {}
    local service
    local lxp = fake_lxp(function(document, callbacks)
        local entry = documents[document]
        if entry then
            emit_candidate(callbacks, entry.candidate, service, entry.settings)
            return true
        end
        if document == "unknown-element" then
            callbacks.StartElement(nil, "YacaContext", {
                schemaVersion = "0.1.0", generation = "1",
            })
            callbacks.StartElement(nil, "Unknown", {})
            return true
        end
        if document == "bad-order" then
            callbacks.StartElement(nil, "YacaContext", {
                schemaVersion = "0.1.0", generation = "1",
            })
            callbacks.StartElement(nil, "Session", {})
            return true
        end
        return false, "reference Context mismatch", 1, 1, 1
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
        maximum_chunk_bytes = 17,
    }))
    service = assert(context.new({
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
    documents[fixture] = { candidate = minimal() }
    return service, lxp, documents
end

return {
    name = "reference/context-reader",
    cases = {
        {
            name = "minimal RNG fixture reads and writer output reads to the same facts",
            run = function()
                local service, lxp, documents = harness()
                local document, stats = assert(service.read(fixture))
                A.equal(document.header.name, "Untitled Conversation [0A1B]")
                A.equal(document.session.current_model.name, "Local")
                A.equal(document.session.context_prompt, "")
                A.equal(document.event_count, 2)
                A.equal(document.facts[1].fields.kind, "main")
                A.equal(document.facts[2].fields.text, "hello")
                A.equal(stats.context_events, 2)
                A.equal(stats.external_entity_opens, 0)

                local encoded = assert(service.encode(document))
                documents[encoded] = { candidate = minimal() }
                local split = math.floor(#encoded / 2)
                local reread = assert(service.read({
                    encoded:sub(1, split), encoded:sub(split + 1),
                }))
                A.equal(reread.generation, document.generation)
                A.deep_equal(reread.header, document.header)
                A.deep_equal(reread.session, document.session)
                A.deep_equal(reread.facts, document.facts)
                A.deep_equal(reread.model_view, document.model_view)
                A.truthy(lxp.observations.maximum_chunk_bytes <= 17)
            end,
        },
        {
            name = "base64 fields and present-empty optional fields survive reader roundtrip",
            run = function()
                local service, _, documents = harness()
                local candidate = rich()
                local original = assert(service.build(candidate))
                local encoded = assert(service.encode(original))
                documents[encoded] = { candidate = candidate }
                local restored = assert(service.read(encoded))
                local tool_result = restored.facts[7]
                A.equal(tool_result.type, "tool_result")
                A.equal(tool_result.fields.body, "\0\255\rbytes")
                A.equal(tool_result.field_metadata.body.representation, "base64")
                A.equal(tool_result.field_metadata.body.raw_bytes, 8)
                A.equal(tool_result.field_metadata.body.digest,
                    sha256.hex("\0\255\rbytes"))
                A.equal(restored.facts[8].fields.reason, "")
                A.equal(restored.facts[8].fields.errorId, nil)
                A.deep_equal(restored.recovery.unresolved_operation_ids, {})
                A.deep_equal(restored.recovery.unresolved_tool_call_ids, {})
                A.truthy(restored.recovery.auto_continue)
                A.equal(assert(service.encode(restored)), encoded)
            end,
        },
        {
            name = "unknown structure order duplicate fields and digest corruption reject typed",
            run = function()
                local service, _, documents = harness()
                local invalid, read_error = service.read("unknown-element")
                A.falsy(invalid)
                A.equal(read_error.code, "ContextSchema")
                A.equal(read_error.reason, "child-order")

                invalid, read_error = service.read("bad-order")
                A.falsy(invalid)
                A.equal(read_error.code, "ContextSchema")
                A.equal(read_error.reason, "child-order")

                documents["duplicate-field"] = {
                    candidate = minimal(), settings = { duplicate_field = true },
                }
                invalid, read_error = service.read("duplicate-field")
                A.falsy(invalid)
                A.equal(read_error.code, "ContextSchema")
                A.equal(read_error.reason, "duplicate-field")

                documents["bad-digest"] = {
                    candidate = rich(), settings = { bad_digest = true },
                }
                invalid, read_error = service.read("bad-digest")
                A.falsy(invalid)
                A.equal(read_error.code, "ContextIntegrity")
                A.equal(read_error.reason, "digest-mismatch")
            end,
        },
        {
            name = "stale imported ModelView is explicit and cannot flow back to publication",
            run = function()
                local service, _, documents = harness()
                local candidate = minimal()
                candidate.model_view.active_manifest.last_event_seq = 20
                documents["stale-view"] = { candidate = candidate }
                local document = assert(service.read("stale-view"))
                A.equal(document.recovery.model_view_status, "stale")
                A.truthy(document.recovery.rebuild_model_view)
                A.falsy(document.recovery.auto_continue)
                A.contains(assert(service.export(document)), "- Status: `stale`")
                local encoded, stale_error = service.encode(document)
                A.falsy(encoded)
                A.equal(stale_error.code, "StaleModelView")
            end,
        },
        {
            name = "export makes markup and controls visible and propagates bounded sink failure",
            run = function()
                local service = harness()
                local candidate = minimal()
                candidate.facts[2].fields.text = "line one\n# forged <script>`x`\u{202E}"
                local document = assert(service.build(candidate))
                local exported = assert(service.export(document))
                A.contains(exported, "line one\\n# forged \\x3Cscript\\x3E\\x60x\\x60")
                A.contains(exported, "\\u{202E}")
                A.falsy(exported:find("<script>", 1, true))
                A.falsy(exported:find("\n# forged", 1, true))

                local calls = 0
                local written, sink_error = service.export(document, function(bytes)
                    calls = calls + 1
                    if calls == 2 then return false, "broken export" end
                    return #bytes
                end)
                A.falsy(written)
                A.equal(sink_error.code, "ContextExportSink")
                A.equal(sink_error.message, "broken export")
            end,
        },
        {
            name = "XML parser security and byte limits remain authoritative below Context schema",
            run = function()
                local service = harness()
                local malformed, syntax_error = service.read("not registered")
                A.falsy(malformed)
                A.equal(syntax_error.code, "XmlSyntax")
                local oversized = string.rep("x", 1024 * 1024 + 1)
                local too_large, limit_error = service.read(oversized)
                A.falsy(too_large)
                A.equal(limit_error.code, "XmlLimit")
                A.equal(limit_error.reason, "bytes")
            end,
        },
    },
}
