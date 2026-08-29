--[[
File: diagnostics_test.lua
Date: 2026-08-30
Author: WaterRun
Description: Verifies the stable secret-safe diagnostic projection registry.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()
local diagnostics = assert(loadfile(
    YACA_TEST_ROOT .. "/src/diagnostics.lua",
    "t",
    _ENV
))()

local SECRET = "diagnostic-secret-token"
local OVERLAP_SECRET = "secret-token"

local function load_module(name, cache)
    cache = cache or {}
    if cache[name] then return cache[name] end
    local environment = {}
    for key, value in pairs(_ENV) do environment[key] = value end
    environment.require = function(dependency) return load_module(dependency, cache) end
    environment._G = environment
    setmetatable(environment, { __index = _ENV })
    local chunk, load_error = loadfile(
        YACA_TEST_ROOT .. "/src/" .. name .. ".lua",
        "t",
        environment
    )
    A.truthy(chunk, load_error)
    local result = chunk()
    cache[name] = result
    return result
end

local function copy(values)
    local result = {}
    for key, value in pairs(values or {}) do result[key] = value end
    return result
end

local function options(overrides)
    local result = {
        product_name = "yaca",
        product_version = "0.1.0-dev",
        release_target = "linux-x64-centos7",
        maximum_records = 32,
        maximum_details = 16,
        maximum_detail_name_bytes = 64,
        maximum_detail_value_bytes = 4096,
        maximum_output_bytes = 8192,
        maximum_stage_bytes = 64,
        maximum_cause_depth = 4,
        maximum_identifier_bytes = 128,
        initial_sequence = 0,
    }
    for key, value in pairs(overrides or {}) do result[key] = value end
    return result
end

local function scanner(settings)
    settings = settings or {}
    return {
        scan = function(bytes)
            if settings.fail then return nil, { code = "SecretScanFailure" } end
            if settings.malformed then
                return { { id = "secret", class = "key", offset = 0, length = 1 } }
            end
            local hits = {}
            for index, value in ipairs({ SECRET, OVERLAP_SECRET }) do
                local offset = bytes:find(value, 1, true)
                if offset then
                    hits[#hits + 1] = {
                        id = "secret-" .. tostring(index),
                        class = "key",
                        offset = offset,
                        length = #value,
                    }
                end
            end
            return hits
        end,
    }
end

local function fixture(settings, option_overrides)
    settings = settings or {}
    local stdout, stderr, context = {}, {}, {}
    local secret_port = scanner(settings.scanner)
    if settings.no_scanner then secret_port = false end
    local stdout_port = {
        write = function(bytes)
            stdout[#stdout + 1] = bytes
            if settings.fail_stdout then return false, { bytes = 0 } end
            return true, { bytes = #bytes }
        end,
    }
    local stderr_port = {
        write = function(bytes)
            stderr[#stderr + 1] = bytes
            if settings.fail_stderr then return false, { bytes = 0 } end
            return true, { bytes = #bytes }
        end,
    }
    local context_port = {
        commit = function(event)
            context[#context + 1] = event
            if settings.bad_context_receipt then
                return true, { binding = {}, durable = true }
            end
            return true, { binding = event, durable = true }
        end,
    }
    if settings.no_stdout then stdout_port = false end
    if settings.no_stderr then stderr_port = false end
    if settings.no_context then context_port = false end
    local ports = {
        secrets = secret_port,
        stdout = stdout_port,
        stderr = stderr_port,
        context = context_port,
    }
    local service, create_error = diagnostics.new(ports, options(option_overrides))
    A.truthy(service, create_error and create_error.code)
    return {
        service = service,
        ports = ports,
        stdout = stdout,
        stderr = stderr,
        context = context,
    }
end

local function record(service, error_id, overrides)
    overrides = overrides or {}
    return service:record({
        error_id = error_id,
        stage = overrides.stage or "runtime.dispatch",
        saved_state = overrides.saved_state or "durable",
        side_effect_state = overrides.side_effect_state or "settled",
        details = overrides.details or {},
        cause_id = overrides.cause_id or false,
        retry = overrides.retry or false,
    })
end

local function read_all(path)
    local handle = assert(io.open(path, "rb"))
    local bytes = assert(handle:read("a"))
    assert(handle:close())
    return bytes
end

local function assert_ascii_lines(bytes)
    for index = 1, #bytes do
        local byte = bytes:byte(index)
        A.truthy(byte == 0x0a or (byte >= 0x20 and byte <= 0x7e),
            "non-ASCII diagnostic byte at " .. tostring(index))
    end
end

return {
    name = "unit/diagnostics",
    cases = {
        {
            name = "public registry matches contract CLI exits and frozen golden bytes",
            run = function()
                local instance = fixture()
                local contract = assert(loadfile(
                    YACA_TEST_ROOT .. "/.develope-docs/contracts/diagnostics.lua",
                    "t",
                    _ENV
                ))()
                local cli = load_module("cli")
                local cli_registry = cli.registry()
                A.equal(#instance.service.registry, #contract.errors)
                A.deep_equal(instance.service.exit_classes, contract.exit_classes)
                for index, expected in ipairs(contract.errors) do
                    local actual = instance.service.registry[index]
                    A.equal(actual.id, expected.id)
                    A.equal(actual.severity, expected.severity)
                    A.equal(actual.exit_class, expected.exit_class)
                    A.equal(actual.exit_code, contract.exit_classes[expected.exit_class])
                    A.equal(actual.retryable, expected.retryable)
                    A.equal(actual.summary, expected.summary)
                    A.equal(actual.next_action, expected.next_action)
                    A.equal(cli_registry.error_exit_classes[actual.id], actual.exit_class)
                    assert_ascii_lines(actual.id .. actual.summary .. actual.next_action)
                end
                A.equal(
                    instance.service:registry_lines(),
                    read_all(YACA_TEST_ROOT .. "/test/golden/errors")
                )
                A.raises(function()
                    instance.service.registry[1].summary = "changed"
                end, "cannot be modified")
                A.equal(instance.service:exit_code("UsageError"), 2)
                A.equal(instance.service:exit_code("Cancelled"), 7)
                A.equal(instance.service:exit_code("not-public"), 1)
            end,
        },
        {
            name = "typed details redact every registered occurrence without raw retention",
            run = function()
                local instance = fixture()
                local retry = {
                    attempt = 2,
                    maximum = 3,
                    delay_ms = 500,
                    cancellable = true,
                }
                local input_details = {
                    {
                        name = "transport",
                        class = "ordinary",
                        value = "before:" .. SECRET .. ":middle:"
                            .. SECRET .. ":after",
                    },
                    {
                        name = "path",
                        class = "path",
                        value = "/工作/" .. OVERLAP_SECRET,
                    },
                    { name = "private", class = "secret", value = SECRET },
                    { name = "cause_code", class = "identifier", value = "curl-exit-28" },
                    { name = "attempts", class = "count", value = 2 },
                    { name = "cancellable", class = "boolean", value = true },
                }
                local captured = assert(record(instance.service, "NetworkError", {
                    details = input_details,
                    retry = retry,
                }))
                input_details[1].value = "mutated"
                retry.attempt = 99
                A.falsy(captured.details[1].value:find(SECRET, 1, true))
                A.equal(captured.details[1].redacted, true)
                A.contains(captured.details[1].value, "[registered-secret]")
                A.falsy(captured.details[2].value:find(OVERLAP_SECRET, 1, true))
                A.equal(captured.details[3].value, "[registered-secret]")
                A.equal(captured.retry.attempt, 2)

                local projection = assert(instance.service:project_stderr(captured, {
                    mode = "standard",
                    include_details = true,
                    last_durable_seq = 41,
                }))
                assert_ascii_lines(projection.bytes)
                A.falsy(projection.bytes:find(SECRET, 1, true))
                A.falsy(projection.bytes:find(OVERLAP_SECRET, 1, true))
                A.falsy(projection.bytes:find("工作", 1, true))
                A.contains(projection.bytes, "retry_attempt=2")
                A.contains(projection.bytes, "detail.transport.redacted=true")
                A.contains(projection.bytes, "\\xE5")

                local unsafe, unsafe_error = instance.service:record({
                    error_id = "NetworkError",
                    stage = "network",
                    saved_state = "none",
                    side_effect_state = "none",
                    details = {},
                    cause_id = false,
                    retry = false,
                    raw_message = SECRET,
                })
                A.falsy(unsafe)
                A.equal(unsafe_error.code, "InvalidDiagnosticRecord")

                local scannerless = fixture({ no_scanner = true })
                local omitted = assert(record(scannerless.service, "ToolFailed", {
                    details = {
                        { name = "body", class = "ordinary", value = SECRET },
                    },
                    retry = {
                        attempt = 1, maximum = 1, delay_ms = 0, cancellable = false,
                    },
                }))
                A.equal(omitted.details[1].omitted, true)
                A.equal(omitted.details[1].value,
                    "[detail-omitted:scanner-unavailable]")
                A.falsy(omitted.details[1].value:find(SECRET, 1, true))
            end,
        },
        {
            name = "stderr fatal cards are ASCII bounded and never cross to stdout",
            run = function()
                local instance = fixture()
                local captured = assert(record(instance.service, "InternalError", {
                    stage = "bootstrap.crash",
                    saved_state = "unknown",
                    side_effect_state = "unknown",
                    details = {
                        { name = "invariant", class = "public", value = "turn-owner" },
                    },
                }))
                local projection = assert(instance.service:emit_stderr(captured, {
                    mode = "fatal-minimal",
                    include_details = true,
                    last_durable_seq = 77,
                }))
                A.equal(#instance.stderr, 1)
                A.equal(#instance.stdout, 0)
                A.equal(#instance.context, 0)
                A.equal(projection.exit_code, 1)
                A.contains(projection.bytes, "error_id=InternalError")
                A.contains(projection.bytes, "stage=bootstrap.crash")
                A.contains(projection.bytes, "last_durable_seq=77")
                A.contains(projection.bytes, "side_effect_state=unknown")
                A.falsy(projection.bytes:find("detail.invariant", 1, true))
                assert_ascii_lines(projection.bytes)

                local failed = fixture({ fail_stderr = true })
                local failed_record = assert(record(failed.service, "StorageError"))
                local emitted, emit_error = failed.service:emit_stderr(failed_record, {
                    mode = "standard",
                    include_details = false,
                    last_durable_seq = false,
                })
                A.falsy(emitted)
                A.equal(emit_error.code, "DiagnosticOutputFailure")
                A.equal(#failed.stdout, 0)
                A.equal(#failed.context, 0)
            end,
        },
        {
            name = "cause chains show one primary card and persist typed references",
            run = function()
                local instance = fixture()
                local root = assert(record(instance.service, "NetworkError", {
                    stage = "network.transport",
                    retry = {
                        attempt = 1, maximum = 2, delay_ms = 250, cancellable = true,
                    },
                }))
                local child = assert(record(instance.service, "ProtocolError", {
                    stage = "model.adapter",
                    cause_id = root.diagnostic_id,
                }))
                A.equal(child.primary, false)
                A.equal(child.primary_id, root.diagnostic_id)
                local suppressed = assert(instance.service:emit_stderr(child, {
                    mode = "standard",
                    include_details = true,
                    last_durable_seq = 9,
                }))
                A.equal(suppressed.suppressed, true)
                A.equal(#instance.stderr, 0)

                local context_projection = assert(instance.service:emit_context(child, {
                    healthy = true,
                    required = true,
                }))
                A.equal(context_projection.event.type, "warning")
                A.equal(context_projection.event.fields.errorId, "ProtocolError")
                A.equal(context_projection.event.fields.causeId, root.diagnostic_id)
                A.equal(#instance.context, 1)
                A.falsy(context_projection.event.fields.details)

                local unrelated = assert(record(instance.service, "NetworkError", {
                    stage = "network.second-request",
                }))
                A.equal(unrelated.primary, true)
                assert(instance.service:emit_stderr(unrelated, {
                    mode = "standard",
                    include_details = false,
                    last_durable_seq = 10,
                }))
                A.equal(#instance.stderr, 1)
            end,
        },
        {
            name = "Context and stdout projections require their exact health and intent",
            run = function()
                local instance = fixture()
                local captured = assert(record(instance.service, "ContextStale", {
                    saved_state = "partial",
                    side_effect_state = "unknown",
                }))
                local unhealthy, unhealthy_error = instance.service:project_context(captured, {
                    healthy = false,
                    required = true,
                })
                A.falsy(unhealthy)
                A.equal(unhealthy_error.code, "DiagnosticContextUnavailable")
                local optional = assert(instance.service:emit_context(captured, {
                    healthy = true,
                    required = false,
                }))
                A.equal(optional.emitted, false)
                A.equal(#instance.context, 0)

                local implicit, implicit_error = instance.service:project_stdout(captured, {
                    explicit = false,
                    include_details = false,
                })
                A.falsy(implicit)
                A.equal(implicit_error.code, "DiagnosticExplicitOutputRequired")
                local explicit = assert(instance.service:emit_stdout(captured, {
                    explicit = true,
                    include_details = false,
                }))
                A.equal(explicit.channel, "stdout")
                A.equal(#instance.stdout, 1)
                A.equal(#instance.stderr, 0)

                local bad = fixture({ bad_context_receipt = true })
                local bad_record = assert(record(bad.service, "StorageError"))
                local persisted, persist_error = bad.service:emit_context(bad_record, {
                    healthy = true,
                    required = true,
                })
                A.falsy(persisted)
                A.equal(persist_error.code, "DiagnosticContextFailure")
            end,
        },
        {
            name = "caps malformed scanners and forbidden persistence surfaces fail closed",
            run = function()
                local limited = fixture({}, { maximum_records = 1 })
                assert(record(limited.service, "UsageError"))
                local excess, limit_error = record(limited.service, "UsageError")
                A.falsy(excess)
                A.equal(limit_error.code, "DiagnosticLimit")

                local malformed = fixture({ scanner = { malformed = true } })
                local sanitized = assert(record(malformed.service, "ToolFailed", {
                    details = {
                        { name = "body", class = "ordinary", value = SECRET },
                    },
                    retry = {
                        attempt = 1, maximum = 1, delay_ms = 0, cancellable = true,
                    },
                }))
                A.equal(sanitized.details[1].omitted, true)
                A.falsy(sanitized.details[1].value:find(SECRET, 1, true))

                local snapshotted = fixture()
                snapshotted.ports.secrets.scan = function() return {} end
                local still_redacted = assert(record(
                    snapshotted.service,
                    "ToolFailed",
                    {
                        details = {
                            { name = "body", class = "ordinary", value = SECRET },
                        },
                        retry = {
                            attempt = 1, maximum = 1, delay_ms = 0,
                            cancellable = true,
                        },
                    }
                ))
                A.falsy(still_redacted.details[1].value:find(SECRET, 1, true))
                A.equal(still_redacted.details[1].redacted, true)

                local invalid_retry, retry_error = record(
                    fixture().service,
                    "UsageError",
                    {
                        retry = {
                            attempt = 1, maximum = 1, delay_ms = 0, cancellable = true,
                        },
                    }
                )
                A.falsy(invalid_retry)
                A.equal(retry_error.code, "InvalidDiagnosticRetry")

                local bounded = fixture({}, { maximum_output_bytes = 512 })
                local verbose = assert(record(bounded.service, "InternalError", {
                    details = {
                        {
                            name = "bounded_detail",
                            class = "public",
                            value = string.rep("x", 1000),
                        },
                    },
                }))
                local bounded_projection = assert(bounded.service:project_stderr(verbose, {
                    mode = "standard",
                    include_details = true,
                    last_durable_seq = false,
                }))
                A.equal(bounded_projection.details_truncated, true)
                A.truthy(bounded_projection.byte_count <= 512)
                A.contains(bounded_projection.bytes, "details_truncated=true")
                A.contains(bounded_projection.bytes, "error_id=InternalError")

                local created, create_error = diagnostics.new({
                    secrets = false,
                    stdout = false,
                    stderr = false,
                    context = false,
                    filesystem = {},
                }, options())
                A.falsy(created)
                A.equal(create_error.code, "InvalidDiagnosticPorts")
                local policy = fixture().service.persistence
                A.equal(policy.standalone_log_file, false)
                A.equal(policy.standalone_diagnostic_xml, false)
                A.equal(policy.background_spool, false)
                A.equal(policy.telemetry, false)
                A.equal(policy.diagnostic_upload, false)
                A.falsy(fixture().service.log)
                A.falsy(fixture().service.upload)
            end,
        },
    },
}
