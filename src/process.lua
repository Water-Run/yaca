--[[
Author: WaterRun
Date: 2026-09-23
File: process.lua
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

-- Construct a structured diagnostic without throwing or formatting its optional fields.
--@param code string Stable diagnostic code used by callers to choose recovery behavior.
--@param message string Human-readable summary supplied by the failing operation.
--@return table New diagnostic record; optional non-nil fields are retained without deep copying.
local function failure(code, message)
    return { code = code, message = message }
end

-- Create a shallow read-only view without copying the backing table.
--@param values table Backing fields retained by reference; the caller owns their stability.
--@param label string|nil Diagnostic label; defaults to "readonly value".
--@return table Empty proxy exposing the backing fields through its locked metatable.
--@ownership Retains values by reference; nested values and the backing table are not frozen.
local function readonly(values, label)
    --@metatable readonly_proxy Forwards reads and iteration; ordinary assignments raise an error.
    --@field __index table Backing values used for missing-key reads.
    --@field __newindex function Rejects ordinary assignments without changing the backing values.
    --@field __pairs function Enumerates the backing table with next.
    --@field __metatable string Hides this metatable behind the fixed "locked" marker.
    return setmetatable({}, {
        __index = values,
        -- Reject a write through the proxy before it can create an ordinary field.
        --@param _ table Proxy receiving the assignment; its contents are not consulted.
        --@param key any Attempted field name included in the diagnostic.
        --@return nil Does not return normally.
        --@error Always raises a read-only assignment error at the caller frame.
        __newindex = function(_, key)
            error((label or "readonly value") .. " cannot be modified: " .. tostring(key), 2)
        end,
        -- Iterate the backing fields instead of the empty proxy table.
        --@param none The proxy argument supplied by pairs is ignored.
        --@return function The standard next iterator.
        --@return table Backing values used as iterator state.
        --@return nil Initial key used to start iteration.
        __pairs = function()
            return next, values, nil
        end,
        __metatable = "locked",
    })
end

-- Check the Lua integer subtype and the caller's inclusive lower bound.
--@param value any Candidate value; floats and non-numeric values are rejected.
--@param minimum integer Inclusive minimum accepted by this check.
--@return boolean True only for an integer at least minimum.
local function valid_integer(value, minimum)
    return math.type(value) == "integer" and value >= minimum
end

-- Admit a NUL-free absolute POSIX, drive, or UNC executable path spelling.
--@param path any Candidate platform path.
--@return boolean valid Whether the spelling is absolute and non-empty.
local function valid_absolute_path(path)
    if type(path) ~= "string" or path == "" or path:find("\0", 1, true) then
        return false
    end
    local normalized = path:gsub("\\", "/")
    return normalized:sub(1, 1) == "/"
        or normalized:match("^[A-Za-z]:/") ~= nil
        or normalized:match("^//[^/]+/[^/]+") ~= nil
end

-- Preserve a typed native error or replace an invalid native error contract.
--@param value any Error value returned by the native process method.
--@param operation string Native method name used in the fallback diagnostic.
--@return table err Structured process error.
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

-- Invoke a native process method under exception and return-shape containment.
--@param native table Native process port containing the selected method.
--@param method string Native method name to invoke.
--@param ... any Arguments forwarded to the native method in order.
--@return boolean ok True only when the native method returns true status.
--@return any value Native result on success or typed diagnostic on failure.
--@effect Calls the selected native method, which may start or mutate an OS process.
local function call_native(native, method, ...)
    local called, ok, value = pcall(native[method], ...)
    if not called then
        return false, failure("NativeFailure", "native process call raised an exception")
    end
    if ok == true then return true, value end
    if ok == false then return false, typed_native_error(value, method) end
    return false, failure("NativeContract", "native process returned an invalid status")
end

-- Raise a typed native error at the requested public caller frame.
--@param native_error table Diagnostic containing code and message.
--@param level integer|nil Caller-frame offset; defaults to one.
--@return nil Does not return normally.
--@error Always raises a formatted native process error.
local function raise_native(native_error, level)
    error(native_error.code .. ": " .. native_error.message, (level or 1) + 1)
end

-- Copy the contiguous array prefix while retaining element references.
--@param values table Sequence copied with ipairs.
--@return table New sequence containing the original element values through the first hole.
--@ownership Copies the outer table only; nested objects retain their original owners.
local function copy_array(values)
    local result = {}
    for index, value in ipairs(values) do result[index] = value end
    return result
end

-- Fold environment variable names with ASCII-only Windows comparison rules.
--@param value string Environment key whose non-ASCII bytes remain unchanged.
--@return string folded Uppercase ASCII key.
local function ascii_upper(value)
    -- Map one lowercase ASCII byte to its uppercase equivalent.
    --@param character string One lowercase ASCII byte matched by gsub.
    --@return string upper Corresponding uppercase ASCII byte.
    return (value:gsub("[a-z]", function(character)
        return string.char(character:byte() - 32)
    end))
end

-- Copy an environment map after rejecting ambiguity and unsafe inherited names.
--@param values table|nil Candidate string-to-string environment map.
--@param mode string minimal or inherit_filtered selection policy.
--@param shell_kind string windows or linux, used for key comparison semantics.
--@return table|nil environment Independent admitted environment map.
--@return table|nil err Structured invalid-entry or duplicate-name failure.
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

-- Match the backend shell against exact fixed command-interpreter arguments.
--@param shell table Candidate platform shell descriptor.
--@return table|nil descriptor Independent validated shell descriptor.
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

-- Allocate bounded head-and-tail retention state for one output channel.
--@param limit integer Maximum retained bytes for this channel.
--@return table accumulator Mutable output retention state.
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

-- Record a new observed chunk while retaining deterministic head and tail bytes.
--@param accumulator table Mutable channel retention state.
--@param bytes string Newly observed bytes in native event order.
--@return nil No result; the accumulator tracks total and retained bytes.
--@effect Mutates accumulator total, head, and tail.
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

-- Read the retained bytes and whether the channel exceeded its quota.
--@param accumulator table Completed or in-progress channel retention state.
--@return string bytes Retained head followed by retained tail.
--@return boolean truncated Whether more than the quota was observed.
local function accumulated_bytes(accumulator)
    return accumulator.head .. accumulator.tail,
        accumulator.total > accumulator.limit
end

-- Admit one native process output or terminal observation without event provenance.
--@param observation any Native observation record.
--@param maximum_poll_bytes integer Maximum bytes admitted for one output event.
--@return table|nil admitted Original valid observation record.
--@return table|nil err Structured native contract failure.
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

-- Check the native joined-process result before projecting public evidence.
--@param result any Candidate terminal result record.
--@return table|nil admitted Original valid native result.
--@return table|nil err Structured native result contract failure.
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

-- Count a dense one-based array while rejecting holes and extra key kinds.
--@param values any Candidate table; every key must belong to the sequence 1 through count.
--@return integer|nil Sequence length, including zero for an empty table; nil for an invalid shape.
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

-- Admit a trusted internal argv process with bounded stdin, arguments, and output.
--@param spec table Candidate component executable, argv, cwd, env, and stdin.
--@param maximum_output_bytes integer Service output cap.
--@param maximum_stdin_bytes integer Service stdin byte cap.
--@param maximum_arguments integer Service argv element cap.
--@param maximum_argument_bytes integer Service total argv byte cap.
--@param shell_kind string Platform kind used for environment-name admission.
--@return table|nil admitted Independent validated component request facts.
--@return table|nil err Structured component, path, argument, or limit failure.
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

-- Create a five-method process port with fixed output quotas and handle lifecycle.
--@param native table Validated native process callbacks.
--@param request_factory function Builds the native start request from a monotonic start time.
--@param output_limit_bytes integer Combined retained stdout/stderr byte cap.
--@param maximum_poll_bytes integer Maximum native output chunk bytes per poll event.
--@return table port Mutable AsyncPort in created state; caller owns start through close.
--@ownership Port owns its native handle after successful start and releases it on close.
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

    -- Start the native process exactly once from the created state.
    --@param self table This AsyncPort and its captured lifecycle state.
    --@param now integer Nonnegative monotonic start timestamp.
    --@return boolean started True after a valid native handle is obtained.
    --@error Raises for invalid state/time or native process failure.
    --@effect Starts an OS process and takes ownership of its handle.
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

    -- Project bounded native observations to ordered progress or terminal events.
    --@param self table Started AsyncPort whose native handle remains owned.
    --@param now integer Nonnegative monotonic observation timestamp.
    --@param budget integer Maximum event count accepted from this poll.
    --@return table events Ordered validated progress/terminal event sequence.
    --@error Raises on invalid state, arguments, or native contract violation.
    --@effect Polls the OS process and updates output quotas and terminal state.
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

    -- Request cancellation of a live process before a terminal observation.
    --@param self table Started AsyncPort owning the process handle.
    --@param now integer Nonnegative monotonic cancellation timestamp.
    --@return boolean accepted Native cancellation acceptance; false if already terminal.
    --@error Raises on invalid state/time or native process failure.
    --@effect Requests native process-tree cancellation.
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

    -- Join the process and combine its terminal result with bounded output evidence.
    --@param self table Started AsyncPort owning the process handle.
    --@param deadline integer|nil Optional nonnegative monotonic join deadline.
    --@return table result Terminal outcome, exit data, output retention, and stop proof.
    --@error Raises on invalid state/deadline or contradictory native result.
    --@effect Waits for process completion and transitions the port to joined.
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

    -- Release a started or joined native process handle exactly once.
    --@param self table AsyncPort owning the process handle.
    --@return boolean closed True after native close succeeds.
    --@error Raises on invalid state or native close failure.
    --@effect Closes the native handle and transitions the port to closed.
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

-- Admit one opaque shell command with a bounded output and filtered environment.
--@param spec table Candidate command, cwd, environment mode, and output cap.
--@param maximum_output_bytes integer Service output cap.
--@param shell_kind string Platform kind used for environment-name admission.
--@return table|nil admitted Independent validated command request facts.
--@return table|nil err Structured command, path, environment, or limit failure.
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
--@param native table Native process implementation.
--@param options table Fixed shell and release hard caps.
--@return table|nil service Immutable process service.
--@return table|nil err Structured construction failure.
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
    --@param spec table Opaque command, cwd, environment mode, and output cap.
    --@return table|nil port AsyncPort in the created state.
    --@return table|nil err Structured validation failure.
    function service.new_port(spec)
        local validated, spec_error = validate_spec(
            spec,
            maximum_output_bytes,
            shell_snapshot.kind
        )
        if not validated then return nil, spec_error end

        -- Build the fixed-shell native start request from validated command facts.
        --@param now integer Nonnegative monotonic start timestamp.
        --@return table request Native shell process request with closed stdin.
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
    --@param spec table Absolute executable, argv, clean environment, and stdin.
    --@return table|nil port AsyncPort in the created state.
    --@return table|nil err Structured validation failure.
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
        -- Build the native argv request with bounded anonymous-pipe stdin.
        --@param now integer Nonnegative monotonic start timestamp.
        --@return table request Native component process request.
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
