--[[
Author: WaterRun
Date: 2026-09-23
File: session.lua
Description: Owns the bounded chat draft and first durable Context publication.
]]

local compact = require("compact")
local text = require("text")

local M = {}

-- Construct a structured diagnostic without throwing or formatting its optional fields.
--@param code string Stable diagnostic code used by callers to choose recovery behavior.
--@param message string Human-readable summary supplied by the failing operation.
--@param reason string|nil Optional machine-readable cause or validation rule.
--@return table New diagnostic record; optional non-nil fields are retained without deep copying.
local function failure(code, message, reason)
    local result = { code = code, message = message }
    if reason ~= nil then result.reason = reason end
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
        __metatable = "locked",
    })
end

-- Check the Lua integer subtype and the caller's inclusive lower bound.
--@param value any Candidate value; floats and non-numeric values are rejected.
--@param minimum integer Inclusive minimum accepted by this check.
--@return boolean True only for an integer at least minimum.
local function valid_integer(value, minimum)
    return math.type(value) == "integer" and value >= minimum
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

-- Accept bounded NUL-free UTF-8 used in durable Context fields.
--@param value any Candidate text.
--@param maximum_bytes integer Inclusive byte limit.
--@return boolean True only for valid text within the limit.
local function valid_text(value, maximum_bytes)
    if type(value) ~= "string" or #value > maximum_bytes then return false end
    local valid, metadata = text.validate_utf8(value)
    return valid and not metadata.contains_nul
end

-- Recognize the lowercase hexadecimal SHA-256 digest format.
--@param value any Candidate digest.
--@return boolean True only for exactly 64 lowercase hexadecimal characters.
local function valid_digest(value)
    return type(value) == "string"
        and #value == 64
        and value:match("^[0-9a-f]+$") ~= nil
end

-- Require an enterable workspace before an unsaved chat can be published.
--@param workspace any Candidate workspace selection.
--@return table|nil Path and identity for a validated workspace.
--@return table|nil InvalidWorkspace diagnostic.
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

-- Require an Agent-ready config generation with Model and Permission snapshots.
--@param generation any Candidate immutable configuration generation.
--@return table|nil Original ready generation.
--@return table|nil ModelUnavailable diagnostic.
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

-- Measure the bounded text fields in current Session settings.
--@param settings table Validated Session settings.
--@return integer Sum of Model, Permission, goal, and ContextPrompt bytes.
local function settings_bytes(settings)
    return #settings.model
        + #settings.permission
        + #settings.double_check_goal
        + #settings.context_prompt
end

-- Recognize NUL-free POSIX, drive-absolute, or UNC paths.
--@param path any Candidate native path.
--@return boolean True for a supported absolute path shape.
local function valid_absolute_path(path)
    if type(path) ~= "string" or path == "" or path:find("\0", 1, true) then
        return false
    end
    local normalized = path:gsub("\\", "/")
    return normalized:sub(1, 1) == "/"
        or normalized:match("^[A-Za-z]:/") ~= nil
        or normalized:match("^//[^/]+/[^/]+") ~= nil
end

-- Extract the parent of a native path while preserving a filesystem root.
--@param path any Candidate native path.
--@param platform_kind string windows or posix separator semantics.
--@return string|nil Parent directory, or nil when no parent is represented.
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

-- Join one child name beneath a native platform directory.
--@param root string Parent directory path.
--@param leaf string Child name without a leading separator.
--@param platform_kind string windows or posix.
--@return string Joined native path.
local function join_native(root, leaf, platform_kind)
    local separator = platform_kind == "windows" and "\\" or "/"
    if root:sub(-1) == separator then return root .. leaf end
    return root .. separator .. leaf
end

-- Encode random identifier bytes as uppercase hexadecimal text.
--@param bytes string Raw identifier bytes.
--@return string Two hexadecimal digits per byte.
local function hex(bytes)
    return (bytes:gsub(".",
        -- Encode one raw byte without locale-sensitive formatting.
        --@param byte string One-byte string.
        --@return string Two uppercase hexadecimal digits.
        function(byte)
        return string.format("%02X", byte:byte())
    end))
end

-- Parse a canonical UTC timestamp and reject impossible calendar dates.
--@param value any Candidate YYYY-MM-DDTHH:MM:SSZ text.
--@return table|nil Year, month, day, hour, minute, second components.
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

-- Return a strictly increasing canonical UTC timestamp despite clock regression.
--@param observed string Current UTC clock reading.
--@param previous string Last published UTC timestamp.
--@return string|nil Observed time if later, otherwise previous plus one second.
--@return table|nil Clock format or year-overflow diagnostic.
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

-- Canonically encode acyclic public data for stable binding digests.
--@param value any String, boolean, finite number, or table of supported data.
--@param visiting table|nil Recursion stack used to reject cycles.
--@return string|nil Type-marked deterministic encoding.
--@return table|nil InvalidSnapshot diagnostic for unsupported or cyclic data.
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

-- Bind a public data snapshot to a named safety-digest domain.
--@param safety table Digest service exposing binding_digest.
--@param domain string Domain separator for the snapshot.
--@param value any Acyclic public snapshot data.
--@return string|nil Binding digest.
--@return table|nil Canonicalization or digest error.
local function snapshot_digest(safety, domain, value)
    local bytes, bytes_error = canonical_public(value)
    if not bytes then return nil, bytes_error end
    return safety.binding_digest(domain, { { name = "public", value = bytes } })
end

-- Escape XML metacharacters before adding durable facts to a Model view.
--@param value string Field or attribute text.
--@return string XML-escaped text.
local function model_view_escape(value)
    return value
        :gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
        :gsub('"', "&quot;")
end

-- Render a bounded, digest-bound Model view of durable facts and optional compaction.
--@param safety table Digest service.
--@param facts table Dense chronological Context event array.
--@param context_generation integer Published Context generation.
--@param maximum_bytes integer Maximum rendered view size.
--@param projection table|nil Structured compaction projection and waterline.
--@return table|nil Digest, sequence range, generation, and rendered XML body.
--@return table|nil Invalid view, size, or digest error.
local function render_model_view(
    safety,
    facts,
    context_generation,
    maximum_bytes,
    projection
)
    local count = dense_count(facts)
    if count == nil then
        return nil, failure("InvalidModelView", "Context Facts are not a dense array")
    end
    local fact_limit = projection and projection.fact_limit or count
    local last_sequence = projection and projection.waterline or count
    if not valid_integer(fact_limit, 0)
        or fact_limit > count
        or not valid_integer(last_sequence, fact_limit)
    then
        return nil, failure("InvalidModelView", "model view waterline is invalid")
    end
    local first_sequence = last_sequence == 0 and 0 or 1
    local parts = {
        '<DurableFacts schemaVersion="1" contextGeneration="',
        tostring(context_generation),
        '" firstSequence="',
        tostring(first_sequence),
        '" lastSequence="',
        tostring(last_sequence),
        '">\n',
    }
    local size = 0
    -- Append one rendered fragment without exceeding the Model view budget.
    --@param value string XML fragment to append.
    --@return boolean|nil True after appending.
    --@return table|nil ModelViewLimit diagnostic.
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
    if projection then
        if not valid_text(projection.compaction_id, 256)
            or projection.compaction_id == ""
            or not valid_integer(projection.source_first_seq, 1)
            or not valid_integer(
                projection.source_last_seq,
                projection.source_first_seq
            )
            or not valid_integer(
                projection.source_event_count,
                projection.source_last_seq
            )
            or not valid_integer(
                projection.internal_last_sequence,
                projection.source_event_count
            )
            or projection.internal_last_sequence > last_sequence
            or not valid_text(projection.source_digest, 512)
            or projection.source_digest == ""
            or not valid_text(projection.summary_digest, 512)
            or projection.summary_digest == ""
            or not valid_text(projection.summary, maximum_bytes)
            or projection.summary == ""
            or text.xml_carrier_kind(projection.summary) ~= "text"
        then
            return nil, failure(
                "InvalidModelView",
                "structured compaction projection is invalid"
            )
        end
        added, add_error = add(table.concat({
            '  <StructuredSummary compactionId="',
            model_view_escape(projection.compaction_id),
            '" sourceFirstSeq="', tostring(projection.source_first_seq),
            '" sourceLastSeq="', tostring(projection.source_last_seq),
            '" sourceDigest="', model_view_escape(projection.source_digest),
            '" summaryDigest="', model_view_escape(projection.summary_digest),
            '">', model_view_escape(projection.summary),
            '</StructuredSummary>\n',
        }))
        if not added then return nil, add_error end
    end
    local ask_turns = {}
    for index = 1, fact_limit do
        local event = facts[index]
        if type(event) ~= "table"
            or event.seq ~= index
            or type(event.type) ~= "string"
            or type(event.at) ~= "string"
            or type(event.fields) ~= "table"
        then
            return nil, failure("InvalidModelView", "Context event cannot enter the model view")
        end
        if event.type == "turn_started" and event.fields.kind == "ask"
            and type(event.turn_id) == "string"
        then
            ask_turns[event.turn_id] = true
        end
        -- Ask turns remain complete durable audit facts, but their Model input
        -- and response are not main-turn authority. Only a later queue_item or
        -- steer event created by explicit ask-use is visible to the main view.
        local included = not projection
            or (index > projection.source_last_seq
                and (index <= projection.source_event_count
                    or index > projection.internal_last_sequence))
        if included and not ask_turns[event.turn_id] then
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
                    return nil, failure(
                        "InvalidModelView",
                        "Context field cannot enter the model view"
                    )
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
            last_sequence = last_sequence,
            compaction_id = projection and projection.compaction_id or false,
            body = body,
        }
    )
    if not digest then return nil, digest_error end
    return {
        digest = digest,
        first_sequence = first_sequence,
        last_sequence = last_sequence,
        context_generation = context_generation,
        compaction_id = projection and projection.compaction_id or false,
        body = body,
    }
end

-- Expose a public config generation with the Session's selected settings.
--@param generation table Config generation snapshot.
--@param settings table Current Session Model and Permission choices.
--@return table Public generation fields used by Prompt and Runtime.
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

-- Require an exact no-follow ordinary directory ancestry at a Context mirror path.
--@param path string Requested native path.
--@param snapshot table Direct filesystem inspection of that path.
--@return table|nil Original admitted snapshot.
--@return table|nil Alias or directory-conflict diagnostic.
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

-- Inspect and admit a Context mirror directory without following aliases.
--@param filesystem table Direct filesystem port.
--@param path string Exact native directory path.
--@return table|nil Admitted existing or absent directory snapshot.
--@return table|nil Inspection or ancestry error.
local function inspect_directory(filesystem, path)
    local inspected, snapshot_or_error = filesystem.direct_inspect(path)
    if not inspected then return nil, snapshot_or_error end
    return admit_directory_snapshot(path, snapshot_or_error)
end

-- Create a missing Context directory and prove its postcondition and durability.
--@param filesystem table Direct filesystem and flush port.
--@param path string Exact native directory path.
--@param platform_kind string windows or posix for parent extraction.
--@return table|nil Verified existing or newly created directory snapshot.
--@return table|nil Creation, conflict, or uncertain-durability error.
--@effect May create one directory and flush its parent.
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

