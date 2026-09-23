--[[
Author: WaterRun
Date: 2026-09-23
File: native_ports_test.lua
Description: Verifies narrow filesystem, process, terminal, and backend ports.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

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
    environment.require = function(dependency)
        return load_module(dependency, cache)
    end
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

--Supplies port options behavior required by this suite.
--@param none No arguments; this closure uses its captured fixture state.
--@return table observed Structured fixture record selected by the exercised branch.
local function port_options()
    return {
        filesystem = { maximum_chunk_bytes = 16 },
        process = {
            maximum_output_bytes = 64,
            maximum_poll_bytes = 16,
        },
        terminal = { maximum_input_bytes = 16 },
    }
end

--Supplies success native behavior required by this suite.
--@param none No arguments; this closure uses its captured fixture state.
--@return any observed success native value observed by the scenario assertion.
local function success_native()
    local native = {
        calls = {},
        process_batches = {},
        terminal_batches = {},
    }

    --Simulates abi version in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return string outcome Simulated abi version outcome returned to the component.
    function native.abi_version()
        return "yaca-native-v0.1.0"
    end

    --Simulates monotonic now in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return integer outcome Simulated monotonic now outcome returned to the component.
    function native.monotonic_now()
        return 100
    end

    --Simulates sleep ms in this test fixture.
    --@param milliseconds integer Requested fake-clock delay in milliseconds.
    --@return boolean accepted Whether sleep ms succeeds in the fixture.
    function native.sleep_ms(milliseconds)
        native.calls.sleep_ms = milliseconds
        return true
    end

    --Simulates utc now in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return string outcome Simulated utc now outcome returned to the component.
    function native.utc_now()
        return "2026-08-29T00:00:00Z"
    end

    --Simulates secure random in this test fixture.
    --@param length integer Byte or item length requested by the fixture.
    --@return any outcome Simulated secure random outcome returned to the component.
    function native.secure_random(length)
        return string.rep("r", length)
    end

    --Simulates current process id in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return integer outcome Simulated current process id outcome returned to the component.
    function native.current_process_id()
        return 41
    end

    --Simulates fs open read in this test fixture.
    --@param path string File or Context path exercised by the case.
    --@return boolean accepted Whether fs open read succeeds in the fixture.
    --@return table secondary2 Structured fixture record with handle.
    function native.fs_open_read(path)
        native.calls.fs_open_read = path
        return true, { handle = "read" }
    end

    --Simulates fs create new in this test fixture.
    --@param path string File or Context path exercised by the case.
    --@param permissions table Permission profile exercised by the case.
    --@return boolean accepted Whether fs create new succeeds in the fixture.
    --@return table secondary2 Structured fixture record with handle.
    function native.fs_create_new(path, permissions)
        native.calls.fs_create_new = { path, permissions }
        return true, { handle = "write" }
    end

    --Simulates fs stat identity in this test fixture.
    --@param handle_or_path table|string Fake handle or path accepted by this port.
    --@return boolean accepted Whether fs stat identity succeeds in the fixture.
    --@return table secondary2 Structured fixture record selected by the exercised branch.
    function native.fs_stat_identity(handle_or_path)
        native.calls.fs_stat_identity = handle_or_path
        return true, {
            kind = "file",
            volume = "7",
            object = "11",
            size = 3,
            modified = "29",
        }
    end

    --Simulates fs read in this test fixture.
    --@param _ any Unused callback argument supplied by the port.
    --@param maximum_bytes integer Maximum allowed byte length.
    --@return boolean accepted Whether fs read succeeds in the fixture.
    --@return table secondary2 Structured fixture record with bytes, eof.
    function native.fs_read(_, maximum_bytes)
        return true, { bytes = ("abc"):sub(1, maximum_bytes), eof = true }
    end

    --Simulates fs write in this test fixture.
    --@param _ any Unused callback argument supplied by the port.
    --@param bytes string Byte chunk supplied to the fake I/O port.
    --@return boolean accepted Whether fs write succeeds in the fixture.
    --@return any secondary2 Number of bytes accepted by the fake sink.
    function native.fs_write(_, bytes)
        native.calls.fs_write = bytes
        return true, #bytes
    end

    --Simulates fs flush file in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether fs flush file succeeds in the fixture.
    --@return boolean secondary2 True acknowledgment from the fake port.
    function native.fs_flush_file()
        return true, true
    end

    --Simulates fs flush directory in this test fixture.
    --@param path string File or Context path exercised by the case.
    --@return boolean accepted Whether fs flush directory succeeds in the fixture.
    --@return boolean secondary2 True acknowledgment from the fake port.
    function native.fs_flush_directory(path)
        native.calls.fs_flush_directory = path
        return true, true
    end

    --Simulates fs replace in this test fixture.
    --@param temporary_path string Temporary publication path used by the fixture.
    --@param target_path string Destination path targeted by the operation.
    --@return boolean accepted Whether fs replace succeeds in the fixture.
    --@return boolean secondary2 True acknowledgment from the fake port.
    function native.fs_replace(temporary_path, target_path)
        native.calls.fs_replace = { temporary_path, target_path }
        return true, true
    end

    --Simulates fs rename no replace in this test fixture.
    --@param source_path string Source file path read by the fixture.
    --@param target_path string Destination path targeted by the operation.
    --@return boolean accepted Whether fs rename no replace succeeds in the fixture.
    --@return boolean secondary2 True acknowledgment from the fake port.
    function native.fs_rename_no_replace(source_path, target_path)
        native.calls.fs_rename = { source_path, target_path }
        return true, true
    end

    --Simulates fs delete verified in this test fixture.
    --@param path string File or Context path exercised by the case.
    --@param identity table File or process identity under inspection.
    --@return boolean accepted Whether fs delete verified succeeds in the fixture.
    --@return boolean secondary2 True acknowledgment from the fake port.
    function native.fs_delete_verified(path, identity)
        native.calls.fs_delete = { path, identity }
        return true, true
    end

    --Simulates fs close in this test fixture.
    --@param handle table|integer Fake resource handle whose state is inspected.
    --@return boolean accepted Whether fs close succeeds in the fixture.
    --@return boolean secondary2 True acknowledgment from the fake port.
    function native.fs_close(handle)
        native.calls.fs_close = handle
        return true, true
    end

    --Simulates process start in this test fixture.
    --@param request table Request delivered to the fake component.
    --@return boolean accepted Whether process start succeeds in the fixture.
    --@return table secondary2 Structured fixture record with process.
    function native.process_start(request)
        native.calls.process_start = request
        return true, { process = 1 }
    end

    --Simulates process poll in this test fixture.
    --@param _ any Unused callback argument supplied by the port.
    --@param _ any Unused callback argument supplied by the port.
    --@param budget integer|table Resource budget applied by the scenario.
    --@return boolean accepted Whether process poll succeeds in the fixture.
    --@return any secondary2 Event batch returned by the fixture.
    function native.process_poll(_, _, budget)
        local batch = table.remove(native.process_batches, 1) or {}
        A.truthy(#batch <= budget)
        return true, batch
    end

    --Simulates process cancel in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether process cancel succeeds in the fixture.
    --@return boolean secondary2 True acknowledgment from the fake port.
    function native.process_cancel()
        native.calls.process_cancel = (native.calls.process_cancel or 0) + 1
        return true, true
    end

    --Simulates process join in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether process join succeeds in the fixture.
    --@return number secondary2 Additional status or structured error from the fixture operation.
    function native.process_join()
        return true, native.process_result or {
            outcome = "completed",
            exit_kind = "exit-code",
            exit_code = 0,
            duration_ms = 9,
            descendants_proven_stopped = true,
        }
    end

    --Simulates process close in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether process close succeeds in the fixture.
    --@return boolean secondary2 True acknowledgment from the fake port.
    function native.process_close()
        native.calls.process_close = true
        return true, true
    end

    --Simulates terminal start in this test fixture.
    --@param request table Request delivered to the fake component.
    --@return boolean accepted Whether terminal start succeeds in the fixture.
    --@return table secondary2 Structured fixture record with terminal.
    function native.terminal_start(request)
        native.calls.terminal_start = request
        return true, { terminal = 1 }
    end

    --Simulates terminal poll in this test fixture.
    --@param _ any Unused callback argument supplied by the port.
    --@param _ any Unused callback argument supplied by the port.
    --@param budget integer|table Resource budget applied by the scenario.
    --@return boolean accepted Whether terminal poll succeeds in the fixture.
    --@return any secondary2 Event batch returned by the fixture.
    function native.terminal_poll(_, _, budget)
        native.calls.terminal_poll = (native.calls.terminal_poll or 0) + 1
        local batch = table.remove(native.terminal_batches, 1) or {}
        A.truthy(#batch <= budget)
        return true, batch
    end

    --Simulates terminal cancel in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether terminal cancel succeeds in the fixture.
    --@return boolean secondary2 True acknowledgment from the fake port.
    function native.terminal_cancel()
        return true, true
    end

    --Simulates terminal join in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether terminal join succeeds in the fixture.
    --@return table secondary2 Structured fixture record with outcome.
    function native.terminal_join()
        return true, { outcome = native.terminal_outcome or "completed" }
    end

    --Simulates terminal restore in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether terminal restore succeeds in the fixture.
    --@return boolean secondary2 True acknowledgment from the fake port.
    function native.terminal_restore()
        native.calls.terminal_restore = (native.calls.terminal_restore or 0) + 1
        return true, true
    end

    --Simulates terminal close in this test fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether terminal close succeeds in the fixture.
    --@return boolean secondary2 True acknowledgment from the fake port.
    function native.terminal_close()
        native.calls.terminal_close = true
        return true, true
    end

    return native
end

--Supplies method names behavior required by this suite.
--@param value any Candidate whose acceptance or transformation the test checks.
--@return any observed method names value observed by the scenario assertion.
local function method_names(value)
    local names = {}
    for name, item in pairs(value) do
        if type(item) == "function" then names[#names + 1] = name end
    end
    table.sort(names)
    return names
end

return {
    name = "integration/native-ports",
    cases = {
        {
            name = "filesystem validates paths bounds identities and publication primitives",
            --Verifies filesystem validates paths bounds identities and publication primitives.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify filesystem validates paths bounds identities and publication primitives.
            run = function()
                local fs = load_module("fs")
                local native = success_native()
                local service = assert(fs.new(native, { maximum_chunk_bytes = 4 }))
                local opened, read_handle = service.open_read("/tmp/source")
                A.truthy(opened)
                local created, write_handle = service.create_new("/tmp/new", 384)
                A.truthy(created)
                local identified, identity = service.stat_identity(read_handle)
                A.truthy(identified)
                A.equal(identity.object, "11")
                --Executes the action expected to raise in the 'filesystem validates paths bounds identities and publication primitives' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify filesystem validates paths bounds identities and publication primitives.
                A.raises(function() identity.size = 9 end, "cannot be modified")
                local read_ok, chunk = service.stream_read(read_handle, 4)
                A.truthy(read_ok)
                A.deep_equal(chunk, { bytes = "abc", eof = true })
                A.truthy(service.stream_write(write_handle, "\0abc"))
                A.truthy(service.flush_file(write_handle))
                A.truthy(service.flush_directory("/tmp"))
                A.truthy(service.replace("/tmp/new", "/tmp/current"))
                A.truthy(service.rename_no_replace("/tmp/a", "/tmp/b"))
                A.truthy(service.delete_verified("/tmp/source", identity))
                A.truthy(service.close(read_handle))
                local invalid, invalid_error = service.open_read("relative")
                A.falsy(invalid)
                A.equal(invalid_error.code, "InvalidPath")
                local too_large, limit_error = service.stream_write(write_handle, "12345")
                A.falsy(too_large)
                A.equal(limit_error.code, "Limit")
            end,
        },
        {
            name = "process port preserves opaque shell command and bounded separate streams",
            --Verifies process port preserves opaque shell command and bounded separate streams.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify process port preserves opaque shell command and bounded separate streams.
            run = function()
                local process = load_module("process")
                local native = success_native()
                native.process_batches = {
                    {
                        { kind = "stdout", bytes = "abcd" },
                        { kind = "stderr", bytes = "err" },
                        { kind = "stdout", bytes = "EFGH" },
                        { kind = "terminal", outcome = "completed" },
                    },
                }
                local service = assert(process.new(native, {
                    maximum_output_bytes = 16,
                    maximum_poll_bytes = 8,
                    shell = {
                        kind = "linux",
                        executable = "/bin/sh",
                        fixed_arguments = { "-c" },
                    },
                }))
                local command = "printf '%s' 'a b'; printf err >&2"
                local port = assert(service.new_port({
                    command = command,
                    cwd = "/tmp",
                    output_limit_bytes = 6,
                    environment_mode = "inherit_filtered",
                    environment = {
                        PATH = "/bin",
                        CUSTOM = "kept",
                        LUA_PATH = "removed",
                        CURL_HOME = "removed",
                    },
                }))
                A.deep_equal(method_names(port), { "cancel", "close", "join", "poll", "start" })
                A.truthy(port:start(10))
                local request = native.calls.process_start
                A.equal(request.command, command)
                A.equal(request.stdin, "closed")
                A.equal(request.shell.executable, "/bin/sh")
                A.equal(request.environment.CUSTOM, "kept")
                A.falsy(request.environment.LUA_PATH)
                A.falsy(request.environment.CURL_HOME)
                local events = port:poll(11, 4)
                A.equal(events[1].stream, "stdout")
                A.equal(events[2].stream, "stderr")
                A.equal(events[4].kind, "io_terminal")
                local result = port:join(20)
                A.equal(result.stdout, "abH")
                A.equal(result.stderr, "err")
                A.truthy(result.stdout_truncated)
                A.falsy(result.stderr_truncated)
                A.equal(result.stdout_observed_bytes, 8)
                A.equal(result.stdout_retained_bytes, 3)
                A.equal(result.stdout_discarded_bytes, 5)
                A.equal(result.stderr_observed_bytes, 3)
                A.equal(result.stdout_quota_bytes + result.stderr_quota_bytes, 6)
                A.equal(result.observed_sequences, 3)
                A.equal(result.outcome, "completed")
                A.truthy(result.descendants_proven_stopped)
                A.truthy(port:close())
            end,
        },
        {
            name = "process cancellation remains a request until typed terminal truth",
            --Verifies process cancellation remains a request until typed terminal truth.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify process cancellation remains a request until typed terminal truth.
            run = function()
                local process = load_module("process")
                local native = success_native()
                native.process_batches = {
                    { { kind = "terminal", outcome = "cancelled" } },
                }
                native.process_result = {
                    outcome = "cancelled",
                    exit_kind = "cancelled",
                    duration_ms = 2,
                    descendants_proven_stopped = true,
                }
                local service = assert(process.new(native, {
                    maximum_output_bytes = 8,
                    maximum_poll_bytes = 8,
                    shell = {
                        kind = "windows",
                        executable = "native-GetSystemDirectoryW/cmd.exe",
                        fixed_arguments = { "/d", "/s", "/c" },
                    },
                }))
                local port = assert(service.new_port({
                    command = "exit /b 0",
                    output_limit_bytes = 8,
                }))
                port:start(1)
                A.truthy(port:cancel(2))
                A.equal(native.calls.process_cancel, 1)
                A.equal(port:poll(3, 1)[1].outcome, "cancelled")
                A.equal(port:join(4).outcome, "cancelled")
                port:close()
            end,
        },
        {
            name = "Windows environment filtering is case-insensitive and minimal",
            --Verifies windows environment filtering is case-insensitive and minimal.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify windows environment filtering is case-insensitive and minimal.
            run = function()
                local process = load_module("process")
                local native = success_native()
                native.process_batches = {
                    { { kind = "terminal", outcome = "completed" } },
                }
                local service = assert(process.new(native, {
                    maximum_output_bytes = 8,
                    maximum_poll_bytes = 8,
                    shell = {
                        kind = "windows",
                        executable = "native-GetSystemDirectoryW/cmd.exe",
                        fixed_arguments = { "/d", "/s", "/c" },
                    },
                }))
                local port = assert(service.new_port({
                    command = "exit /b 0",
                    output_limit_bytes = 8,
                    environment = {
                        Path = "C:\\Windows\\System32",
                        SystemRoot = "C:\\Windows",
                        lua_path = "removed",
                        Custom = "removed",
                    },
                }))
                port:start(1)
                A.equal(native.calls.process_start.environment.Path, "C:\\Windows\\System32")
                A.equal(native.calls.process_start.environment.SystemRoot, "C:\\Windows")
                A.falsy(native.calls.process_start.environment.lua_path)
                A.falsy(native.calls.process_start.environment.Custom)
                A.equal(port:poll(2, 1)[1].outcome, "completed")
                port:join(3)
                port:close()

                local duplicate, duplicate_error = service.new_port({
                    command = "exit /b 0",
                    output_limit_bytes = 8,
                    environment = { PATH = "one", Path = "two" },
                })
                A.falsy(duplicate)
                A.equal(duplicate_error.code, "InvalidEnvironment")
            end,
        },
        {
            name = "terminal maps semantic actions and restores before close",
            --Verifies terminal maps semantic actions and restores before close.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify terminal maps semantic actions and restores before close.
            run = function()
                local terminal = load_module("terminal")
                local native = success_native()
                native.terminal_batches = {
                    {
                        { kind = "action", intent = "text", text = "x" },
                        { kind = "action", intent = "submit-or-queue" },
                        { kind = "terminal", outcome = "completed" },
                    },
                }
                local port = assert(terminal.new(native, {
                    mode = "auto",
                    maximum_input_bytes = 8,
                }))
                A.deep_equal(
                    method_names(port),
                    { "cancel", "close", "join", "poll", "restore", "start" }
                )
                port:start(1)
                local events = port:poll(2, 3)
                A.deep_equal(events[1], {
                    kind = "user_action",
                    action = "text",
                    text = "x",
                })
                A.equal(events[2].action, "submit-or-queue")
                A.equal(events[3].outcome, "completed")
                A.equal(port:join(3).outcome, "completed")
                A.truthy(port:restore())
                A.truthy(port:restore())
                A.equal(native.calls.terminal_restore, 1)
                A.truthy(port:close())
                A.equal(native.calls.terminal_restore, 1)
            end,
        },
        {
            name = "terminal splits line chunks within budget and folds split CRLF",
            --Verifies terminal splits line chunks within budget and folds split CRLF.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify terminal splits line chunks within budget and folds split CRLF.
            run = function()
                local terminal = load_module("terminal")
                local native = success_native()
                native.terminal_batches = {
                    { { kind = "action", intent = "text", text = "hello\r" } },
                    { { kind = "action", intent = "text", text = "\nworld\n" } },
                    { { kind = "terminal", outcome = "completed" } },
                }
                local port = assert(terminal.new(native, {
                    mode = "auto",
                    maximum_input_bytes = 64,
                }))
                port:start(1)
                A.deep_equal(port:poll(2, 2), {
                    { kind = "user_action", action = "text", text = "hello" },
                    { kind = "user_action", action = "submit-or-queue" },
                })
                A.deep_equal(port:poll(3, 1), {
                    { kind = "user_action", action = "text", text = "world" },
                })
                A.deep_equal(port:poll(4, 1), {
                    { kind = "user_action", action = "submit-or-queue" },
                })
                A.equal(native.calls.terminal_poll, 2)
                A.deep_equal(port:poll(5, 1), {
                    { kind = "io_terminal", outcome = "completed" },
                })
                A.equal(native.calls.terminal_poll, 3)
                A.equal(port:join(6).outcome, "completed")
                A.truthy(port:close())
            end,
        },
        {
            name = "backends bind exact package identities shells and pending qualification",
            --Verifies backends bind exact package identities shells and pending qualification.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify backends bind exact package identities shells and pending qualification.
            run = function()
                local linux = load_module("backend_linux")
                local windows = load_module("backend_windows")
                local linux_native = success_native()
                local linux_backend = assert(linux.new(linux_native, {
                    os = "linux",
                    arch = "x86_64",
                    target = "linux-x86_64",
                    supported = true,
                }, port_options()))
                A.equal(linux_backend.target_id, "linux-x86_64")
                A.equal(linux_backend.processes.capabilities.shell, "linux")
                A.truthy(linux_backend.clock_port.sleep_ms(2))
                A.equal(linux_native.calls.sleep_ms, 2)
                A.equal(#assert(linux_backend.system.secure_random(10)), 10)
                A.equal(linux_backend.system.current_process_id(), 41)
                A.equal(linux_backend.qualification, "pending-target-evidence")
                --Executes the action expected to raise in the 'backends bind exact package identities shells and pending qualification' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify backends bind exact package identities shells and pending qualification.
                A.raises(function() linux_backend.target_id = "win32-x86" end, "cannot be modified")

                local windows_native = success_native()
                local windows_backend = assert(windows.new(windows_native, {
                    os = "windows",
                    arch = "x86",
                    target = "win32-x86",
                    supported = true,
                }, port_options()))
                A.equal(windows_backend.target_id, "win32-x86")
                A.equal(windows_backend.processes.capabilities.shell, "windows")
                A.truthy(windows_backend.clock_port.sleep_ms(3))
                A.equal(windows_native.calls.sleep_ms, 3)
                A.equal(#assert(windows_backend.system.secure_random(10)), 10)
                A.equal(windows_backend.system.current_process_id(), 41)
                A.equal(windows_backend.qualification, "pending-target-evidence")
                local rejected, mismatch = windows.new(windows_native, {
                    os = "windows",
                    arch = "x86_64",
                    target = "win32-x86",
                    supported = true,
                }, port_options())
                A.falsy(rejected)
                A.equal(mismatch.code, "PlatformMismatch")
            end,
        },
        {
            name = "malformed native results fail closed at adapter boundary",
            --Verifies malformed native results fail closed at adapter boundary.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify malformed native results fail closed at adapter boundary.
            run = function()
                local fs = load_module("fs")
                local process = load_module("process")
                local native = success_native()
                --Simulates fs open read in the malformed native results fail closed at adapter boundary fixture.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return string text Text emitted by the scenario callback.
                --@return string secondary2 Fixture text "handle".
                native.fs_open_read = function()
                    return "yes", "handle"
                end
                local filesystem = assert(fs.new(native, { maximum_chunk_bytes = 4 }))
                local opened, open_error = filesystem.open_read("/tmp/file")
                A.falsy(opened)
                A.equal(open_error.code, "NativeContract")

                native = success_native()
                native.process_batches = {
                    { { kind = "combined", bytes = "not-separated" } },
                }
                local processes = assert(process.new(native, {
                    maximum_output_bytes = 8,
                    maximum_poll_bytes = 8,
                    shell = {
                        kind = "linux",
                        executable = "/bin/sh",
                        fixed_arguments = { "-c" },
                    },
                }))
                local port = assert(processes.new_port({
                    command = "true",
                    output_limit_bytes = 8,
                }))
                port:start(0)
                --Executes the action expected to raise in the 'malformed native results fail closed at adapter boundary' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; the fake port or test assertion observes this callback's effects.
                A.raises(function() port:poll(1, 1) end, "NativeContract")

                local invalid_shell, shell_error = process.new(native, {
                    maximum_output_bytes = 8,
                    maximum_poll_bytes = 8,
                    shell = {
                        kind = "linux",
                        executable = "/tmp/sh",
                        fixed_arguments = { "-c" },
                    },
                })
                A.falsy(invalid_shell)
                A.equal(shell_error.code, "InvalidShell")

                local terminal = load_module("terminal")
                native = success_native()
                native.terminal_batches = {
                    { { kind = "action", intent = "text", text = "too-large" } },
                }
                local terminal_port = assert(terminal.new(native, {
                    maximum_input_bytes = 4,
                }))
                terminal_port:start(0)
                --Executes the action expected to raise in the 'malformed native results fail closed at adapter boundary' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; the fake port or test assertion observes this callback's effects.
                A.raises(function() terminal_port:poll(1, 1) end, "NativeContract")
            end,
        },
    },
}
