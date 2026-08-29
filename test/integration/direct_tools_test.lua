--[[
File: direct_tools_test.lua
Date: 2026-08-29
Author: WaterRun
Description: Verifies the closed registry and all seven direct tool contracts.
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
    local chunk, load_error = loadfile(YACA_TEST_ROOT .. "/src/" .. name .. ".lua", "t", environment)
    A.truthy(chunk, load_error)
    local result = chunk()
    cache[name] = result
    return result
end

local array_marks = setmetatable({}, { __mode = "k" })

local function arr(values)
    array_marks[values] = true
    return values
end

local function escape(value)
    return '"' .. value:gsub("[\\\"\0-\31]", function(character)
        local mappings = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
        return mappings[character] or string.format("\\u%04x", character:byte())
    end) .. '"'
end

local function encode(value)
    if type(value) == "string" then return escape(value) end
    if type(value) == "boolean" then return value and "true" or "false" end
    if math.type(value) == "integer" then return tostring(value) end
    A.type(value, "table")
    local output = {}
    if array_marks[value] then
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
        sha256_start = function() return { parts = {}, closed = false } end,
        sha256_update = function(handle, bytes)
            handle.parts[#handle.parts + 1] = bytes
            return true
        end,
        sha256_finish = function(handle) return sha256.digest(table.concat(handle.parts)) end,
        sha256_close = function(handle) handle.closed = true; return true end,
    }
end

local function options(overrides)
    local result = {
        maximum_argument_bytes = 65536,
        maximum_path_bytes = 1024,
        maximum_content_bytes = 32768,
        maximum_file_bytes = 32768,
        maximum_result_bytes = 65536,
        maximum_list_depth = 8,
        maximum_page_entries = 16,
        maximum_walk_entries = 128,
        maximum_search_pattern_bytes = 256,
        maximum_search_matches = 64,
        maximum_patch_hunks = 16,
        maximum_patch_lines = 128,
        maximum_line_bytes = 4096,
        maximum_continuations = 8,
        maximum_identifier_bytes = 128,
        filesystem_chunk_bytes = 7,
        create_permissions = 384,
        maximum_json_depth = 24,
        maximum_json_nodes = 4096,
        maximum_number_bytes = 32,
        maximum_exec_output_bytes = 8192,
        maximum_exec_deadline_ms = 60000,
        platform_kind = "posix",
        workspace_path = "/work",
        reserved_paths = { "/reserved" },
    }
    for key, value in pairs(overrides or {}) do result[key] = value end
    return result
end

local function fixture(settings)
    settings = settings or {}
    local initial = {
        ["/work"] = { kind = "directory" },
        ["/work/a.txt"] = "alpha\nbeta\n",
        ["/work/sub"] = { kind = "directory" },
        ["/work/sub/b.txt"] = "Alpha beta\r\ngamma\r\n",
        ["/work/binary.bin"] = "A\0B",
        ["/reserved"] = { kind = "directory" },
        ["/reserved/config.ini"] = "Key=secret",
    }
    for path, value in pairs(settings.initial or {}) do initial[path] = value end
    local native, controls = direct_harness.new(initial)
    local modules = {}
    local filesystem = assert(load_module("fs", modules).new(native, {
        maximum_chunk_bytes = 7,
        maximum_lease_bytes = 256,
        maximum_direct_entries = 128,
    }))
    local port = hash_port()
    local paths = assert(load_module("path", modules).new(port, {
        maximum_path_bytes = 1024,
        maximum_segments = 64,
        maximum_segment_bytes = 255,
        maximum_hash_chunk_bytes = 11,
    }))
    local safety = assert(load_module("safety", modules).new(port, {
        maximum_hash_chunk_bytes = 11,
        minimum_scannable_secret_bytes = 8,
    }))
    local secrets = false
    if settings.secret then
        secrets = assert(safety.secret_registry({ {
            id = "provider-key",
            class = "credential",
            value = settings.secret,
            destinations = { "curl-config-stdin" },
        } }))
    end
    local authorization_controls = { current = true, admits = 0, reverifies = 0 }
    local authorization = {
        admit = function(call)
            authorization_controls.admits = authorization_controls.admits + 1
            if not authorization_controls.current then return false end
            return true, "authority-" .. call.call_digest
        end,
        reverify = function(call, _, digest)
            authorization_controls.reverifies = authorization_controls.reverifies + 1
            return authorization_controls.current
                and digest == "authority-" .. call.call_digest
        end,
    }
    local operation_controls = { intents = {}, results = {}, active = false }
    local operations = {
        begin = function(intent)
            A.falsy(operation_controls.active)
            local handle = {}
            operation_controls.active = handle
            operation_controls.intents[#operation_controls.intents + 1] = intent
            return handle, "intent-" .. intent.operation_id
        end,
        finish = function(handle, result)
            A.equal(handle, operation_controls.active)
            operation_controls.results[#operation_controls.results + 1] = result
            operation_controls.active = false
            return "result-" .. tostring(#operation_controls.results)
        end,
        status = function()
            return { blocked = false, active_operation_id = false, auto_replay = false }
        end,
    }
    local tools = assert(load_module("tools", modules).new({
        filesystem = filesystem,
        path = paths,
        safety = safety,
        secret_registry = secrets,
        authorization = authorization,
        processes = false,
        operations = operations,
    }, options(settings.options)))
    return tools, controls, authorization_controls, {
        modules = modules,
        safety = safety,
        filesystem = filesystem,
        operations = operation_controls,
    }
end

local function call(service, tool, arguments, suffix)
    suffix = suffix or tool
    return service:admit_call({
        tool = tool,
        schema_version = service.schema_version,
        registry_digest = service.registry_digest,
        provider_call_id = "provider-" .. suffix,
        tool_call_id = "call-" .. suffix,
        operation_id = "operation-" .. suffix,
        canonical_arguments = encode(arguments),
    })
end

local function authorize(service, admitted)
    local action = assert(service:permission_action(admitted))
    if admitted.mutates or admitted.tool == "exec" then
        assert(service:begin_operation(admitted))
    end
    return assert(service:authorize(admitted, {
        permission_snapshot_digest = "permission-v1",
        approval_digest = "",
        config_generation = "generation-1",
        workspace_identity = action.workspace_root_identity,
        double_check = false,
        action_review = "not-required",
    }))
end

local function run(service, tool, arguments, suffix)
    local admitted, admission_error = call(service, tool, arguments, suffix)
    A.truthy(admitted, admission_error and admission_error.code)
    return assert(service:execute(authorize(service, admitted))), admitted
end

local function identity(controls, path)
    return assert(controls.identity(path))
end

return {
    name = "integration/direct-tools",
    cases = {
        {
            name = "registry is exactly eight versioned tools and non-main purposes are empty",
            run = function()
                local service = fixture()
                local main = assert(service:registry_for("main"))
                local names = {}
                for index, tool in ipairs(main.tools) do
                    names[index] = tool.name
                    A.equal(tool.schema.additionalProperties, false)
                end
                A.deep_equal(names, {
                    "list", "read", "search", "write", "patch", "rename", "delete", "exec",
                })
                A.equal(main.digest, service.registry_digest)
                A.equal(#assert(service:registry_for("side")).tools, 0)
                A.falsy(assert(service:registry_for("side")).digest == main.digest)
                A.raises(function() main.tools[1].name = "http" end, "cannot be modified")

                local result = run(service, "exec", { command = "echo opaque" }, "exec")
                A.equal(result.outcome, "failed")
                A.equal(result.error.code, "ExecUnavailable")
            end,
        },
        {
            name = "exact registry schemas project through both provider adapters",
            run = function()
                local tools, _, _, context = fixture()
                local prompt_module = load_module("prompt", context.modules)
                local prompt = assert(prompt_module.new({ digest = context.safety.digest }, {
                    maximum_component_bytes = 32768,
                    maximum_quoted_bytes = 16384,
                    maximum_total_bytes = 131072,
                    maximum_estimated_tokens = 131072,
                    maximum_components = 16,
                    maximum_source_bytes = 256,
                    maximum_version_bytes = 256,
                }))
                local bundle = assert(prompt:assemble({
                    purpose = "main",
                    config_generation = "generation-1",
                    tool_mode = "registered",
                    layers = {
                        global = { source = "General.SystemPrompt", version = "g1", text = "" },
                        model = { source = "Model.Test.SystemPrompt", version = "g1", text = "" },
                        permission = {
                            source = "Permission.Std.SystemPrompt", version = "g1", text = "",
                        },
                        context = { source = "ContextPrompt", version = "g1", text = "" },
                    },
                    input = { user_message = "inspect the workspace" },
                }))
                local model = assert(load_module("model", context.modules).new({
                    maximum_json_bytes = 131072,
                    maximum_json_depth = 32,
                    maximum_json_nodes = 8192,
                    maximum_string_bytes = 65536,
                    maximum_number_bytes = 32,
                    maximum_sse_line_bytes = 8192,
                    maximum_sse_event_bytes = 16384,
                    maximum_sse_buffered_bytes = 32768,
                    maximum_sse_events_per_push = 128,
                    maximum_response_bytes = 131072,
                    maximum_text_bytes = 65536,
                    maximum_reasoning_bytes = 8192,
                    maximum_tool_calls = 16,
                    maximum_tool_argument_bytes = 32768,
                    maximum_total_tool_argument_bytes = 65536,
                    maximum_content_blocks = 64,
                    maximum_events = 256,
                }))
                for _, protocol in ipairs({ "openai-chat", "anthropic-messages" }) do
                    local request = assert(model:normalize_request({
                        request_id = "request-" .. protocol,
                        purpose = "main",
                        model_ref = {
                            name = "Test",
                            protocol = protocol,
                            endpoint = protocol == "openai-chat"
                                and "https://api.example/v1/chat/completions"
                                or "https://api.example/v1/messages",
                            remote_model = "model-test",
                            capabilities_digest = "capabilities-1",
                        },
                        config_generation = "generation-1",
                        prompt_bundle = bundle,
                        model_view_manifest = { digest = "view-1" },
                        tool_registry = assert(tools:registry_for("main")),
                        controls_schema = bundle.controls_schema,
                        streaming = "force",
                        limits = protocol == "anthropic-messages"
                            and { max_output_tokens = 64 } or {},
                        retry_policy = { count = 0, base_delay_ms = 1 },
                    }))
                    local body = assert(model:encode(request)).body
                    for _, name in ipairs(tools.tool_names) do
                        A.contains(body, '"name":"' .. name .. '"', protocol .. "/" .. name)
                    end
                    A.falsy(body:find('"name":"http"', 1, true))
                    A.contains(body, '"additionalProperties":false')
                end
            end,
        },
        {
            name = "list read and search are stable bounded typed results with continuation",
            run = function()
                local service, controls, _, context = fixture()
                local inspected, snapshot = context.filesystem.direct_inspect(
                    "/work/sub/b.txt"
                )
                A.truthy(inspected)
                A.equal(#snapshot.ancestors, 3)
                A.raises(function() snapshot.ancestors[1] = false end, "cannot be modified")
                local workspace_ok, workspace = context.filesystem.direct_inspect("/work")
                A.truthy(workspace_ok)
                local walked, raw_walk = context.filesystem.direct_walk(workspace, 2, 8)
                A.truthy(walked)
                A.equal(#raw_walk.entries, 4)
                A.raises(function() raw_walk.entries[1] = false end, "cannot be modified")
                local first = run(service, "list", {
                    path = "/work", depth = 2, page_size = 2,
                }, "list-1")
                A.equal(first.outcome, "success", first.error and (
                    first.error.code .. ":" .. first.error.message .. ":" .. tostring(first.error.detail)
                ))
                A.equal(#first.payload.entries, 2)
                A.truthy(first.payload.continuation)
                A.equal(controls.last_ignore_policy, "git-compatible-v1")
                local second = run(service, "list", {
                    path = "/work", depth = 2, page_size = 16,
                    continuation = first.payload.continuation,
                }, "list-2")
                A.equal(second.outcome, "success")
                A.equal(second.payload.continuation, false)
                A.truthy(second.payload.complete)

                local read = run(service, "read", {
                    path = "/work/a.txt", start_line = 2, max_lines = 1,
                }, "read")
                A.equal(read.payload.classification, "text")
                A.equal(read.payload.encoding, "utf-8")
                A.equal(read.payload.lines[1].number, 2)
                A.equal(read.payload.lines[1].text, "beta")
                A.equal(read.payload.lines[1].newline, "lf")
                A.truthy(read.payload.eof)

                local search = run(service, "search", {
                    path = "/work", pattern = "alpha", dialect = "literal",
                    case_sensitive = false, page_size = 1,
                }, "search-1")
                A.equal(#search.payload.matches, 1)
                A.equal(search.payload.matches[1].file, "a.txt")
                A.truthy(search.payload.continuation)
                local search_tail = run(service, "search", {
                    path = "/work", pattern = "alpha", dialect = "literal",
                    case_sensitive = false, page_size = 4,
                    continuation = search.payload.continuation,
                }, "search-2")
                A.equal(search_tail.payload.matches[1].file, "sub/b.txt")
                A.equal(search_tail.payload.continuation, false)

                controls.add("/work/unicode", "directory", "")
                controls.add("/work/unicode/u.txt", "file", "你a\n")
                local pattern = run(service, "search", {
                    path = "/work/unicode", pattern = ".", dialect = "lua-pattern-v1",
                    case_sensitive = true, page_size = 8,
                }, "search-pattern")
                A.equal(pattern.outcome, "success")
                -- lua-pattern-v1 is the explicitly registered Lua byte-pattern
                -- dialect, but only scalar-boundary matches may be retained.
                A.equal(#pattern.payload.matches, 1)
                A.equal(pattern.payload.matches[1].column, 2)
            end,
        },
        {
            name = "read preserves UTF BOM newline spans and classifies binary without body",
            run = function()
                local utf16 = "\255\254A\0\r\0\n\0B\0"
                local service = fixture({ initial = { ["/work/utf16.txt"] = utf16 } })
                local read = run(service, "read", {
                    path = "/work/utf16.txt", start_line = 1, max_lines = 8,
                }, "utf16")
                A.truthy(read.payload, read.error and read.error.detail)
                A.equal(read.payload.encoding, "utf-16le-bom")
                A.equal(read.payload.newline, "crlf")
                A.equal(read.payload.lines[1].raw_start, 2)
                A.equal(read.payload.lines[1].raw_end, 8)
                A.equal(read.payload.lines[2].text, "B")
                local binary = run(service, "read", {
                    path = "/work/binary.bin", start_line = 1, max_lines = 8,
                }, "binary")
                A.equal(binary.payload.classification, "binary-content")
                A.equal(#binary.payload.lines, 0)
                A.equal(binary.payload.raw_size, 3)
            end,
        },
        {
            name = "write create and replace use no-replace expected digest and metadata-safe publish",
            run = function()
                local service, controls = fixture()
                local created = run(service, "write", {
                    path = "/work/new.txt", mode = "create", content = "one\ntwo\n",
                    encoding = "utf-8", newline_policy = "preserve",
                }, "write-create")
                A.equal(created.outcome, "success", created.error and created.error.detail)
                A.equal(controls.bytes("/work/new.txt"), "one\ntwo\n")
                A.falsy(call(service, "write", {
                    path = "/work/new.txt", mode = "create", content = "lost",
                    encoding = "utf-8", newline_policy = "preserve",
                }, "write-conflict"))

                local old = controls.bytes("/work/a.txt")
                local replaced = run(service, "write", {
                    path = "/work/a.txt", mode = "replace", content = "alpha\nchanged\n",
                    encoding = "utf-8", newline_policy = "preserve",
                    expected_identity = identity(controls, "/work/a.txt"),
                    expected_raw_digest = sha256.hex(old),
                }, "write-replace")
                A.equal(replaced.outcome, "success")
                A.equal(controls.bytes("/work/a.txt"), "alpha\nchanged\n")
                A.equal(replaced.payload.old_digest, sha256.hex(old))
                A.equal(replaced.payload.new_digest, sha256.hex("alpha\nchanged\n"))
            end,
        },
        {
            name = "structured patch validates every context before one publication",
            run = function()
                local service, controls = fixture()
                local before = controls.bytes("/work/sub/b.txt")
                local bad = run(service, "patch", {
                    path = "/work/sub/b.txt",
                    expected_identity = identity(controls, "/work/sub/b.txt"),
                    expected_raw_digest = sha256.hex(before),
                    hunks = arr({ {
                        start_line = 2,
                        context_before = arr({ "wrong" }),
                        delete_lines = arr({ "gamma" }),
                        insert_lines = arr({ "delta" }),
                        context_after = arr({}),
                        newline = "crlf",
                        final_newline = true,
                    } }),
                }, "patch-bad")
                A.equal(bad.outcome, "failed", bad.error and bad.error.detail)
                A.equal(bad.error.code, "PatchConflict")
                A.equal(controls.bytes("/work/sub/b.txt"), before)

                local good = run(service, "patch", {
                    path = "/work/sub/b.txt",
                    expected_identity = identity(controls, "/work/sub/b.txt"),
                    expected_raw_digest = sha256.hex(before),
                    hunks = arr({ {
                        start_line = 2,
                        context_before = arr({ "Alpha beta" }),
                        delete_lines = arr({ "gamma" }),
                        insert_lines = arr({ "delta", "omega" }),
                        context_after = arr({}),
                        newline = "crlf",
                        final_newline = true,
                    } }),
                }, "patch-good")
                A.equal(good.outcome, "success")
                A.equal(controls.bytes("/work/sub/b.txt"), "Alpha beta\r\ndelta\r\nomega\r\n")
            end,
        },
        {
            name = "rename never clobbers or copies and delete only removes one exact target",
            run = function()
                local service, controls = fixture()
                controls.faults.rename = "EXDEV"
                local cross = run(service, "rename", {
                    source = "/work/a.txt", target = "/work/moved.txt",
                    expected_identity = identity(controls, "/work/a.txt"),
                    expected_raw_digest = sha256.hex(controls.bytes("/work/a.txt")),
                }, "rename-cross")
                A.equal(cross.error.code, "CrossDeviceRenameUnsupported", cross.error.detail)
                A.truthy(controls.exists("/work/a.txt"))
                A.falsy(controls.exists("/work/moved.txt"))
                controls.faults.rename = nil
                local renamed = run(service, "rename", {
                    source = "/work/a.txt", target = "/work/moved.txt",
                    expected_identity = identity(controls, "/work/a.txt"),
                    expected_raw_digest = sha256.hex(controls.bytes("/work/a.txt")),
                }, "rename-good")
                A.equal(renamed.outcome, "success")
                A.falsy(controls.exists("/work/a.txt"))
                A.truthy(controls.exists("/work/moved.txt"))
                local deleted = run(service, "delete", {
                    path = "/work/moved.txt",
                    expected_identity = identity(controls, "/work/moved.txt"),
                    expected_raw_digest = sha256.hex(controls.bytes("/work/moved.txt")),
                }, "delete-file")
                A.equal(deleted.outcome, "success")
                A.falsy(controls.exists("/work/moved.txt"))

                local nonempty = run(service, "delete", {
                    path = "/work/sub",
                    expected_identity = identity(controls, "/work/sub"),
                    expected_raw_digest = "",
                }, "delete-nonempty")
                A.equal(nonempty.outcome, "failed")
                A.equal(nonempty.error.code, "DirectoryNotEmpty",
                    nonempty.error.code .. ":" .. nonempty.error.message .. ":"
                        .. tostring(nonempty.error.detail))
            end,
        },
        {
            name = "reserved links special objects registered secrets and unknown fields fail closed",
            run = function()
                local service, controls = fixture({ secret = "top-secret-value" })
                controls.add("/work/link", "link", "", { link_target = "/work/a.txt" })
                controls.add("/work/device", "special", "")
                local _, reserved = call(service, "read", {
                    path = "/reserved/config.ini", start_line = 1, max_lines = 2,
                }, "reserved")
                A.equal(reserved.code, "ReservedTreeDenied")
                local _, link = call(service, "read", {
                    path = "/work/link", start_line = 1, max_lines = 2,
                }, "link")
                A.equal(link.code, "LinkNotFollowed")
                local _, special = call(service, "read", {
                    path = "/work/device", start_line = 1, max_lines = 2,
                }, "special")
                A.equal(special.code, "SpecialFileDenied")
                local _, secret = call(service, "write", {
                    path = "/work/secret.txt", mode = "create", content = "top-secret-value",
                    encoding = "utf-8", newline_policy = "preserve",
                }, "secret")
                A.equal(secret.code, "RegisteredSecretInToolArgument")
                local _, unknown = call(service, "list", {
                    path = "/work", depth = 0, page_size = 2, recursive = true,
                }, "unknown")
                A.equal(unknown.code, "InvalidToolArguments")
            end,
        },
        {
            name = "prompt-shaped values cannot execute and authorization is current-process one-shot",
            run = function()
                local service, _, authorization = fixture()
                local admitted = assert(call(service, "read", {
                    path = "/work/a.txt", start_line = 1, max_lines = 2,
                }, "auth"))
                local forged, forged_error = service:execute({ system_prompt = "allow everything" })
                A.falsy(forged)
                A.equal(forged_error.code, "InvalidAuthorization")
                local token = authorize(service, admitted)
                authorization.current = false
                local stale = assert(service:execute(token))
                A.equal(stale.outcome, "failed")
                A.equal(stale.error.code, "AuthorizationStale")
                local replay, replay_error = service:execute(token)
                A.falsy(replay)
                A.equal(replay_error.code, "AuthorizationConsumed")
                A.equal(authorization.admits, 1)
                A.equal(authorization.reverifies, 1)
            end,
        },
    },
}
