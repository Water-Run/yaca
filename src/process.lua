--[[
File: process.lua
Date: 2026-08-29
Author: WaterRun
Description: Builds bounded foreground shell and internal component AsyncPorts.
]]

local M = {}

local REQUIRED_NATIVE_METHODS = {
    "process_start",
    "process_poll",
    "process_cancel",
    "process_join",
    "process_close",
}

local TERMINAL_OUTCOMES = {
    completed = true,
    cancelled = true,
    failed = true,
    unknown = true,
}

local MINIMAL_ENVIRONMENT_NAMES = {
    PATH = true,
    SystemRoot = true,
    TEMP = true,
    TMP = true,
    HOME = true,
    LANG = true,
    LC_ALL = true,
    TERM = true,
}

local MINIMAL_WINDOWS_ENVIRONMENT_NAMES = {
    PATH = true,
    SYSTEMROOT = true,
    TEMP = true,
    TMP = true,
    HOME = true,
    LANG = true,
    LC_ALL = true,
    TERM = true,
}

local FORBIDDEN_ENVIRONMENT_NAMES = {
    LUA_PATH = true,
    LUA_CPATH = true,
    LUA_INIT = true,
    LUA_INIT_5_5 = true,
    CURL_HOME = true,
    CURL_CA_BUNDLE = true,
    SSL_CERT_FILE = true,
    SSL_CERT_DIR = true,
    NETRC = true,
}

local function failure(code, message)
    return { code = code, message = message }
end

local function readonly(values, label)
    return setmetatable({}, {
        __index = values,
        __newindex = function(_, key)
            error((label or "readonly value") .. " cannot be modified: " .. tostring(key), 2)
        end,
        __pairs = function()
            return next, values, nil
        end,
        __metatable = "locked",
    })
end

local function valid_integer(value, minimum)
    return math.type(value) == "integer" and value >= minimum
end

local function valid_absolute_path(path)
    if type(path) ~= "string" or path == "" or path:find("\0", 1, true) then
        return false
    end
    local normalized = path:gsub("\\", "/")
    return normalized:sub(1, 1) == "/"
        or normalized:match("^[A-Za-z]:/") ~= nil
        or normalized:match("^//[^/]+/[^/]+") ~= nil
end

local function typed_native_error(value, operation)
    if type(value) == "table"
        and type(value.code) == "string"
        and value.code ~= ""
        and type(value.message) == "string"
        and value.message ~= ""
    then
        return value
    end
    return failure("NativeContract", "native process returned an invalid " .. operation .. " error")
end

local function call_native(native, method, ...)
    local called, ok, value = pcall(native[method], ...)
    if not called then
        return false, failure("NativeFailure", "native process call raised an exception")
    end
    if ok == true then return true, value end
    if ok == false then return false, typed_native_error(value, method) end
    return false, failure("NativeContract", "native process returned an invalid status")
end

local function raise_native(native_error, level)
    error(native_error.code .. ": " .. native_error.message, (level or 1) + 1)
end

local function copy_array(values)
    local result = {}
    for index, value in ipairs(values) do result[index] = value end
    return result
end

local function ascii_upper(value)
    return (value:gsub("[a-z]", function(character)
        return string.char(character:byte() - 32)
    end))
end

local function sanitize_environment(values, mode, shell_kind)
    if values == nil then return {} end
    if type(values) ~= "table" then
        return nil, failure("InvalidEnvironment", "environment must be a string map")
    end
    local result = {}
    local seen_names = {}
    for name, value in pairs(values) do
        if type(name) ~= "string"
            or name == ""
            or name:find("[=\0]")
            or type(value) ~= "string"
            or value:find("\0", 1, true)
        then
            return nil, failure("InvalidEnvironment", "environment contains an invalid entry")
        end
        local comparison_name = shell_kind == "windows" and ascii_upper(name) or name
        if seen_names[comparison_name] then
            return nil, failure("InvalidEnvironment", "environment repeats a platform name")
        end
        seen_names[comparison_name] = true
        local minimal_names = shell_kind == "windows"
            and MINIMAL_WINDOWS_ENVIRONMENT_NAMES
            or MINIMAL_ENVIRONMENT_NAMES
        if not FORBIDDEN_ENVIRONMENT_NAMES[comparison_name]
            and (mode == "inherit_filtered" or minimal_names[comparison_name])
        then
            result[name] = value
        end
    end
    return result
end

