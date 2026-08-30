--[[
File: diagnostics.lua
Date: 2026-08-30
Author: WaterRun
Description: Projects stable secret-safe diagnostics without a log side channel.
]]

local M = {}

local EXIT_CLASSES = {
    success = 0,
    general_error = 1,
    usage = 2,
    invalid_config = 3,
    lock_conflict = 4,
    interaction_required = 5,
    resolver_negative = 6,
    cancelled = 7,
}

local function definition(id, severity, exit_class, retryable, summary, next_action)
    return {
        id = id,
        severity = severity,
        exit_class = exit_class,
        retryable = retryable,
        summary = summary,
        next_action = next_action,
    }
end

local ERROR_DEFINITIONS = {
    definition("UsageError", "error", "usage", false,
        "Invalid command usage.", "Run --help for the canonical grammar."),
    definition("ConfigMissing", "error", "invalid_config", false,
        "The main configuration is missing.", "Run --config-repl or --model-repl."),
    definition("ConfigInvalid", "error", "invalid_config", false,
        "The candidate configuration is invalid.",
        "Open the reported field in --config-repl."),
    definition("ConfigChanged", "error", "invalid_config", true,
        "The configuration changed during publication.",
        "Reload, review, and retry the transaction."),
    definition("ModelUnavailable", "error", "invalid_config", true,
        "The selected Model is unavailable.", "Select or repair an enabled Model."),
    definition("PermissionUnavailable", "error", "invalid_config", false,
        "The selected Permission is unavailable.",
        "Map the Context to a valid Permission."),
    definition("TtyRequired", "error", "interaction_required", false,
        "This action requires an interactive terminal.",
        "Use a complete non-interactive projection where supported."),
    definition("OnlineConsentRequired", "error", "interaction_required", false,
        "Online self-test consent is required.",
        "Add the explicit invocation consent or use Stage 1."),
    definition("WorkspaceConfirmationRequired", "error", "interaction_required", false,
        "The Context belongs to another workspace.",
        "Run continue from its recorded workspace or confirm an explicit rebind."),
    definition("NotFound", "error", "resolver_negative", true,
        "No matching Context was found.", "Refresh the Catalog or use a precise hash."),
    definition("HashCollision", "error", "resolver_negative", false,
        "The Context hash matches multiple paths.",
        "Choose a displayed logical path explicitly."),
    definition("MatchedUnavailable", "error", "resolver_negative", true,
        "A matching Context is unavailable.",
        "Inspect permissions or repair the Context."),
    definition("ScanIncomplete", "warning", "resolver_negative", true,
        "The Context scan is incomplete.",
        "Review the unread scope before concluding absence."),
    definition("ScanLimit", "warning", "resolver_negative", true,
        "The Context scan reached its hard limit.",
        "Narrow the view or repair the Catalog layout."),
    definition("TargetChanged", "error", "general_error", true,
        "The selected target changed after inspection.",
        "Refresh and confirm the new target snapshot."),
    definition("OpenConflict", "error", "general_error", true,
        "The Context cannot be opened in its observed state.",
        "Refresh or use context-repl self-fix."),
    definition("ContextRecoveryRequired", "error", "general_error", true,
        "The Context has unfinished or unresolved durable work.",
        "Inspect and resolve its recovery facts before continuing."),
    definition("DestinationExists", "error", "general_error", false,
        "The destination already exists.",
        "Choose another name or root; no overwrite occurred."),
    definition("LockConflict", "error", "lock_conflict", true,
        "The Context has an active writer.",
        "Wait for the writer or use evidence-based self-fix."),
    definition("UnsupportedPath", "error", "general_error", false,
        "The path cannot be represented losslessly.", "Choose a supported real path."),
    definition("UnsupportedObject", "error", "general_error", false,
        "The target object kind is unsupported.",
        "Use a regular file or directory as required."),
    definition("PathEscapesWorkspace", "error", "general_error", false,
        "The target resolves outside the workspace.",
        "Use an in-root target or satisfy OutsideWorkspace policy."),
    definition("PermissionDenied", "error", "general_error", false,
        "Permission policy denied the operation.",
        "Choose a permitted operation or change configuration explicitly."),
    definition("ApprovalRequired", "warning", "interaction_required", true,
        "Human approval is required.", "Review the bound operation snapshot."),
    definition("ApprovalStale", "warning", "interaction_required", true,
        "The approved operation snapshot is stale.",
        "Review and approve the new snapshot."),
    definition("ToolSchemaInvalid", "error", "general_error", false,
        "Tool arguments failed schema validation.",
        "Correct the tool call; it was not executed."),
    definition("ToolFailed", "error", "general_error", true,
        "The tool returned an error.", "Inspect the bounded result and retry only if safe."),
    definition("ToolCancelled", "warning", "cancelled", true,
        "The tool was cancelled.", "Inspect the paired result before continuing."),
    definition("ToolUnknown", "fatal", "general_error", false,
        "The tool side effect cannot be proven.",
        "Resolve the unknown operation before continuing."),
    definition("ProcessTimeout", "error", "general_error", true,
        "The process exceeded its deadline.",
        "Inspect termination evidence before retrying."),
    definition("NetworkError", "error", "general_error", true,
        "The Model transport failed.",
        "Inspect endpoint, proxy, CA, and retry state."),
    definition("ProtocolError", "error", "general_error", false,
        "The Model response violated the adapter protocol.",
        "Run Model self-test and inspect recorded diagnostics."),
    definition("StorageError", "fatal", "general_error", true,
        "Durable storage publication failed.",
        "Stop side effects and use context-repl self-fix."),
    definition("ContextCorrupt", "fatal", "general_error", false,
        "The Context failed structural or relation validation.",
        "Open it read-only and use context-repl self-fix."),
    definition("ContextVersionUnsupported", "error", "general_error", false,
        "The Context schema version is unsupported.",
        "Use a compatible yaca or an explicit migration."),
    definition("ContextHardLimit", "fatal", "general_error", false,
        "The Context reached its hard resource limit.",
        "Export it and start a new Context with a handoff prompt."),
    definition("ContextStale", "fatal", "general_error", true,
        "The active Context target changed externally.",
        "Stop, refresh, and explicitly recover or rebind."),
    definition("BudgetExhausted", "error", "general_error", false,
        "A runtime hard budget was exhausted.",
        "Review the partial facts and start a bounded follow-up."),
    definition("Stuck", "error", "general_error", false,
        "The no-progress detector stopped the turn.",
        "Review the durable warning and choose the next action."),
    definition("Cancelled", "warning", "cancelled", true,
        "The action was cancelled.", "Inspect the final typed outcome."),
    definition("InternalError", "fatal", "general_error", false,
        "An internal invariant failed.",
        "Preserve the Context and report the stable error details."),
}

local ERROR_BY_ID = {}
for _, item in ipairs(ERROR_DEFINITIONS) do ERROR_BY_ID[item.id] = item end

