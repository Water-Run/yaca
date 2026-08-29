--[[
File: bootstrap_test.lua
Date: 2026-08-30
Author: WaterRun
Description: Verifies offline bootstrap routing, Agent gates, and bare-draft behavior.
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
local config = load_module("config", cache)
local main = load_module("main", cache)
local sha256 = load_table("test/support/sha256_reference.lua")
local fake_filesystem = load_table("test/support/fake_filesystem.lua")

local CONFIG_PATH = "/release/__yaca__/config.ini"

local function hash_port()
    local port = {}

    function port.sha256_start()
        return { parts = {}, finished = false, closed = false }
    end

    function port.sha256_update(handle, bytes)
        assert(not handle.finished and not handle.closed)
        handle.parts[#handle.parts + 1] = bytes
        return true
    end

    function port.sha256_finish(handle)
        assert(not handle.finished and not handle.closed)
        handle.finished = true
        return sha256.digest(table.concat(handle.parts))
    end

    function port.sha256_close(handle)
        assert(not handle.closed)
        handle.closed = true
        return true
    end

    return port
end

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

local function production_native()
    local outer = "/release"
    local inner = "/runtime/payload"
    local data_root = outer .. "/__yaca__"
    local native_path = inner .. "/.luai/native/yaca_native.so"
    local initial = {
        [outer .. "/yaca"] = "outer",
        [inner .. "/yaca"] = "runtime",
        [inner .. "/.luai/components/curl"] = "curl",
        [inner .. "/.luai/components/cacert.pem"] = "not-the-release-ca",
        [native_path] = "native",
    }
    local raw, controls = fake_filesystem.new(initial, 65536)
    local directories = {
        [outer] = true,
        [inner] = true,
        [inner .. "/.luai"] = true,
        [inner .. "/.luai/components"] = true,
        [inner .. "/.luai/native"] = true,
    }
    local hashes = hash_port()
    local calls = { directory_creates = 0, process_starts = 0 }
    local function native_error(code, message)
        return { code = code, message = message or code }
    end
    local native = {}
    function native.abi_version() return "yaca-native-v0.1.0" end
    function native.platform_identity() return { os = "linux", arch = "x86_64" } end
    function native.stdio_facts()
        return { stdin_is_tty = true, stdout_is_tty = true, stderr_is_tty = true }
    end
    function native.executable_paths()
        return { application = outer .. "/yaca", runtime = inner .. "/yaca" }
    end
    function native.workspace_inspect()
        return {
            path = "/workspace",
            enterable = true,
            identity = {
                kind = "directory", volume = "fake-volume", object = "workspace",
                size = 0, modified = "1",
            },
        }
    end
    function native.monotonic_now() return 1 end
    function native.utc_now() return "2026-08-30T00:00:00Z" end
    function native.secure_random(length) return string.rep("r", length) end
    function native.current_process_id() return 41 end
    for _, name in ipairs({
        "sha256_start", "sha256_update", "sha256_finish", "sha256_close",
    }) do
        native[name] = hashes[name]
    end
    function native.fs_open_read(path) return raw.open_read(path) end
    function native.fs_create_new(path, permissions)
        return raw.create_new(path, permissions)
    end
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
    function native.fs_read(handle, maximum) return raw.stream_read(handle, maximum) end
    function native.fs_write(handle, bytes) return raw.stream_write(handle, bytes) end
    function native.fs_flush_file(handle) return raw.flush_file(handle) end
    function native.fs_flush_directory(path) return raw.flush_directory(path) end
    function native.fs_replace(temporary, target) return raw.replace(temporary, target) end
    function native.fs_rename_no_replace(source, target)
        return raw.rename_no_replace(source, target)
    end
    function native.fs_delete_verified(path, identity)
        return raw.delete_verified(path, identity)
    end
    function native.fs_close(handle) return raw.close(handle) end
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
    function native.process_start()
        calls.process_starts = calls.process_starts + 1
        return false, native_error("UnexpectedProcess", "process start was not expected")
    end
    function native.process_poll() return true, {} end
    function native.process_cancel() return true, true end
    function native.process_join()
        return true, {
            outcome = "completed", exit_kind = "exit-code", exit_code = 0,
            duration_ms = 0, descendants_proven_stopped = true,
        }
    end
    function native.process_close() return true, true end
    function native.terminal_start() return true, {} end
    function native.terminal_poll() return true, {} end
    function native.terminal_cancel() return true, true end
    function native.terminal_join() return true, { outcome = "completed" } end
    function native.terminal_close() return true, true end
    function native.terminal_restore() return true, true end
    return native, controls, calls, native_path, data_root
end

local function application(source)
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
    function counted_config.reload_file(path)
        calls.config = calls.config + 1
        return config_service.reload_file(path)
    end
    setmetatable(counted_config, { __index = config_service })

    local platform = {}
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
    function workspace.inspect(requested)
        calls.workspace = calls.workspace + 1
        return {
            path = requested == "." and "/workspace" or requested,
            enterable = true,
            identity = { object = "workspace-1" },
        }
    end

    local self_test = {
        online = "explicit-current-invocation-only",
        auto_fix = false,
    }
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

    local app = assert(main.new({
        platform = platform,
        config = counted_config,
        workspace = workspace,
        self_test = self_test,
        management = management,
        network = { request = function() calls.network = calls.network + 1 end },
        context_catalog = { scan = function() calls.catalog = calls.catalog + 1 end },
        agent = { start = function() calls.agent = calls.agent + 1 end },
    }, {
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
            name = "packaged layout separates outer durable data from inner runtime resources",
            run = function()
                local calls = {}
                local layout = assert(main.resolve_runtime_layout({
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
                A.raises(function() layout.data_root = "/tmp/escape" end, "cannot be modified")
            end,
        },
        {
            name = "packaged layout rejects relative swapped and cross-target paths",
            run = function()
                local relative, relative_error = main.resolve_runtime_layout({
                    executable_paths = function()
                        return { application = "yaca", runtime = "/tmp/cache/yaca" }
                    end,
                }, "yaca", "linux-x86_64")
                A.falsy(relative)
                A.equal(relative_error.code, "InvalidExecutableLayout")

                local same, same_error = main.resolve_runtime_layout({
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
            run = function()
                local calls = { platform = 0, stdio = 0, paths = 0 }
                local native = {}
                function native.abi_version() return "yaca-native-v0.1.0" end
                function native.platform_identity()
                    calls.platform = calls.platform + 1
                    return { os = "linux", arch = "x86_64" }
                end
                function native.stdio_facts()
                    calls.stdio = calls.stdio + 1
                    return {
                        stdin_is_tty = false,
                        stdout_is_tty = false,
                        stderr_is_tty = false,
                    }
                end
                function native.executable_paths()
                    calls.paths = calls.paths + 1
                    error("help and version must not resolve writable roots")
                end

                local stdout, stderr = {}, {}
                local ports = {
                    native = native,
                    stdout = function(bytes) stdout[#stdout + 1] = bytes return true end,
                    stderr = function(bytes) stderr[#stderr + 1] = bytes return true end,
                }
                A.equal(main.run_cli({ [0] = "/opt/yaca", "--help" }, ports), 0)
                A.contains(table.concat(stdout), "yaca: Yet Another Coding Agent.")
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
            run = function()
                local native = {
                    abi_version = function() return "yaca-native-v0.1.0" end,
                    platform_identity = function()
                        return { os = "linux", arch = "x86_64" }
                    end,
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
                    stdout = function() return true end,
                    stderr = function(bytes) stderr[#stderr + 1] = bytes return true end,
                }
                A.equal(main.run_cli({ [0] = "/opt/yaca", "--unknown" }, ports), 2)
                A.contains(table.concat(stderr), "UsageError")
                stderr = {}
                A.equal(main.run_cli({ [0] = "/opt/yaca" }, ports), 5)
                A.contains(table.concat(stderr), "TtyRequired")
            end,
        },
        {
            name = "production composition creates only an explicit offline repair template",
            run = function()
                local native, filesystem, calls, native_path, data_root = production_native()
                local stdout, stderr = {}, {}
                local ports = {
                    native = native,
                    native_path = native_path,
                    stdout = function(bytes) stdout[#stdout + 1] = bytes return true end,
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
                A.equal(main.run_cli({
                    [0] = "/release/yaca", "--config-repl",
                }, ports), 1)
                A.equal(filesystem.bytes(config_path), template)
                A.equal(calls.directory_creates, 1)
                A.equal(calls.process_starts, 0)
                A.contains(table.concat(stdout), "requires repair")

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
            name = "construction help and version perform no probes reads scans or network",
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
            name = "all management routes remain available with missing or invalid config",
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
            name = "bare chat creates only a bounded not-saved draft and never scans history",
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
                    platform = { identity = function() return {} end },
                    config = { reload_file = function() return nil end },
                    workspace = { inspect = function() return nil end },
                    self_test = {
                        online = true,
                        auto_fix = false,
                        run = function() return {} end,
                    },
                    management = { online = false, run = function() return {} end },
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
