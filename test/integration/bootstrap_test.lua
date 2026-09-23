--[[
Author: WaterRun
Date: 2026-09-23
File: bootstrap_test.lua
Description: Verifies offline bootstrap routing, Agent gates, and bare-draft behavior.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

--Loads a source module into an isolated per-case environment.
--@param name string Module, Model, or resource name selected by the case.
--@param cache table Per-case module cache preserving isolated imports.
--@return any module Module export loaded in the isolated source environment.
local function load_module(name, cache)
    cache = cache or {}
    if cache[name] then return cache[name] end
    local environment = {
        --Resolves an imported Lua module through the isolated test loader.
        --@param dependency string Source module requested from the isolated loader.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        require = function(dependency)
        return load_module(dependency, cache)
    end }
    environment._G = environment
    --@metatable environment Test-owned lookup and mutation contract for the current case.
    --@field __index any Fallback table or function used for missing fixture keys.
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

--Loads a repository Lua module as a test support value.
--@param relative_path string Repository-relative Lua source path to load.
--@return any module Test support module export loaded from the repository.
local function load_table(relative_path)
    local chunk, load_error = loadfile(YACA_TEST_ROOT .. "/" .. relative_path, "t", _ENV)
    A.truthy(chunk, load_error)
    return chunk()
end

local cache = {}
local config = load_module("config", cache)
local main = load_module("main", cache)
local sha256 = load_table("test/support/sha256_reference.lua")
local fake_filesystem = load_table("test/support/fake_filesystem.lua")
local fake_lxp = load_table("test/support/fake_lxp.lua")

local CONFIG_PATH = "/release/__yaca__/config.ini"

--Constructs an incremental SHA-256 port backed by the reference digest.
--@param none No arguments; this closure uses its captured fixture state.
--@return any port Incremental SHA-256 fixture port.
local function hash_port()
    local port = {}

    --Starts a fake incremental SHA-256 handle.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return table handle New incremental SHA-256 fixture handle.
    function port.sha256_start()
        return { parts = {}, finished = false, closed = false }
    end

    --Adds bytes to the fake incremental SHA-256 handle.
    --@param handle table|integer Fake resource handle whose state is inspected.
    --@param bytes string Byte chunk supplied to the fake I/O port.
    --@return boolean accepted Whether the fixture accepted the byte chunk.
    function port.sha256_update(handle, bytes)
        assert(not handle.finished and not handle.closed)
        handle.parts[#handle.parts + 1] = bytes
        return true
    end

    --Finalizes the fake SHA-256 handle using the reference digest.
    --@param handle table|integer Fake resource handle whose state is inspected.
    --@return any digest Hexadecimal digest of the accumulated fixture bytes.
    function port.sha256_finish(handle)
        assert(not handle.finished and not handle.closed)
        handle.finished = true
        return sha256.digest(table.concat(handle.parts))
    end

    --Closes the fake SHA-256 handle and records its state.
    --@param handle table|integer Fake resource handle whose state is inspected.
    --@return boolean closed Whether the fixture handle was closed.
    function port.sha256_close(handle)
        assert(not handle.closed)
        handle.closed = true
        return true
    end

    return port
end

--Builds bounded configuration parser options for bootstrap cases.
--@param none No arguments; this closure uses its captured fixture state.
--@return table observed Structured fixture record selected by the exercised branch.
local function config_options()
    return {
        schema_version = "0.1.0",
        release_ca_path = "/release/cacert.pem",
        ini_limits = {
            maximum_bytes = 65536,
            maximum_lines = 512,
            maximum_line_bytes = 4096,
            maximum_value_bytes = 16384,
        },
        hard_limits = {
            queue_items = 64,
            turn_model_requests = 64,
            turn_tool_calls = 256,
            connect_timeout_ms = 120000,
            response_bytes = 16777216,
            exec_timeout_ms = 3600000,
            exec_output_kb = 8192,
            auto_name_turns = 100000,
            recent_contexts = 10000,
            model_context_tokens = 2000000,
            model_output_tokens = 131072,
            request_timeout_ms = 3600000,
            retry_count = 10,
            retry_base_delay_ms = 60000,
        },
        runtime_defaults = { retry_count = 2 },
        maximum_text_bytes = 16384,
        maximum_name_bytes = 128,
        maximum_adapter_options_bytes = 4096,
        maximum_hash_chunk_bytes = 11,
        minimum_scannable_secret_bytes = 8,
    }
end

--Builds a valid INI source with selectable scenario settings.
--@param settings table|nil Fixture settings and scenario overrides.
--@return any matches Whether valid source satisfies the tested condition.
local function valid_source(settings)
    settings = settings or {}
    local model_sections = {}
    if settings.disabled_first then
        model_sections[#model_sections + 1] = table.concat({
            "[Model.Disabled]",
            "Enabled = false",
            "Protocol = openai-chat",
            "",
        }, "\n")
    end
    model_sections[#model_sections + 1] = table.concat({
        "[Model.Primary]",
        "Enabled = true",
        "Protocol = openai-chat",
        "Endpoint = \"https://api.example/v1/chat\"",
        "RemoteModel = \"remote-main\"",
        "Key = \"bootstrap-secret\"",
        "",
    }, "\n")
    return table.concat({
        "[General]",
        "SchemaVersion = 0.1.0",
        "StartupSelfTest = " .. (settings.startup_self_test or "off"),
        "",
        "[Permission.Std]",
        "Read = allow",
        "Write = confirm",
        "Delete = confirm",
        "Shell = confirm",
        "OutsideWorkspace = confirm",
        "",
        table.concat(model_sections, "\n"),
    }, "\n")
end

--Supplies production native behavior required by this suite.
--@param settings table|nil Fixture settings and scenario overrides.
--@return any observed production native value observed by the scenario assertion.
--@return any secondary2 Configured control actions returned by the fixture.
--@return any secondary3 Recorded call count returned by the fixture.
--@return any secondary4 Additional status or structured error from the fixture operation.
--@return any secondary5 Additional status or structured error from the fixture operation.
--@return any secondary6 Additional status or structured error from the fixture operation.
--@return any secondary7 Additional status or structured error from the fixture operation.
local function production_native(settings)
    settings = settings or {}
    local windows = settings.os == "windows"
    local separator = windows and "\\" or "/"
    local outer = windows and "C:\\release" or "/release"
    local inner = windows and "C:\\runtime\\payload" or "/runtime/payload"
    local application = outer .. separator .. (windows and "yaca.exe" or "yaca")
    local runtime = inner .. separator .. (windows and "yaca.exe" or "yaca")
    local data_root = outer .. separator .. "__yaca__"
    local config_path = data_root .. separator .. "config.ini"
    local native_path = inner .. separator .. ".luai" .. separator .. "native"
        .. separator .. (windows and "yaca_native.dll" or "yaca_native.so")
    local components = inner .. separator .. ".luai" .. separator .. "components"
    local initial = {
        [application] = "outer",
        [runtime] = "runtime",
        [components .. separator .. (windows and "curl.exe" or "curl")] = "curl",
        [components .. separator .. "cacert.pem"] = "not-the-release-ca",
        [native_path] = "native",
    }
    local raw, controls = fake_filesystem.new(initial, 65536)
    local directories = {
        [outer] = true,
        [inner] = true,
        [inner .. separator .. ".luai"] = true,
        [components] = true,
        [inner .. separator .. ".luai" .. separator .. "native"] = true,
    }
    local hashes = hash_port()
    local calls = { directory_creates = 0, process_starts = 0 }
    --Supplies native error behavior required by this suite.
    --@param code string|integer Expected error or exit code.
    --@param message string|table Message or diagnostic passed through this test port.
    --@return table observed Structured fixture record with code, message.
    local function native_error(code, message)
        return { code = code, message = message or code }
    end
    local native = {}
    --Simulates abi version in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return string outcome Simulated abi version outcome returned to the component.
    function native.abi_version() return "yaca-native-v0.1.0" end
    --Simulates platform identity in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return table outcome Simulated platform identity outcome returned to the component.
    function native.platform_identity()
        return {
            os = windows and "windows" or "linux",
            arch = windows and (settings.arch or "x86") or "x86_64",
        }
    end
    --Simulates stdio facts in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return table outcome Simulated stdio facts outcome returned to the component.
    function native.stdio_facts()
        return { stdin_is_tty = true, stdout_is_tty = true, stderr_is_tty = true }
    end
    --Simulates executable paths in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return table outcome Simulated executable paths outcome returned to the component.
    function native.executable_paths()
        return { application = application, runtime = runtime }
    end
    --Simulates workspace inspect in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return table outcome Simulated workspace inspect outcome returned to the component.
    function native.workspace_inspect()
        return {
            path = windows and "C:\\workspace" or "/workspace",
            enterable = true,
            identity = {
                kind = "directory", volume = "fake-volume", object = "workspace",
                size = 0, modified = "1",
            },
        }
    end
    --Simulates monotonic now in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return integer outcome Simulated monotonic now outcome returned to the component.
    function native.monotonic_now() return 1 end
    --Simulates sleep ms in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether sleep ms succeeds in the fixture.
    function native.sleep_ms() return true end
    --Simulates utc now in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return string outcome Simulated utc now outcome returned to the component.
    function native.utc_now() return "2026-08-30T00:00:00Z" end
    --Simulates secure random in this test fixture.
    --@param length integer Byte or item length requested by the fixture.
    --@return any outcome Simulated secure random outcome returned to the component.
    function native.secure_random(length) return string.rep("r", length) end
    --Simulates current process id in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return integer outcome Simulated current process id outcome returned to the component.
    function native.current_process_id() return 41 end
    for _, name in ipairs({
        "sha256_start", "sha256_update", "sha256_finish", "sha256_close",
    }) do
        native[name] = hashes[name]
    end
    --Simulates fs open read in this test fixture.
    --@param path string File or Context path exercised by the case.
    --@return any outcome Simulated fs open read outcome returned to the component.
    function native.fs_open_read(path) return raw.open_read(path) end
    --Simulates fs create new in this test fixture.
    --@param path string File or Context path exercised by the case.
    --@param permissions table Permission profile exercised by the case.
    --@return any outcome Simulated fs create new outcome returned to the component.
    function native.fs_create_new(path, permissions)
        return raw.create_new(path, permissions)
    end
    --Simulates fs stat identity in this test fixture.
    --@param handle_or_path table|string Fake handle or path accepted by this port.
    --@return boolean|any outcome Simulated fs stat identity outcome returned to the component.
    --@return table|nil secondary2 Structured fixture record selected by the exercised branch.
    function native.fs_stat_identity(handle_or_path)
        if type(handle_or_path) == "string" and directories[handle_or_path] then
            return true, {
                kind = "directory",
                volume = "fake-volume",
                object = "dir:" .. handle_or_path,
                size = 0,
                modified = "1",
            }
        end
        return raw.stat_identity(handle_or_path)
    end
    --Simulates fs read in this test fixture.
    --@param handle table|integer Fake resource handle whose state is inspected.
    --@param maximum integer Maximum allowed count or byte length.
    --@return any outcome Simulated fs read outcome returned to the component.
    function native.fs_read(handle, maximum) return raw.stream_read(handle, maximum) end
    --Simulates fs write in this test fixture.
    --@param handle table|integer Fake resource handle whose state is inspected.
    --@param bytes string Byte chunk supplied to the fake I/O port.
    --@return any outcome Simulated fs write outcome returned to the component.
    function native.fs_write(handle, bytes) return raw.stream_write(handle, bytes) end
    --Simulates fs flush file in this test fixture.
    --@param handle table|integer Fake resource handle whose state is inspected.
    --@return any outcome Simulated fs flush file outcome returned to the component.
    function native.fs_flush_file(handle) return raw.flush_file(handle) end
    --Simulates fs flush directory in this test fixture.
    --@param path string File or Context path exercised by the case.
    --@return any outcome Simulated fs flush directory outcome returned to the component.
    function native.fs_flush_directory(path) return raw.flush_directory(path) end
    --Simulates fs replace in this test fixture.
    --@param temporary string Temporary publication path.
    --@param target table|string Target selected for the exercised operation.
    --@return any outcome Simulated fs replace outcome returned to the component.
    function native.fs_replace(temporary, target) return raw.replace(temporary, target) end
    --Simulates fs rename no replace in this test fixture.
    --@param source string|table Source content or object under test.
    --@param target table|string Target selected for the exercised operation.
    --@return any outcome Simulated fs rename no replace outcome returned to the component.
    function native.fs_rename_no_replace(source, target)
        return raw.rename_no_replace(source, target)
    end
    --Simulates fs delete verified in this test fixture.
    --@param path string File or Context path exercised by the case.
    --@param identity table File or process identity under inspection.
    --@return any outcome Simulated fs delete verified outcome returned to the component.
    function native.fs_delete_verified(path, identity)
        return raw.delete_verified(path, identity)
    end
    --Simulates fs close in this test fixture.
    --@param handle table|integer Fake resource handle whose state is inspected.
    --@return any outcome Simulated fs close outcome returned to the component.
    function native.fs_close(handle) return raw.close(handle) end
    --Simulates fs make directory in this test fixture.
    --@param path string File or Context path exercised by the case.
    --@return boolean accepted Whether fs make directory succeeds in the fixture.
    --@return boolean|any secondary2 Additional status or structured error from the fixture operation.
    function native.fs_make_directory(path)
        if directories[path] then
            return false, native_error("DestinationExists", "directory already exists")
        end
        if path ~= data_root then
            return false, native_error("NotFound", "directory parent is unavailable")
        end
        directories[path] = true
        calls.directory_creates = calls.directory_creates + 1
        return true, true
    end
    --Simulates process start in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether process start succeeds in the fixture.
    --@return any secondary2 Additional status or structured error from the fixture operation.
    function native.process_start()
        calls.process_starts = calls.process_starts + 1
        return false, native_error("UnexpectedProcess", "process start was not expected")
    end
    --Simulates process poll in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether process poll succeeds in the fixture.
    --@return table secondary2 Empty structured fixture record.
    function native.process_poll() return true, {} end
    --Simulates process cancel in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether process cancel succeeds in the fixture.
    --@return boolean secondary2 True acknowledgment from the fake port.
    function native.process_cancel() return true, true end
    --Simulates process join in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether process join succeeds in the fixture.
    --@return table secondary2 Outcome record with status completed.
    function native.process_join()
        return true, {
            outcome = "completed", exit_kind = "exit-code", exit_code = 0,
            duration_ms = 0, descendants_proven_stopped = true,
        }
    end
    --Simulates process close in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether process close succeeds in the fixture.
    --@return boolean secondary2 True acknowledgment from the fake port.
    function native.process_close() return true, true end
    --Simulates terminal start in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether terminal start succeeds in the fixture.
    --@return table secondary2 Empty structured fixture record.
    function native.terminal_start() return true, {} end
    --Simulates terminal poll in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether terminal poll succeeds in the fixture.
    --@return table secondary2 Empty structured fixture record.
    function native.terminal_poll() return true, {} end
    --Simulates terminal cancel in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether terminal cancel succeeds in the fixture.
    --@return boolean secondary2 True acknowledgment from the fake port.
    function native.terminal_cancel() return true, true end
    --Simulates terminal join in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether terminal join succeeds in the fixture.
    --@return table secondary2 Outcome record with status completed.
    function native.terminal_join() return true, { outcome = "completed" } end
    --Simulates terminal close in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether terminal close succeeds in the fixture.
    --@return boolean secondary2 True acknowledgment from the fake port.
    function native.terminal_close() return true, true end
    --Simulates terminal restore in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether terminal restore succeeds in the fixture.
    --@return boolean secondary2 True acknowledgment from the fake port.
    function native.terminal_restore() return true, true end
    return native, controls, calls, native_path, data_root, application, config_path
end

--Supplies config editor fixture behavior required by this suite.
--@param answers any The answers supplied to the fake service for this scenario.
--@param settings table|nil Fixture settings and scenario overrides.
--@return table observed Structured fixture record selected by the exercised branch.
local function config_editor_fixture(answers, settings)
    settings = settings or {}
    --Constructs the fake lxp service used by this suite.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether the fake callback accepts this scenario.
    --@return string secondary2 Fixture text "configuration editing must not parse Context XML".
    --@return integer secondary3 Fixture numeric value 1.
    --@return integer secondary4 Fixture numeric value 1.
    --@return integer secondary5 Fixture numeric value 1.
    cache.lxp = fake_lxp(function()
        return false, "configuration editing must not parse Context XML", 1, 1, 1
    end)
    local native, filesystem, calls, native_path, _, application_path, config_path = production_native(settings)
    local original = settings.source or ("; retained config comment\n" .. valid_source())
    filesystem.external_replace(config_path, original)
    local output, errors, modes = {}, {}, {}
    local polls, restores = 0, 0
    --Simulates monotonic now in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return integer|nil outcome Simulated monotonic now outcome returned to the component.
    function native.monotonic_now()
        if settings.clock_failed then return nil end
        return 1
    end
    --Simulates terminal start in this test fixture.
    --@param request table Request delivered to the fake component.
    --@return boolean accepted Whether terminal start succeeds in the fixture.
    --@return table secondary2 Structured fixture record with mode.
    function native.terminal_start(request)
        modes[#modes + 1] = request.mode
        return true, { mode = request.mode }
    end
    --Simulates terminal poll in this test fixture.
    --@param handle table|integer Fake resource handle whose state is inspected.
    --@return boolean accepted Whether terminal poll succeeds in the fixture.
    --@return table|any secondary2 Additional status or structured error from the fixture operation.
    function native.terminal_poll(handle)
        if handle.cancelled then return true, { { kind = "terminal", outcome = "cancelled" } } end
        polls = polls + 1
        if settings.before_poll then settings.before_poll(polls, filesystem, config_path) end
        local answer = answers[polls]
        if type(answer) == "table" and answer.batch then return true, answer.batch end
        if type(answer) == "table" then return true, { answer } end
        if answer == nil then return true, { { kind = "action", intent = "eof" } } end
        return true, { { kind = "action", intent = "text", text = answer .. "\n" } }
    end
    --Simulates terminal cancel in this test fixture.
    --@param handle table|integer Fake resource handle whose state is inspected.
    --@return boolean accepted Whether terminal cancel succeeds in the fixture.
    --@return boolean secondary2 True acknowledgment from the fake port.
    function native.terminal_cancel(handle) handle.cancelled = true return true, true end
    --Simulates terminal join in this test fixture.
    --@param handle table|integer Fake resource handle whose state is inspected.
    --@return boolean accepted Whether terminal join succeeds in the fixture.
    --@return table secondary2 Outcome record with status cancelled.
    function native.terminal_join(handle)
        A.truthy(handle.cancelled)
        return true, { outcome = "cancelled" }
    end
    --Simulates terminal restore in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether terminal restore succeeds in the fixture.
    --@return boolean secondary2 True acknowledgment from the fake port.
    function native.terminal_restore() restores = restores + 1 return true, true end
    --Simulates terminal close in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether terminal close succeeds in the fixture.
    --@return boolean secondary2 True acknowledgment from the fake port.
    function native.terminal_close() return true, true end
    if settings.native_setup then settings.native_setup(native, filesystem) end
    local code = main.run_cli({ [0] = application_path, settings.action or "--config-repl" }, {
        native = native, native_path = native_path,
        --Captures stdout bytes in the the current case scenario.
        --@param bytes string Byte chunk supplied to the fake I/O port.
        --@return boolean accepted Whether the fake callback accepts this scenario.
        stdout = function(bytes) output[#output + 1] = bytes return true end,
        --Captures stderr bytes in the the current case scenario.
        --@param bytes string Byte chunk supplied to the fake I/O port.
        --@return boolean accepted Whether the fake callback accepts this scenario.
        stderr = function(bytes) errors[#errors + 1] = bytes return true end,
    })
    return {
        code = code, output = table.concat(output), stderr = table.concat(errors),
        filesystem = filesystem, calls = calls, path = config_path, original = original,
        modes = modes, restores = restores, polls = polls,
    }
end

--Supplies application behavior required by this suite.
--@param source string|table Source content or object under test.
--@param continuation any The continuation supplied to the fake service for this scenario.
--@return any observed application value observed by the scenario assertion.
--@return any secondary2 Recorded call count returned by the fixture.
--@return any secondary3 Additional status or structured error from the fixture operation.
local function application(source, continuation)
    local initial = source and { [CONFIG_PATH] = source } or {}
    local filesystem, filesystem_controls = fake_filesystem.new(initial, 23)
    local config_service = assert(config.new({
        sha256 = hash_port(),
        filesystem = filesystem,
    }, config_options()))
    local calls = {
        platform = 0,
        config = 0,
        workspace = 0,
        stage1 = 0,
        management = 0,
        network = 0,
        catalog = 0,
        agent = 0,
        stage1_outcome = "passed",
        stage1_online_requests = 0,
    }
    local counted_config = {}
    --Supplies reload file behavior required by this suite.
    --@param path string File or Context path exercised by the case.
    --@param overrides table|nil Per-case overrides of default fixture behavior.
    --@return any observed reload file value observed by the scenario assertion.
    function counted_config.reload_file(path, overrides)
        calls.config = calls.config + 1
        calls.last_config_overrides = overrides or false
        return config_service.reload_file(path, overrides)
    end
    --@metatable counted_config Test-owned lookup and mutation contract for the current case.
    --@field __index any Fallback table or function used for missing fixture keys.
    setmetatable(counted_config, { __index = config_service })

    local platform = {}
    --Supplies the identity observation used by this suite.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return table observed Structured fixture record with os, arch, target, supported.
    function platform.identity()
        calls.platform = calls.platform + 1
        return {
            os = "linux",
            arch = "x86_64",
            target = "linux-x86_64",
            supported = true,
        }
    end

    local workspace = {}
    --Returns the inspect observation prepared for this suite.
    --@param requested any The requested supplied to the fake service for this scenario.
    --@return table observed Structured fixture record selected by the exercised branch.
    function workspace.inspect(requested)
        calls.workspace = calls.workspace + 1
        local observed = requested == "." and "/workspace" or requested
        return {
            path = observed,
            enterable = true,
            identity = {
                kind = "directory",
                volume = "volume-1",
                object = continuation and continuation.workspace_objects
                    and continuation.workspace_objects[observed] or observed,
            },
        }
    end

    local self_test = {
        online = "explicit-current-invocation-only",
        auto_fix = false,
    }
    --Supplies run behavior required by this suite.
    --@param self table Fixture or port instance receiving this call.
    --@param request table Request delivered to the fake component.
    --@return table observed Structured fixture record selected by the exercised branch.
    function self_test:run(request)
        calls.stage1 = calls.stage1 + 1
        calls.catalog = calls.catalog + 1
        calls.last_stage1 = request
        local online_requests = calls.stage1_online_requests
        if request.through_stage >= 2 and not request.list_checks
            and online_requests == 0
        then
            online_requests = 1
            calls.network = calls.network + 1
        end
        return {
            kind = "self-test",
            outcome = calls.stage1_outcome,
            online_requests = online_requests,
            auto_fixes = 0,
            completed_stage = request.list_checks and 0 or request.through_stage,
            check_count = 15,
        }
    end

    local management = { online = false }
    --Supplies run behavior required by this suite.
    --@param request table Request delivered to the fake component.
    --@return table observed Outcome record with status success.
    function management.run(request)
        calls.management = calls.management + 1
        calls.last_management = request
        if request.action == "context-repl" then calls.catalog = calls.catalog + 1 end
        return {
            outcome = "success",
            action = request.action,
            config_error = request.config_error and request.config_error.code or false,
        }
    end

    local components = {
        platform = platform,
        config = counted_config,
        workspace = workspace,
        self_test = self_test,
        management = management,
        network = {
            --Simulates the request port for this suite.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; the fake port or test assertion observes this callback's effects.
            request = function() calls.network = calls.network + 1 end },
        agent = {
            --Simulates the start transition of a fake activity port for this suite.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; the fake port or test assertion observes this callback's effects.
            start = function() calls.agent = calls.agent + 1 end },
    }
    if continuation then
        local logical_path = continuation.logical_path or "/workspace/Task.xml"
        local physical_path = continuation.physical_path
            or "/data/CONTEXT/posix" .. logical_path
        local selection = {
            tag = "Unique",
            logical_path = logical_path,
            hash = "0123456789ABCDEF",
        }
        local credential = {
            physical_path = physical_path,
            logical_path = logical_path,
            observed_stat = { object = continuation.credential_version or "original" },
        }
        local resolver = {}
        --Supplies resolve behavior required by this suite.
        --@param selector string Context selector resolved by the case.
        --@param origin string Original workspace or request origin.
        --@return table|any observed resolve value observed by the scenario assertion.
        function resolver.resolve(selector, origin)
            calls.catalog = calls.catalog + 1
            calls.last_selector = selector
            calls.last_origin = origin
            if continuation.resolve_tag then
                return { tag = continuation.resolve_tag }
            end
            return selection
        end
        --Checks verify target against this test expectation.
        --@param observed table|any State observed after the exercised operation.
        --@param purpose string Operation purpose supplied to the verifier.
        --@return table observed Structured fixture record selected by the exercised branch.
        function resolver.verify_target(observed, purpose)
            calls.verify = (calls.verify or 0) + 1
            calls.last_verify_purpose = purpose
            A.equal(observed, selection)
            if continuation.verify_tag then
                return { tag = continuation.verify_tag }
            end
            if continuation.change_after_read and (calls.export_read or 0) > 0 then
                return { tag = "TargetChanged" }
            end
            return {
                tag = "Verified",
                logical_path = logical_path,
                hash = "0123456789ABCDEF",
                physical_hint = physical_path,
                credential = credential,
            }
        end
        local path = {}
        --Supplies to logical behavior required by this suite.
        --@param value any Candidate whose acceptance or transformation the test checks.
        --@return any observed to logical value observed by the scenario assertion.
        function path.to_logical(value) return value:gsub("\\", "/") end
        --Supplies from logical behavior required by this suite.
        --@param value any Candidate whose acceptance or transformation the test checks.
        --@return any observed Selected fixture value returned by the fixture.
        function path.from_logical(value) return value end
        --Supplies parent behavior required by this suite.
        --@param value any Candidate whose acceptance or transformation the test checks.
        --@return number observed parent value observed by the scenario assertion.
        function path.parent(value)
            return value:match("^(.*)/[^/]+$") or "/"
        end
        --Supplies comparison key behavior required by this suite.
        --@param value any Candidate whose acceptance or transformation the test checks.
        --@return any observed Selected fixture value returned by the fixture.
        function path.comparison_key(value) return value end

        local publication = {}
        local publication_closed = false
        --Supplies publish first behavior required by this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return nil rejected Explicit empty outcome from publish first.
        --@return table secondary2 Typed error record with code UnexpectedPublication.
        function publication.publish_first()
            return nil, { code = "UnexpectedPublication" }
        end
        --Supplies open existing behavior required by this suite.
        --@param specification table Test specification used to construct the fixture.
        --@return table|nil observed Outcome record with status opened; nil on alternate branches.
        --@return any|nil secondary2 Additional status or structured error from the fixture operation.
        function publication.open_existing(specification)
            calls.open_existing = (calls.open_existing or 0) + 1
            calls.last_open = specification
            if continuation.on_open then continuation.on_open() end
            if continuation.open_error then return nil, continuation.open_error end
            return {
                outcome = "opened",
                durable = true,
                context_path = physical_path,
                logical_path = logical_path,
                context_hash = "0123456789ABCDEF",
                display_name = "Task",
                generation = 7,
                event_count = 29,
                first_sequence = 1,
                last_sequence = 29,
                view_manifest_snapshot = "sha256:restored-view",
                auto_continue = continuation.auto_continue ~= false,
                unresolved_operation_ids = {},
                unresolved_tool_call_ids = {},
                unknown_operation_ids = {},
                unfinished_turn_ids = continuation.auto_continue == false
                    and { "turn-4" } or {},
                active_queue_item_ids = {},
                runtime_initial_serials = {
                    turn = 4, message = 8, request = 6, tool = 3,
                    operation = 2, queue = 5, queue_display = 2, ask = 1,
                },
            }
        end
        --Supplies turn context behavior required by this suite.
        --@param observation table Observed state supplied to the assertion.
        --@return table observed Structured fixture record with context_generation, overrides.
        function publication.turn_context(observation)
            calls.turn_context = (calls.turn_context or 0) + 1
            A.equal(observation.expected_context_generation, 7)
            return { context_generation = 7, overrides = {} }
        end
        --Simulates the close transition of a fake activity port for this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return boolean accepted Whether close succeeds in the fixture.
        function publication.close()
            calls.publication_close = (calls.publication_close or 0) + 1
            if publication_closed then return false end
            publication_closed = true
            return true
        end
        local export_document = { generation = 7 }
        components.context_catalog = {
            resolver = resolver, path = path,
            store = {
                --Returns the inspect import observation prepared for this suite.
                --@param target table|string Target selected for the exercised operation.
                --@param expected any Expected value used by the assertion.
                --@return any|nil value Callback value consumed by the enclosing scenario assertion.
                --@return any|nil secondary2 Additional status or structured error from the fixture operation.
                inspect_import = function(target, expected)
                calls.export_read = (calls.export_read or 0) + 1
                A.equal(target, physical_path)
                A.equal(expected, credential)
                if continuation.export_error then return nil, continuation.export_error end
                return export_document
            end },
            schema = {
                --Supplies export behavior required by this suite.
                --@param document table Parsed Context or configuration document under test.
                --@param sink any The sink supplied to the fake service for this scenario.
                --@param scan any The scan supplied to the fake service for this scenario.
                --@return string text Text emitted by the scenario callback.
                export = function(document, sink, scan)
                A.equal(document, export_document)
                A.equal(sink, nil)
                calls.export_format = (calls.export_format or 0) + 1
                calls.export_secret_scan = type(scan) == "function"
                return "# yaca Context export v1\n\nselected Context\n"
            end },
        }
        components.publication = publication
    end

    local app = assert(main.new(components, {
        product_name = "yaca",
        product_version = "0.1.0-dev",
        release_target = "linux-x86_64",
        config_path = CONFIG_PATH,
        maximum_draft_bytes = 4096,
    }))
    return app, calls, filesystem_controls
end

return {
    name = "integration/bootstrap",
    cases = {
        {
            name = "Model manager edits hidden fields and binds save to a reviewed draft",
            --Verifies model manager edits hidden fields and binds save to a reviewed draft.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify model manager edits hidden fields and binds save to a reviewed draft.
            run = function()
                local observed = config_editor_fixture({ "help", "show model-edit-1:1",
                    "set model-edit-1:1 Key", '"manager-private-key"',
                    "show model-edit-1:1", "save model-edit-2", "show model-edit-2:1",
                    "preview", "save model-edit-2" }, { action = "--model-repl" })
                A.equal(observed.code, 0, observed.stderr .. observed.output)
                A.contains(observed.output, "YACA MODEL MANAGER")
                A.contains(observed.output, "ModelEditorStale")
                A.contains(observed.output, "ModelPreviewRequired")
                A.contains(observed.output, "Models published offline")
                A.contains(observed.output, "test=untested")
                for _, secret in ipairs({ "bootstrap-secret", "manager-private-key" }) do
                    A.falsy(observed.output:find(secret, 1, true))
                    A.falsy(observed.stderr:find(secret, 1, true))
                end
                A.contains(observed.filesystem.bytes(observed.path), 'Key = "manager-private-key"')
                A.equal(observed.calls.process_starts, 0)
                A.deep_equal(observed.modes, { "cooked", "raw", "cooked" })
                A.equal(observed.restores, #observed.modes)
            end,
        },
        {
            name = "Model manager blank add supports back and reorders without copying existing credentials",
            --Verifies model manager blank add supports back and reorders without copying existing credentials.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify model manager blank add supports back and reorders without copying existing credentials.
            run = function()
                local observed = config_editor_fixture({ "add", "New", "", "", "https://other.example/chat",
                    "wrong-model", ".back", "new-model", "", "", "",
                    "move model-edit-2:2 1", "show model-edit-3:1", "preview", "save model-edit-3" },
                    { action = "--model-repl" })
                A.equal(observed.code, 0, observed.stderr .. observed.output)
                local bytes = observed.filesystem.bytes(observed.path)
                A.truthy(bytes:find("Model.New", 1, true) < bytes:find("Model.Primary", 1, true))
                A.contains(bytes, 'RemoteModel = "new-model"')
                local new = bytes:match("%[Model.New%](.-)%[Model.Primary%]")
                A.falsy(new:find("Key", 1, true))
                A.contains(observed.output, "Default Model: Primary -> New")
                A.falsy(observed.output:find("bootstrap-secret", 1, true))
                A.equal(observed.calls.process_starts, 0)
            end,
        },
        {
            name = "Model removal requires a complete Context scan and never writes after an unavailable preview",
            --Verifies model removal requires a complete Context scan and never writes after an unavailable preview.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify model removal requires a complete Context scan and never writes after an unavailable preview.
            run = function()
                local observed = config_editor_fixture({ "rename model-edit-1:1 Renamed", "preview",
                    "save model-edit-2", "quit" }, { action = "--model-repl" })
                A.equal(observed.code, 0, observed.stderr .. observed.output)
                A.contains(observed.output, "ModelPreviewRequired")
                A.equal(observed.filesystem.bytes(observed.path), observed.original)
                A.falsy(table.concat(observed.filesystem.operations, "|"):find("create:", 1, true))
            end,
        },
        {
            name = "Model manager renames after an empty complete Context scan and refuses a stale configuration",
            --Verifies model removal requires a complete Context scan and never writes after an unavailable preview.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify model removal requires a complete Context scan and never writes after an unavailable preview.
            run = function()
                --Supplies empty catalog behavior required by the 'Model manager renames after an empty complete Context scan and refuses a stale configuration' case.
                --@param native table Fake native port collection.
                --@return nil No value; assertions verify model removal requires a complete Context scan and never writes after an unavailable preview.
                local function empty_catalog(native)
                    --Supplies missing behavior required by the 'Model manager renames after an empty complete Context scan and refuses a stale configuration' case.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return boolean accepted Whether missing succeeds in the fixture.
                    --@return table secondary2 Typed error record with code NotFound.
                    local function missing() return false, { code = "NotFound", message = "absent catalog" } end
                    for _, method in ipairs({ "fs_inspect_direct", "fs_walk_direct", "fs_open_read_verified",
                        "fs_create_new_verified", "fs_replace_verified", "fs_rename_no_replace_verified",
                        "fs_delete_direct_verified" }) do native[method] = missing end
                end
                local observed = config_editor_fixture({ "rename model-edit-1:1 Renamed", "preview",
                    "save model-edit-2" }, { action = "--model-repl", native_setup = empty_catalog })
                A.equal(observed.code, 0, observed.stderr .. observed.output)
                A.contains(observed.output, "Affected Contexts: 0")
                A.contains(observed.filesystem.bytes(observed.path), "[Model.Renamed]")
                local raced = config_editor_fixture({ "set model-edit-1:1 RemoteModel", '"new-remote"',
                    "preview", "save model-edit-2", "quit" }, { action = "--model-repl",
                    --Changes fixture state before polling in the Model manager renames after an empty complete Context scan and refuses a stale configuration scenario.
                    --@param index integer One-based event or item position.
                    --@param filesystem table Fake filesystem whose operations are observed.
                    --@param path string File or Context path exercised by the case.
                    --@return nil No value; the fake port or test assertion observes this callback's effects.
                    before_poll = function(index, filesystem, path)
                        if index == 4 then filesystem.external_replace(path, valid_source()) end
                    end })
                A.equal(raced.code, 0, raced.stderr .. raced.output)
                A.contains(raced.output, "ConfigStale")
                A.equal(raced.filesystem.bytes(raced.path), valid_source())
            end,
        },
        {
            name = "Context REPL production dispatch enters the read-only loop without configuration",
            --Verifies context REPL production dispatch enters the read-only loop without configuration.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify context REPL production dispatch enters the read-only loop without configuration.
            run = function()
                --Constructs the fake lxp service used by the 'Context REPL production dispatch enters the read-only loop without configuration' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify context REPL production dispatch enters the read-only loop without configuration.
                cache.lxp = fake_lxp(function() error("read-only catalog must not parse Context bodies") end)
                local native, filesystem, calls, native_path = production_native()
                --Supplies missing behavior required by the 'Context REPL production dispatch enters the read-only loop without configuration' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether missing succeeds in the fixture.
                --@return table secondary2 Typed error record with code NotFound.
                local function missing() return false, { code = "NotFound", message = "absent catalog" } end
                for _, method in ipairs({ "fs_inspect_direct", "fs_walk_direct", "fs_open_read_verified",
                    "fs_create_new_verified", "fs_replace_verified", "fs_rename_no_replace_verified",
                    "fs_delete_direct_verified" }) do native[method] = missing end
                local polls, restores, output, errors = 0, 0, {}, {}
                local answers = { "list full", "refresh", "quit" }
                --Simulates terminal start in the Context REPL production dispatch enters the read-only loop without configuration fixture.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether terminal start succeeds in the fixture.
                --@return table secondary2 Empty structured fixture record.
                function native.terminal_start() return true, {} end
                --Simulates terminal poll in the Context REPL production dispatch enters the read-only loop without configuration fixture.
                --@param handle table|integer Fake resource handle whose state is inspected.
                --@return boolean accepted Whether terminal poll succeeds in the fixture.
                --@return table secondary2 Structured fixture record selected by the exercised branch.
                function native.terminal_poll(handle)
                    if handle.cancelled then return true, { { kind = "terminal", outcome = "cancelled" } } end
                    polls = polls + 1
                    if not answers[polls] then return true, { { kind = "action", intent = "eof" } } end
                    return true, { { kind = "action", intent = "text", text = answers[polls] .. "\n" } }
                end
                --Simulates terminal cancel in the Context REPL production dispatch enters the read-only loop without configuration fixture.
                --@param handle table|integer Fake resource handle whose state is inspected.
                --@return boolean accepted Whether terminal cancel succeeds in the fixture.
                --@return boolean secondary2 True acknowledgment from the fake port.
                function native.terminal_cancel(handle) handle.cancelled = true return true, true end
                --Simulates terminal join in the Context REPL production dispatch enters the read-only loop without configuration fixture.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether terminal join succeeds in the fixture.
                --@return table secondary2 Outcome record with status cancelled.
                function native.terminal_join() return true, { outcome = "cancelled" } end
                --Simulates terminal restore in the Context REPL production dispatch enters the read-only loop without configuration fixture.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether terminal restore succeeds in the fixture.
                --@return boolean secondary2 True acknowledgment from the fake port.
                function native.terminal_restore() restores = restores + 1 return true, true end
                --Simulates terminal close in the Context REPL production dispatch enters the read-only loop without configuration fixture.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether terminal close succeeds in the fixture.
                --@return boolean secondary2 True acknowledgment from the fake port.
                function native.terminal_close() return true, true end
                A.equal(main.run_cli({ [0] = "/release/yaca", "--context-repl", "full" }, {
                    native = native, native_path = native_path,
                    --Captures stdout bytes in the Context REPL production dispatch enters the read-only loop without configuration scenario.
                    --@param bytes string Byte chunk supplied to the fake I/O port.
                    --@return boolean accepted Whether the fake callback accepts this scenario.
                    stdout = function(bytes) output[#output + 1] = bytes return true end,
                    --Captures stderr bytes in the Context REPL production dispatch enters the read-only loop without configuration scenario.
                    --@param bytes string Byte chunk supplied to the fake I/O port.
                    --@return boolean accepted Whether the fake callback accepts this scenario.
                    stderr = function(bytes) errors[#errors + 1] = bytes return true end,
                }), 0)
                A.contains(table.concat(output), "YACA CONTEXT MANAGER")
                A.contains(table.concat(output), "CONTEXT CATALOG view=full")
                A.contains(table.concat(output), "Catalog rescanned; 0 Context(s)")
                A.equal(polls, 3); A.equal(restores, 1); A.equal(calls.process_starts, 0)
                A.falsy(filesystem.bytes(CONFIG_PATH)); A.deep_equal(errors, {})
            end,
        },
        {
            name = "configuration secret input restores the terminal even after its clock fails",
            --Verifies configuration secret input restores the terminal even after its clock fails.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify configuration secret input restores the terminal even after its clock fails.
            run = function()
                local settings = {}
                --Changes fixture state before polling in the configuration secret input restores the terminal even after its clock fails scenario.
                --@param index integer One-based event or item position.
                --@return nil No value; the fake port or test assertion observes this callback's effects.
                settings.before_poll = function(index)
                    if index == 2 then settings.clock_failed = true end
                end
                local observed = config_editor_fixture({ "set Network ProxyUrl", '"never-published-key"' }, settings)
                A.equal(observed.code, 1)
                A.contains(observed.stderr, "MonotonicClockDegraded")
                A.deep_equal(observed.modes, { "cooked", "raw" })
                A.equal(observed.restores, 2)
                A.equal(observed.filesystem.bytes(observed.path), observed.original)
                A.falsy(observed.output:find("never-published-key", 1, true))
            end,
        },
        {
            name = "configuration input retains cooked batches and rejects buffered values across a hidden boundary",
            --Verifies configuration secret input restores the terminal even after its clock fails.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify configuration secret input restores the terminal even after its clock fails.
            run = function()
                local batch = { batch = { { kind = "action", intent = "text",
                    text = "set General LogLevel\ndebug\npreview\nsave config-edit-2\n" } } }
                local observed = config_editor_fixture({ batch })
                A.equal(observed.code, 0, observed.stderr .. observed.output)
                A.equal(observed.polls, 1)
                A.contains(observed.filesystem.bytes(observed.path), "LogLevel = debug")
                local rejected = config_editor_fixture({ { batch = { { kind = "action", intent = "text",
                    text = 'set Network ProxyUrl\n"untrusted-buffered-key"\nsave config-edit-2\n' } } }, "quit" })
                A.equal(rejected.code, 0, rejected.stderr .. rejected.output)
                A.contains(rejected.output, "InputModeBoundary")
                A.falsy(rejected.output:find("untrusted-buffered-key", 1, true))
                A.equal(rejected.filesystem.bytes(rejected.path), rejected.original)
                A.deep_equal(rejected.modes, { "cooked" })
            end,
        },
        {
            name = "production config REPL previews and publishes typed fields with hidden credentials on both ports",
            --Verifies production config REPL previews and publishes typed fields with hidden credentials on both ports.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify production config REPL previews and publishes typed fields with hidden credentials on both ports.
            run = function()
                for _, settings in ipairs({ {}, { os = "windows", arch = "x86" } }) do
                    local observed = config_editor_fixture({
                        "help", "list", "show Model.Primary", "set General LogLevel", "debug",
                        "set TUI StartupShowVersion", "false", "set Model.Primary Key",
                        "set Network ProxyUrl", '"https://user:proxy-hidden-key@proxy.example"',
                        "preview", "save config-edit-4",
                    }, settings)
                    A.equal(observed.code, 0, observed.stderr .. observed.output)
                    A.contains(observed.output, "YACA CONFIGURATION EDITOR")
                    A.contains(observed.output, "CONFIG SECTIONS")
                    A.contains(observed.output, "General.LogLevel: \"info\" (default) -> \"debug\"")
                    A.contains(observed.output, "TUI.StartupShowVersion: true (default) -> false")
                    A.contains(observed.output, "Configuration published offline")
                    for _, secret in ipairs({ "bootstrap-secret", "new-hidden-key", "proxy-hidden-key" }) do
                        A.falsy(observed.output:find(secret, 1, true))
                        A.falsy(observed.stderr:find(secret, 1, true))
                    end
                    local bytes = observed.filesystem.bytes(observed.path)
                    A.contains(bytes, "; retained config comment")
                    A.contains(bytes, "LogLevel = debug")
                    A.contains(bytes, "StartupShowVersion = false")
                    A.contains(bytes, 'Key = "bootstrap-secret"')
                    A.contains(observed.output, "ModelEditorRequired")
                    A.contains(bytes, 'ProxyUrl = "https://user:proxy-hidden-key@proxy.example"')
                    A.equal(observed.calls.process_starts, 0)
                    A.equal(observed.calls.directory_creates, 0)
                    A.equal(observed.stderr, "")
                    A.deep_equal(observed.modes, { "cooked", "raw", "cooked" })
                    A.equal(observed.restores, #observed.modes)
                    for index = 1, #observed.output do A.truthy(observed.output:byte(index) <= 0x7F) end
                end
            end,
        },
        {
            name = "invalid configuration enters offline repair and publishes only explicit hidden line edits",
            --Verifies invalid configuration enters offline repair and publishes only explicit hidden line edits.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify invalid configuration enters offline repair and publishes only explicit hidden line edits.
            run = function()
                local valid = valid_source()
                local line = select(2, valid:gsub("\n", "")) + 1
                for _, settings in ipairs({ {}, { os = "windows", arch = "x86" } }) do
                    settings.source = valid .. 'Unknown = "unknown-private-value"\n'
                    local observed = config_editor_fixture({
                        "help", "list", "save config-repair-1",
                        "replace " .. tostring(line), "; replacement-private-comment",
                        "save config-repair-1", "preview", "save config-repair-2",
                    }, settings)
                    A.equal(observed.code, 0, observed.stderr .. observed.output)
                    A.contains(observed.output, "YACA CONFIGURATION REPAIR")
                    A.contains(observed.output, "VALIDATION FAILED")
                    A.contains(observed.output, "SCHEMA VALID / AGENT READY")
                    A.contains(observed.output, "ConfigEditorStale")
                    A.contains(observed.output, "Repaired configuration published offline")
                    for _, hidden in ipairs({ "bootstrap-secret", "unknown-private-value",
                        "replacement-private-comment" }) do
                        A.falsy(observed.output:find(hidden, 1, true))
                        A.falsy(observed.stderr:find(hidden, 1, true))
                    end
                    A.equal(observed.filesystem.bytes(observed.path), valid .. "; replacement-private-comment\n")
                    A.deep_equal(observed.modes, { "cooked", "raw", "cooked" })
                    A.equal(observed.restores, #observed.modes)
                    A.equal(observed.calls.process_starts, 0)
                    A.equal(observed.calls.directory_creates, 0)
                end
            end,
        },
        {
            name = "configuration repair reset cancel Esc and EOF preserve the damaged source",
            --Verifies configuration repair reset cancel Esc and EOF preserve the damaged source.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify configuration repair reset cancel Esc and EOF preserve the damaged source.
            run = function()
                local valid = valid_source()
                local original = valid .. "broken\n"
                local line = select(2, valid:gsub("\n", "")) + 1
                for _, ending in ipairs({ "quit", "cancel", { kind = "action", intent = "cancel" }, false }) do
                    local answers = { "delete " .. tostring(line), "reset", "validate" }
                    if ending then answers[#answers + 1] = ending end
                    local observed = config_editor_fixture(answers, { source = original })
                    A.equal(observed.code, ending == "quit" and 0 or 7, observed.stderr .. observed.output)
                    A.equal(observed.filesystem.bytes(observed.path), original)
                    A.falsy(table.concat(observed.filesystem.operations, "|"):find("create:", 1, true))
                    A.equal(observed.restores, #observed.modes)
                end
                local observed = config_editor_fixture({ "replace " .. tostring(line),
                    { kind = "action", intent = "cancel" } }, { source = original })
                A.equal(observed.code, 7, observed.stderr .. observed.output)
                A.deep_equal(observed.modes, { "cooked", "raw" })
                A.equal(observed.filesystem.bytes(observed.path), original)
                A.equal(observed.restores, #observed.modes)
            end,
        },
        {
            name = "configuration repair requires explicit reload after an external replacement",
            --Verifies configuration repair requires explicit reload after an external replacement.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify configuration repair requires explicit reload after an external replacement.
            run = function()
                local valid = valid_source()
                local original = valid .. "broken\n"
                local line = select(2, valid:gsub("\n", "")) + 1
                local observed = config_editor_fixture({
                    "delete " .. tostring(line), "save config-repair-2", "reload",
                    "delete " .. tostring(line), "save config-repair-4",
                }, { source = original,
                    --Changes fixture state before polling in the configuration repair requires explicit reload after an external replacement scenario.
                    --@param index integer One-based event or item position.
                    --@param filesystem table Fake filesystem whose operations are observed.
                    --@param path string File or Context path exercised by the case.
                    --@return nil No value; the fake port or test assertion observes this callback's effects.
                    before_poll = function(index, filesystem, path)
                    if index == 2 then filesystem.external_replace(path, original .. "; external\n") end
                    if index == 3 then
                        A.falsy(table.concat(filesystem.operations, "|"):find("create:", 1, true))
                    end
                end })
                A.equal(observed.code, 0, observed.stderr .. observed.output)
                A.contains(observed.output, "ConfigStale")
                A.equal(observed.filesystem.bytes(observed.path), valid .. "; external\n")
                A.equal(observed.calls.process_starts, 0)
            end,
        },
        {
            name = "configuration repair retries known publication failures and stops on uncertain durability",
            --Verifies configuration repair retries known publication failures and stops on uncertain durability.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify configuration repair retries known publication failures and stops on uncertain durability.
            run = function()
                local valid = valid_source()
                local line = select(2, valid:gsub("\n", "")) + 1
                local observed = config_editor_fixture({
                    "delete " .. tostring(line), "save config-repair-2", "preview", "save config-repair-2",
                }, { source = valid .. "broken\n",
                    --Changes fixture state before polling in the configuration repair retries known publication failures and stops on uncertain durability scenario.
                    --@param index integer One-based event or item position.
                    --@param filesystem table Fake filesystem whose operations are observed.
                    --@return nil No value; the fake port or test assertion observes this callback's effects.
                    before_poll = function(index, filesystem)
                    if index == 2 then filesystem.faults.replace = true end
                    if index == 4 then filesystem.faults.replace = false end
                end })
                A.equal(observed.code, 0, observed.stderr .. observed.output)
                A.contains(observed.output, "InjectedReplace")
                A.equal(observed.filesystem.bytes(observed.path), valid)
                observed = config_editor_fixture({ "delete " .. tostring(line), "save config-repair-2", "quit" },
                    { source = valid .. "broken\n",
                        --Changes fixture state before polling in the configuration repair retries known publication failures and stops on uncertain durability scenario.
                        --@param index integer One-based event or item position.
                        --@param filesystem table Fake filesystem whose operations are observed.
                        --@return nil No value; the fake port or test assertion observes this callback's effects.
                        before_poll = function(index, filesystem)
                        if index == 2 then filesystem.faults.flush_directory = true end
                    end })
                A.equal(observed.code, 1, observed.stderr .. observed.output)
                A.contains(observed.stderr, "ConfigPublishUnknown")
                A.equal(observed.polls, 2)
                A.equal(observed.restores, #observed.modes)
            end,
        },
        {
            name = "config REPL quit cancel Esc and EOF discard only its unsaved draft",
            --Verifies config REPL quit cancel Esc and EOF discard only its unsaved draft.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify config REPL quit cancel Esc and EOF discard only its unsaved draft.
            run = function()
                for _, ending in ipairs({ "quit", "cancel", { kind = "action", intent = "cancel" }, false }) do
                    local answers = { "set General SystemPrompt", '"unsaved guidance"', "preview" }
                    if ending then answers[#answers + 1] = ending end
                    local observed = config_editor_fixture(answers)
                    A.equal(observed.code, ending == "quit" and 0 or 7, observed.stderr)
                    A.equal(observed.filesystem.bytes(observed.path), observed.original)
                    A.falsy(table.concat(observed.filesystem.operations, "|"):find("create:", 1, true))
                    A.equal(observed.calls.process_starts, 0)
                    A.equal(observed.restores, #observed.modes)
                end
            end,
        },
        {
            name = "config REPL rejects invalid fields secrets bounds and stale save ids without losing the draft",
            --Verifies config REPL rejects invalid fields secrets bounds and stale save ids without losing the draft.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify config REPL rejects invalid fields secrets bounds and stale save ids without losing the draft.
            run = function()
                local observed = config_editor_fixture({
                    "set Agent QueueMaxItems", "0", "set General SystemPrompt", '"bootstrap-secret"',
                    "unset General SchemaVersion", "set General Unknown", "list 2",
                    "set General LogLevel", "debug", "save config-edit-1", "show General",
                    "preview", "save config-edit-2",
                })
                A.equal(observed.code, 0, observed.stderr .. observed.output)
                A.contains(observed.output, "registered-secret-cross-field")
                A.contains(observed.output, "UnknownConfigField")
                A.contains(observed.output, "ConfigEditorPage")
                A.contains(observed.output, "ConfigEditorStale")
                A.falsy(observed.output:find("bootstrap-secret", 1, true))
                A.contains(observed.filesystem.bytes(observed.path), "LogLevel = debug")
                A.falsy(observed.filesystem.bytes(observed.path):find("SystemPrompt", 1, true))
                A.equal(observed.stderr, "")
            end,
        },
        {
            name = "config REPL refuses concurrent replacement until explicit reload rebases the draft",
            --Verifies config REPL refuses concurrent replacement until explicit reload rebases the draft.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify config REPL refuses concurrent replacement until explicit reload rebases the draft.
            run = function()
                local external = "; external change retained\n" .. valid_source():gsub(
                    "SchemaVersion = 0.1.0", "SchemaVersion = 0.1.0\nLogLevel = warn", 1)
                local observed = config_editor_fixture({
                    "set General LogLevel", "debug", "preview", "save config-edit-2",
                    "reload", "set General LogLevel", "trace", "preview", "save config-edit-4",
                }, {
                    --Changes fixture state before polling in the config REPL refuses concurrent replacement until explicit reload rebases the draft scenario.
                    --@param index integer One-based event or item position.
                    --@param filesystem table Fake filesystem whose operations are observed.
                    --@param path string File or Context path exercised by the case.
                    --@return nil No value; the fake port or test assertion observes this callback's effects.
                    before_poll = function(index, filesystem, path)
                    if index == 4 then filesystem.external_replace(path, external) end
                    if index == 5 then
                        A.equal(filesystem.bytes(path), external)
                        A.falsy(table.concat(filesystem.operations, "|"):find("create:", 1, true))
                    end
                end })
                A.equal(observed.code, 0, observed.stderr .. observed.output)
                A.contains(observed.output, "ConfigStale")
                A.contains(observed.filesystem.bytes(observed.path), "; external change retained")
                A.contains(observed.filesystem.bytes(observed.path), "LogLevel = trace")
                A.equal(observed.calls.process_starts, 0)
            end,
        },
        {
            name = "config REPL retains a safe draft after known publication failure and stops on unknown durability",
            --Verifies config REPL retains a safe draft after known publication failure and stops on unknown durability.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify config REPL retains a safe draft after known publication failure and stops on unknown durability.
            run = function()
                local observed = config_editor_fixture({
                    "set General LogLevel", "debug", "save config-edit-2", "show General", "save config-edit-2",
                }, {
                    --Changes fixture state before polling in the config REPL retains a safe draft after known publication failure and stops on unknown durability scenario.
                    --@param index integer One-based event or item position.
                    --@param filesystem table Fake filesystem whose operations are observed.
                    --@return nil No value; the fake port or test assertion observes this callback's effects.
                    before_poll = function(index, filesystem)
                    if index == 3 then filesystem.faults.replace = true end
                    if index == 5 then filesystem.faults.replace = false end
                end })
                A.equal(observed.code, 0, observed.stderr .. observed.output)
                A.contains(observed.output, "InjectedReplace")
                A.contains(observed.filesystem.bytes(observed.path), "LogLevel = debug")
                local unknown = config_editor_fixture({ "set General LogLevel", "debug", "save config-edit-2" }, {
                    --Changes fixture state before polling in the config REPL retains a safe draft after known publication failure and stops on unknown durability scenario.
                    --@param index integer One-based event or item position.
                    --@param filesystem table Fake filesystem whose operations are observed.
                    --@return nil No value; the fake port or test assertion observes this callback's effects.
                    before_poll = function(index, filesystem)
                        if index == 3 then filesystem.faults.flush_directory = true end
                    end,
                })
                A.equal(unknown.code, 1)
                A.contains(unknown.stderr, "ConfigPublishUnknown")
                A.contains(unknown.filesystem.bytes(unknown.path), "LogLevel = debug")
                A.falsy(unknown.output:find("Configuration published", 1, true))
                A.equal(unknown.polls, 3)
                A.equal(unknown.restores, #unknown.modes)
            end,
        },
        {
            name = "production Prompt editor changes only the unsaved draft on Linux and old CMD",
            --Verifies production Prompt editor changes only the unsaved draft on Linux and old CMD.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify production Prompt editor changes only the unsaved draft on Linux and old CMD.
            run = function()
                for _, os_name in ipairs({ "linux", "windows" }) do
                    --Constructs the fake lxp service used by the 'production Prompt editor changes only the unsaved draft on Linux and old CMD' case.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return boolean accepted Whether the fake callback accepts this scenario.
                    --@return string secondary2 Fixture text "unsaved Prompt editing must not parse Context XML".
                    --@return integer secondary3 Fixture numeric value 1.
                    --@return integer secondary4 Fixture numeric value 1.
                    --@return integer secondary5 Fixture numeric value 1.
                    cache.lxp = fake_lxp(function()
                        return false, "unsaved Prompt editing must not parse Context XML", 1, 1, 1
                    end)
                    local native, files, calls, native_path, _, application_path, config_path
                        = production_native({ os = os_name })
                    files.external_replace(config_path, valid_source())
                    --Supplies unavailable behavior required by the 'production Prompt editor changes only the unsaved draft on Linux and old CMD' case.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return boolean accepted Whether unavailable succeeds in the fixture.
                    --@return table secondary2 Typed error record with code NotFound.
                    local function unavailable()
                        return false, { code = "NotFound", message = "Context path is absent" }
                    end
                    for _, name in ipairs({
                        "fs_inspect_direct", "fs_walk_direct", "fs_open_read_verified",
                        "fs_create_new_verified", "fs_replace_verified",
                        "fs_rename_no_replace_verified", "fs_delete_direct_verified",
                    }) do native[name] = unavailable end
                    local lines = {
                        ".prompt edit", ".clear", "draft guidance", "bootstrap-secret",
                        ".save prompt-edit-1", ".prompt show", ".quit",
                    }
                    --Simulates terminal start in the production Prompt editor changes only the unsaved draft on Linux and old CMD fixture.
                    --@param request table Request delivered to the fake component.
                    --@return boolean accepted Whether terminal start succeeds in the fixture.
                    --@return table secondary2 Empty structured fixture record.
                    function native.terminal_start(request)
                        A.equal(request.mode, "cooked")
                        return true, {}
                    end
                    --Simulates terminal poll in the production Prompt editor changes only the unsaved draft on Linux and old CMD fixture.
                    --@param handle table|integer Fake resource handle whose state is inspected.
                    --@return boolean accepted Whether terminal poll succeeds in the fixture.
                    --@return table secondary2 Structured fixture record selected by the exercised branch.
                    function native.terminal_poll(handle)
                        if handle.cancelled then
                            return true, { { kind = "terminal", outcome = "cancelled" } }
                        end
                        local line = table.remove(lines, 1)
                        if line == nil then
                            return true, { { kind = "terminal", outcome = "completed" } }
                        end
                        return true, {
                            { kind = "action", intent = "text", text = line },
                            { kind = "action", intent = "submit-or-queue" },
                        }
                    end
                    --Simulates terminal cancel in the production Prompt editor changes only the unsaved draft on Linux and old CMD fixture.
                    --@param handle table|integer Fake resource handle whose state is inspected.
                    --@return boolean accepted Whether terminal cancel succeeds in the fixture.
                    --@return boolean secondary2 True acknowledgment from the fake port.
                    function native.terminal_cancel(handle)
                        handle.cancelled = true
                        return true, true
                    end
                    --Simulates terminal join in the production Prompt editor changes only the unsaved draft on Linux and old CMD fixture.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return boolean accepted Whether terminal join succeeds in the fixture.
                    --@return table secondary2 Outcome record with status cancelled.
                    function native.terminal_join() return true, { outcome = "cancelled" } end
                    local stdout, stderr = {}, {}
                    A.equal(main.run_cli({ [0] = application_path }, {
                        native = native, native_path = native_path,
                        --Captures stdout bytes in the production Prompt editor changes only the unsaved draft on Linux and old CMD scenario.
                        --@param bytes string Byte chunk supplied to the fake I/O port.
                        --@return boolean accepted Whether the fake callback accepts this scenario.
                        stdout = function(bytes) stdout[#stdout + 1] = bytes return true end,
                        --Captures stderr bytes in the production Prompt editor changes only the unsaved draft on Linux and old CMD scenario.
                        --@param bytes string Byte chunk supplied to the fake I/O port.
                        --@return boolean accepted Whether the fake callback accepts this scenario.
                        stderr = function(bytes) stderr[#stderr + 1] = bytes return true end,
                    }), 0)
                    local rendered = table.concat(stdout)
                    A.contains(rendered, "Editing ContextPrompt in memory")
                    A.contains(rendered, "draft guidance")
                    A.contains(rendered, "RegisteredSecret")
                    A.falsy(rendered:find("bootstrap-secret", 1, true))
                    A.deep_equal(stderr, {})
                    A.equal(files.bytes(config_path), valid_source())
                    A.equal(calls.directory_creates, 0)
                    A.equal(calls.process_starts, 0)
                end
            end,
        },
        {
            name = "production export returns only verified Markdown and suppresses registered secrets",
            --Verifies production export returns only verified Markdown and suppresses registered secrets.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify production export returns only verified Markdown and suppresses registered secrets.
            run = function()
                local store_harness = load_table("test/support/context_store_harness.lua")
                local direct_harness = load_table("test/support/direct_filesystem_harness.lua")
                for _, secret in ipairs({ false, true }) do
                    local candidate = store_harness.minimal("Task")
                    candidate.session.context_prompt = secret and "bootstrap-secret" or "public context"
                    local fixture = store_harness.new({
                        context = load_module("context", cache),
                        xml = load_module("xml", cache),
                        fs = load_module("fs", cache),
                        fake_lxp = fake_lxp, sha256 = sha256, fake_filesystem = fake_filesystem,
                    })
                    local _, xml_bytes = fixture.document(candidate)
                    cache.lxp = fixture.lxp
                    local native, _, calls, native_path, data_root = production_native()
                    local target = data_root .. "/CONTEXT/workspace/Task.xml"
                    local direct, files = direct_harness.new({
                        [target] = xml_bytes,
                        [CONFIG_PATH] = valid_source(),
                        ["/workspace"] = { kind = "directory" },
                        ["/release/yaca"] = "outer",
                        ["/runtime/payload/yaca"] = "runtime",
                        [native_path] = "native",
                        ["/runtime/payload/.luai/components/curl"] = "curl",
                        ["/runtime/payload/.luai/components/cacert.pem"] = "ca",
                    })
                    for name, method in pairs(direct) do native[name] = method end
                    local stdout, stderr = {}, {}
                    local ports = {
                        native = native, native_path = native_path,
                        --Captures stdout bytes in the production export returns only verified Markdown and suppresses registered secrets scenario.
                        --@param bytes string Byte chunk supplied to the fake I/O port.
                        --@return boolean accepted Whether the fake callback accepts this scenario.
                        stdout = function(bytes) stdout[#stdout + 1] = bytes return true end,
                        --Captures stderr bytes in the production export returns only verified Markdown and suppresses registered secrets scenario.
                        --@param bytes string Byte chunk supplied to the fake I/O port.
                        --@return boolean accepted Whether the fake callback accepts this scenario.
                        stderr = function(bytes) stderr[#stderr + 1] = bytes return true end,
                    }
                    local code = main.run_cli({ [0] = "/release/yaca", "--export", "Task" }, ports)
                    if secret then
                        A.truthy(code ~= 0)
                        A.deep_equal(stdout, {})
                        A.contains(table.concat(stderr), "RegisteredSecret")
                        A.falsy(table.concat(stderr):find("bootstrap-secret", 1, true))
                    else
                        A.equal(code, 0)
                        local markdown = table.concat(stdout)
                        local heading = "# yaca Context export v1\n"
                        A.equal(markdown:sub(1, #heading), heading)
                        A.contains(markdown, "public context")
                        A.contains(markdown, "## Facts")
                        A.deep_equal(stderr, {})
                    end
                    A.equal(files.bytes(target), xml_bytes)
                    A.falsy(files.exists(target .. ".yaca-lock"))
                    A.falsy(files.exists(target .. ".yaca-prev"))
                    A.equal(calls.directory_creates, 0)
                    A.equal(calls.process_starts, 0)
                    stdout, stderr = {}, {}
                    --Simulates stdio facts in the production export returns only verified Markdown and suppresses registered secrets fixture.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return table record Fixture record emitted by the scenario callback.
                    native.stdio_facts = function()
                        return { stdin_is_tty = false, stdout_is_tty = false, stderr_is_tty = false }
                    end
                    A.equal(main.run_cli({ [0] = "/release/yaca", "--export", "Task" }, ports), 5)
                    A.deep_equal(stdout, {})
                end
            end,
        },
        {
            name = "selected export is read-only and keeps invalid config and history independent",
            --Verifies selected export is read-only and keeps invalid config and history independent.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify selected export is read-only and keeps invalid config and history independent.
            run = function()
                for _, source in ipairs({ false, "invalid INI", valid_source() }) do
                    local app, calls = application(source, {})
                    local result = assert(app.dispatch({ id = "export-context", selector = "Task" }))
                    A.equal(result.kind, "context-export")
                    A.contains(result.markdown, "# yaca Context export v1")
                    A.equal(result.context_hash, "0123456789ABCDEF")
                    A.equal(result.generation, 7)
                    A.equal(calls.catalog, 1)
                    A.equal(calls.verify, 2)
                    A.equal(calls.export_read, 1)
                    A.equal(calls.export_secret_scan, source == valid_source())
                    A.equal(calls.open_existing, nil)
                    A.equal(calls.network, 0)
                    A.equal(calls.agent, 0)
                    A.equal(calls.stage1, 0)
                    A.falsy(app.status().active_draft)
                end
            end,
        },
        {
            name = "export refuses missing current Context locks incomplete scans and changed targets",
            --Verifies export refuses missing current Context locks incomplete scans and changed targets.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify export refuses missing current Context locks incomplete scans and changed targets.
            run = function()
                local app, calls = application(false, {})
                local rejected, reject_error = app.dispatch({ id = "export-context" })
                A.falsy(rejected)
                A.equal(reject_error.code, "NoActiveContext")
                A.equal(calls.catalog, 0)
                A.equal(calls.config, 0)
                for _, setting in ipairs({
                    { resolve_tag = "ScanIncomplete", expected = "ScanIncomplete" },
                    { export_error = { code = "LockConflict" }, expected = "LockConflict" },
                    { export_error = { code = "ContextIntegrity" }, expected = "ContextIntegrity" },
                    { change_after_read = true, expected = "TargetChanged" },
                }) do
                    local selected, observed = application(valid_source(), setting)
                    rejected, reject_error = selected.dispatch({ id = "export-context", selector = "Task" })
                    A.falsy(rejected)
                    A.equal(reject_error.code, setting.expected)
                    A.equal(observed.catalog, 1)
                    A.equal(observed.open_existing, nil)
                    A.equal(observed.network, 0)
                end
            end,
        },
        {
            name = "packaged layout separates outer durable data from inner runtime resources",
            --Verifies packaged layout separates outer durable data from inner runtime resources.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify packaged layout separates outer durable data from inner runtime resources.
            run = function()
                local calls = {}
                local layout = assert(main.resolve_runtime_layout({
                    --Supplies executable paths behavior required by the 'packaged layout separates outer durable data from inner runtime resources' case.
                    --@param argv0 any The argv0 supplied to the fake service for this scenario.
                    --@return table record Fixture record emitted by the scenario callback.
                    executable_paths = function(argv0)
                        calls[#calls + 1] = argv0
                        return {
                            application = "/opt/yaca release/yaca",
                            runtime = "/tmp/luainstaller-onefile-42/payload/yaca",
                        }
                    end,
                }, "yaca", "linux-x86_64"))
                A.deep_equal(calls, { "yaca" })
                A.equal(layout.application_executable, "/opt/yaca release/yaca")
                A.equal(layout.runtime_executable, "/tmp/luainstaller-onefile-42/payload/yaca")
                A.equal(layout.application_root, "/opt/yaca release")
                A.equal(layout.runtime_root, "/tmp/luainstaller-onefile-42/payload")
                A.equal(layout.data_root, "/opt/yaca release/__yaca__")
                A.equal(
                    layout.config_path,
                    "/opt/yaca release/__yaca__/config.ini"
                )
                A.equal(
                    layout.curl_executable,
                    "/tmp/luainstaller-onefile-42/payload/.luai/components/curl"
                )
                A.equal(
                    layout.ca_bundle_path,
                    "/tmp/luainstaller-onefile-42/payload/.luai/components/cacert.pem"
                )
                --Executes the action expected to raise in the 'packaged layout separates outer durable data from inner runtime resources' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify packaged layout separates outer durable data from inner runtime resources.
                A.raises(function() layout.data_root = "/tmp/escape" end, "cannot be modified")
            end,
        },
        {
            name = "packaged layout rejects relative swapped and cross-target paths",
            --Verifies packaged layout rejects relative swapped and cross-target paths.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify packaged layout rejects relative swapped and cross-target paths.
            run = function()
                local relative, relative_error = main.resolve_runtime_layout({
                    --Supplies executable paths behavior required by the 'packaged layout rejects relative swapped and cross-target paths' case.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return table record Fixture record emitted by the scenario callback.
                    executable_paths = function()
                        return { application = "yaca", runtime = "/tmp/cache/yaca" }
                    end,
                }, "yaca", "linux-x86_64")
                A.falsy(relative)
                A.equal(relative_error.code, "InvalidExecutableLayout")

                local same, same_error = main.resolve_runtime_layout({
                    --Supplies executable paths behavior required by the 'packaged layout rejects relative swapped and cross-target paths' case.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return table record Fixture record emitted by the scenario callback.
                    executable_paths = function()
                        return {
                            application = "/tmp/cache/yaca",
                            runtime = "/tmp/cache/yaca",
                        }
                    end,
                }, "yaca", "linux-x86_64")
                A.falsy(same)
                A.equal(same_error.code, "InvalidExecutableLayout")

                local target, target_error = main.resolve_runtime_layout({
                    --Supplies executable paths behavior required by the 'packaged layout rejects relative swapped and cross-target paths' case.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return table record Fixture record emitted by the scenario callback.
                    executable_paths = function()
                        return {
                            application = "C:\\Yaca\\yaca.exe",
                            runtime = "C:\\Temp\\payload\\yaca.exe",
                        }
                    end,
                }, "yaca.exe", "linux-x86_64")
                A.falsy(target)
                A.equal(target_error.code, "InvalidExecutableLayout")
            end,
        },
        {
            name = "executable help and machine version use real fd facts without bootstrap reads",
            --Verifies executable help and machine version use real fd facts without bootstrap reads.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify executable help and machine version use real fd facts without bootstrap reads.
            run = function()
                local calls = { platform = 0, stdio = 0, paths = 0 }
                local native = {}
                --Simulates abi version in the executable help and machine version use real fd facts without bootstrap reads fixture.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return string outcome Simulated abi version outcome returned to the component.
                function native.abi_version() return "yaca-native-v0.1.0" end
                --Simulates platform identity in the executable help and machine version use real fd facts without bootstrap reads fixture.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return table outcome Simulated platform identity outcome returned to the component.
                function native.platform_identity()
                    calls.platform = calls.platform + 1
                    return { os = "linux", arch = "x86_64" }
                end
                --Simulates stdio facts in the executable help and machine version use real fd facts without bootstrap reads fixture.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return table outcome Simulated stdio facts outcome returned to the component.
                function native.stdio_facts()
                    calls.stdio = calls.stdio + 1
                    return {
                        stdin_is_tty = false,
                        stdout_is_tty = false,
                        stderr_is_tty = false,
                    }
                end
                --Simulates executable paths in the executable help and machine version use real fd facts without bootstrap reads fixture.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; the fake port or test assertion observes this callback's effects.
                function native.executable_paths()
                    calls.paths = calls.paths + 1
                    error("help and version must not resolve writable roots")
                end

                local stdout, stderr = {}, {}
                local ports = {
                    native = native,
                    --Captures stdout bytes in the executable help and machine version use real fd facts without bootstrap reads scenario.
                    --@param bytes string Byte chunk supplied to the fake I/O port.
                    --@return boolean accepted Whether the fake callback accepts this scenario.
                    stdout = function(bytes) stdout[#stdout + 1] = bytes return true end,
                    --Captures stderr bytes in the executable help and machine version use real fd facts without bootstrap reads scenario.
                    --@param bytes string Byte chunk supplied to the fake I/O port.
                    --@return boolean accepted Whether the fake callback accepts this scenario.
                    stderr = function(bytes) stderr[#stderr + 1] = bytes return true end,
                }
                A.equal(main.run_cli({ [0] = "/opt/yaca", "--help" }, ports), 0)
                A.contains(table.concat(stdout), "yaca: General-purpose terminal agent.")
                A.deep_equal(stderr, {})

                stdout = {}
                A.equal(main.run_cli({
                    [0] = "/opt/yaca", "--machine", "--version",
                }, ports), 0)
                local machine = table.concat(stdout)
                A.contains(machine, '"kind":"version"')
                A.contains(machine, '"outcome":"success"')
                A.contains(machine, '"release_target":"linux-x86_64"')
                A.equal(calls.platform, 2)
                A.equal(calls.stdio, 2)
                A.equal(calls.paths, 0)
            end,
        },
        {
            name = "executable entry maps typed usage and tty failures to stable exits",
            --Verifies executable entry maps typed usage and tty failures to stable exits.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify executable entry maps typed usage and tty failures to stable exits.
            run = function()
                local native = {
                    --Supplies abi version behavior required by the 'executable entry maps typed usage and tty failures to stable exits' case.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return string text Text emitted by the scenario callback.
                    abi_version = function() return "yaca-native-v0.1.0" end,
                    --Supplies platform identity behavior required by the 'executable entry maps typed usage and tty failures to stable exits' case.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return table record Fixture record emitted by the scenario callback.
                    platform_identity = function()
                        return { os = "linux", arch = "x86_64" }
                    end,
                    --Supplies stdio facts behavior required by the 'executable entry maps typed usage and tty failures to stable exits' case.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return table record Fixture record emitted by the scenario callback.
                    stdio_facts = function()
                        return {
                            stdin_is_tty = false,
                            stdout_is_tty = false,
                            stderr_is_tty = false,
                        }
                    end,
                }
                local stderr = {}
                local ports = {
                    native = native,
                    --Captures stdout bytes in the executable entry maps typed usage and tty failures to stable exits scenario.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return boolean accepted Whether the fake callback accepts this scenario.
                    stdout = function() return true end,
                    --Captures stderr bytes in the executable entry maps typed usage and tty failures to stable exits scenario.
                    --@param bytes string Byte chunk supplied to the fake I/O port.
                    --@return boolean accepted Whether the fake callback accepts this scenario.
                    stderr = function(bytes) stderr[#stderr + 1] = bytes return true end,
                }
                A.equal(main.run_cli({ [0] = "/opt/yaca", "--unknown" }, ports), 2)
                A.contains(table.concat(stderr), "UsageError")
                stderr = {}
                A.equal(main.run_cli({ [0] = "/opt/yaca" }, ports), 5)
                A.contains(table.concat(stderr), "TtyRequired")

                stderr = {}
                --Simulates the dispatch port for the 'executable entry maps typed usage and tty failures to stable exits' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil rejected Explicit rejection from the scenario callback.
                --@return table secondary2 Typed error record with code WorkspaceConfirmationRequired.
                ports.dispatch = function()
                    return nil, {
                        code = "WorkspaceConfirmationRequired",
                        message = "rerun from C:\\工作区",
                    }
                end
                A.equal(main.run_cli({
                    [0] = "/opt/yaca", "--self-test",
                }, ports), 5)
                local diagnostic = table.concat(stderr)
                A.contains(diagnostic, "WorkspaceConfirmationRequired")
                A.contains(diagnostic, "\\xE5\\xB7\\xA5")
                for index = 1, #diagnostic do
                    A.truthy(diagnostic:byte(index) <= 0x7F)
                end
            end,
        },
        {
            name = "production composition creates only an explicit offline repair template",
            --Verifies production composition creates only an explicit offline repair template.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify production composition creates only an explicit offline repair template.
            run = function()
                local native, filesystem, calls, native_path, data_root = production_native()
                local stdout, stderr = {}, {}
                local ports = {
                    native = native,
                    native_path = native_path,
                    --Captures stdout bytes in the production composition creates only an explicit offline repair template scenario.
                    --@param bytes string Byte chunk supplied to the fake I/O port.
                    --@return boolean accepted Whether the fake callback accepts this scenario.
                    stdout = function(bytes) stdout[#stdout + 1] = bytes return true end,
                    --Captures stderr bytes in the production composition creates only an explicit offline repair template scenario.
                    --@param bytes string Byte chunk supplied to the fake I/O port.
                    --@return boolean accepted Whether the fake callback accepts this scenario.
                    stderr = function(bytes) stderr[#stderr + 1] = bytes return true end,
                }
                A.equal(main.run_cli({
                    [0] = "/release/yaca", "--config-repl",
                }, ports), 0)
                local config_path = data_root .. "/config.ini"
                local template = filesystem.bytes(config_path)
                A.truthy(template)
                A.contains(template, "[Permission.Readonly]")
                A.contains(template, "Enabled = false")
                A.equal(filesystem.permissions(config_path), 384)
                A.equal(calls.directory_creates, 1)
                A.equal(calls.process_starts, 0)
                A.deep_equal(stderr, {})
                A.contains(table.concat(stdout), "repair template")

                stdout = {}
                --Simulates terminal poll in the production composition creates only an explicit offline repair template fixture.
                --@param handle table|integer Fake resource handle whose state is inspected.
                --@return boolean accepted Whether terminal poll succeeds in the fixture.
                --@return any secondary2 Additional status or structured error from the fixture operation.
                function native.terminal_poll(handle)
                    return true, handle.cancelled and { { kind = "terminal", outcome = "cancelled" } }
                        or { { kind = "action", intent = "text", text = "quit\n" } }
                end
                --Simulates terminal cancel in the production composition creates only an explicit offline repair template fixture.
                --@param handle table|integer Fake resource handle whose state is inspected.
                --@return boolean accepted Whether terminal cancel succeeds in the fixture.
                --@return boolean secondary2 True acknowledgment from the fake port.
                function native.terminal_cancel(handle)
                    handle.cancelled = true
                    return true, true
                end
                --Simulates terminal join in the production composition creates only an explicit offline repair template fixture.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether terminal join succeeds in the fixture.
                --@return table secondary2 Outcome record with status cancelled.
                function native.terminal_join() return true, { outcome = "cancelled" } end
                A.equal(main.run_cli({
                    [0] = "/release/yaca", "--config-repl",
                }, ports), 0, table.concat(stderr) .. table.concat(stdout))
                A.equal(filesystem.bytes(config_path), template)
                A.equal(calls.directory_creates, 1)
                A.equal(calls.process_starts, 0)
                A.contains(table.concat(stdout), "YACA CONFIGURATION REPAIR")

                --Simulates workspace inspect in the production composition creates only an explicit offline repair template fixture.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return table record Fixture record emitted by the scenario callback.
                native.workspace_inspect = function()
                    return {
                        path = "/workspace",
                        enterable = true,
                        identity = {
                            kind = "directory",
                            volume = "fake-volume",
                            object = "workspace",
                            size = 0,
                            modified = "1",
                            alias = "not-an-identity-field",
                        },
                    }
                end
                stdout, stderr = {}, {}
                A.equal(main.run_cli({ [0] = "/release/yaca" }, ports), 1)
                A.contains(table.concat(stderr), "InvalidWorkspace")
                A.equal(calls.process_starts, 0)
            end,
        },
        {
            name = "production context catalog renders an empty bounded snapshot",
            --Verifies production context catalog renders an empty bounded snapshot.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify production context catalog renders an empty bounded snapshot.
            run = function()
                --Constructs the fake lxp service used by the 'production context catalog renders an empty bounded snapshot' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether the fake callback accepts this scenario.
                --@return string secondary2 Fixture text "empty catalog must not parse Context XML".
                --@return integer secondary3 Fixture numeric value 1.
                --@return integer secondary4 Fixture numeric value 1.
                --@return integer secondary5 Fixture numeric value 1.
                cache.lxp = fake_lxp(function()
                    return false, "empty catalog must not parse Context XML", 1, 1, 1
                end)
                local native, _, calls, native_path = production_native()
                --Supplies not found behavior required by the 'production context catalog renders an empty bounded snapshot' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether not found succeeds in the fixture.
                --@return table secondary2 Typed error record with code NotFound.
                local function not_found()
                    return false, { code = "NotFound", message = "catalog path is absent" }
                end
                native.fs_inspect_direct = not_found
                native.fs_walk_direct = not_found
                native.fs_open_read_verified = not_found
                native.fs_create_new_verified = not_found
                native.fs_replace_verified = not_found
                native.fs_rename_no_replace_verified = not_found
                native.fs_delete_direct_verified = not_found
                local stdout, stderr = {}, {}
                local ports = {
                    native = native,
                    native_path = native_path,
                    --Captures stdout bytes in the production context catalog renders an empty bounded snapshot scenario.
                    --@param bytes string Byte chunk supplied to the fake I/O port.
                    --@return boolean accepted Whether the fake callback accepts this scenario.
                    stdout = function(bytes) stdout[#stdout + 1] = bytes return true end,
                    --Captures stderr bytes in the production context catalog renders an empty bounded snapshot scenario.
                    --@param bytes string Byte chunk supplied to the fake I/O port.
                    --@return boolean accepted Whether the fake callback accepts this scenario.
                    stderr = function(bytes) stderr[#stderr + 1] = bytes return true end,
                }
                --Simulates terminal start in the production context catalog renders an empty bounded snapshot fixture.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether terminal start succeeds in the fixture.
                --@return table secondary2 Empty structured fixture record.
                function native.terminal_start() return true, {} end
                --Simulates terminal poll in the production context catalog renders an empty bounded snapshot fixture.
                --@param handle table|integer Fake resource handle whose state is inspected.
                --@return boolean accepted Whether terminal poll succeeds in the fixture.
                --@return any secondary2 Additional status or structured error from the fixture operation.
                function native.terminal_poll(handle)
                    return true, handle.cancelled and { { kind = "terminal", outcome = "cancelled" } }
                        or { { kind = "action", intent = "text", text = "quit\n" } }
                end
                --Simulates terminal cancel in the production context catalog renders an empty bounded snapshot fixture.
                --@param handle table|integer Fake resource handle whose state is inspected.
                --@return boolean accepted Whether terminal cancel succeeds in the fixture.
                --@return boolean secondary2 True acknowledgment from the fake port.
                function native.terminal_cancel(handle) handle.cancelled = true return true, true end
                --Simulates terminal join in the production context catalog renders an empty bounded snapshot fixture.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether terminal join succeeds in the fixture.
                --@return table secondary2 Outcome record with status cancelled.
                function native.terminal_join() return true, { outcome = "cancelled" } end
                --Simulates terminal restore in the production context catalog renders an empty bounded snapshot fixture.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether terminal restore succeeds in the fixture.
                --@return boolean secondary2 True acknowledgment from the fake port.
                function native.terminal_restore() return true, true end
                --Simulates terminal close in the production context catalog renders an empty bounded snapshot fixture.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether terminal close succeeds in the fixture.
                --@return boolean secondary2 True acknowledgment from the fake port.
                function native.terminal_close() return true, true end
                A.equal(main.run_cli({
                    [0] = "/release/yaca", "--context-repl", "recent",
                }, ports), 0)
                local rendered = table.concat(stdout)
                A.contains(rendered, "CONTEXT CATALOG view=recent")
                A.contains(rendered, "No matching Contexts were found.")
                A.contains(rendered, "Total: 0")
                A.deep_equal(stderr, {})
                A.equal(calls.process_starts, 0)

                stdout, stderr = {}, {}
                A.equal(main.run_cli({
                    [0] = "/release/yaca", "--config-repl",
                }, ports), 0)
                stdout, stderr = {}, {}
                A.equal(main.run_cli({
                    [0] = "/release/yaca",
                    "--self-test",
                    "--through-stage", "1",
                    "--check", "ST1-CONTEXT-LOCK",
                }, ports), 1)
                rendered = table.concat(stdout)
                A.contains(rendered, "ST1-CONTEXT-CATALOG PASSED")
                A.contains(rendered, "ST1-CONTEXT-LOCK PASSED")
                A.falsy(rendered:find("not yet attached", 1, true))
                A.deep_equal(stderr, {})
            end,
        },
        {
            name = "production model setup replaces only its template and hides the Key",
            --Verifies production model setup replaces only its template and hides the Key.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify production model setup replaces only its template and hides the Key.
            run = function()
                --Constructs the fake lxp service used by the 'production model setup replaces only its template and hides the Key' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether the fake callback accepts this scenario.
                --@return string secondary2 Fixture text "Model setup must not parse Context XML".
                --@return integer secondary3 Fixture numeric value 1.
                --@return integer secondary4 Fixture numeric value 1.
                --@return integer secondary5 Fixture numeric value 1.
                cache.lxp = fake_lxp(function()
                    return false, "Model setup must not parse Context XML", 1, 1, 1
                end)
                local native, filesystem, calls, native_path = production_native()
                local stdout, stderr = {}, {}
                local ports = {
                    native = native,
                    native_path = native_path,
                    --Captures stdout bytes in the production model setup replaces only its template and hides the Key scenario.
                    --@param bytes string Byte chunk supplied to the fake I/O port.
                    --@return boolean accepted Whether the fake callback accepts this scenario.
                    stdout = function(bytes) stdout[#stdout + 1] = bytes return true end,
                    --Captures stderr bytes in the production model setup replaces only its template and hides the Key scenario.
                    --@param bytes string Byte chunk supplied to the fake I/O port.
                    --@return boolean accepted Whether the fake callback accepts this scenario.
                    stderr = function(bytes) stderr[#stderr + 1] = bytes return true end,
                }
                A.equal(main.run_cli({
                    [0] = "/release/yaca", "--config-repl",
                }, ports), 0)
                A.contains(assert(filesystem.bytes(CONFIG_PATH)), "Enabled = false")

                local answers = {
                    "", -- Primary
                    "", -- openai-chat
                    "", -- enabled=yes
                    "https://api.example/v1/chat",
                    "remote-main",
                    "0", -- rejected before any publication
                    "", -- context length=32768
                    "32768", -- output must be smaller than the context window
                    "", -- maximum output=4096
                    "super-secret-key",
                    "APPLY",
                }
                local answer_index = 0
                local modes = {}
                --Simulates terminal start in the production model setup replaces only its template and hides the Key fixture.
                --@param request table Request delivered to the fake component.
                --@return boolean accepted Whether terminal start succeeds in the fixture.
                --@return table secondary2 Structured fixture record with mode.
                function native.terminal_start(request)
                    modes[#modes + 1] = request.mode
                    return true, { mode = request.mode }
                end
                --Simulates terminal poll in the production model setup replaces only its template and hides the Key fixture.
                --@param handle table|integer Fake resource handle whose state is inspected.
                --@return boolean accepted Whether terminal poll succeeds in the fixture.
                --@return table secondary2 Structured fixture record selected by the exercised branch.
                function native.terminal_poll(handle)
                    if handle.cancelled then
                        return true, { { kind = "terminal", outcome = "cancelled" } }
                    end
                    answer_index = answer_index + 1
                    local answer = answers[answer_index]
                    if answer == nil then return true, {} end
                    return true, {
                        { kind = "action", intent = "text", text = answer .. "\n" },
                    }
                end
                --Simulates terminal cancel in the production model setup replaces only its template and hides the Key fixture.
                --@param handle table|integer Fake resource handle whose state is inspected.
                --@return boolean accepted Whether terminal cancel succeeds in the fixture.
                --@return boolean secondary2 True acknowledgment from the fake port.
                function native.terminal_cancel(handle)
                    handle.cancelled = true
                    return true, true
                end
                --Simulates terminal join in the production model setup replaces only its template and hides the Key fixture.
                --@param handle table|integer Fake resource handle whose state is inspected.
                --@return boolean accepted Whether terminal join succeeds in the fixture.
                --@return table secondary2 Outcome record with status cancelled.
                function native.terminal_join(handle)
                    A.truthy(handle.cancelled)
                    return true, { outcome = "cancelled" }
                end
                --Simulates terminal restore in the production model setup replaces only its template and hides the Key fixture.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether terminal restore succeeds in the fixture.
                --@return boolean secondary2 True acknowledgment from the fake port.
                function native.terminal_restore() return true, true end
                --Simulates terminal close in the production model setup replaces only its template and hides the Key fixture.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether terminal close succeeds in the fixture.
                --@return boolean secondary2 True acknowledgment from the fake port.
                function native.terminal_close() return true, true end

                stdout, stderr = {}, {}
                A.equal(main.run_cli({
                    [0] = "/release/yaca", "--model-repl",
                }, ports), 0)
                local rendered = table.concat(stdout)
                A.contains(rendered, "YACA MODEL SETUP")
                A.contains(rendered, "[hidden]")
                A.contains(rendered, "was published offline")
                A.falsy(rendered:find("super-secret-key", 1, true))
                local published = assert(filesystem.bytes(CONFIG_PATH))
                A.contains(published, "Enabled = true")
                A.contains(published, "Endpoint = \"https://api.example/v1/chat\"")
                A.contains(published, "RemoteModel = \"remote-main\"")
                A.contains(published, "ContextLength = 32768")
                A.contains(published, "MaxOutputTokens = 4096")
                A.contains(published, "Key = \"super-secret-key\"")
                A.deep_equal(modes, { "cooked", "raw", "cooked" })
                A.equal(answer_index, #answers)
                A.equal(calls.process_starts, 0)
                A.deep_equal(stderr, {})
            end,
        },
        {
            name = "cancelled Model setup creates no data or configuration",
            --Verifies cancelled Model setup creates no data or configuration.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify cancelled Model setup creates no data or configuration.
            run = function()
                --Constructs the fake lxp service used by the 'cancelled Model setup creates no data or configuration' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether the fake callback accepts this scenario.
                --@return string secondary2 Fixture text "cancelled setup must not parse XML".
                --@return integer secondary3 Fixture numeric value 1.
                --@return integer secondary4 Fixture numeric value 1.
                --@return integer secondary5 Fixture numeric value 1.
                cache.lxp = fake_lxp(function()
                    return false, "cancelled setup must not parse XML", 1, 1, 1
                end)
                local native, filesystem, calls, native_path = production_native()
                local polls = 0
                --Simulates terminal start in the cancelled Model setup creates no data or configuration fixture.
                --@param request table Request delivered to the fake component.
                --@return boolean accepted Whether terminal start succeeds in the fixture.
                --@return table secondary2 Empty structured fixture record.
                function native.terminal_start(request)
                    A.equal(request.mode, "cooked")
                    return true, {}
                end
                --Simulates terminal poll in the cancelled Model setup creates no data or configuration fixture.
                --@param handle table|integer Fake resource handle whose state is inspected.
                --@return boolean accepted Whether terminal poll succeeds in the fixture.
                --@return table secondary2 Structured fixture record selected by the exercised branch.
                function native.terminal_poll(handle)
                    if handle.cancelled then
                        return true, { { kind = "terminal", outcome = "cancelled" } }
                    end
                    polls = polls + 1
                    return true, { { kind = "action", intent = "cancel" } }
                end
                --Simulates terminal cancel in the cancelled Model setup creates no data or configuration fixture.
                --@param handle table|integer Fake resource handle whose state is inspected.
                --@return boolean accepted Whether terminal cancel succeeds in the fixture.
                --@return boolean secondary2 True acknowledgment from the fake port.
                function native.terminal_cancel(handle)
                    handle.cancelled = true
                    return true, true
                end
                --Simulates terminal join in the cancelled Model setup creates no data or configuration fixture.
                --@param handle table|integer Fake resource handle whose state is inspected.
                --@return boolean accepted Whether terminal join succeeds in the fixture.
                --@return table secondary2 Outcome record with status cancelled.
                function native.terminal_join(handle)
                    A.truthy(handle.cancelled)
                    return true, { outcome = "cancelled" }
                end
                --Simulates terminal restore in the cancelled Model setup creates no data or configuration fixture.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether terminal restore succeeds in the fixture.
                --@return boolean secondary2 True acknowledgment from the fake port.
                function native.terminal_restore() return true, true end
                --Simulates terminal close in the cancelled Model setup creates no data or configuration fixture.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether terminal close succeeds in the fixture.
                --@return boolean secondary2 True acknowledgment from the fake port.
                function native.terminal_close() return true, true end
                local stdout, stderr = {}, {}
                local exit_code = main.run_cli({
                    [0] = "/release/yaca", "--model-repl",
                }, {
                    native = native,
                    native_path = native_path,
                    --Captures stdout bytes in the cancelled Model setup creates no data or configuration scenario.
                    --@param bytes string Byte chunk supplied to the fake I/O port.
                    --@return boolean accepted Whether the fake callback accepts this scenario.
                    stdout = function(bytes) stdout[#stdout + 1] = bytes return true end,
                    --Captures stderr bytes in the cancelled Model setup creates no data or configuration scenario.
                    --@param bytes string Byte chunk supplied to the fake I/O port.
                    --@return boolean accepted Whether the fake callback accepts this scenario.
                    stderr = function(bytes) stderr[#stderr + 1] = bytes return true end,
                })
                A.equal(exit_code, 7)
                A.equal(polls, 1)
                A.falsy(filesystem.exists(CONFIG_PATH))
                A.equal(calls.directory_creates, 0)
                A.equal(calls.process_starts, 0)
                A.contains(table.concat(stdout), "no configuration was changed")
                A.deep_equal(stderr, {})
            end,
        },
        {
            name = "synthetic WinXP CMD setup uses cooked lines and ASCII output",
            --Verifies synthetic WinXP CMD setup uses cooked lines and ASCII output.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify synthetic WinXP CMD setup uses cooked lines and ASCII output.
            run = function()
                --Constructs the fake lxp service used by the 'synthetic WinXP CMD setup uses cooked lines and ASCII output' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether the fake callback accepts this scenario.
                --@return string secondary2 Fixture text "Model setup must not parse Context XML".
                --@return integer secondary3 Fixture numeric value 1.
                --@return integer secondary4 Fixture numeric value 1.
                --@return integer secondary5 Fixture numeric value 1.
                cache.lxp = fake_lxp(function()
                    return false, "Model setup must not parse Context XML", 1, 1, 1
                end)
                local native, filesystem, calls, native_path, _, application_path,
                    config_path = production_native({ os = "windows", arch = "x86" })
                local answers = {
                    "主要", -- UTF-8 is transported by the native wide-console path.
                    "", -- openai-chat
                    "no", -- rejected because a first configuration needs one enabled Model.
                    "yes",
                    "https://api.example/v1/chat",
                    "remote-main",
                    "128000",
                    "8192",
                    "xp-secret-key",
                    "APPLY",
                }
                local answer_index = 0
                local modes = {}
                --Simulates terminal start in the synthetic WinXP CMD setup uses cooked lines and ASCII output fixture.
                --@param request table Request delivered to the fake component.
                --@return boolean accepted Whether terminal start succeeds in the fixture.
                --@return table secondary2 Structured fixture record with mode.
                function native.terminal_start(request)
                    modes[#modes + 1] = request.mode
                    return true, { mode = request.mode }
                end
                --Simulates terminal poll in the synthetic WinXP CMD setup uses cooked lines and ASCII output fixture.
                --@param handle table|integer Fake resource handle whose state is inspected.
                --@return boolean accepted Whether terminal poll succeeds in the fixture.
                --@return table secondary2 Structured fixture record selected by the exercised branch.
                function native.terminal_poll(handle)
                    if handle.cancelled then
                        return true, { { kind = "terminal", outcome = "cancelled" } }
                    end
                    answer_index = answer_index + 1
                    local answer = answers[answer_index]
                    if answer == nil then return true, {} end
                    return true, {
                        { kind = "action", intent = "text", text = answer .. "\r\n" },
                    }
                end
                --Simulates terminal cancel in the synthetic WinXP CMD setup uses cooked lines and ASCII output fixture.
                --@param handle table|integer Fake resource handle whose state is inspected.
                --@return boolean accepted Whether terminal cancel succeeds in the fixture.
                --@return boolean secondary2 True acknowledgment from the fake port.
                function native.terminal_cancel(handle)
                    handle.cancelled = true
                    return true, true
                end
                --Simulates terminal join in the synthetic WinXP CMD setup uses cooked lines and ASCII output fixture.
                --@param handle table|integer Fake resource handle whose state is inspected.
                --@return boolean accepted Whether terminal join succeeds in the fixture.
                --@return table secondary2 Outcome record with status cancelled.
                function native.terminal_join(handle)
                    A.truthy(handle.cancelled)
                    return true, { outcome = "cancelled" }
                end
                --Simulates terminal restore in the synthetic WinXP CMD setup uses cooked lines and ASCII output fixture.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether terminal restore succeeds in the fixture.
                --@return boolean secondary2 True acknowledgment from the fake port.
                function native.terminal_restore() return true, true end
                --Simulates terminal close in the synthetic WinXP CMD setup uses cooked lines and ASCII output fixture.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether terminal close succeeds in the fixture.
                --@return boolean secondary2 True acknowledgment from the fake port.
                function native.terminal_close() return true, true end

                local stdout, stderr = {}, {}
                local exit_code = main.run_cli({
                    [0] = application_path, "--model-repl",
                }, {
                    native = native,
                    native_path = native_path,
                    --Captures stdout bytes in the synthetic WinXP CMD setup uses cooked lines and ASCII output scenario.
                    --@param bytes string Byte chunk supplied to the fake I/O port.
                    --@return boolean accepted Whether the fake callback accepts this scenario.
                    stdout = function(bytes) stdout[#stdout + 1] = bytes return true end,
                    --Captures stderr bytes in the synthetic WinXP CMD setup uses cooked lines and ASCII output scenario.
                    --@param bytes string Byte chunk supplied to the fake I/O port.
                    --@return boolean accepted Whether the fake callback accepts this scenario.
                    stderr = function(bytes) stderr[#stderr + 1] = bytes return true end,
                })
                A.equal(exit_code, 0)
                local rendered = table.concat(stdout)
                for index = 1, #rendered do
                    local byte = rendered:byte(index)
                    A.truthy(
                        byte == 0x09 or byte == 0x0A or byte == 0x0D
                            or (byte >= 0x20 and byte <= 0x7E),
                        "non-ASCII WinXP transcript byte at " .. tostring(index)
                    )
                end
                A.contains(rendered, "At least one Model must remain enabled")
                A.contains(rendered, "Model.\\xE4\\xB8\\xBB\\xE8\\xA6\\x81")
                A.contains(rendered, "[hidden]")
                A.falsy(rendered:find("xp-secret-key", 1, true))
                local published = assert(filesystem.bytes(config_path))
                A.contains(published, "[Model.主要]")
                A.contains(published, "Key = \"xp-secret-key\"")
                A.contains(published, "ContextLength = 128000")
                A.contains(published, "MaxOutputTokens = 8192")
                A.deep_equal(modes, { "cooked", "raw", "cooked" })
                A.equal(answer_index, #answers)
                A.equal(calls.directory_creates, 1)
                A.equal(calls.process_starts, 0)
                A.deep_equal(stderr, {})
            end,
        },
        {
            name = "Model setup publishes nothing when terminal restoration is unknown",
            --Verifies model setup publishes nothing when terminal restoration is unknown.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify model setup publishes nothing when terminal restoration is unknown.
            run = function()
                --Constructs the fake lxp service used by the 'Model setup publishes nothing when terminal restoration is unknown' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether the fake callback accepts this scenario.
                --@return string secondary2 Fixture text "failed setup must not parse Context XML".
                --@return integer secondary3 Fixture numeric value 1.
                --@return integer secondary4 Fixture numeric value 1.
                --@return integer secondary5 Fixture numeric value 1.
                cache.lxp = fake_lxp(function()
                    return false, "failed setup must not parse Context XML", 1, 1, 1
                end)
                local native, filesystem, calls, native_path = production_native()
                local answers = {
                    "", "", "", "https://api.example/v1/chat",
                    "remote-main", "", "", "secret-before-restore", "APPLY",
                }
                local answer_index = 0
                local restores = 0
                --Simulates terminal start in the Model setup publishes nothing when terminal restoration is unknown fixture.
                --@param request table Request delivered to the fake component.
                --@return boolean accepted Whether terminal start succeeds in the fixture.
                --@return table secondary2 Structured fixture record with mode.
                function native.terminal_start(request)
                    return true, { mode = request.mode }
                end
                --Simulates terminal poll in the Model setup publishes nothing when terminal restoration is unknown fixture.
                --@param handle table|integer Fake resource handle whose state is inspected.
                --@return boolean accepted Whether terminal poll succeeds in the fixture.
                --@return table secondary2 Structured fixture record selected by the exercised branch.
                function native.terminal_poll(handle)
                    if handle.cancelled then
                        return true, { { kind = "terminal", outcome = "cancelled" } }
                    end
                    answer_index = answer_index + 1
                    return true, {
                        {
                            kind = "action",
                            intent = "text",
                            text = assert(answers[answer_index]) .. "\n",
                        },
                    }
                end
                --Simulates terminal cancel in the Model setup publishes nothing when terminal restoration is unknown fixture.
                --@param handle table|integer Fake resource handle whose state is inspected.
                --@return boolean accepted Whether terminal cancel succeeds in the fixture.
                --@return boolean secondary2 True acknowledgment from the fake port.
                function native.terminal_cancel(handle)
                    handle.cancelled = true
                    return true, true
                end
                --Simulates terminal join in the Model setup publishes nothing when terminal restoration is unknown fixture.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether terminal join succeeds in the fixture.
                --@return table secondary2 Outcome record with status cancelled.
                function native.terminal_join()
                    return true, { outcome = "cancelled" }
                end
                --Simulates terminal restore in the Model setup publishes nothing when terminal restoration is unknown fixture.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether terminal restore succeeds in the fixture.
                --@return table|boolean secondary2 Additional status or structured error from the fixture operation.
                function native.terminal_restore()
                    restores = restores + 1
                    if restores == 3 then
                        return false, {
                            code = "RestoreUnknown",
                            message = "terminal mode restoration is unknown",
                        }
                    end
                    return true, true
                end
                --Simulates terminal close in the Model setup publishes nothing when terminal restoration is unknown fixture.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return boolean accepted Whether terminal close succeeds in the fixture.
                --@return boolean secondary2 True acknowledgment from the fake port.
                function native.terminal_close() return true, true end

                local stdout, stderr = {}, {}
                local exit_code = main.run_cli({
                    [0] = "/release/yaca", "--model-repl",
                }, {
                    native = native,
                    native_path = native_path,
                    --Captures stdout bytes in the Model setup publishes nothing when terminal restoration is unknown scenario.
                    --@param bytes string Byte chunk supplied to the fake I/O port.
                    --@return boolean accepted Whether the fake callback accepts this scenario.
                    stdout = function(bytes) stdout[#stdout + 1] = bytes return true end,
                    --Captures stderr bytes in the Model setup publishes nothing when terminal restoration is unknown scenario.
                    --@param bytes string Byte chunk supplied to the fake I/O port.
                    --@return boolean accepted Whether the fake callback accepts this scenario.
                    stderr = function(bytes) stderr[#stderr + 1] = bytes return true end,
                })
                A.equal(exit_code, 1)
                A.equal(answer_index, #answers)
                A.equal(restores, 3)
                A.falsy(filesystem.exists(CONFIG_PATH))
                A.equal(calls.directory_creates, 0)
                A.equal(calls.process_starts, 0)
                A.falsy(table.concat(stdout):find("was published", 1, true))
                A.falsy(table.concat(stdout):find("secret-before-restore", 1, true))
                A.contains(table.concat(stderr), "TerminalFailure")
            end,
        },
        {
            name = "construction help and version perform no probes reads scans or network",
            --Verifies construction help and version perform no probes reads scans or network.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify construction help and version perform no probes reads scans or network.
            run = function()
                local app, calls = application(nil)
                A.deep_equal(app.status(), {
                    lifecycle = "constructed",
                    active_draft = false,
                    platform_checked = false,
                })
                local help = assert(app.dispatch({ id = "help" }))
                local version = assert(app.dispatch({ id = "version", machine = true }))
                A.equal(help.outcome, "success")
                A.equal(version.version, "0.1.0-dev")
                A.equal(calls.platform, 0)
                A.equal(calls.config, 0)
                A.equal(calls.workspace, 0)
                A.equal(calls.stage1, 0)
                A.equal(calls.management, 0)
                A.equal(calls.catalog, 0)
                A.equal(calls.network, 0)
                A.equal(calls.agent, 0)
            end,
        },
        {
            name = "status is read-only and reports missing invalid and valid configuration",
            --Verifies status is read-only and reports missing invalid and valid configuration.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify status is read-only and reports missing invalid and valid configuration.
            run = function()
                for _, source in ipairs({ false, "invalid INI", valid_source() }) do
                    local app, calls = application(source)
                    local result = assert(app.dispatch({ id = "status" }))
                    A.equal(result.kind, "status")
                    A.equal(result.state, "no-active-context")
                    A.equal(result.workspace, "/workspace")
                    A.falsy(result.durable)
                    A.falsy(result.context_hash)
                    A.equal(result.config_available, source == valid_source())
                    if result.config_available then
                        A.equal(result.model, "Primary")
                        A.equal(result.permission, "Std")
                    end
                    A.falsy(A.render(result):find("bootstrap-secret", 1, true))
                    A.equal(calls.catalog, 0)
                    A.equal(calls.network, 0)
                    A.equal(calls.agent, 0)
                    A.equal(calls.management, 0)
                    A.equal(calls.stage1, 0)
                    A.falsy(app.status().active_draft)
                    --Executes the action expected to raise in the 'status is read-only and reports missing invalid and valid configuration' case.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return nil No value; assertions verify status is read-only and reports missing invalid and valid configuration.
                    A.raises(function() result.state = "changed" end, "cannot be modified")
                end
            end,
        },
        {
            name = "production status preserves the TTY gate and does not create data",
            --Verifies production status preserves the TTY gate and does not create data.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify production status preserves the TTY gate and does not create data.
            run = function()
                local native, filesystem, calls, native_path, data_root = production_native()
                local stdout, stderr = {}, {}
                local ports = {
                    native = native,
                    native_path = native_path,
                    --Captures stdout bytes in the production status preserves the TTY gate and does not create data scenario.
                    --@param bytes string Byte chunk supplied to the fake I/O port.
                    --@return boolean accepted Whether the fake callback accepts this scenario.
                    stdout = function(bytes) stdout[#stdout + 1] = bytes return true end,
                    --Captures stderr bytes in the production status preserves the TTY gate and does not create data scenario.
                    --@param bytes string Byte chunk supplied to the fake I/O port.
                    --@return boolean accepted Whether the fake callback accepts this scenario.
                    stderr = function(bytes) stderr[#stderr + 1] = bytes return true end,
                }
                A.equal(main.run_cli({ [0] = "/release/yaca", "--status" }, ports), 0)
                local rendered = table.concat(stdout)
                A.contains(rendered, "state: no-active-context")
                A.contains(rendered, "context: none")
                A.contains(rendered, "config: unavailable (ConfigMissing)")
                A.equal(calls.directory_creates, 0)
                A.equal(calls.process_starts, 0)
                A.falsy(filesystem.bytes(data_root .. "/config.ini"))
                A.deep_equal(stderr, {})
                --Simulates stdio facts in the production status preserves the TTY gate and does not create data fixture.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return table record Fixture record emitted by the scenario callback.
                native.stdio_facts = function()
                    return {
                        stdin_is_tty = false, stdout_is_tty = false,
                        stderr_is_tty = false,
                    }
                end
                stdout, stderr = {}, {}
                A.equal(main.run_cli({ [0] = "/release/yaca", "--status" }, ports), 5)
                A.deep_equal(stdout, {})
                A.equal(calls.directory_creates, 0)
            end,
        },
        {
            name = "all management routes remain available with missing or invalid config",
            --Verifies all management routes remain available with missing or invalid config.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify all management routes remain available with missing or invalid config.
            run = function()
                local app, calls = application(nil)
                local config_result = assert(app.dispatch({ id = "config-repl" }))
                A.equal(config_result.config_error, "ConfigMissing")
                A.equal(calls.management, 1)
                A.equal(calls.catalog, 0)
                A.equal(calls.network, 0)
                assert(app.dispatch({ id = "context-repl", view = "recent" }))
                A.equal(calls.catalog, 1)
                A.equal(calls.network, 0)

                app, calls = application("[General]\nUnknown = true\n")
                local model_result = assert(app.dispatch({ id = "model-repl" }))
                A.equal(model_result.config_error, "ConfigInvalid")
                A.equal(calls.management, 1)
                A.equal(calls.network, 0)
                A.equal(calls.agent, 0)
            end,
        },
        {
            name = "Stage 1 runs offline even when the main configuration is invalid",
            --Verifies stage 1 runs offline even when the main configuration is invalid.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify stage 1 runs offline even when the main configuration is invalid.
            run = function()
                local app, calls = application("[General]\nUnknown = true\n")
                local result = assert(app.dispatch({
                    id = "self-test",
                    through_stage = 1,
                }))
                A.equal(result.outcome, "passed")
                A.equal(calls.stage1, 1)
                A.equal(calls.last_stage1.snapshot.config.error.code, "ConfigInvalid")
                A.equal(calls.catalog, 1)
                A.equal(calls.network, 0)
                A.equal(calls.agent, 0)

                local online, online_error = app.dispatch({
                    id = "self-test",
                    through_stage = 2,
                })
                A.falsy(online)
                A.equal(online_error.code, "OnlineConsentRequired")
                A.equal(calls.network, 0)

                online = assert(app.dispatch({
                    id = "self-test",
                    through_stage = 2,
                    online_consent = true,
                }))
                A.equal(online.outcome, "passed")
                A.equal(online.completed_stage, 2)
                A.equal(calls.network, 1)
            end,
        },
        {
            name = "Stage 1 rejects any handler that reports an online request",
            --Verifies stage 1 rejects any handler that reports an online request.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify stage 1 rejects any handler that reports an online request.
            run = function()
                local app, calls = application(valid_source())
                calls.stage1_online_requests = 1
                local result, result_error = app.dispatch({ id = "self-test" })
                A.falsy(result)
                A.equal(result_error.code, "SelfTestContract")
                A.equal(calls.network, 0)
            end,
        },
        {
            name = "chat is blocked by missing invalid or selected-unavailable Model config",
            --Verifies stage 1 rejects any handler that reports an online request.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify stage 1 rejects any handler that reports an online request.
            run = function()
                local cases = {
                    { false, "ConfigMissing" },
                    { "[General]\nUnknown = true\n", "ConfigInvalid" },
                    { valid_source({ disabled_first = true }), "ModelUnavailable" },
                }
                for _, case in ipairs(cases) do
                    local app, calls = application(case[1])
                    local result, result_error = app.dispatch({ id = "run-chat" })
                    A.falsy(result)
                    A.equal(result_error.code, case[2])
                    A.equal(calls.network, 0)
                    A.equal(calls.catalog, 0)
                    A.equal(calls.agent, 0)
                    A.equal(calls.stage1, 0)
                end
            end,
        },
        {
            name = "continue preview freezes an exact target without acquiring its writer",
            --Verifies chat is blocked by missing invalid or selected-unavailable Model config.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify chat is blocked by missing invalid or selected-unavailable Model config.
            run = function()
                local app, calls = application(valid_source(), {})
                local preview = assert(app.preview_continue("Task"))
                A.equal(preview.kind, "continue-preview")
                A.equal(preview.logical_path, "/workspace/Task.xml")
                A.equal(preview.context_hash, "0123456789ABCDEF")
                A.equal(preview.recorded_workspace, "/workspace")
                A.equal(calls.catalog, 1)
                A.equal(calls.verify, 1)
                A.equal(calls.open_existing or 0, 0)
                A.equal(calls.config, 0)
                A.equal(app.status().lifecycle, "constructed")
            end,
        },
        {
            name = "cross-workspace continuation requires exact consent and transfers one private preview",
            --Verifies continue preview freezes an exact target without acquiring its writer.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify continue preview freezes an exact target without acquiring its writer.
            run = function()
                local settings = { logical_path = "/other/Task.xml", physical_path = "/data/other/Task.xml" }
                local app, calls = application(valid_source(), settings)
                local preview = assert(app.preview_continue("Task"))
                A.truthy(preview.requires_workspace_confirmation)
                A.equal(preview.origin_workspace, "/workspace")
                A.equal(preview.recorded_workspace, "/other")
                A.equal(calls.open_existing or 0, 0)
                A.equal(calls.config, 0)
                local rejected, err = app.continue_preview(preview, "yes")
                A.falsy(rejected)
                A.equal(err.code, "WorkspaceConfirmationRequired")
                local next_app, next_calls = application(valid_source(), settings)
                local opened = assert(next_app.continue_preview(preview, "CONTINUE 0123456789ABCDEF"))
                A.equal(opened.status.workspace, "/other")
                A.equal(next_calls.last_selector, "0123456789ABCDEF")
                A.equal(next_calls.open_existing, 1)
                A.equal(next_calls.network, 0)
                rejected, err = app.continue_preview(preview, "CONTINUE 0123456789ABCDEF")
                A.falsy(rejected)
                A.equal(err.code, "InvalidContinuePreview")
                assert(next_app.close())
            end,
        },
        {
            name = "continuation refuses forged superseded and changed preview targets before opening",
            --Verifies continuation refuses forged superseded and changed preview targets before opening.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify continuation refuses forged superseded and changed preview targets before opening.
            run = function()
                local settings = { logical_path = "/other/Task.xml" }
                local app, calls = application(valid_source(), settings)
                local old = assert(app.preview_continue("Task"))
                local preview = assert(app.preview_continue("Task"))
                for _, invalid in ipairs({ old, { context_hash = preview.context_hash,
                    requires_workspace_confirmation = false } }) do
                    local opened, err = app.continue_preview(invalid, "CONTINUE 0123456789ABCDEF")
                    A.falsy(opened)
                    A.equal(err.code, "InvalidContinuePreview")
                end
                settings.verify_tag = "TargetChanged"
                local opened, err = app.continue_preview(preview, "CONTINUE 0123456789ABCDEF")
                A.falsy(opened)
                A.equal(err.code, "TargetChanged")
                A.equal(calls.open_existing or 0, 0)
                settings.verify_tag = nil
                preview = assert(app.preview_continue("Task"))
                local other, other_calls = application(valid_source(), {
                    logical_path = "/other/Task.xml", credential_version = "replacement",
                })
                opened, err = other.continue_preview(preview, "CONTINUE 0123456789ABCDEF")
                A.falsy(opened)
                A.equal(err.code, "TargetChanged")
                A.equal(other_calls.open_existing or 0, 0)
            end,
        },
        {
            name = "continuation binds both workspace identities and releases a writer on later changes",
            --Verifies continuation binds both workspace identities and releases a writer on later changes.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify continuation binds both workspace identities and releases a writer on later changes.
            run = function()
                for _, changed in ipairs({ "/workspace", "/other" }) do
                    for _, phase in ipairs({ "confirm", "open" }) do
                        local settings = { logical_path = "/other/Task.xml", workspace_objects = {} }
                        local app, calls = application(valid_source(), settings)
                        local preview = assert(app.preview_continue("Task"))
                        if phase == "confirm" then settings.workspace_objects[changed] = "replaced"
                        else
                            --Supplies on open behavior required by the 'continuation binds both workspace identities and releases a writer on later changes' case.
                            --@param none No arguments; this closure uses its captured fixture state.
                            --@return nil No value; assertions verify continuation binds both workspace identities and releases a writer on later changes.
                            settings.on_open = function() settings.workspace_objects[changed] = "replaced" end end
                        local opened, err = app.continue_preview(preview, "CONTINUE 0123456789ABCDEF")
                        A.falsy(opened)
                        A.equal(err.code, "TargetChanged")
                        A.equal(calls.open_existing or 0, phase == "open" and 1 or 0)
                        A.equal(calls.publication_close or 0, phase == "open" and 1 or 0)
                        A.equal(calls.config, 0)
                        A.equal(calls.network, 0)
                    end
                end
            end,
        },
        {
            name = "workspace consent does not bypass recovery or configuration gates",
            --Verifies workspace consent does not bypass recovery or configuration gates.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify workspace consent does not bypass recovery or configuration gates.
            run = function()
                for _, case in ipairs({ { valid_source(), false, "ContextRecoveryRequired" },
                    { false, true, "ConfigMissing" } }) do
                    local app, calls = application(case[1], { logical_path = "/other/Task.xml", auto_continue = case[2] })
                    local preview = assert(app.preview_continue("Task"))
                    local opened, err = app.continue_preview(preview, "CONTINUE 0123456789ABCDEF")
                    A.falsy(opened)
                    A.equal(err.code, case[3])
                    A.equal(calls.publication_close, 1)
                    A.equal(calls.network, 0)
                    A.equal(calls.agent, 0)
                end
            end,
        },
        {
            name = "continuation selection uses the active draft workspace instead of process cwd",
            --Verifies workspace consent does not bypass recovery or configuration gates.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify workspace consent does not bypass recovery or configuration gates.
            run = function()
                local app = application(valid_source(), { logical_path = "/other/Task.xml" })
                assert(app.dispatch({ id = "run-chat", directory = "/other" }))
                local preview = assert(app.preview_continue("Task"))
                A.equal(preview.origin_workspace, "/other")
                A.falsy(preview.requires_workspace_confirmation)
                assert(app.close())
            end,
        },
        {
            name = "continue verifies one exact quiescent Context and retains its writer",
            --Verifies continuation selection uses the active draft workspace instead of process cwd.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify continuation selection uses the active draft workspace instead of process cwd.
            run = function()
                local app, calls = application(valid_source(), {})
                local result = assert(app.dispatch({
                    id = "continue",
                    selector = "Task",
                }))
                A.equal(result.kind, "continue-chat")
                A.equal(result.outcome, "ready")
                A.equal(result.status.lifecycle, "saved")
                A.truthy(result.status.durable)
                A.equal(result.status.workspace, "/workspace")
                A.equal(result.status.context_hash, "0123456789ABCDEF")
                A.equal(result.open_receipt.event_count, 29)
                A.equal(result.open_receipt.runtime_initial_serials.turn, 4)
                A.equal(calls.catalog, 1)
                A.equal(calls.last_selector, "Task")
                A.equal(calls.last_origin, "/workspace")
                A.equal(calls.verify, 1)
                A.equal(calls.last_verify_purpose, "open")
                A.equal(calls.open_existing, 1)
                A.equal(calls.turn_context, 1)
                A.equal(calls.config, 1)
                A.deep_equal(calls.last_config_overrides, {})
                A.equal(calls.network, 0)
                A.equal(calls.agent, 0)
                A.equal(app.status().lifecycle, "context-ready")
                A.truthy(app.close())
                A.equal(calls.publication_close, 1)
            end,
        },
        {
            name = "continue fails closed for scope recovery resolver and lock uncertainty",
            --Verifies continue fails closed for scope recovery resolver and lock uncertainty.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify continue fails closed for scope recovery resolver and lock uncertainty.
            run = function()
                local app, calls = application(valid_source(), {
                    logical_path = "/other/Task.xml",
                })
                local result, result_error = app.dispatch({
                    id = "continue",
                    selector = "Task",
                })
                A.falsy(result)
                A.equal(result_error.code, "WorkspaceConfirmationRequired")
                A.equal(calls.open_existing or 0, 0)
                A.equal(calls.config, 0)

                app, calls = application(valid_source(), { auto_continue = false })
                result, result_error = app.dispatch({
                    id = "continue",
                    selector = "Task",
                })
                A.falsy(result)
                A.equal(result_error.code, "ContextRecoveryRequired")
                A.equal(calls.open_existing, 1)
                A.equal(calls.publication_close, 1)
                A.equal(calls.config, 0)

                app, calls = application(valid_source(), { resolve_tag = "NotFound" })
                result, result_error = app.dispatch({
                    id = "continue",
                    selector = "missing",
                })
                A.falsy(result)
                A.equal(result_error.code, "NotFound")
                A.equal(calls.verify or 0, 0)
                A.equal(calls.open_existing or 0, 0)

                app, calls = application(valid_source(), {
                    open_error = {
                        code = "LockConflict",
                        message = "another writer is active",
                    },
                })
                result, result_error = app.dispatch({
                    id = "continue",
                    selector = "Task",
                })
                A.falsy(result)
                A.equal(result_error.code, "LockConflict")
                A.equal(calls.open_existing, 1)
                A.equal(calls.publication_close or 0, 0)
            end,
        },
        {
            name = "bare chat creates only a bounded not-saved draft and never scans history",
            --Verifies bare chat creates only a bounded not-saved draft and never scans history.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify bare chat creates only a bounded not-saved draft and never scans history.
            run = function()
                local app, calls, filesystem = application(valid_source())
                local result = assert(app.dispatch({ id = "run-chat" }))
                A.equal(result.outcome, "ready")
                A.equal(result.status.lifecycle, "not-saved")
                A.falsy(result.status.durable)
                A.equal(result.status.display_name, "not saved")
                A.equal(result.status.workspace, "/workspace")
                A.equal(calls.config, 1)
                A.equal(calls.workspace, 1)
                A.equal(calls.catalog, 0)
                A.equal(calls.network, 0)
                A.equal(calls.agent, 0)
                A.equal(calls.stage1, 0)
                A.falsy(A.render(result.status):find("bootstrap-secret", 1, true))
                A.falsy(table.concat(filesystem.operations, "|"):find(
                    "CONTEXT",
                    1,
                    true
                ))

                local updated = assert(result.draft.update({
                    permission = "Std",
                    double_check = false,
                    context_prompt = "draft-only preference",
                }))
                A.equal(updated.double_check, false)
                A.equal(updated.context_prompt, "draft-only preference")
                local inspected = assert(app.dispatch({ id = "status" }))
                A.equal(inspected.double_check, false)
                A.equal(inspected.state, "not-saved")
                A.falsy(inspected.context_hash)
                A.equal(calls.catalog, 0)
                local rejected, reject_error = result.draft.update({
                    context_prompt = "bootstrap-secret",
                })
                A.falsy(rejected)
                A.equal(reject_error.code, "RegisteredSecret")
                rejected, reject_error = result.draft.update({
                    context_prompt = string.rep("x", 4096),
                })
                A.falsy(rejected)
                A.equal(reject_error.code, "DraftLimit")
                local accepted, accept_error = result.draft.begin_main("do work")
                A.falsy(accepted)
                A.equal(accept_error.code, "ContextPublicationUnavailable")
                A.equal(calls.network, 0)
                A.equal(calls.agent, 0)
                A.truthy(app.close())
                A.equal(result.draft.status().lifecycle, "closed")
            end,
        },
        {
            name = "configured startup checks run Stage 1 but never imply online consent",
            --Verifies configured startup checks run Stage 1 but never imply online consent.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify configured startup checks run Stage 1 but never imply online consent.
            run = function()
                local app, calls = application(valid_source({ startup_self_test = "stage1" }))
                local result = assert(app.dispatch({ id = "run-chat" }))
                A.equal(result.outcome, "ready")
                A.equal(calls.stage1, 1)
                A.equal(calls.catalog, 1)
                A.equal(calls.network, 0)
                A.equal(#calls.last_stage1.models, 1)
                A.equal(calls.last_stage1.models[1].id, "Primary")
                A.truthy(calls.last_stage1.snapshot.config.available)
                A.truthy(calls.last_stage1.snapshot.config.generation
                    .models.Primary.key_configured)
                A.falsy(A.render(calls.last_stage1):find(
                    "bootstrap-secret",
                    1,
                    true
                ))
                --Executes the action expected to raise in the 'configured startup checks run Stage 1 but never imply online consent' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify configured startup checks run Stage 1 but never imply online consent.
                A.raises(function()
                    calls.last_stage1.snapshot.config.available = false
                end, "cannot be modified")

                app, calls = application(valid_source({ startup_self_test = "stage1" }))
                calls.stage1_outcome = "partial"
                result, result_error = app.dispatch({ id = "run-chat" })
                A.falsy(result)
                A.equal(result_error.code, "StartupSelfTestFailed")
                A.equal(calls.network, 0)

                app, calls = application(valid_source({ startup_self_test = "stage2" }))
                result, result_error = app.dispatch({ id = "run-chat" })
                A.falsy(result)
                A.equal(result_error.code, "OnlineConsentRequired")
                A.equal(calls.stage1, 0)
                A.equal(calls.network, 0)
            end,
        },
        {
            name = "invalid requests and online-declared bootstrap ports fail before dispatch",
            --Verifies invalid requests and online-declared bootstrap ports fail before dispatch.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify invalid requests and online-declared bootstrap ports fail before dispatch.
            run = function()
                local app, calls = application(valid_source())
                local result, result_error = app.dispatch({
                    id = "run-chat",
                    surprise = true,
                })
                A.falsy(result)
                A.equal(result_error.code, "UsageError")
                A.equal(calls.platform, 0)
                A.equal(calls.config, 0)

                local invalid, invalid_error = main.new({
                    platform = {
                        --Supplies the identity observation used by the 'invalid requests and online-declared bootstrap ports fail before dispatch' case.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return table record Fixture record emitted by the scenario callback.
                        identity = function() return {} end },
                    config = {
                        --Supplies reload file behavior required by the 'invalid requests and online-declared bootstrap ports fail before dispatch' case.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return nil rejected Explicit rejection from the scenario callback.
                        reload_file = function() return nil end },
                    workspace = {
                        --Returns the inspect observation prepared for the 'invalid requests and online-declared bootstrap ports fail before dispatch' case.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return nil rejected Explicit rejection from the scenario callback.
                        inspect = function() return nil end },
                    self_test = {
                        online = true,
                        auto_fix = false,
                        --Verifies invalid requests and online-declared bootstrap ports fail before dispatch.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return table record Fixture record emitted by the scenario callback.
                        run = function() return {} end,
                    },
                    management = { online = false,
                        --Verifies invalid requests and online-declared bootstrap ports fail before dispatch.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return table record Fixture record emitted by the scenario callback.
                        run = function() return {} end },
                }, {
                    product_name = "yaca",
                    product_version = "0.1.0-dev",
                    release_target = "linux-x86_64",
                    config_path = CONFIG_PATH,
                    maximum_draft_bytes = 4096,
                })
                A.falsy(invalid)
                A.equal(invalid_error.code, "InvalidBootstrapComponents")
            end,
        },
    },
}