local function check(id, stage, required, online, dependencies, owner)
    return {
        id = id,
        stage = stage,
        required = required,
        online = online,
        dependencies = dependencies or {},
        owner = owner,
    }
end

local SELF_TEST_CHECKS = {
    check("ST1-PLATFORM", 1, true, false, {}, "platform"),
    check("ST1-PACKAGE", 1, true, false, { "ST1-PLATFORM" }, "release"),
    check("ST1-SAFE-LOAD", 1, true, false,
        { "ST1-PLATFORM", "ST1-PACKAGE" }, "runtime"),
    check("ST1-DATA-ROOT", 1, true, false, { "ST1-PLATFORM" }, "platform"),
    check("ST1-CONFIG-SCHEMA", 1, true, false, { "ST1-PACKAGE" }, "config"),
    check("ST1-CONFIG-SOURCE", 1, true, false,
        { "ST1-CONFIG-SCHEMA", "ST1-DATA-ROOT" }, "config"),
    check("ST1-ATOMIC-WRITE", 1, true, false, { "ST1-DATA-ROOT" }, "platform"),
    check("ST1-CONTEXT-CODEC", 1, true, false, { "ST1-PLATFORM" }, "context"),
    check("ST1-CONTEXT-SCHEMA", 1, true, false,
        { "ST1-CONTEXT-CODEC" }, "context"),
    check("ST1-CONTEXT-CATALOG", 1, true, false,
        { "ST1-DATA-ROOT", "ST1-CONTEXT-CODEC" }, "context"),
    check("ST1-CONTEXT-LOCK", 1, true, false,
        { "ST1-CONTEXT-CATALOG" }, "context"),
    check("ST1-TOOLS", 1, true, false, { "ST1-SAFE-LOAD" }, "tools"),
    check("ST1-CA-BUNDLE", 1, true, false, { "ST1-PACKAGE" }, "network"),
    check("ST1-TTY-INPUT", 1, false, false, { "ST1-PLATFORM" }, "tui"),
    check("ST1-ZERO-SURFACE", 1, true, false,
        { "ST1-PACKAGE", "ST1-CONFIG-SCHEMA" }, "release"),

    check("ST2-MODEL-TRANSPORT", 2, true, true,
        { "ST1-CA-BUNDLE", "ST1-CONFIG-SOURCE" }, "model"),
    check("ST2-MODEL-AUTH", 2, true, true,
        { "ST2-MODEL-TRANSPORT" }, "model"),
    check("ST2-MODEL-WIRE", 2, true, true, { "ST2-MODEL-AUTH" }, "model"),
    check("ST2-MODEL-STREAM", 2, true, true, { "ST2-MODEL-WIRE" }, "model"),
    check("ST2-MODEL-TOOLS", 2, true, true,
        { "ST2-MODEL-WIRE", "ST1-TOOLS" }, "model"),
    check("ST2-MODEL-CONTROL", 2, true, true,
        { "ST2-MODEL-TOOLS" }, "model"),
    check("ST2-MODEL-USAGE-CANCEL", 2, true, true,
        { "ST2-MODEL-STREAM" }, "model"),

    check("ST3-CONFIG-SEMANTICS", 3, false, true,
        { "ST2-MODEL-CONTROL" }, "diagnostics"),
    check("ST3-PERMISSION-SEMANTICS", 3, false, true,
        { "ST2-MODEL-CONTROL" }, "diagnostics"),
    check("ST3-NAMING-AND-SPELLING", 3, false, true,
        { "ST2-MODEL-CONTROL" }, "diagnostics"),
}

local SELF_TEST_CHECK_BY_ID = {}
for index, item in ipairs(SELF_TEST_CHECKS) do
    SELF_TEST_CHECK_BY_ID[item.id] = item
    for _, dependency in ipairs(item.dependencies) do
        local dependency_check = SELF_TEST_CHECK_BY_ID[dependency]
        assert(dependency_check and dependency_check.stage <= item.stage,
            "self-test check registry is not topological at " .. tostring(index))
    end
end

local SEVERITIES = { info = true, warning = true, error = true, fatal = true }
local SAVED_STATES = { none = true, durable = true, partial = true, unknown = true }
local SIDE_EFFECT_STATES = { none = true, settled = true, unknown = true }
local DETAIL_CLASSES = {
    public = true,
    identifier = true,
    digest = true,
    path = true,
    ordinary = true,
    secret = true,
    count = true,
    boolean = true,
}

local function failure(code, message, detail)
    local result = { code = code, message = message }
    if detail ~= nil then result.detail = detail end
    return result
end

local function integer_at_least(value, minimum)
    return math.type(value) == "integer" and value >= minimum
end

local function dense_count(values)
    if type(values) ~= "table" then return nil end
    local count = 0
    for key in pairs(values) do
        if math.type(key) ~= "integer" or key < 1 then return nil end
        count = count + 1
    end
    for index = 1, count do if values[index] == nil then return nil end end
    return count
end

local function exact_fields(value, allowed)
    if type(value) ~= "table" then return false end
    for key in pairs(value) do
        if type(key) ~= "string" or not allowed[key] then return false end
    end
    return true
end

local function valid_text(value, maximum, empty)
    return type(value) == "string"
        and (empty or value ~= "")
        and #value <= maximum
        and not value:find("\0", 1, true)
end

local function safe_identifier(value, maximum)
    return valid_text(value, maximum, false)
        and value:match("^[A-Za-z0-9][A-Za-z0-9._:-]*$") ~= nil
end

local function printable_ascii(value, maximum, empty)
    if not valid_text(value, maximum, empty) then return false end
    for index = 1, #value do
        local byte = value:byte(index)
        if byte < 0x20 or byte > 0x7e then return false end
    end
    return true
end

local function readonly(values, label)
    return setmetatable({}, {
        __index = values,
        __newindex = function(_, key)
            error((label or "readonly value") .. " cannot be modified: " .. tostring(key), 2)
        end,
        __pairs = function() return next, values, nil end,
        __len = function() return #values end,
        __metatable = "locked",
    })
end

local function freeze(value, visiting, label)
    if type(value) ~= "table" then return value end
    visiting = visiting or {}
    if visiting[value] then return nil end
    visiting[value] = true
    local copied = {}
    for key, item in pairs(value) do
        local frozen = freeze(item, visiting, label)
        if frozen == nil and type(item) == "table" then
            visiting[value] = nil
            return nil
        end
        copied[key] = frozen
    end
    visiting[value] = nil
    return readonly(copied, label)
end

local OPTION_FIELDS = {
    product_name = true,
    product_version = true,
    release_target = true,
    maximum_records = true,
    maximum_details = true,
    maximum_detail_name_bytes = true,
    maximum_detail_value_bytes = true,
    maximum_output_bytes = true,
    maximum_stage_bytes = true,
    maximum_cause_depth = true,
    maximum_identifier_bytes = true,
    initial_sequence = true,
}

