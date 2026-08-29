--[[
File: session.lua
Date: 2026-08-30
Author: WaterRun
Description: Owns the bounded chat draft and first durable Context publication.
]]

local text = require("text")

local M = {}

local function failure(code, message, reason)
    local result = { code = code, message = message }
    if reason ~= nil then result.reason = reason end
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
    for index = 1, count do if values[index] == nil then return nil end end
    return count
end

local function valid_text(value, maximum_bytes)
    if type(value) ~= "string" or #value > maximum_bytes then return false end
    local valid, metadata = text.validate_utf8(value)
    return valid and not metadata.contains_nul
end

local function validate_workspace(workspace)
    if type(workspace) ~= "table"
        or type(workspace.path) ~= "string"
        or workspace.path == ""
        or workspace.enterable ~= true
    then
        return nil, failure(
            "InvalidWorkspace",
            "unsaved chat requires a validated enterable workspace"
        )
    end
    return {
        path = workspace.path,
        identity = workspace.identity,
    }
end

local function validate_generation(generation)
    if type(generation) ~= "table"
        or type(generation.id) ~= "string"
        or generation.id == ""
        or generation.agent_ready ~= true
        or type(generation.current_model) ~= "string"
        or type(generation.current_permission) ~= "string"
        or type(generation.models) ~= "table"
        or type(generation.permissions) ~= "table"
        or type(generation.scan_registered_secrets) ~= "function"
    then
        return nil, failure(
            "ModelUnavailable",
            "unsaved chat requires an Agent-ready configuration generation"
        )
    end
    return generation
end

local function settings_bytes(settings)
    return #settings.model
        + #settings.permission
        + #settings.double_check_goal
        + #settings.context_prompt
end

local function valid_absolute_path(path)
    if type(path) ~= "string" or path == "" or path:find("\0", 1, true) then
        return false
    end
    local normalized = path:gsub("\\", "/")
    return normalized:sub(1, 1) == "/"
        or normalized:match("^[A-Za-z]:/") ~= nil
        or normalized:match("^//[^/]+/[^/]+") ~= nil
end

local function directory_of(path, platform_kind)
    if type(path) ~= "string" then return nil end
    local separator
    for index = #path, 1, -1 do
        local byte = path:byte(index)
        if byte == 0x2F or (platform_kind == "windows" and byte == 0x5C) then
            separator = index
            break
        end
    end
    if not separator then return nil end
    if separator == 1 then return path:sub(1, 1) end
    if separator == 3 and path:sub(2, 2) == ":" then return path:sub(1, 3) end
    return path:sub(1, separator - 1)
end

local function join_native(root, leaf, platform_kind)
    local separator = platform_kind == "windows" and "\\" or "/"
    if root:sub(-1) == separator then return root .. leaf end
    return root .. separator .. leaf
end

local function hex(bytes)
    return (bytes:gsub(".", function(byte)
        return string.format("%02X", byte:byte())
    end))
end

local function utc_parts(value)
    if type(value) ~= "string" then return nil end
    local year, month, day, hour, minute, second = value:match(
        "^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)Z$"
    )
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
    hour, minute, second = tonumber(hour), tonumber(minute), tonumber(second)
    if not year or year < 1 or month < 1 or month > 12
        or hour > 23 or minute > 59 or second > 59
    then
        return nil
    end
    local leap = year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
    local days = {
        31, leap and 29 or 28, 31, 30, 31, 30,
        31, 31, 30, 31, 30, 31,
    }
    if day < 1 or day > days[month] then return nil end
    return { year, month, day, hour, minute, second }
end

local function next_utc_time(observed, previous)
    local current = utc_parts(observed)
    local prior = utc_parts(previous)
    if not current or not prior then
        return nil, failure("UtcClockReadFailed", "UTC clock returned a non-canonical value")
    end
    if observed > previous then return observed end
    local year, month, day, hour, minute, second = table.unpack(prior)
    second = second + 1
    if second >= 60 then second, minute = 0, minute + 1 end
    if minute >= 60 then minute, hour = 0, hour + 1 end
    if hour >= 24 then hour, day = 0, day + 1 end
    local leap = year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
    local days = {
        31, leap and 29 or 28, 31, 30, 31, 30,
        31, 31, 30, 31, 30, 31,
    }
    if day > days[month] then day, month = 1, month + 1 end
    if month > 12 then month, year = 1, year + 1 end
    if year > 9999 then
        return nil, failure("UtcClockReadFailed", "UTC generation timestamp overflowed")
    end
    return string.format(
        "%04d-%02d-%02dT%02d:%02d:%02dZ",
        year,
        month,
        day,
        hour,
        minute,
        second
    )
end

