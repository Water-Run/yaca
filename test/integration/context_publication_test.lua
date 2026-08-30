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
            identity = exists and { kind = "directory" } or false,
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
        observations.published = {
            writer = writer,
            document = document,
            temporary_path = temporary_path,
        }
        if settings.publish_error then return nil, settings.publish_error end
        if settings.shared_store then settings.shared_store.document = document end
        return {
            outcome = "published",
            generation = document.generation,
            event_count = document.event_count,
        }
    end

    function store.close_writer(writer)
        observations.closes = observations.closes + 1
        observations.last_closed = writer
        return true
    end

    local random_values = settings.random_values or {
        string.char(0x0A, 0x1B) .. "12345678",
    }
    local system = {}
    function system.secure_random(length)
        observations.random_calls = observations.random_calls + 1
        local value = random_values[observations.random_calls] or string.rep("z", length)
        A.equal(#value, length)
        return value
    end
    function system.current_process_id() return 1234 end
    function system.utc_now() return "2026-08-30T12:34:56Z" end

    local publication = assert(session.new_context_publication({
        filesystem = filesystem,
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

return {
    name = "integration/context-publication",
    cases = {
        {
            name = "first main message publishes generation one before becoming durable",
            run = function()
                local publication, observed, path_service, registry = fixture()
                local draft = assert(session.new_draft(generation(), {
                    path = "/work/项目",
                    enterable = true,
                    identity = { object = "workspace-1" },
                }, { maximum_draft_bytes = 16384 }, publication))
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
                    A.truthy(recovered.recovery.auto_continue)
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
