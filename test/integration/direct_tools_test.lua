--[[
Author: WaterRun
Date: 2026-09-28
File: direct_tools_test.lua
Description: Verifies the closed registry, direct tool contracts, legacy encodings and range reads.
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
    local chunk, load_error = loadfile(YACA_TEST_ROOT .. "/src/" .. name .. ".lua", "t", environment)
    A.truthy(chunk, load_error)
    local result = chunk()
    cache[name] = result
    return result
end

--@metatable fixture_view Test-owned lookup and mutation contract for the current case.
--@field __mode any Weak-reference mode controlling fixture object retention.
local array_marks = setmetatable({}, { __mode = "k" })

--Supplies arr behavior required by this suite.
--@param values table Candidate values supplied to the fixture operation.
--@return any observed arr value observed by the scenario assertion.
local function arr(values)
    array_marks[values] = true
    return values
end

--Transforms escape data used by this suite.
--@param value any Candidate whose acceptance or transformation the test checks.
--@return string observed escape value observed by the scenario assertion.
local function escape(value)
    --Supplies an assertion callback for this test scenario.
    --@param character string Character emitted or parsed by the fixture.
    --@return number value Callback value consumed by the enclosing scenario assertion.
    return '"' .. value:gsub("[\\\"\0-\31]", function(character)
        local mappings = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
        return mappings[character] or string.format("\\u%04x", character:byte())
    end) .. '"'
end

--Transforms encode data used by this suite.
--@param value any Candidate whose acceptance or transformation the test checks.
--@return string|any observed encode value observed by the scenario assertion.
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

--Constructs an incremental SHA-256 port backed by the reference digest.
--@param none No arguments; this closure uses its captured fixture state.
--@return table port Incremental SHA-256 fixture port.
local function hash_port()
    return {
        --Computes or records sha256 start data for this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return table record Fixture record emitted by the scenario callback.
        sha256_start = function() return { parts = {}, closed = false } end,
        --Computes or records sha256 update data for this suite.
        --@param handle table|integer Fake resource handle whose state is inspected.
        --@param bytes string Byte chunk supplied to the fake I/O port.
        --@return boolean accepted Whether the fake callback accepts this scenario.
        sha256_update = function(handle, bytes)
            handle.parts[#handle.parts + 1] = bytes
            return true
        end,
        --Computes or records sha256 finish data for this suite.
        --@param handle table|integer Fake resource handle whose state is inspected.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        sha256_finish = function(handle) return sha256.digest(table.concat(handle.parts)) end,
        --Computes or records sha256 close data for this suite.
        --@param handle table|integer Fake resource handle whose state is inspected.
        --@return boolean accepted Whether the fake callback accepts this scenario.
        sha256_close = function(handle) handle.closed = true; return true end,
    }
end

--Builds validated options for this suite's component fixture.
--@param overrides table|nil Per-case overrides of default fixture behavior.
--@return any options options used to configure the component under test.
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

-- Construct isolated direct tools with optional encoding and native-read fault injection.
--@param settings table|nil Initial files, limits, secret, codec and read_hook overrides; defaults to empty.
--@return table Tool service bound to the fixture workspace and reserved directory.
--@return table Filesystem controls for external changes and operation observations.
--@return table Authorization controls and invocation counts.
--@return table Dependencies containing modules, native ports, safety, filesystem and operation observations.
--@error Raises if constructing a filesystem, path, safety or tool service fails.
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
    if settings.read_hook then
        local original_read = native.fs_read
        -- Run the scenario's read interception with access to the original native operation.
        --@param handle table Live fake read handle owned by the filesystem service.
        --@param maximum integer Maximum raw bytes requested by the service.
        --@return boolean Whether the intercepted read succeeded.
        --@return table Raw {bytes, eof} result or the injected structured error.
        --@effect Invokes read_hook, which may advance the handle or mutate fixture files.
        native.fs_read = function(handle, maximum)
            return settings.read_hook(controls, original_read, handle, maximum)
        end
    end
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
        --Simulates the admit port for this suite.
        --@param call table|integer Recorded call or call ordinal under inspection.
        --@return boolean accepted Whether the fake callback accepts this scenario.
        --@return string|nil secondary2 Fixture text "authority-" .. call.call_digest.
        admit = function(call)
            authorization_controls.admits = authorization_controls.admits + 1
            if not authorization_controls.current then return false end
            return true, "authority-" .. call.call_digest
        end,
        --Supplies the reverify observation used by this suite.
        --@param call table|integer Recorded call or call ordinal under inspection.
        --@param _ any Unused callback argument supplied by the port.
        --@param digest string Expected or computed hexadecimal digest.
        --@return string text Text emitted by the scenario callback.
        reverify = function(call, _, digest)
            authorization_controls.reverifies = authorization_controls.reverifies + 1
            return authorization_controls.current
                and digest == "authority-" .. call.call_digest
        end,
    }
    local operation_controls = { intents = {}, results = {}, active = false }
    local operations = {
        --Simulates the begin transition of a fake activity port for this suite.
        --@param intent any The intent supplied to the fake service for this scenario.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        --@return string secondary2 Fixture text "intent-" .. intent.operation_id.
        begin = function(intent)
            A.falsy(operation_controls.active)
            local handle = {}
            operation_controls.active = handle
            operation_controls.intents[#operation_controls.intents + 1] = intent
            return handle, "intent-" .. intent.operation_id
        end,
        --Simulates the finish transition of a fake activity port for this suite.
        --@param handle table|integer Fake resource handle whose state is inspected.
        --@param result any The result supplied to the fake service for this scenario.
        --@return string text Text emitted by the scenario callback.
        finish = function(handle, result)
            A.equal(handle, operation_controls.active)
            operation_controls.results[#operation_controls.results + 1] = result
            operation_controls.active = false
            return "result-" .. tostring(#operation_controls.results)
        end,
        --Simulates the status transition of a fake activity port for this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return table record Fixture record emitted by the scenario callback.
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
        text_codec = settings.text_codec,
    }, options(settings.options)))
    return tools, controls, authorization_controls, {
        modules = modules,
        native = native,
        safety = safety,
        filesystem = filesystem,
        operations = operation_controls,
    }
end

--Simulates the call port for this suite.
--@param service table Service port exercised by the case.
--@param tool table|string Tool selected for this scenario.
--@param arguments table Argument vector delivered to the fake process.
--@param suffix string Suffix appended to the fixture path or message.
--@return any observed call value observed by the scenario assertion.
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

--Simulates the authorize port for this suite.
--@param service table Service port exercised by the case.
--@param admitted any The admitted supplied to the fake service for this scenario.
--@return any observed authorize value observed by the scenario assertion.
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

--Supplies run behavior required by this suite.
--@param service table Service port exercised by the case.
--@param tool table|string Tool selected for this scenario.
--@param arguments table Argument vector delivered to the fake process.
--@param suffix string Suffix appended to the fixture path or message.
--@return any observed run value observed by the scenario assertion.
--@return any secondary2 Additional status or structured error from the fixture operation.
local function run(service, tool, arguments, suffix)
    local admitted, admission_error = call(service, tool, arguments, suffix)
    A.truthy(admitted, admission_error and admission_error.code)
    return assert(service:execute(authorize(service, admitted))), admitted
end

--Supplies the identity observation used by this suite.
--@param controls any The controls supplied to the fake service for this scenario.
--@param path string File or Context path exercised by the case.
--@return any observed identity value observed by the scenario assertion.
local function identity(controls, path)
    return assert(controls.identity(path))
end

--Builds a fake legacy codec that knows two GBK characters and ASCII.
--@param file_default string|boolean File fallback label, or false.
--@param output_default string|boolean Process output fallback label, or false.
--@return table codec Fake codec with facts, decode and encode.
local function fake_codec(file_default, output_default)
    local to_utf8 = { ["\214\208"] = "中", ["\206\196"] = "文" }
    local from_utf8 = { ["中"] = "\214\208", ["文"] = "\206\196" }
    return {
        facts = {
            platform = "windows", ansi = file_default or "cp1252", oem = "cp437",
            console_output = false, file_default = file_default or false,
            output_default = output_default or false,
        },
        --Decodes ASCII and the two known GBK characters.
        --@param _ string Canonical label, ignored by the fake.
        --@param bytes string Input bytes.
        --@param lossy boolean Whether unknown bytes may become U+FFFD.
        --@return string|nil text Decoded text.
        --@return boolean|table exact Exact flag or InvalidEncoding error.
        decode = function(_, bytes, lossy)
            local output, index, exact = {}, 1, true
            while index <= #bytes do
                local byte = bytes:byte(index)
                local pair = to_utf8[bytes:sub(index, index + 1)]
                if byte < 0x80 then
                    output[#output + 1] = string.char(byte); index = index + 1
                elseif pair then
                    output[#output + 1] = pair; index = index + 2
                elseif lossy then
                    output[#output + 1] = "\239\191\189"; index = index + 1; exact = false
                else
                    return nil, { code = "InvalidEncoding", message = "invalid" }
                end
            end
            return table.concat(output), exact
        end,
        --Encodes ASCII and the two known characters, refusing everything else.
        --@param _ string Canonical label, ignored by the fake.
        --@param value string UTF-8 text.
        --@return string|nil bytes Encoded bytes.
        --@return boolean|table exact True or EncodingLossy error.
        encode = function(_, value)
            local output = {}
            for _, codepoint in utf8.codes(value) do
                local character = utf8.char(codepoint)
                if codepoint < 0x80 then
                    output[#output + 1] = character
                elseif from_utf8[character] then
                    output[#output + 1] = from_utf8[character]
                else
                    return nil, { code = "EncodingLossy", message = "unmappable" }
                end
            end
            return table.concat(output), true
        end,
    }
end

--Builds numbered ASCII log lines of exactly ten bytes each.
--@param count integer Number of lines.
--@return string bytes Log content "line 0001\n"...
local function numbered_lines(count)
    local parts = {}
    for index = 1, count do parts[index] = string.format("line %04d\n", index) end
    return table.concat(parts)
end

--Encodes ASCII or BMP text as UTF-16LE for fixtures.
--@param value string UTF-8 text without supplementary characters.
--@return string bytes UTF-16LE bytes without a BOM.
local function utf16le(value)
    local output = {}
    for _, codepoint in utf8.codes(value) do
        output[#output + 1] = string.char(codepoint % 256, codepoint // 256)
    end
    return table.concat(output)
end

return {
    name = "integration/direct-tools",
    cases = {
        {
            name = "an oversized result envelope rejects the write before intent or filesystem effects",
            --Verifies an oversized result envelope rejects the write before intent or filesystem effects.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify an oversized result envelope rejects the write before intent or filesystem effects.
            run = function()
                local service, controls, authority, dependencies = fixture({
                    options = { maximum_result_bytes = 20000 },
                })
                local accepted, err = call(service, "write", {
                    path = "/work/new.txt", mode = "create", content = string.rep("&", 10000),
                    encoding = "utf-8", newline_policy = "preserve",
                })
                A.falsy(accepted); A.equal(err.code, "ResultLimit")
                A.equal(#dependencies.operations.intents, 0)
                A.equal(authority.admits, 0)
                A.falsy(controls.exists("/work/new.txt"))
            end,
        },
        {
            name = "relative tool paths resolve only against the bound workspace and retain reserved-root denial",
            --Verifies an oversized result envelope rejects the write before intent or filesystem effects.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify an oversized result envelope rejects the write before intent or filesystem effects.
            run = function()
                local service = fixture()
                local listed = run(service, "list", { path = ".", depth = 1, page_size = 16 }, "relative-list")
                A.equal(listed.outcome, "success")
                local read = run(service, "read", { path = "sub/../a.txt", start_line = 1, max_lines = 1 }, "relative-read")
                A.equal(read.outcome, "success")
                local denied, err = call(service, "read", { path = "../reserved/config.ini", start_line = 1, max_lines = 1 }, "reserved-relative")
                A.falsy(denied)
                A.equal(err.code, "ReservedTreeDenied")
                A.falsy(call(service, "read", { path = "C:ambiguous", start_line = 1, max_lines = 1 }, "drive-relative"))
            end,
        },
        {
            name = "registry includes embedded Lua and non-main purposes are empty",
            --Verifies registry includes embedded Lua and non-main purposes are empty.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify registry includes embedded Lua and non-main purposes are empty.
            run = function()
                local service = fixture()
                local main = assert(service:registry_for("main"))
                local names = {}
                for index, tool in ipairs(main.tools) do
                    names[index] = tool.name
                    A.equal(tool.schema.additionalProperties, false)
                end
                A.deep_equal(names, {
                    "list", "read", "search", "write", "patch", "rename", "delete", "exec", "lua",
                })
                A.equal(main.digest, service.registry_digest)
                A.equal(#assert(service:registry_for("ask")).tools, 0)
                A.falsy(assert(service:registry_for("ask")).digest == main.digest)
                --Executes the action expected to raise in the 'registry includes embedded Lua and non-main purposes are empty' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify registry includes embedded Lua and non-main purposes are empty.
                A.raises(function() main.tools[1].name = "http" end, "cannot be modified")

                local result = run(service, "exec", { command = "echo opaque" }, "exec")
                A.equal(result.outcome, "failed")
                A.equal(result.error.code, "ExecUnavailable")
            end,
        },
        {
            name = "exact registry schemas project through both provider adapters",
            --Verifies exact registry schemas project through both provider adapters.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify exact registry schemas project through both provider adapters.
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
            --Verifies list read and search are stable bounded typed results with continuation.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify list read and search are stable bounded typed results with continuation.
            run = function()
                local service, controls, _, context = fixture()
                local inspected, snapshot = context.filesystem.direct_inspect(
                    "/work/sub/b.txt"
                )
                A.truthy(inspected)
                A.equal(#snapshot.ancestors, 3)
                --Executes the action expected to raise in the 'list read and search are stable bounded typed results with continuation' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify list read and search are stable bounded typed results with continuation.
                A.raises(function() snapshot.ancestors[1] = false end, "cannot be modified")
                local workspace_ok, workspace = context.filesystem.direct_inspect("/work")
                A.truthy(workspace_ok)
                local walked, raw_walk = context.filesystem.direct_walk(workspace, 2, 8)
                A.truthy(walked)
                A.equal(#raw_walk.entries, 4)
                --Executes the action expected to raise in the 'list read and search are stable bounded typed results with continuation' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify list read and search are stable bounded typed results with continuation.
                A.raises(function() raw_walk.entries[1] = false end, "cannot be modified")
                local first, first_call = run(service, "list", {
                    path = "/work", depth = 2, page_size = 2,
                }, "list-1")
                A.equal(first.outcome, "success", first.error and (
                    first.error.code .. ":" .. first.error.message .. ":" .. tostring(first.error.detail)
                ))
                local runtime_result = assert(service:runtime_result(first_call))
                A.equal(runtime_result.kind, "real-success")
                A.equal(runtime_result.raw_bytes, #runtime_result.body)
                A.equal(runtime_result.progress_identity, first.result_digest)
                A.contains(runtime_result.body, '"result_digest":"' .. first.result_digest .. '"')
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
            --Verifies read preserves UTF BOM newline spans and classifies binary without body.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify read preserves UTF BOM newline spans and classifies binary without body.
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
            --Verifies write create and replace use no-replace expected digest and metadata-safe publish.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify write create and replace use no-replace expected digest and metadata-safe publish.
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
            --Verifies structured patch validates every context before one publication.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify structured patch validates every context before one publication.
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
            --Verifies rename never clobbers or copies and delete only removes one exact target.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify rename never clobbers or copies and delete only removes one exact target.
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
            --Verifies reserved links special objects registered secrets and unknown fields fail closed.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify reserved links special objects registered secrets and unknown fields fail closed.
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
            --Verifies prompt-shaped values cannot execute and authorization is current-process one-shot.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify prompt-shaped values cannot execute and authorization is current-process one-shot.
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
        {
            name = "legacy code page files decode automatically with exact raw offsets",
            --Verifies legacy code page files decode automatically with exact raw offsets.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify system-default decoding and offsets.
            run = function()
                local initial = { ["/work/gbk.txt"] = "a\214\208\r\n\206\196b\n" }
                local service = fixture({ initial = initial, text_codec = fake_codec("cp936") })
                local read = run(service, "read", { path = "/work/gbk.txt", start_line = 1, max_lines = 5 }, "gbk")
                A.equal(read.outcome, "success")
                A.equal(read.payload.encoding, "cp936")
                A.equal(read.payload.encoding_basis, "system-default")
                A.equal(read.payload.lines[1].text, "a中")
                A.equal(read.payload.lines[1].raw_start, 0)
                A.equal(read.payload.lines[1].raw_end, 5)
                A.equal(read.payload.lines[2].text, "文b")
                A.equal(read.payload.lines[2].raw_start, 5)
                A.equal(read.payload.lines[2].raw_end, 9)
                local plain = fixture({ initial = initial })
                local undecoded = run(plain, "read", { path = "/work/gbk.txt", start_line = 1, max_lines = 5 }, "plain")
                A.equal(undecoded.payload.classification, "invalid-encoding")
                A.contains(undecoded.payload.hint, "encoding")
                local refused, refused_error = call(plain, "read", {
                    path = "/work/gbk.txt", start_line = 1, max_lines = 1, encoding = "gbk",
                }, "no-codec")
                A.falsy(refused)
                A.equal(refused_error.code, "EncodingUnavailable")
            end,
        },
        {
            name = "explicit encodings decode legacy bytes and repair invalid UTF-8 for display",
            --Verifies explicit encodings decode legacy bytes and repair invalid UTF-8 for display.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify requested and lossy decoding.
            run = function()
                local service = fixture({
                    initial = { ["/work/gbk.txt"] = "\214\208\n", ["/work/bad.txt"] = "ok\255\n" },
                    text_codec = fake_codec(false),
                })
                local read = run(service, "read", {
                    path = "/work/gbk.txt", start_line = 1, max_lines = 1, encoding = "GBK",
                }, "gbk")
                A.equal(read.payload.encoding, "cp936")
                A.equal(read.payload.encoding_basis, "requested")
                A.equal(read.payload.lines[1].text, "中")
                local repaired = run(service, "read", {
                    path = "/work/bad.txt", start_line = 1, max_lines = 1, encoding = "utf-8",
                }, "bad")
                A.equal(repaired.payload.lossy, true)
                A.equal(repaired.payload.lines[1].text, "ok\239\191\189")
                A.equal(repaired.payload.lines[1].raw_end, 4)
                local invalid, invalid_error = call(service, "read", {
                    path = "/work/bad.txt", start_line = 1, max_lines = 1, encoding = "utf-7",
                }, "label")
                A.falsy(invalid)
                A.equal(invalid_error.code, "InvalidToolArguments")
            end,
        },
        {
            name = "legacy writes and patches round-trip and refuse unrepresentable characters",
            --Verifies legacy writes and patches round-trip and refuse unrepresentable characters.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify exact legacy bytes on disk.
            run = function()
                local service, controls = fixture({
                    initial = { ["/work/gbk.txt"] = "a\214\208\r\n\206\196b\r\n" },
                    text_codec = fake_codec("cp936"),
                })
                local created = run(service, "write", {
                    path = "/work/new.txt", mode = "create", content = "中文\n",
                    encoding = "cp936", newline_policy = "preserve",
                }, "create")
                A.equal(created.outcome, "success")
                A.equal(controls.bytes("/work/new.txt"), "\214\208\206\196\n")
                local lossy = run(service, "write", {
                    path = "/work/emoji.txt", mode = "create", content = "😀\n",
                    encoding = "cp936", newline_policy = "preserve",
                }, "emoji")
                A.equal(lossy.outcome, "failed")
                A.equal(lossy.error.code, "EncodingLossy")
                A.falsy(controls.exists("/work/emoji.txt"))
                local read = run(service, "read", { path = "/work/gbk.txt", start_line = 1, max_lines = 2 }, "base")
                local patched = run(service, "patch", {
                    path = "/work/gbk.txt",
                    expected_identity = identity(controls, "/work/gbk.txt"),
                    expected_raw_digest = read.payload.raw_digest,
                    hunks = arr({ {
                        start_line = 2, context_before = arr({ "a中" }), delete_lines = arr({ "文b" }),
                        insert_lines = arr({ "中文c" }), context_after = arr({}),
                        newline = "crlf", final_newline = true,
                    } }),
                }, "patch")
                A.equal(patched.outcome, "success")
                A.equal(controls.bytes("/work/gbk.txt"), "a\214\208\r\n\214\208\206\196c\r\n")
            end,
        },
        {
            name = "from_end reads count lines backward on whole files",
            --Verifies from_end reads count lines backward on whole files.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify the backward page.
            run = function()
                local service = fixture()
                local read = run(service, "read", {
                    path = "/work/a.txt", start_line = 1, max_lines = 1, from_end = true,
                }, "tail")
                A.equal(#read.payload.lines, 1)
                A.equal(read.payload.lines[1].text, "beta")
                A.equal(read.payload.lines[1].number, 2)
                A.equal(read.payload.total_lines, 2)
                A.equal(read.payload.previous_line, 1)
            end,
        },
        {
            name = "large files are read as ranges with continuations, skips and seeks from the end",
            --Verifies large files are read as ranges with continuations, skips and seeks from the end.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify range pages and offsets.
            run = function()
                local service, controls = fixture({ initial = { ["/work/big.log"] = numbered_lines(4000) } })
                local first = run(service, "read", { path = "/work/big.log", start_line = 1, max_lines = 16 }, "r1")
                A.equal(first.payload.mode, "range")
                A.equal(first.payload.raw_digest, false)
                A.equal(#first.payload.lines, 16)
                A.equal(first.payload.lines[16].text, "line 0016")
                A.equal(first.payload.lines[16].raw_start, 150)
                A.equal(first.payload.next_line, 17)
                A.type(first.payload.continuation, "string")
                local second = run(service, "read", {
                    path = "/work/big.log", start_line = 1, max_lines = 16,
                    continuation = first.payload.continuation,
                }, "r2")
                A.equal(second.payload.lines[1].text, "line 0017")
                A.equal(second.payload.lines[1].number, 17)
                A.equal(second.payload.lines[1].raw_start, 160)
                local stale, stale_error = call(service, "read", {
                    path = "/work/big.log", start_line = 1, max_lines = 16,
                    continuation = first.payload.continuation,
                }, "r-stale")
                A.falsy(stale)
                A.equal(stale_error.code, "InvalidContinuation")
                local skipped = run(service, "read", { path = "/work/big.log", start_line = 3990, max_lines = 2 }, "skip")
                A.equal(skipped.payload.lines[1].text, "line 3990")
                A.equal(skipped.payload.lines[2].number, 3991)
                local tail = run(service, "read", {
                    path = "/work/big.log", start_line = 2, max_lines = 3, from_end = true,
                }, "tail")
                A.equal(#tail.payload.lines, 3)
                A.equal(tail.payload.lines[3].text, "line 3999")
                A.equal(tail.payload.lines[3].from_end, 2)
                A.equal(tail.payload.lines[3].number, false)
                A.equal(tail.payload.lines[3].raw_start, 39980)
                A.truthy(controls.seeks > 0)
            end,
        },
        {
            name = "the scan budget stops a large read with a resumable continuation",
            --Verifies the scan budget stops a large read with a resumable continuation.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify scan-limited pages resume.
            run = function()
                local service = fixture({
                    initial = { ["/work/big.log"] = numbered_lines(4000) },
                    options = { maximum_scan_bytes = 32768 },
                })
                local limited = run(service, "read", { path = "/work/big.log", start_line = 3500, max_lines = 2 }, "limit")
                A.equal(limited.payload.scan_limited, true)
                A.equal(#limited.payload.lines, 0)
                A.type(limited.payload.continuation, "string")
                local resumed = run(service, "read", {
                    path = "/work/big.log", start_line = 1, max_lines = 1,
                    continuation = limited.payload.continuation,
                }, "resume")
                local number = limited.payload.next_line
                A.equal(resumed.payload.lines[1].number, number)
                A.equal(resumed.payload.lines[1].text, string.format("line %04d", number))
            end,
        },
        {
            name = "UTF-16 large files split on aligned code units",
            --Verifies UTF-16 large files split on aligned code units.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify UTF-16 range decoding.
            run = function()
                local body = "\255\254" .. string.rep(utf16le("ab中\r\n"), 3500)
                local service = fixture({ initial = { ["/work/wide.log"] = body } })
                local read = run(service, "read", { path = "/work/wide.log", start_line = 1, max_lines = 2 }, "wide")
                A.equal(read.payload.encoding, "utf-16le-bom")
                A.equal(read.payload.lines[1].text, "ab中")
                A.equal(read.payload.lines[1].newline, "crlf")
                A.equal(read.payload.lines[1].raw_start, 2)
                A.equal(read.payload.lines[1].raw_end, 12)
                local tail = run(service, "read", {
                    path = "/work/wide.log", start_line = 1, max_lines = 1, from_end = true,
                }, "wide-tail")
                A.equal(tail.payload.lines[1].text, "ab中")
                A.equal(tail.payload.lines[1].raw_end, #body)
            end,
        },
        {
            name = "range reads reject empty chunks without EOF and release their handles",
            -- A native read that makes no progress must remain an error in sampling, reading and searching.
            --@param none Injects an empty non-EOF chunk into each range operation phase.
            --@return nil Assertions require FilesystemContract and closure of all observed read handles.
            --@error Raises on a false success, a wrong diagnostic or an unclosed read handle.
            run = function()
                for _, phase in ipairs({ "sample", "forward", "tail", "search" }) do
                    local first, handles, injected = nil, {}, false
                    local service = fixture({
                        initial = { ["/work/big.log"] = numbered_lines(4000) },
                        -- Inject once in the sampler or the subsequent content reader.
                        --@param _ table Unused filesystem controls; the bytes stay unchanged.
                        --@param read function Original native read operation.
                        --@param handle table Read handle whose phase and closure are observed.
                        --@param maximum integer Requested byte limit.
                        --@return boolean Whether the delegated or injected read succeeded.
                        --@return table Read result with bytes/eof.
                        --@effect Records handles and advances only delegated reads.
                        read_hook = function(_, read, handle, maximum)
                            first = first or handle
                            handles[handle] = true
                            if not injected and (phase == "sample" or handle ~= first) then
                                injected = true
                                return true, { bytes = "", eof = false }
                            end
                            return read(handle, maximum)
                        end,
                    })
                    local arguments = { path = "/work/big.log", start_line = 1, max_lines = 1,
                        from_end = phase == "tail" }
                    if phase == "search" then
                        arguments = { path = "/work/big.log", pattern = "absent", dialect = "literal",
                            case_sensitive = true, page_size = 1 }
                    end
                    local result = run(service, phase == "search" and "search" or "read", arguments, phase)
                    A.equal(injected, true)
                    A.equal(result.outcome, "failed", phase)
                    A.equal(result.error.code, "FilesystemContract", phase)
                    for handle in pairs(handles) do A.equal(handle.closed, true, phase) end
                end
            end,
        },
        {
            name = "range page lookahead preserves the native read error",
            -- A failure after the requested last line must not become a successful scan-limited page.
            --@param none Uses a first line matching the seven-byte chunk size and fails its lookahead.
            --@return nil Assertions require InjectedRead and closure of sampler and content handles.
            --@error Raises if the native read error is hidden or a handle remains open.
            run = function()
                local first, handles, injected = nil, {}, false
                local service = fixture({
                    initial = { ["/work/big.log"] = "first!\n" .. numbered_lines(4000) },
                    -- Fail the second content read after one full line has already been consumed.
                    --@param _ table Unused filesystem controls.
                    --@param read function Original native read operation.
                    --@param handle table Read handle with a one-based byte offset.
                    --@param maximum integer Requested byte limit.
                    --@return boolean False for the injected read, otherwise the delegated status.
                    --@return table InjectedRead error or raw read result.
                    --@effect Records handles and advances successful delegated reads.
                    read_hook = function(_, read, handle, maximum)
                        first = first or handle
                        handles[handle] = true
                        if handle ~= first and handle.offset > 1 then
                            injected = true
                            return false, { code = "InjectedRead", message = "lookahead failed" }
                        end
                        return read(handle, maximum)
                    end,
                })
                local result = run(service, "read", {
                    path = "/work/big.log", start_line = 1, max_lines = 1,
                }, "lookahead")
                A.equal(injected, true)
                A.equal(result.outcome, "failed")
                A.equal(result.error.code, "InjectedRead")
                for handle in pairs(handles) do A.equal(handle.closed, true) end
            end,
        },
        {
            name = "range reads and all large-search exits reject concurrent file changes",
            -- Version checks must run for forward/tail reads and search EOF, match-limit and scan-limit exits.
            --@param none Injects equal-size rewrites, growth, truncation and replacement during content reads.
            --@return nil Assertions require TargetChanged and closure of every observed handle.
            --@error Raises when a changed file produces success or cleanup misses a handle.
            run = function()
                local body = numbered_lines(4000)
                for _, mode in ipairs({ "forward", "tail", "search-eof", "search-match", "search-scan" }) do
                    for _, change in ipairs({ "rewrite", "grow", "truncate", "replace" }) do
                        local first, handles, injected = nil, {}, false
                        local service = fixture({
                            initial = { ["/work/big.log"] = body },
                            options = { maximum_search_matches = 1,
                                maximum_scan_bytes = mode == "search-scan" and 32768 or 262144 },
                            -- Change the backing file after the first content chunk has been returned.
                            --@param controls table Filesystem mutation controls.
                            --@param read function Original native read operation.
                            --@param handle table Read handle retained to verify cleanup.
                            --@param maximum integer Requested byte limit.
                            --@return boolean Status from the delegated read.
                            --@return table Original raw read result.
                            --@effect Advances the handle, records it and mutates or replaces the file once.
                            read_hook = function(controls, read, handle, maximum)
                                first = first or handle
                                handles[handle] = true
                                local ok, chunk = read(handle, maximum)
                                if handle ~= first and not injected then
                                    injected = true
                                    if change == "replace" then
                                        controls.external_replace("/work/big.log", body)
                                    else
                                        local changed = change == "grow" and body .. "new\n"
                                            or change == "truncate" and body:sub(1, #body - 10)
                                            or body:gsub("line", "LINE")
                                        controls.external_write("/work/big.log", changed)
                                    end
                                end
                                return ok, chunk
                            end,
                        })
                        local searching = mode:sub(1, 6) == "search"
                        local arguments = searching and {
                            path = "/work/big.log", pattern = mode == "search-match" and "line" or "absent",
                            dialect = "literal", case_sensitive = true, page_size = 1,
                        } or { path = "/work/big.log", start_line = 1, max_lines = 1,
                            from_end = mode == "tail" }
                        local result = run(service, searching and "search" or "read", arguments, mode .. change)
                        A.equal(injected, true)
                        A.equal(result.outcome, "failed", mode .. change)
                        A.equal(result.error.code, "TargetChanged", mode .. change)
                        for handle in pairs(handles) do A.equal(handle.closed, true, mode .. change) end
                    end
                end
            end,
        },
        {
            name = "content-dependent Lua pattern errors close streams and leave tools usable",
            -- Empty-string validation can miss malformed suffixes reached only while matching real content.
            --@param none Applies a trailing malformed bracket after a matching prefix in large and small files.
            --@return nil Assertions require a typed pattern error, closed handles and a succeeding follow-up read.
            --@error Raises if matching errors leak a handle, lose their typed code or poison later calls.
            run = function()
                for _, large in ipairs({ true, false }) do
                    local handles = {}
                    local service = fixture({
                        initial = { ["/work/pattern.log"] = "alpha\n" .. (large and string.rep("x\n", 20000) or "") },
                        -- Observe all reads without changing their bytes or native result.
                        --@param _ table Unused filesystem controls.
                        --@param read function Original native read operation.
                        --@param handle table Read handle whose eventual close is checked.
                        --@param maximum integer Requested byte limit.
                        --@return boolean Delegated read status.
                        --@return table Raw read result or native error.
                        --@effect Records handles and delegates their offset advancement.
                        read_hook = function(_, read, handle, maximum)
                            handles[handle] = true
                            return read(handle, maximum)
                        end,
                    })
                    local result = run(service, "search", {
                        path = "/work/pattern.log", pattern = "alpha[", dialect = "lua-pattern-v1",
                        case_sensitive = true, page_size = 1,
                    }, "bad-pattern")
                    A.equal(result.outcome, "failed")
                    for handle in pairs(handles) do A.equal(handle.closed, true) end
                    A.equal(result.error.code, "InvalidSearchPattern")
                    local recovered = run(service, "read", {
                        path = "/work/pattern.log", start_line = 1, max_lines = 1,
                    }, "after-pattern")
                    A.equal(recovered.outcome, "success")
                    A.equal(recovered.payload.lines[1].text, "alpha")
                end
            end,
        },
        {
            name = "range cleanup propagates final stat and close failures",
            -- Every successful or partial range observation must honor errors discovered while finishing its handle.
            --@param none Injects failures at sampler/read/tail/search completion using the native ports.
            --@return nil Assertions require the original error code and exactly one close for each opened handle.
            --@error Raises on swallowed finalization errors, an open handle or a repeated close.
            run = function()
                for _, phase in ipairs({ "sample", "forward", "tail", "search" }) do
                    for _, fault in ipairs({ "stat", "close" }) do
                        local first, active, handles, closes = nil, nil, {}, {}
                        local service, _, _, dependencies = fixture({
                            initial = { ["/work/big.log"] = numbered_lines(4000) },
                            options = { maximum_scan_bytes = 32768 },
                            -- Observe the handle whose completion operation should fail.
                            --@param _ table Unused filesystem controls.
                            --@param read function Original native read operation.
                            --@param handle table Live read handle.
                            --@param maximum integer Requested byte limit.
                            --@return boolean Status from the delegated read.
                            --@return table Raw read result or filesystem error.
                            --@effect Records each handle, selects the fault target and advances its offset.
                            read_hook = function(_, read, handle, maximum)
                                first = first or handle
                                handles[handle] = true
                                if phase == "sample" or handle ~= first then active = handle end
                                return read(handle, maximum)
                            end,
                        })
                        local native = dependencies.native
                        local stat, close = native.fs_stat_identity, native.fs_close
                        -- Fail the final stat of the selected handle while preserving ordinary path observations.
                        --@param reference table|string Read handle or path accepted by the native stat port.
                        --@return boolean False for the injected stat; otherwise delegated status.
                        --@return table InjectedStat error or observed filesystem identity.
                        native.fs_stat_identity = function(reference)
                            if fault == "stat" and reference == active then
                                return false, { code = "InjectedStat", message = "final stat failed" }
                            end
                            return stat(reference)
                        end
                        -- Release each handle and optionally report a failure from its close operation.
                        --@param handle table Native fake handle being released.
                        --@return boolean False for the injected close; otherwise delegated status.
                        --@return table|boolean InjectedClose error or true after an ordinary close.
                        --@effect Closes the native handle and counts every attempt, including failures.
                        native.fs_close = function(handle)
                            closes[handle] = (closes[handle] or 0) + 1
                            local ok, value = close(handle)
                            if fault == "close" and handle == active then
                                return false, { code = "InjectedClose", message = "close failed" }
                            end
                            return ok, value
                        end
                        local arguments = phase == "search" and {
                            path = "/work/big.log", pattern = "absent", dialect = "literal",
                            case_sensitive = true, page_size = 1,
                        } or { path = "/work/big.log", start_line = 1, max_lines = 1,
                            from_end = phase == "tail" }
                        local result = run(service, phase == "search" and "search" or "read", arguments, phase .. fault)
                        A.equal(result.outcome, "failed", phase .. fault)
                        A.equal(result.error.code, fault == "stat" and "InjectedStat" or "InjectedClose")
                        for handle in pairs(handles) do
                            A.equal(handle.closed, true)
                            A.equal(closes[handle], 1)
                        end
                    end
                end
            end,
        },
        {
            name = "range continuations reject changed versions before reusing partial lines",
            -- Cached long-line prefixes must not combine with a later file version, even on the same object.
            --@param none Uses a scan-limited half-line followed by equal-size, growth and shrink changes.
            --@return nil Assertions require TargetChanged, one-use token consumption and no new reads.
            --@error Raises if stale cached data is reused, a token is replayed or fresh reads precede rejection.
            run = function()
                local body = string.rep("x", 70000) .. "\nend\n"
                for _, change in ipairs({ "rewrite", "grow", "truncate" }) do
                    local reads = 0
                    local service, controls = fixture({
                        initial = { ["/work/big.log"] = body },
                        options = { maximum_scan_bytes = 32768 },
                        -- Count actual reads so stale cached state cannot start a new content stream.
                        --@param _ table Unused filesystem controls.
                        --@param read function Original native read operation.
                        --@param handle table Current read handle.
                        --@param maximum integer Requested byte limit.
                        --@return boolean Status from the delegated read.
                        --@return table Raw read result or filesystem error.
                        --@effect Increments reads and advances the delegated handle.
                        read_hook = function(_, read, handle, maximum)
                            reads = reads + 1
                            return read(handle, maximum)
                        end,
                    })
                    local first = run(service, "read", {
                        path = "/work/big.log", start_line = 1, max_lines = 1,
                    }, "version-first")
                    A.equal(first.payload.scan_limited, true)
                    A.equal(#first.payload.lines, 0)
                    local changed = change == "grow" and body .. "extra\n"
                        or change == "truncate" and body:sub(1, #body - 5)
                        or body:gsub("x", "y")
                    controls.external_write("/work/big.log", changed)
                    local before = reads
                    local arguments = { path = "/work/big.log", start_line = 1, max_lines = 1,
                        continuation = first.payload.continuation }
                    local resumed = run(service, "read", arguments, "version-next")
                    A.equal(resumed.outcome, "failed", change)
                    A.equal(resumed.error.code, "TargetChanged", change)
                    A.equal(reads, before)
                    local replay, replay_error = call(service, "read", arguments, "version-replay")
                    A.falsy(replay)
                    A.equal(replay_error.code, "InvalidContinuation")
                end
            end,
        },
        {
            name = "read pages retain content after JSON escaping in both directions and file modes",
            -- Paging must account for escaped JSON bytes instead of dropping a valid tool payload at serialization.
            --@param none Uses backslash/TAB lines below and above the whole-file threshold.
            --@return nil Assertions require complete forward pagination, the actual last line on tail reads and bounded JSON.
            run = function()
                local line = string.rep("\t\\", 8191)
                for _, count in ipairs({ 2, 4 }) do
                    local service = fixture({
                        initial = { ["/work/escaped.log"] = string.rep(line .. "\n", count) },
                        options = { maximum_line_bytes = 32768 },
                    })
                    for _, from_end in ipairs({ false, true }) do
                        local token, next_line, finished = nil, 1, false
                        for page = 1, count do
                            local result, admitted = run(service, "read", {
                                path = "/work/escaped.log", start_line = next_line, max_lines = 16,
                                from_end = from_end, continuation = token,
                            }, "escaped-" .. count .. tostring(from_end) .. "-" .. page)
                            A.equal(result.outcome, "success")
                            A.equal(result.payload.classification, "text")
                            A.truthy(#result.payload.lines > 0)
                            for _, observed in ipairs(result.payload.lines) do
                                A.equal(observed.text, line)
                                if not from_end then
                                    A.equal(observed.number, next_line)
                                    next_line = next_line + 1
                                end
                            end
                            A.truthy(#assert(service:runtime_result(admitted)).body <= 65536)
                            if from_end then
                                local last = result.payload.lines[#result.payload.lines]
                                A.equal(last.raw_end, (#line + 1) * count)
                                finished = true
                                break
                            end
                            if result.payload.eof then finished = true; break end
                            A.equal(result.payload.next_line, next_line)
                            token = result.payload.continuation
                        end
                        A.equal(finished, true)
                        if not from_end then A.equal(next_line, count + 1) end
                    end
                end
            end,
        },
        {
            name = "search pagination preserves every match within the final JSON limit",
            -- Large escaped snippets must move to later pages rather than erase the result and its continuation.
            --@param none Uses 32 matching lines whose combined requested page exceeds the result limit.
            --@return nil Assertions require each match exactly once and a bounded canonical result for every page.
            run = function()
                local line = "needle" .. string.rep("\\", 2040)
                local service = fixture({ initial = { ["/work/matches.log"] = string.rep(line .. "\n", 32) } })
                local token, next_line = nil, 1
                for index = 1, 8 do
                    local result, admitted = run(service, "search", {
                        path = "/work/matches.log", pattern = "needle", dialect = "literal",
                        case_sensitive = true, page_size = 16, continuation = token,
                    }, "escaped-matches-" .. index)
                    A.equal(result.outcome, "success")
                    A.truthy(result.payload.matches, result.payload.classification)
                    for _, match in ipairs(result.payload.matches) do
                        A.equal(match.line, next_line)
                        A.equal(match.snippet, line)
                        next_line = next_line + 1
                    end
                    A.truthy(#assert(service:runtime_result(admitted)).body <= 65536)
                    token = result.payload.continuation
                    if not token then
                        A.equal(result.payload.complete, true)
                        break
                    end
                end
                A.equal(next_line, 33)
                A.equal(token, false)
            end,
        },
        {
            name = "a single oversized JSON snippet is shortened at a scalar boundary",
            -- Even one escaped match needs room for the result envelope and pagination metadata.
            --@param none Uses one long matching line with escaped and multibyte characters.
            --@return nil Assertions require a useful truncated snippet and valid UTF-8 within the hard result limit.
            run = function()
                local service = fixture({
                    initial = { ["/work/match.log"] = "needle" .. string.rep("\\你", 8190) },
                    options = { maximum_result_bytes = 32768, maximum_line_bytes = 32768 },
                })
                local result, admitted = run(service, "search", {
                    path = "/work/match.log", pattern = "needle", dialect = "literal",
                    case_sensitive = true, page_size = 1,
                }, "one-snippet")
                A.equal(result.outcome, "success")
                A.truthy(result.payload.matches, result.payload.classification)
                local match = result.payload.matches[1]
                A.equal(match.truncated, true)
                A.equal(match.snippet:sub(1, 6), "needle")
                A.truthy(utf8.len(match.snippet))
                A.truthy(#assert(service:runtime_result(admitted)).body <= 32768)
            end,
        },
        {
            name = "a long legacy first line uses the system encoding without needing a newline sample",
            -- Auto detection must inspect the prefix bytes even when the first newline is beyond the sample.
            --@param none Uses a large GBK line and the Windows CP936 file default.
            --@return nil Assertions require legacy decoding and its explicit basis instead of UTF-8 repair.
            run = function()
                local service = fixture({
                    initial = { ["/work/gbk.log"] = string.rep("\214\208", 18000) .. "\n" },
                    text_codec = fake_codec("cp936"),
                })
                local result = run(service, "read", {
                    path = "/work/gbk.log", start_line = 1, max_lines = 1,
                }, "long-gbk")
                A.equal(result.outcome, "success")
                A.equal(result.payload.encoding, "cp936")
                A.equal(result.payload.encoding_basis, "system-default")
                A.equal(result.payload.lines[1].text:sub(1, 9), "中中中")
                A.falsy(result.payload.lines[1].lossy)
            end,
        },
        {
            name = "search reports omitted long-line content and enforces the shared scan budget",
            -- A prefix-only match pass cannot claim complete coverage, and small files share the same I/O budget.
            --@param none Uses one truncated record and two individually small files exceeding the combined budget.
            --@return nil Assertions require line-limit and scan-limit results instead of false completeness.
            run = function()
                local service = fixture({ initial = {
                    ["/work/long.log"] = string.rep("x", 5000) .. "NEEDLE\n" .. string.rep("padding\n", 4000),
                    ["/work/many"] = { kind = "directory" },
                    ["/work/many/1.log"] = string.rep("short\n", 4500),
                    ["/work/many/2.log"] = string.rep("short\n", 4500),
                }, options = { maximum_scan_bytes = 50000 } })
                local long = run(service, "search", {
                    path = "/work/long.log", pattern = "NEEDLE", dialect = "literal",
                    case_sensitive = true, page_size = 2,
                }, "search-long")
                A.equal(long.outcome, "success")
                A.equal(long.payload.complete, false)
                A.equal(long.payload.partial_reason, "line-limit")
                A.equal(long.payload.truncated_lines, 1)
                local many = run(service, "search", {
                    path = "/work/many", pattern = "NEEDLE", dialect = "literal",
                    case_sensitive = true, page_size = 2,
                }, "search-budget")
                A.equal(many.outcome, "success")
                A.equal(many.payload.complete, false)
                A.equal(many.payload.partial_reason, "scan-limit")
            end,
        },
        {
            name = "tail reads return a marked suffix when a line exceeds the retained window",
            -- A huge final line must yield useful bounded content rather than an empty end-of-file page.
            --@param none Uses a final record larger than the tail window, with and without a terminator.
            --@return nil Assertions require the suffix, raw byte range and explicit partial-start marker.
            run = function()
                for _, ending in ipairs({ "", "\r\n" }) do
                    local body = string.rep("x", 70000) .. "TAIL" .. ending
                    local service = fixture({ initial = { ["/work/long.log"] = body } })
                    local result = run(service, "read", {
                        path = "/work/long.log", start_line = 1, max_lines = 1, from_end = true,
                    }, "long-tail")
                    A.equal(result.outcome, "success")
                    A.equal(#result.payload.lines, 1)
                    local line = result.payload.lines[1]
                    A.equal(line.text:sub(-4), "TAIL")
                    A.equal(#line.text, 4096)
                    A.equal(line.partial_start, true)
                    A.equal(line.truncated, true)
                    A.equal(line.from_end, 1)
                    A.equal(line.raw_start, #body - #ending - 4096)
                    A.equal(line.raw_end, #body)
                    A.equal(line.newline, ending == "" and "none" or "crlf")
                    A.equal(result.payload.scan_limited, true)
                end
            end,
        },
        {
            name = "oversized lines resume beyond a scan budget without repeating the same prefix",
            -- A long record needs several bounded reads, then yields its prefix once and continues to the next line.
            --@param none Uses a line larger than two scan budgets followed by a short record.
            --@return nil Assertions require bounded progress, correct raw extent and the following record.
            run = function()
                local long = string.rep("x", 70000)
                local service = fixture({
                    initial = { ["/work/long.log"] = long .. "\nafter\n" },
                    options = { maximum_scan_bytes = 32768 },
                })
                local token, long_line, after = nil, nil, nil
                for index = 1, 4 do
                    local result = run(service, "read", {
                        path = "/work/long.log", start_line = 1, max_lines = 2, continuation = token,
                    }, "long-" .. tostring(index))
                    A.equal(result.outcome, "success")
                    for _, line in ipairs(result.payload.lines) do
                        if line.number == 1 then
                            A.falsy(long_line, "long record must be emitted once")
                            long_line = line
                        elseif line.number == 2 then
                            after = line
                        end
                    end
                    token = result.payload.continuation
                    if token == false then break end
                end
                A.truthy(long_line, "scan continuation did not finish the long record")
                A.equal(long_line.text, string.rep("x", 4096))
                A.equal(long_line.truncated, true)
                A.equal(long_line.raw_start, 0)
                A.equal(long_line.raw_end, #long + 1)
                A.truthy(after)
                A.equal(after.text, "after")
                A.equal(token, false)
            end,
        },
        {
            name = "UTF-16 range CRLF stays one terminator across odd chunk boundaries",
            -- Read enough UTF-16 lines to exercise every CRLF alignment in seven-byte reads.
            --@param none Uses a large BOM-marked file with identical CRLF records.
            --@return nil Assertions require exact text, terminators and raw spans on all selected lines.
            run = function()
                local body = "\255\254" .. string.rep(utf16le("ab中\r\n"), 3500)
                local service = fixture({ initial = { ["/work/wide.log"] = body } })
                local result = run(service, "read", {
                    path = "/work/wide.log", start_line = 1, max_lines = 16,
                }, "crlf-boundary")
                A.equal(result.outcome, "success")
                A.equal(#result.payload.lines, 16)
                for index, line in ipairs(result.payload.lines) do
                    A.equal(line.text, "ab中", tostring(index))
                    A.equal(line.newline, "crlf", tostring(index))
                    A.equal(line.raw_start, 2 + (index - 1) * 10)
                    A.equal(line.raw_end, 2 + index * 10)
                end
            end,
        },
        {
            name = "UTF-16 range reads retain and mark an incomplete final code unit",
            -- Check that a malformed final byte is neither silently dropped nor reported as lossless.
            --@param none Uses a large UTF-16 file with one dangling byte after its last newline.
            --@return nil Assertions require a replacement line covering the final byte for forward and tail reads.
            run = function()
                local prefix = "\255\254" .. string.rep(utf16le("ok\n"), 5500)
                local service = fixture({ initial = { ["/work/odd.log"] = prefix .. "x" } })
                for _, from_end in ipairs({ false, true }) do
                    local result = run(service, "read", {
                        path = "/work/odd.log", start_line = from_end and 1 or 5501,
                        max_lines = 1, from_end = from_end,
                    }, from_end and "odd-tail" or "odd-forward")
                    A.equal(result.outcome, "success")
                    A.equal(#result.payload.lines, 1)
                    local line = result.payload.lines[1]
                    A.equal(line.text, "\239\191\189")
                    A.equal(line.lossy, true)
                    A.equal(line.raw_start, #prefix)
                    A.equal(line.raw_end, #prefix + 1)
                    A.equal(result.payload.eof, true)
                end
            end,
        },
        {
            name = "range decoding keeps valid UTF-16 around an isolated surrogate",
            -- Preserve readable text when a single invalid UTF-16 unit requires display repair.
            --@param none Uses a large file ending in a line with an unpaired high surrogate.
            --@return nil Assertions require local replacement without discarding surrounding text.
            run = function()
                local body = "\255\254" .. string.rep(utf16le("ok\n"), 5500)
                    .. utf16le("before") .. "\0\216" .. utf16le("after\n")
                local service = fixture({ initial = { ["/work/wide.log"] = body } })
                local result = run(service, "read", {
                    path = "/work/wide.log", start_line = 1, max_lines = 1, from_end = true,
                }, "surrogate")
                A.equal(result.outcome, "success")
                A.equal(result.payload.lines[1].text, "before\239\191\189after")
                A.equal(result.payload.lines[1].lossy, true)
            end,
        },
        {
            name = "search covers single files, legacy text and large files",
            --Verifies search covers single files, legacy text and large files.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify search coverage.
            run = function()
                local service = fixture({
                    initial = {
                        ["/work/big.log"] = numbered_lines(4000),
                        ["/work/gbk.txt"] = "a\214\208\n",
                    },
                    text_codec = fake_codec("cp936"),
                })
                local single = run(service, "search", {
                    path = "/work/big.log", pattern = "line 3999", dialect = "literal",
                    case_sensitive = true, page_size = 4,
                }, "single")
                A.equal(single.outcome, "success")
                A.equal(#single.payload.matches, 1)
                A.equal(single.payload.matches[1].line, 3999)
                A.equal(single.payload.skipped_large, 0)
                local tree = run(service, "search", {
                    path = "/work", pattern = "中", dialect = "literal",
                    case_sensitive = true, page_size = 8,
                }, "tree")
                A.equal(#tree.payload.matches, 1)
                A.equal(tree.payload.matches[1].file, "gbk.txt")
                A.equal(tree.payload.matches[1].column, 2)
            end,
        },
    },
}