local function validate_shell(shell)
    if type(shell) ~= "table"
        or type(shell.kind) ~= "string"
        or type(shell.executable) ~= "string"
        or type(shell.fixed_arguments) ~= "table"
    then
        return nil
    end
    local expected
    if shell.kind == "linux" and shell.executable == "/bin/sh" then
        expected = { "-c" }
    elseif shell.kind == "windows"
        and shell.executable == "native-GetSystemDirectoryW/cmd.exe"
    then
        expected = { "/d", "/s", "/c" }
    else
        return nil
    end
    for key in pairs(shell.fixed_arguments) do
        if math.type(key) ~= "integer" or key < 1 or key > #expected then return nil end
    end
    if #shell.fixed_arguments ~= #expected then return nil end
    for index, value in ipairs(expected) do
        if shell.fixed_arguments[index] ~= value then return nil end
    end
    return {
        kind = shell.kind,
        executable = shell.executable,
        fixed_arguments = expected,
    }
end

local function new_accumulator(limit)
    return {
        limit = limit,
        head_limit = (limit + 1) // 2,
        tail_limit = limit // 2,
        head = "",
        tail = "",
        total = 0,
    }
end

local function append_bytes(accumulator, bytes)
    accumulator.total = accumulator.total + #bytes
    local head_room = accumulator.head_limit - #accumulator.head
    if head_room > 0 then
        accumulator.head = accumulator.head .. bytes:sub(1, head_room)
        bytes = bytes:sub(head_room + 1)
    end
    if accumulator.tail_limit > 0 and bytes ~= "" then
        accumulator.tail = (accumulator.tail .. bytes):sub(-accumulator.tail_limit)
    end
end

local function accumulated_bytes(accumulator)
    return accumulator.head .. accumulator.tail,
        accumulator.total > accumulator.limit
end

local function validate_observation(observation, maximum_poll_bytes)
    if type(observation) ~= "table" or type(observation.kind) ~= "string" then
        return nil, failure("NativeContract", "native process observation is invalid")
    end
    if observation.source ~= nil then
        return nil, failure("NativeContract", "native process must not provide event source")
    end
    if observation.kind == "stdout" or observation.kind == "stderr" then
        if type(observation.bytes) ~= "string" or #observation.bytes > maximum_poll_bytes then
            return nil, failure("NativeContract", "native process output chunk is invalid")
        end
        return observation
    end
    if observation.kind == "terminal" and TERMINAL_OUTCOMES[observation.outcome] then
        return observation
    end
    return nil, failure("NativeContract", "native process observation kind is invalid")
end

local function validate_result(result)
    if type(result) ~= "table" or not TERMINAL_OUTCOMES[result.outcome] then
        return nil, failure("NativeContract", "native process result has no terminal outcome")
    end
    if type(result.exit_kind) ~= "string"
        or not valid_integer(result.duration_ms, 0)
        or type(result.descendants_proven_stopped) ~= "boolean"
    then
        return nil, failure("NativeContract", "native process result fields are invalid")
    end
    if result.exit_code ~= nil and math.type(result.exit_code) ~= "integer" then
        return nil, failure("NativeContract", "native process exit_code is invalid")
    end
    if result.signal_or_exception ~= nil
        and type(result.signal_or_exception) ~= "string"
        and math.type(result.signal_or_exception) ~= "integer"
    then
        return nil, failure("NativeContract", "native process signal is invalid")
    end
    return result
end

local function dense_count(values)
    if type(values) ~= "table" then return nil end
    local count = 0
    for key in pairs(values) do
        if math.type(key) ~= "integer" or key < 1 then return nil end
        count = count + 1
    end
    for index = 1, count do
        if values[index] == nil then return nil end
    end
    return count
end

