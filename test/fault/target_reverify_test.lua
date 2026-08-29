--[[
File: target_reverify_test.lua
Date: 2026-08-29
Author: WaterRun
Description: Verifies exact target revalidation immediately before direct effects.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()
local sha256 = assert(loadfile(
    YACA_TEST_ROOT .. "/test/support/sha256_reference.lua",
    "t",
    _ENV
))()
local direct_harness = assert(loadfile(
    YACA_TEST_ROOT .. "/test/support/direct_filesystem_harness.lua",
    "t",
    _ENV
))()

local function load_module(name, cache)
    cache = cache or {}
    if cache[name] then return cache[name] end
    local environment = {}
    for key, value in pairs(_ENV) do environment[key] = value end
    environment.require = function(dependency) return load_module(dependency, cache) end
    environment._G = environment
    setmetatable(environment, { __index = _ENV })
    local chunk = assert(loadfile(YACA_TEST_ROOT .. "/src/" .. name .. ".lua", "t", environment))
    local result = chunk()
    cache[name] = result
    return result
end

local arrays = setmetatable({}, { __mode = "k" })
local function arr(value) arrays[value] = true; return value end

local function escape(value)
    return '"' .. value:gsub("[\\\"\0-\31]", function(character)
        local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
        return map[character] or string.format("\\u%04x", character:byte())
    end) .. '"'
end

local function encode(value)
    if type(value) == "string" then return escape(value) end
    if type(value) == "boolean" then return value and "true" or "false" end
    if math.type(value) == "integer" then return tostring(value) end
    local output = {}
    if arrays[value] then
        for index, item in ipairs(value) do output[index] = encode(item) end
        return "[" .. table.concat(output, ",") .. "]"
    end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys)
    for index, key in ipairs(keys) do output[index] = escape(key) .. ":" .. encode(value[key]) end
    return "{" .. table.concat(output, ",") .. "}"
end

local function hash_port()
    return {
        sha256_start = function() return { parts = {} } end,
        sha256_update = function(handle, bytes) handle.parts[#handle.parts + 1] = bytes; return true end,
        sha256_finish = function(handle) return sha256.digest(table.concat(handle.parts)) end,
        sha256_close = function() return true end,
    }
end

local function setup()
    local native, controls = direct_harness.new({
        ["/work"] = { kind = "directory" },
        ["/work/a.txt"] = "old\n",
        ["/work/sub"] = { kind = "directory" },
        ["/work/sub/b.txt"] = "nested\n",
        ["/reserved"] = { kind = "directory" },
    })
    local modules, port = {}, hash_port()
    local filesystem = assert(load_module("fs", modules).new(native, {
        maximum_chunk_bytes = 5,
        maximum_lease_bytes = 64,
        maximum_direct_entries = 64,
    }))
    local paths = assert(load_module("path", modules).new(port, {
        maximum_path_bytes = 1024,
        maximum_segments = 64,
        maximum_segment_bytes = 255,
        maximum_hash_chunk_bytes = 9,
    }))
    local safety = assert(load_module("safety", modules).new(port, {
        maximum_hash_chunk_bytes = 9,
        minimum_scannable_secret_bytes = 8,
    }))
    local authority = {
        admit = function(call) return true, "authority-" .. call.call_digest end,
        reverify = function(call, _, digest) return digest == "authority-" .. call.call_digest end,
    }
    local service = assert(load_module("tools", modules).new({
        filesystem = filesystem,
        path = paths,
        safety = safety,
        secret_registry = false,
        authorization = authority,
    }, {
        maximum_argument_bytes = 32768,
        maximum_path_bytes = 1024,
        maximum_content_bytes = 16384,
        maximum_file_bytes = 16384,
        maximum_result_bytes = 32768,
        maximum_list_depth = 8,
        maximum_page_entries = 8,
        maximum_walk_entries = 64,
        maximum_search_pattern_bytes = 128,
        maximum_search_matches = 32,
        maximum_patch_hunks = 8,
        maximum_patch_lines = 64,
        maximum_line_bytes = 2048,
        maximum_continuations = 4,
        maximum_identifier_bytes = 128,
        filesystem_chunk_bytes = 5,
        create_permissions = 384,
        maximum_json_depth = 20,
        maximum_json_nodes = 2048,
        maximum_number_bytes = 32,
        platform_kind = "posix",
        workspace_path = "/work",
        reserved_paths = { "/reserved" },
    }))
    return service, controls
end

local function admit(service, tool, arguments, id)
    local call = assert(service:admit_call({
        tool = tool,
        schema_version = service.schema_version,
        registry_digest = service.registry_digest,
        provider_call_id = "provider-" .. id,
        tool_call_id = "call-" .. id,
        operation_id = "operation-" .. id,
        canonical_arguments = encode(arguments),
    }))
    local action = assert(service:permission_action(call))
    local token = assert(service:authorize(call, {
        permission_snapshot_digest = "permission-v1",
        approval_digest = "approval-v1",
        durable_intent_digest = "intent-" .. id,
        config_generation = "generation-1",
        workspace_identity = action.workspace_root_identity,
        double_check = true,
        action_review = "approved",
    }))
    return call, token
end

local function operation_count(controls, prefix)
    local count = 0
    for _, operation in ipairs(controls.operations) do
        if operation:sub(1, #prefix) == prefix then count = count + 1 end
    end
    return count
end

return {
    name = "fault/target-reverify",
    cases = {
        {
            name = "read identity replacement after approval fails before verified open",
            run = function()
                local service, controls = setup()
                local _, token = admit(service, "read", {
                    path = "/work/a.txt", start_line = 1, max_lines = 4,
                }, "read-race")
                controls.external_replace("/work/a.txt", "foreign\n")
                local result = assert(service:execute(token))
                A.equal(result.outcome, "failed")
                A.equal(result.error.code, "TargetChanged")
                A.equal(operation_count(controls, "open-verified:/work/a.txt"), 0)
                A.equal(controls.bytes("/work/a.txt"), "foreign\n")
            end,
        },
        {
            name = "replace and create races cause zero direct publication",
            run = function()
                local service, controls = setup()
                local old_identity = controls.identity("/work/a.txt")
                local _, replace_token = admit(service, "write", {
                    path = "/work/a.txt", mode = "replace", content = "candidate\n",
                    encoding = "utf-8", newline_policy = "preserve",
                    expected_identity = old_identity,
                    expected_raw_digest = sha256.hex("old\n"),
                }, "replace-race")
                controls.external_replace("/work/a.txt", "foreign\n")
                local replaced = assert(service:execute(replace_token))
                A.equal(replaced.error.code, "TargetChanged")
                A.equal(operation_count(controls, "create-verified:"), 0)
                A.equal(operation_count(controls, "replace-verified:"), 0)
                A.equal(controls.bytes("/work/a.txt"), "foreign\n")

                local _, create_token = admit(service, "write", {
                    path = "/work/new.txt", mode = "create", content = "candidate\n",
                    encoding = "utf-8", newline_policy = "preserve",
                }, "create-race")
                controls.external_replace("/work/new.txt", "foreign\n")
                local created = assert(service:execute(create_token))
                A.equal(created.error.code, "TargetChanged")
                A.equal(controls.bytes("/work/new.txt"), "foreign\n")
            end,
        },
        {
            name = "rename source target and delete races never touch substitutes",
            run = function()
                local service, controls = setup()
                local _, rename_token = admit(service, "rename", {
                    source = "/work/a.txt", target = "/work/moved.txt",
                    expected_identity = controls.identity("/work/a.txt"),
                    expected_raw_digest = sha256.hex("old\n"),
                }, "rename-race")
                controls.external_replace("/work/moved.txt", "occupied\n")
                local renamed = assert(service:execute(rename_token))
                A.equal(renamed.error.code, "TargetChanged")
                A.equal(operation_count(controls, "rename-verified:"), 0)
                A.equal(controls.bytes("/work/a.txt"), "old\n")
                A.equal(controls.bytes("/work/moved.txt"), "occupied\n")

                local _, delete_token = admit(service, "delete", {
                    path = "/work/a.txt",
                    expected_identity = controls.identity("/work/a.txt"),
                    expected_raw_digest = sha256.hex("old\n"),
                }, "delete-race")
                controls.external_replace("/work/a.txt", "substitute\n")
                local deleted = assert(service:execute(delete_token))
                A.equal(deleted.error.code, "TargetChanged")
                A.equal(operation_count(controls, "delete-verified:/work/a.txt"), 0)
                A.equal(controls.bytes("/work/a.txt"), "substitute\n")
            end,
        },
        {
            name = "reserved-root identity and incomplete ancestry fail closed",
            run = function()
                local service, controls = setup()
                local _, token = admit(service, "read", {
                    path = "/work/a.txt", start_line = 1, max_lines = 2,
                }, "reserved-race")
                controls.add("/reserved", "directory", "")
                local result = assert(service:execute(token))
                A.equal(result.error.code, "ReservedTreeChanged")
                A.equal(operation_count(controls, "open-verified:/work/a.txt"), 0)

                local other, other_controls = setup()
                other_controls.incomplete_ancestry = "/work/a.txt"
                local call, error_value = other:admit_call({
                    tool = "read",
                    schema_version = other.schema_version,
                    registry_digest = other.registry_digest,
                    provider_call_id = "provider-incomplete",
                    tool_call_id = "call-incomplete",
                    operation_id = "operation-incomplete",
                    canonical_arguments = encode({
                        path = "/work/a.txt", start_line = 1, max_lines = 1,
                    }),
                })
                A.falsy(call)
                A.equal(error_value.code, "ReservedAliasUnknown")
            end,
        },
        {
            name = "continuation generation changes are stale and never mix views",
            run = function()
                local service, controls = setup()
                local _, first_token = admit(service, "list", {
                    path = "/work", depth = 2, page_size = 1,
                }, "list-first")
                local first = assert(service:execute(first_token))
                A.truthy(first.payload.continuation)
                local _, next_token = admit(service, "list", {
                    path = "/work", depth = 2, page_size = 8,
                    continuation = first.payload.continuation,
                }, "list-next")
                controls.external_write("/work/sub/b.txt", "changed nested\n")
                local next_result = assert(service:execute(next_token))
                A.equal(next_result.outcome, "failed")
                A.equal(next_result.error.code, "ContinuationStale")
                A.equal(next_result.payload, false)
            end,
        },
        {
            name = "uncertain publish and durability windows report unknown without replay",
            run = function()
                local service, controls = setup()
                local _, replace_token = admit(service, "write", {
                    path = "/work/a.txt", mode = "replace", content = "candidate\n",
                    encoding = "utf-8", newline_policy = "preserve",
                    expected_identity = controls.identity("/work/a.txt"),
                    expected_raw_digest = sha256.hex("old\n"),
                }, "replace-unknown")
                controls.faults.replace = "Unknown"
                local replaced = assert(service:execute(replace_token))
                A.equal(replaced.outcome, "unknown")
                A.equal(replaced.error.code, "PublicationUnknown")
                A.equal(controls.bytes("/work/a.txt"), "old\n")
                local replay, replay_error = service:execute(replace_token)
                A.falsy(replay)
                A.equal(replay_error.code, "AuthorizationConsumed")

                local create_service, create_controls = setup()
                local _, create_token = admit(create_service, "write", {
                    path = "/work/new.txt", mode = "create", content = "candidate\n",
                    encoding = "utf-8", newline_policy = "preserve",
                }, "create-unknown")
                create_controls.faults.flush_directory = true
                local created = assert(create_service:execute(create_token))
                A.equal(created.outcome, "unknown")
                A.equal(created.error.code, "PublicationUnknown")
                A.equal(create_controls.bytes("/work/new.txt"), "candidate\n")
            end,
        },
    },
}
