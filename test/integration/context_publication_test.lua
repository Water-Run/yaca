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
        agent = { double_check = true },
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

    function store.publish(writer, document, temporary_path)
        observations.published = {
            writer = writer,
            document = document,
            temporary_path = temporary_path,
        }
        if settings.publish_error then return nil, settings.publish_error end
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
    }))
    return publication, observations, path_service, registry
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
                A.truthy(draft.close())
                A.equal(observed.closes, 1)
                A.equal(draft.status().lifecycle, "closed")
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