local function validate_component_spec(
    spec,
    maximum_output_bytes,
    maximum_stdin_bytes,
    maximum_arguments,
    maximum_argument_bytes,
    shell_kind
)
    if type(spec) ~= "table" then
        return nil, failure("InvalidComponent", "component process spec must be a table")
    end
    local allowed = {
        executable = true,
        arguments = true,
        cwd = true,
        environment = true,
        stdin_bytes = true,
        output_limit_bytes = true,
    }
    for key in pairs(spec) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure("InvalidComponent", "component process spec has an unknown field")
        end
    end
    if not valid_absolute_path(spec.executable) then
        return nil, failure(
            "InvalidExecutable",
            "internal component executable must be an absolute NUL-free path"
        )
    end
    local argument_count = dense_count(spec.arguments)
    if argument_count == nil or argument_count > maximum_arguments then
        return nil, failure("Limit", "internal component argument count exceeds its limit")
    end
    local arguments, argument_bytes = {}, 0
    for index, value in ipairs(spec.arguments) do
        if type(value) ~= "string" or value:find("\0", 1, true) then
            return nil, failure("InvalidArguments", "component arguments must be NUL-free bytes")
        end
        argument_bytes = argument_bytes + #value
        if argument_bytes > maximum_argument_bytes then
            return nil, failure("Limit", "internal component arguments exceed their byte limit")
        end
        arguments[index] = value
    end
    if spec.cwd ~= nil and not valid_absolute_path(spec.cwd) then
        return nil, failure("InvalidWorkingDirectory", "cwd must be an absolute NUL-free path")
    end
    if type(spec.stdin_bytes) ~= "string" or #spec.stdin_bytes > maximum_stdin_bytes then
        return nil, failure("Limit", "internal component stdin exceeds its byte limit")
    end
    local output_limit_bytes = spec.output_limit_bytes
    if not valid_integer(output_limit_bytes, 1) or output_limit_bytes > maximum_output_bytes then
        return nil, failure("Limit", "output_limit_bytes exceeds the release maximum")
    end
    local environment, environment_error = sanitize_environment(
        spec.environment,
        "minimal",
        shell_kind
    )
    if not environment then return nil, environment_error end
    return {
        executable = spec.executable,
        arguments = arguments,
        cwd = spec.cwd,
        environment = environment,
        stdin_bytes = spec.stdin_bytes,
        output_limit_bytes = output_limit_bytes,
    }
end