-- Verify every required Context publication dependency and operation method.
--@param ports any Candidate publication port bundle.
--@return table|nil Original validated ports.
--@return table|nil InvalidContextPublication diagnostic.
local function validate_publication_ports(ports)
    if type(ports) ~= "table" then
        return nil, failure("InvalidContextPublication", "Context publication ports are required")
    end
    local required = {
        filesystem = {
            "direct_inspect", "direct_reverify", "make_directory", "flush_directory",
        },
        schema = { "build", "append_events", "session_document", "encode", "export" },
        store = { "create_writer", "open_writer", "publish", "close_writer", "verify_writer" },
        path = { "to_logical", "validate_context_name", "context_hash" },
        safety = { "binding_digest", "digest" },
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

-- Validate Context paths and hard publication, view, compaction, and queue limits.
--@param options any Candidate publication limits.
--@return table|nil Original validated options.
--@return table|nil InvalidContextPublication diagnostic.
local function validate_publication_options(options)
    if type(options) ~= "table" then
        return nil, failure("InvalidContextPublication", "Context publication limits are required")
    end
    local allowed = {
        data_root = true,
        platform_kind = true,
        maximum_create_attempts = true,
        maximum_model_view_bytes = true,
        maximum_compaction_source_bytes = true,
        maximum_compaction_identifier_bytes = true,
        default_model_request_limit = true,
        default_tool_call_limit = true,
        maximum_queue_items = true,
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
        or not valid_integer(options.maximum_compaction_source_bytes, 1)
        or not valid_integer(options.maximum_compaction_identifier_bytes, 16)
        or not valid_integer(options.default_model_request_limit, 1)
        or not valid_integer(options.default_tool_call_limit, 1)
        or not valid_integer(options.maximum_queue_items, 1)
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
--@param ports table Filesystem, schema, store, path, safety, Prompt, and system ports.
--@param options table Platform, data root, and hard Context limits.
--@return table|nil Single-owner Context publication service.
--@return table|nil Invalid dependency or option error.
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
    local compaction_journal
    local compaction_lifecycles = {}
    local operation_intent_receipts = {}
    local operation_result_receipts = {}

    -- Render and retain one read-only Model view indexed by its binding digest.
    --@param facts table Published chronological Context events.
    --@param context_generation integer Durable Context generation.
    --@param projection table|nil Structured compaction projection.
    --@param forced_digest string|nil Verified external manifest digest to index this view.
    --@return table|nil Read-only cached Model view.
    --@return table|nil Rendering or forced-digest error.
    local function cache_model_view(
        facts,
        context_generation,
        projection,
        forced_digest
    )
        local candidate, view_error = render_model_view(
            safety,
            facts,
            context_generation,
            admitted.maximum_model_view_bytes,
            projection
        )
        if not candidate then return nil, view_error end
        if forced_digest ~= nil then
            if not valid_text(forced_digest, 512) or forced_digest == "" then
                return nil, failure(
                    "InvalidModelView",
                    "forced compaction manifest digest is invalid"
                )
            end
            candidate.digest = forced_digest
        end
        local frozen = readonly(candidate, "durable model view")
        model_views[candidate.digest] = frozen
        return frozen
    end

    -- Rebuild and hash the durable compaction source and summary before accepting them.
    --@param document table Current verified Context document.
    --@param values table Candidate compaction ranges, digests, summary, and waterline.
    --@return table|nil Verified structured compaction projection.
    --@return table|nil Invalid, stale, or mismatched source/summary diagnostic.
    local function verified_compaction_projection(document, values)
        if type(document) ~= "table"
            or type(values) ~= "table"
            or not valid_text(values.compaction_id, 256)
            or values.compaction_id == ""
            or not valid_integer(values.source_first_seq, 1)
            or values.source_first_seq ~= 1
            or not valid_integer(
                values.source_last_seq,
                values.source_first_seq
            )
            or not valid_integer(
                values.source_event_count,
                values.source_last_seq
            )
            or values.source_event_count > document.event_count
            or not valid_integer(
                values.internal_last_sequence,
                values.source_event_count
            )
            or not valid_integer(values.fact_limit, values.source_event_count)
            or values.fact_limit > document.event_count
            or not valid_integer(values.waterline, values.fact_limit)
            or not valid_text(values.source_digest, 512)
            or values.source_digest == ""
            or not valid_text(values.summary_digest, 512)
            or values.summary_digest == ""
            or not valid_text(values.summary, admitted.maximum_model_view_bytes)
            or values.summary == ""
        then
            return nil, failure(
                "InvalidCompactionProjection",
                "durable compaction projection is incomplete"
            )
        end
        local called, source_bytes, source_error = pcall(
            compact.encode_source,
            document,
            values.source_first_seq,
            values.source_last_seq,
            admitted.maximum_compaction_identifier_bytes,
            admitted.maximum_compaction_source_bytes
        )
        if not called or not source_bytes then
            return nil, called and source_error or failure(
                "InvalidCompactionProjection",
                "canonical compaction source could not be rebuilt"
            )
        end
        local digest_called, source_digest, digest_error = pcall(
            safety.digest,
            source_bytes
        )
        if not digest_called or source_digest ~= values.source_digest then
            return nil, failure(
                "CompactionSourceMismatch",
                digest_called and "durable compaction source digest disagrees"
                    or "durable compaction source digest failed",
                digest_called and (digest_error or source_digest)
                    or "digest-exception"
            )
        end
        digest_called, source_digest, digest_error = pcall(
            safety.digest,
            values.summary
        )
        if not digest_called or source_digest ~= values.summary_digest then
            return nil, failure(
                "CompactionSummaryMismatch",
                digest_called and "durable compaction summary digest disagrees"
                    or "durable compaction summary digest failed",
                digest_called and (digest_error or source_digest)
                    or "digest-exception"
            )
        end
        return {
            compaction_id = values.compaction_id,
            source_first_seq = values.source_first_seq,
            source_last_seq = values.source_last_seq,
            source_event_count = values.source_event_count,
            internal_last_sequence = values.internal_last_sequence,
            source_digest = values.source_digest,
            summary_digest = values.summary_digest,
            summary = values.summary,
            fact_limit = values.fact_limit,
            waterline = values.waterline,
        }
    end

    -- Link an active manifest to its accepted compaction record and publication bracket.
    --@param document table Verified durable Context document.
    --@param manifest table Active Model view manifest.
    --@return table|nil Verified compaction projection.
    --@return integer|table View generation on success, or structured error on failure.
    local function durable_compaction_projection(document, manifest)
        local compaction_id = manifest.compaction_id
        if not compaction_id then
            return nil, failure(
                "InvalidCompactionProjection",
                "active manifest has no compaction identity"
            )
        end
        local record
        for _, candidate in ipairs(document.model_view.compaction_records) do
            if candidate.id == compaction_id then record = candidate end
        end
        if not record or record.status ~= "ok" or type(record.summary) ~= "string" then
            return nil, failure(
                "CompactionRecordUnavailable",
                "active compaction record is missing or not accepted"
            )
        end
        local terminal
        local initial_publication
        local active_publication
        for _, event in ipairs(document.facts) do
            if event.type == "compaction"
                and event.fields.compactionId == compaction_id
            then
                terminal = event
            elseif event.type == "model_view_published"
                and event.fields.compactionId == compaction_id
            then
                if event.fields.manifestDigest == manifest.digest then
                    active_publication = event
                end
                if terminal and not initial_publication then
                    initial_publication = event
                end
            end
        end
        local fields = terminal and terminal.fields or nil
        local source_event_count = fields and tonumber(fields.sourceEventCount)
        local view_generation = active_publication
            and tonumber(active_publication.fields.viewContextGeneration)
        local initial_view_generation = initial_publication
            and tonumber(initial_publication.fields.viewContextGeneration)
        if not fields
            or fields.status ~= "ok"
            or fields.summary ~= record.summary
            or fields.manifestDigest == nil
            or not initial_publication
            or initial_publication.seq ~= terminal.seq + 1
            or initial_publication.fields.firstEventSeq ~= "1"
            or initial_publication.fields.lastEventSeq
                ~= tostring(initial_publication.seq)
            or initial_publication.fields.manifestDigest ~= fields.manifestDigest
            or not valid_integer(source_event_count, record.source_last_seq)
            or source_event_count >= terminal.seq
            or not valid_integer(initial_view_generation, 1)
            or tonumber(fields.viewContextGeneration) ~= initial_view_generation
            or not active_publication
            or not valid_integer(view_generation, 1)
        then
            return nil, failure(
                "CompactionRecordUnavailable",
                "accepted compaction bracket is incomplete"
            )
        end
        local projection, projection_error = verified_compaction_projection(
            document,
            {
                compaction_id = compaction_id,
                source_first_seq = record.source_first_seq,
                source_last_seq = record.source_last_seq,
                source_event_count = source_event_count,
                internal_last_sequence = initial_publication.seq,
                source_digest = record.source_digest,
                summary_digest = fields.summaryDigest,
                summary = record.summary,
                fact_limit = manifest.last_event_seq,
                waterline = manifest.last_event_seq,
            }
        )
        if not projection then return nil, projection_error end
        return projection, view_generation
    end

    -- Recreate the active compacted Model view from durable Context evidence.
    --@param document table Verified Context document with active compacted manifest.
    --@return table|nil Cached read-only Model view.
    --@return table|nil Compaction or view validation error.
    local function rebuild_active_compaction_view(document)
        local manifest = document.model_view.active_manifest
        local projection, view_generation = durable_compaction_projection(
            document,
            manifest
        )
        if not projection then return nil, view_generation end
        return cache_model_view(
            document.facts,
            view_generation,
            projection,
            manifest.digest
        )
    end

    -- Recreate an active Model view from durable facts and its manifest digest.
    --@param document table Verified Context document.
    --@return table|nil Cached read-only plain or compacted Model view.
    --@return table|nil Manifest or rebuild error.
    local function rebuild_active_model_view(document)
        local manifest = document.model_view.active_manifest
        if manifest.compaction_id then
            return rebuild_active_compaction_view(document)
        end
        if manifest.first_event_seq ~= (manifest.last_event_seq == 0 and 0 or 1)
            or manifest.last_event_seq > document.event_count
        then
            return nil, failure(
                "ModelViewUnavailable",
                "plain active Model view has an invalid durable range"
            )
        end
        local facts = {}
        for index = 1, manifest.last_event_seq do facts[index] = document.facts[index] end
        -- Plain Model-view publications before v0.1 did not persist their
        -- Context generation. The event cap makes this exact bounded search
        -- preferable to trusting a wall-clock or inventing sidecar state.
        for generation = 1, document.generation do
            local candidate, candidate_error = cache_model_view(facts, generation)
            if not candidate then return nil, candidate_error end
            if candidate.digest == manifest.digest
                and candidate.first_sequence == manifest.first_event_seq
                and candidate.last_sequence == manifest.last_event_seq
            then
                return candidate
            end
            model_views[candidate.digest] = nil
        end
        return nil, failure(
            "ModelViewUnavailable",
            "plain active Model view cannot be rebuilt from durable facts"
        )
    end

    -- Build the no-follow Context mirror directories for a logical workspace path.
    --@param workspace_path string Validated native workspace path.
    --@return string|nil Native mirror directory path.
    --@return string|table Logical workspace path on success, or error on failure.
    --@return table|nil Final admitted directory snapshot.
    --@effect May create and flush missing Context mirror directories.
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

    -- Assemble a purpose-bound Prompt snapshot from selected config and message.
    --@param generation table Agent-ready config generation.
    --@param settings table Current Model, Permission, and ContextPrompt settings.
    --@param message string User input for this request.
    --@param purpose string|nil main or ask request purpose; defaults to main.
    --@return table|nil Prompt bundle with digest and tool mode.
    --@return table|nil Missing selection or Prompt assembly error.
    local function prompt_bundle(generation, settings, message, purpose)
        local model = generation.models[settings.model]
        local permission = generation.permissions[settings.permission]
        if type(model) ~= "table" or type(permission) ~= "table" then
            return nil, failure("SnapshotUnavailable", "selected Model or Permission vanished")
        end
        purpose = purpose or "main"
        return prompt:assemble({
            purpose = purpose,
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
            tool_mode = purpose == "ask" and "none" or "registered",
        })
    end

    -- Bind the selected Model, Permission, config, Prompt, registry, and turn caps.
    --@param specification table Generation, Session settings, message, and request kind.
    --@return table|nil Digests and bounded Agent turn limits.
    --@return table|nil Missing selection, excessive limit, or digest error.
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
            specification.message,
            specification.kind
        )
        if not bundle then return nil, bundle_error end
        local model_request_limit = generation.agent.max_turn_model_requests
            or admitted.default_model_request_limit
        local tool_call_limit = generation.agent.max_turn_tool_calls
            or admitted.default_tool_call_limit
        local queue_limit = generation.agent.queue_max_items
        if not valid_integer(model_request_limit, 1)
            or model_request_limit > admitted.default_model_request_limit
            or not valid_integer(tool_call_limit, 1)
            or tool_call_limit > admitted.default_tool_call_limit
            or not valid_integer(queue_limit, 1)
            or queue_limit > admitted.maximum_queue_items
        then
            return nil, failure(
                "SnapshotUnavailable",
                "configured Agent limits exceed the release turn caps"
            )
        end
        return {
            model = model_digest,
            permission = permission_digest,
            config = config_digest,
            prompt = bundle.digest,
            tool_registry = admitted_ports.tool_registry.digest,
            model_request_limit = model_request_limit,
            tool_call_limit = tool_call_limit,
            queue_limit = queue_limit,
        }
    end

    -- Project durable Session overrides into config-generation selector fields.
    --@param document table Verified Context document.
    --@return table Model, Permission, double-check, prompt, and rename overrides.
    local function document_overrides(document)
        local goal = document.session.double_check_goal_override
        return {
            CurrentModel = document.session.current_model.name,
            CurrentPermission = document.session.current_permission.name,
            DoubleCheckOverride = document.session.double_check_override,
            DoubleCheckGoalOverride = goal.mode == "value" and goal.value or "inherit",
            ContextPrompt = document.session.context_prompt,
            AutoRenameDisabled = document.header.auto_rename_disabled == true,
        }
    end

    -- Read Session overrides from the currently owned durable Context.
    --@param none This closure takes no arguments.
    --@return table|nil Current override projection, or nil before opening a Context.
    local function durable_context_overrides()
        if not active or not active.document then return nil end
        return document_overrides(active.document)
    end

    -- Check whether a config generation implements every durable Session override.
    --@param generation table Candidate Agent-ready config generation.
    --@param overrides table Current durable Context selector and setting values.
    --@return boolean True only when the generation matches all effective choices.
    local function generation_matches_context(generation, overrides)
        if type(generation) ~= "table"
            or generation.agent_ready ~= true
            or generation.current_model ~= overrides.CurrentModel
            or generation.current_permission ~= overrides.CurrentPermission
            or generation.context_prompt ~= overrides.ContextPrompt
            or generation.auto_rename_disabled ~= overrides.AutoRenameDisabled
        then
            return false
        end
        if type(overrides.DoubleCheckOverride) == "boolean"
            and generation.effective_double_check ~= overrides.DoubleCheckOverride
        then
            return false
        end
        return overrides.DoubleCheckGoalOverride == "inherit"
            or generation.effective_double_check_goal == overrides.DoubleCheckGoalOverride
    end

    -- Copy a flat Session override map before applying one management change.
    --@param source table Existing override fields.
    --@return table Shallow independent map of the same fields.
    local function copy_overrides(source)
        local result = {}
        for key, value in pairs(source) do result[key] = value end
        return result
    end

    -- Bind an enabled Model or available Permission selector to its exact config snapshot.
    --@param generation table Current config generation.
    --@param name string CurrentModel or CurrentPermission field name.
    --@param selector string Selected Model or Permission name.
    --@return string|nil Snapshot binding digest.
    --@return table|nil Unavailable selector or digest error.
    local function selector_snapshot(generation, name, selector)
        local values
        local domain
        if name == "CurrentModel" then
            values = generation.models[selector]
            domain = "yaca-model-snapshot-v1"
            if type(values) ~= "table" or values.enabled ~= true
                or values.tools_enabled ~= true
            then
                return nil, failure(
                    "ModelUnavailable",
                    "selected Context Model cannot run the Agent"
                )
            end
        else
            values = generation.permissions[selector]
            domain = "yaca-permission-snapshot-v1"
            if type(values) ~= "table" then
                return nil, failure(
                    "PermissionUnavailable",
                    "selected Context Permission is unavailable"
                )
            end
        end
        return snapshot_digest(safety, domain, {
            name = selector,
            generation = generation.id,
            values = values,
        })
    end

    -- Read one canonical durable Session override value from a Context document.
    --@param document table Verified Context document.
    --@param name string Override field name.
    --@return any Selector record, boolean, goal mode, or ContextPrompt text.
    local function override_value(document, name)
        if name == "CurrentModel" then
            return {
                name = document.session.current_model.name,
                snapshot_digest = document.session.current_model.snapshot_digest,
            }
        end
        if name == "CurrentPermission" then
            return {
                name = document.session.current_permission.name,
                snapshot_digest = document.session.current_permission.snapshot_digest,
            }
        end
        if name == "DoubleCheckOverride" then
            return document.session.double_check_override
        end
        if name == "DoubleCheckGoalOverride" then
            local goal = document.session.double_check_goal_override
            return goal.mode == "value"
                and { mode = "value", value = goal.value }
                or { mode = "inherit" }
        end
        return document.session.context_prompt
    end

    -- Hash one named Session override value for publication evidence.
    --@param name string Override field name.
    --@param value any Canonical override value.
    --@return string|nil Binding digest.
    --@return table|nil Snapshot or digest error.
    local function override_digest(name, value)
        return snapshot_digest(safety, "yaca-session-override-value-v1", {
            name = name,
            value = value,
        })
    end

    -- Release a failed Context writer while preserving uncertainty about release.
    --@param writer table Open Context writer owned by this service.
    --@param original_error table Original publication failure.
    --@return nil Publication remains failed.
    --@return table Original error, or ContextPublicationUnknown if writer close fails.
    --@effect Closes the writer lease.
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

    -- Build a lifecycle document whose Model view manifest matches its new facts.
    --@param document table Verified previous Context document.
    --@param mutation table Rename, import, repair, or setting mutation fields.
    --@return table|nil Candidate next Context document.
    --@return table Model view on success, or structured error on failure.
    local function management_document(document, mutation)
        local manifest = document.model_view.active_manifest
        -- Let the schema form the lifecycle event, then compute its real
        -- plain/compacted view. The provisional document is never published.
        local candidate, candidate_error = schema.lifecycle_document(document, mutation)
        if not candidate then return nil, candidate_error end
        local facts = {}
        for index = 1, candidate.event_count - 1 do facts[index] = candidate.facts[index] end
        local projection
        if manifest.compaction_id then
            projection, candidate_error = durable_compaction_projection(document, manifest)
            if not projection then return nil, candidate_error end
            projection.fact_limit = #facts
            projection.waterline = #facts
        end
        local view
        view, candidate_error = cache_model_view(facts, candidate.generation, projection)
        if not view then return nil, candidate_error end
        mutation.view_manifest_digest = view.digest
        candidate, candidate_error = schema.lifecycle_document(document, mutation)
        if not candidate then return nil, candidate_error end
        local next_manifest = candidate.model_view.active_manifest
        if next_manifest.digest ~= view.digest
            or next_manifest.first_event_seq ~= view.first_sequence
            or next_manifest.last_event_seq ~= view.last_sequence
            or (next_manifest.compaction_id or false) ~= view.compaction_id
        then
            return nil, failure("InvalidModelView", "Context lifecycle view binding is inexact")
        end
        return candidate, view
    end

    local rebind_plans = {}
    local import_plans = {}
    local repair_plans = {}

    -- Bind an offline management request to its exact inspected Context path.
    --@param specification table Context path, logical path, and inspection credential.
    --@param allow_corrupt string|boolean|nil Repair or delete allowance for damaged headers.
    --@return string|nil Exact physical path within the logical mirror.
    --@return string|table Context hash on success, or binding error on failure.
    local function bound_management_path(specification, allow_corrupt)
        local credential = specification.expected_credential
        local missing = allow_corrupt == "repair" and type(credential) == "table"
            and credential.header_state == "unavailable" and credential.observed_stat == nil
            and type(credential.recovery_stat) == "table"
        if type(credential) ~= "table"
            or credential.physical_path ~= specification.context_path
            or credential.logical_path ~= specification.logical_path
            or (type(credential.observed_stat) ~= "table" and not missing)
            or (credential.header_state ~= "valid"
                and not (allow_corrupt and credential.header_state == "corrupt") and not missing)
        then
            return nil, failure("InvalidContextMutation", "an exact verified Context credential is required")
        end
        local hash, hash_error = path.context_hash(specification.logical_path)
        if not hash then return nil, hash_error end
        local physical = context_root
        for segment in specification.logical_path:gmatch("[^/]+") do
            physical = join_native(physical, segment, admitted.platform_kind)
        end
        if physical ~= specification.context_path then
            return nil, failure("InvalidContextMutation", "Context path is outside its logical mirror binding")
        end
        return physical, hash
    end

    -- Hash a workspace root's logical path and stable physical object identity.
    --@param logical string Logical workspace root.
    --@param identity table Direct directory identity.
    --@return string|nil Domain-separated root identity digest.
    --@return table|nil InvalidWorkspace or digest error.
    local function root_identity_digest(logical, identity)
        if type(identity) ~= "table" or identity.kind ~= "directory"
            or type(identity.volume) ~= "string" or type(identity.object) ~= "string"
        then
            return nil, failure("InvalidWorkspace", "workspace object identity is unavailable")
        end
        return snapshot_digest(safety, "yaca-rebind-root-v1", {
            logical_path = logical, kind = identity.kind,
            volume = identity.volume, object = identity.object,
        })
    end

    -- Reinspect the workspace bound to a pending offline Context proposal.
    --@param plan table Proposal's direct snapshot, root path, and identity digest.
    --@return boolean|nil True when root path and identity remain exact.
    --@return table|nil Changed-workspace or inspection error.
    local function verify_management_workspace(plan)
        local current, current_error = filesystem.direct_reverify(plan.root_snapshot)
        if not current then
            return nil, failure("ContextWorkspaceChanged", "Context workspace changed after inspection",
                current_error and current_error.code)
        end
        local workspace, workspace_error = admitted_ports.workspace.inspect(plan.root_path)
        if not workspace then return nil, workspace_error end
        local digest, digest_error = root_identity_digest(plan.root_logical, workspace.identity)
        if not digest then return nil, digest_error end
        if workspace.path ~= plan.root_path or workspace.enterable ~= true
            or digest ~= plan.new_root_identity
        then
            return nil, failure("ContextWorkspaceChanged", "Context workspace identity changed")
        end
        return true
    end

    ---Builds a read-only rebind proposal. Only this owner's latest proposal can
    -- be consumed, once, by manage_context after the controller confirms it.
    --@param specification table Inspected Context credential and desired workspace root.
    --@return table|nil Opaque, read-only rebind proposal.
    --@return table|nil Validation, workspace, or binding error.
    function service.plan_rebind(specification)
        rebind_plans = {}
        if closed or journal_failure or active then
            return nil, failure("ContextActionUnavailable", "Context management owner is unavailable")
        end
        if type(specification) ~= "table" then
            return nil, failure("InvalidContextMutation", "a bound rebind request is required")
        end
        if type(admitted_ports.workspace) ~= "table"
            or type(admitted_ports.workspace.inspect) ~= "function"
            or type(path.context_file) ~= "function" or type(path.from_logical) ~= "function"
        then
            return nil, failure("ContextActionUnavailable", "workspace inspection is unavailable")
        end
        local physical, hash = bound_management_path(specification)
        if not physical then return nil, hash end
        local workspace, workspace_error = admitted_ports.workspace.inspect(specification.target_root)
        if not workspace then return nil, workspace_error end
        if workspace.enterable ~= true then
            return nil, failure("InvalidWorkspace", "rebind requires an enterable workspace")
        end
        local logical, logical_error = path.to_logical(workspace.path)
        if not logical then return nil, logical_error end
        local root_snapshot, root_error = inspect_directory(filesystem, workspace.path)
        if not root_snapshot then return nil, root_error end
        if not root_snapshot.exists then
            return nil, failure("InvalidWorkspace", "rebind requires an existing workspace")
        end
        local new_identity, identity_error = root_identity_digest(logical, root_snapshot.identity)
        if not new_identity then return nil, identity_error end
        local details, details_error = path.context_file(specification.logical_path)
        if not details then return nil, details_error end
        if logical == details.parent then
            return nil, failure("InvalidLifecycleMove", "Context is already bound to this workspace")
        end
        local old_identity = "unavailable"
        local old_root = path.from_logical(details.parent, admitted.platform_kind)
        if old_root then
            local old_snapshot = inspect_directory(filesystem, old_root)
            if old_snapshot and old_snapshot.exists then
                old_identity = root_identity_digest(details.parent, old_snapshot.identity) or "unavailable"
            end
        end
        local next_logical = (logical == "/" and "" or logical) .. "/" .. details.leaf
        local next_hash, hash_error = path.context_hash(next_logical)
        if not next_hash then return nil, hash_error end
        local credential_digest, credential_error = snapshot_digest(safety,
            "yaca-rebind-selection-v1", specification.expected_credential)
        if not credential_digest then return nil, credential_error end
        local plan = {
            root_snapshot = root_snapshot, root_path = workspace.path, root_logical = logical,
            old_root_identity = old_identity, new_root_identity = new_identity,
            context_path = physical, logical_path = specification.logical_path,
            credential_digest = credential_digest, next_logical = next_logical,
        }
        local valid, valid_error = verify_management_workspace(plan)
        if not valid then return nil, valid_error end
        local proposal = readonly({
            action = "rebind", context_hash = hash, logical_path = specification.logical_path,
            target_root = workspace.path, target_logical_path = next_logical,
            target_hash = next_hash, old_root_identity = old_identity, new_root_identity = new_identity,
        }, "Context rebind proposal")
        rebind_plans[proposal] = plan
        return proposal
    end

    ---Prepares a complete in-place import generation without acquiring a writer.
    -- Local mappings replace only effective selectors. Historical authority and
    -- unfinished operations remain data, and cannot resume work through import.
    --@param specification table Inspected Context, credential, and local config generation.
    --@return table|nil Read-only import proposal with mapping and recovery facts.
    --@return table|nil Workspace, mapping, source, or candidate-generation error.
    function service.plan_import(specification)
        import_plans = {}
        if closed or journal_failure or active then
            return nil, failure("ContextActionUnavailable", "Context management owner is unavailable")
        end
        if type(specification) ~= "table" then
            return nil, failure("InvalidContextMutation", "an exact import request is required")
        end
        if type(store.inspect_import) ~= "function" or type(admitted_ports.workspace) ~= "table"
            or type(admitted_ports.workspace.inspect) ~= "function"
            or type(path.context_file) ~= "function" or type(path.from_logical) ~= "function"
            or type(path.comparison_key) ~= "function" or type(schema.lifecycle_document) ~= "function"
        then
            return nil, failure("ContextActionUnavailable", "in-place import inspection is unavailable")
        end
        local physical, hash = bound_management_path(specification)
        if not physical then return nil, hash end
        local generation, generation_error = validate_generation(specification.generation)
        if not generation then return nil, generation_error end
        local document, report = store.inspect_import(physical, specification.expected_credential)
        if not document then return nil, report end
        local overrides = document_overrides(document)
        overrides.CurrentModel = generation.current_model
        overrides.CurrentPermission = generation.current_permission
        if not generation_matches_context(generation, overrides) then
            return nil, failure("ConfigGenerationMismatch", "import mapping changed other Context overrides")
        end
        local model_snapshot, model_error = selector_snapshot(generation, "CurrentModel", overrides.CurrentModel)
        if not model_snapshot then return nil, model_error end
        local permission_snapshot, permission_error = selector_snapshot(generation,
            "CurrentPermission", overrides.CurrentPermission)
        if not permission_snapshot then return nil, permission_error end
        local details, details_error = path.context_file(specification.logical_path)
        if not details then return nil, details_error end
        local root, root_error = path.from_logical(details.parent, admitted.platform_kind)
        if not root then return nil, root_error end
        local workspace = admitted_ports.workspace.inspect(root)
        if not workspace or workspace.enterable ~= true then
            return nil, failure("WorkspaceMappingRequired", "recorded workspace is unavailable; use rebind first")
        end
        local logical, logical_error = path.to_logical(workspace.path)
        if not logical then return nil, logical_error end
        if path.comparison_key(logical, admitted.platform_kind)
            ~= path.comparison_key(details.parent, admitted.platform_kind)
        then
            return nil, failure("WorkspaceMappingRequired", "recorded workspace resolves to another directory")
        end
        local root_snapshot, snapshot_error = inspect_directory(filesystem, workspace.path)
        if not root_snapshot then return nil, snapshot_error end
        if not root_snapshot.exists then
            return nil, failure("WorkspaceMappingRequired", "recorded workspace is missing")
        end
        local identity, identity_error = root_identity_digest(logical, root_snapshot.identity)
        if not identity then return nil, identity_error end
        local now, time_error = system.utc_now()
        if not utc_parts(now) then return nil, time_error or failure("UtcClockReadFailed", "UTC is unavailable") end
        local updated_at, updated_error = next_utc_time(now, document.header.updated_at)
        if not updated_at then return nil, updated_error end
        -- Render one explicit before-and-after selector mapping for audit facts.
        --@param previous table Prior selector name and snapshot digest.
        --@param name string New local selector name.
        --@param digest string New selector snapshot digest.
        --@return string Human-readable mapping with both digests.
        local function mapping_text(previous, name, digest)
            return previous.name .. " [" .. previous.snapshot_digest .. "] -> " .. name .. " [" .. digest .. "]"
        end
        local manifest = document.model_view.active_manifest
        local mutation = {
            kind = "import", updated_at = updated_at, source_schema = document.schema_version,
            model_name = overrides.CurrentModel, model_snapshot_digest = model_snapshot,
            permission_name = overrides.CurrentPermission, permission_snapshot_digest = permission_snapshot,
            model_mappings = mapping_text(document.session.current_model, overrides.CurrentModel, model_snapshot),
            permission_mappings = mapping_text(document.session.current_permission,
                overrides.CurrentPermission, permission_snapshot),
            decision = "approved-local-mapping", notes = "history approvals remain audit-only; no automatic replay",
            view_manifest_digest = manifest.digest, view_compaction_id = manifest.compaction_id,
            view_context_generation = manifest.compaction_id and document.generation + 1 or nil,
        }
        local hits, scan_error = generation.scan_registered_secrets(
            mutation.model_mappings .. "\n" .. mutation.permission_mappings)
        if not hits then return nil, scan_error end
        if #hits > 0 then return nil, failure("RegisteredSecret", "import mapping contains registered secret material") end
        model_views = {}
        local old_view, view_error = rebuild_active_model_view(document)
        if not old_view then return nil, view_error end
        local candidate, view = management_document(document, mutation)
        model_views = {}
        if not candidate then return nil, view end
        local bytes, encode_error = schema.encode(document)
        if not bytes then return nil, encode_error end
        local document_digest, digest_error = safety.digest(bytes)
        if not document_digest then return nil, digest_error end
        local credential_digest, credential_error = snapshot_digest(safety,
            "yaca-import-selection-v1", specification.expected_credential)
        if not credential_digest then return nil, credential_error end
        local plan = {
            context_path = physical, logical_path = specification.logical_path,
            credential_digest = credential_digest, document_digest = document_digest,
            root_path = workspace.path, root_logical = logical,
            root_snapshot = root_snapshot, new_root_identity = identity,
            generation = generation, mutation = mutation,
        }
        local valid, valid_error = verify_management_workspace(plan)
        if not valid then return nil, valid_error end
        local proposal = readonly({
            action = "import", context_hash = hash, logical_path = specification.logical_path,
            workspace = workspace.path, model = overrides.CurrentModel, permission = overrides.CurrentPermission,
            previous_model = document.session.current_model.name,
            previous_permission = document.session.current_permission.name,
            generation = candidate.generation, history_approvals = "audit-only", auto_replay = false,
            auto_continue = false, unresolved_operations = #document.recovery.unresolved_operation_ids,
            unresolved_tools = #document.recovery.unresolved_tool_call_ids,
            unknown_operations = #document.recovery.unknown_operation_ids,
        }, "Context import proposal")
        import_plans[proposal] = plan
        return proposal
    end

    -- Create a durable repair lifecycle generation from a validated prior document.
    --@param document table Verified surviving Context document.
    --@param action string restore-previous or cleanup action.
    --@param now string Canonical current UTC timestamp.
    --@param previous_updated_at string|nil Latest known prior timestamp.
    --@return table|nil Repaired lifecycle document.
    --@return table|nil View or timestamp error.
    local function repair_document(document, action, now, previous_updated_at)
        local old_view, view_error = rebuild_active_model_view(document)
        if not old_view then return nil, view_error end
        local previous = document.header.updated_at
        if utc_parts(previous_updated_at) and previous_updated_at > previous then previous = previous_updated_at end
        local updated_at, updated_error = next_utc_time(now, previous)
        if not updated_at then return nil, updated_error end
        local manifest = document.model_view.active_manifest
        return management_document(document, {
            kind = "repair", updated_at = updated_at,
            error_id = action == "restore-previous" and "PreviousValidRestored" or "PreviousValidCleaned",
            summary = action == "restore-previous" and "restored the validated previous generation; no operation replay"
                or "removed the verified obsolete previous generation; no operation replay",
            view_manifest_digest = manifest.digest, view_compaction_id = manifest.compaction_id,
            view_context_generation = manifest.compaction_id and document.generation + 1 or nil,
        })
    end

    ---Previews a bounded physical repair without acquiring a writer or moving
    -- files. Missing officials remain unavailable until confirmed publication.
    --@param specification table Exact damaged Context credential and paths.
    --@return table|nil Read-only repair proposal.
    --@return table|nil Inspection, source, or candidate-document error.
    function service.plan_repair(specification)
        repair_plans = {}
        if closed or journal_failure or active then
            return nil, failure("ContextActionUnavailable", "Context management owner is unavailable")
        end
        if type(specification) ~= "table" or type(store.plan_repair) ~= "function"
            or type(store.apply_repair) ~= "function"
        then
            return nil, failure("ContextActionUnavailable", "typed Context repair is unavailable")
        end
        local physical, hash = bound_management_path(specification, "repair")
        if not physical then return nil, hash end
        local proposal, document = store.plan_repair(physical, specification.expected_credential)
        if not proposal then return nil, document end
        if proposal.action ~= "no-repair-needed" then
            local now, time_error = system.utc_now()
            if not utc_parts(now) then return nil, time_error or failure("UtcClockReadFailed", "UTC is unavailable") end
            model_views = {}
            local prepared, prepare_error = repair_document(document, proposal.action, now,
                specification.expected_credential.updated_at)
            model_views = {}
            if not prepared then return nil, prepare_error end
        end
        local digest, digest_error = snapshot_digest(safety, "yaca-repair-selection-v1", specification.expected_credential)
        if not digest then return nil, digest_error end
        local result = readonly({ action = proposal.action, context_hash = hash,
            context_path = physical, logical_path = specification.logical_path,
            source_path = proposal.source_path, previous_path = proposal.previous_path,
            official_exists = proposal.official_exists, generation = proposal.generation,
            auto_replay = false }, "Context repair proposal")
        repair_plans[result] = { store_plan = proposal, document = document,
            physical = physical, logical = specification.logical_path, credential_digest = digest }
        return result
    end

    -- Consume an exact repair proposal and publish its verified replacement.
    --@param specification table Repair plan and matching Context credential.
    --@return table|nil Read-only repair receipt.
    --@return table|nil Stale proposal, repair, or uncertain-publication error.
    --@effect May replace Context files; closes this management owner on uncertain outcome.
    local function apply_context_repair(specification)
        local plan = repair_plans[specification.repair_plan]
        repair_plans = {}
        local physical, hash = bound_management_path(specification, "repair")
        if not physical then return nil, hash end
        local digest = snapshot_digest(safety, "yaca-repair-selection-v1", specification.expected_credential)
        if not plan or plan.physical ~= physical or plan.logical ~= specification.logical_path
            or plan.credential_digest ~= digest or specification.new_name ~= nil or specification.value ~= nil
            or specification.rebind_plan ~= nil or specification.import_plan ~= nil or specification.generation ~= nil
        then
            return nil, failure("InvalidRepairPlan", "an exact current repair proposal is required")
        end
        local document, temporary, metadata
        if plan.store_plan.action ~= "no-repair-needed" then
            local now, time_error = system.utc_now()
            if not utc_parts(now) then return nil, time_error or failure("UtcClockReadFailed", "UTC is unavailable") end
            local pid, pid_error = system.current_process_id()
            if not valid_integer(pid, 1) then return nil, pid_error or failure("ProcessIdentityUnavailable", "PID is unavailable") end
            metadata = { pid = pid, started_at = now }
            local document_error
            document, document_error = repair_document(plan.document, plan.store_plan.action, now,
                specification.expected_credential.updated_at)
            model_views = {}
            if not document then return nil, document_error end
            local random, random_error = system.secure_random(8)
            if type(random) ~= "string" or #random ~= 8 then
                return nil, random_error or failure("SecureRandomUnavailable", "repair temporary identity is unavailable")
            end
            temporary = physical .. ".yaca-tmp-" .. hex(random)
        end
        local called, receipt, repair_error = pcall(store.apply_repair, plan.store_plan, document, temporary, metadata)
        local code = type(repair_error) == "table" and repair_error.code or ""
        if not called or code:find("Unknown", 1, true) or code == "ContextCleanupRequired" then
            closed = true
            return nil, failure("ContextMutationUnknown", "Context repair outcome is uncertain", code)
        end
        if not receipt then return nil, repair_error end
        return readonly({ outcome = receipt.outcome, context_path = physical,
            logical_path = specification.logical_path, context_hash = hash,
            generation = receipt.generation, auto_replay = false }, "managed Context repair receipt")
    end

    ---Performs one offline management transaction against an exact selection.
    -- This uses a separate short-lived writer, never opens a Runtime, and never
    -- recovers or replays pending work. Every path releases its writer before
    -- returning; uncertain publication stops this management owner.
    --@param specification table Exact offline action, credential, and optional proposal.
    --@return table|nil Read-only management transaction receipt.
    --@return table|nil Validation, writer, or uncertain-publication error.
    --@effect May rename, rebind, import, repair, delete, or update Context metadata.
    function service.manage_context(specification)
        if closed or journal_failure then
            return nil, failure("ContextMutationUnknown", "Context management owner is closed")
        end
        if active then
            return nil, failure("ContextAlreadyPublished", "close the active Context before management")
        end
        local allowed = {
            action = true, context_path = true, logical_path = true,
            expected_credential = true, new_name = true, value = true, rebind_plan = true,
            import_plan = true, generation = true,
            repair_plan = true,
        }
        if type(specification) ~= "table" then
            return nil, failure("InvalidContextMutation", "a bound Context action is required")
        end
        for key in pairs(specification) do
            if not allowed[key] then
                return nil, failure("InvalidContextMutation", "Context action contains an unknown field")
            end
        end
        local action = specification.action
        if action == "repair" then return apply_context_repair(specification) end
        if specification.repair_plan ~= nil then
            return nil, failure("InvalidContextMutation", "only repair accepts a repair proposal")
        end
        if action ~= "rename" and action ~= "set_auto_rename_disabled"
            and action ~= "delete" and action ~= "rebind" and action ~= "import"
        then
            return nil, failure("InvalidContextMutation", "Context management action is unavailable")
        end
        local credential = specification.expected_credential
        local physical, context_hash = bound_management_path(specification, action == "delete")
        if not physical then return nil, context_hash end
        local importing
        if action == "import" then
            importing = import_plans[specification.import_plan]
            import_plans = {}
            local digest = snapshot_digest(safety, "yaca-import-selection-v1", credential)
            if not importing or importing.context_path ~= physical
                or importing.logical_path ~= specification.logical_path or importing.credential_digest ~= digest
                or specification.new_name ~= nil or specification.value ~= nil
            then
                return nil, failure("InvalidContextMutation", "an exact current import proposal is required")
            end
            if specification.generation ~= importing.generation then
                return nil, failure("ConfigGenerationChanged", "local configuration changed after import planning")
            end
            local valid, valid_error = verify_management_workspace(importing)
            if not valid then return nil, valid_error end
        elseif specification.import_plan ~= nil or specification.generation ~= nil then
            return nil, failure("InvalidContextMutation", "only import accepts a local mapping proposal")
        end
        local rebind
        if action == "rebind" then
            rebind = rebind_plans[specification.rebind_plan]
            rebind_plans = {}
            local credential_digest = snapshot_digest(safety, "yaca-rebind-selection-v1", credential)
            if not rebind or rebind.context_path ~= physical
                or rebind.logical_path ~= specification.logical_path
                or rebind.credential_digest ~= credential_digest
                or specification.new_name ~= nil or specification.value ~= nil
            then
                return nil, failure("InvalidContextMutation", "an exact current rebind proposal is required")
            end
            local valid, valid_error = verify_management_workspace(rebind)
            if not valid then return nil, valid_error end
        elseif specification.rebind_plan ~= nil then
            return nil, failure("InvalidContextMutation", "only rebind accepts a workspace proposal")
        end
        local destination = physical
        local next_logical = specification.logical_path
        if rebind then
            next_logical = rebind.next_logical
            destination = context_root
            for segment in next_logical:gmatch("[^/]+") do
                destination = join_native(destination, segment, admitted.platform_kind)
            end
        elseif action == "rename" then
            if specification.value ~= nil then
                return nil, failure("InvalidContextMutation", "rename does not accept a metadata value")
            end
            local name, name_error = path.validate_context_name(specification.new_name)
            if not name then return nil, name_error end
            if admitted.platform_kind == "windows" then
                local base = (name:match("^[^.]+") or ""):upper()
                local reserved = {
                    CON = true, PRN = true, AUX = true, NUL = true,
                    ["CLOCK$"] = true, ["CONIN$"] = true, ["CONOUT$"] = true,
                }
                if name:find('[<>:"|?*]') or name:find("[. ]$")
                    or reserved[base] or base:match("^COM[1-9]$") or base:match("^LPT[1-9]$")
                then
                    return nil, failure("InvalidContextName", "Context name is not an ordinary Windows filename")
                end
            end
            destination = join_native(assert(directory_of(physical, admitted.platform_kind)),
                name .. ".xml", admitted.platform_kind)
            next_logical = assert(specification.logical_path:match("^(.*)/[^/]+$"))
                .. "/" .. name .. ".xml"
        elseif specification.new_name ~= nil
            or (action == "delete" and specification.value ~= nil)
            or (action == "set_auto_rename_disabled" and type(specification.value) ~= "boolean")
        then
            return nil, failure("InvalidContextMutation", "Context metadata arguments are invalid")
        end
        local next_hash, next_hash_error = path.context_hash(next_logical)
        if not next_hash then return nil, next_hash_error end
        local required = action == "delete" and { "open_delete_writer", "delete" }
            or ((action == "rename" or rebind) and { "move" } or {})
        for _, method in ipairs(required) do
            if type(store[method]) ~= "function" then
                return nil, failure("ContextActionUnavailable", "Context store omits " .. method)
            end
        end
        if action ~= "delete" and type(schema.lifecycle_document) ~= "function" then
            return nil, failure("ContextActionUnavailable", "Context lifecycle schema is unavailable")
        end
        local now, time_error = system.utc_now()
        if not utc_parts(now) then
            return nil, time_error or failure("UtcClockReadFailed", "UTC clock is unavailable")
        end
        local pid, pid_error = system.current_process_id()
        if not valid_integer(pid, 1) then
            return nil, pid_error or failure("ProcessIdentityUnavailable", "process ID is unavailable")
        end
        local opener = action == "delete" and store.open_delete_writer or store.open_writer
        local writer, document = opener(physical, { pid = pid, started_at = now }, credential)
        if not writer then
            local code = type(document) == "table" and document.code or ""
            if code:find("Unknown", 1, true) or code == "ContextCleanupRequired" then
                closed = true
                return nil, failure("ContextMutationUnknown", "Context writer acquisition is uncertain", code)
            end
            return nil, document
        end
        -- Execute one already-bound offline mutation under the short-lived writer.
        --@param none This closure captures the selected management action and writer.
        --@return table|nil Read-only mutation receipt.
        --@return table|nil Validation, publication, or changed-target error.
        --@effect May delete, move, or publish a Context generation.
        local function transact()
            if action == "delete" then return store.delete(writer) end
            if type(document) ~= "table" or type(document.header) ~= "table"
                or type(document.model_view) ~= "table"
            then
                return nil, failure("ContextMutationUnknown", "Context writer returned no canonical document")
            end
            local candidate, view
            if importing then
                local bytes, encode_error = schema.encode(document)
                if not bytes then return nil, encode_error end
                local digest, digest_error = safety.digest(bytes)
                if not digest then return nil, digest_error end
                if digest ~= importing.document_digest then
                    return nil, failure("ContextTargetChanged", "Context body changed after import planning")
                end
                -- Confirmation can take arbitrarily long. Publish the actual
                -- mutation time, while retaining the already-reviewed mapping.
                local updated_at, updated_error = next_utc_time(now, document.header.updated_at)
                if not updated_at then return nil, updated_error end
                importing.mutation.updated_at = updated_at
                candidate, view = management_document(document, importing.mutation)
                if not candidate then return nil, view end
            else
                local old_view, view_error = rebuild_active_model_view(document)
                if not old_view then return nil, view_error end
                if (action == "rename" and specification.new_name == document.header.name)
                    or (action == "set_auto_rename_disabled"
                        and specification.value == (document.header.auto_rename_disabled == true))
                then
                    return readonly({ outcome = "unchanged", context_path = physical,
                        logical_path = next_logical, context_hash = context_hash,
                        generation = document.generation }, "unchanged Context metadata")
                end
                local updated_at, next_error = next_utc_time(now, document.header.updated_at)
                if not updated_at then return nil, next_error end
                local manifest = document.model_view.active_manifest
                local mutation = {
                    kind = action, updated_at = updated_at, view_manifest_digest = manifest.digest,
                    view_compaction_id = manifest.compaction_id,
                    view_context_generation = manifest.compaction_id and document.generation + 1 or nil,
                }
                if rebind then
                    mutation.old_logical_path = specification.logical_path
                    mutation.new_logical_path = next_logical
                    mutation.old_root_identity = rebind.old_root_identity
                    mutation.new_root_identity = rebind.new_root_identity
                elseif action == "rename" then
                    mutation.new_name = specification.new_name
                    mutation.manual = true
                    mutation.old_logical_path = specification.logical_path
                    mutation.new_logical_path = next_logical
                else
                    mutation.value = specification.value
                    local old_digest, digest_error = override_digest(
                        "AutoRenameDisabled", document.header.auto_rename_disabled == true
                    )
                    if not old_digest then return nil, digest_error end
                    local new_digest
                    new_digest, digest_error = override_digest("AutoRenameDisabled", specification.value)
                    if not new_digest then return nil, digest_error end
                    mutation.old_value_digest = old_digest
                    mutation.new_value_digest = new_digest
                    mutation.effective_at = "next-turn"
                    local main_turns, completed = {}, 0
                    for _, event in ipairs(document.facts) do
                        if event.type == "turn_started" and event.fields.kind == "main" then
                            main_turns[event.turn_id] = true
                        elseif event.type == "turn_ended" and event.fields.outcome == "completed"
                            and main_turns[event.turn_id]
                        then
                            completed = completed + 1
                        end
                    end
                    mutation.naming_waterline = math.max(document.header.naming_waterline or 0, completed)
                end
                candidate, view = management_document(document, mutation)
                if not candidate then return nil, view end
            end
            local random, random_error = system.secure_random(8)
            if type(random) ~= "string" or #random ~= 8 then
                return nil, random_error or failure("SecureRandomUnavailable", "temporary identity is unavailable")
            end
            local temporary_path = destination .. ".yaca-tmp-" .. hex(random)
            local published, publish_error
            if importing then
                local valid, valid_error = verify_management_workspace(importing)
                if not valid then return nil, valid_error end
            end
            if rebind then
                local valid, valid_error = verify_management_workspace(rebind)
                if not valid then return nil, valid_error end
                local mirror, mirror_error, mirror_snapshot = prepare_mirror(rebind.root_path)
                if not mirror then return nil, mirror_error end
                local current, current_error = filesystem.direct_reverify(mirror_snapshot)
                if not current then return nil, current_error end
                valid, valid_error = verify_management_workspace(rebind)
                if not valid then return nil, valid_error end
            end
            if action == "rename" or rebind then
                published, publish_error = store.move(writer, candidate, destination, temporary_path, action)
            else
                published, publish_error = store.publish(writer, candidate, temporary_path)
            end
            if not published then return nil, publish_error end
            if rebind or importing then
                local valid, valid_error = verify_management_workspace(rebind or importing)
                if not valid then
                    return nil, failure("ContextMutationUnknown", "workspace changed during Context publication",
                        valid_error and valid_error.code)
                end
            end
            return readonly({
                outcome = "success", durable = true, context_path = destination,
                logical_path = next_logical, context_hash = next_hash,
                previous_context_hash = context_hash, display_name = candidate.header.name,
                generation = candidate.generation, event_count = candidate.event_count,
                auto_rename_disabled = candidate.header.auto_rename_disabled == true,
                view_manifest_snapshot = view.digest,
                model = importing and candidate.session.current_model.name or nil,
                permission = importing and candidate.session.current_permission.name or nil,
                auto_replay = false,
            }, "managed Context receipt")
        end
        local called, receipt, mutation_error = pcall(transact)
        local close_called, released, release_error = pcall(store.close_writer, writer)
        model_views = {}
        if not close_called or not released then
            closed = true
            return nil, failure("ContextMutationUnknown", "Context writer release is unknown",
                type(release_error) == "table" and release_error.code or "release-failed")
        end
        if not called then
            closed = true
            return nil, failure("ContextMutationUnknown", "Context transaction raised an exception")
        end
        if not receipt then
            local code = type(mutation_error) == "table" and mutation_error.code or ""
            if code:find("Unknown", 1, true) or code == "ContextCleanupRequired" then
                closed = true
                return nil, failure("ContextMutationUnknown", "Context transaction outcome is unknown", code)
            end
            return nil, mutation_error or failure("ContextMutationFailed", "Context transaction failed")
        end
        if action == "delete" and receipt.outcome ~= "deleted" then closed = true end
        return receipt
    end

    -- Publish the first durable Context generation under a collision-safe random name.
    --@param specification table Generation, workspace, settings, initial message, and lane.
    --@return table|nil Read-only first-publication receipt with Agent binding digests.
    --@return table|nil Input, name, filesystem, or publication error.
    --@effect Creates a Context file and retains its writer as the active owner.
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
            or (specification.initial_lane ~= nil and specification.initial_lane ~= "main"
                and specification.initial_lane ~= "ask")
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
            -- An initial Ask publishes only the Context owner here. The Ask
            -- lane then records its own turn and request atomically; no main
            -- turn or main Model activity is manufactured for initialization.
            local first_ask = specification.initial_lane == "ask"
            if first_ask then facts = {} end
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
                        first_event_seq = first_ask and 0 or 1,
                        last_event_seq = #facts,
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
                        first_sequence = first_ask and 0 or 1,
                        last_sequence = #facts,
                        turn_id = not first_ask and "turn-1" or false,
                        message_id = not first_ask and "turn-1:message:1" or false,
                        runtime_initial_serials = document.recovery.runtime_initial_serials,
                        config_snapshot = snapshot.config,
                        model_snapshot = snapshot.model,
                        permission_snapshot = snapshot.permission,
                        prompt_snapshot = snapshot.prompt,
                        tool_registry_snapshot = snapshot.tool_registry,
                        view_manifest_snapshot = snapshot.view,
                        model_request_limit = snapshot.model_request_limit,
                        tool_call_limit = snapshot.tool_call_limit,
                        queue_limit = snapshot.queue_limit,
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

    -- Reconstruct pending compaction lifecycle state from verified recovery facts.
    --@param document table Reopened durable Context document.
    --@return boolean|nil True after valid lifecycles are restored.
    --@return table|nil Invalid recovery or compaction-binding error.
    local function restore_compaction_lifecycles(document)
        compaction_lifecycles = {}
        local recovery = document.recovery or {}
        for _, recovered in ipairs(recovery.pending_compactions or {}) do
            if type(recovered) ~= "table"
                or not valid_text(
                    recovered.compaction_id,
                    admitted.maximum_compaction_identifier_bytes
                )
                or not valid_text(
                    recovered.request_id,
                    admitted.maximum_compaction_identifier_bytes
                )
                or (recovered.mode ~= "manual" and recovered.mode ~= "automatic")
                or not valid_integer(recovered.attempt, 1)
                or not valid_integer(recovered.source_first_seq, 1)
                or not valid_integer(
                    recovered.source_last_seq,
                    recovered.source_first_seq
                )
                or not valid_integer(
                    recovered.source_event_count,
                    recovered.source_last_seq
                )
                or not valid_digest(recovered.source_digest)
                or not valid_digest(recovered.config_snapshot)
                or not valid_digest(recovered.model_snapshot)
                or not valid_digest(recovered.prompt_snapshot)
                or not valid_text(
                    recovered.manifest_snapshot,
                    admitted.maximum_compaction_identifier_bytes
                )
                or not valid_digest(recovered.manifest_digest)
                or (recovered.response_status ~= false
                    and recovered.response_status ~= "complete"
                    and recovered.response_status ~= "interrupted")
                or type(recovered.cancel_requested) ~= "boolean"
                or (recovered.cancel_requested
                    and not valid_text(
                        recovered.cancel_reason,
                        admitted.maximum_model_view_bytes
                    ))
                or recovered.manifest_digest
                    ~= document.model_view.active_manifest.digest
                or compaction_lifecycles[recovered.compaction_id]
            then
                return nil, failure(
                    "CompactionRecoveryUnknown",
                    "durable pending compaction recovery data is invalid"
                )
            end
            compaction_lifecycles[recovered.compaction_id] = {
                compaction_id = recovered.compaction_id,
                mode = recovered.mode,
                request_id = recovered.request_id,
                attempt = recovered.attempt,
                source_first_seq = recovered.source_first_seq,
                source_last_seq = recovered.source_last_seq,
                source_digest = recovered.source_digest,
                source_event_count = recovered.source_event_count,
                manifest_digest = recovered.manifest_digest,
                config_snapshot = recovered.config_snapshot,
                model_snapshot_digest = recovered.model_snapshot,
                prompt_bundle_digest = recovered.prompt_snapshot,
                manifest_snapshot_id = recovered.manifest_snapshot,
                response_committed = recovered.response_status == "complete",
                cancel_requested = recovered.cancel_requested,
                cancel_reason = recovered.cancel_requested
                    and recovered.cancel_reason or nil,
                terminal = false,
            }
        end
        return true
    end

    -- Settle every crash-left compaction request as unknown before exposing a Runtime.
    --@param none This closure uses the active durable Context and its journal.
    --@return table|nil Read-only recovery counts and retained-view status.
    --@return table|nil Journal or incomplete-recovery error.
    --@effect Publishes cancellation facts for bound and legacy pending compactions.
    local function recover_opened_compactions()
        local recovery = active.document.recovery or {}
        local pending = recovery.pending_compactions or {}
        local legacy = recovery.legacy_pending_compaction_request_ids or {}
        local recovered_bound = 0
        local recovered_legacy = 0
        if #pending > 0 then
            local journal = service.compaction_journal()
            for _, recovered in ipairs(pending) do
                local lifecycle = compaction_lifecycles[recovered.compaction_id]
                local reason = lifecycle.cancel_requested
                    and lifecycle.cancel_reason or "compaction-process-recovery"
                if not lifecycle.cancel_requested then
                    local committed, receipt = journal.commit_rejection({
                        kind = "compaction-cancel-request",
                        compaction_id = lifecycle.compaction_id,
                        request_id = lifecycle.request_id,
                        reason = reason,
                        source_first_seq = lifecycle.source_first_seq,
                        source_last_seq = lifecycle.source_last_seq,
                        source_digest = lifecycle.source_digest,
                        canonical_facts_before = lifecycle.source_event_count,
                        expected_context_generation = active.document.generation,
                        expected_manifest_digest = lifecycle.manifest_digest,
                        old_view_retained = true,
                    })
                    if committed ~= true then return nil, receipt end
                end
                local committed, receipt = journal.commit_rejection({
                    kind = "compaction-cancel-result",
                    compaction_id = lifecycle.compaction_id,
                    request_id = lifecycle.request_id,
                    reason = reason,
                    outcome = "unknown",
                    source_first_seq = lifecycle.source_first_seq,
                    source_last_seq = lifecycle.source_last_seq,
                    source_digest = lifecycle.source_digest,
                    canonical_facts_before = lifecycle.source_event_count,
                    config_snapshot = lifecycle.config_snapshot,
                    model_snapshot_digest = lifecycle.model_snapshot_digest,
                    prompt_bundle_digest = lifecycle.prompt_bundle_digest,
                    expected_context_generation = active.document.generation,
                    expected_manifest_digest = lifecycle.manifest_digest,
                    old_view_retained = true,
                })
                if committed ~= true then return nil, receipt end
                recovered_bound = recovered_bound + 1
            end
        end
        if #legacy > 0 then
            local legacy_states = {}
            for _, request_id in ipairs(legacy) do
                legacy_states[request_id] = { cancel_requested = false }
            end
            for _, event in ipairs(active.document.facts) do
                local fields = event.fields
                local state = event.type == "cancel"
                    and fields.targetKind == "compaction-request"
                    and legacy_states[fields.targetId]
                    or nil
                if state and fields.result == "pending" then
                    state.cancel_requested = true
                    state.reason = fields.reason
                end
            end
            for _, request_id in ipairs(legacy) do
                local state = legacy_states[request_id]
                local reason = state.cancel_requested and state.reason
                    or "compaction-process-recovery"
                local events = {}
                if not state.cancel_requested then
                    events[#events + 1] = {
                        type = "cancel",
                        fields = {
                            targetKind = "compaction-request",
                            targetId = request_id,
                            reason = reason,
                            result = "pending",
                        },
                    }
                end
                events[#events + 1] = {
                    type = "cancel",
                    fields = {
                        targetKind = "compaction-request",
                        targetId = request_id,
                        reason = reason,
                        result = "unknown",
                    },
                }
                local first_sequence = active.document.event_count + 1
                for index, event in ipairs(events) do
                    event.seq = first_sequence + index - 1
                end
                local digest_called, digest, digest_error = pcall(
                    safety.binding_digest,
                    "yaca-legacy-compaction-recovery-v1",
                    {
                        { name = "request", value = request_id },
                        { name = "generation", value = tostring(
                            active.document.generation
                        ) },
                        { name = "sequence", value = tostring(first_sequence) },
                    }
                )
                if not digest_called or not valid_digest(digest) then
                    return nil, (digest_called and digest_error) or failure(
                        "CompactionRecoveryUnknown",
                        "legacy compaction recovery barrier is unavailable"
                    )
                end
                local committed, receipt = service.commit({
                    barrier_id = "legacy-compaction-recovery:" .. digest,
                    first_sequence = first_sequence,
                    last_sequence = first_sequence + #events - 1,
                    event_count = #events,
                    expected_context_generation = active.document.generation,
                    events = events,
                })
                if committed ~= true then return nil, receipt end
                recovered_legacy = recovered_legacy + 1
            end
        end
        local remaining = active.document.recovery or {}
        if #(remaining.pending_compactions or {}) > 0
            or #(remaining.legacy_pending_compaction_request_ids or {}) > 0
        then
            return nil, failure(
                "CompactionRecoveryUnknown",
                "pending compaction recovery did not reach a terminal state"
            )
        end
        return readonly({
            outcome = recovered_bound + recovered_legacy > 0
                and "recovered-unknown" or "clean",
            recovered_bound = recovered_bound,
            recovered_legacy = recovered_legacy,
            old_view_retained = true,
            automatic_failure_count =
                remaining.automatic_compaction_failure_count or 0,
            automatic_failure_history_complete =
                remaining.automatic_compaction_failure_history_complete ~= false,
        }, "opened Context compaction recovery")
    end

    ---Acquires a verified existing Context and resolves every crash-left
    -- compaction bracket before exposing the writer to a new Runtime.
    --@param specification table Exact physical/logical paths and inspection credential.
    --@return table|nil Opened or recovered Context receipt.
    --@return table|nil Validation, lease, view, or recovery error.
    --@effect Acquires and retains the Context writer; may publish recovery facts.
    function service.open_existing(specification)
        if closed then
            return nil, failure(
                "ContextPublicationClosed",
                "existing Context publication service is closed"
            )
        end
        if active then
            return nil, failure(
                "ContextAlreadyPublished",
                "this process already owns a Context"
            )
        end
        local allowed = {
            context_path = true,
            logical_path = true,
            expected_credential = true,
        }
        if type(specification) ~= "table" then
            return nil, failure(
                "InvalidContextOpen",
                "existing Context open input is required"
            )
        end
        for key in pairs(specification) do
            if type(key) ~= "string" or not allowed[key] then
                return nil, failure(
                    "InvalidContextOpen",
                    "existing Context open input is ambiguous"
                )
            end
        end
        local credential = specification.expected_credential
        if not valid_absolute_path(specification.context_path)
            or type(specification.logical_path) ~= "string"
            or type(credential) ~= "table"
            or credential.physical_path ~= specification.context_path
            or credential.logical_path ~= specification.logical_path
        then
            return nil, failure(
                "InvalidContextOpen",
                "existing Context requires an exact verified target"
            )
        end
        local context_hash, hash_error = path.context_hash(
            specification.logical_path
        )
        if not context_hash then return nil, hash_error end
        local now, time_error = system.utc_now()
        if type(now) ~= "string" or now == "" then
            return nil, time_error or failure(
                "UtcClockReadFailed",
                "UTC clock is unavailable"
            )
        end
        local pid, pid_error = system.current_process_id()
        if not valid_integer(pid, 1) then
            return nil, pid_error or failure(
                "ProcessIdentityUnavailable",
                "process ID is unavailable"
            )
        end
        local writer, document_or_error = store.open_writer(
            specification.context_path,
            { pid = pid, started_at = now },
            credential
        )
        if not writer then return nil, document_or_error end
        local document = document_or_error
        if type(document) ~= "table"
            or type(document.header) ~= "table"
            or type(document.model_view) ~= "table"
            or type(document.recovery) ~= "table"
        then
            return close_writer(writer, failure(
                "ContextOpenUnknown",
                "existing Context store returned no canonical document"
            ))
        end
        local view, view_error = rebuild_active_model_view(document)
        if not view then return close_writer(writer, view_error) end
        local restored, restore_error = restore_compaction_lifecycles(document)
        if not restored then return close_writer(writer, restore_error) end
        local receipt = readonly({
            outcome = "opened",
            durable = true,
            context_path = specification.context_path,
            logical_path = specification.logical_path,
            context_hash = context_hash,
            display_name = document.header.name,
            generation = document.generation,
            event_count = document.event_count,
            first_sequence = 1,
            last_sequence = document.event_count,
            view_manifest_snapshot = document.model_view.active_manifest.digest,
        }, "existing Context publication receipt")
        active = { writer = writer, document = document, receipt = receipt }
        local recovery, recovery_error = recover_opened_compactions()
        if not recovery then
            local released, release_error = store.close_writer(writer)
            active = nil
            compaction_journal = nil
            compaction_lifecycles = {}
            if not released then
                return nil, failure(
                    "ContextLeaseUnknown",
                    "failed compaction recovery writer release is unknown",
                    release_error and release_error.code
                )
            end
            return nil, recovery_error
        end
        local values = {}
        for key, value in pairs(active.receipt) do values[key] = value end
        local durable_recovery = active.document.recovery
        values.outcome = recovery.outcome == "clean" and "opened" or "recovered"
        values.compaction_recovery = recovery
        values.generation = active.document.generation
        values.event_count = active.document.event_count
        values.first_sequence = active.document.event_count == 0 and 0 or 1
        values.last_sequence = active.document.event_count
        values.view_manifest_snapshot = active.document.model_view.active_manifest.digest
        values.auto_continue = durable_recovery.auto_continue
        values.unresolved_operation_ids = durable_recovery.unresolved_operation_ids
        values.unresolved_tool_call_ids = durable_recovery.unresolved_tool_call_ids
        values.unknown_operation_ids = durable_recovery.unknown_operation_ids
        values.unfinished_turn_ids = durable_recovery.unfinished_turn_ids
        values.active_queue_item_ids = durable_recovery.active_queue_item_ids
        values.runtime_initial_serials = durable_recovery.runtime_initial_serials
        values.approval_initial_serial = durable_recovery.approval_initial_serial
        active.receipt = readonly(values, "existing Context publication receipt")
        return active.receipt
    end

    ---Builds a bounded quoted-data model view from the exact current durable
    -- Fact prefix. A changed view is only a candidate until AgentLoop commits
    -- the matching model_view_published event through this journal.
    --@param specification table Expected Context generation, event count, and manifest digest.
    --@return table|nil Read-only view candidate or unchanged active-view reference.
    --@return table|nil Stale observation, rebuild, or size error.
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
                local rebuild_error
                view, rebuild_error = rebuild_active_model_view(document)
                if not view then return nil, rebuild_error end
            end
            if not view then
                return nil, failure(
                    "ModelViewUnavailable",
                    "active model view body is not available to this writer"
                )
            end
        else
            local view_error
            if manifest.compaction_id then
                local projection
                projection, view_error = durable_compaction_projection(document, manifest)
                if not projection then return nil, view_error end
                projection.fact_limit = document.event_count
                projection.waterline = document.event_count
                view, view_error = cache_model_view(
                    document.facts,
                    document.generation,
                    projection
                )
            else
                view, view_error = cache_model_view(document.facts, document.generation)
            end
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
            compaction_id = view.compaction_id,
            view_context_generation = view.context_generation,
            binding = specification,
        }, "prepared durable model view")
    end

    ---Returns one body only after its manifest is the active durable view.
    --@param digest string Exact active Model view manifest digest.
    --@return table|nil Read-only active Model view with its quoted-data body.
    --@return table|nil Stale, unavailable, or rebuild error.
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
            local rebuild_error
            view, rebuild_error = rebuild_active_model_view(active.document)
            if not view then return nil, rebuild_error end
        end
        if not view then
            return nil, failure("ModelViewUnavailable", "durable model view body is unavailable")
        end
        return view
    end

    ---Returns the exact durable session overrides used for the next complete
    -- Config reload. The private config source digest never enters this view.
    --@param observation table Expected current Context generation.
    --@return table|nil Read-only Context generation and override snapshot.
    --@return table|nil Closed, unpublished, invalid, or stale-observation error.
    function service.turn_context(observation)
        if closed then
            return nil, failure("ContextPublicationClosed", "Context turn snapshot is closed")
        end
        if journal_failure then return nil, journal_failure end
        if not active or not active.document then
            return nil, failure("ContextNotPublished", "Context turn snapshot has no durable source")
        end
        if type(observation) ~= "table" then
            return nil, failure("InvalidTurnSnapshot", "Context turn observation is invalid")
        end
        for key in pairs(observation) do
            if key ~= "expected_context_generation" then
                return nil, failure("InvalidTurnSnapshot", "Context turn observation is ambiguous")
            end
        end
        if not valid_integer(observation.expected_context_generation, 1) then
            return nil, failure("InvalidTurnSnapshot", "Context turn observation is invalid")
        end
        if observation.expected_context_generation ~= active.document.generation then
            return nil, failure("StaleContextObservation", "Context turn observation is stale")
        end
        return readonly({
            context_generation = active.document.generation,
            overrides = readonly(durable_context_overrides(), "durable Context overrides"),
        }, "durable Context turn state")
    end

    ---Atomically publishes one whitelisted Context Session override plus the
    -- refreshed active Model view. The returned receipt must be adopted by the
    -- sole Runtime before any later barrier is allowed to advance.
    --@param specification table Exact override change and expected Context/config state.
    --@return table|nil Durable Session update receipt for Runtime adoption.
    --@return table|nil Validation, stale generation, or publication error.
    --@effect Publishes a new Context generation with the override and Model view.
    function service.update_session(specification)
        if closed then
            return nil, failure(
                "ContextPublicationClosed",
                "Context session update is closed"
            )
        end
        if journal_failure then return nil, journal_failure end
        if not active or not active.writer or not active.document then
            return nil, failure(
                "ContextNotPublished",
                "Context session update has no durable owner"
            )
        end
        local allowed = {
            expected_context_generation = true,
            expected_last_sequence = true,
            expected_manifest_digest = true,
            generation = true,
            name = true,
            value = true,
            mode = true,
        }
        if type(specification) ~= "table" then
            return nil, failure(
                "InvalidSessionUpdate",
                "Context session update specification is required"
            )
        end
        for key in pairs(specification) do
            if type(key) ~= "string" or not allowed[key] then
                return nil, failure(
                    "InvalidSessionUpdate",
                    "Context session update specification is ambiguous"
                )
            end
        end
        local names = {
            CurrentModel = true,
            CurrentPermission = true,
            DoubleCheckOverride = true,
            DoubleCheckGoalOverride = true,
            ContextPrompt = true,
        }
        local generation, generation_error = validate_generation(
            specification.generation
        )
        local document = active.document
        local manifest = document.model_view.active_manifest
        if not generation then return nil, generation_error end
        if not names[specification.name]
            or specification.expected_context_generation ~= document.generation
            or specification.expected_last_sequence ~= document.event_count
            or specification.expected_manifest_digest ~= manifest.digest
        then
            return nil, failure(
                "StaleSessionUpdate",
                "Context session update does not bind the active generation"
            )
        end

        local name = specification.name
        local next_overrides = copy_overrides(durable_context_overrides())
        local schema_value = specification.value
        local schema_mode = specification.mode
        if name == "CurrentModel" or name == "CurrentPermission" then
            if type(schema_value) ~= "string" or schema_value == ""
                or schema_mode ~= nil
            then
                return nil, failure(
                    "InvalidSessionUpdate",
                    "Context selector update is invalid"
                )
            end
            next_overrides[name] = schema_value
        elseif name == "DoubleCheckOverride" then
            if schema_mode ~= nil
                or (schema_value ~= "inherit" and type(schema_value) ~= "boolean")
            then
                return nil, failure(
                    "InvalidSessionUpdate",
                    "DoubleCheck Context update is invalid"
                )
            end
            next_overrides.DoubleCheckOverride = schema_value
        elseif name == "DoubleCheckGoalOverride" then
            if (schema_mode ~= "inherit" and schema_mode ~= "value")
                or (schema_mode == "inherit" and schema_value ~= nil)
                or (schema_mode == "value"
                    and not valid_text(schema_value, admitted.maximum_model_view_bytes))
            then
                return nil, failure(
                    "InvalidSessionUpdate",
                    "DoubleCheck goal Context update is invalid"
                )
            end
            next_overrides.DoubleCheckGoalOverride = schema_mode == "inherit"
                and "inherit" or schema_value
        else
            if schema_mode ~= nil
                or not valid_text(schema_value, admitted.maximum_model_view_bytes)
            then
                return nil, failure(
                    "InvalidSessionUpdate",
                    "ContextPrompt update is invalid"
                )
            end
            next_overrides.ContextPrompt = schema_value
        end
        if not generation_matches_context(generation, next_overrides) then
            return nil, failure(
                "ConfigGenerationMismatch",
                "Context session update generation does not match its overrides"
            )
        end
        if name == "ContextPrompt"
            or (name == "DoubleCheckGoalOverride" and schema_mode == "value")
        then
            local hits, scan_error = generation.scan_registered_secrets(schema_value)
            if not hits then return nil, scan_error end
            if #hits > 0 then
                return nil, failure(
                    "RegisteredSecret",
                    "Context session update matches a registered configuration secret"
                )
            end
        end

        local old_value = override_value(document, name)
        local snapshot
        local new_value = schema_value
        if name == "CurrentModel" or name == "CurrentPermission" then
            snapshot, generation_error = selector_snapshot(generation, name, schema_value)
            if not snapshot then return nil, generation_error end
            new_value = { name = schema_value, snapshot_digest = snapshot }
        elseif name == "DoubleCheckGoalOverride" then
            new_value = schema_mode == "value"
                and { mode = "value", value = schema_value }
                or { mode = "inherit" }
        end
        local old_bytes, old_bytes_error = canonical_public(old_value)
        if not old_bytes then return nil, old_bytes_error end
        local new_bytes, new_bytes_error = canonical_public(new_value)
        if not new_bytes then return nil, new_bytes_error end
        if old_bytes == new_bytes then
            return nil, failure(
                "SessionOverrideUnchanged",
                "Context session override already has the requested value"
            )
        end
        local old_digest, digest_error = override_digest(name, old_value)
        if not old_digest then return nil, digest_error end
        local new_digest
        new_digest, digest_error = override_digest(name, new_value)
        if not new_digest then return nil, digest_error end

        local observed, time_error = system.utc_now()
        if not observed then return nil, time_error end
        local updated_at, next_error = next_utc_time(
            observed,
            document.header.updated_at
        )
        if not updated_at then return nil, next_error end
        local session_event = {
            seq = document.event_count + 1,
            type = "session_override",
            at = updated_at,
            fields = {
                name = name,
                oldValueDigest = old_digest,
                newValueDigest = new_digest,
                effectiveAt = "next-turn",
            },
        }
        local view_facts = {}
        for index, event in ipairs(document.facts) do view_facts[index] = event end
        view_facts[#view_facts + 1] = session_event
        local projection
        if manifest.compaction_id then
            projection, generation_error = durable_compaction_projection(
                document,
                manifest
            )
            if not projection then return nil, generation_error end
            projection.fact_limit = #view_facts
            projection.waterline = #view_facts
        end
        local view, view_error = cache_model_view(
            view_facts,
            document.generation + 1,
            projection
        )
        if not view then return nil, view_error end
        local mutation = {
            updated_at = updated_at,
            name = name,
            value = schema_value,
            mode = schema_mode,
            snapshot_digest = snapshot,
            old_value_digest = old_digest,
            new_value_digest = new_digest,
            effective_at = "next-turn",
            view_manifest_digest = view.digest,
        }
        if view.compaction_id then
            mutation.view_compaction_id = view.compaction_id
            mutation.view_context_generation = view.context_generation
        end
        local next_document, document_error = schema.session_document(
            document,
            mutation
        )
        if not next_document then
            model_views[view.digest] = nil
            return nil, document_error
        end
        if next_document.model_view.active_manifest.digest ~= view.digest
            or next_document.model_view.active_manifest.first_event_seq
                ~= view.first_sequence
            or next_document.model_view.active_manifest.last_event_seq
                ~= view.last_sequence
            or next_document.event_count ~= document.event_count + 2
        then
            model_views[view.digest] = nil
            return nil, failure(
                "InvalidSessionUpdate",
                "Context session update view publication is inexact"
            )
        end

        local published, publish_error
        for _ = 1, admitted.maximum_create_attempts do
            local random, random_error = system.secure_random(8)
            if type(random) ~= "string" or #random ~= 8 then
                model_views[view.digest] = nil
                return nil, random_error or failure(
                    "SecureRandomUnavailable",
                    "Context session update requires a temporary identity"
                )
            end
            published, publish_error = store.publish(
                active.writer,
                next_document,
                active.receipt.context_path .. ".yaca-tmp-" .. hex(random)
            )
            if published then break end
            if publish_error and publish_error.code == "ContextCapacity"
                and publish_error.publication_started == false
            then
                model_views[view.digest] = nil
                return nil, publish_error
            end
            if type(publish_error) ~= "table"
                or publish_error.code ~= "DestinationExists"
            then
                journal_failure = failure(
                    "ContextPublicationUnknown",
                    "Context session update returned no durable outcome",
                    type(publish_error) == "table" and publish_error.code
                        or "publish-failure"
                )
                model_views[view.digest] = nil
                return nil, journal_failure
            end
        end
        if not published then
            model_views[view.digest] = nil
            return nil, failure(
                "ContextTemporaryNameExhausted",
                "Context session temporary names exhausted the retry limit"
            )
        end
        if type(published) ~= "table"
            or published.generation ~= document.generation + 1
            or published.event_count ~= document.event_count + 2
        then
            journal_failure = failure(
                "ContextPublicationUnknown",
                "Context session update returned an inexact durable receipt"
            )
            model_views[view.digest] = nil
            return nil, journal_failure
        end

        local first_sequence = document.event_count + 1
        local session_fact = next_document.facts[first_sequence]
        local view_fact = next_document.facts[first_sequence + 1]
        local events = readonly({
            readonly({
                seq = session_fact.seq,
                type = session_fact.type,
                turn_id = false,
                fields = session_fact.fields,
            }, "session override receipt event"),
            readonly({
                seq = view_fact.seq,
                type = view_fact.type,
                turn_id = false,
                fields = view_fact.fields,
            }, "session view receipt event"),
        }, "session override receipt events")
        local barrier_id = "session-override:" .. tostring(document.generation)
            .. ":" .. tostring(first_sequence)
        local batch = readonly({
            barrier_id = barrier_id,
            first_sequence = first_sequence,
            last_sequence = first_sequence + 1,
            event_count = 2,
            expected_context_generation = document.generation,
            events = events,
        }, "session override receipt binding")
        local record = readonly({
            kind = "session-override",
            name = name,
            old_value_digest = old_digest,
            new_value_digest = new_digest,
            effective_at = "next-turn",
            replaces_manifest_digest = manifest.digest,
            manifest_digest = view.digest,
            compaction_id = view.compaction_id or false,
            view_context_generation = view.context_generation,
        }, "durable session override record")
        local receipt = readonly({
            barrier_id = barrier_id,
            first_sequence = first_sequence,
            last_sequence = first_sequence + 1,
            event_count = 2,
            binding = batch,
            previous_context_generation = document.generation,
            context_generation = next_document.generation,
        }, "Context session update receipt")

        active.document = next_document
        local status_values = {}
        for key, value in pairs(active.receipt) do status_values[key] = value end
        status_values.generation = next_document.generation
        status_values.event_count = next_document.event_count
        status_values.last_sequence = next_document.event_count
        status_values.view_manifest_snapshot = view.digest
        active.receipt = readonly(status_values, "Context publication receipt")
        return record, receipt
    end

    ---Builds a complete immutable Runtime turn input from one already reloaded
    -- ConfigGeneration and the current durable Model-view manifest.
    --@param specification table Generation, main/ask text, source, and expected Context generation.
    --@return table|nil Read-only Runtime turn snapshot with binding digests and limits.
    --@return table|nil Invalid, stale, or mismatched generation error.
    function service.capture_turn(specification)
        if closed then
            return nil, failure("ContextPublicationClosed", "Context turn snapshot is closed")
        end
        if journal_failure then return nil, journal_failure end
        if not active or not active.document then
            return nil, failure("ContextNotPublished", "Context turn snapshot has no durable source")
        end
        if type(specification) ~= "table" then
            return nil, failure("InvalidTurnSnapshot", "turn snapshot input is required")
        end
        local allowed = {
            generation = true,
            kind = true,
            text = true,
            source = true,
            expected_context_generation = true,
        }
        for key in pairs(specification) do
            if type(key) ~= "string" or not allowed[key] then
                return nil, failure("InvalidTurnSnapshot", "turn snapshot input is ambiguous")
            end
        end
        if type(specification.generation) ~= "table"
            or (specification.kind ~= nil
                and specification.kind ~= "main"
                and specification.kind ~= "ask")
            or not valid_text(specification.text, admitted.maximum_model_view_bytes)
            or specification.text == ""
            or not valid_text(specification.source, 256)
            or specification.source == ""
            or not valid_integer(specification.expected_context_generation, 1)
            or specification.expected_context_generation ~= active.document.generation
        then
            return nil, failure("InvalidTurnSnapshot", "turn snapshot input is invalid or stale")
        end
        local overrides = durable_context_overrides()
        local generation = specification.generation
        if not generation_matches_context(generation, overrides) then
            return nil, failure(
                "ConfigGenerationMismatch",
                "reloaded configuration does not bind the durable Context overrides"
            )
        end
        local settings = {
            model = generation.current_model,
            permission = generation.current_permission,
            double_check = generation.effective_double_check,
            double_check_goal = generation.effective_double_check_goal or "",
            context_prompt = generation.context_prompt or "",
            auto_rename_disabled = generation.auto_rename_disabled == true,
        }
        local snapshot, snapshot_error = snapshots({
            generation = generation,
            settings = settings,
            message = specification.text,
            kind = specification.kind or "main",
        })
        if not snapshot then return nil, snapshot_error end
        return readonly({
            text = specification.text,
            source = specification.source,
            config_generation = snapshot.config,
            model_snapshot = snapshot.model,
            permission_snapshot = snapshot.permission,
            prompt_snapshot = snapshot.prompt,
            tool_registry_snapshot = snapshot.tool_registry,
            view_manifest_ref = active.document.model_view.active_manifest.digest,
            double_check = settings.double_check,
            context_generation = active.document.generation,
            model_request_limit = snapshot.model_request_limit,
            tool_call_limit = snapshot.tool_call_limit,
            queue_limit = snapshot.queue_limit,
        }, "durable Runtime turn snapshot")
    end

    ---Returns the exact immutable Context and active Model-view facts needed
    -- to plan compaction. The caller supplies the complete Runtime waterline;
    -- a stale generation, sequence, or manifest fails before XML encoding.
    --@param observation table Expected Context generation, sequence, and active manifest digest.
    --@return table|nil Read-only compaction source, corrections, ranges, and recovery state.
    --@return table|nil Stale, oversized, encoding, or digest error.
    function service.compaction_snapshot(observation)
        if closed then
            return nil, failure(
                "ContextPublicationClosed",
                "Context compaction snapshot is closed"
            )
        end
        if journal_failure then return nil, journal_failure end
        if not active or not active.document then
            return nil, failure(
                "ContextNotPublished",
                "Context compaction snapshot has no durable source"
            )
        end
        local allowed = {
            expected_context_generation = true,
            expected_last_sequence = true,
            expected_manifest_digest = true,
        }
        if type(observation) ~= "table" then
            return nil, failure(
                "InvalidCompactionSnapshot",
                "Context compaction observation is required"
            )
        end
        for key in pairs(observation) do
            if type(key) ~= "string" or not allowed[key] then
                return nil, failure(
                    "InvalidCompactionSnapshot",
                    "Context compaction observation is ambiguous"
                )
            end
        end
        local document = active.document
        local manifest = document.model_view.active_manifest
        if observation.expected_context_generation ~= document.generation
            or observation.expected_last_sequence ~= document.event_count
            or observation.expected_manifest_digest ~= manifest.digest
        then
            return nil, failure(
                "StaleCompactionSnapshot",
                "Context compaction observation does not bind the active Context"
            )
        end
        local encoded, encode_error = schema.encode(document)
        if not encoded then return nil, encode_error end
        if #encoded > admitted.maximum_compaction_source_bytes then
            return nil, failure(
                "CompactionInputLimit",
                "canonical Context exceeds the compaction snapshot byte cap"
            )
        end
        local context_digest, digest_error = safety.digest(encoded)
        if type(context_digest) ~= "string" or context_digest == "" then
            return nil, digest_error or failure(
                "CompactionDigestFailure",
                "canonical Context digest is unavailable"
            )
        end
        local view, view_error = service.resolve_view(manifest.digest)
        if not view then return nil, view_error end

        local accepted = {}
        local recovery = document.recovery or {}
        local initial_serial = recovery.compaction_initial_serial or 0
        for _, record in ipairs(document.model_view.compaction_records) do
            accepted[record.id] = record.status == "ok"
            local serial = record.id:match("^compaction%-([1-9][0-9]*)$")
            serial = tonumber(serial)
            if valid_integer(serial, 1) and serial > initial_serial then
                initial_serial = serial
            end
        end
        local corrections = {}
        for _, event in ipairs(document.facts) do
            local fields = event.fields
            if event.type == "warning"
                and type(fields.errorId) == "string"
                and fields.errorId:match("^summary%-correction%-")
                and accepted[fields.causeId]
                and valid_text(fields.summary, admitted.maximum_model_view_bytes)
                and fields.summary ~= ""
            then
                corrections[#corrections + 1] = readonly({
                    correction_id = fields.errorId,
                    compaction_id = fields.causeId,
                    text = fields.summary,
                }, "durable compaction correction")
            end
            if event.type == "compaction" then
                local serial = fields.compactionId
                    and fields.compactionId:match("^compaction%-([1-9][0-9]*)$")
                serial = tonumber(serial)
                if valid_integer(serial, 1) and serial > initial_serial then
                    initial_serial = serial
                end
            end
        end
        local included_ranges = {}
        if manifest.last_event_seq > 0 then
            included_ranges[1] = readonly({
                first = manifest.first_event_seq,
                last = manifest.last_event_seq,
            }, "active Model-view range")
        end
        return readonly({
            document = document,
            context_digest = context_digest,
            context_generation = document.generation,
            last_sequence = document.event_count,
            manifest_digest = manifest.digest,
            manifest_compaction_id = manifest.compaction_id or false,
            view_body_bytes = #view.body,
            included_ranges = readonly(
                included_ranges,
                "active Model-view ranges"
            ),
            corrections = readonly(corrections, "durable compaction corrections"),
            initial_serial = initial_serial,
            initial_automatic_failure_count =
                recovery.automatic_compaction_failure_count or 0,
            automatic_failure_history_complete =
                recovery.automatic_compaction_failure_history_complete ~= false,
            pending_compactions = recovery.pending_compactions or readonly(
                {},
                "pending durable compactions"
            ),
            legacy_pending_compaction_request_ids =
                recovery.legacy_pending_compaction_request_ids or readonly(
                    {},
                    "legacy pending compaction requests"
                ),
            binding = observation,
        }, "durable compaction snapshot")
    end

    ---Commits one AgentLoop batch through the already-owned writer lease. Each
    -- acknowledged batch is a fully validated replacement generation.
    --@param batch table Exact sequence, generation, events, barrier, and optional compaction record.
    --@return boolean|nil True when a replacement generation is durable.
    --@return table Context journal receipt on success, or structured error on failure.
    --@effect Publishes a new Context generation and latches uncertain journal failures.
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
            compaction_record = true,
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
                    or (fields.compactionId or false) ~= prepared.compaction_id
                    or (prepared.compaction_id ~= false and
                        fields.viewContextGeneration
                            ~= tostring(prepared.context_generation))
                    or (prepared.compaction_id == false
                        and fields.viewContextGeneration ~= nil)
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
            compaction_record = batch.compaction_record,
        })
        if not document then
            if document_error and document_error.code == "ContextLimit" then
                return nil, { code = "ContextCapacity", publication_started = false,
                    message = "Context event capacity is exhausted; start a new Context" }
            end
            return nil, document_error
        end

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
            if publish_error and publish_error.code == "ContextCapacity"
                and publish_error.publication_started == false
            then
                return nil, publish_error
            end
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
    --@param none This service method takes no arguments.
    --@return table Read-only operation journal with commit and receipt methods.
    function service.operation_journal()
        if operation_journal then return operation_journal end
        local journal = {}

        -- Recover the owning turn ID from a canonical Tool call identifier.
        --@param tool_call_id any Candidate Tool call ID.
        --@return string|boolean Turn ID, or false when the ID is not canonical.
        local function turn_id(tool_call_id)
            if type(tool_call_id) ~= "string" then return false end
            return tool_call_id:match("^(.-):tool:[1-9][0-9]*$") or false
        end

        -- Publish operation intent or paired result facts under one Context barrier.
        --@param record table Operation record from the durable operation service.
        --@param digest string Record binding digest.
        --@param kind string intent or result.
        --@return boolean True after Context publication.
        --@return string|table Record digest on success, or error on failure.
        --@effect Appends operation facts and retains a one-use Runtime receipt.
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

        -- Publish an operation intent and retain its adoption receipt.
        --@param record table Durable operation intent record.
        --@param digest string Record digest.
        --@return boolean Commit status.
        --@return string|table Digest on success, or error on failure.
        function journal.commit_intent(record, digest)
            return commit_record(record, digest, "intent")
        end

        -- Publish operation and Tool result facts atomically.
        --@param record table Durable operation-result record.
        --@param digest string Record digest.
        --@return boolean Commit status.
        --@return string|table Digest on success, or error on failure.
        function journal.commit_result(record, digest)
            return commit_record(record, digest, "result")
        end

        -- Consume the exact one-use Context receipt for an operation barrier.
        --@param receipts table Intent or result receipt map.
        --@param operation_id string Durable operation ID.
        --@param digest string|nil Expected record digest.
        --@return table|nil Matching Context receipt.
        --@return table|nil OperationJournalContract diagnostic.
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

        -- Take the Runtime adoption receipt for a published intent.
        --@param operation_id string Durable operation ID.
        --@param digest string|nil Expected intent digest.
        --@return table|nil Context receipt.
        --@return table|nil Missing or mismatched receipt error.
        function journal.take_intent_receipt(operation_id, digest)
            return take(operation_intent_receipts, operation_id, digest)
        end

        -- Take the Runtime adoption receipt for a published operation result.
        --@param operation_id string Durable operation ID.
        --@param digest string|nil Expected result digest.
        --@return table|nil Context receipt.
        --@return table|nil Missing or mismatched receipt error.
        function journal.take_result_receipt(operation_id, digest)
            return take(operation_result_receipts, operation_id, digest)
        end

        operation_journal = readonly(journal, "Context operation journal")
        return operation_journal
    end

    ---Returns the durable journal used by compact.new. Every non-publication
    -- record advances Context while retaining the active manifest. An accepted
    -- summary, its terminal CompactionRecord, and its prepared Model view are
    -- published in one replacement generation or not at all.
    --@param none This service method takes no arguments.
    --@return table Read-only compaction journal with lifecycle commit methods.
    function service.compaction_journal()
        if compaction_journal then return compaction_journal end
        local journal = {}

        local RECORD_FIELDS = {
            ["compaction-request"] = {
                kind = true, purpose = true, mode = true, compaction_id = true,
                request_id = true, attempt = true, correction_reason = true,
                expected_context_generation = true,
                expected_manifest_digest = true, source_first_seq = true,
                source_last_seq = true, source_digest = true,
                config_snapshot = true, model_snapshot_digest = true,
                prompt_bundle_digest = true,
                manifest_snapshot_id = true,
            },
            ["compaction-response"] = {
                kind = true, compaction_id = true, request_id = true,
                attempt = true, canonical_body = true, canonical_digest = true,
                source_first_seq = true, source_last_seq = true,
                source_digest = true, usage = true,
                expected_context_generation = true,
                expected_manifest_digest = true,
            },
            ["compaction-rejection"] = {
                kind = true, compaction_id = true, request_id = true,
                attempt = true, error_code = true, detail = true,
                response_digest = true, response_body = true, terminal = true,
                source_first_seq = true, source_last_seq = true,
                source_digest = true, canonical_facts_before = true,
                config_snapshot = true, model_snapshot_digest = true,
                prompt_bundle_digest = true,
                expected_context_generation = true,
                expected_manifest_digest = true, old_view_retained = true,
            },
            ["compaction-cancel-request"] = {
                kind = true, compaction_id = true, request_id = true,
                reason = true, source_first_seq = true, source_last_seq = true,
                source_digest = true, canonical_facts_before = true,
                expected_context_generation = true,
                expected_manifest_digest = true, old_view_retained = true,
            },
            ["compaction-cancel-result"] = {
                kind = true, compaction_id = true, request_id = true,
                reason = true, outcome = true, source_first_seq = true,
                source_last_seq = true, source_digest = true,
                canonical_facts_before = true, config_snapshot = true,
                model_snapshot_digest = true, prompt_bundle_digest = true,
                expected_context_generation = true,
                expected_manifest_digest = true, old_view_retained = true,
            },
            ["compaction-publication"] = {
                kind = true, compaction_id = true, summary_id = true,
                request_id = true, expected_context_generation = true,
                expected_manifest_digest = true, canonical_facts_before = true,
                canonical_facts_removed = true, source_first_seq = true,
                source_last_seq = true, source_digest = true,
                config_snapshot = true, summary = true, summary_digest = true,
                summary_schema = true, generator_model_snapshot = true,
                usage = true, correction_ids = true, manifest = true,
                old_view_retained_until_publish = true,
                atomic_groups_split = true,
            },
            ["summary-correction"] = {
                kind = true, correction_id = true, compaction_id = true,
                source_first_seq = true, source_last_seq = true,
                source_digest = true, text = true, correction_digest = true,
                effective_at = true, expected_context_generation = true,
                expected_manifest_digest = true,
            },
        }

        -- Check a bounded identifier accepted by the compaction journal.
        --@param value any Candidate lifecycle or request ID.
        --@return boolean True for a nonempty safe identifier.
        local function valid_id(value)
            return valid_text(value, admitted.maximum_compaction_identifier_bytes)
                and value ~= ""
                and value:match("^[A-Za-z0-9][A-Za-z0-9._:-]*$") ~= nil
        end

        -- Check a lowercase SHA-256 digest in compaction records.
        --@param value any Candidate digest.
        --@return boolean True for a 64-character lowercase hexadecimal digest.
        local function valid_digest(value)
            return type(value) == "string"
                and #value == 64
                and value:match("^[0-9a-f]+$") ~= nil
        end

        -- Require every field in a closed compaction record schema and reject extras.
        --@param record any Candidate journal record.
        --@param kind string Expected record kind.
        --@return boolean|nil True for an exact record.
        --@return table|nil CompactionJournalContract diagnostic.
        local function exact_record(record, kind)
            local allowed = RECORD_FIELDS[kind]
            if type(record) ~= "table" or record.kind ~= kind or not allowed then
                return nil, failure(
                    "CompactionJournalContract",
                    "compaction journal record kind is invalid"
                )
            end
            for key in pairs(record) do
                if type(key) ~= "string" or not allowed[key] then
                    return nil, failure(
                        "CompactionJournalContract",
                        "compaction journal record contains an unknown field"
                    )
                end
            end
            for key in pairs(allowed) do
                if record[key] == nil then
                    return nil, failure(
                        "CompactionJournalContract",
                        "compaction journal record omits a required field",
                        key
                    )
                end
            end
            return true
        end

        -- Bind a compaction record to this owner's active generation and manifest.
        --@param record table Journal record with expected Context and manifest references.
        --@return table|nil Active durable Context document.
        --@return table Active manifest on success, or structured error on failure.
        local function current_document(record)
            if not active or not active.document then
                return nil, failure(
                    "ContextNotPublished",
                    "durable compaction journal has no active Context"
                )
            end
            local document = active.document
            local manifest = document.model_view.active_manifest
            if not valid_id(record.compaction_id)
                or not valid_integer(record.expected_context_generation, 1)
                or record.expected_context_generation ~= document.generation
                or not valid_digest(record.expected_manifest_digest)
                or record.expected_manifest_digest ~= manifest.digest
            then
                return nil, failure(
                    "StaleCompactionJournal",
                    "compaction record does not bind the active Context generation"
                )
            end
            return document, manifest
        end

        -- Verify an exact digest while mapping mismatch to the caller's error code.
        --@param bytes string Canonical bytes to hash.
        --@param expected string Claimed lowercase digest.
        --@param code string Mismatch diagnostic code.
        --@param message string Mismatch diagnostic summary.
        --@return boolean|nil True on exact match.
        --@return table|nil Structured mismatch or digest failure.
        local function verify_digest(bytes, expected, code, message)
            if not valid_digest(expected) then return nil, failure(code, message) end
            local called, observed, digest_error = pcall(safety.digest, bytes)
            if not called or observed ~= expected then
                return nil, failure(
                    code,
                    message,
                    called and (digest_error or observed) or "digest-exception"
                )
            end
            return true
        end

        -- Rebuild a bounded compaction source and match its durable range and digest.
        --@param document table Active Context document.
        --@param record table Candidate source range and digest.
        --@param lifecycle table|nil Earlier lifecycle binding for retries.
        --@param source_event_count integer|nil Explicit source waterline.
        --@return integer|nil Verified source event count.
        --@return table|nil Stale range, encoder, or digest error.
        local function verify_source(document, record, lifecycle, source_event_count)
            source_event_count = source_event_count
                or (lifecycle and lifecycle.source_event_count)
            if not valid_integer(record.source_first_seq, 1)
                or record.source_first_seq ~= 1
                or not valid_integer(record.source_last_seq, record.source_first_seq)
                or not valid_integer(source_event_count, record.source_last_seq)
                or source_event_count > document.event_count
                or (lifecycle and (
                    record.source_first_seq ~= lifecycle.source_first_seq
                    or record.source_last_seq ~= lifecycle.source_last_seq
                    or record.source_digest ~= lifecycle.source_digest
                    or source_event_count ~= lifecycle.source_event_count
                ))
            then
                return nil, failure(
                    "CompactionSourceMismatch",
                    "compaction record source range is stale or inconsistent"
                )
            end
            local called, bytes, source_error = pcall(
                compact.encode_source,
                document,
                record.source_first_seq,
                record.source_last_seq,
                admitted.maximum_compaction_identifier_bytes,
                admitted.maximum_compaction_source_bytes
            )
            if not called or not bytes then
                return nil, called and source_error or failure(
                    "CompactionSourceMismatch",
                    "canonical compaction source could not be rebuilt"
                )
            end
            local verified, verify_error = verify_digest(
                bytes,
                record.source_digest,
                "CompactionSourceMismatch",
                "canonical compaction source digest disagrees"
            )
            if not verified then return nil, verify_error end
            return source_event_count
        end

        -- Resolve a live compaction lifecycle matching request, attempt, and manifest.
        --@param record table Compaction journal record.
        --@param require_response boolean Whether a response must already be durable.
        --@return table|nil Matching nonterminal lifecycle.
        --@return table|nil CompactionJournalContract diagnostic.
        local function lifecycle_for(record, require_response)
            local lifecycle = compaction_lifecycles[record.compaction_id]
            if not lifecycle or lifecycle.terminal
                or record.request_id ~= lifecycle.request_id
                or record.attempt ~= lifecycle.attempt
                or record.expected_manifest_digest ~= lifecycle.manifest_digest
                or (require_response and lifecycle.response_committed ~= true)
            then
                return nil, failure(
                    "CompactionJournalContract",
                    "compaction record does not match its active lifecycle"
                )
            end
            return lifecycle
        end

        -- Derive a unique Context barrier ID from compaction kind and sequence.
        --@param record table Bound compaction record.
        --@param first_sequence integer First event sequence in the proposed batch.
        --@return string|nil Domain-separated barrier ID.
        --@return table|nil Binding-digest error.
        local function barrier_id(record, first_sequence)
            local called, digest, digest_error = pcall(
                safety.binding_digest,
                "yaca-compaction-journal-barrier-v1",
                {
                    { name = "kind", value = record.kind },
                    { name = "compaction", value = record.compaction_id },
                    { name = "generation", value = tostring(record.expected_context_generation) },
                    { name = "sequence", value = tostring(first_sequence) },
                }
            )
            if not called or not valid_digest(digest) then
                return nil, digest_error or failure(
                    "CompactionJournalContract",
                    "compaction journal barrier could not be bound"
                )
            end
            return "compaction:" .. digest
        end

        -- Commit a compaction fact batch and return its Runtime adoption receipt.
        --@param record table Bound compaction journal record.
        --@param events table New events to sequence and publish.
        --@param compaction_record table|nil Terminal summary record for schema publication.
        --@param publishing boolean Whether this batch changes the active Model view.
        --@return boolean True after durable Context publication.
        --@return table Journal receipt on success, or structured error on failure.
        --@effect Publishes a new Context generation through the sole writer.
        local function commit_events(record, events, compaction_record, publishing)
            local first_sequence = active.document.event_count + 1
            local barrier, barrier_error = barrier_id(record, first_sequence)
            if not barrier then return false, barrier_error end
            for index, event in ipairs(events) do
                event.seq = first_sequence + index - 1
            end
            local batch = {
                barrier_id = barrier,
                first_sequence = first_sequence,
                last_sequence = first_sequence + #events - 1,
                event_count = #events,
                expected_context_generation = record.expected_context_generation,
                events = events,
            }
            if compaction_record then batch.compaction_record = compaction_record end
            local previous_manifest = active.document.model_view.active_manifest.digest
            local committed, receipt = service.commit(batch)
            if committed ~= true then return false, receipt end
            local current_manifest = active.document.model_view.active_manifest.digest
            local values = {
                binding = record,
                previous_context_generation = receipt.previous_context_generation,
                context_generation = receipt.context_generation,
                runtime_receipt = receipt,
            }
            if publishing then
                values.previous_manifest_digest = previous_manifest
                values.published_manifest_digest = current_manifest
            else
                values.active_manifest_digest = current_manifest
            end
            return true, readonly(values, "durable compaction journal receipt")
        end

        -- Publish and bind a new compaction request or valid retry.
        --@param record table Exact compaction-request record.
        --@return boolean True after durable request publication.
        --@return table Receipt on success, or structured error on failure.
        --@effect Adds a model_request fact and retains lifecycle state.
        function journal.commit_intent(record)
            local exact, exact_error = exact_record(record, "compaction-request")
            if not exact then return false, exact_error end
            local document, document_error = current_document(record)
            if not document then return false, document_error end
            if record.purpose ~= "compaction"
                or (record.mode ~= "manual" and record.mode ~= "automatic")
                or not valid_id(record.request_id)
                or not valid_integer(record.attempt, 1)
                or not valid_digest(record.config_snapshot)
                or not valid_digest(record.model_snapshot_digest)
                or not valid_digest(record.prompt_bundle_digest)
                or not valid_id(record.manifest_snapshot_id)
                or (record.correction_reason ~= false
                    and not valid_text(
                        record.correction_reason,
                        admitted.maximum_model_view_bytes
                    ))
            then
                return false, failure(
                    "CompactionJournalContract",
                    "compaction request record is invalid"
                )
            end
            local previous = compaction_lifecycles[record.compaction_id]
            local source_event_count
            if previous then
                if previous.terminal
                    or record.attempt ~= previous.attempt + 1
                    or record.mode ~= previous.mode
                    or record.config_snapshot ~= previous.config_snapshot
                    or record.model_snapshot_digest ~= previous.model_snapshot_digest
                    or record.prompt_bundle_digest ~= previous.prompt_bundle_digest
                    or record.manifest_snapshot_id ~= previous.manifest_snapshot_id
                    or record.expected_manifest_digest ~= previous.manifest_digest
                then
                    return false, failure(
                        "CompactionJournalContract",
                        "compaction retry does not continue its prior lifecycle"
                    )
                end
                source_event_count, document_error = verify_source(
                    document,
                    record,
                    previous
                )
                if not source_event_count then return false, document_error end
            else
                if record.attempt ~= 1 then
                    return false, failure(
                        "CompactionJournalContract",
                        "first compaction request must be attempt one"
                    )
                end
                source_event_count, document_error = verify_source(
                    document,
                    record,
                    nil,
                    document.event_count
                )
                if not source_event_count then return false, document_error end
            end
            local candidate = {
                compaction_id = record.compaction_id,
                mode = record.mode,
                request_id = record.request_id,
                attempt = record.attempt,
                source_first_seq = record.source_first_seq,
                source_last_seq = record.source_last_seq,
                source_digest = record.source_digest,
                source_event_count = source_event_count,
                manifest_digest = record.expected_manifest_digest,
                config_snapshot = record.config_snapshot,
                model_snapshot_digest = record.model_snapshot_digest,
                prompt_bundle_digest = record.prompt_bundle_digest,
                manifest_snapshot_id = record.manifest_snapshot_id,
                response_committed = false,
                cancel_requested = false,
                terminal = false,
            }
            local committed, receipt = commit_events(record, { {
                type = "model_request",
                fields = {
                    requestId = record.request_id,
                    purpose = "compaction",
                    viewManifestRef = record.expected_manifest_digest,
                    attemptId = tostring(record.attempt),
                    compactionId = record.compaction_id,
                    compactionMode = record.mode,
                    sourceFirstSeq = tostring(record.source_first_seq),
                    sourceLastSeq = tostring(record.source_last_seq),
                    sourceDigest = record.source_digest,
                    sourceEventCount = tostring(source_event_count),
                    configSnapshot = record.config_snapshot,
                    modelSnapshot = record.model_snapshot_digest,
                    promptSnapshot = record.prompt_bundle_digest,
                    manifestSnapshot = record.manifest_snapshot_id,
                    viewContextGeneration = tostring(
                        record.expected_context_generation
                    ),
                },
            } }, nil, false)
            if committed ~= true then return false, receipt end
            compaction_lifecycles[record.compaction_id] = candidate
            return true, receipt
        end

        -- Publish one digest-verified complete compaction Model response.
        --@param record table Exact compaction-response record.
        --@return boolean True after durable response publication.
        --@return table Receipt on success, or structured error on failure.
        --@effect Adds a model_message fact and marks response committed.
        function journal.commit_response(record)
            local exact, exact_error = exact_record(record, "compaction-response")
            if not exact then return false, exact_error end
            local document, document_error = current_document(record)
            if not document then return false, document_error end
            local lifecycle, lifecycle_error = lifecycle_for(record, false)
            if not lifecycle then return false, lifecycle_error end
            if lifecycle.response_committed
                or not valid_text(record.canonical_body, admitted.maximum_model_view_bytes)
                or record.canonical_body == ""
            then
                return false, failure(
                    "CompactionJournalContract",
                    "compaction response record is invalid or duplicated"
                )
            end
            local source_count, source_error = verify_source(document, record, lifecycle)
            if not source_count then return false, source_error end
            local verified, verify_error = verify_digest(
                record.canonical_body,
                record.canonical_digest,
                "CompactionSummaryMismatch",
                "compaction response digest disagrees"
            )
            if not verified then return false, verify_error end
            local message_id = record.request_id .. ":response"
            if not valid_id(message_id) then
                return false, failure(
                    "CompactionJournalContract",
                    "compaction response message identity is too large"
                )
            end
            local committed, receipt = commit_events(record, { {
                type = "model_message",
                fields = {
                    messageId = message_id,
                    requestId = record.request_id,
                    role = "assistant",
                    status = "complete",
                    body = record.canonical_body,
                    rawBytes = tostring(#record.canonical_body),
                    digest = record.canonical_digest,
                },
            } }, nil, false)
            if committed ~= true then return false, receipt end
            lifecycle.response_committed = true
            return true, receipt
        end

        -- Build a terminal compaction event and schema record from one lifecycle.
        --@param record table Source and terminal result fields.
        --@param lifecycle table Bound live compaction lifecycle.
        --@param status string Terminal status.
        --@param error_id string|nil Failure code for rejected or unknown compaction.
        --@param automatic_failure boolean Whether this counts as an automatic failure.
        --@return table Compaction event.
        --@return table Terminal schema record.
        local function terminal_event(
            record,
            lifecycle,
            status,
            error_id,
            automatic_failure
        )
            local fields = {
                compactionId = record.compaction_id,
                sourceFirstSeq = tostring(record.source_first_seq),
                sourceLastSeq = tostring(record.source_last_seq),
                sourceDigest = record.source_digest,
                status = status,
                sourceEventCount = tostring(record.canonical_facts_before),
                viewContextGeneration = tostring(record.expected_context_generation),
                requestId = record.request_id,
                attemptId = tostring(lifecycle.attempt),
                compactionMode = lifecycle.mode,
                automaticFailure = automatic_failure and "true" or "false",
            }
            if error_id then fields.errorId = error_id end
            if record.model_snapshot_digest then
                fields.modelSnapshot = record.model_snapshot_digest
            end
            if record.prompt_bundle_digest then
                fields.promptSnapshot = record.prompt_bundle_digest
            end
            return {
                type = "compaction",
                fields = fields,
            }, {
                id = record.compaction_id,
                source_first_seq = record.source_first_seq,
                source_last_seq = record.source_last_seq,
                source_digest = record.source_digest,
                status = status,
            }
        end

        -- Publish a rejected response or cancellation while retaining the old view.
        --@param record table Exact rejection, cancel-request, or cancel-result record.
        --@return boolean True after durable event publication.
        --@return table Receipt on success, or structured error on failure.
        --@effect Adds warning/cancel/terminal facts and updates lifecycle state.
        function journal.commit_rejection(record)
            if type(record) ~= "table" or not RECORD_FIELDS[record.kind] then
                return false, failure(
                    "CompactionJournalContract",
                    "compaction rejection kind is invalid"
                )
            end
            local exact, exact_error = exact_record(record, record.kind)
            if not exact then return false, exact_error end
            if record.kind ~= "compaction-rejection"
                and record.kind ~= "compaction-cancel-request"
                and record.kind ~= "compaction-cancel-result"
            then
                return false, failure(
                    "CompactionJournalContract",
                    "record is not a compaction rejection or cancellation"
                )
            end
            local document, document_error = current_document(record)
            if not document then return false, document_error end
            local lifecycle, lifecycle_error
            if record.kind == "compaction-rejection" then
                lifecycle, lifecycle_error = lifecycle_for(record, false)
            else
                lifecycle = compaction_lifecycles[record.compaction_id]
                if not lifecycle or lifecycle.terminal
                    or record.request_id ~= lifecycle.request_id
                    or record.expected_manifest_digest ~= lifecycle.manifest_digest
                then
                    lifecycle_error = failure(
                        "CompactionJournalContract",
                        "cancellation does not match its active lifecycle"
                    )
                    lifecycle = nil
                end
            end
            if not lifecycle then return false, lifecycle_error end
            if record.canonical_facts_before ~= lifecycle.source_event_count
                or record.old_view_retained ~= true
            then
                return false, failure(
                    "CompactionJournalContract",
                    "rejection does not retain the bound source and Model view"
                )
            end
            local source_count, source_error = verify_source(document, record, lifecycle)
            if not source_count then return false, source_error end

            local events = {}
            local compaction_record
            local terminal = false
            if record.kind == "compaction-rejection" then
                if type(record.terminal) ~= "boolean"
                    or not valid_id(record.error_code)
                    or not valid_text(record.detail, admitted.maximum_model_view_bytes)
                    or (record.response_body ~= false
                        and not valid_text(
                            record.response_body,
                            admitted.maximum_model_view_bytes
                        ))
                    or (record.response_digest ~= false
                        and record.response_digest ~= ""
                        and not valid_digest(record.response_digest))
                    or not valid_digest(record.config_snapshot)
                    or record.config_snapshot ~= lifecycle.config_snapshot
                    or not valid_digest(record.model_snapshot_digest)
                    or record.model_snapshot_digest
                        ~= lifecycle.model_snapshot_digest
                    or not valid_digest(record.prompt_bundle_digest)
                    or record.prompt_bundle_digest
                        ~= lifecycle.prompt_bundle_digest
                then
                    return false, failure(
                        "CompactionJournalContract",
                        "compaction rejection record is invalid"
                    )
                end
                local body = record.response_body == false and "" or record.response_body
                local message_id = record.request_id .. ":rejected"
                if not valid_id(message_id) then
                    return false, failure(
                        "CompactionJournalContract",
                        "compaction rejection message identity is too large"
                    )
                end
                local message_fields = {
                    messageId = message_id,
                    requestId = record.request_id,
                    role = "assistant",
                    status = "interrupted",
                    body = body,
                    rawBytes = tostring(#body),
                }
                if record.response_digest ~= false and record.response_digest ~= "" then
                    message_fields.digest = record.response_digest
                end
                events[#events + 1] = {
                    type = "model_message",
                    fields = message_fields,
                }
                events[#events + 1] = {
                    type = "warning",
                    fields = {
                        errorId = record.error_code,
                        summary = record.detail ~= "" and record.detail
                            or "compaction response rejected",
                        causeId = record.compaction_id,
                    },
                }
                terminal = record.terminal
                if terminal then
                    local event
                    event, compaction_record = terminal_event(
                        record,
                        lifecycle,
                        "error",
                        record.error_code,
                        lifecycle.mode == "automatic"
                    )
                    events[#events + 1] = event
                end
            elseif record.kind == "compaction-cancel-request" then
                if lifecycle.cancel_requested
                    or not valid_text(record.reason, admitted.maximum_model_view_bytes)
                    or record.reason == ""
                then
                    return false, failure(
                        "CompactionJournalContract",
                        "compaction cancel request is invalid or duplicated"
                    )
                end
                events[1] = {
                    type = "cancel",
                    fields = {
                        targetKind = "compaction-request",
                        targetId = record.request_id,
                        reason = record.reason,
                        result = "pending",
                    },
                }
            else
                if not lifecycle.cancel_requested
                    or (record.outcome ~= "cancelled" and record.outcome ~= "unknown")
                    or record.reason ~= lifecycle.cancel_reason
                    or not valid_digest(record.config_snapshot)
                    or record.config_snapshot ~= lifecycle.config_snapshot
                    or not valid_digest(record.model_snapshot_digest)
                    or record.model_snapshot_digest
                        ~= lifecycle.model_snapshot_digest
                    or not valid_digest(record.prompt_bundle_digest)
                    or record.prompt_bundle_digest
                        ~= lifecycle.prompt_bundle_digest
                then
                    return false, failure(
                        "CompactionJournalContract",
                        "compaction cancel result is invalid"
                    )
                end
                events[1] = {
                    type = "cancel",
                    fields = {
                        targetKind = "compaction-request",
                        targetId = record.request_id,
                        reason = record.reason,
                        result = record.outcome,
                    },
                }
                local status = record.outcome == "cancelled" and "cancelled" or "error"
                local error_id = status == "error" and "CompactionCancelUnknown" or nil
                local event
                event, compaction_record = terminal_event(
                    record,
                    lifecycle,
                    status,
                    error_id,
                    lifecycle.mode == "automatic"
                        and (record.reason == "compaction-active-time"
                            or record.reason == "compaction-process-recovery")
                )
                events[#events + 1] = event
                terminal = true
            end
            local committed, receipt = commit_events(
                record,
                events,
                compaction_record,
                false
            )
            if committed ~= true then return false, receipt end
            if record.kind == "compaction-cancel-request" then
                lifecycle.cancel_requested = true
                lifecycle.cancel_reason = record.reason
            elseif terminal then
                lifecycle.terminal = true
                lifecycle.outcome = compaction_record.status
            end
            return true, receipt
        end

        -- Atomically publish an accepted summary, terminal fact, and new Model view.
        --@param record table Exact compaction-publication record and canonical manifest.
        --@return boolean True after one durable replacement generation.
        --@return table Receipt on success, or validation/publication error.
        --@effect Advances active Model view only with verified source and summary bindings.
        function journal.publish(record)
            local exact, exact_error = exact_record(record, "compaction-publication")
            if not exact then return false, exact_error end
            local document, manifest_or_error = current_document(record)
            if not document then return false, manifest_or_error end
            local lifecycle = compaction_lifecycles[record.compaction_id]
            if not lifecycle or lifecycle.terminal
                or lifecycle.response_committed ~= true
                or record.request_id ~= lifecycle.request_id
                or record.canonical_facts_before ~= lifecycle.source_event_count
                or record.config_snapshot ~= lifecycle.config_snapshot
                or record.generator_model_snapshot ~= lifecycle.model_snapshot_digest
                or record.old_view_retained_until_publish ~= true
                or record.canonical_facts_removed ~= 0
                or record.atomic_groups_split ~= 0
                or type(record.manifest) ~= "table"
                or record.manifest.prompt_bundle_digest
                    ~= lifecycle.prompt_bundle_digest
                or record.manifest.context_generation
                    ~= record.expected_context_generation
                or record.manifest.summary_id ~= record.summary_id
                or record.manifest.model_snapshot_digest
                    ~= record.generator_model_snapshot
                or record.manifest.digest == record.expected_manifest_digest
                or not valid_digest(record.manifest.digest)
                or not valid_text(
                    record.manifest.canonical_bytes,
                    admitted.maximum_compaction_source_bytes
                )
                or record.manifest.canonical_bytes == ""
                or not valid_id(record.manifest.builder_algorithm)
                or not valid_digest(record.manifest.prompt_bundle_digest)
                or record.manifest.summary_source_range
                    ~= tostring(record.source_first_seq)
                        .. "-" .. tostring(record.source_last_seq)
                or not valid_text(record.summary, admitted.maximum_model_view_bytes)
                or record.summary == ""
                or text.xml_carrier_kind(record.summary) ~= "text"
            then
                return false, failure(
                    "CompactionJournalContract",
                    "compaction publication does not match its durable lifecycle"
                )
            end
            local decoded_called, decoded, decode_error = pcall(
                compact.decode_summary,
                record.summary,
                admitted.maximum_model_view_bytes
            )
            if not decoded_called or not decoded
                or decoded.schema_version ~= record.summary_schema
                or decoded.source_first_seq ~= record.source_first_seq
                or decoded.source_last_seq ~= record.source_last_seq
                or decoded.source_digest ~= record.source_digest
            then
                return false, decoded_called and (decode_error or failure(
                    "CompactionSummaryMismatch",
                    "accepted structured summary source binding disagrees"
                )) or failure(
                    "CompactionSummaryMismatch",
                    "accepted structured summary could not be decoded"
                )
            end
            local correction_count = dense_count(record.correction_ids)
            local manifest_correction_count = dense_count(
                record.manifest.correction_ids
            )
            if correction_count == nil
                or manifest_correction_count ~= correction_count
            then
                return false, failure(
                    "CompactionManifestMismatch",
                    "compaction manifest correction set disagrees"
                )
            end
            for index = 1, correction_count do
                if record.correction_ids[index]
                    ~= record.manifest.correction_ids[index]
                then
                    return false, failure(
                        "CompactionManifestMismatch",
                        "compaction manifest correction order disagrees"
                    )
                end
            end
            local manifest_called, rebuilt_manifest, manifest_error = pcall(
                compact.encode_manifest,
                record.manifest,
                admitted.maximum_compaction_identifier_bytes,
                admitted.maximum_compaction_source_bytes
            )
            if not manifest_called
                or rebuilt_manifest ~= record.manifest.canonical_bytes
            then
                return false, manifest_called and (manifest_error or failure(
                    "CompactionManifestMismatch",
                    "accepted compaction manifest bytes are not canonical"
                )) or failure(
                    "CompactionManifestMismatch",
                    "accepted compaction manifest could not be rebuilt"
                )
            end
            local source_count, source_error = verify_source(document, record, lifecycle)
            if not source_count then return false, source_error end
            local verified, verify_error = verify_digest(
                record.summary,
                record.summary_digest,
                "CompactionSummaryMismatch",
                "accepted compaction summary digest disagrees"
            )
            if not verified then return false, verify_error end
            verified, verify_error = verify_digest(
                record.manifest.canonical_bytes,
                record.manifest.digest,
                "CompactionManifestMismatch",
                "accepted compaction manifest digest disagrees"
            )
            if not verified then return false, verify_error end

            local terminal_sequence = document.event_count + 1
            local publication_sequence = terminal_sequence + 1
            local projection, projection_error = verified_compaction_projection(
                document,
                {
                    compaction_id = record.compaction_id,
                    source_first_seq = record.source_first_seq,
                    source_last_seq = record.source_last_seq,
                    source_event_count = record.canonical_facts_before,
                    internal_last_sequence = publication_sequence,
                    source_digest = record.source_digest,
                    summary_digest = record.summary_digest,
                    summary = record.summary,
                    fact_limit = record.canonical_facts_before,
                    waterline = publication_sequence,
                }
            )
            if not projection then return false, projection_error end
            local previous_cached = model_views[record.manifest.digest]
            local prepared, prepare_error = cache_model_view(
                document.facts,
                record.expected_context_generation,
                projection,
                record.manifest.digest
            )
            if not prepared then return false, prepare_error end
            local compaction_fields = {
                compactionId = record.compaction_id,
                sourceFirstSeq = tostring(record.source_first_seq),
                sourceLastSeq = tostring(record.source_last_seq),
                sourceDigest = record.source_digest,
                status = "ok",
                summary = record.summary,
                sourceEventCount = tostring(record.canonical_facts_before),
                summaryDigest = record.summary_digest,
                manifestDigest = record.manifest.digest,
                builderAlgorithm = record.manifest.builder_algorithm,
                modelSnapshot = record.generator_model_snapshot,
                promptSnapshot = record.manifest.prompt_bundle_digest,
                viewContextGeneration = tostring(record.expected_context_generation),
                requestId = record.request_id,
                attemptId = tostring(lifecycle.attempt),
                compactionMode = lifecycle.mode,
                automaticFailure = "false",
            }
            local compaction_record = {
                id = record.compaction_id,
                source_first_seq = record.source_first_seq,
                source_last_seq = record.source_last_seq,
                source_digest = record.source_digest,
                status = "ok",
                summary = record.summary,
            }
            local committed, receipt = commit_events(record, {
                { type = "compaction", fields = compaction_fields },
                {
                    type = "model_view_published",
                    fields = {
                        manifestDigest = record.manifest.digest,
                        firstEventSeq = "1",
                        lastEventSeq = tostring(publication_sequence),
                        replacesManifestDigest = record.expected_manifest_digest,
                        compactionId = record.compaction_id,
                        viewContextGeneration = tostring(
                            record.expected_context_generation
                        ),
                    },
                },
            }, compaction_record, true)
            if committed ~= true then
                model_views[record.manifest.digest] = previous_cached
                return false, receipt
            end
            lifecycle.terminal = true
            lifecycle.outcome = "ok"
            lifecycle.manifest_digest = record.manifest.digest
            return true, receipt
        end

        -- Publish a digest-checked correction for an already accepted summary.
        --@param record table Exact summary-correction record.
        --@return boolean True after durable warning publication.
        --@return table Receipt on success, or structured error on failure.
        --@effect Appends a correction warning for the next Model view publication.
        function journal.commit_correction(record)
            local exact, exact_error = exact_record(record, "summary-correction")
            if not exact then return false, exact_error end
            local document, document_error = current_document(record)
            if not document then return false, document_error end
            if not valid_id(record.correction_id)
                or record.effective_at ~= "next-model-view-publication"
                or not valid_text(record.text, admitted.maximum_model_view_bytes)
                or record.text == ""
            then
                return false, failure(
                    "CompactionJournalContract",
                    "summary correction record is invalid"
                )
            end
            local accepted
            for _, candidate in ipairs(document.model_view.compaction_records) do
                if candidate.id == record.compaction_id and candidate.status == "ok"
                    and candidate.source_first_seq == record.source_first_seq
                    and candidate.source_last_seq == record.source_last_seq
                    and candidate.source_digest == record.source_digest
                then
                    accepted = true
                    break
                end
            end
            if not accepted then
                return false, failure(
                    "CompactionJournalContract",
                    "summary correction has no accepted compaction source"
                )
            end
            local verified, verify_error = verify_digest(
                record.text,
                record.correction_digest,
                "CompactionCorrectionMismatch",
                "summary correction digest disagrees"
            )
            if not verified then return false, verify_error end
            return commit_events(record, { {
                type = "warning",
                fields = {
                    errorId = record.correction_id,
                    summary = record.text,
                    causeId = record.compaction_id,
                },
            } }, nil, false)
        end

        compaction_journal = readonly(journal, "Context compaction journal")
        return compaction_journal
    end

    ---Returns the latest publication receipt without filesystem access.
    --@param none This service method takes no arguments.
    --@return table Active publication receipt or non-durable closed status.
    function service.status()
        if active then return active.receipt end
        return readonly({ durable = false, closed = closed }, "Context publication status")
    end

    ---Checks the active writer and derives its current public path hash.
    -- A failed observation is sticky and closes all later publication barriers.
    -- This reads only the owned file and never discovers or follows a replacement.
    --@param none This service method takes no arguments.
    --@return table|nil Verified active Context status and current hash.
    --@return table|nil Closed, stale, or missing-owner error.
    function service.inspect_active()
        if closed then
            return nil, failure("ContextPublicationClosed", "Context inspection is closed")
        end
        if journal_failure then return nil, journal_failure end
        if not active or not active.writer then
            return nil, failure("ContextNotPublished", "Context inspection has no durable owner")
        end
        local checked, check_error = store.verify_writer(active.writer)
        if not checked or checked.path ~= active.receipt.context_path
            or checked.generation ~= active.document.generation
        then
            journal_failure = failure(
                "ContextStale",
                "the active Context is stale; execution has stopped",
                check_error and check_error.code or "writer-receipt-mismatch"
            )
            return nil, journal_failure
        end
        local hash, hash_error = path.context_hash(active.receipt.logical_path)
        if not hash then
            journal_failure = failure(
                "ContextStale", "the active Context hash is unavailable", hash_error and hash_error.code
            )
            return nil, journal_failure
        end
        local values = {}
        for key, value in pairs(active.receipt) do values[key] = value end
        values.context_hash = hash
        return readonly(values, "verified active Context status")
    end

    ---Exports only this owner's verified current document without mutation.
    --@param secret_scan function|nil Current ConfigGeneration secret scanner.
    --@return string|nil markdown Complete bounded public Markdown view.
    --@return table|nil receipt Verified identity, or a typed failure.
    function service.export_active(secret_scan)
        local inspected, inspection_error = service.inspect_active()
        if not inspected then return nil, inspection_error end
        local markdown, export_error = schema.export(active.document, nil, secret_scan)
        if not markdown then return nil, export_error end
        local verified, verify_error = service.inspect_active()
        if not verified then return nil, verify_error end
        return markdown, verified
    end

    -- Release the owned Context writer and close this publication service.
    --@param none This service method takes no arguments.
    --@return boolean|nil True after release, false if already closed.
    --@return table|nil Writer-release error.
    --@effect Closes the sole Context writer lease.
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
--@param generation table Immutable Agent-ready ConfigGeneration.
--@param workspace table Validated path/identity/enterable observation.
--@param options table Contains maximum_draft_bytes.
--@param publication table|nil First-Context publication service attached to the draft.
--@return table|nil draft Immutable facade over the owned draft state.
--@return table|nil err Structured validation failure.
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

    -- Require the unsaved draft to remain before first publication or close.
    --@param none This closure takes no arguments.
    --@return boolean|nil True while the draft is not saved.
    --@return table|nil SessionClosed diagnostic.
    local function require_open()
        if lifecycle ~= "not-saved" then
            return nil, failure("SessionClosed", "the unsaved chat draft is closed")
        end
        return true
    end

    -- Snapshot unsaved draft settings and any published Context identity.
    --@param none This closure takes no arguments.
    --@return table Read-only draft status and selection fields.
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
            double_check_default = generation.agent.double_check,
            double_check_override = settings.double_check_override,
            double_check_goal = settings.double_check_goal,
            context_prompt = settings.context_prompt,
            auto_rename_disabled = settings.auto_rename_disabled,
        }, "session status")
    end

    ---Returns a fresh immutable projection of the owned draft state.
    --@param none This draft method takes no arguments.
    --@return table Read-only draft status.
    function draft.status()
        return status()
    end

    ---Updates only session-whitelisted settings before the first main message.
    --@param changes table Model, Permission, DoubleCheck, goal, and Prompt fields.
    --@return table|nil status New immutable draft projection.
    --@return table|nil err Unknown, invalid, or closed-state failure.
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
            double_check_override = true,
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
        if changes.double_check ~= nil
            and changes.double_check_override ~= nil
        then
            return nil, failure(
                "InvalidDraftUpdate",
                "double_check and double_check_override are mutually exclusive"
            )
        end
        local double_check_change = changes.double_check
        if double_check_change == nil then
            double_check_change = changes.double_check_override
        end
        if double_check_change ~= nil then
            if double_check_change ~= "inherit"
                and type(double_check_change) ~= "boolean"
            then
                return nil, failure(
                    "InvalidDraftUpdate",
                    "double_check override must be boolean or inherit"
                )
            end
            next_settings.double_check_override = double_check_change
            next_settings.double_check = double_check_change == "inherit"
                and generation.agent.double_check or double_check_change
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
    --@param message string Initial main or ask input.
    --@param source string|nil Input source label.
    --@param lane string main or ask initial lane.
    --@return table|nil Durable first Context receipt.
    --@return table|nil Closed, secret, validation, or publication error.
    --@effect Publishes and retains the first Context writer on success.
    local function begin_first(message, source, lane)
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
            initial_lane = lane,
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

    -- Publish the first main request through the shared first-turn gate.
    --@param message string Initial main input.
    --@param source string|nil Input source label.
    --@return table|nil Durable first Context receipt.
    --@return table|nil First-turn validation or publication error.
    function draft.begin_main(message, source)
        return begin_first(message, source, "main")
    end

    -- Publish only the Context owner before a first ask request begins.
    --@param message string Initial ask input.
    --@param source string|nil Input source label.
    --@return table|nil Durable first Context receipt.
    --@return table|nil First-turn validation or publication error.
    function draft.begin_ask(message, source)
        return begin_first(message, source, "ask")
    end

    ---Returns the exact precommitted first-turn handoff for AgentLoop. The
    -- handoff exists only after begin_main received a durable receipt.
    --@param none This draft method takes no arguments.
    --@return table|nil Read-only first-turn input and publication binding.
    --@return table|nil ContextNotPublished diagnostic.
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
                model_request_limit = publication_receipt.model_request_limit,
                tool_call_limit = publication_receipt.tool_call_limit,
                queue_limit = publication_receipt.queue_limit,
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
                model_request_limit = publication_receipt.model_request_limit,
                tool_call_limit = publication_receipt.tool_call_limit,
                queue_limit = publication_receipt.queue_limit,
            }, "published first-turn binding"),
        }, "published first-turn handoff")
    end

    ---Closes the in-memory draft without creating any filesystem object.
    --@param none This draft method takes no arguments.
    --@return boolean|nil True after close, false if already closed.
    --@return table|nil Context writer release error.
    --@effect Releases a saved Context writer when one was attached.
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
    --@param none This draft method takes no arguments.
    --@return table Original immutable config generation.
    function draft.config_generation()
        return generation
    end

    return readonly(draft, "unsaved chat draft")
