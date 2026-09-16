--[[
File: context_publication_test.lua
Date: 2026-08-30
Author: WaterRun
Description: Verifies first-message durable Context publication and fail-closed retries.
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
local compact = load_module("compact", cache)
local context = load_module("context", cache)
local path = load_module("path", cache)
local prompt = load_module("prompt", cache)
local safety = load_module("safety", cache)
local session = load_module("session", cache)
local tools = load_module("tools", cache)
local xml = load_module("xml", cache)
local fake_lxp = load_table("test/support/fake_lxp.lua")
local sha256 = load_table("test/support/sha256_reference.lua")

local function hash_port()
    local port = {}

    function port.sha256_start()
        return { parts = {}, closed = false }
    end

    function port.sha256_update(handle, bytes)
        A.falsy(handle.closed)
        handle.parts[#handle.parts + 1] = bytes
        return true
    end

    function port.sha256_finish(handle)
        A.falsy(handle.closed)
        handle.closed = true
        return sha256.digest(table.concat(handle.parts))
    end

    function port.sha256_close(handle)
        handle.closed = true
        return true
    end

    return port
end

local function generation()
    return {
        id = "config-generation-7",
        schema_version = "0.1.0",
        agent_ready = true,
        current_model = "Primary",
        current_permission = "Std",
        default_model = "Primary",
        default_permission = "Std",
        effective_double_check = true,
        effective_double_check_goal = "verify the durable result",
        context_prompt = "workspace context",
        auto_rename_disabled = false,
        general = { system_prompt = "global instructions", startup_self_test = "off" },
        tui = { color = true },
        agent = { double_check = true, queue_max_items = 9 },
        network = { retry_count = 2 },
        exec = { timeout_ms = 1000 },
        context = { recent = 8 },
        permissions = {
            Std = {
                system_prompt = "permission instructions",
                read = "allow",
                write = "confirm",
            },
        },
        permission_order = { "Std" },
        models = {
            Primary = {
                enabled = true,
                tools_enabled = true,
                system_prompt = "model instructions",
                endpoint = "https://api.example/v1/chat",
                remote_model = "remote-main",
            },
        },
        model_order = { "Primary" },
        warnings = {},
        scan_registered_secrets = function(bytes)
            if bytes:find("registered-secret", 1, true) then
                return { { id = "Model.Primary.Key" } }
            end
            return {}
        end,
    }
end

local function fixture(settings)
    settings = settings or {}
    local native = hash_port()
    local safety_service = assert(safety.new(native, {
        maximum_hash_chunk_bytes = 97,
        minimum_scannable_secret_bytes = 8,
    }))
    local codec = assert(xml.new({
        lxp = fake_lxp(function()
            return false, "publication reader is not configured", 1, 1, 1
        end),
        maximum_bytes = 1024 * 1024,
        maximum_depth = 32,
        maximum_elements = 4096,
        maximum_attributes_per_element = 8,
        maximum_text_node_bytes = 131072,
        maximum_total_text_bytes = 512 * 1024,
        maximum_sax_events = 16384,
        maximum_context_events = 256,
        maximum_carrier_bytes = 65536,
        maximum_chunk_bytes = 97,
    }))
    local schema = assert(context.new({
        xml = codec,
        safety = safety_service,
        maximum_name_bytes = 256,
        maximum_identifier_bytes = 256,
        maximum_field_name_bytes = 64,
        maximum_field_bytes = 65536,
        maximum_events = 256,
        maximum_compaction_records = 64,
        maximum_export_bytes = 1024 * 1024,
    }))
    local path_service = assert(path.new(native, {
        maximum_path_bytes = 4096,
        maximum_segments = 128,
        maximum_segment_bytes = 255,
        maximum_hash_chunk_bytes = 97,
    }))
    local prompt_service = assert(prompt.new({ digest = safety_service.digest }, {
        maximum_component_bytes = 32768,
        maximum_quoted_bytes = 16384,
        maximum_total_bytes = 262144,
        maximum_estimated_tokens = 262144,
        maximum_components = 16,
        maximum_source_bytes = 256,
        maximum_version_bytes = 256,
    }))
    local registry = assert(tools.registry_snapshot(safety_service))
    local directories = { [settings.initial_root or "/release"] = true }
    for _, target in ipairs(settings.workspace_roots or {}) do directories[target] = true end
    local observations = {
        creates = {},
        flushes = {},
        random_calls = 0,
        writers = {},
        closes = 0,
    }
    local filesystem = {}

    local function direct_snapshot(target)
        local canonical = settings.alias_path == target and target .. "-redirected" or target
        local exists = directories[target] == true
        return {
            requested_path = target,
            canonical_path = canonical,
            exists = exists,
            identity = exists and { kind = "directory", volume = "disk", object = target } or false,
            parent_identity = { kind = "directory" },
            metadata = exists and { link_target = false } or false,
            ancestors = { { path = settings.initial_root or "/release", identity = {
                kind = "directory",
            } } },
            ancestry_complete = true,
        }
    end

    function filesystem.direct_inspect(target)
        return true, direct_snapshot(target)
    end

    function filesystem.direct_reverify(snapshot)
        if settings.changed_root == snapshot.requested_path then
            return false, { code = "TargetChanged" }
        end
        return true, direct_snapshot(snapshot.requested_path)
    end

    function filesystem.stat_identity(target)
        if directories[target] then return true, { kind = "directory" } end
        return false, { code = "NotFound", message = "absent" }
    end

    function filesystem.make_directory(target, permissions)
        A.equal(permissions, 448)
        if directories[target] then
            return false, { code = "DestinationExists", message = "exists" }
        end
        directories[target] = true
        observations.creates[#observations.creates + 1] = target
        return true
    end

    function filesystem.flush_directory(target)
        observations.flushes[#observations.flushes + 1] = target
        return true
    end

    local store = {}
    function store.plan_repair(target, credential)
        observations.repair_plans = (observations.repair_plans or 0) + 1
        A.equal(target, credential.physical_path)
        if settings.repair_error then return nil, settings.repair_error end
        local document = settings.open_document
        return { action = settings.repair_action or "restore-previous", path = target,
            source_path = target .. ".yaca-prev", previous_path = target .. ".yaca-prev",
            official_exists = credential.observed_stat ~= nil, generation = document.generation }, document
    end
    function store.apply_repair(plan, document, temporary, metadata)
        observations.applied_repair = plan
        if settings.apply_repair_error then return nil, settings.apply_repair_error end
        if plan.action == "no-repair-needed" then return { outcome = "unchanged", generation = plan.generation } end
        observations.closes = observations.closes + 1
        observations.published = { document = document, temporary_path = temporary, metadata = metadata }
        return { outcome = "restored-previous", generation = document.generation }
    end
    function store.inspect_import(target, credential)
        observations.import_reads = (observations.import_reads or 0) + 1
        A.equal(target, credential.physical_path)
        if settings.import_error then return nil, settings.import_error end
        return settings.import_document or settings.open_document,
            { outcome = "validated-readonly", history_approvals = "audit-only", auto_replay = false }
    end
    function store.create_writer(target, metadata)
        observations.create_attempts = (observations.create_attempts or 0) + 1
        if observations.create_attempts <= (settings.create_collisions or 0) then
            return nil, { code = "LockConflict", message = "collided" }
        end
        local writer = { target = target, metadata = metadata }
        observations.writers[#observations.writers + 1] = writer
        return writer
    end

    function store.open_writer(target, metadata, expected_credential)
        observations.opened = {
            target = target,
            metadata = metadata,
            expected_credential = expected_credential,
        }
        if settings.open_error then return nil, settings.open_error end
        if settings.change_root_on_open then settings.changed_root = settings.change_root_on_open end
        local document = settings.open_document
            or (settings.shared_store and settings.shared_store.document)
        if not document then
            return nil, { code = "NotFound", message = "fixture has no saved Context" }
        end
        local writer = { target = target, metadata = metadata, opened = true }
        observations.writers[#observations.writers + 1] = writer
        return writer, document
    end

    function store.publish(writer, document, temporary_path)
        if settings.publish_exception then error("synthetic storage failure") end
        observations.published = {
            writer = writer,
            document = document,
            temporary_path = temporary_path,
        }
        if settings.publish_error then return nil, settings.publish_error end
        writer.document = document
        if settings.shared_store then settings.shared_store.document = document end
        return {
            outcome = "published",
            generation = document.generation,
            event_count = document.event_count,
        }
    end

    function store.move(writer, document, destination, temporary_path, action)
        observations.moved = { destination = destination, action = action, temporary_path = temporary_path }
        if settings.move_error then return nil, settings.move_error end
        if settings.change_root_on_move then settings.changed_root = settings.change_root_on_move end
        writer.target = destination
        return store.publish(writer, document, temporary_path)
    end

    function store.open_delete_writer(target, metadata, credential)
        observations.delete_opened = { target = target, credential = credential }
        if settings.open_error then return nil, settings.open_error end
        return { target = target, metadata = metadata }
    end

    function store.delete(writer)
        observations.deleted = writer.target
        return { outcome = settings.partial_delete and "partial" or "deleted", targets = {} }
    end

    function store.verify_writer(writer)
        if settings.inspect_error then return nil, settings.inspect_error end
        local document = writer.document or settings.open_document
            or (settings.shared_store and settings.shared_store.document)
        return { path = writer.target, generation = document.generation }
    end

    function store.close_writer(writer)
        observations.closes = observations.closes + 1
        observations.last_closed = writer
        if settings.close_error then return nil, settings.close_error end
        return true
    end

    local random_values = settings.random_values or {
        string.char(0x0A, 0x1B) .. "12345678",
    }
    local system = {}
    function system.secure_random(length)
        observations.random_calls = observations.random_calls + 1
        local value = random_values[observations.random_calls] or string.rep("z", length)
        if not settings.random_values and length == 8 then value = value:sub(1, length) end
        A.equal(#value, length)
        return value
    end
    function system.current_process_id() return 1234 end
    function system.utc_now() return settings.now or "2026-08-30T12:34:56Z" end

    local publication = assert(session.new_context_publication({
        filesystem = filesystem,
        workspace = { inspect = function(target)
            if not directories[target] or settings.unenterable == target then
                return nil, { code = "InvalidWorkspace" }
            end
            return { path = target, enterable = true,
                identity = { kind = "directory", volume = "disk", object = target } }
        end },
        schema = schema,
        store = store,
        path = path_service,
        safety = safety_service,
        prompt = prompt_service,
        system = system,
        tool_registry = registry,
    }, {
        data_root = settings.data_root or "/release/__yaca__",
        platform_kind = settings.platform_kind or "posix",
        maximum_create_attempts = 4,
        maximum_model_view_bytes = 262144,
        maximum_compaction_source_bytes = 16 * 1024 * 1024,
        maximum_compaction_identifier_bytes = 256,
        default_model_request_limit = 64,
        default_tool_call_limit = 256,
        maximum_queue_items = 9,
    }))
    return publication, observations, path_service, registry, safety_service, schema
end

local function management_spec(receipt, document, action, extra)
    local value = {
        action = action, context_path = receipt.context_path, logical_path = receipt.logical_path,
        expected_credential = {
            physical_path = receipt.context_path, logical_path = receipt.logical_path,
            observed_stat = { kind = "file", object = "same-file", volume = "disk", size = 1024 },
            canonical_name = document.header.name, created_at = document.header.created_at,
            updated_at = document.header.updated_at, header_state = "valid",
        },
    }
    for key, item in pairs(extra or {}) do value[key] = item end
    return value
end

local function management_seed(pending)
    local publication, observed = fixture()
    local draft = assert(session.new_draft(generation(), {
        path = "/work", enterable = true,
    }, { maximum_draft_bytes = 16384 }, publication))
    local receipt = assert(draft.begin_main("preserve this history", "terminal"))
    local events = { { seq = 3, type = "turn_ended", turn_id = "turn-1", fields = { outcome = "completed" } } }
    if pending then
        events = {
            { seq = 3, type = "model_request", turn_id = "turn-1", fields = {
                requestId = "request-1", purpose = "main", viewManifestRef = receipt.view_manifest_snapshot,
            } },
            { seq = 4, type = "tool_call", turn_id = "turn-1", fields = {
                toolCallId = "tool-1", requestId = "request-1", name = "exec", canonicalArguments = "{}",
            } },
            { seq = 5, type = "approval", turn_id = "turn-1", fields = {
                approvalId = "approval-1", toolCallId = "tool-1", decision = "approved", snapshotDigest = "sha256:old-approval",
            } },
            { seq = 6, type = "operation_intent", turn_id = "turn-1", fields = {
                operationId = "operation-1", toolCallId = "tool-1", kind = "exec",
                targetIdentity = "old-workspace-object", expectedDigest = "sha256:old-target",
            } },
        }
    end
    assert(publication.commit({
        barrier_id = "finish-first", first_sequence = 3, last_sequence = 2 + #events, event_count = #events,
        expected_context_generation = 1,
        events = events,
    }))
    assert(draft.close())
    return receipt, observed.published.document
end

return {
    name = "integration/context-publication",
    cases = {
        {
            name = "active inspection derives the current hash and stale failure stays closed",
            run = function()
                local settings = {}
                local publication, observed, path_service = fixture(settings)
                local draft = assert(session.new_draft(generation(), {
                    path = "/work/项目", enterable = true, identity = { object = "workspace-1" },
                }, { maximum_draft_bytes = 16384 }, publication))
                local receipt = assert(draft.begin_main("inspect owned Context", "terminal"))
                local inspected = assert(publication.inspect_active())
                A.equal(inspected.context_path, receipt.context_path)
                A.equal(inspected.context_hash, assert(path_service.context_hash(receipt.logical_path)))
                local exported, export_receipt = assert(publication.export_active())
                A.contains(exported, "# yaca Context export v1")
                A.contains(exported, "inspect owned Context")
                A.equal(export_receipt.context_hash, inspected.context_hash)
                settings.inspect_error = { code = "TargetChanged", message = "changed" }
                local rejected, reject_error = publication.inspect_active()
                A.falsy(rejected)
                A.equal(reject_error.code, "ContextStale")
                A.falsy(publication.export_active())
                settings.inspect_error = nil
                rejected, reject_error = publication.turn_context({ expected_context_generation = 1 })
                A.falsy(rejected)
                A.equal(reject_error.code, "ContextStale")
                A.falsy(publication.inspect_active())
                A.truthy(publication.close())
                A.equal(observed.closes, 1)
            end,
        },
        {
            name = "first main message publishes generation one before becoming durable",
            run = function()
                local publication, observed, path_service, registry = fixture()
                local draft = assert(session.new_draft(generation(), {
                    path = "/work/项目",
                    enterable = true,
                    identity = { object = "workspace-1" },
                }, { maximum_draft_bytes = 16384 }, publication))
                A.truthy(draft.status().double_check_default)
                A.equal(draft.status().double_check_override, "inherit")
                local cautious_off = assert(draft.update({
                    double_check_override = false,
                }))
                A.falsy(cautious_off.double_check)
                A.falsy(cautious_off.double_check_override)
                local cautious_reset = assert(draft.update({
                    double_check_override = "inherit",
                }))
                A.truthy(cautious_reset.double_check)
                A.equal(cautious_reset.double_check_override, "inherit")
                assert(draft.update({
                    double_check = false,
                    double_check_goal = "check exact evidence",
                    context_prompt = "current session context",
                    auto_rename_disabled = true,
                }))
                local receipt = assert(draft.begin_main("实现首个持久化节点", "terminal"))
                local target = "/release/__yaca__/CONTEXT/work/项目/"
                    .. "Untitled Conversation [0A1B].xml"
                A.equal(receipt.context_path, target)
                A.equal(receipt.display_name, "Untitled Conversation [0A1B]")
                A.equal(receipt.generation, 1)
                A.equal(receipt.event_count, 2)
                A.equal(receipt.tool_registry_snapshot, registry.digest)
                A.equal(receipt.model_request_limit, 64)
                A.equal(receipt.tool_call_limit, 256)
                A.equal(receipt.queue_limit, 9)
                A.truthy(receipt.view_manifest_snapshot ~= receipt.prompt_snapshot)
                A.equal(
                    receipt.context_hash,
                    assert(path_service.context_hash(
                        "/work/项目/Untitled Conversation [0A1B].xml"
                    ))
                )
                A.deep_equal(observed.creates, {
                    "/release/__yaca__",
                    "/release/__yaca__/CONTEXT",
                    "/release/__yaca__/CONTEXT/work",
                    "/release/__yaca__/CONTEXT/work/项目",
                })
                A.deep_equal(observed.flushes, {
                    "/release",
                    "/release/__yaca__",
                    "/release/__yaca__/CONTEXT",
                    "/release/__yaca__/CONTEXT/work",
                })
                A.equal(observed.published.writer.metadata.pid, 1234)
                A.equal(observed.published.writer.metadata.started_at, "2026-08-30T12:34:56Z")
                A.equal(
                    observed.published.temporary_path,
                    target .. ".yaca-tmp-3132333435363738"
                )
                local document = observed.published.document
                A.equal(document.generation, 1)
                A.equal(document.header.name, receipt.display_name)
                A.truthy(document.header.auto_rename_disabled)
                A.equal(document.session.double_check_override, false)
                A.equal(document.session.double_check_goal_override.mode, "value")
                A.equal(document.session.double_check_goal_override.value, "check exact evidence")
                A.equal(document.session.context_prompt, "current session context")
                A.equal(document.facts[1].type, "turn_started")
                A.equal(document.facts[1].fields.promptSnapshot, receipt.prompt_snapshot)
                A.equal(document.facts[2].type, "user_message")
                A.equal(document.facts[2].fields.text, "实现首个持久化节点")
                A.equal(document.facts[2].fields.source, "terminal")
                A.equal(draft.status().lifecycle, "saved")
                A.truthy(draft.status().durable)
                local initial_view = assert(publication.prepare_view({
                    expected_context_generation = 1,
                    expected_last_sequence = 2,
                    current_manifest_ref = receipt.view_manifest_snapshot,
                }))
                A.falsy(initial_view.changed)
                A.equal(initial_view.digest, receipt.view_manifest_snapshot)
                A.equal(initial_view.last_sequence, 2)
                local resolved_initial = assert(publication.resolve_view(initial_view.digest))
                A.contains(resolved_initial.body, "<DurableFacts")
                A.contains(resolved_initial.body, "实现首个持久化节点")
                local batch = {
                    barrier_id = "turn-1:barrier:1",
                    first_sequence = 3,
                    last_sequence = 3,
                    event_count = 1,
                    expected_context_generation = 1,
                    events = { {
                        seq = 3,
                        type = "model_request",
                        turn_id = "turn-1",
                        fields = {
                            requestId = "turn-1:request:1",
                            purpose = "main",
                            viewManifestRef = receipt.view_manifest_snapshot,
                        },
                    } },
                }
                local committed, journal_receipt = publication.commit(batch)
                A.truthy(committed)
                A.equal(journal_receipt.binding, batch)
                A.equal(journal_receipt.previous_context_generation, 1)
                A.equal(journal_receipt.context_generation, 2)
                A.equal(publication.status().generation, 2)
                A.equal(publication.status().event_count, 3)
                A.equal(observed.published.document.header.updated_at, "2026-08-30T12:34:57Z")
                A.equal(observed.published.document.facts[3].type, "model_request")
                local next_observation = {
                    expected_context_generation = 2,
                    expected_last_sequence = 3,
                    current_manifest_ref = receipt.view_manifest_snapshot,
                }
                local next_view = assert(publication.prepare_view(next_observation))
                A.truthy(next_view.changed)
                A.equal(next_view.binding, next_observation)
                A.equal(next_view.first_sequence, 1)
                A.equal(next_view.last_sequence, 3)
                local unresolved, unresolved_error = publication.resolve_view(next_view.digest)
                A.falsy(unresolved)
                A.equal(unresolved_error.code, "StaleModelView")
                local view_batch = {
                    barrier_id = "turn-1:barrier:2",
                    first_sequence = 4,
                    last_sequence = 4,
                    event_count = 1,
                    expected_context_generation = 2,
                    events = { {
                        seq = 4,
                        type = "model_view_published",
                        turn_id = "turn-1",
                        fields = {
                            manifestDigest = next_view.digest,
                            firstEventSeq = tostring(next_view.first_sequence),
                            lastEventSeq = tostring(next_view.last_sequence),
                            replacesManifestDigest = next_view.replaces_manifest_ref,
                        },
                    } },
                }
                A.truthy(publication.commit(view_batch))
                A.equal(publication.status().generation, 3)
                A.equal(publication.status().event_count, 4)
                local resolved_next = assert(publication.resolve_view(next_view.digest))
                A.equal(resolved_next.digest, next_view.digest)
                A.contains(resolved_next.body, "model_request")
                A.equal(observed.published.document.model_view.active_manifest.digest, next_view.digest)
                A.equal(observed.published.document.facts[4].type, "model_view_published")
                local turn_context = assert(publication.turn_context({
                    expected_context_generation = 3,
                }))
                A.equal(turn_context.context_generation, 3)
                A.equal(turn_context.overrides.CurrentModel, "Primary")
                A.equal(turn_context.overrides.CurrentPermission, "Std")
                A.equal(turn_context.overrides.DoubleCheckOverride, false)
                A.equal(
                    turn_context.overrides.DoubleCheckGoalOverride,
                    "check exact evidence"
                )
                A.equal(turn_context.overrides.ContextPrompt, "current session context")
                A.truthy(turn_context.overrides.AutoRenameDisabled)
                A.raises(function()
                    turn_context.overrides.CurrentModel = "forged"
                end, "cannot be modified")

                local next_generation = generation()
                next_generation.id = "config-generation-8"
                next_generation.effective_double_check = false
                next_generation.effective_double_check_goal = "check exact evidence"
                next_generation.context_prompt = "current session context"
                next_generation.auto_rename_disabled = true
                local turn_snapshot = assert(publication.capture_turn({
                    generation = next_generation,
                    text = "继续实现第二个节点",
                    source = "terminal",
                    expected_context_generation = 3,
                }))
                A.equal(turn_snapshot.text, "继续实现第二个节点")
                A.equal(turn_snapshot.source, "terminal")
                A.equal(turn_snapshot.context_generation, 3)
                A.equal(turn_snapshot.view_manifest_ref, next_view.digest)
                A.equal(turn_snapshot.tool_registry_snapshot, registry.digest)
                A.falsy(turn_snapshot.double_check)
                A.equal(turn_snapshot.model_request_limit, 64)
                A.equal(turn_snapshot.tool_call_limit, 256)
                A.equal(turn_snapshot.queue_limit, 9)
                A.falsy(turn_snapshot.config_generation == next_generation.id)
                A.falsy(turn_snapshot.prompt_snapshot == receipt.prompt_snapshot)
                local side_snapshot = assert(publication.capture_turn({
                    generation = next_generation,
                    kind = "side",
                    text = "继续实现第二个节点",
                    source = "terminal",
                    expected_context_generation = 3,
                }))
                A.falsy(side_snapshot.prompt_snapshot == turn_snapshot.prompt_snapshot)
                A.equal(side_snapshot.model_snapshot, turn_snapshot.model_snapshot)
                A.equal(side_snapshot.permission_snapshot, turn_snapshot.permission_snapshot)
                A.equal(side_snapshot.tool_registry_snapshot, turn_snapshot.tool_registry_snapshot)
                A.equal(side_snapshot.view_manifest_ref, turn_snapshot.view_manifest_ref)
                local stale, stale_error = publication.capture_turn({
                    generation = next_generation,
                    text = "stale",
                    source = "terminal",
                    expected_context_generation = 2,
                })
                A.falsy(stale)
                A.equal(stale_error.code, "InvalidTurnSnapshot")

                local side_answer = "SIDE-ONLY-ANSWER"
                local side_committed, side_commit_error = publication.commit({
                    barrier_id = "side-1:barrier:1",
                    first_sequence = 5,
                    last_sequence = 9,
                    event_count = 5,
                    expected_context_generation = 3,
                    events = {
                        {
                            seq = 5,
                            type = "turn_started",
                            turn_id = "side-1",
                            fields = {
                                kind = "side",
                                configGeneration = side_snapshot.config_generation,
                                modelSnapshot = side_snapshot.model_snapshot,
                                permissionSnapshot = side_snapshot.permission_snapshot,
                                promptSnapshot = side_snapshot.prompt_snapshot,
                                toolRegistrySnapshot = side_snapshot.tool_registry_snapshot,
                            },
                        },
                        {
                            seq = 6,
                            type = "user_message",
                            turn_id = "side-1",
                            fields = {
                                messageId = "side-1:message:1",
                                text = "private side question",
                                source = "terminal",
                            },
                        },
                        {
                            seq = 7,
                            type = "model_request",
                            turn_id = "side-1",
                            fields = {
                                requestId = "side-1:request:1",
                                purpose = "side",
                                viewManifestRef = next_view.digest,
                            },
                        },
                        {
                            seq = 8,
                            type = "model_message",
                            turn_id = "side-1",
                            fields = {
                                messageId = "side-1:message:2",
                                requestId = "side-1:request:1",
                                role = "assistant",
                                status = "complete",
                                body = side_answer,
                            },
                        },
                        {
                            seq = 9,
                            type = "turn_ended",
                            turn_id = "side-1",
                            fields = { outcome = "completed" },
                        },
                    },
                })
                A.truthy(side_committed, A.render(side_commit_error))
                local hidden_side_view = assert(publication.prepare_view({
                    expected_context_generation = 4,
                    expected_last_sequence = 9,
                    current_manifest_ref = next_view.digest,
                }))
                A.truthy(publication.commit({
                    barrier_id = "turn-1:barrier:3",
                    first_sequence = 10,
                    last_sequence = 10,
                    event_count = 1,
                    expected_context_generation = 4,
                    events = { {
                        seq = 10,
                        type = "model_view_published",
                        turn_id = "turn-1",
                        fields = {
                            manifestDigest = hidden_side_view.digest,
                            firstEventSeq = tostring(hidden_side_view.first_sequence),
                            lastEventSeq = tostring(hidden_side_view.last_sequence),
                            replacesManifestDigest = hidden_side_view.replaces_manifest_ref,
                        },
                    } },
                }))
                local hidden_body = assert(
                    publication.resolve_view(hidden_side_view.digest)
                ).body
                A.falsy(hidden_body:find("private side question", 1, true))
                A.falsy(hidden_body:find(side_answer, 1, true))
                A.falsy(hidden_body:find('turnId="side-1"', 1, true))

                A.truthy(publication.commit({
                    barrier_id = "queue:barrier:1",
                    first_sequence = 11,
                    last_sequence = 11,
                    event_count = 1,
                    expected_context_generation = 5,
                    events = { {
                        seq = 11,
                        type = "queue_item",
                        fields = {
                            queueItemId = "queue-1",
                            displayId = "#1",
                            action = "enqueue",
                            text = side_answer,
                            sideId = "side-1",
                        },
                    } },
                }))
                local authorized_side_view = assert(publication.prepare_view({
                    expected_context_generation = 6,
                    expected_last_sequence = 11,
                    current_manifest_ref = hidden_side_view.digest,
                }))
                A.truthy(publication.commit({
                    barrier_id = "turn-1:barrier:4",
                    first_sequence = 12,
                    last_sequence = 12,
                    event_count = 1,
                    expected_context_generation = 6,
                    events = { {
                        seq = 12,
                        type = "model_view_published",
                        turn_id = "turn-1",
                        fields = {
                            manifestDigest = authorized_side_view.digest,
                            firstEventSeq = tostring(authorized_side_view.first_sequence),
                            lastEventSeq = tostring(authorized_side_view.last_sequence),
                            replacesManifestDigest = authorized_side_view.replaces_manifest_ref,
                        },
                    } },
                }))
                local authorized_body = assert(
                    publication.resolve_view(authorized_side_view.digest)
                ).body
                A.contains(authorized_body, side_answer)
                A.contains(authorized_body, "queue_item")
                A.contains(authorized_body, "side-1")
                A.truthy(draft.close())
                A.equal(observed.closes, 1)
                A.equal(draft.status().lifecycle, "closed")
            end,
        },
        {
            name = "session override publishes Session audit view and exact Runtime receipt atomically",
            run = function()
                local publication, observed = fixture()
                local draft = assert(session.new_draft(generation(), {
                    path = "/work/project",
                    enterable = true,
                    identity = { object = "workspace-1" },
                }, { maximum_draft_bytes = 16384 }, publication))
                local first = assert(draft.begin_main("start durable work", "terminal"))
                local next_generation = generation()
                next_generation.id = "config-generation-8"
                next_generation.effective_double_check = false
                local record, receipt = publication.update_session({
                    expected_context_generation = first.generation,
                    expected_last_sequence = first.last_sequence,
                    expected_manifest_digest = first.view_manifest_snapshot,
                    generation = next_generation,
                    name = "DoubleCheckOverride",
                    value = false,
                })
                A.truthy(record)
                A.equal(record.kind, "session-override")
                A.equal(record.name, "DoubleCheckOverride")
                A.equal(record.effective_at, "next-turn")
                A.equal(record.replaces_manifest_digest, first.view_manifest_snapshot)
                A.falsy(record.manifest_digest == first.view_manifest_snapshot)
                A.equal(receipt.event_count, 2)
                A.equal(receipt.first_sequence, 3)
                A.equal(receipt.last_sequence, 4)
                A.equal(receipt.previous_context_generation, 1)
                A.equal(receipt.context_generation, 2)
                A.equal(receipt.binding.expected_context_generation, 1)
                A.equal(receipt.binding.events[1].type, "session_override")
                A.equal(receipt.binding.events[1].turn_id, false)
                A.equal(receipt.binding.events[2].type, "model_view_published")
                A.equal(
                    receipt.binding.events[2].fields.manifestDigest,
                    record.manifest_digest
                )
                A.equal(publication.status().generation, 2)
                A.equal(publication.status().event_count, 4)
                A.equal(
                    publication.status().view_manifest_snapshot,
                    record.manifest_digest
                )

                local document = observed.published.document
                A.falsy(document.session.double_check_override)
                A.equal(document.facts[3].type, "session_override")
                A.equal(document.facts[3].fields.name, "DoubleCheckOverride")
                A.equal(document.facts[3].fields.effectiveAt, "next-turn")
                A.equal(document.facts[4].type, "model_view_published")
                A.equal(
                    document.model_view.active_manifest.digest,
                    record.manifest_digest
                )
                local view = assert(publication.resolve_view(record.manifest_digest))
                A.contains(view.body, 'type="session_override"')
                A.contains(view.body, "oldValueDigest")
                A.contains(view.body, "newValueDigest")
                local turn_context = assert(publication.turn_context({
                    expected_context_generation = 2,
                }))
                A.falsy(turn_context.overrides.DoubleCheckOverride)
                local turn = assert(publication.capture_turn({
                    generation = next_generation,
                    text = "continue with next-turn settings",
                    source = "terminal",
                    expected_context_generation = 2,
                }))
                A.falsy(turn.double_check)
                A.equal(turn.view_manifest_ref, record.manifest_digest)

                local unchanged, unchanged_error = publication.update_session({
                    expected_context_generation = 2,
                    expected_last_sequence = 4,
                    expected_manifest_digest = record.manifest_digest,
                    generation = next_generation,
                    name = "DoubleCheckOverride",
                    value = false,
                })
                A.falsy(unchanged)
                A.equal(unchanged_error.code, "SessionOverrideUnchanged")
                A.equal(publication.status().generation, 2)

                local prompt_generation = generation()
                prompt_generation.id = "config-generation-9"
                prompt_generation.effective_double_check = false
                prompt_generation.context_prompt = "bounded project guidance"
                local prompt_record, prompt_receipt = publication.update_session({
                    expected_context_generation = 2,
                    expected_last_sequence = 4,
                    expected_manifest_digest = record.manifest_digest,
                    generation = prompt_generation,
                    name = "ContextPrompt",
                    value = "bounded project guidance",
                })
                A.truthy(prompt_record)
                A.equal(prompt_record.name, "ContextPrompt")
                A.equal(prompt_receipt.first_sequence, 5)
                A.equal(prompt_receipt.last_sequence, 6)
                A.equal(prompt_receipt.context_generation, 3)
                A.equal(publication.status().generation, 3)
                local prompt_document = observed.published.document
                A.equal(
                    prompt_document.session.context_prompt,
                    "bounded project guidance"
                )
                A.equal(prompt_document.facts[5].fields.name, "ContextPrompt")
                local prompt_context = assert(publication.turn_context({
                    expected_context_generation = 3,
                }))
                A.equal(
                    prompt_context.overrides.ContextPrompt,
                    "bounded project guidance"
                )
                local prompt_turn = assert(publication.capture_turn({
                    generation = prompt_generation,
                    text = "use the durable project guidance",
                    source = "terminal",
                    expected_context_generation = 3,
                }))
                A.falsy(prompt_turn.prompt_snapshot == turn.prompt_snapshot)
                A.equal(
                    prompt_turn.view_manifest_ref,
                    prompt_record.manifest_digest
                )

                local secret_generation = generation()
                secret_generation.id = "config-generation-10"
                secret_generation.effective_double_check = false
                secret_generation.context_prompt = "registered-secret"
                local secret, secret_error = publication.update_session({
                    expected_context_generation = 3,
                    expected_last_sequence = 6,
                    expected_manifest_digest = prompt_record.manifest_digest,
                    generation = secret_generation,
                    name = "ContextPrompt",
                    value = "registered-secret",
                })
                A.falsy(secret)
                A.equal(secret_error.code, "RegisteredSecret")
                A.equal(publication.status().generation, 3)
                A.equal(observed.published.document, prompt_document)
                A.truthy(draft.close())
            end,
        },
        {
            name = "repair keeps previous-only targets read-only until a reconstructable audited publication",
            run = function()
                local first, document = management_seed()
                local manager, observed = fixture({ open_document = document })
                local request = management_spec(first, document, "repair")
                local credential = request.expected_credential
                credential.recovery_stat, credential.observed_stat = credential.observed_stat, nil
                credential.canonical_name, credential.created_at, credential.updated_at = nil, nil, nil
                credential.header_state = "unavailable"
                local proposal = assert(manager.plan_repair(request))
                A.equal(proposal.action, "restore-previous")
                A.equal(#observed.writers, 0)
                A.falsy(observed.published)
                request.repair_plan = proposal
                local receipt = assert(manager.manage_context(request))
                A.equal(receipt.context_hash, first.context_hash)
                A.equal(receipt.generation, document.generation + 1)
                local repaired = observed.published.document
                A.equal(repaired.facts[4].type, "warning")
                A.equal(repaired.facts[4].fields.errorId, "PreviousValidRestored")
                A.equal(repaired.header.created_at, document.header.created_at)
                local reopened = fixture({ open_document = repaired })
                local open_request = management_spec(receipt, repaired, "repair")
                open_request.action = nil
                local opened = assert(reopened.open_existing(open_request))
                A.contains(assert(reopened.resolve_view(opened.view_manifest_snapshot)).body, "preserve this history")
                assert(reopened.close())
                local repeated, repeated_error = manager.manage_context(request)
                A.falsy(repeated)
                A.equal(repeated_error.code, "InvalidRepairPlan")
            end,
        },
        {
            name = "repair no-op leaves the generation intact and uncertain repair stops further mutation",
            run = function()
                local first, document = management_seed()
                for _, noop in ipairs({ true, false }) do
                    local manager, observed = fixture({ open_document = document,
                        repair_action = noop and "no-repair-needed" or nil,
                        apply_repair_error = not noop and { code = "ContextRepairUnknown" } or nil })
                    local request = management_spec(first, document, "repair")
                    request.repair_plan = assert(manager.plan_repair(request))
                    local receipt, err = manager.manage_context(request)
                    if noop then
                        A.truthy(receipt, A.render(err))
                        A.equal(receipt.outcome, "unchanged")
                        A.equal(receipt.generation, document.generation)
                    else
                        A.falsy(receipt)
                        A.equal(err.code, "ContextMutationUnknown")
                        local later, later_error = manager.manage_context(management_spec(first, document,
                            "rename", { new_name = "Later" }))
                        A.falsy(later)
                        A.equal(later_error.code, "ContextMutationUnknown")
                    end
                    A.falsy(observed.published)
                    A.equal(observed.closes, 0)
                end
            end,
        },
        {
            name = "import preserves historical approvals and unresolved work without granting or replaying it",
            run = function()
                local first, document = management_seed(true)
                local importer, observed = fixture({ open_document = document, workspace_roots = { "/work" } })
                local request = management_spec(first, document, "import", { generation = generation() })
                local proposal = assert(importer.plan_import(request))
                A.equal(proposal.unresolved_operations, 1)
                A.equal(proposal.unresolved_tools, 1)
                A.equal(proposal.history_approvals, "audit-only")
                A.falsy(proposal.auto_continue)
                request.import_plan = proposal
                local receipt = assert(importer.manage_context(request))
                local mapped = observed.published.document
                A.equal(mapped.facts[5].type, "approval")
                A.equal(mapped.facts[5].fields.snapshotDigest, "sha256:old-approval")
                A.deep_equal(mapped.recovery.unresolved_operation_ids, { "operation-1" })
                A.deep_equal(mapped.recovery.unresolved_tool_call_ids, { "tool-1" })
                local reopened = fixture({ open_document = mapped })
                local open_request = management_spec(receipt, mapped, "import")
                open_request.action = nil
                local opened = assert(reopened.open_existing(open_request))
                A.falsy(opened.auto_continue)
                A.equal(opened.approval_initial_serial, 1)
                assert(reopened.close())
            end,
        },
        {
            name = "in-place import applies both local mappings in one durable generation and rebuilds history",
            run = function()
                local first, document = management_seed()
                local settings = { open_document = document, workspace_roots = { "/work" } }
                local manager, observed = fixture(settings)
                local local_generation = generation()
                local_generation.models.Local = local_generation.models.Primary
                local_generation.permissions.LocalStd = local_generation.permissions.Std
                local_generation.current_model = "Local"
                local_generation.current_permission = "LocalStd"
                local request = management_spec(first, document, "import", { generation = local_generation })
                local proposal, plan_error = manager.plan_import(request)
                A.truthy(proposal, A.render(plan_error))
                A.equal(observed.import_reads, 1)
                A.equal(#observed.writers, 0)
                A.equal(#observed.creates, 0)
                A.falsy(observed.published)
                A.equal(proposal.previous_model, "Primary")
                A.equal(proposal.model, "Local")
                A.equal(proposal.permission, "LocalStd")
                A.equal(proposal.workspace, "/work")
                A.falsy(proposal.auto_replay)
                request.import_plan = proposal
                settings.now = "2026-09-01T00:00:00Z"
                local receipt, import_error = manager.manage_context(request)
                A.truthy(receipt, A.render(import_error))
                A.equal(receipt.generation, document.generation + 1)
                A.equal(receipt.context_hash, first.context_hash)
                A.equal(receipt.context_path, first.context_path)
                A.equal(receipt.model, "Local")
                A.equal(receipt.permission, "LocalStd")
                A.falsy(receipt.auto_replay)
                A.equal(observed.closes, 1)
                local mapped = observed.published.document
                A.equal(mapped.header.created_at, document.header.created_at)
                A.equal(mapped.header.updated_at, settings.now)
                A.equal(mapped.session.current_model.name, "Local")
                A.equal(mapped.session.current_permission.name, "LocalStd")
                A.truthy(mapped.session.current_model.snapshot_digest ~= document.session.current_model.snapshot_digest)
                A.equal(mapped.facts[4].type, "import_mapping")
                A.contains(mapped.facts[4].fields.modelMappings, "Primary [")
                A.contains(mapped.facts[4].fields.modelMappings, " -> Local [")
                A.equal(mapped.facts[3].fields.outcome, "completed")
                local reopened = fixture({ open_document = mapped })
                local open_request = management_spec(receipt, mapped, "import")
                open_request.action = nil
                local opened = assert(reopened.open_existing(open_request))
                local view = assert(reopened.resolve_view(opened.view_manifest_snapshot))
                A.contains(view.body, "preserve this history")
                A.contains(view.body, "LocalStd")
                assert(reopened.close())
                local repeated, repeated_error = manager.manage_context(request)
                A.falsy(repeated)
                A.equal(repeated_error.code, "InvalidContextMutation")
            end,
        },
        {
            name = "import mapping refuses missing workspace invalid profiles changed config and changed source",
            run = function()
                local first, document = management_seed()
                for _, stage in ipairs({ "workspace", "model", "permission", "overrides", "busy-read",
                    "config", "source", "root", "publish", "unknown" }) do
                    local settings = { open_document = document, workspace_roots = { "/work" } }
                    if stage == "workspace" then settings.workspace_roots = {} end
                    if stage == "busy-read" then settings.import_error = { code = "LockConflict" } end
                    local manager, observed, _, _, _, schema = fixture(settings)
                    local local_generation = generation()
                    if stage == "model" then local_generation.models.Primary.enabled = false end
                    if stage == "permission" then local_generation.permissions.Std = nil end
                    if stage == "overrides" then local_generation.context_prompt = "replacement" end
                    local request = management_spec(first, document, "import", { generation = local_generation })
                    local proposal, err = manager.plan_import(request)
                    local early = { workspace = "WorkspaceMappingRequired", model = "ModelUnavailable",
                        permission = "PermissionUnavailable", overrides = "ConfigGenerationMismatch", ["busy-read"] = "LockConflict" }
                    if early[stage] then
                        A.falsy(proposal)
                        A.equal(err.code, early[stage])
                        A.equal(#observed.writers, 0)
                    else
                        A.truthy(proposal, A.render(err))
                        request.import_plan = proposal
                        if stage == "config" then request.generation = generation()
                        elseif stage == "root" then settings.changed_root = "/work"
                        elseif stage == "source" then
                            settings.open_document = assert(schema.lifecycle_document(document, {
                                kind = "repair", updated_at = "2026-09-01T00:00:00Z", error_id = "error-1",
                                summary = "changed source", view_manifest_digest = document.model_view.active_manifest.digest,
                            }))
                        elseif stage == "publish" then settings.publish_error = { code = "InjectedPublish" }
                        elseif stage == "unknown" then settings.publish_error = { code = "ContextPublishUnknown" } end
                        local result
                        result, err = manager.manage_context(request)
                        A.falsy(result)
                        local expected = { config = "ConfigGenerationChanged", root = "ContextWorkspaceChanged",
                            source = "ContextTargetChanged", publish = "InjectedPublish", unknown = "ContextMutationUnknown" }
                        A.equal(err.code, expected[stage])
                        A.equal(observed.closes, (stage == "config" or stage == "root") and 0 or 1)
                    end
                    A.equal(#observed.creates, 0)
                end
            end,
        },
        {
            name = "rebind plans are read-only and publish a reconstructable move with both root identities",
            run = function()
                local first, document = management_seed()
                local manager, observed = fixture({ open_document = document,
                    workspace_roots = { "/work", "/new-work" } })
                local request = management_spec(first, document, "rebind")
                request.target_root = "/new-work"
                local proposal = assert(manager.plan_rebind(request))
                A.equal(#observed.creates, 0)
                A.equal(#observed.writers, 0)
                A.falsy(observed.published)
                A.equal(proposal.target_logical_path, "/new-work/" .. document.header.name .. ".xml")
                A.truthy(proposal.old_root_identity ~= "unavailable")
                request.target_root = nil
                request.rebind_plan = proposal
                local moved = assert(manager.manage_context(request))
                A.equal(observed.moved.action, "rebind")
                A.equal(observed.closes, 1)
                A.equal(moved.context_hash, proposal.target_hash)
                A.truthy(moved.context_hash ~= first.context_hash)
                local changed = observed.published.document
                A.equal(changed.header.created_at, document.header.created_at)
                A.truthy(changed.header.updated_at > document.header.updated_at)
                A.equal(changed.header.name, document.header.name)
                A.equal(changed.header.auto_rename_disabled, document.header.auto_rename_disabled)
                A.equal(changed.facts[4].type, "rebind")
                A.equal(changed.facts[4].fields.oldRootIdentity, proposal.old_root_identity)
                A.equal(changed.facts[4].fields.newRootIdentity, proposal.new_root_identity)
                local reopened = fixture({ open_document = changed })
                local open_request = management_spec(moved, changed, "rebind")
                open_request.action = nil
                local opened = assert(reopened.open_existing(open_request))
                local view = assert(reopened.resolve_view(opened.view_manifest_snapshot))
                A.contains(view.body, "preserve this history")
                A.contains(view.body, "/new-work/")
                assert(reopened.close())
                local repeated, repeated_error = manager.manage_context(request)
                A.falsy(repeated)
                A.equal(repeated_error.code, "InvalidContextMutation")
                A.equal(observed.closes, 1)
            end,
        },
        {
            name = "rebind refuses stale roots before and during publication and closes failed writers",
            run = function()
                local first, document = management_seed()
                for _, stage in ipairs({ "before", "open", "move", "collision", "busy", "credential", "unknown" }) do
                    local settings = { open_document = document, workspace_roots = { "/new-work" } }
                    local manager, observed = fixture(settings)
                    local request = management_spec(first, document, "rebind")
                    request.target_root = "/new-work"
                    local proposal = assert(manager.plan_rebind(request))
                    A.equal(proposal.old_root_identity, "unavailable")
                    request.target_root = nil
                    request.rebind_plan = proposal
                    if stage == "before" then settings.changed_root = "/new-work"
                    elseif stage == "open" then settings.change_root_on_open = "/new-work"
                    elseif stage == "move" then settings.change_root_on_move = "/new-work"
                    elseif stage == "collision" then settings.move_error = { code = "DestinationExists" }
                    elseif stage == "busy" then settings.open_error = { code = "LockConflict" }
                    elseif stage == "unknown" then settings.open_error = { code = "ContextRecoveryUnknown" }
                    else request.expected_credential.observed_stat.object = "replacement" end
                    local result, err = manager.manage_context(request)
                    A.falsy(result)
                    local expected = { before = "ContextWorkspaceChanged", open = "ContextWorkspaceChanged",
                        move = "ContextMutationUnknown", collision = "DestinationExists",
                        busy = "LockConflict", credential = "InvalidContextMutation", unknown = "ContextMutationUnknown" }
                    A.equal(err.code, expected[stage])
                    A.equal(observed.closes, (stage == "before" or stage == "busy"
                        or stage == "credential" or stage == "unknown")
                        and 0 or 1)
                    if stage ~= "move" then A.falsy(observed.published) end
                    if stage == "move" or stage == "unknown" then
                        local next_result, next_error = manager.manage_context(
                            management_spec(first, document, "rename", { new_name = "Later" }))
                        A.falsy(next_result)
                        A.equal(next_error.code, "ContextMutationUnknown")
                    end
                end
            end,
        },
        {
            name = "rebind requires an existing enterable plain directory and the latest private proposal",
            run = function()
                local first, document = management_seed()
                for _, invalid in ipairs({ "missing", "unenterable", "alias", "same" }) do
                    local settings = { open_document = document, workspace_roots = { "/work", "/new-work" } }
                    if invalid == "unenterable" then settings.unenterable = "/new-work"
                    elseif invalid == "alias" then settings.alias_path = "/new-work" end
                    local manager, observed = fixture(settings)
                    local request = management_spec(first, document, "rebind", {
                        target_root = invalid == "same" and "/work"
                            or (invalid == "missing" and "/missing" or "/new-work"),
                    })
                    A.falsy(manager.plan_rebind(request))
                    A.equal(#observed.creates, 0)
                    A.equal(#observed.writers, 0)
                end
                local manager, observed = fixture({ open_document = document,
                    workspace_roots = { "/new-work" } })
                local request = management_spec(first, document, "rebind", { target_root = "/new-work" })
                local stale = assert(manager.plan_rebind(request))
                assert(manager.plan_rebind(request))
                request.target_root = nil
                request.rebind_plan = stale
                local result, err = manager.manage_context(request)
                A.falsy(result)
                A.equal(err.code, "InvalidContextMutation")
                request.rebind_plan = { target_root = "/new-work" }
                A.falsy(manager.manage_context(request))
                A.equal(#observed.writers, 0)
            end,
        },
        {
            name = "offline rename and naming switch publish reconstructable views and release every writer",
            run = function()
                local first, document = management_seed()
                local manager, observed = fixture({ open_document = document })
                local renamed = assert(manager.manage_context(management_spec(first, document, "rename", {
                    new_name = "Managed Context",
                })))
                A.equal(observed.closes, 1)
                A.equal(renamed.logical_path, "/work/Managed Context.xml")
                A.truthy(renamed.context_hash ~= first.context_hash)
                A.truthy(renamed.auto_rename_disabled)
                A.equal(observed.moved.action, "rename")
                local changed = observed.published.document
                A.equal(changed.facts[3].fields.outcome, "completed")
                A.equal(changed.facts[4].type, "rename")
                A.equal(changed.model_view.active_manifest.last_event_seq, 4)
                local switch, switched = fixture({ open_document = changed })
                local enabled = assert(switch.manage_context(management_spec(renamed, changed,
                    "set_auto_rename_disabled", { value = false })))
                A.equal(switched.closes, 1)
                A.falsy(enabled.auto_rename_disabled)
                local enabled_document = switched.published.document
                A.equal(enabled_document.header.naming_waterline, 1)
                A.equal(enabled_document.header.auto_name_baseline, 1)
                local reopened = fixture({ open_document = enabled_document })
                local specification = management_spec(enabled, enabled_document, "rename")
                specification.action = nil
                local opened = assert(reopened.open_existing(specification))
                A.truthy(opened.auto_continue)
                local view = assert(reopened.resolve_view(opened.view_manifest_snapshot))
                A.contains(view.body, "preserve this history")
                A.contains(view.body, "Managed Context")
                A.contains(view.body, "AutoRenameDisabled")
                A.equal(view.digest, enabled.view_manifest_snapshot)
                A.truthy(reopened.close())
            end,
        },
        {
            name = "offline management rejects stale bindings and known failures without changing the document",
            run = function()
                local first, document = management_seed()
                local manager, observed = fixture({ open_document = document })
                local unchanged = assert(manager.manage_context(management_spec(first, document,
                    "set_auto_rename_disabled", { value = false })))
                A.equal(unchanged.outcome, "unchanged")
                A.equal(observed.closes, 1)
                A.falsy(observed.published)
                local wrong = management_spec(first, document, "rename", { new_name = "Elsewhere" })
                wrong.context_path = "/outside/Task.xml"
                wrong.expected_credential.physical_path = wrong.context_path
                local rejected, reject_error = manager.manage_context(wrong)
                A.falsy(rejected)
                A.equal(reject_error.code, "InvalidContextMutation")
                A.equal(observed.closes, 1)
                for _, code in ipairs({ "DestinationExists", "TargetChanged", "LockConflict" }) do
                    local failed, failed_observed = fixture({ open_document = document,
                        move_error = { code = code, message = "known failure" } })
                    rejected, reject_error = failed.manage_context(management_spec(first, document,
                        "rename", { new_name = "Other" }))
                    A.falsy(rejected)
                    A.equal(reject_error.code, code)
                    A.equal(failed_observed.closes, 1)
                    A.falsy(failed_observed.published)
                end
            end,
        },
        {
            name = "management exceptions publication uncertainty and failed release stop subsequent mutation",
            run = function()
                local first, document = management_seed()
                for _, setting in ipairs({
                    { publish_exception = true },
                    { publish_error = { code = "ContextPublishUnknown" } },
                    { move_error = { code = "ContextCleanupRequired" } },
                    { close_error = { code = "LeaseUnknown" } },
                }) do
                    setting.open_document = document
                    local manager, observed = fixture(setting)
                    local request = management_spec(first, document, "rename", { new_name = "Changed" })
                    local result, err = manager.manage_context(request)
                    A.falsy(result)
                    A.equal(err.code, "ContextMutationUnknown")
                    A.equal(observed.closes, 1)
                    result, err = manager.manage_context(request)
                    A.falsy(result)
                    A.equal(err.code, "ContextMutationUnknown")
                    A.equal(observed.closes, 1)
                end
            end,
        },
        {
            name = "Windows management rejects device alternate-stream and ambiguous names before opening a writer",
            run = function()
                local _, document = management_seed()
                local manager, observed = fixture({ platform_kind = "windows",
                    data_root = "C:\\release\\__yaca__", initial_root = "C:\\release", open_document = document })
                local receipt = {
                    context_path = "C:\\release\\__yaca__\\CONTEXT\\C\\work\\Task.xml",
                    logical_path = "/C/work/Task.xml",
                }
                for _, name in ipairs({ "CON", "nul.txt", "COM1", "LPT9", "CONIN$",
                    "Task:stream", "Task?", "trailing.", "trailing " }) do
                    local result, err = manager.manage_context(management_spec(receipt, document,
                        "rename", { new_name = name }))
                    A.falsy(result)
                    A.equal(err.code, "InvalidContextName")
                end
                A.falsy(observed.opened)
                A.equal(observed.closes, 0)
            end,
        },
        {
            name = "corrupt deletion uses a body-free writer and partial results close management",
            run = function()
                local first, document = management_seed()
                for _, partial in ipairs({ false, true }) do
                    local manager, observed = fixture({ partial_delete = partial })
                    local request = management_spec(first, document, "delete")
                    request.expected_credential.header_state = "corrupt"
                    local deleted = assert(manager.manage_context(request))
                    A.equal(deleted.outcome, partial and "partial" or "deleted")
                    A.equal(observed.deleted, first.context_path)
                    A.falsy(observed.opened)
                    A.equal(observed.closes, 1)
                    if partial then
                        local again, err = manager.manage_context(request)
                        A.falsy(again)
                        A.equal(err.code, "ContextMutationUnknown")
                        A.equal(observed.closes, 1)
                    end
                end
            end,
        },
        {
            name = "compaction journal publishes summary and ModelView in one generation",
            run = function()
                local publication, observed, _, _, safety_service = fixture()
                local first = assert(publication.publish_first({
                    generation = generation(),
                    workspace = { path = "/work", enterable = true },
                    settings = {
                        model = "Primary",
                        permission = "Std",
                        double_check = true,
                        double_check_override = "inherit",
                        double_check_goal = "verify compaction",
                        double_check_goal_override = "inherit",
                        context_prompt = "workspace context",
                        auto_rename_disabled = false,
                    },
                    message = "compact this prefix",
                    source = "main",
                }))
                A.truthy(publication.commit({
                    barrier_id = "compaction-tail",
                    first_sequence = 3,
                    last_sequence = 3,
                    event_count = 1,
                    expected_context_generation = 1,
                    events = { {
                        seq = 3,
                        type = "warning",
                        fields = { errorId = "TailMarker", summary = "TAIL-KEEP" },
                    } },
                }))

                local source_document = observed.published.document
                local source_bytes = assert(compact.encode_source(
                    source_document,
                    1,
                    2,
                    256,
                    16 * 1024 * 1024
                ))
                local source_digest = assert(safety_service.digest(source_bytes))
                local config_snapshot = assert(safety_service.digest("config-snapshot"))
                local model_snapshot = assert(safety_service.digest("model-snapshot"))
                local prompt_snapshot = assert(safety_service.digest("prompt-snapshot"))
                local journal = publication.compaction_journal()
                local intent = {
                    kind = "compaction-request",
                    purpose = "compaction",
                    mode = "manual",
                    compaction_id = "compaction-1",
                    request_id = "compaction-1:request:1",
                    attempt = 1,
                    correction_reason = false,
                    expected_context_generation = 2,
                    expected_manifest_digest = first.view_manifest_snapshot,
                    source_first_seq = 1,
                    source_last_seq = 2,
                    source_digest = source_digest,
                    config_snapshot = config_snapshot,
                    model_snapshot_digest = model_snapshot,
                    prompt_bundle_digest = prompt_snapshot,
                    manifest_snapshot_id = "manifest-compaction-v1",
                }
                local intent_committed, intent_receipt = journal.commit_intent(intent)
                A.truthy(intent_committed, A.render(intent_receipt))
                A.equal(intent_receipt.binding, intent)
                A.equal(intent_receipt.context_generation, 3)
                A.equal(intent_receipt.active_manifest_digest, first.view_manifest_snapshot)
                local durable_request = observed.published.document.facts[4]
                A.equal(durable_request.type, "model_request")
                A.equal(durable_request.fields.compactionId, "compaction-1")
                A.equal(durable_request.fields.compactionMode, "manual")
                A.equal(durable_request.fields.sourceEventCount, "3")
                A.equal(durable_request.fields.configSnapshot, config_snapshot)
                A.equal(durable_request.fields.modelSnapshot, model_snapshot)
                A.equal(durable_request.fields.promptSnapshot, prompt_snapshot)
                A.equal(
                    observed.published.document.recovery.pending_compactions[1]
                        .request_id,
                    "compaction-1:request:1"
                )

                local summary = compact.encode_summary({
                    schema_version = "structured-summary-v1",
                    source_first_seq = 1,
                    source_last_seq = 2,
                    source_digest = source_digest,
                    goals_decisions = "GOALS-PRESERVED",
                    constraints_permissions = "permission facts preserved",
                    files_touched = "no files",
                    verification_evidence = "durable journal integration",
                    unknown_side_effects = "none",
                    open_todos = "continue from tail",
                    prompt_model_transitions = "same model snapshot",
                })
                local summary_digest = assert(safety_service.digest(summary))
                local usage = { input_tokens = 32, output_tokens = 16, estimated = true }
                local response = {
                    kind = "compaction-response",
                    compaction_id = "compaction-1",
                    request_id = "compaction-1:request:1",
                    attempt = 1,
                    canonical_body = summary,
                    canonical_digest = summary_digest,
                    source_first_seq = 1,
                    source_last_seq = 2,
                    source_digest = source_digest,
                    usage = usage,
                    expected_context_generation = 3,
                    expected_manifest_digest = first.view_manifest_snapshot,
                }
                local response_committed, response_receipt = journal.commit_response(response)
                A.truthy(response_committed, A.render(response_receipt))
                A.equal(response_receipt.context_generation, 4)
                A.equal(publication.status().event_count, 5)

                local manifest = {
                    schema_version = 1,
                    context_generation = 4,
                    context_digest = assert(safety_service.digest("context")),
                    model_id = "Primary",
                    model_snapshot_digest = model_snapshot,
                    window_tokens = 4096,
                    prompt_bundle_digest = prompt_snapshot,
                    summary_id = "compaction-1:summary",
                    summary_source_range = "1-2",
                    included_event_ranges = { { first = 3, last = 3 } },
                    excluded_prefix_reason = "summarized",
                    builder_algorithm = "structured-prefix-v1",
                    estimated_tokens = 128,
                    correction_ids = {},
                }
                local manifest_bytes = assert(compact.encode_manifest(
                    manifest,
                    256,
                    16 * 1024 * 1024
                ))
                local manifest_digest = assert(safety_service.digest(manifest_bytes))
                manifest.digest = manifest_digest
                manifest.canonical_bytes = manifest_bytes
                local publication_record = {
                    kind = "compaction-publication",
                    compaction_id = "compaction-1",
                    summary_id = "compaction-1:summary",
                    request_id = "compaction-1:request:1",
                    expected_context_generation = 4,
                    expected_manifest_digest = first.view_manifest_snapshot,
                    canonical_facts_before = 3,
                    canonical_facts_removed = 0,
                    source_first_seq = 1,
                    source_last_seq = 2,
                    source_digest = source_digest,
                    config_snapshot = config_snapshot,
                    summary = summary,
                    summary_digest = summary_digest,
                    summary_schema = "structured-summary-v1",
                    generator_model_snapshot = model_snapshot,
                    usage = usage,
                    correction_ids = {},
                    manifest = manifest,
                    old_view_retained_until_publish = true,
                    atomic_groups_split = 0,
                }
                local malformed = {}
                for key, value in pairs(publication_record) do malformed[key] = value end
                malformed.summary_digest = string.rep("0", 64)
                local rejected, reject_error = journal.publish(malformed)
                A.falsy(rejected)
                A.equal(reject_error.code, "CompactionSummaryMismatch")
                A.equal(publication.status().generation, 4)
                A.equal(publication.status().event_count, 5)
                A.equal(
                    observed.published.document.model_view.active_manifest.digest,
                    first.view_manifest_snapshot
                )

                local malformed_manifest = {}
                for key, value in pairs(publication_record) do
                    malformed_manifest[key] = value
                end
                local forged_manifest = {}
                for key, value in pairs(manifest) do forged_manifest[key] = value end
                forged_manifest.canonical_bytes = manifest.canonical_bytes .. "forged"
                malformed_manifest.manifest = forged_manifest
                rejected, reject_error = journal.publish(malformed_manifest)
                A.falsy(rejected)
                A.equal(reject_error.code, "CompactionManifestMismatch")
                A.equal(publication.status().generation, 4)
                A.equal(publication.status().event_count, 5)

                local published, publish_receipt = journal.publish(publication_record)
                A.truthy(published, A.render(publish_receipt))
                A.equal(publish_receipt.binding, publication_record)
                A.equal(publish_receipt.previous_manifest_digest, first.view_manifest_snapshot)
                A.equal(publish_receipt.published_manifest_digest, manifest_digest)
                A.equal(publication.status().generation, 5)
                A.equal(publication.status().event_count, 7)
                local document = observed.published.document
                A.equal(document.facts[6].type, "compaction")
                A.equal(document.facts[7].type, "model_view_published")
                A.equal(document.model_view.active_manifest.compaction_id, "compaction-1")
                A.equal(document.model_view.compaction_records[1].summary, summary)
                local body = assert(publication.resolve_view(manifest_digest)).body
                A.contains(body, "<StructuredSummary")
                A.contains(body, "GOALS-PRESERVED")
                A.contains(body, "TAIL-KEEP")
                A.falsy(body:find("compact this prefix", 1, true))
                A.falsy(body:find('type="model_request"', 1, true))
                local _, summary_count = body:gsub("<StructuredSummary", "")
                A.equal(summary_count, 1)

                A.truthy(publication.commit({
                    barrier_id = "after-compaction",
                    first_sequence = 8,
                    last_sequence = 8,
                    event_count = 1,
                    expected_context_generation = 5,
                    events = { {
                        seq = 8,
                        type = "warning",
                        fields = {
                            errorId = "AfterCompaction",
                            summary = "AFTER-COMPACT",
                        },
                    } },
                }))
                local next_view = assert(publication.prepare_view({
                    expected_context_generation = 6,
                    expected_last_sequence = 8,
                    current_manifest_ref = manifest_digest,
                }))
                A.equal(next_view.compaction_id, "compaction-1")
                A.equal(next_view.view_context_generation, 6)
                A.truthy(next_view.changed)
                A.truthy(publication.commit({
                    barrier_id = "publish-after-compaction",
                    first_sequence = 9,
                    last_sequence = 9,
                    event_count = 1,
                    expected_context_generation = 6,
                    events = { {
                        seq = 9,
                        type = "model_view_published",
                        fields = {
                            manifestDigest = next_view.digest,
                            firstEventSeq = tostring(next_view.first_sequence),
                            lastEventSeq = tostring(next_view.last_sequence),
                            replacesManifestDigest = next_view.replaces_manifest_ref,
                            compactionId = next_view.compaction_id,
                            viewContextGeneration = tostring(
                                next_view.view_context_generation
                            ),
                        },
                    } },
                }))
                local next_body = assert(publication.resolve_view(next_view.digest)).body
                A.contains(next_body, "GOALS-PRESERVED")
                A.contains(next_body, "TAIL-KEEP")
                A.contains(next_body, "AFTER-COMPACT")
                A.falsy(next_body:find("compact this prefix", 1, true))
                _, summary_count = next_body:gsub("<StructuredSummary", "")
                A.equal(summary_count, 1)
                local compacted_document = observed.published.document
                A.truthy(publication.close())
                local manager, managed_observed = fixture({ open_document = compacted_document })
                local renamed, rename_error = manager.manage_context(management_spec(first, compacted_document,
                    "rename", { new_name = "Still Compacted" }))
                A.truthy(renamed, A.render(rename_error))
                local managed = managed_observed.published.document
                A.equal(managed.model_view.active_manifest.compaction_id, "compaction-1")
                local rebinder, rebound_observed = fixture({ open_document = managed,
                    workspace_roots = { "/compacted-work" } })
                local move_request = management_spec(renamed, managed, "rebind", {
                    target_root = "/compacted-work",
                })
                move_request.rebind_plan = assert(rebinder.plan_rebind(move_request))
                move_request.target_root = nil
                renamed = assert(rebinder.manage_context(move_request))
                managed = rebound_observed.published.document
                A.equal(managed.model_view.active_manifest.compaction_id, "compaction-1")
                local importer, imported_observed = fixture({ open_document = managed,
                    workspace_roots = { "/compacted-work" } })
                local mapped_generation = generation()
                mapped_generation.context_prompt = managed.session.context_prompt
                mapped_generation.auto_rename_disabled = managed.header.auto_rename_disabled == true
                if type(managed.session.double_check_override) == "boolean" then
                    mapped_generation.effective_double_check = managed.session.double_check_override
                end
                if managed.session.double_check_goal_override.mode == "value" then
                    mapped_generation.effective_double_check_goal = managed.session.double_check_goal_override.value
                end
                mapped_generation.models.ImportedCompact = mapped_generation.models.Primary
                mapped_generation.current_model = "ImportedCompact"
                local import_request = management_spec(renamed, managed, "import", { generation = mapped_generation })
                import_request.import_plan = assert(importer.plan_import(import_request))
                renamed = assert(importer.manage_context(import_request))
                managed = imported_observed.published.document
                A.equal(managed.model_view.active_manifest.compaction_id, "compaction-1")
                A.equal(managed.session.current_model.name, "ImportedCompact")
                local repairer, repaired_observed = fixture({ open_document = managed })
                local repair_request = management_spec(renamed, managed, "repair")
                repair_request.repair_plan = assert(repairer.plan_repair(repair_request))
                renamed = assert(repairer.manage_context(repair_request))
                managed = repaired_observed.published.document
                A.equal(managed.model_view.active_manifest.compaction_id, "compaction-1")
                local reopened = fixture({ open_document = managed })
                local specification = management_spec(renamed, managed, "rename")
                specification.action = nil
                local opened = assert(reopened.open_existing(specification))
                local restored = assert(reopened.resolve_view(opened.view_manifest_snapshot)).body
                A.contains(restored, "GOALS-PRESERVED")
                A.contains(restored, "AFTER-COMPACT")
                A.contains(restored, "Still Compacted")
                A.contains(restored, "/compacted-work/")
                A.contains(restored, "ImportedCompact")
                A.contains(restored, "PreviousValidRestored")
                A.falsy(restored:find("compact this prefix", 1, true))
                local _, restored_count = restored:gsub("<StructuredSummary", "")
                A.equal(restored_count, 1)
                A.truthy(reopened.close())
            end,
        },
        {
            name = "compaction cancellation records terminal truth without replacing the view",
            run = function()
                local publication, observed, _, _, safety_service = fixture()
                local first = assert(publication.publish_first({
                    generation = generation(),
                    workspace = { path = "/work", enterable = true },
                    settings = {
                        model = "Primary",
                        permission = "Std",
                        double_check = true,
                        double_check_override = "inherit",
                        double_check_goal = "verify cancellation",
                        double_check_goal_override = "inherit",
                        context_prompt = "workspace context",
                        auto_rename_disabled = false,
                    },
                    message = "cancel compaction safely",
                    source = "main",
                }))
                local document = observed.published.document
                local source_bytes = assert(compact.encode_source(
                    document,
                    1,
                    2,
                    256,
                    16 * 1024 * 1024
                ))
                local source_digest = assert(safety_service.digest(source_bytes))
                local config_snapshot = assert(safety_service.digest("cancel-config"))
                local model_snapshot = assert(safety_service.digest("cancel-model"))
                local prompt_snapshot = assert(safety_service.digest("cancel-prompt"))
                local journal = publication.compaction_journal()
                local committed, receipt = journal.commit_intent({
                    kind = "compaction-request",
                    purpose = "compaction",
                    mode = "manual",
                    compaction_id = "compaction-cancelled",
                    request_id = "compaction-cancelled:request:1",
                    attempt = 1,
                    correction_reason = false,
                    expected_context_generation = 1,
                    expected_manifest_digest = first.view_manifest_snapshot,
                    source_first_seq = 1,
                    source_last_seq = 2,
                    source_digest = source_digest,
                    config_snapshot = config_snapshot,
                    model_snapshot_digest = model_snapshot,
                    prompt_bundle_digest = prompt_snapshot,
                    manifest_snapshot_id = "manifest-compaction-v1",
                })
                A.truthy(committed, A.render(receipt))
                committed, receipt = journal.commit_rejection({
                    kind = "compaction-cancel-request",
                    compaction_id = "compaction-cancelled",
                    request_id = "compaction-cancelled:request:1",
                    reason = "user-cancel",
                    source_first_seq = 1,
                    source_last_seq = 2,
                    source_digest = source_digest,
                    canonical_facts_before = 2,
                    expected_context_generation = 2,
                    expected_manifest_digest = first.view_manifest_snapshot,
                    old_view_retained = true,
                })
                A.truthy(committed, A.render(receipt))
                committed, receipt = journal.commit_rejection({
                    kind = "compaction-cancel-result",
                    compaction_id = "compaction-cancelled",
                    request_id = "compaction-cancelled:request:1",
                    reason = "user-cancel",
                    outcome = "cancelled",
                    source_first_seq = 1,
                    source_last_seq = 2,
                    source_digest = source_digest,
                    canonical_facts_before = 2,
                    config_snapshot = config_snapshot,
                    model_snapshot_digest = model_snapshot,
                    prompt_bundle_digest = prompt_snapshot,
                    expected_context_generation = 3,
                    expected_manifest_digest = first.view_manifest_snapshot,
                    old_view_retained = true,
                })
                A.truthy(committed, A.render(receipt))
                A.equal(receipt.context_generation, 4)
                A.equal(receipt.active_manifest_digest, first.view_manifest_snapshot)
                A.equal(publication.status().event_count, 6)
                local cancelled = observed.published.document
                A.equal(cancelled.facts[4].type, "cancel")
                A.equal(cancelled.facts[5].type, "cancel")
                A.equal(cancelled.facts[6].type, "compaction")
                A.equal(cancelled.facts[6].fields.status, "cancelled")
                A.equal(cancelled.facts[6].fields.requestId,
                    "compaction-cancelled:request:1")
                A.equal(cancelled.facts[6].fields.compactionMode, "manual")
                A.equal(cancelled.facts[6].fields.automaticFailure, "false")
                A.equal(cancelled.model_view.compaction_records[1].status, "cancelled")
                A.equal(cancelled.model_view.active_manifest.digest, first.view_manifest_snapshot)
                A.falsy(cancelled.model_view.active_manifest.compaction_id)
                A.equal(#cancelled.recovery.pending_compactions, 0)
                A.truthy(publication.resolve_view(first.view_manifest_snapshot))
            end,
        },
        {
            name = "existing Context open terminalizes every crash-left compaction bracket",
            run = function()
                for _, crash_state in ipairs({
                    "request-only", "automatic-request-only", "response-only",
                    "cancel-pending", "rejected-retry",
                }) do
                    local shared = {}
                    local settings = { shared_store = shared }
                    local publication, observed, _, _, safety_service = fixture(settings)
                    local first = assert(publication.publish_first({
                        generation = generation(),
                        workspace = { path = "/work", enterable = true },
                        settings = {
                            model = "Primary",
                            permission = "Std",
                            double_check = true,
                            double_check_override = "inherit",
                            double_check_goal = "recover compaction",
                            double_check_goal_override = "inherit",
                            context_prompt = "workspace context",
                            auto_rename_disabled = false,
                        },
                        message = "recover " .. crash_state,
                        source = "main",
                    }))
                    local source_bytes = assert(compact.encode_source(
                        observed.published.document,
                        1,
                        2,
                        256,
                        16 * 1024 * 1024
                    ))
                    local source_digest = assert(safety_service.digest(source_bytes))
                    local config_snapshot = assert(safety_service.digest(
                        "recovery-config-" .. crash_state
                    ))
                    local model_snapshot = assert(safety_service.digest(
                        "recovery-model-" .. crash_state
                    ))
                    local prompt_snapshot = assert(safety_service.digest(
                        "recovery-prompt-" .. crash_state
                    ))
                    local request_id = "compaction-81:request:1"
                    local mode = crash_state == "automatic-request-only"
                        and "automatic" or "manual"
                    local journal = publication.compaction_journal()
                    local committed, receipt = journal.commit_intent({
                        kind = "compaction-request",
                        purpose = "compaction",
                        mode = mode,
                        compaction_id = "compaction-81",
                        request_id = request_id,
                        attempt = 1,
                        correction_reason = false,
                        expected_context_generation = 1,
                        expected_manifest_digest = first.view_manifest_snapshot,
                        source_first_seq = 1,
                        source_last_seq = 2,
                        source_digest = source_digest,
                        config_snapshot = config_snapshot,
                        model_snapshot_digest = model_snapshot,
                        prompt_bundle_digest = prompt_snapshot,
                        manifest_snapshot_id = "manifest-compaction-v1",
                    })
                    A.truthy(committed, A.render(receipt))
                    if crash_state == "response-only" then
                        local body = "durable response before process loss"
                        committed, receipt = journal.commit_response({
                            kind = "compaction-response",
                            compaction_id = "compaction-81",
                            request_id = request_id,
                            attempt = 1,
                            canonical_body = body,
                            canonical_digest = assert(safety_service.digest(body)),
                            source_first_seq = 1,
                            source_last_seq = 2,
                            source_digest = source_digest,
                            usage = {
                                input_tokens = 10,
                                output_tokens = 5,
                                estimated = true,
                            },
                            expected_context_generation = 2,
                            expected_manifest_digest = first.view_manifest_snapshot,
                        })
                        A.truthy(committed, A.render(receipt))
                    elseif crash_state == "cancel-pending" then
                        committed, receipt = journal.commit_rejection({
                            kind = "compaction-cancel-request",
                            compaction_id = "compaction-81",
                            request_id = request_id,
                            reason = "user-cancel-before-crash",
                            source_first_seq = 1,
                            source_last_seq = 2,
                            source_digest = source_digest,
                            canonical_facts_before = 2,
                            expected_context_generation = 2,
                            expected_manifest_digest = first.view_manifest_snapshot,
                            old_view_retained = true,
                        })
                        A.truthy(committed, A.render(receipt))
                    elseif crash_state == "rejected-retry" then
                        committed, receipt = journal.commit_rejection({
                            kind = "compaction-rejection",
                            compaction_id = "compaction-81",
                            request_id = request_id,
                            attempt = 1,
                            error_code = "CompactionNoBenefit",
                            detail = "retry not started before process loss",
                            response_digest = false,
                            response_body = false,
                            terminal = false,
                            source_first_seq = 1,
                            source_last_seq = 2,
                            source_digest = source_digest,
                            canonical_facts_before = 2,
                            config_snapshot = config_snapshot,
                            model_snapshot_digest = model_snapshot,
                            prompt_bundle_digest = prompt_snapshot,
                            expected_context_generation = 2,
                            expected_manifest_digest = first.view_manifest_snapshot,
                            old_view_retained = true,
                        })
                        A.truthy(committed, A.render(receipt))
                    end
                    A.truthy(publication.close())

                    local reopened, reopened_observed = fixture({
                        shared_store = shared,
                        random_values = {
                            string.rep("r", 8),
                            string.rep("s", 8),
                        },
                    })
                    local opened = assert(reopened.open_existing({
                        context_path = first.context_path,
                        logical_path = first.logical_path,
                        expected_credential = {
                            physical_path = first.context_path,
                            logical_path = first.logical_path,
                        },
                    }))
                    A.equal(opened.outcome, "recovered", crash_state)
                    A.equal(opened.compaction_recovery.recovered_bound, 1)
                    A.equal(opened.compaction_recovery.recovered_legacy, 0)
                    A.equal(opened.compaction_recovery.outcome, "recovered-unknown")
                    A.truthy(opened.compaction_recovery.old_view_retained)
                    A.equal(opened.view_manifest_snapshot, first.view_manifest_snapshot)
                    local recovered = reopened_observed.published.document
                    A.equal(#recovered.recovery.pending_compactions, 0)
                    A.falsy(recovered.recovery.auto_continue)
                    A.deep_equal(recovered.recovery.unfinished_turn_ids, { "turn-1" })
                    A.equal(recovered.model_view.active_manifest.digest,
                        first.view_manifest_snapshot)
                    A.equal(recovered.model_view.compaction_records[1].status, "error")
                    local terminal = recovered.facts[#recovered.facts]
                    A.equal(terminal.type, "compaction")
                    A.equal(terminal.fields.requestId, request_id)
                    A.equal(terminal.fields.status, "error")
                    A.equal(terminal.fields.errorId, "CompactionCancelUnknown")
                    A.equal(
                        terminal.fields.automaticFailure,
                        mode == "automatic" and "true" or "false"
                    )
                    local pending_count, unknown_count = 0, 0
                    for _, event in ipairs(recovered.facts) do
                        if event.type == "cancel"
                            and event.fields.targetId == request_id
                        then
                            if event.fields.result == "pending" then
                                pending_count = pending_count + 1
                            elseif event.fields.result == "unknown" then
                                unknown_count = unknown_count + 1
                            end
                        end
                    end
                    A.equal(pending_count, 1)
                    A.equal(unknown_count, 1)
                    A.truthy(reopened.resolve_view(first.view_manifest_snapshot))
                    local snapshot = assert(reopened.compaction_snapshot({
                        expected_context_generation = opened.generation,
                        expected_last_sequence = opened.event_count,
                        expected_manifest_digest = opened.view_manifest_snapshot,
                    }))
                    A.equal(snapshot.initial_serial, 81)
                    A.equal(
                        snapshot.initial_automatic_failure_count,
                        mode == "automatic" and 1 or 0
                    )
                    A.truthy(snapshot.automatic_failure_history_complete)
                    A.equal(#snapshot.pending_compactions, 0)
                    A.truthy(reopened.close())
                end

                local shared = {}
                local publication, observed, _, _, _, schema = fixture({
                    shared_store = shared,
                })
                local first = assert(publication.publish_first({
                    generation = generation(),
                    workspace = { path = "/work", enterable = true },
                    settings = {
                        model = "Primary",
                        permission = "Std",
                        double_check = true,
                        double_check_override = "inherit",
                        double_check_goal = "recover legacy compaction",
                        double_check_goal_override = "inherit",
                        context_prompt = "workspace context",
                        auto_rename_disabled = false,
                    },
                    message = "recover legacy request",
                    source = "main",
                }))
                shared.document = assert(schema.append_events(
                    observed.published.document,
                    {
                        updated_at = "2026-08-30T12:34:57Z",
                        events = { {
                            seq = 3,
                            type = "model_request",
                            fields = {
                                requestId = "compaction-91:request:1",
                                purpose = "compaction",
                                viewManifestRef = first.view_manifest_snapshot,
                                attemptId = "1",
                            },
                        } },
                    }
                ))
                A.truthy(publication.close())
                local reopened, reopened_observed = fixture({
                    shared_store = shared,
                    random_values = { string.rep("l", 8) },
                })
                local opened = assert(reopened.open_existing({
                    context_path = first.context_path,
                    logical_path = first.logical_path,
                    expected_credential = {
                        physical_path = first.context_path,
                        logical_path = first.logical_path,
                    },
                }))
                A.equal(opened.compaction_recovery.recovered_bound, 0)
                A.equal(opened.compaction_recovery.recovered_legacy, 1)
                local recovered = reopened_observed.published.document
                A.equal(#recovered.recovery.legacy_pending_compaction_request_ids, 0)
                A.equal(#recovered.model_view.compaction_records, 0)
                A.equal(recovered.facts[#recovered.facts - 1].fields.result, "pending")
                A.equal(recovered.facts[#recovered.facts].fields.result, "unknown")
                A.equal(recovered.model_view.active_manifest.digest,
                    first.view_manifest_snapshot)
                local snapshot = assert(reopened.compaction_snapshot({
                    expected_context_generation = opened.generation,
                    expected_last_sequence = opened.event_count,
                    expected_manifest_digest = opened.view_manifest_snapshot,
                }))
                A.equal(snapshot.initial_serial, 91)
                A.equal(#snapshot.legacy_pending_compaction_request_ids, 0)
                A.truthy(reopened.close())
            end,
        },
        {
            name = "operation journal publishes intent and paired result into one waterline",
            run = function()
                local publication, observed, _, _, safety_service = fixture()
                local first = assert(publication.publish_first({
                    generation = generation(),
                    workspace = { path = "/work", enterable = true },
                    settings = {
                        model = "Primary",
                        permission = "Std",
                        double_check = true,
                        double_check_override = "inherit",
                        double_check_goal = "verify the durable result",
                        double_check_goal_override = "inherit",
                        context_prompt = "workspace context",
                        auto_rename_disabled = false,
                    },
                    message = "run a tool",
                    source = "main",
                }))
                local accepted = {
                    barrier_id = "turn-1:barrier:accepted-tool",
                    first_sequence = 3,
                    last_sequence = 6,
                    event_count = 4,
                    expected_context_generation = first.generation,
                    events = {
                        {
                            seq = 3,
                            type = "model_request",
                            turn_id = "turn-1",
                            fields = {
                                requestId = "turn-1:request:1",
                                purpose = "main",
                                viewManifestRef = first.view_manifest_snapshot,
                            },
                        },
                        {
                            seq = 4,
                            type = "model_message",
                            turn_id = "turn-1",
                            fields = {
                                messageId = "turn-1:message:2",
                                requestId = "turn-1:request:1",
                                role = "assistant",
                                status = "complete",
                                body = "tool call",
                                rawBytes = "9",
                                digest = "model-message-digest",
                            },
                        },
                        {
                            seq = 5,
                            type = "tool_call",
                            turn_id = "turn-1",
                            fields = {
                                toolCallId = "turn-1:tool:1",
                                requestId = "turn-1:request:1",
                                name = "exec",
                                canonicalArguments = '{"command":"true"}',
                                providerCallId = "provider-1",
                            },
                        },
                        {
                            seq = 6,
                            type = "permission_decision",
                            turn_id = "turn-1",
                            fields = {
                                toolCallId = "turn-1:tool:1",
                                capabilities = "Shell",
                                decision = "allow",
                                profileSnapshot = "permission-snapshot",
                            },
                        },
                    },
                }
                A.truthy(publication.commit(accepted))
                local journal = publication.operation_journal()
                local operations = assert(context.new_operation_service({
                    safety = safety_service,
                    journal = journal,
                }, {
                    maximum_identifier_bytes = 256,
                    maximum_evidence_bytes = 65536,
                    unresolved_operation_ids = {},
                }))
                local handle, intent_digest = assert(operations.begin({
                    operation_id = "turn-1:operation:1",
                    tool_call_id = "turn-1:tool:1",
                    kind = "exec",
                    target_identity = "target-digest",
                    expected_digest = "opaque-call-digest",
                    call_digest = "call-digest",
                }))
                local intent_receipt = assert(journal.take_intent_receipt(
                    "turn-1:operation:1",
                    intent_digest
                ))
                A.equal(intent_receipt.first_sequence, 7)
                A.equal(intent_receipt.last_sequence, 7)
                A.equal(intent_receipt.context_generation, 3)
                local body = '{"outcome":"success"}'
                local result_digest = assert(operations.finish(handle, {
                    status = "ok",
                    evidence = "canonical-result:result-digest",
                    tool_status = "ok",
                    tool_body = body,
                    tool_truncated = false,
                    tool_raw_bytes = #body,
                    tool_digest = "tool-body-digest",
                }))
                local result_receipt = assert(journal.take_result_receipt(
                    "turn-1:operation:1",
                    result_digest
                ))
                A.equal(result_receipt.first_sequence, 8)
                A.equal(result_receipt.last_sequence, 9)
                A.equal(result_receipt.context_generation, 4)
                A.equal(publication.status().event_count, 9)
                A.equal(observed.published.document.facts[7].type, "operation_intent")
                A.equal(observed.published.document.facts[8].type, "operation_result")
                A.equal(observed.published.document.facts[9].type, "tool_result")
                A.equal(observed.published.document.facts[9].fields.body, body)
                A.truthy(publication.close())
            end,
        },
        {
            name = "name collision retries with fresh secure bytes and remains bounded",
            run = function()
                local publication, observed = fixture({
                    create_collisions = 1,
                    random_values = {
                        string.char(0x00, 0x01) .. "abcdefgh",
                        string.char(0xFE, 0xDC) .. "ABCDEFGH",
                    },
                })
                local receipt = assert(publication.publish_first({
                    generation = generation(),
                    workspace = { path = "/work", enterable = true },
                    settings = {
                        model = "Primary",
                        permission = "Std",
                        double_check = true,
                        double_check_override = "inherit",
                        double_check_goal = "verify the durable result",
                        double_check_goal_override = "inherit",
                        context_prompt = "workspace context",
                        auto_rename_disabled = false,
                    },
                    message = "continue",
                    source = "main",
                }))
                A.equal(receipt.display_name, "Untitled Conversation [FEDC]")
                A.equal(observed.random_calls, 2)
                A.equal(observed.create_attempts, 2)
                A.truthy(publication.close())
            end,
        },
        {
            name = "secret and publication failure leave the draft not saved",
            run = function()
                local publication, observed = fixture({
                    publish_error = { code = "Storage", message = "write failed" },
                })
                local draft = assert(session.new_draft(generation(), {
                    path = "/work",
                    enterable = true,
                }, { maximum_draft_bytes = 16384 }, publication))
                local receipt, publication_error = draft.begin_main("registered-secret")
                A.falsy(receipt)
                A.equal(publication_error.code, "RegisteredSecret")
                A.equal(observed.random_calls, 0)
                receipt, publication_error = draft.begin_main("safe input")
                A.falsy(receipt)
                A.equal(publication_error.code, "Storage")
                A.equal(draft.status().lifecycle, "not-saved")
                A.falsy(draft.status().durable)
                A.equal(observed.closes, 1)
                A.truthy(draft.close())
                A.equal(observed.closes, 1)
            end,
        },
        {
            name = "Windows mirror uses logical drive segments and native separators",
            run = function()
                local publication, observed = fixture({
                    initial_root = "C:\\release",
                    data_root = "C:\\release\\__yaca__",
                    platform_kind = "windows",
                })
                local receipt = assert(publication.publish_first({
                    generation = generation(),
                    workspace = { path = "C:\\Work\\任务", enterable = true },
                    settings = {
                        model = "Primary",
                        permission = "Std",
                        double_check = true,
                        double_check_override = "inherit",
                        double_check_goal = "verify the durable result",
                        double_check_goal_override = "inherit",
                        context_prompt = "workspace context",
                        auto_rename_disabled = false,
                    },
                    message = "publish on Windows",
                    source = "main",
                }))
                A.equal(
                    receipt.context_path,
                    "C:\\release\\__yaca__\\CONTEXT\\C\\Work\\任务\\"
                        .. "Untitled Conversation [0A1B].xml"
                )
                A.deep_equal(observed.creates, {
                    "C:\\release\\__yaca__",
                    "C:\\release\\__yaca__\\CONTEXT",
                    "C:\\release\\__yaca__\\CONTEXT\\C",
                    "C:\\release\\__yaca__\\CONTEXT\\C\\Work",
                    "C:\\release\\__yaca__\\CONTEXT\\C\\Work\\任务",
                })
                A.truthy(publication.close())
            end,
        },
        {
            name = "aliased Context ancestry fails before directory or Context creation",
            run = function()
                local publication, observed = fixture({
                    alias_path = "/release/__yaca__/CONTEXT",
                })
                local receipt, publication_error = publication.publish_first({
                    generation = generation(),
                    workspace = { path = "/work", enterable = true },
                    settings = {
                        model = "Primary",
                        permission = "Std",
                        double_check = true,
                        double_check_override = "inherit",
                        double_check_goal = "verify the durable result",
                        double_check_goal_override = "inherit",
                        context_prompt = "workspace context",
                        auto_rename_disabled = false,
                    },
                    message = "must not publish",
                    source = "main",
                })
                A.falsy(receipt)
                A.equal(publication_error.code, "ContextDirectoryAlias")
                A.equal(observed.random_calls, 0)
                A.equal(observed.create_attempts or 0, 0)
            end,
        },
    },
}