local function validate_options(options)
    if not exact_fields(options, OPTION_FIELDS)
        or not printable_ascii(options.product_name, 128, false)
        or not printable_ascii(options.product_version, 128, false)
        or not safe_identifier(options.release_target, 128)
        or not integer_at_least(options.maximum_records, 1)
        or not integer_at_least(options.maximum_details, 0)
        or not integer_at_least(options.maximum_detail_name_bytes, 8)
        or not integer_at_least(options.maximum_detail_value_bytes, 16)
        or not integer_at_least(options.maximum_output_bytes, 512)
        or not integer_at_least(options.maximum_stage_bytes, 8)
        or not integer_at_least(options.maximum_cause_depth, 1)
        or not integer_at_least(options.maximum_identifier_bytes, 32)
        or not integer_at_least(options.initial_sequence, 0)
    then
        return nil, failure("InvalidDiagnosticOptions", "diagnostic limits are incomplete")
    end
    local copied = {}
    for key in pairs(OPTION_FIELDS) do copied[key] = options[key] end
    return copied
end

local function validate_writer(candidate)
    return candidate == false
        or (type(candidate) == "table" and type(candidate.write) == "function")
end

local function validate_ports(ports)
    if not exact_fields(ports, {
        secrets = true, stdout = true, stderr = true, context = true,
    })
        or (ports.secrets ~= false and (
            type(ports.secrets) ~= "table" or type(ports.secrets.scan) ~= "function"
        ))
        or not validate_writer(ports.stdout)
        or not validate_writer(ports.stderr)
        or (ports.context ~= false and (
            type(ports.context) ~= "table" or type(ports.context.commit) ~= "function"
        ))
    then
        return nil, failure(
            "InvalidDiagnosticPorts",
            "diagnostics accepts only secret, stdout, stderr, and Context ports"
        )
    end
    local copied = {
        secrets = false,
        stdout = false,
        stderr = false,
        context = false,
    }
    if ports.secrets ~= false then copied.secrets = { scan = ports.secrets.scan } end
    if ports.stdout ~= false then copied.stdout = { write = ports.stdout.write } end
    if ports.stderr ~= false then copied.stderr = { write = ports.stderr.write } end
    if ports.context ~= false then copied.context = { commit = ports.context.commit } end
    return copied
end