end

---Creates the saved-session input owner over one typed AgentLoop.
-- Draft observation is captured when text is staged, so a delayed submission
-- cannot silently redirect itself to a newer Context generation or turn.
--@param loop table Typed Runtime AgentLoop facade.
--@param options table Contains maximum_draft_bytes.
--@return table|nil session Readonly saved-session facade.
--@return table|nil err Structured construction failure.
function M.new_agent_session(loop, options)
    if type(loop) ~= "table"
        or type(loop.status) ~= "function"
        or type(loop.submit_main) ~= "function"
        or type(loop.enqueue) ~= "function"
        or type(loop.steer) ~= "function"
        or type(loop.start_ask) ~= "function"
        or type(loop.resolve_yield) ~= "function"
        or type(loop.reply) ~= "function"
        or type(loop.list_queue) ~= "function"
        or type(loop.drop_queue) ~= "function"
        or type(loop.edit_queue) ~= "function"
        or type(loop.reorder_queue) ~= "function"
        or type(loop.clear_queue) ~= "function"
        or type(loop.use_ask) ~= "function"
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

    -- Reject saved-session input after the AgentLoop owner has closed.
    --@param none This closure takes no arguments.
    --@return boolean|nil True while the saved session is open.
    --@return table|nil SessionClosed diagnostic.
    local function require_open()
        if lifecycle ~= "open" then
            return nil, failure("SessionClosed", "the saved Agent session is closed")
        end
        return true
    end

    -- Capture the exact Context generation and turn ID seen by a queue action.
    --@param status table Current typed AgentLoop status.
    --@return table Expected Context generation and turn identity.
    local function observation(status)
        return {
            expected_context_generation = status.context_generation,
            expected_turn_id = status.turn_id,
        }
    end

    -- Read the current AgentLoop observation for an immediate queue action.
    --@param none This closure takes no arguments.
    --@return table Context generation and turn identity.
    local function current_observation()
        return observation(loop:status())
    end

    -- Project staged text and its captured observation into a Runtime command.
    --@param none This closure takes no arguments.
    --@return table|nil Text, source, and expected Context/turn fields.
    --@return table|nil DraftEmpty diagnostic.
    local function command_from_draft()
        if not staged then return nil, failure("DraftEmpty", "no chat draft is staged") end
        return {
            text = staged.text,
            source = staged.source,
            expected_context_generation = staged.context_generation,
            expected_turn_id = staged.turn_id,
        }
    end

    -- Clear staged text only after Runtime accepts an action.
    --@param result table|nil Runtime action receipt.
    --@param action_error table|nil Failure returned by Runtime.
    --@return table|nil Accepted action receipt.
    --@return table|nil Original action error when not accepted.
    local function consume_on_success(result, action_error)
        if not result then return nil, action_error end
        staged = nil
        return result
    end

    -- Resolve a visible queue number to its current durable queue-item ID.
    --@param display_id string Display ID such as #1.
    --@return string|nil Durable queue-item ID.
    --@return table|nil Invalid or missing display-ID diagnostic.
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
    --@param self table Saved Agent session facade.
    --@param text_value string User input to stage.
    --@param source string|nil Input source; defaults to user.
    --@return table|nil Read-only staged draft.
    --@return table|nil Closed-session or invalid-text error.
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
    --@param self table Saved Agent session facade.
    --@return table|boolean Read-only staged draft, or false when empty.
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
    --@param self table Saved Agent session facade.
    --@return table|nil Runtime receipt for the selected lane.
    --@return table|nil Closed, stale-draft, or Runtime action error.
    --@effect May submit, reply, supersede, or enqueue a durable Agent action.
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
    --@param self table Saved Agent session facade.
    --@return table|nil Queue admission receipt.
    --@return table|nil Closed, empty, or Runtime action error.
    --@effect May enqueue the staged text through AgentLoop.
    function session:queue()
        local open, open_error = require_open()
        if not open then return nil, open_error end
        local command, command_error = command_from_draft()
        if not command then return nil, command_error end
        local result, action_error = loop:enqueue(command)
        return consume_on_success(result, action_error)
    end

    ---Explicit same-turn steer for the staged draft.
    --@param self table Saved Agent session facade.
    --@return table|nil Steer receipt.
    --@return table|nil Closed, empty, or Runtime action error.
    --@effect May steer the active turn through AgentLoop.
    function session:steer()
        local open, open_error = require_open()
        if not open then return nil, open_error end
        local command, command_error = command_from_draft()
        if not command then return nil, command_error end
        local result, action_error = loop:steer(command)
        return consume_on_success(result, action_error)
    end

    ---Explicit single-concurrency ask request for the staged draft.
    --@param self table Saved Agent session facade.
    --@return table|nil Ask request receipt.
    --@return table|nil Closed, empty, or Runtime action error.
    --@effect May start the pure ask lane through AgentLoop.
    function session:ask()
        local open, open_error = require_open()
        if not open then return nil, open_error end
        local command, command_error = command_from_draft()
        if not command then return nil, command_error end
        local result, action_error = loop:start_ask(command)
        return consume_on_success(result, action_error)
    end

    ---Continues the exact yielded response in a new turn using the staged text.
    --@param self table Saved Agent session facade.
    --@param response_id string Exact yielded response to continue.
    --@return table|nil Continue receipt.
    --@return table|nil Closed, empty, stale, or Runtime action error.
    --@effect May resolve a yielded Model response through AgentLoop.
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

    -- List the current durable queue projection.
    --@param self table Saved Agent session facade.
    --@return table|nil Queue projection.
    --@return table|nil SessionClosed diagnostic.
    function session:queue_list()
        local open, open_error = require_open()
        if not open then return nil, open_error end
        return loop:list_queue()
    end

    -- Drop a displayed queue item against the current Context observation.
    --@param self table Saved Agent session facade.
    --@param display_id string Visible queue ID.
    --@param reason string|nil Drop reason; defaults to user-drop.
    --@return table|nil Queue mutation receipt.
    --@return table|nil Closed, missing-item, or Runtime error.
    --@effect Publishes a queue drop through AgentLoop.
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

    -- Replace a displayed queue item's text under the draft byte limit.
    --@param self table Saved Agent session facade.
    --@param display_id string Visible queue ID.
    --@param text_value string New bounded queue text.
    --@return table|nil Queue mutation receipt.
    --@return table|nil Invalid text, missing item, or Runtime error.
    --@effect Publishes a queue edit through AgentLoop.
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

    -- Reorder a displayed queue item before another item or to the end.
    --@param self table Saved Agent session facade.
    --@param display_id string Item to move.
    --@param before_display_id string|boolean Destination item or false for end.
    --@return table|nil Queue mutation receipt.
    --@return table|nil Missing item or Runtime error.
    --@effect Publishes a queue reorder through AgentLoop.
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

    -- Clear queued items against the current Context observation.
    --@param self table Saved Agent session facade.
    --@param reason string|nil Clear reason; defaults to user-clear.
    --@return table|nil Queue mutation receipt.
    --@return table|nil Closed-session or Runtime error.
    --@effect Publishes a queue clear through AgentLoop.
    function session:queue_clear(reason)
        local open, open_error = require_open()
        if not open then return nil, open_error end
        local observed = current_observation()
        observed.reason = reason or "user-clear"
        return loop:clear_queue(observed)
    end

    -- Insert an ask result into the requested main or queue lane explicitly.
    --@param self table Saved Agent session facade.
    --@param ask_id string Completed ask result ID.
    --@param lane string Requested use lane.
    --@return table|nil AgentLoop use-ask receipt.
    --@return table|nil Closed-session or Runtime error.
    --@effect May publish a durable ask-use fact.
    function session:use_ask(ask_id, lane)
        local open, open_error = require_open()
        if not open then return nil, open_error end
        local observed = current_observation()
        observed.ask_id = ask_id
        observed.lane = lane
        return loop:use_ask(observed)
    end

    -- Discard staged text without touching durable Context state.
    --@param self table Saved Agent session facade.
    --@return boolean True when a staged draft existed.
    function session:clear_draft()
        local existed = staged ~= nil
        staged = nil
        return existed
    end

    -- Snapshot saved-session lifecycle, staged text, and AgentLoop status.
    --@param self table Saved Agent session facade.
    --@return table Read-only status projection.
    function session:status()
        return readonly({
            lifecycle = lifecycle,
            has_draft = staged ~= nil,
            draft = self:draft(),
            loop = loop:status(),
        }, "saved Agent session status")
    end

    -- Close AgentLoop and discard staged text after its close is acknowledged.
    --@param self table Saved Agent session facade.
    --@param reason string|nil Close reason; defaults to session-close.
    --@return boolean|nil True after close, false if already closed.
    --@return table|nil AgentLoop close error.
    --@effect Closes the Runtime owner and clears in-memory staged text.
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
