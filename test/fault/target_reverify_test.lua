--[[
Author: WaterRun
Date: 2026-09-23
File: target_reverify_test.lua
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

--Loads a source module into an isolated per-case environment.
--@param name string Module, Model, or resource name selected by the case.
--@param cache table Per-case module cache preserving isolated imports.
--@return any module Module export loaded in the isolated source environment.
local function load_module(name, cache)
    cache = cache or {}
    if cache[name] then return cache[name] end
    local environment = {}
    for key, value in pairs(_ENV) do environment[key] = value end
    --Resolves an imported Lua module through the isolated test loader.
    --@param dependency string Source module requested from the isolated loader.
    --@return any value Callback value consumed by the enclosing scenario assertion.
    environment.require = function(dependency) return load_module(dependency, cache) end
    environment._G = environment
    --@metatable environment Test-owned lookup and mutation contract for the current case.
    --@field __index any Fallback table or function used for missing fixture keys.
    setmetatable(environment, { __index = _ENV })
    local chunk = assert(loadfile(YACA_TEST_ROOT .. "/src/" .. name .. ".lua", "t", environment))
    local result = chunk()
    cache[name] = result
    return result
end

--@metatable fixture_view Test-owned lookup and mutation contract for the current case.
--@field __mode any Weak-reference mode controlling fixture object retention.
local arrays = setmetatable({}, { __mode = "k" })
--Supplies arr behavior required by this suite.
--@param value any Candidate whose acceptance or transformation the test checks.
--@return any observed Selected fixture value returned by the fixture.
local function arr(value) arrays[value] = true; return value end

--Transforms escape data used by this suite.
--@param value any Candidate whose acceptance or transformation the test checks.
--@return string observed escape value observed by the scenario assertion.
local function escape(value)
    --Supplies an assertion callback for this test scenario.
    --@param character string Character emitted or parsed by the fixture.
    --@return number value Callback value consumed by the enclosing scenario assertion.
    return '"' .. value:gsub("[\\\"\0-\31]", function(character)
        local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
        return map[character] or string.format("\\u%04x", character:byte())
    end) .. '"'
end

--Transforms encode data used by this suite.
--@param value any Candidate whose acceptance or transformation the test checks.
--@return string|any observed encode value observed by the scenario assertion.
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

--Constructs an incremental SHA-256 port backed by the reference digest.
--@param none No arguments; this closure uses its captured fixture state.
--@return table port Incremental SHA-256 fixture port.
local function hash_port()
    return {
        --Computes or records sha256 start data for this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return table record Fixture record emitted by the scenario callback.
        sha256_start = function() return { parts = {} } end,
        --Computes or records sha256 update data for this suite.
        --@param handle table|integer Fake resource handle whose state is inspected.
        --@param bytes string Byte chunk supplied to the fake I/O port.
        --@return boolean accepted Whether the fake callback accepts this scenario.
        sha256_update = function(handle, bytes) handle.parts[#handle.parts + 1] = bytes; return true end,
        --Computes or records sha256 finish data for this suite.
        --@param handle table|integer Fake resource handle whose state is inspected.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        sha256_finish = function(handle) return sha256.digest(table.concat(handle.parts)) end,
        --Computes or records sha256 close data for this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return boolean accepted Whether the fake callback accepts this scenario.
        sha256_close = function() return true end,
    }
end

-- Build one isolated direct-tool service, optionally replacing native fixture operations before composition.
--@param prepare_native function|nil Hook receiving native operations and controls before fs.new binds them.
--@return table Tool service with operation and authorization fixtures.
--@return table Direct filesystem observation and external-mutation controls.
--@effect Creates only fixture files and invokes prepare_native once when supplied.
local function setup(prepare_native)
    local native, controls = direct_harness.new({
        ["/work"] = { kind = "directory" },
        ["/work/a.txt"] = "old\n",
        ["/work/sub"] = { kind = "directory" },
        ["/work/sub/b.txt"] = "nested\n",
        ["/reserved"] = { kind = "directory" },
    })
    if prepare_native then prepare_native(native, controls) end
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
        --Simulates the admit port for this suite.
        --@param call table|integer Recorded call or call ordinal under inspection.
        --@return boolean accepted Whether the fake callback accepts this scenario.
        --@return string secondary2 Fixture text "authority-" .. call.call_digest.
        admit = function(call) return true, "authority-" .. call.call_digest end,
        --Supplies the reverify observation used by this suite.
        --@param call table|integer Recorded call or call ordinal under inspection.
        --@param _ any Unused callback argument supplied by the port.
        --@param digest string Expected or computed hexadecimal digest.
        --@return string text Text emitted by the scenario callback.
        reverify = function(call, _, digest) return digest == "authority-" .. call.call_digest end,
    }
    local active_operation
    local operations = {
        --Simulates the begin transition of a fake activity port for this suite.
        --@param intent any The intent supplied to the fake service for this scenario.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        --@return string secondary2 Fixture text "intent-" .. intent.operation_id.
        begin = function(intent)
            active_operation = {}
            return active_operation, "intent-" .. intent.operation_id
        end,
        --Simulates the finish transition of a fake activity port for this suite.
        --@param handle table|integer Fake resource handle whose state is inspected.
        --@return string text Text emitted by the scenario callback.
        finish = function(handle)
            A.equal(handle, active_operation)
            active_operation = false
            return "result-durable"
        end,
        --Simulates the status transition of a fake activity port for this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return table record Fixture record emitted by the scenario callback.
        status = function() return { blocked = false, auto_replay = false } end,
    }
    local service = assert(load_module("tools", modules).new({
        filesystem = filesystem,
        path = paths,
        safety = safety,
        secret_registry = false,
        authorization = authority,
        processes = false,
        operations = operations,
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
        maximum_exec_output_bytes = 4096,
        maximum_exec_deadline_ms = 60000,
        platform_kind = "posix",
        workspace_path = "/work",
        reserved_paths = { "/reserved" },
    }))
    return service, controls
end

--Simulates the admit port for this suite.
--@param service table Service port exercised by the case.
--@param tool table|string Tool selected for this scenario.
--@param arguments table Argument vector delivered to the fake process.
--@param id string|integer Identity selected for the fake operation.
--@return any observed admit value observed by the scenario assertion.
--@return any secondary2 Authorization token returned by the fixture.
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
    if call.mutates or call.tool == "exec" then assert(service:begin_operation(call)) end
    local token = assert(service:authorize(call, {
        permission_snapshot_digest = "permission-v1",
        approval_digest = "approval-v1",
        config_generation = "generation-1",
        workspace_identity = action.workspace_root_identity,
        double_check = true,
        action_review = "approved",
    }))
    return call, token
end

--Supplies operation count behavior required by this suite.
--@param controls any The controls supplied to the fake service for this scenario.
--@param prefix string Prefix added to the generated fixture value.
--@return any observed operation count value observed by the scenario assertion.
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
            --Verifies read identity replacement after approval fails before verified open.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify read identity replacement after approval fails before verified open.
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
            --Verifies read identity replacement after approval fails before verified open.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify read identity replacement after approval fails before verified open.
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
            --Verifies rename source target and delete races never touch substitutes.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify rename source target and delete races never touch substitutes.
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
            --Verifies reserved-root identity and incomplete ancestry fail closed.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify reserved-root identity and incomplete ancestry fail closed.
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
            --Verifies continuation generation changes are stale and never mix views.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify continuation generation changes are stale and never mix views.
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
            --Verifies uncertain publish and durability windows report unknown without replay.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify uncertain publish and durability windows report unknown without replay.
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
                A.truthy(controls.exists(
                    "/work/a.txt.yaca-operation-replace-unknown.tmp"
                ))
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
        {
            name = "created file write failure cannot clean up a foreign replacement",
            -- Replace the direct path while its original create handle remains open.
            --@param none No arguments.
            --@return nil Assertions complete without returning a value.
            --@effect Uses an isolated direct filesystem and an injected native write failure.
            run = function()
                -- Intercept only the new file's write after direct_create_new has returned its handle.
                --@param native table Mutable native port assembled by the fixture.
                --@param controls table Fixture operations for replacing the created pathname.
                --@return nil Native write hook is installed in place.
                --@effect Replaces native.fs_write for this isolated service.
                local service, controls = setup(function(native, controls)
                    local original_write = native.fs_write
                    -- Simulate a different actor replacing the path before write reports failure.
                    --@param handle table Original create handle retained by the native fixture.
                    --@param bytes string Candidate write chunk rejected for the new file.
                    --@return boolean False on the injected failure, or the original port's status for other files.
                    --@return any InjectedWrite error or the original port's result.
                    --@effect Replaces /work/new.txt with a foreign fixture file on its first write.
                    native.fs_write = function(handle, bytes)
                        if handle.path == "/work/new.txt" then
                            controls.external_replace(handle.path, "foreign\n")
                            return false, { code = "InjectedWrite", message = "fixture write failure" }
                        end
                        return original_write(handle, bytes)
                    end
                end)
                local _, token = admit(service, "write", {
                    path = "/work/new.txt", mode = "create", content = "candidate\n",
                    encoding = "utf-8", newline_policy = "preserve",
                }, "create-cleanup-race")
                local result = assert(service:execute(token))
                A.equal(result.outcome, "unknown")
                A.equal(result.error.code, "PublicationUnknown")
                A.equal(controls.bytes("/work/new.txt"), "foreign\n")
                A.equal(operation_count(controls, "delete-verified:/work/new.txt"), 0)
            end,
        },
        {
            name = "same-byte direct creation replacement fails before verified readback",
            -- Keep the bytes identical while swapping the object immediately before direct inspection.
            --@param none No arguments.
            --@return nil Assertions complete without returning a value.
            --@effect Uses an isolated direct filesystem with one injected path replacement.
            run = function()
                -- Replace only the first post-create inspection of the newly written path.
                --@param native table Mutable native port assembled by the fixture.
                --@param controls table Fixture operations for replacing a path with identical bytes.
                --@return nil Native inspection hook is installed in place.
                --@effect Replaces native.fs_inspect_direct for this isolated service.
                local service, controls = setup(function(native, controls)
                    local original_inspect = native.fs_inspect_direct
                    local swapped = false
                    -- Return the actual foreign snapshot once the newly created file exists.
                    --@param path string Direct-inspection target path.
                    --@return boolean Original port's inspection status.
                    --@return table Original port's inspected snapshot or error.
                    --@effect Replaces the created file once with a same-byte foreign object before inspection.
                    native.fs_inspect_direct = function(path)
                        if path == "/work/new.txt" and controls.exists(path) and not swapped then
                            swapped = true
                            controls.external_replace(path, controls.bytes(path))
                        end
                        return original_inspect(path)
                    end
                end)
                local _, token = admit(service, "write", {
                    path = "/work/new.txt", mode = "create", content = "candidate\n",
                    encoding = "utf-8", newline_policy = "preserve",
                }, "create-readback-race")
                local result = assert(service:execute(token))
                A.equal(result.outcome, "unknown")
                A.equal(result.error.code, "PublicationUnknown")
                A.equal(controls.bytes("/work/new.txt"), "candidate\n")
                A.equal(operation_count(controls, "open-verified:/work/new.txt"), 0)
                A.equal(operation_count(controls, "delete-verified:/work/new.txt"), 0)
            end,
        },
        {
            name = "changed physical ancestor rejects direct readback and cleanup",
            -- Keep leaf and parent IDs stable while replacing their grandparent during publication.
            --@param none No arguments.
            --@return nil Assertions complete without returning a value.
            --@effect Uses an isolated direct filesystem with an injected ancestor replacement.
            run = function()
                -- Change the root object on the first inspection after the created leaf appears.
                --@param native table Mutable native port assembled by the fixture.
                --@param controls table Fixture operations for replacing the ancestor object.
                --@return nil Native inspection hook is installed in place.
                --@effect Replaces native.fs_inspect_direct for this isolated service.
                local service, controls = setup(function(native, controls)
                    local original_inspect = native.fs_inspect_direct
                    local swapped = false
                    -- Expose the changed root in the leaf's otherwise unchanged physical ancestry.
                    --@param path string Direct-inspection target path.
                    --@return boolean Original port's inspection status.
                    --@return table Original port's inspected snapshot or error.
                    --@effect Replaces the fixture root object once after /work/new.txt exists.
                    native.fs_inspect_direct = function(path)
                        if path == "/work/new.txt" and controls.exists(path) and not swapped then
                            swapped = true
                            controls.external_replace("/", "foreign root")
                        end
                        return original_inspect(path)
                    end
                end)
                local _, token = admit(service, "write", {
                    path = "/work/new.txt", mode = "create", content = "candidate\n",
                    encoding = "utf-8", newline_policy = "preserve",
                }, "create-ancestry-race")
                local result = assert(service:execute(token))
                A.equal(result.outcome, "unknown")
                A.equal(result.error.code, "PublicationUnknown")
                A.equal(controls.bytes("/"), "foreign root")
                A.equal(controls.bytes("/work/new.txt"), "candidate\n")
                A.equal(operation_count(controls, "delete-verified:/work/new.txt"), 0)
            end,
        },
        {
            name = "failed direct replacement leaves a substituted temporary untouched",
            -- Replace the fully verified temporary immediately before the verified native replace.
            --@param none No arguments.
            --@return nil Assertions complete without returning a value.
            --@effect Uses an isolated direct filesystem with one injected replacement failure.
            run = function()
                -- Install an operation that swaps the temporary path but declines publication.
                --@param native table Mutable native port assembled by the fixture.
                --@param controls table Fixture operations for replacing the temporary path.
                --@return nil Native replacement hook is installed in place.
                --@effect Replaces native.fs_replace_verified for this isolated service.
                local service, controls = setup(function(native, controls)
                    -- Leave the original target intact and put a foreign file at the temporary path.
                    --@param temporary string Absolute verified temporary path from the direct filesystem.
                    --@param target string Absolute original target path; it remains unchanged.
                    --@param expected_temporary table Identity the direct filesystem expected to publish.
                    --@param expected_target table Identity the direct filesystem expected to replace.
                    --@param expected_parent table Parent identity the direct filesystem verified.
                    --@param expected_behavior_digest string Behavior predicate expected of the original target.
                    --@return boolean False because publication is deliberately rejected.
                    --@return table TargetChanged diagnostic caused by the injected replacement.
                    --@effect Replaces only the temporary path with a foreign fixture file.
                    native.fs_replace_verified = function(
                        temporary, target, expected_temporary, expected_target,
                        expected_parent, expected_behavior_digest
                    )
                        A.equal(target, "/work/a.txt")
                        A.truthy(expected_temporary)
                        A.truthy(expected_target)
                        A.truthy(expected_parent)
                        A.truthy(expected_behavior_digest)
                        controls.external_replace(temporary, "foreign temporary\n")
                        return false, { code = "TargetChanged", message = "fixture replacement race" }
                    end
                end)
                local _, token = admit(service, "write", {
                    path = "/work/a.txt", mode = "replace", content = "candidate\n",
                    encoding = "utf-8", newline_policy = "preserve",
                    expected_identity = controls.identity("/work/a.txt"),
                    expected_raw_digest = sha256.hex("old\n"),
                }, "replace-cleanup-race")
                local result = assert(service:execute(token))
                local temporary = "/work/a.txt.yaca-operation-replace-cleanup-race.tmp"
                A.equal(result.outcome, "unknown")
                A.equal(result.error.code, "PublicationUnknown")
                A.equal(controls.bytes("/work/a.txt"), "old\n")
                A.equal(controls.bytes(temporary), "foreign temporary\n")
                A.equal(operation_count(controls, "delete-verified:" .. temporary), 0)
            end,
        },
    },
}