local function new_async_port(native, request_factory, output_limit_bytes, maximum_poll_bytes)
    local state = "created"
    local handle
    local terminal_outcome
    -- The release cap is combined across both canonical channels.  Fixed
    -- quotas keep retention deterministic even when the OS happens to make one
    -- pipe readable before the other one.
    local stdout_quota = (output_limit_bytes + 1) // 2
    local stderr_quota = output_limit_bytes // 2
    local stdout = new_accumulator(stdout_quota)
    local stderr = new_accumulator(stderr_quota)
    local observed_sequence = 0
    local port = {}

    function port:start(now)
        if state ~= "created" then error("process port is " .. state, 2) end
        if not valid_integer(now, 0) then error("process start time is invalid", 2) end
        local ok, value = call_native(native, "process_start", request_factory(now))
        if not ok then raise_native(value, 1) end
        if value == nil then
            raise_native(failure("NativeContract", "native process returned no handle"), 1)
        end
        handle, state = value, "started"
        return true
    end

    function port:poll(now, budget)
        if state ~= "started" then error("process port is " .. state, 2) end
        if terminal_outcome then return {} end
        if not valid_integer(now, 0) or not valid_integer(budget, 0) then
            error("process poll arguments are invalid", 2)
        end
        local ok, observations = call_native(
            native,
            "process_poll",
            handle,
            now,
            budget,
            maximum_poll_bytes
        )
        if not ok then raise_native(observations, 1) end
        if type(observations) ~= "table" then
            raise_native(failure("NativeContract", "native process poll returned no array"), 1)
        end
        local event_count = 0
        for key in pairs(observations) do
            if math.type(key) ~= "integer" or key < 1 then
                raise_native(failure("NativeContract", "native process poll returned a map"), 1)
            end
            event_count = event_count + 1
        end
        if event_count > budget then
            raise_native(failure("NativeContract", "native process exceeded poll budget"), 1)
        end
        local events = {}
        for index = 1, event_count do
            if observations[index] == nil then
                raise_native(
                    failure("NativeContract", "native process poll returned a sparse array"),
                    1
                )
            end
            local observation, observation_error = validate_observation(
                observations[index],
                maximum_poll_bytes
            )
            if not observation then raise_native(observation_error, 1) end
            if terminal_outcome then
                raise_native(
                    failure("NativeContract", "native process emitted data after terminal"),
                    1
                )
            end
            if observation.kind == "stdout" or observation.kind == "stderr" then
                local accumulator = observation.kind == "stdout" and stdout or stderr
                append_bytes(accumulator, observation.bytes)
                observed_sequence = observed_sequence + 1
                events[#events + 1] = {
                    kind = "io_progress",
                    key = observation.kind,
                    stream = observation.kind,
                    bytes = observation.bytes,
                    observed_sequence = observed_sequence,
                }
            else
                terminal_outcome = observation.outcome
                events[#events + 1] = {
                    kind = "io_terminal",
                    outcome = observation.outcome,
                }
            end
        end
        return events
    end

    function port:cancel(now)
        if state ~= "started" then error("process port is " .. state, 2) end
        if terminal_outcome then return false end
        if not valid_integer(now, 0) then error("process cancel time is invalid", 2) end
        local ok, accepted = call_native(native, "process_cancel", handle, now)
        if not ok then raise_native(accepted, 1) end
        if type(accepted) ~= "boolean" then
            raise_native(
                failure("NativeContract", "native process cancel result is invalid"),
                1
            )
        end
        return accepted
    end

    function port:join(deadline)
        if state ~= "started" then error("process port is " .. state, 2) end
        if deadline ~= nil and not valid_integer(deadline, 0) then
            error("process join deadline is invalid", 2)
        end
        local ok, value = call_native(native, "process_join", handle, deadline)
        if not ok then raise_native(value, 1) end
        local result, result_error = validate_result(value)
        if not result then raise_native(result_error, 1) end
        if terminal_outcome and terminal_outcome ~= result.outcome then
            raise_native(
                failure("NativeContract", "process join contradicted terminal event"),
                1
            )
        end
        local stdout_bytes, stdout_truncated = accumulated_bytes(stdout)
        local stderr_bytes, stderr_truncated = accumulated_bytes(stderr)
        terminal_outcome = result.outcome
        state = "joined"
        return {
            outcome = result.outcome,
            exit_kind = result.exit_kind,
            exit_code = result.exit_code,
            signal_or_exception = result.signal_or_exception,
            stdout = stdout_bytes,
            stderr = stderr_bytes,
            stdout_truncated = stdout_truncated,
            stderr_truncated = stderr_truncated,
            stdout_observed_bytes = stdout.total,
            stderr_observed_bytes = stderr.total,
            stdout_retained_bytes = #stdout_bytes,
            stderr_retained_bytes = #stderr_bytes,
            stdout_discarded_bytes = stdout.total - #stdout_bytes,
            stderr_discarded_bytes = stderr.total - #stderr_bytes,
            stdout_quota_bytes = stdout_quota,
            stderr_quota_bytes = stderr_quota,
            observed_sequences = observed_sequence,
            decoder = "bytes",
            duration_ms = result.duration_ms,
            descendants_proven_stopped = result.descendants_proven_stopped,
        }
    end

    function port:close()
        if state ~= "started" and state ~= "joined" then
            error("process port is " .. state, 2)
        end
        local ok, value = call_native(native, "process_close", handle)
        if not ok then raise_native(value, 1) end
        state = "closed"
        return true
    end

    return port
end

local function validate_spec(spec, maximum_output_bytes, shell_kind)
    if type(spec) ~= "table"
        or type(spec.command) ~= "string"
        or spec.command == ""
        or spec.command:find("\0", 1, true)
    then
        return nil, failure("InvalidCommand", "command must be a nonempty NUL-free byte string")
    end
    if spec.cwd ~= nil and not valid_absolute_path(spec.cwd) then
        return nil, failure("InvalidWorkingDirectory", "cwd must be an absolute NUL-free path")
    end
    local output_limit_bytes = spec.output_limit_bytes
    if not valid_integer(output_limit_bytes, 1) or output_limit_bytes > maximum_output_bytes then
        return nil, failure("Limit", "output_limit_bytes exceeds the release maximum")
    end
    local environment_mode = spec.environment_mode or "minimal"
    if environment_mode ~= "minimal" and environment_mode ~= "inherit_filtered" then
        return nil, failure("InvalidEnvironment", "unknown environment mode")
    end
    local environment, environment_error = sanitize_environment(
        spec.environment,
        environment_mode,
        shell_kind
    )
    if not environment then return nil, environment_error end
    return {
        command = spec.command,
        cwd = spec.cwd,
        output_limit_bytes = output_limit_bytes,
        environment_mode = environment_mode,
        environment = environment,
    }
end