local function canonical_public(value, visiting)
    local value_type = type(value)
    if value_type == "string" then return "s" .. tostring(#value) .. ":" .. value end
    if value_type == "boolean" then return value and "b1" or "b0" end
    if value_type == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return nil, failure("InvalidSnapshot", "public snapshot contains a non-finite number")
        end
        if math.type(value) == "integer" then return "i" .. tostring(value) end
        return "f" .. string.format("%.17g", value)
    end
    if value_type ~= "table" then
        return nil, failure("InvalidSnapshot", "public snapshot contains a non-data value")
    end
    visiting = visiting or {}
    if visiting[value] then
        return nil, failure("InvalidSnapshot", "public snapshot contains a cycle")
    end
    visiting[value] = true
    local entries = {}
    for key, item in pairs(value) do
        local key_bytes, key_error = canonical_public(key, visiting)
        if not key_bytes then visiting[value] = nil; return nil, key_error end
        local item_bytes, item_error = canonical_public(item, visiting)
        if not item_bytes then visiting[value] = nil; return nil, item_error end
        entries[#entries + 1] = key_bytes .. "=" .. item_bytes
    end
    table.sort(entries)
    visiting[value] = nil
    return "t" .. tostring(#entries) .. ":" .. table.concat(entries, "|")
end

local function snapshot_digest(safety, domain, value)
    local bytes, bytes_error = canonical_public(value)
    if not bytes then return nil, bytes_error end
    return safety.binding_digest(domain, { { name = "public", value = bytes } })
end

local function model_view_escape(value)
    return value
        :gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
        :gsub('"', "&quot;")
end

local function render_model_view(safety, facts, context_generation, maximum_bytes)
    local count = dense_count(facts)
    if count == nil then
        return nil, failure("InvalidModelView", "Context Facts are not a dense array")
    end
    local first_sequence = count == 0 and 0 or 1
    local parts = {
        '<DurableFacts schemaVersion="1" contextGeneration="',
        tostring(context_generation),
        '" firstSequence="',
        tostring(first_sequence),
        '" lastSequence="',
        tostring(count),
        '">\n',
    }
    local size = 0
    local function add(value)
        size = size + #value
        if size > maximum_bytes then
            return nil, failure("ModelViewLimit", "durable model view exceeds its byte limit")
        end
        parts[#parts + 1] = value
        return true
    end
    -- Account for the fixed header assembled above before appending event data.
    local header = table.concat(parts)
    parts = {}
    local added, add_error = add(header)
    if not added then return nil, add_error end
    for index, event in ipairs(facts) do
        if type(event) ~= "table"
            or event.seq ~= index
            or type(event.type) ~= "string"
            or type(event.at) ~= "string"
            or type(event.fields) ~= "table"
        then
            return nil, failure("InvalidModelView", "Context event cannot enter the model view")
        end
        local turn = event.turn_id and ' turnId="'
            .. model_view_escape(event.turn_id) .. '"' or ""
        added, add_error = add(table.concat({
            '  <Event seq="', tostring(event.seq), '" type="',
            model_view_escape(event.type), '" at="', model_view_escape(event.at),
            '"', turn, '>\n',
        }))
        if not added then return nil, add_error end
        local names = {}
        for name in pairs(event.fields) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            local value = event.fields[name]
            local metadata = event.field_metadata and event.field_metadata[name]
            if type(name) ~= "string" or type(value) ~= "string" then
                return nil, failure("InvalidModelView", "Context field cannot enter the model view")
            end
            local visible
            if metadata and metadata.representation == "base64" then
                visible = table.concat({
                    "[binary omitted; rawBytes=", tostring(metadata.raw_bytes),
                    "; sha256=", tostring(metadata.digest), "]",
                })
            elseif text.xml_carrier_kind(value) == "text" then
                visible = model_view_escape(value)
            else
                visible = "[non-text field omitted]"
            end
            added, add_error = add(table.concat({
                '    <Field name="', model_view_escape(name), '" bytes="',
                tostring(#value), '">', visible, '</Field>\n',
            }))
            if not added then return nil, add_error end
        end
        added, add_error = add("  </Event>\n")
        if not added then return nil, add_error end
    end
    added, add_error = add("</DurableFacts>")
    if not added then return nil, add_error end
    local body = table.concat(parts)
    local digest, digest_error = snapshot_digest(
        safety,
        "yaca-model-view-manifest-v1",
        {
            schema_version = 1,
            context_generation = context_generation,
            first_sequence = first_sequence,
            last_sequence = count,
            body = body,
        }
    )
    if not digest then return nil, digest_error end
    return {
        digest = digest,
        first_sequence = first_sequence,
        last_sequence = count,
        body = body,
    }
end

local function public_generation_snapshot(generation, settings)
    return {
        id = generation.id,
        schema_version = generation.schema_version,
        general = generation.general,
        tui = generation.tui,
        agent = generation.agent,
        network = generation.network,
        exec = generation.exec,
        context = generation.context,
        permissions = generation.permissions,
        permission_order = generation.permission_order,
        models = generation.models,
        model_order = generation.model_order,
        current_model = settings.model,
        current_permission = settings.permission,
        double_check = settings.double_check,
        double_check_goal = settings.double_check_goal,
        context_prompt = settings.context_prompt,
        auto_rename_disabled = settings.auto_rename_disabled,
    }
end

local function admit_directory_snapshot(path, snapshot)
    if type(snapshot) ~= "table"
        or snapshot.requested_path ~= path
        or snapshot.canonical_path ~= path
        or snapshot.ancestry_complete ~= true
        or type(snapshot.ancestors) ~= "table"
        or #snapshot.ancestors == 0
        or type(snapshot.parent_identity) ~= "table"
        or snapshot.parent_identity.kind ~= "directory"
    then
        return nil, failure(
            "ContextDirectoryAlias",
            "Context mirror ancestry is not an exact no-follow directory path"
        )
    end
    for _, ancestor in ipairs(snapshot.ancestors) do
        if type(ancestor) ~= "table"
            or type(ancestor.identity) ~= "table"
            or ancestor.identity.kind ~= "directory"
        then
            return nil, failure(
                "ContextDirectoryAlias",
                "Context mirror ancestry contains a non-directory"
            )
        end
    end
    if snapshot.exists then
        if type(snapshot.identity) ~= "table"
            or snapshot.identity.kind ~= "directory"
            or type(snapshot.metadata) ~= "table"
            or snapshot.metadata.link_target ~= false
        then
            return nil, failure(
                "ContextDirectoryConflict",
                "Context mirror path is not an ordinary directory"
            )
        end
    end
    return snapshot
end

local function inspect_directory(filesystem, path)
    local inspected, snapshot_or_error = filesystem.direct_inspect(path)
    if not inspected then return nil, snapshot_or_error end
    return admit_directory_snapshot(path, snapshot_or_error)
end

local function ensure_directory(filesystem, path, platform_kind)
    local snapshot, inspect_error = inspect_directory(filesystem, path)
    if not snapshot then return nil, inspect_error end
    if snapshot.exists then return snapshot end
    local created, create_error = filesystem.make_directory(path, 448)
    if not created
        and (type(create_error) ~= "table" or create_error.code ~= "DestinationExists")
    then
        return nil, create_error
    end
    snapshot, inspect_error = inspect_directory(filesystem, path)
    if not snapshot then return nil, inspect_error end
    if not snapshot.exists then
        return nil, failure(
            "ContextDirectoryUnknown",
            "Context mirror directory creation could not be confirmed"
        )
    end
    if not created then return snapshot end
    local parent = directory_of(path, platform_kind)
    if not parent then
        return nil, failure("InvalidContextPath", "Context mirror directory has no parent")
    end
    local flushed, flush_error = filesystem.flush_directory(parent)
    if not flushed then
        return nil, failure(
            "ContextDirectoryUnknown",
            "Context mirror directory durability is unknown",
            flush_error and flush_error.code
        )
    end
    return snapshot
end

local function validate_publication_ports(ports)
    if type(ports) ~= "table" then
        return nil, failure("InvalidContextPublication", "Context publication ports are required")
    end
    local required = {
        filesystem = {
            "direct_inspect", "direct_reverify", "make_directory", "flush_directory",
        },
        schema = { "build", "append_events" },
        store = { "create_writer", "publish", "close_writer" },
        path = { "to_logical", "validate_context_name", "context_hash" },
        safety = { "binding_digest" },
        prompt = { "assemble" },
        system = { "secure_random", "current_process_id", "utc_now" },
    }
    for name, methods in pairs(required) do
        if type(ports[name]) ~= "table" then
            return nil, failure(
                "InvalidContextPublication",
                "Context publication omits the " .. name .. " port"
            )
        end
        for _, method in ipairs(methods) do
            if type(ports[name][method]) ~= "function" then
                return nil, failure(
                    "InvalidContextPublication",
                    "Context publication " .. name .. " port omits " .. method
                )
            end
        end
    end
    if type(ports.tool_registry) ~= "table"
        or type(ports.tool_registry.digest) ~= "string"
        or ports.tool_registry.digest == ""
    then
        return nil, failure(
            "InvalidContextPublication",
            "Context publication requires the exact tool registry snapshot"
        )
    end
    return ports
end

local function validate_publication_options(options)
    if type(options) ~= "table" then
        return nil, failure("InvalidContextPublication", "Context publication limits are required")
    end
    local allowed = {
        data_root = true,
        platform_kind = true,
        maximum_create_attempts = true,
        maximum_model_view_bytes = true,
    }
    for key in pairs(options) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure(
                "InvalidContextPublication",
                "Context publication options contain an unknown field"
            )
        end
    end
    if not valid_absolute_path(options.data_root)
        or (options.platform_kind ~= "windows" and options.platform_kind ~= "posix")
        or not valid_integer(options.maximum_create_attempts, 1)
        or options.maximum_create_attempts > 256
        or not valid_integer(options.maximum_model_view_bytes, 1)
    then
        return nil, failure(
            "InvalidContextPublication",
            "Context publication options are incomplete or unsafe"
        )
    end
    return options
end

---Creates the single-owner service that turns a first main message into the
-- initial durable Context generation. Candidate names come only from the
-- injected secure random port and every attempt is published no-replace.
function M.new_context_publication(ports, options)
    local admitted_ports, ports_error = validate_publication_ports(ports)
    if not admitted_ports then return nil, ports_error end
    local admitted, options_error = validate_publication_options(options)
    if not admitted then return nil, options_error end

    local filesystem = admitted_ports.filesystem
    local schema = admitted_ports.schema
    local store = admitted_ports.store
    local path = admitted_ports.path
    local safety = admitted_ports.safety
    local prompt = admitted_ports.prompt
    local system = admitted_ports.system
    local context_root = join_native(admitted.data_root, "CONTEXT", admitted.platform_kind)
    local active
    local closed = false
    local journal_failure
    local service = {}
    local model_views = {}
    local operation_journal
    local operation_intent_receipts = {}
    local operation_result_receipts = {}

    local function cache_model_view(facts, context_generation)
        local candidate, view_error = render_model_view(
            safety,
            facts,
            context_generation,
            admitted.maximum_model_view_bytes
        )
        if not candidate then return nil, view_error end
        local frozen = readonly(candidate, "durable model view")
        model_views[candidate.digest] = frozen
        return frozen
    end

    local function prepare_mirror(workspace_path)
        local logical, logical_error = path.to_logical(workspace_path)
        if not logical then return nil, logical_error end
        local current = admitted.data_root
        local prepared, prepare_error = ensure_directory(
            filesystem,
            current,
            admitted.platform_kind
        )
        if prepared == nil then return nil, prepare_error end
        current = context_root
        prepared, prepare_error = ensure_directory(filesystem, current, admitted.platform_kind)
        if prepared == nil then return nil, prepare_error end
        if logical ~= "/" then
            for segment in logical:sub(2):gmatch("[^/]+") do
                current = join_native(current, segment, admitted.platform_kind)
                prepared, prepare_error = ensure_directory(
                    filesystem,
                    current,
                    admitted.platform_kind
                )
                if prepared == nil then return nil, prepare_error end
            end
        end
        return current, logical, prepared
    end

    local function prompt_bundle(generation, settings, message)
        local model = generation.models[settings.model]
        local permission = generation.permissions[settings.permission]
        if type(model) ~= "table" or type(permission) ~= "table" then
            return nil, failure("SnapshotUnavailable", "selected Model or Permission vanished")
        end
        return prompt:assemble({
            purpose = "main",
            config_generation = generation.id,
            layers = {
                global = {
                    source = "General.SystemPrompt",
                    version = generation.id,
                    text = generation.general.system_prompt,
                },
                model = {
                    source = "Model." .. settings.model .. ".SystemPrompt",
                    version = generation.id,
                    text = model.system_prompt,
                },
                permission = {
                    source = "Permission." .. settings.permission .. ".SystemPrompt",
                    version = generation.id,
                    text = permission.system_prompt,
                },
                context = {
                    source = "ContextPrompt",
                    version = generation.id,
                    text = settings.context_prompt,
                },
            },
            input = { user_message = message },
            tool_mode = "registered",
        })
    end

    local function snapshots(specification)
        local generation = specification.generation
        local settings = specification.settings
        local model = generation.models[settings.model]
        local permission = generation.permissions[settings.permission]
        if type(model) ~= "table" or type(permission) ~= "table" then
            return nil, failure("SnapshotUnavailable", "selected Model or Permission is missing")
        end
        local model_digest, digest_error = snapshot_digest(
            safety,
            "yaca-model-snapshot-v1",
            { name = settings.model, generation = generation.id, values = model }
        )
        if not model_digest then return nil, digest_error end
        local permission_digest
        permission_digest, digest_error = snapshot_digest(
            safety,
            "yaca-permission-snapshot-v1",
            { name = settings.permission, generation = generation.id, values = permission }
        )
        if not permission_digest then return nil, digest_error end
        local config_digest
        config_digest, digest_error = snapshot_digest(
            safety,
            "yaca-config-generation-public-v1",
            public_generation_snapshot(generation, settings)
        )
        if not config_digest then return nil, digest_error end
        local bundle, bundle_error = prompt_bundle(
            generation,
            settings,
            specification.message
        )
        if not bundle then return nil, bundle_error end
        return {
            model = model_digest,
            permission = permission_digest,
            config = config_digest,
            prompt = bundle.digest,
            tool_registry = admitted_ports.tool_registry.digest,
        }
    end

    local function close_writer(writer, original_error)
        local closed_writer, close_error = store.close_writer(writer)
        if not closed_writer then
            return nil, failure(
                "ContextPublicationUnknown",
                "Context publication failed and writer release is unknown",
                close_error and close_error.code or (original_error and original_error.code)
            )
        end
        return nil, original_error
    end

    function service.publish_first(specification)
        if closed then
            return nil, failure("ContextPublicationClosed", "Context publication service is closed")
        end
        if active then
            return nil, failure("ContextAlreadyPublished", "this process already owns a Context")
        end
        if type(specification) ~= "table"
            or type(specification.generation) ~= "table"
            or type(specification.workspace) ~= "table"
            or type(specification.workspace.path) ~= "string"
            or type(specification.settings) ~= "table"
            or type(specification.message) ~= "string"
            or specification.message == ""
            or type(specification.source) ~= "string"
            or specification.source == ""
        then
            return nil, failure("InvalidFirstMain", "first main publication input is incomplete")
        end
        local generation = specification.generation
        local settings = specification.settings
        local snapshot, snapshot_error = snapshots(specification)
        if not snapshot then return nil, snapshot_error end
        local mirror, workspace_logical_or_error, mirror_snapshot = prepare_mirror(
            specification.workspace.path
        )
        if not mirror then return nil, workspace_logical_or_error end
        local workspace_logical = workspace_logical_or_error
        local now, time_error = system.utc_now()
        if type(now) ~= "string" or now == "" then
            return nil, time_error or failure("UtcClockReadFailed", "UTC clock is unavailable")
        end
        local pid, pid_error = system.current_process_id()
        if not valid_integer(pid, 1) then
            return nil, pid_error or failure("ProcessIdentityUnavailable", "process ID is unavailable")
        end

        for _ = 1, admitted.maximum_create_attempts do
            local current, current_or_error = filesystem.direct_reverify(mirror_snapshot)
            if not current then return nil, current_or_error end
            mirror_snapshot, current_or_error = admit_directory_snapshot(mirror, current_or_error)
            if not mirror_snapshot then return nil, current_or_error end
            local random, random_error = system.secure_random(10)
            if type(random) ~= "string" or #random ~= 10 then
                return nil, random_error or failure(
                    "SecureRandomUnavailable",
                    "secure random source returned an invalid result"
                )
            end
            local display_name = "Untitled Conversation [" .. hex(random:sub(1, 2)) .. "]"
            local valid_name, name_error = path.validate_context_name(display_name)
            if not valid_name then return nil, name_error end
            local filename = display_name .. ".xml"
            local target_path = join_native(mirror, filename, admitted.platform_kind)
            local logical_path = workspace_logical == "/" and "/" .. filename
                or workspace_logical .. "/" .. filename
            local context_hash, hash_error = path.context_hash(logical_path)
            if not context_hash then return nil, hash_error end
            local facts = {
                {
                    seq = 1,
                    type = "turn_started",
                    at = now,
                    turn_id = "turn-1",
                    fields = {
                        kind = "main",
                        configGeneration = snapshot.config,
                        modelSnapshot = snapshot.model,
                        permissionSnapshot = snapshot.permission,
                        promptSnapshot = snapshot.prompt,
                        toolRegistrySnapshot = snapshot.tool_registry,
                    },
                },
                {
                    seq = 2,
                    type = "user_message",
                    at = now,
                    turn_id = "turn-1",
                    fields = {
                        messageId = "turn-1:message:1",
                        text = specification.message,
                        source = specification.source,
                    },
                },
            }
            local initial_view, view_error = cache_model_view(facts, 1)
            if not initial_view then return nil, view_error end
            snapshot.view = initial_view.digest
            local goal_override = settings.double_check_goal_override == "value"
                and { mode = "value", value = settings.double_check_goal }
                or { mode = "inherit" }
            local header = {
                name = display_name,
                created_at = now,
                updated_at = now,
                naming_waterline = 0,
                auto_name_baseline = 0,
            }
            if settings.auto_rename_disabled then header.auto_rename_disabled = true end
            local document, document_error = schema.build({
                schema_version = "0.1.0",
                generation = 1,
                header = header,
                session = {
                    current_model = {
                        name = settings.model,
                        snapshot_digest = snapshot.model,
                    },
                    current_permission = {
                        name = settings.permission,
                        snapshot_digest = snapshot.permission,
                    },
                    double_check_override = settings.double_check_override,
                    double_check_goal_override = goal_override,
                    context_prompt = settings.context_prompt,
                },
                facts = facts,
                model_view = {
                    active_manifest = {
                        digest = snapshot.view,
                        first_event_seq = 1,
                        last_event_seq = 2,
                    },
                    compaction_records = {},
                },
            })
            if not document then return nil, document_error end
            local writer, writer_error = store.create_writer(target_path, {
                pid = pid,
                started_at = now,
            })
            if writer then
                local temporary_path = target_path .. ".yaca-tmp-" .. hex(random:sub(3))
                local published, publish_error = store.publish(
                    writer,
                    document,
                    temporary_path
                )
                if published then
                    local receipt = readonly({
                        outcome = "published",
                        durable = true,
                        context_path = target_path,
                        logical_path = logical_path,
                        context_hash = context_hash,
                        display_name = display_name,
                        generation = document.generation,
                        event_count = document.event_count,
                        first_sequence = 1,
                        last_sequence = 2,
                        turn_id = "turn-1",
                        message_id = "turn-1:message:1",
                        config_snapshot = snapshot.config,
                        model_snapshot = snapshot.model,
                        permission_snapshot = snapshot.permission,
                        prompt_snapshot = snapshot.prompt,
                        tool_registry_snapshot = snapshot.tool_registry,
                        view_manifest_snapshot = snapshot.view,
                    }, "first Context publication receipt")
                    active = { writer = writer, document = document, receipt = receipt }
                    return receipt
                end
                local collision = type(publish_error) == "table"
                    and (publish_error.code == "DestinationExists"
                        or publish_error.code == "LockConflict")
                local _, close_error = close_writer(writer, publish_error)
                if close_error and close_error.code == "ContextPublicationUnknown" then
                    return nil, close_error
                end
                if not collision then return nil, publish_error end
            elseif type(writer_error) ~= "table"
                or (writer_error.code ~= "DestinationExists"
                    and writer_error.code ~= "LockConflict")
            then
                return nil, writer_error
            end
        end
        return nil, failure(
            "ContextNameExhausted",
            "secure random Context names collided through the bounded retry limit"
        )
    end

    ---Builds a bounded quoted-data model view from the exact current durable
    -- Fact prefix. A changed view is only a candidate until AgentLoop commits
    -- the matching model_view_published event through this journal.
    function service.prepare_view(specification)
        if closed then
            return nil, failure("ContextPublicationClosed", "Context model view is closed")
        end
        if journal_failure then return nil, journal_failure end
        if not active or not active.document then
            return nil, failure("ContextNotPublished", "Context model view has no durable source")
        end
        local allowed = {
            expected_context_generation = true,
            expected_last_sequence = true,
            current_manifest_ref = true,
        }
        if type(specification) ~= "table" then
            return nil, failure("InvalidModelView", "model view observation is required")
        end
        for key in pairs(specification) do
            if type(key) ~= "string" or not allowed[key] then
                return nil, failure("InvalidModelView", "model view observation is ambiguous")
            end
        end
        local document = active.document
        local manifest = document.model_view.active_manifest
        if specification.expected_context_generation ~= document.generation
            or specification.expected_last_sequence ~= document.event_count
            or specification.current_manifest_ref ~= manifest.digest
        then
            return nil, failure(
                "StaleModelView",
                "model view observation does not bind the active Context"
            )
        end
        local view
        local changed = manifest.first_event_seq ~= (document.event_count == 0 and 0 or 1)
            or manifest.last_event_seq ~= document.event_count
        if not changed then
            view = model_views[manifest.digest]
            if not view then
                return nil, failure(
                    "ModelViewUnavailable",
                    "active model view body is not available to this writer"
                )
            end
        else
            local view_error
            view, view_error = cache_model_view(document.facts, document.generation)
            if not view then return nil, view_error end
            changed = view.digest ~= manifest.digest
                or view.first_sequence ~= manifest.first_event_seq
                or view.last_sequence ~= manifest.last_event_seq
        end
        return readonly({
            digest = view.digest,
            first_sequence = view.first_sequence,
            last_sequence = view.last_sequence,
            changed = changed,
            replaces_manifest_ref = manifest.digest,
            binding = specification,
        }, "prepared durable model view")
    end

    ---Returns one body only after its manifest is the active durable view.
    function service.resolve_view(digest)
        if closed then
            return nil, failure("ContextPublicationClosed", "Context model view is closed")
        end
        if not active or type(digest) ~= "string"
            or digest ~= active.document.model_view.active_manifest.digest
        then
            return nil, failure("StaleModelView", "model view is not the active durable manifest")
        end
        local view = model_views[digest]
        if not view then
            return nil, failure("ModelViewUnavailable", "durable model view body is unavailable")
        end
        return view
    end

    ---Commits one AgentLoop batch through the already-owned writer lease. Each
    -- acknowledged batch is a fully validated replacement generation.
    function service.commit(batch)
        if closed then
            return nil, failure("ContextPublicationClosed", "Context journal is closed")
        end
        if journal_failure then return nil, journal_failure end
        if not active or not active.writer then
            return nil, failure("ContextNotPublished", "Context journal has no durable owner")
        end
        local allowed = {
            barrier_id = true,
            first_sequence = true,
            last_sequence = true,
            event_count = true,
            expected_context_generation = true,
            events = true,
        }
        if type(batch) ~= "table" then
            return nil, failure("InvalidContextBatch", "Context journal batch is required")
        end
        for key in pairs(batch) do
            if type(key) ~= "string" or not allowed[key] then
                return nil, failure("InvalidContextBatch", "Context journal batch is ambiguous")
            end
        end
        local count = dense_count(batch.events)
        local previous_generation = active.document.generation
        local first_sequence = active.document.event_count + 1
        if not valid_text(batch.barrier_id, 256) or batch.barrier_id == ""
            or count == nil or count < 1
            or batch.event_count ~= count
            or batch.first_sequence ~= first_sequence
            or batch.last_sequence ~= first_sequence + count - 1
            or batch.expected_context_generation ~= previous_generation
        then
            return nil, failure(
                "InvalidContextBatch",
                "Context journal batch does not bind the current generation"
            )
        end
        local view_publications = 0
        for _, event in ipairs(batch.events) do
            if event.type == "model_view_published" then
                view_publications = view_publications + 1
                local fields = event.fields
                local prepared = type(fields) == "table"
                    and model_views[fields.manifestDigest]
                    or nil
                local current = active.document.model_view.active_manifest
                if view_publications > 1
                    or not prepared
                    or fields.firstEventSeq ~= tostring(prepared.first_sequence)
                    or fields.lastEventSeq ~= tostring(prepared.last_sequence)
                    or fields.replacesManifestDigest ~= current.digest
                then
                    return nil, failure(
                        "InvalidModelView",
                        "Context journal model-view event has no exact prepared body"
                    )
                end
            end
        end
        local observed, time_error = system.utc_now()
        if not observed then return nil, time_error end
        local updated_at, next_error = next_utc_time(
            observed,
            active.document.header.updated_at
        )
        if not updated_at then return nil, next_error end
        local document, document_error = schema.append_events(active.document, {
            updated_at = updated_at,
            events = batch.events,
        })
        if not document then return nil, document_error end

        local published, publish_error
        for _ = 1, admitted.maximum_create_attempts do
            local random, random_error = system.secure_random(8)
            if type(random) ~= "string" or #random ~= 8 then
                return nil, random_error or failure(
                    "SecureRandomUnavailable",
                    "Context journal temporary name requires secure random bytes"
                )
            end
            published, publish_error = store.publish(
                active.writer,
                document,
                active.receipt.context_path .. ".yaca-tmp-" .. hex(random)
            )
            if published then break end
            if type(publish_error) ~= "table"
                or publish_error.code ~= "DestinationExists"
            then
                journal_failure = publish_error or failure(
                    "ContextPublicationUnknown",
                    "Context journal publication returned no outcome"
                )
                return nil, journal_failure
            end
        end
        if not published then
            return nil, failure(
                "ContextTemporaryNameExhausted",
                "Context journal temporary names collided through the retry limit"
            )
        end
        if type(published) ~= "table"
            or published.generation ~= previous_generation + 1
            or published.event_count ~= batch.last_sequence
        then
            journal_failure = failure(
                "ContextPublicationUnknown",
                "Context journal returned an inexact durable receipt"
            )
            return nil, journal_failure
        end
        active.document = document
        local status_values = {}
        for key, value in pairs(active.receipt) do status_values[key] = value end
        status_values.generation = document.generation
        status_values.event_count = document.event_count
        status_values.last_sequence = document.event_count
        active.receipt = readonly(status_values, "Context publication receipt")
        return true, readonly({
            barrier_id = batch.barrier_id,
            first_sequence = batch.first_sequence,
            last_sequence = batch.last_sequence,
            event_count = batch.event_count,
            binding = batch,
            previous_context_generation = previous_generation,
            context_generation = document.generation,
        }, "Context journal receipt")
    end

    ---Returns the durable journal used by context.new_operation_service. Each
    -- commit is translated into the same sequenced Context stream owned by
    -- this publication lease. Receipts are retained until the Runtime tool
    -- adapter adopts the external barrier into its local sequence waterline.
    function service.operation_journal()
        if operation_journal then return operation_journal end
        local journal = {}

        local function turn_id(tool_call_id)
            if type(tool_call_id) ~= "string" then return false end
            return tool_call_id:match("^(.-):tool:[1-9][0-9]*$") or false
        end

        local function commit_record(record, digest, kind)
            if not active or not active.document then
                return false, failure(
                    "ContextNotPublished",
                    "durable operation journal has no active Context"
                )
            end
            local status = active.receipt
            local first_sequence = status.event_count + 1
            local events
            if kind == "intent" then
                events = { {
                    seq = first_sequence,
                    type = "operation_intent",
                    turn_id = turn_id(record.tool_call_id),
                    fields = {
                        operationId = record.operation_id,
                        toolCallId = record.tool_call_id,
                        kind = record.kind,
                        targetIdentity = record.target_identity,
                        expectedDigest = record.expected_digest,
                    },
                } }
            else
                local operation_fields = {
                    operationId = record.operation_id,
                    status = record.status,
                    evidence = record.evidence,
                }
                if record.error_id ~= false then
                    operation_fields.errorId = record.error_id
                end
                local tool_fields = {
                    toolCallId = record.tool_call_id,
                    status = record.tool_status,
                    body = record.tool_body,
                    truncated = tostring(record.tool_truncated),
                    rawBytes = tostring(record.tool_raw_bytes),
                }
                if record.tool_digest ~= false then
                    tool_fields.digest = record.tool_digest
                end
                if record.tool_error_id ~= false then
                    tool_fields.errorId = record.tool_error_id
                end
                events = {
                    {
                        seq = first_sequence,
                        type = "operation_result",
                        turn_id = turn_id(record.tool_call_id),
                        fields = operation_fields,
                    },
                    {
                        seq = first_sequence + 1,
                        type = "tool_result",
                        turn_id = turn_id(record.tool_call_id),
                        fields = tool_fields,
                    },
                }
            end
            local batch = {
                barrier_id = "operation-" .. kind .. ":" .. digest,
                first_sequence = first_sequence,
                last_sequence = first_sequence + #events - 1,
                event_count = #events,
                expected_context_generation = status.generation,
                events = events,
            }
            local committed, receipt = service.commit(batch)
            if committed ~= true then return false, receipt end
            local slot = { digest = digest, receipt = receipt }
            if kind == "intent" then
                operation_intent_receipts[record.operation_id] = slot
            else
                operation_result_receipts[record.operation_id] = slot
            end
            return true, digest
        end

        function journal.commit_intent(record, digest)
            return commit_record(record, digest, "intent")
        end

        function journal.commit_result(record, digest)
            return commit_record(record, digest, "result")
        end

        local function take(receipts, operation_id, digest)
            local slot = receipts[operation_id]
            if not slot or (digest ~= nil and slot.digest ~= digest) then
                return nil, failure(
                    "OperationJournalContract",
                    "Runtime requested an unbound durable operation receipt"
                )
            end
            receipts[operation_id] = nil
            return slot.receipt
        end

        function journal.take_intent_receipt(operation_id, digest)
            return take(operation_intent_receipts, operation_id, digest)
        end

        function journal.take_result_receipt(operation_id, digest)
            return take(operation_result_receipts, operation_id, digest)
        end

        operation_journal = readonly(journal, "Context operation journal")
        return operation_journal
    end

    function service.status()
        if active then return active.receipt end
        return readonly({ durable = false, closed = closed }, "Context publication status")
    end

    function service.close()
        if closed then return false end
        closed = true
        if not active then return true end
        local writer = active.writer
        active.writer = false
        local released, release_error = store.close_writer(writer)
        if not released then return nil, release_error end
        return true
    end

    return readonly(service, "Context publication service")
end

---Creates a bounded in-memory chat draft without scanning or writing Contexts.
-- The draft owns only not-yet-durable session selectors. It cannot accept a
-- first main message until the later Context publication service is attached.
-- @param generation table Immutable Agent-ready ConfigGeneration.
-- @param workspace table Validated path/identity/enterable observation.
-- @param options table Contains maximum_draft_bytes.
-- @return table|nil draft Immutable facade over the owned draft state.
-- @return table|nil err Structured validation failure.
function M.new_draft(generation, workspace, options, publication)
    local admitted_generation, generation_error = validate_generation(generation)
    if not admitted_generation then return nil, generation_error end
    local admitted_workspace, workspace_error = validate_workspace(workspace)
    if not admitted_workspace then return nil, workspace_error end
    if type(options) ~= "table" then
        return nil, failure("InvalidSessionOptions", "session limits are required")
    end
    for key in pairs(options) do
        if key ~= "maximum_draft_bytes" then
            return nil, failure("InvalidSessionOptions", "session options contain an unknown field")
        end
    end
    if not valid_integer(options.maximum_draft_bytes, 1) then
        return nil, failure("InvalidSessionOptions", "maximum_draft_bytes must be positive")
    end
    if publication ~= nil and (type(publication) ~= "table"
        or type(publication.publish_first) ~= "function"
        or type(publication.close) ~= "function")
    then
        return nil, failure(
            "InvalidSessionPublication",
            "draft publication must expose publish_first and close"
        )
    end
    if not valid_text(generation.context_prompt or "", options.maximum_draft_bytes) then
        return nil, failure("DraftLimit", "initial Context Prompt exceeds the draft limit")
    end

    local lifecycle = "not-saved"
    local settings = {
        model = generation.current_model,
        permission = generation.current_permission,
        double_check = generation.effective_double_check,
        double_check_override = "inherit",
        double_check_goal = generation.effective_double_check_goal or "",
        double_check_goal_override = "inherit",
        context_prompt = generation.context_prompt or "",
        auto_rename_disabled = generation.auto_rename_disabled == true,
    }
    if settings_bytes(settings) > options.maximum_draft_bytes then
        return nil, failure("DraftLimit", "initial session settings exceed the draft limit")
    end
    local draft = {}
    local publication_receipt
    local published_message
    local published_source
    local close_failure

    local function require_open()
        if lifecycle ~= "not-saved" then
            return nil, failure("SessionClosed", "the unsaved chat draft is closed")
        end
        return true
    end

    local function status()
        return readonly({
            lifecycle = lifecycle,
            durable = publication_receipt ~= nil,
            context_path = publication_receipt and publication_receipt.context_path or false,
            context_hash = publication_receipt and publication_receipt.context_hash or false,
            display_name = publication_receipt and publication_receipt.display_name or "not saved",
            workspace = admitted_workspace.path,
            config_generation = generation.id,
            model = settings.model,
            permission = settings.permission,
            double_check = settings.double_check,
            double_check_goal = settings.double_check_goal,
            context_prompt = settings.context_prompt,
            auto_rename_disabled = settings.auto_rename_disabled,
        }, "session status")
    end

    ---Returns a fresh immutable projection of the owned draft state.
    function draft.status()
        return status()
    end

    ---Updates only session-whitelisted settings before the first main message.
    -- @param changes table Model, Permission, DoubleCheck, goal, and Prompt fields.
    -- @return table|nil status New immutable draft projection.
    -- @return table|nil err Unknown, invalid, or closed-state failure.
    function draft.update(changes)
        local open, open_error = require_open()
        if not open then return nil, open_error end
        if type(changes) ~= "table" then
            return nil, failure("InvalidDraftUpdate", "draft changes must be a table")
        end
        local allowed = {
            model = true,
            permission = true,
            double_check = true,
            double_check_goal = true,
            context_prompt = true,
            auto_rename_disabled = true,
        }
        for key in pairs(changes) do
            if type(key) ~= "string" or not allowed[key] then
                return nil, failure("InvalidDraftUpdate", "draft update contains an unknown field")
            end
        end
        local next_settings = {}
        for key, value in pairs(settings) do next_settings[key] = value end
        if changes.model ~= nil then
            local model = type(changes.model) == "string"
                and generation.models[changes.model]
                or nil
            if not model or not model.enabled or not model.tools_enabled then
                return nil, failure("ModelUnavailable", "draft Model is unavailable")
            end
            next_settings.model = changes.model
        end
        if changes.permission ~= nil then
            if type(changes.permission) ~= "string"
                or not generation.permissions[changes.permission]
            then
                return nil, failure("PermissionUnavailable", "draft Permission is unavailable")
            end
            next_settings.permission = changes.permission
        end
        if changes.double_check ~= nil then
            if type(changes.double_check) ~= "boolean" then
                return nil, failure("InvalidDraftUpdate", "double_check must be boolean")
            end
            next_settings.double_check = changes.double_check
            next_settings.double_check_override = changes.double_check
        end
        for _, key in ipairs({ "double_check_goal", "context_prompt" }) do
            if changes[key] ~= nil then
                if not valid_text(changes[key], options.maximum_draft_bytes) then
                    return nil, failure("DraftLimit", key .. " exceeds the draft limit")
                end
                local hits, scan_error = generation.scan_registered_secrets(changes[key])
                if not hits then return nil, scan_error end
                if #hits > 0 then
                    return nil, failure(
                        "RegisteredSecret",
                        key .. " matches a registered configuration secret"
                    )
                end
                next_settings[key] = changes[key]
                if key == "double_check_goal" then
                    next_settings.double_check_goal_override = "value"
                end
            end
        end
        if changes.auto_rename_disabled ~= nil then
            if type(changes.auto_rename_disabled) ~= "boolean" then
                return nil, failure(
                    "InvalidDraftUpdate",
                    "auto_rename_disabled must be boolean"
                )
            end
            next_settings.auto_rename_disabled = changes.auto_rename_disabled
        end
        if settings_bytes(next_settings) > options.maximum_draft_bytes then
            return nil, failure("DraftLimit", "session settings exceed the draft limit")
        end
        settings = next_settings
        return status()
    end

    ---Publishes the first main input before any Model or tool may be started.
    function draft.begin_main(message, source)
        local open, open_error = require_open()
        if not open then return nil, open_error end
        if not publication then
            return nil, failure(
                "ContextPublicationUnavailable",
                "the first main message cannot be accepted before Context storage is attached"
            )
        end
        source = source or "main"
        if not valid_text(message, options.maximum_draft_bytes) or message == ""
            or not valid_text(source, 64) or source == ""
            or source:match("^[A-Za-z0-9][A-Za-z0-9._:-]*$") == nil
        then
            return nil, failure("InvalidDraft", "first main message or source is invalid")
        end
        local hits, scan_error = generation.scan_registered_secrets(message)
        if not hits then return nil, scan_error end
        if #hits > 0 then
            return nil, failure(
                "RegisteredSecret",
                "first main message matches a registered configuration secret"
            )
        end
        local called, receipt, publish_error = pcall(publication.publish_first, {
            generation = generation,
            workspace = admitted_workspace,
            settings = {
                model = settings.model,
                permission = settings.permission,
                double_check = settings.double_check,
                double_check_override = settings.double_check_override,
                double_check_goal = settings.double_check_goal,
                double_check_goal_override = settings.double_check_goal_override,
                context_prompt = settings.context_prompt,
                auto_rename_disabled = settings.auto_rename_disabled,
            },
            message = message,
            source = source,
        })
        if not called then
            return nil, failure(
                "ContextPublicationFailure",
                "first Context publication raised an exception"
            )
        end
        if type(receipt) ~= "table" or receipt.durable ~= true
            or type(receipt.context_path) ~= "string"
            or type(receipt.context_hash) ~= "string"
            or type(receipt.display_name) ~= "string"
        then
            return nil, publish_error or failure(
                "ContextPublicationFailure",
                "first Context publication returned no exact durable receipt"
            )
        end
        publication_receipt = receipt
        published_message = message
        published_source = source
        lifecycle = "saved"
        return receipt
    end

    ---Returns the exact precommitted first-turn handoff for AgentLoop. The
    -- handoff exists only after begin_main received a durable receipt.
    function draft.agent_handoff()
        if not publication_receipt then
            return nil, failure(
                "ContextNotPublished",
                "Agent handoff requires a durable first Context generation"
            )
        end
        return readonly({
            input = readonly({
                text = published_message,
                source = published_source,
                config_generation = publication_receipt.config_snapshot,
                model_snapshot = publication_receipt.model_snapshot,
                permission_snapshot = publication_receipt.permission_snapshot,
                prompt_snapshot = publication_receipt.prompt_snapshot,
                tool_registry_snapshot = publication_receipt.tool_registry_snapshot,
                view_manifest_ref = publication_receipt.view_manifest_snapshot,
                double_check = settings.double_check,
                context_generation = publication_receipt.generation,
            }, "published first-turn input"),
            binding = readonly({
                first_sequence = publication_receipt.first_sequence,
                last_sequence = publication_receipt.last_sequence,
                context_generation = publication_receipt.generation,
                turn_id = publication_receipt.turn_id,
                message_id = publication_receipt.message_id,
                text = published_message,
                source = published_source,
                config_snapshot = publication_receipt.config_snapshot,
                model_snapshot = publication_receipt.model_snapshot,
                permission_snapshot = publication_receipt.permission_snapshot,
                prompt_snapshot = publication_receipt.prompt_snapshot,
                tool_registry_snapshot = publication_receipt.tool_registry_snapshot,
                view_manifest_snapshot = publication_receipt.view_manifest_snapshot,
            }, "published first-turn binding"),
        }, "published first-turn handoff")
    end

    ---Closes the in-memory draft without creating any filesystem object.
    function draft.close()
        if lifecycle == "closed" then
            if close_failure then return nil, close_failure end
            return false
        end
        lifecycle = "closed"
        if publication_receipt then
            local called, closed_publication, close_error = pcall(publication.close)
            if not called or not closed_publication then
                close_failure = close_error or failure(
                    "ContextLeaseUnknown",
                    "saved Context writer could not be released"
                )
                return nil, close_failure
            end
        end
        return true
    end

    ---Returns the frozen generation used to create this draft.
    function draft.config_generation()
        return generation
    end

    return readonly(draft, "unsaved chat draft")
end

---Creates the saved-session input owner over one typed AgentLoop.
-- Draft observation is captured when text is staged, so a delayed submission
-- cannot silently redirect itself to a newer Context generation or turn.
-- @param loop table Typed Runtime AgentLoop facade.
-- @param options table Contains maximum_draft_bytes.
-- @return table|nil session Readonly saved-session facade.
-- @return table|nil err Structured construction failure.
function M.new_agent_session(loop, options)
    if type(loop) ~= "table"
        or type(loop.status) ~= "function"
        or type(loop.submit_main) ~= "function"
        or type(loop.enqueue) ~= "function"
        or type(loop.steer) ~= "function"
        or type(loop.start_side) ~= "function"
        or type(loop.resolve_yield) ~= "function"
        or type(loop.reply) ~= "function"
        or type(loop.list_queue) ~= "function"
        or type(loop.drop_queue) ~= "function"
        or type(loop.edit_queue) ~= "function"
        or type(loop.reorder_queue) ~= "function"
        or type(loop.clear_queue) ~= "function"
        or type(loop.use_side) ~= "function"
        or type(loop.close) ~= "function"
    then
        return nil, failure("InvalidAgentSession", "a typed AgentLoop is required")
    end
    if type(options) ~= "table" then
        return nil, failure("InvalidSessionOptions", "saved-session limits are required")
    end
    for key in pairs(options) do
        if key ~= "maximum_draft_bytes" then
            return nil, failure("InvalidSessionOptions", "saved-session options are ambiguous")
        end
    end
    if not valid_integer(options.maximum_draft_bytes, 1) then
        return nil, failure("InvalidSessionOptions", "maximum_draft_bytes must be positive")
    end

    local lifecycle = "open"
    local staged
    local session = {}

    local function require_open()
        if lifecycle ~= "open" then
            return nil, failure("SessionClosed", "the saved Agent session is closed")
        end
        return true
    end

    local function observation(status)
        return {
            expected_context_generation = status.context_generation,
            expected_turn_id = status.turn_id,
        }
    end

    local function current_observation()
        return observation(loop:status())
    end

    local function command_from_draft()
        if not staged then return nil, failure("DraftEmpty", "no chat draft is staged") end
        return {
            text = staged.text,
            source = staged.source,
            expected_context_generation = staged.context_generation,
            expected_turn_id = staged.turn_id,
        }
    end

    local function consume_on_success(result, action_error)
        if not result then return nil, action_error end
        staged = nil
        return result
    end

    local function resolve_display(display_id)
        if type(display_id) ~= "string" or not display_id:match("^#[1-9][0-9]*$") then
            return nil, failure("InvalidQueueId", "queue display id is invalid")
        end
        local projection = loop:list_queue()
        for _, item in ipairs(projection.items) do
            if item.display_id == display_id then return item.queue_item_id end
        end
        return nil, failure("QueueItemMissing", "queue display id is not active")
    end

    ---Captures a bounded draft plus the exact Context/turn observation it saw.
    function session:stage(text_value, source)
        local open, open_error = require_open()
        if not open then return nil, open_error end
        source = source or "user"
        if not valid_text(text_value, options.maximum_draft_bytes) or text_value == ""
            or type(source) ~= "string" or source == ""
        then
            return nil, failure("InvalidDraft", "saved-session draft is invalid")
        end
        local status = loop:status()
        staged = {
            text = text_value,
            source = source,
            context_generation = status.context_generation,
            turn_id = status.turn_id,
        }
        return self:draft()
    end

    ---Returns the detached current draft; its text is preserved on lane rejection.
    function session:draft()
        if not staged then return false end
        return readonly({
            text = staged.text,
            source = staged.source,
            context_generation = staged.context_generation,
            turn_id = staged.turn_id,
        }, "saved-session draft")
    end

    ---Submits staged text to reply, supersede-yield, direct-main, or queue by state.
    function session:submit()
        local open, open_error = require_open()
        if not open then return nil, open_error end
        local command, command_error = command_from_draft()
        if not command then return nil, command_error end
        local status = loop:status()
        local result, action_error
        if command.expected_context_generation ~= status.context_generation
            or command.expected_turn_id ~= status.turn_id
        then
            return nil, failure(
                "StaleDraftObservation",
                "draft was preserved because the active Context or turn changed"
            )
        elseif status.state == "Idle" then
            result, action_error = loop:submit_main(command)
        elseif status.state == "WaitingUser"
            and (status.pending_kind == "ask-user"
                or status.pending_kind == "termination-review")
        then
            result, action_error = loop:reply(command.text, command.source)
        elseif status.state == "WaitingUser" and status.pending_kind == "model-yield" then
            command.response_id = status.pending_response_id
            command.action = "supersede"
            result, action_error = loop:resolve_yield(command)
        else
            result, action_error = loop:enqueue(command)
        end
        return consume_on_success(result, action_error)
    end

    ---Explicit queue admission for the staged draft.
    function session:queue()
        local open, open_error = require_open()
        if not open then return nil, open_error end
        local command, command_error = command_from_draft()
        if not command then return nil, command_error end
        local result, action_error = loop:enqueue(command)
        return consume_on_success(result, action_error)
    end

    ---Explicit same-turn steer for the staged draft.
    function session:steer()
        local open, open_error = require_open()
        if not open then return nil, open_error end
        local command, command_error = command_from_draft()
        if not command then return nil, command_error end
        local result, action_error = loop:steer(command)
        return consume_on_success(result, action_error)
    end

    ---Explicit single-concurrency side request for the staged draft.
    function session:side()
        local open, open_error = require_open()
        if not open then return nil, open_error end
        local command, command_error = command_from_draft()
        if not command then return nil, command_error end
        local result, action_error = loop:start_side(command)
        return consume_on_success(result, action_error)
    end

    ---Continues the exact yielded response in a new turn using the staged text.
    function session:continue_response(response_id)
        local open, open_error = require_open()
        if not open then return nil, open_error end
        local command, command_error = command_from_draft()
        if not command then return nil, command_error end
        command.response_id = response_id
        command.action = "continue"
        local result, action_error = loop:resolve_yield(command)
        return consume_on_success(result, action_error)
    end

    function session:queue_list()
        local open, open_error = require_open()
        if not open then return nil, open_error end
        return loop:list_queue()
    end

    function session:queue_drop(display_id, reason)
        local open, open_error = require_open()
        if not open then return nil, open_error end
        local queue_item_id, id_error = resolve_display(display_id)
        if not queue_item_id then return nil, id_error end
        local observed = current_observation()
        observed.queue_item_id = queue_item_id
        observed.reason = reason or "user-drop"
        return loop:drop_queue(observed)
    end

    function session:queue_edit(display_id, text_value)
        local open, open_error = require_open()
        if not open then return nil, open_error end
        if not valid_text(text_value, options.maximum_draft_bytes) or text_value == "" then
            return nil, failure("InvalidDraft", "queue amendment text is invalid")
        end
        local queue_item_id, id_error = resolve_display(display_id)
        if not queue_item_id then return nil, id_error end
        local observed = current_observation()
        observed.queue_item_id = queue_item_id
        observed.text = text_value
        return loop:edit_queue(observed)
    end

    function session:queue_move(display_id, before_display_id)
        local open, open_error = require_open()
        if not open then return nil, open_error end
        local queue_item_id, id_error = resolve_display(display_id)
        if not queue_item_id then return nil, id_error end
        local before_queue_item_id = false
        if before_display_id ~= false then
            before_queue_item_id, id_error = resolve_display(before_display_id)
            if not before_queue_item_id then return nil, id_error end
        end
        local observed = current_observation()
        observed.queue_item_id = queue_item_id
        observed.before_queue_item_id = before_queue_item_id
        return loop:reorder_queue(observed)
    end

    function session:queue_clear(reason)
        local open, open_error = require_open()
        if not open then return nil, open_error end
        local observed = current_observation()
        observed.reason = reason or "user-clear"
        return loop:clear_queue(observed)
    end

    function session:use_side(side_id, lane)
        local open, open_error = require_open()
        if not open then return nil, open_error end
        local observed = current_observation()
        observed.side_id = side_id
        observed.lane = lane
        return loop:use_side(observed)
    end

    function session:clear_draft()
        local existed = staged ~= nil
        staged = nil
        return existed
    end

    function session:status()
        return readonly({
            lifecycle = lifecycle,
            has_draft = staged ~= nil,
            draft = self:draft(),
            loop = loop:status(),
        }, "saved Agent session status")
    end

    function session:close(reason)
        if lifecycle ~= "open" then return false end
        local closed, close_error = loop:close(reason or "session-close")
        if closed == nil then return nil, close_error end
        lifecycle = "closed"
        staged = nil
        return true
    end

    return readonly(session, "saved Agent session")
end

return M
