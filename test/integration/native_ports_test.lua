--[[
File: native_ports_test.lua
Date: 2026-08-30
Author: WaterRun
Description: Verifies narrow filesystem, process, terminal, and backend ports.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

local function load_module(name, cache)
    cache = cache or {}
    if cache[name] then return cache[name] end
    local environment = {}
    for key, value in pairs(_ENV) do environment[key] = value end
    environment.require = function(dependency)
        return load_module(dependency, cache)
    end
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

local function success_native()
    local native = {
        calls = {},
        process_batches = {},
        terminal_batches = {},
    }

    function native.abi_version()
        return "yaca-native-v0.1.0"
    end

    function native.monotonic_now()
        return 100
    end

    function native.utc_now()
        return "2026-08-29T00:00:00Z"
    end

    function native.secure_random(length)
        return string.rep("r", length)
    end

    function native.current_process_id()
        return 41
    end

    function native.fs_open_read(path)
        native.calls.fs_open_read = path
        return true, { handle = "read" }
    end

    function native.fs_create_new(path, permissions)
        native.calls.fs_create_new = { path, permissions }
        return true, { handle = "write" }
    end

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

    function native.fs_read(_, maximum_bytes)
        return true, { bytes = ("abc"):sub(1, maximum_bytes), eof = true }
    end

    function native.fs_write(_, bytes)
        native.calls.fs_write = bytes
        return true, #bytes
    end

    function native.fs_flush_file()
        return true, true
    end

    function native.fs_flush_directory(path)
        native.calls.fs_flush_directory = path
        return true, true
    end

    function native.fs_replace(temporary_path, target_path)
        native.calls.fs_replace = { temporary_path, target_path }
        return true, true
    end

    function native.fs_rename_no_replace(source_path, target_path)
        native.calls.fs_rename = { source_path, target_path }
        return true, true
    end

    function native.fs_delete_verified(path, identity)
        native.calls.fs_delete = { path, identity }
        return true, true
    end

    function native.fs_close(handle)
        native.calls.fs_close = handle
        return true, true
    end

    function native.process_start(request)
        native.calls.process_start = request
        return true, { process = 1 }
    end

    function native.process_poll(_, _, budget)
        local batch = table.remove(native.process_batches, 1) or {}
        A.truthy(#batch <= budget)
        return true, batch
    end

    function native.process_cancel()
        native.calls.process_cancel = (native.calls.process_cancel or 0) + 1
        return true, true
    end

    function native.process_join()
        return true, native.process_result or {
            outcome = "completed",
            exit_kind = "exit-code",
            exit_code = 0,
            duration_ms = 9,
            descendants_proven_stopped = true,
        }
    end

    function native.process_close()
        native.calls.process_close = true
        return true, true
    end

    function native.terminal_start(request)
        native.calls.terminal_start = request
        return true, { terminal = 1 }
    end

    function native.terminal_poll(_, _, budget)
        native.calls.terminal_poll = (native.calls.terminal_poll or 0) + 1
        local batch = table.remove(native.terminal_batches, 1) or {}
        A.truthy(#batch <= budget)
        return true, batch
    end

    function native.terminal_cancel()
        return true, true
    end

    function native.terminal_join()
        return true, { outcome = native.terminal_outcome or "completed" }
    end

    function native.terminal_restore()
        native.calls.terminal_restore = (native.calls.terminal_restore or 0) + 1
        return true, true
    end

    function native.terminal_close()
        native.calls.terminal_close = true
        return true, true
    end

    return native
end

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
                A.equal(#assert(linux_backend.system.secure_random(10)), 10)
                A.equal(linux_backend.system.current_process_id(), 41)
                A.equal(linux_backend.qualification, "pending-target-evidence")
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
            run = function()
                local fs = load_module("fs")
                local process = load_module("process")
                local native = success_native()
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
                A.raises(function() terminal_port:poll(1, 1) end, "NativeContract")
            end,
        },
    },
}