---Creates a foreground process factory for one fixed platform shell.
-- The shell executable and fixed arguments come only from the selected backend;
-- callers provide one opaque command and cannot substitute the internal shell.
-- @param native table Native process implementation.
-- @param options table Fixed shell and release hard caps.
-- @return table|nil service Immutable process service.
-- @return table|nil err Structured construction failure.
function M.new(native, options)
    if type(native) ~= "table" then
        return nil, failure("InvalidProcessPort", "native process port is required")
    end
    for _, method in ipairs(REQUIRED_NATIVE_METHODS) do
        if type(native[method]) ~= "function" then
            return nil, failure("InvalidProcessPort", "native process omits " .. method)
        end
    end
    options = options or {}
    local maximum_output_bytes = options.maximum_output_bytes
    local maximum_poll_bytes = options.maximum_poll_bytes
    local maximum_stdin_bytes = options.maximum_stdin_bytes or maximum_output_bytes
    local maximum_arguments = options.maximum_arguments or maximum_poll_bytes
    local maximum_argument_bytes = options.maximum_argument_bytes or maximum_output_bytes
    local shell = options.shell
    if not valid_integer(maximum_output_bytes, 1)
        or not valid_integer(maximum_poll_bytes, 1)
        or maximum_poll_bytes > maximum_output_bytes
        or not valid_integer(maximum_stdin_bytes, 1)
        or not valid_integer(maximum_arguments, 1)
        or not valid_integer(maximum_argument_bytes, 1)
    then
        return nil, failure("InvalidProcessLimit", "process output and poll limits are required")
    end
    local validated_shell = validate_shell(shell)
    if not validated_shell then
        return nil, failure("InvalidShell", "backend shell descriptor is required")
    end
    local shell_snapshot = validated_shell

    local service = {}

    ---Creates a five-method AsyncPort for one non-interactive shell command.
    -- @param spec table Opaque command, cwd, environment mode, and output cap.
    -- @return table|nil port AsyncPort in the created state.
    -- @return table|nil err Structured validation failure.
    function service.new_port(spec)
        local validated, spec_error = validate_spec(
            spec,
            maximum_output_bytes,
            shell_snapshot.kind
        )
        if not validated then return nil, spec_error end

        return new_async_port(native, function(now)
            return {
                shell = {
                    kind = shell_snapshot.kind,
                    executable = shell_snapshot.executable,
                    fixed_arguments = copy_array(shell_snapshot.fixed_arguments),
                },
                command = validated.command,
                cwd = validated.cwd,
                environment_mode = validated.environment_mode,
                environment = validated.environment,
                stdin = "closed",
                started_at = now,
            }
        end, validated.output_limit_bytes, maximum_poll_bytes)
    end

    ---Creates a structured argv AsyncPort for one trusted bundled component.
    -- This method is a composition-layer primitive, not a model tool surface.
    -- Its environment is always constructed from a strict allowlist and its
    -- bounded stdin bytes are represented as an anonymous native pipe request.
    -- @param spec table Absolute executable, argv, clean environment, and stdin.
    -- @return table|nil port AsyncPort in the created state.
    -- @return table|nil err Structured validation failure.
    function service.new_component_port(spec)
        local validated, spec_error = validate_component_spec(
            spec,
            maximum_output_bytes,
            maximum_stdin_bytes,
            maximum_arguments,
            maximum_argument_bytes,
            shell_snapshot.kind
        )
        if not validated then return nil, spec_error end
        return new_async_port(native, function(now)
            return {
                mode = "argv",
                executable = validated.executable,
                arguments = copy_array(validated.arguments),
                cwd = validated.cwd,
                environment_mode = "clean",
                environment = validated.environment,
                stdin = {
                    kind = "bytes",
                    bytes = validated.stdin_bytes,
                    carrier = "anonymous-pipe",
                },
                started_at = now,
            }
        end, validated.output_limit_bytes, maximum_poll_bytes)
    end

    service.capabilities = readonly({
        foreground_only = true,
        interactive = false,
        stdin = "closed",
        stdout_stderr_separate = true,
        shell = shell_snapshot.kind,
        maximum_output_bytes = maximum_output_bytes,
        output_limit_scope = "combined-fixed-channel-quotas",
        maximum_poll_bytes = maximum_poll_bytes,
        internal_argv = true,
        internal_stdin = "bounded-anonymous-pipe-bytes",
        maximum_stdin_bytes = maximum_stdin_bytes,
        maximum_arguments = maximum_arguments,
        maximum_argument_bytes = maximum_argument_bytes,
        internal_target_qualified = false,
    }, "process capabilities")

    return readonly(service, "process service")
end

return M
