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

return M
