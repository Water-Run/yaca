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

--Constructs the suite's isolated runtime fixture and observation ports.
--@param settings table|nil Fixture settings and scenario overrides.
--@return any fixture Constructed fixture service used by this suite.
--@return any secondary2 Configured control actions returned by the fixture.
--@return any secondary3 Additional status or structured error from the fixture operation.
--@return table secondary4 Structured fixture record with modules, safety, filesystem, operations.
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