local function ascii_escape(value)
    local parts = {}
    for index = 1, #value do
        local byte = value:byte(index)
        if byte >= 0x20 and byte <= 0x7e and byte ~= 0x5c then
            parts[#parts + 1] = string.char(byte)
        elseif byte == 0x5c then
            parts[#parts + 1] = "\\\\"
        else
            parts[#parts + 1] = string.format("\\x%02X", byte)
        end
    end
    return table.concat(parts)
end

local function validate_scan_hits(hits, byte_count)
    if dense_count(hits) == nil then return nil end
    local intervals = {}
    for _, hit in ipairs(hits) do
        if not exact_fields(hit, {
            id = true, class = true, offset = true, length = true,
        })
            or not integer_at_least(hit.offset, 1)
            or not integer_at_least(hit.length, 1)
            or hit.offset + hit.length - 1 > byte_count
        then
            return nil
        end
        intervals[#intervals + 1] = {
            first = hit.offset,
            last = hit.offset + hit.length - 1,
        }
    end
    table.sort(intervals, function(left, right)
        if left.first ~= right.first then return left.first < right.first end
        return left.last > right.last
    end)
    return intervals
end

local function redact_registered(scanner, value)
    if scanner == false then return nil, "scanner-unavailable" end
    local output, offset, redacted = {}, 1, false
    while offset <= #value do
        local suffix = value:sub(offset)
        local called, hits = pcall(scanner.scan, suffix)
        local intervals = called and validate_scan_hits(hits, #suffix) or nil
        if not intervals then return nil, "scanner-failure" end
        if #intervals == 0 then
            output[#output + 1] = suffix
            break
        end
        local first, last = intervals[1].first, intervals[1].last
        for index = 2, #intervals do
            local candidate = intervals[index]
            if candidate.first > last + 1 then break end
            last = math.max(last, candidate.last)
        end
        if first > 1 then output[#output + 1] = suffix:sub(1, first - 1) end
        output[#output + 1] = "[registered-secret]"
        redacted = true
        offset = offset + last
    end
    if #value == 0 then return "", false end
    return table.concat(output), redacted
end

local function sanitize_detail(candidate, ports, limits)
    if not exact_fields(candidate, { name = true, class = true, value = true })
        or not safe_identifier(candidate.name, limits.maximum_detail_name_bytes)
        or not DETAIL_CLASSES[candidate.class]
    then
        return nil, failure("InvalidDiagnosticDetail", "diagnostic detail is ambiguous")
    end
    local class, value = candidate.class, candidate.value
    if class == "count" then
        if not integer_at_least(value, 0) then
            return nil, failure("InvalidDiagnosticDetail", "count detail is invalid")
        end
        return {
            name = candidate.name, class = class, value = tostring(value),
            redacted = false, omitted = false, possibly_secret = false,
        }
    end
    if class == "boolean" then
        if type(value) ~= "boolean" then
            return nil, failure("InvalidDiagnosticDetail", "boolean detail is invalid")
        end
        return {
            name = candidate.name, class = class, value = tostring(value),
            redacted = false, omitted = false, possibly_secret = false,
        }
    end
    if class == "secret" then
        return {
            name = candidate.name, class = class, value = "[registered-secret]",
            redacted = true, omitted = false, possibly_secret = false,
        }
    end
    if not valid_text(value, limits.maximum_detail_value_bytes, true)
        or ((class == "identifier" or class == "digest")
            and not safe_identifier(value, limits.maximum_detail_value_bytes))
        or (class == "public"
            and not printable_ascii(value, limits.maximum_detail_value_bytes, true))
    then
        return nil, failure("InvalidDiagnosticDetail", "string detail is invalid")
    end
    local sanitized, redacted_or_reason = redact_registered(ports.secrets, value)
    if not sanitized then
        if class == "ordinary" or class == "path" then
            return {
                name = candidate.name,
                class = class,
                value = "[detail-omitted:" .. redacted_or_reason .. "]",
                redacted = false,
                omitted = true,
                possibly_secret = true,
            }
        end
        if redacted_or_reason ~= "scanner-unavailable" then
            return {
                name = candidate.name,
                class = class,
                value = "[detail-omitted:scanner-failure]",
                redacted = false,
                omitted = true,
                possibly_secret = false,
            }
        end
        sanitized, redacted_or_reason = value, false
    end
    return {
        name = candidate.name,
        class = class,
        value = sanitized,
        redacted = redacted_or_reason == true,
        omitted = false,
        possibly_secret = class == "ordinary" or class == "path",
    }
end

local function registry_snapshot()
    local result = {}
    for index, item in ipairs(ERROR_DEFINITIONS) do
        result[index] = {
            id = item.id,
            severity = item.severity,
            exit_class = item.exit_class,
            exit_code = EXIT_CLASSES[item.exit_class],
            retryable = item.retryable,
            summary = item.summary,
            next_action = item.next_action,
        }
    end
    return assert(freeze(result, nil, "diagnostic error registry"))
end

local FROZEN_REGISTRY = registry_snapshot()
local FROZEN_EXIT_CLASSES = assert(freeze(
    EXIT_CLASSES,
    nil,
    "diagnostic exit classes"
))

local function registry_lines()
    local lines = {}
    for _, item in ipairs(ERROR_DEFINITIONS) do
        lines[#lines + 1] = table.concat({
            item.id,
            item.severity,
            item.exit_class,
            tostring(EXIT_CLASSES[item.exit_class]),
            tostring(item.retryable),
            item.summary,
            item.next_action,
        }, "|")
    end
    return table.concat(lines, "\n") .. "\n"
end

---Creates a bounded stable diagnostic projector.
function M.new(ports, options)
    local admitted_ports, ports_error = validate_ports(ports)
    if not admitted_ports then return nil, ports_error end
    local limits, options_error = validate_options(options)
    if not limits then return nil, options_error end

    local sequence = limits.initial_sequence
    local record_count = 0
    local records_by_id, record_states = {}, setmetatable({}, { __mode = "k" })
    local service = {}

    local function state_for(record)
        local state = type(record) == "table" and record_states[record] or nil
        if not state then
            return nil, failure("InvalidDiagnosticRecord", "record belongs to another projector")
        end
        return state
    end

    function service:record(input)
        if not exact_fields(input, {
            error_id = true,
            stage = true,
            saved_state = true,
            side_effect_state = true,
            details = true,
            cause_id = true,
            retry = true,
        })
            or not ERROR_BY_ID[input.error_id]
            or not safe_identifier(input.stage, limits.maximum_stage_bytes)
            or not SAVED_STATES[input.saved_state]
            or not SIDE_EFFECT_STATES[input.side_effect_state]
            or dense_count(input.details) == nil
            or #input.details > limits.maximum_details
            or (input.cause_id ~= false
                and not safe_identifier(input.cause_id, limits.maximum_identifier_bytes))
        then
            return nil, failure("InvalidDiagnosticRecord", "diagnostic record is invalid")
        end
        if record_count >= limits.maximum_records or sequence == math.maxinteger then
            return nil, failure("DiagnosticLimit", "diagnostic record hard cap reached")
        end
        local descriptor = ERROR_BY_ID[input.error_id]
        local retry = input.retry
        if retry ~= false then
            if not descriptor.retryable
                or not exact_fields(retry, {
                    attempt = true, maximum = true, delay_ms = true, cancellable = true,
                })
                or not integer_at_least(retry.attempt, 1)
                or not integer_at_least(retry.maximum, retry.attempt)
                or not integer_at_least(retry.delay_ms, 0)
                or type(retry.cancellable) ~= "boolean"
            then
                return nil, failure("InvalidDiagnosticRetry", "retry status is invalid")
            end
        end
        local cause
        if input.cause_id ~= false then
            cause = records_by_id[input.cause_id]
            if not cause or cause.depth >= limits.maximum_cause_depth then
                return nil, failure("InvalidDiagnosticCause", "diagnostic cause is absent or too deep")
            end
        end
        local details = {}
        for index, candidate in ipairs(input.details) do
            local sanitized, detail_error = sanitize_detail(
                candidate,
                admitted_ports,
                limits
            )
            if not sanitized then return nil, detail_error end
            details[index] = sanitized
        end
        local next_sequence = sequence + 1
        local diagnostic_id = "diagnostic-" .. tostring(next_sequence)
        if #diagnostic_id > limits.maximum_identifier_bytes then
            return nil, failure("DiagnosticLimit", "diagnostic identity exceeds its cap")
        end
        local retry_snapshot = false
        if retry ~= false then
            retry_snapshot = {
                attempt = retry.attempt,
                maximum = retry.maximum,
                delay_ms = retry.delay_ms,
                cancellable = retry.cancellable,
            }
        end
        local state = {
            diagnostic_id = diagnostic_id,
            error_id = descriptor.id,
            severity = descriptor.severity,
            exit_class = descriptor.exit_class,
            exit_code = EXIT_CLASSES[descriptor.exit_class],
            retryable = descriptor.retryable,
            summary = descriptor.summary,
            next_action = descriptor.next_action,
            stage = input.stage,
            saved_state = input.saved_state,
            side_effect_state = input.side_effect_state,
            details = details,
            cause_id = cause and cause.diagnostic_id or false,
            primary_id = cause and cause.primary_id or diagnostic_id,
            primary = cause == nil,
            depth = cause and cause.depth + 1 or 0,
            retry = retry_snapshot,
        }
        local record = assert(freeze(state, nil, "diagnostic record"))
        sequence = next_sequence
        record_count = record_count + 1
        record_states[record] = state
        records_by_id[diagnostic_id] = state
        return record
    end

    local function build_projection(state, channel, request)
        local lines = {
            "YACA-DIAGNOSTIC-V1",
            "channel=" .. channel,
            "diagnostic_id=" .. state.diagnostic_id,
            "error_id=" .. state.error_id,
            "severity=" .. state.severity,
            "summary=" .. state.summary,
            "stage=" .. state.stage,
            "saved_state=" .. state.saved_state,
            "side_effect_state=" .. state.side_effect_state,
            "retryable=" .. tostring(state.retryable),
            "next_action=" .. state.next_action,
            "exit_class=" .. state.exit_class,
            "exit_code=" .. tostring(state.exit_code),
            "product=" .. limits.product_name,
            "version=" .. limits.product_version,
            "target=" .. limits.release_target,
            "primary=" .. tostring(state.primary),
            "primary_id=" .. state.primary_id,
            "cause_id=" .. tostring(state.cause_id),
        }
        if request.last_durable_seq ~= nil then
            lines[#lines + 1] = "last_durable_seq="
                .. (request.last_durable_seq == false
                    and "none" or tostring(request.last_durable_seq))
        end
        if state.retry ~= false then
            lines[#lines + 1] = "retry_attempt=" .. tostring(state.retry.attempt)
            lines[#lines + 1] = "retry_maximum=" .. tostring(state.retry.maximum)
            lines[#lines + 1] = "retry_delay_ms=" .. tostring(state.retry.delay_ms)
            lines[#lines + 1] = "retry_cancellable=" .. tostring(state.retry.cancellable)
        end
        local base_count = #lines
        if request.include_details then
            for _, item in ipairs(state.details) do
                lines[#lines + 1] = "detail." .. item.name .. "="
                    .. ascii_escape(item.value)
                lines[#lines + 1] = "detail." .. item.name .. ".class=" .. item.class
                lines[#lines + 1] = "detail." .. item.name .. ".redacted="
                    .. tostring(item.redacted)
                lines[#lines + 1] = "detail." .. item.name .. ".omitted="
                    .. tostring(item.omitted)
                lines[#lines + 1] = "detail." .. item.name .. ".possibly_secret="
                    .. tostring(item.possibly_secret)
            end
        end
        local function encode(count, truncated)
            local values = {}
            for index = 1, count do values[index] = lines[index] end
            if truncated then values[#values + 1] = "details_truncated=true" end
            return table.concat(values, "\n") .. "\n"
        end
        local bytes = encode(#lines, false)
        local details_truncated = false
        while #bytes > limits.maximum_output_bytes and #lines > base_count do
            for _ = 1, math.min(5, #lines - base_count) do lines[#lines] = nil end
            details_truncated = true
            bytes = encode(#lines, true)
        end
        if #bytes > limits.maximum_output_bytes then
            return nil, failure("DiagnosticOutputLimit", "mandatory diagnostic card exceeds cap")
        end
        return assert(freeze({
            channel = channel,
            bytes = bytes,
            byte_count = #bytes,
            exit_class = state.exit_class,
            exit_code = state.exit_code,
            details_truncated = details_truncated,
            suppressed = false,
            primary_id = state.primary_id,
        }, nil, "diagnostic projection"))
    end

    function service:project_stderr(record, request)
        local state, record_error = state_for(record)
        if not state then return nil, record_error end
        if not exact_fields(request, {
            mode = true, include_details = true, last_durable_seq = true,
        })
            or (request.mode ~= "standard" and request.mode ~= "fatal-minimal")
            or type(request.include_details) ~= "boolean"
            or (request.last_durable_seq ~= false
                and not integer_at_least(request.last_durable_seq, 0))
        then
            return nil, failure("InvalidDiagnosticProjection", "stderr projection is invalid")
        end
        if not state.primary then
            return assert(freeze({
                channel = "stderr",
                bytes = "",
                byte_count = 0,
                exit_class = state.exit_class,
                exit_code = state.exit_code,
                details_truncated = false,
                suppressed = true,
                primary_id = state.primary_id,
            }, nil, "suppressed diagnostic projection"))
        end
        return build_projection(state, "stderr", {
            include_details = request.mode == "standard" and request.include_details,
            last_durable_seq = request.last_durable_seq,
        })
    end

    function service:project_stdout(record, request)
        local state, record_error = state_for(record)
        if not state then return nil, record_error end
        if not exact_fields(request, { explicit = true, include_details = true })
            or request.explicit ~= true
            or type(request.include_details) ~= "boolean"
        then
            return nil, failure(
                "DiagnosticExplicitOutputRequired",
                "stdout diagnostics require an explicit current action"
            )
        end
        return build_projection(state, "stdout", {
            include_details = request.include_details,
        })
    end

    function service:project_context(record, request)
        local state, record_error = state_for(record)
        if not state then return nil, record_error end
        if not exact_fields(request, { healthy = true, required = true })
            or type(request.healthy) ~= "boolean"
            or type(request.required) ~= "boolean"
        then
            return nil, failure("InvalidDiagnosticProjection", "Context projection is invalid")
        end
        if not request.healthy then
            return nil, failure(
                "DiagnosticContextUnavailable",
                "unhealthy Context cannot receive diagnostic facts"
            )
        end
        if not request.required then
            return assert(freeze({
                channel = "context",
                emitted = false,
                reason = "not-required",
            }, nil, "omitted Context diagnostic"))
        end
        local fields = {
            errorId = state.error_id,
            summary = state.summary,
        }
        if state.cause_id ~= false then fields.causeId = state.cause_id end
        local event = assert(freeze({
            type = "warning",
            fields = fields,
        }, nil, "Context diagnostic event"))
        return assert(freeze({
            channel = "context",
            emitted = true,
            event = event,
            diagnostic_id = state.diagnostic_id,
            primary_id = state.primary_id,
        }, nil, "Context diagnostic projection"))
    end

    local function emit_writer(port, projection)
        if port == false then
            return nil, failure("DiagnosticOutputUnavailable", "diagnostic channel is unavailable")
        end
        if projection.suppressed then return projection end
        local called, written, receipt = pcall(port.write, projection.bytes)
        if not called or written ~= true or type(receipt) ~= "table"
            or receipt.bytes ~= projection.byte_count
        then
            return nil, failure(
                "DiagnosticOutputFailure",
                "diagnostic channel did not confirm exact bytes"
            )
        end
        return projection
    end

    function service:emit_stderr(record, request)
        local projection, projection_error = self:project_stderr(record, request)
        if not projection then return nil, projection_error end
        return emit_writer(admitted_ports.stderr, projection)
    end

    function service:emit_stdout(record, request)
        local projection, projection_error = self:project_stdout(record, request)
        if not projection then return nil, projection_error end
        return emit_writer(admitted_ports.stdout, projection)
    end

    function service:emit_context(record, request)
        local projection, projection_error = self:project_context(record, request)
        if not projection then return nil, projection_error end
        if not projection.emitted then return projection end
        if admitted_ports.context == false then
            return nil, failure("DiagnosticContextUnavailable", "Context journal is unavailable")
        end
        local called, committed, receipt = pcall(
            admitted_ports.context.commit,
            projection.event
        )
        if not called or committed ~= true or type(receipt) ~= "table"
            or receipt.binding ~= projection.event or receipt.durable ~= true
        then
            return nil, failure(
                "DiagnosticContextFailure",
                "Context did not confirm the exact durable diagnostic fact"
            )
        end
        return projection
    end

    function service:descriptor(error_id)
        if not safe_identifier(error_id, limits.maximum_identifier_bytes) then
            return nil, failure("InvalidErrorIdentity", "error identity is invalid")
        end
        for _, item in ipairs(FROZEN_REGISTRY) do
            if item.id == error_id then return item end
        end
        return nil, failure("UnknownErrorIdentity", "error identity is not public")
    end

    function service:exit_code(value)
        local state = type(value) == "table" and record_states[value] or nil
        if state then return state.exit_code end
        local descriptor = type(value) == "string" and ERROR_BY_ID[value] or nil
        return descriptor and EXIT_CLASSES[descriptor.exit_class]
            or EXIT_CLASSES.general_error
    end

    function service:registry_lines()
        return registry_lines()
    end

    service.registry = FROZEN_REGISTRY
    service.exit_classes = FROZEN_EXIT_CLASSES
    service.contract_version = "yaca-diagnostics-v1"
    service.persistence = assert(freeze({
        standalone_log_file = false,
        standalone_diagnostic_xml = false,
        background_spool = false,
        telemetry = false,
        diagnostic_upload = false,
        context_policy = "healthy-required-facts-only",
        pre_context_policy = "stderr-and-exit-code",
        explicit_report_policy = "stdout-only",
    }, nil, "diagnostic persistence policy"))
    return readonly(service, "diagnostic service")
end

local SELF_TEST_OUTCOMES = {
    passed = true,
    warning = true,
    failed = true,
    skipped = true,
    cancelled = true,
    unknown = true,
}

local function validate_self_test_options(options)
    if not exact_fields(options, {
        maximum_models = true,
        maximum_filters = true,
        maximum_results = true,
        maximum_summary_bytes = true,
        maximum_evidence_items = true,
        maximum_evidence_bytes = true,
        maximum_online_requests = true,
        maximum_snapshot_nodes = true,
        maximum_snapshot_bytes = true,
        maximum_identifier_bytes = true,
    })
    then
        return nil, failure("InvalidSelfTestOptions", "self-test limits are required")
    end
    for _, name in ipairs({
        "maximum_models", "maximum_results", "maximum_summary_bytes",
        "maximum_evidence_bytes", "maximum_online_requests",
        "maximum_snapshot_nodes", "maximum_snapshot_bytes",
        "maximum_identifier_bytes",
    }) do
        if not integer_at_least(options[name], 1) then
            return nil, failure("InvalidSelfTestOptions", "self-test cap is invalid", name)
        end
    end
    for _, name in ipairs({ "maximum_filters", "maximum_evidence_items" }) do
        if not integer_at_least(options[name], 0) then
            return nil, failure("InvalidSelfTestOptions", "self-test cap is invalid", name)
        end
    end
    if options.maximum_models > options.maximum_results
        or options.maximum_identifier_bytes < 32
        or options.maximum_summary_bytes < 16
    then
        return nil, failure("InvalidSelfTestOptions", "self-test caps disagree")
    end
    local copied = {}
    for key, value in pairs(options) do copied[key] = value end
    return copied
end

local function validate_self_test_ports(ports)
    if not exact_fields(ports, { offline = true, model = true, advisory = true })
        or not exact_fields(ports.offline, { online = true, run = true })
        or ports.offline.online ~= false
        or type(ports.offline.run) ~= "function"
        or not exact_fields(ports.model, { online = true, run = true })
        or ports.model.online ~= true
        or type(ports.model.run) ~= "function"
        or not exact_fields(ports.advisory, {
            online = true, auto_fix = true, run = true,
        })
        or ports.advisory.online ~= true
        or ports.advisory.auto_fix ~= false
        or type(ports.advisory.run) ~= "function"
    then
        return nil, failure(
            "InvalidSelfTestPorts",
            "self-test ports must separate offline, Model, and no-auto-fix advisory checks"
        )
    end
    return {
        offline = { run = ports.offline.run },
        model = { run = ports.model.run },
        advisory = { run = ports.advisory.run },
    }
end

local function bounded_snapshot(value, limits, state, visiting)
    local value_type = type(value)
    if value_type == "string" then
        state.bytes = state.bytes + #value
        if state.bytes > limits.maximum_snapshot_bytes or value:find("\0", 1, true) then
            return nil
        end
        return value
    end
    if value_type == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return nil end
        return value
    end
    if value_type == "boolean" then return value end
    if value_type ~= "table" then return nil end
    visiting = visiting or {}
    if visiting[value] then return nil end
    visiting[value] = true
    state.nodes = state.nodes + 1
    if state.nodes > limits.maximum_snapshot_nodes then
        visiting[value] = nil
        return nil
    end
    local copied = {}
    for key, item in pairs(value) do
        if type(key) ~= "string" and math.type(key) ~= "integer" then
            visiting[value] = nil
            return nil
        end
        if type(key) == "string" then
            state.bytes = state.bytes + #key
            if state.bytes > limits.maximum_snapshot_bytes
                or key:find("\0", 1, true)
            then
                visiting[value] = nil
                return nil
            end
        end
        local copied_item = bounded_snapshot(item, limits, state, visiting)
        if copied_item == nil then
            visiting[value] = nil
            return nil
        end
        copied[key] = copied_item
    end
    visiting[value] = nil
    return copied
end

local function self_test_registry_snapshot()
    local result = {}
    for index, item in ipairs(SELF_TEST_CHECKS) do
        result[index] = {
            id = item.id,
            stage = item.stage,
            required = item.required,
            online = item.online,
            owner = item.owner,
            dependencies = item.dependencies,
        }
    end
    return assert(freeze(result, nil, "self-test check registry"))
end

local FROZEN_SELF_TEST_CHECKS = self_test_registry_snapshot()

local function validate_filter(values, maximum, known, label, validator)
    if dense_count(values) == nil or #values > maximum then
        return nil, failure("InvalidSelfTestRequest", label .. " filter is invalid")
    end
    local result = {}
    for _, value in ipairs(values) do
        if not validator(value) or not known[value] or result[value] then
            return nil, failure("InvalidSelfTestRequest", label .. " filter is invalid", value)
        end
        result[value] = true
    end
    return result
end

local function validate_check_result(result, check_item, limits)
    if not exact_fields(result, {
        outcome = true,
        summary = true,
        evidence = true,
        online_requests = true,
        auto_fixes = true,
    })
        or not SELF_TEST_OUTCOMES[result.outcome]
        or not printable_ascii(result.summary, limits.maximum_summary_bytes, false)
        or dense_count(result.evidence) == nil
        or #result.evidence > limits.maximum_evidence_items
        or not integer_at_least(result.online_requests, 0)
        or result.online_requests > limits.maximum_online_requests
        or result.auto_fixes ~= 0
    then
        return nil, failure("SelfTestContract", "check returned an invalid result", check_item.id)
    end
    local evidence = {}
    for index, value in ipairs(result.evidence) do
        if not printable_ascii(value, limits.maximum_evidence_bytes, true) then
            return nil, failure("SelfTestContract", "check evidence is unsafe", check_item.id)
        end
        evidence[index] = value
    end
    if not check_item.online and result.online_requests ~= 0 then
        return nil, failure("SelfTestContract", "offline check attempted network", check_item.id)
    end
    if check_item.online
        and (result.outcome == "passed" or result.outcome == "warning")
        and result.online_requests == 0
    then
        return nil, failure("SelfTestContract", "online pass has no real request", check_item.id)
    end
    local outcome = result.outcome
    if not check_item.required and (outcome == "failed" or outcome == "unknown") then
        outcome = "warning"
    end
    return {
        outcome = outcome,
        summary = result.summary,
        evidence = evidence,
        online_requests = result.online_requests,
    }
end

---Creates the strict Stage 1 -> Stage 2 -> Stage 3 self-test executor.
function M.new_self_test(ports, options)
    local admitted_ports, ports_error = validate_self_test_ports(ports)
    if not admitted_ports then return nil, ports_error end
    local limits, options_error = validate_self_test_options(options)
    if not limits then return nil, options_error end

    local running = false
    local service = {}

    local function run_internal(request)
        if not exact_fields(request, {
            mode = true,
            through_stage = true,
            list_checks = true,
            online_consent = true,
            excluded_models = true,
            excluded_checks = true,
            selected_checks = true,
            snapshot_id = true,
            snapshot = true,
            models = true,
        })
            or (request.mode ~= "explicit" and request.mode ~= "startup")
            or not integer_at_least(request.through_stage, 1)
            or request.through_stage > 3
            or type(request.list_checks) ~= "boolean"
            or type(request.online_consent) ~= "boolean"
            or not safe_identifier(request.snapshot_id, limits.maximum_identifier_bytes)
            or type(request.snapshot) ~= "table"
            or dense_count(request.models) == nil
            or #request.models > limits.maximum_models
            or dense_count(request.excluded_models) == nil
            or dense_count(request.excluded_checks) == nil
            or dense_count(request.selected_checks) == nil
        then
            return nil, failure("InvalidSelfTestRequest", "self-test request is invalid")
        end
        if request.mode == "startup" and (
            request.list_checks or #request.excluded_models > 0
            or #request.excluded_checks > 0 or #request.selected_checks > 0
        ) then
            return nil, failure("InvalidSelfTestRequest", "startup self-test cannot narrow scope")
        end
        local snapshot_copy = bounded_snapshot(
            request.snapshot,
            limits,
            { nodes = 0, bytes = 0 },
            {}
        )
        if not snapshot_copy then
            return nil, failure("InvalidSelfTestRequest", "self-test snapshot is unsafe")
        end
        local snapshot = assert(freeze(snapshot_copy, nil, "self-test snapshot"))
        local model_by_id, models = {}, {}
        for index, model in ipairs(request.models) do
            if not exact_fields(model, { id = true, endpoint = true, snapshot_id = true })
                or not valid_text(model.id, limits.maximum_identifier_bytes, false)
                or not valid_text(model.endpoint, limits.maximum_snapshot_bytes, false)
                or not safe_identifier(model.snapshot_id, limits.maximum_identifier_bytes)
                or model_by_id[model.id]
            then
                return nil, failure("InvalidSelfTestRequest", "enabled Model snapshot is invalid")
            end
            models[index] = {
                id = model.id,
                endpoint = model.endpoint,
                snapshot_id = model.snapshot_id,
            }
            model_by_id[model.id] = models[index]
        end
        local excluded_models, filter_error = validate_filter(
            request.excluded_models,
            limits.maximum_filters,
            model_by_id,
            "Model exclusion",
            function(value)
                return valid_text(value, limits.maximum_identifier_bytes, false)
            end
        )
        if not excluded_models then return nil, filter_error end
        local excluded_checks
        excluded_checks, filter_error = validate_filter(
            request.excluded_checks,
            limits.maximum_filters,
            SELF_TEST_CHECK_BY_ID,
            "check exclusion",
            function(value)
                return safe_identifier(value, limits.maximum_identifier_bytes)
            end
        )
        if not excluded_checks then return nil, filter_error end
        local selected_checks
        selected_checks, filter_error = validate_filter(
            request.selected_checks,
            limits.maximum_filters,
            SELF_TEST_CHECK_BY_ID,
            "check selection",
            function(value)
                return safe_identifier(value, limits.maximum_identifier_bytes)
            end
        )
        if not selected_checks then return nil, filter_error end
        for id in pairs(selected_checks) do
            if excluded_checks[id] or SELF_TEST_CHECK_BY_ID[id].stage > request.through_stage then
                return nil, failure("InvalidSelfTestRequest", "selected check is excluded or out of stage", id)
            end
        end
        if request.through_stage >= 2 and not request.list_checks
            and request.online_consent ~= true
        then
            return nil, failure(
                "OnlineConsentRequired",
                "online self-test requires explicit current-invocation consent"
            )
        end

        local selected_effective = {}
        local function include_with_dependencies(id)
            if selected_effective[id] then return end
            selected_effective[id] = true
            for _, dependency in ipairs(SELF_TEST_CHECK_BY_ID[id].dependencies) do
                include_with_dependencies(dependency)
            end
        end
        for id in pairs(selected_checks) do include_with_dependencies(id) end
        local has_selection = next(selected_checks) ~= nil
        local frozen_models = assert(freeze(models, nil, "enabled self-test Models"))
        if request.list_checks then
            return assert(freeze({
                kind = "self-test",
                outcome = "passed",
                listed = true,
                through_stage = request.through_stage,
                completed_stage = 0,
                checks = FROZEN_SELF_TEST_CHECKS,
                models = frozen_models,
                results = {},
                online_requests = 0,
                auto_fixes = 0,
                required_exclusions = 0,
                advisories = 0,
                snapshot_id = request.snapshot_id,
                consent_consumed = false,
            }, nil, "self-test listing"))
        end

        local results, result_sequence = {}, 0
        local online_requests, required_exclusions, advisories = 0, 0, 0
        local hard_failure, cancelled, partial = false, false, false
        local stage1_status, model_status = {}, {}
        local function append_result(check_item, model_id, result, excluded, reason)
            if #results >= limits.maximum_results then
                return nil, failure("SelfTestLimit", "self-test result cap reached")
            end
            result_sequence = result_sequence + 1
            results[#results + 1] = {
                sequence = result_sequence,
                check_id = check_item.id,
                stage = check_item.stage,
                required = check_item.required,
                online = check_item.online,
                owner = check_item.owner,
                model_id = model_id or false,
                outcome = result.outcome,
                summary = result.summary,
                evidence = result.evidence or {},
                advisory = check_item.stage == 3,
                excluded = excluded == true,
                reason = reason or false,
            }
            online_requests = online_requests + (result.online_requests or 0)
            if online_requests > limits.maximum_online_requests then
                return nil, failure("SelfTestLimit", "self-test online request cap reached")
            end
            if result.outcome == "cancelled" then
                cancelled = true
            elseif check_item.required then
                if result.outcome == "failed" or result.outcome == "unknown" then
                    hard_failure = true
                elseif result.outcome == "skipped" or result.outcome == "warning" then
                    partial = true
                    if result.outcome == "skipped" and excluded then
                        required_exclusions = required_exclusions + 1
                    end
                end
            elseif check_item.stage == 3 and result.outcome == "warning" then
                advisories = advisories + 1
            end
            return true
        end
        local function skipped(check_item, reason)
            return {
                outcome = "skipped",
                summary = reason,
                evidence = {},
                online_requests = 0,
            }
        end
        local function dependencies_pass(check_item, statuses)
            for _, dependency in ipairs(check_item.dependencies) do
                local status = dependency:sub(1, 3) == "ST1"
                    and stage1_status[dependency] or statuses[dependency]
                if status ~= "passed" then return false end
            end
            return true
        end
        local function call_port(port, specification, check_item)
            local frozen_spec = freeze(specification, nil, "self-test check request")
            if not frozen_spec then
                return nil, failure("SelfTestContract", "check request contains a cycle")
            end
            local called, raw = pcall(port.run, frozen_spec)
            if not called then
                return nil, failure("SelfTestContract", "check executor raised", check_item.id)
            end
            return validate_check_result(raw, check_item, limits)
        end

        for _, check_item in ipairs(SELF_TEST_CHECKS) do
            if check_item.stage == 1 then
                local excluded = excluded_checks[check_item.id]
                    or (has_selection and not selected_effective[check_item.id])
                local result, result_error
                if excluded then
                    result = skipped(check_item, "Check was excluded from this invocation.")
                elseif not dependencies_pass(check_item, stage1_status) then
                    result = skipped(check_item, "A required dependency did not pass.")
                else
                    result, result_error = call_port(admitted_ports.offline, {
                        check = check_item,
                        snapshot_id = request.snapshot_id,
                        snapshot = snapshot,
                        mode = request.mode,
                        no_network = true,
                        no_auto_fix = true,
                    }, check_item)
                    if not result then return nil, result_error end
                end
                local appended, append_error = append_result(
                    check_item,
                    false,
                    result,
                    excluded,
                    excluded and "excluded" or false
                )
                if not appended then return nil, append_error end
                stage1_status[check_item.id] = result.outcome
            end
        end
        local function overall_outcome()
            if cancelled then return "cancelled" end
            if hard_failure then return "error" end
            if partial then return "partial" end
            return "passed"
        end
        if request.through_stage == 1 or overall_outcome() ~= "passed" then
            return assert(freeze({
                kind = "self-test",
                outcome = overall_outcome(),
                listed = false,
                through_stage = request.through_stage,
                completed_stage = 1,
                checks = FROZEN_SELF_TEST_CHECKS,
                models = frozen_models,
                results = results,
                online_requests = online_requests,
                auto_fixes = 0,
                required_exclusions = required_exclusions,
                advisories = advisories,
                snapshot_id = request.snapshot_id,
                consent_consumed = false,
            }, nil, "Stage 1 self-test result"))
        end

        if #models == 0 then
            partial = true
            for _, check_item in ipairs(SELF_TEST_CHECKS) do
                if check_item.stage == 2 then
                    local appended, append_error = append_result(
                        check_item,
                        false,
                        skipped(check_item, "No enabled Model is available."),
                        true,
                        "no-enabled-model"
                    )
                    if not appended then return nil, append_error end
                end
            end
        end
        local confirmed_models = {}
        for _, model in ipairs(models) do
            local statuses = {}
            model_status[model.id] = statuses
            local model_confirmed = not excluded_models[model.id]
            for _, check_item in ipairs(SELF_TEST_CHECKS) do
                if check_item.stage == 2 then
                    local excluded = excluded_models[model.id]
                        or excluded_checks[check_item.id]
                        or (has_selection and not selected_effective[check_item.id])
                    local result, result_error
                    if excluded then
                        result = skipped(check_item, "Model or check was excluded.")
                    elseif not dependencies_pass(check_item, statuses) then
                        result = skipped(check_item, "A required dependency did not pass.")
                    else
                        result, result_error = call_port(admitted_ports.model, {
                            check = check_item,
                            model = model,
                            snapshot_id = request.snapshot_id,
                            online_consent = true,
                            no_tools_outside_fixture = true,
                            no_auto_fix = true,
                        }, check_item)
                        if not result then return nil, result_error end
                    end
                    local appended, append_error = append_result(
                        check_item,
                        model.id,
                        result,
                        excluded,
                        excluded and "excluded" or false
                    )
                    if not appended then return nil, append_error end
                    statuses[check_item.id] = result.outcome
                    if result.outcome ~= "passed" then model_confirmed = false end
                end
            end
            if model_confirmed then confirmed_models[#confirmed_models + 1] = model end
        end
        if request.through_stage == 2 or overall_outcome() ~= "passed"
            or #confirmed_models ~= #models
        then
            return assert(freeze({
                kind = "self-test",
                outcome = overall_outcome(),
                listed = false,
                through_stage = request.through_stage,
                completed_stage = 2,
                checks = FROZEN_SELF_TEST_CHECKS,
                models = frozen_models,
                confirmed_models = confirmed_models,
                results = results,
                online_requests = online_requests,
                auto_fixes = 0,
                required_exclusions = required_exclusions,
                advisories = advisories,
                snapshot_id = request.snapshot_id,
                consent_consumed = online_requests > 0,
            }, nil, "Stage 2 self-test result"))
        end

        local frozen_confirmed = assert(freeze(
            confirmed_models,
            nil,
            "Stage 3 confirmed Models"
        ))
        for _, check_item in ipairs(SELF_TEST_CHECKS) do
            if check_item.stage == 3 then
                local excluded = excluded_checks[check_item.id]
                    or (has_selection and not selected_effective[check_item.id])
                local result, result_error
                if excluded then
                    result = skipped(check_item, "Advisory check was excluded.")
                else
                    result, result_error = call_port(admitted_ports.advisory, {
                        check = check_item,
                        confirmed_models = frozen_confirmed,
                        snapshot_id = request.snapshot_id,
                        snapshot = snapshot,
                        online_consent = true,
                        advisory_only = true,
                        no_auto_fix = true,
                    }, check_item)
                    if not result then return nil, result_error end
                    if result.outcome == "failed" or result.outcome == "unknown" then
                        result.outcome = "warning"
                    end
                end
                local appended, append_error = append_result(
                    check_item,
                    false,
                    result,
                    excluded,
                    excluded and "excluded" or false
                )
                if not appended then return nil, append_error end
            end
        end
        return assert(freeze({
            kind = "self-test",
            outcome = overall_outcome(),
            listed = false,
            through_stage = request.through_stage,
            completed_stage = 3,
            checks = FROZEN_SELF_TEST_CHECKS,
            models = frozen_models,
            confirmed_models = confirmed_models,
            results = results,
            online_requests = online_requests,
            auto_fixes = 0,
            required_exclusions = required_exclusions,
            advisories = advisories,
            snapshot_id = request.snapshot_id,
            consent_consumed = online_requests > 0,
        }, nil, "Stage 3 self-test result"))
    end

    function service:run(request)
        if running then return nil, failure("SelfTestBusy", "one self-test is already active") end
        running = true
        local called, result, run_error = pcall(run_internal, request)
        running = false
        if not called then
            return nil, failure("SelfTestContract", "self-test execution raised internally")
        end
        return result, run_error
    end

    service.online = "explicit-current-invocation-only"
    service.checks = FROZEN_SELF_TEST_CHECKS
    service.stage3_is_advisory = true
    service.auto_fix = false
    service.strict_dependency_order = true
    return readonly(service, "self-test service")
end

return M
