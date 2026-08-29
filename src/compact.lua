--[[
File: compact.lua
Date: 2026-08-29
Author: WaterRun
Description: Builds and publishes lossless-facts structured ModelView compactions.
]]

local M = {}

local SUMMARY_SLOTS = {
    "goals_decisions",
    "constraints_permissions",
    "files_touched",
    "verification_evidence",
    "unknown_side_effects",
    "open_todos",
    "prompt_model_transitions",
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

local function valid_id(value, maximum)
    return valid_text(value, maximum, false)
        and value:match("^[A-Za-z0-9][A-Za-z0-9._:-]*$") ~= nil
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

local function copy_array(values)
    local copied = {}
    for index, value in ipairs(values or {}) do copied[index] = value end
    return copied
end

local function tagged(tag, value)
    value = tostring(value)
    return tag .. ":" .. tostring(#value) .. ":" .. value
end

local function canonical_event(item, maximum_identifier_bytes, maximum_input_bytes)
    if not exact_fields(item, {
        seq = true, type = true, at = true, turn_id = true, fields = true,
        field_order = true, field_metadata = true,
    })
        or not integer_at_least(item.seq, 1)
        or not valid_id(item.type, maximum_identifier_bytes)
        or not valid_text(item.at, maximum_input_bytes, false)
        or (item.turn_id ~= nil
            and not valid_id(item.turn_id, maximum_identifier_bytes))
        or type(item.fields) ~= "table"
    then
        return nil, failure("InvalidCompactionEvent", "Context event is not canonical")
    end
    local names = {}
    for name, value in pairs(item.fields) do
        if not valid_text(name, maximum_identifier_bytes, false)
            or not valid_text(value, maximum_input_bytes, true)
        then
            return nil, failure("InvalidCompactionEvent", "Context event field is invalid")
        end
        names[#names + 1] = name
    end
    table.sort(names)
    local pieces = {
        "yaca-event-v1",
        tagged("seq", item.seq),
        tagged("type", item.type),
        tagged("at", item.at),
        tagged("turn", item.turn_id or ""),
    }
    for _, name in ipairs(names) do
        pieces[#pieces + 1] = tagged("name", name)
        pieces[#pieces + 1] = tagged("value", item.fields[name])
    end
    local encoded = table.concat(pieces, "\n") .. "\n"
    if #encoded > maximum_input_bytes then
        return nil, failure("CompactionInputLimit", "one canonical event exceeds input limit")
    end
    return encoded
end

local function encode_summary(summary)
    local pieces = { "yaca-structured-summary-v1" }
    pieces[#pieces + 1] = tagged("schema", summary.schema_version)
    pieces[#pieces + 1] = tagged("source-first", summary.source_first_seq)
    pieces[#pieces + 1] = tagged("source-last", summary.source_last_seq)
    pieces[#pieces + 1] = tagged("source-digest", summary.source_digest)
    for _, name in ipairs(SUMMARY_SLOTS) do
        pieces[#pieces + 1] = tagged(name, summary[name])
    end
    return table.concat(pieces, "\n") .. "\n"
end

local function decode_summary(bytes, maximum)
    if not valid_text(bytes, maximum, false) then
        return nil, failure("InvalidStructuredSummary", "summary bytes are invalid")
    end
    local header = "yaca-structured-summary-v1\n"
    if bytes:sub(1, #header) ~= header then
        return nil, failure("InvalidStructuredSummary", "summary envelope is invalid")
    end
    local cursor = #header + 1
    local function read_tag(expected)
        local tag_end = bytes:find(":", cursor, true)
        if not tag_end then return nil end
        local size_end = bytes:find(":", tag_end + 1, true)
        if not size_end or bytes:sub(cursor, tag_end - 1) ~= expected then return nil end
        local size_bytes = bytes:sub(tag_end + 1, size_end - 1)
        if size_bytes == "" or not size_bytes:match("^[0-9]+$")
            or (#size_bytes > 1 and size_bytes:sub(1, 1) == "0")
        then
            return nil
        end
        local size = tonumber(size_bytes)
        if not integer_at_least(size, 0) or size > maximum then return nil end
        local value_first = size_end + 1
        local value_last = value_first + size - 1
        if value_last > #bytes or bytes:sub(value_last + 1, value_last + 1) ~= "\n" then
            return nil
        end
        local value = bytes:sub(value_first, value_last)
        cursor = value_last + 2
        return value
    end
    local summary = {
        schema_version = read_tag("schema"),
        source_first_seq = tonumber(read_tag("source-first")),
        source_last_seq = tonumber(read_tag("source-last")),
        source_digest = read_tag("source-digest"),
    }
    for _, name in ipairs(SUMMARY_SLOTS) do summary[name] = read_tag(name) end
    if not summary.schema_version
        or not integer_at_least(summary.source_first_seq, 1)
        or not integer_at_least(summary.source_last_seq, summary.source_first_seq)
        or not summary.source_digest
        or cursor ~= #bytes + 1
    then
        return nil, failure("InvalidStructuredSummary", "summary fields are malformed")
    end
    for _, name in ipairs(SUMMARY_SLOTS) do
        if not summary[name] or summary[name] == "" then
            return nil, failure("InvalidStructuredSummary", "summary slot is absent", name)
        end
    end
    if encode_summary(summary) ~= bytes then
        return nil, failure("InvalidStructuredSummary", "summary encoding is not canonical")
    end
    return summary
end

local function ranges_from_sequences(sequences)
    table.sort(sequences)
    local ranges = {}
    local first, last
    for _, sequence in ipairs(sequences) do
        if first == nil then
            first, last = sequence, sequence
        elseif sequence == last + 1 then
            last = sequence
        else
            ranges[#ranges + 1] = { first = first, last = last }
            first, last = sequence, sequence
        end
    end
    if first ~= nil then ranges[#ranges + 1] = { first = first, last = last } end
    return ranges
end

local function encode_ranges(ranges)
    local parts = {}
    for index, range in ipairs(ranges) do
        parts[index] = tostring(range.first) .. "-" .. tostring(range.last)
    end
    return table.concat(parts, ",")
end

local function canonical_manifest(manifest)
    local pieces = {
        "yaca-model-view-manifest-v1",
        tagged("schema", manifest.schema_version),
        tagged("context-generation", manifest.context_generation),
        tagged("context-digest", manifest.context_digest),
        tagged("model", manifest.model_id),
        tagged("model-snapshot", manifest.model_snapshot_digest),
        tagged("window", manifest.window_tokens),
        tagged("prompt", manifest.prompt_bundle_digest),
        tagged("summary", manifest.summary_id),
        tagged("summary-source", manifest.summary_source_range),
        tagged("included-ranges", encode_ranges(manifest.included_event_ranges)),
        tagged("excluded-prefix", manifest.excluded_prefix_reason),
        tagged("algorithm", manifest.builder_algorithm),
        tagged("estimated-tokens", manifest.estimated_tokens),
        tagged("estimate-kind", "estimated"),
        tagged("corrections", table.concat(manifest.correction_ids, ",")),
    }
    return table.concat(pieces, "\n") .. "\n"
end

local MANIFEST_FIELDS = {
    snapshot_id = true,
    builder_algorithm = true,
    summary_schema = true,
    maximum_events = true,
    maximum_groups = true,
    maximum_input_bytes = true,
    maximum_summary_bytes = true,
    maximum_summary_tokens = true,
    maximum_view_tokens = true,
    maximum_attempts = true,
    active_time_ms = true,
    trigger_numerator = true,
    trigger_denominator = true,
    reserve_tokens = true,
    minimum_benefit_tokens = true,
}

local function validate_options(options)
    if not exact_fields(options, {
        manifest = true, maximum_identifier_bytes = true, initial_serial = true,
    })
        or not exact_fields(options.manifest, MANIFEST_FIELDS)
        or not integer_at_least(options.maximum_identifier_bytes, 16)
        or not integer_at_least(options.initial_serial, 0)
    then
        return nil, failure("InvalidCompactionOptions", "compaction options are ambiguous")
    end
    local manifest = options.manifest
    for _, name in ipairs({
        "maximum_events", "maximum_groups", "maximum_input_bytes",
        "maximum_summary_bytes", "maximum_summary_tokens", "maximum_view_tokens",
        "maximum_attempts", "active_time_ms", "trigger_numerator",
        "trigger_denominator", "reserve_tokens", "minimum_benefit_tokens",
    }) do
        local minimum = (name == "reserve_tokens" or name == "minimum_benefit_tokens")
            and 0 or 1
        if not integer_at_least(manifest[name], minimum) then
            return nil, failure("InvalidCompactionOptions", "compaction manifest cap is invalid", name)
        end
    end
    if not valid_id(manifest.snapshot_id, options.maximum_identifier_bytes)
        or not valid_id(manifest.builder_algorithm, options.maximum_identifier_bytes)
        or not valid_id(manifest.summary_schema, options.maximum_identifier_bytes)
        or manifest.maximum_attempts ~= 2
        or manifest.trigger_numerator >= manifest.trigger_denominator
        or manifest.maximum_summary_tokens >= manifest.maximum_view_tokens
    then
        return nil, failure("InvalidCompactionOptions", "compaction manifest identity is invalid")
    end
    local copied = { maximum_identifier_bytes = options.maximum_identifier_bytes,
        initial_serial = options.initial_serial, manifest = {} }
    for name in pairs(MANIFEST_FIELDS) do copied.manifest[name] = manifest[name] end
    return copied
end

local function validate_ports(ports)
    if not exact_fields(ports, {
        safety = true, estimator = true, clock = true, model = true, journal = true,
    })
        or type(ports.safety) ~= "table"
        or type(ports.safety.digest) ~= "function"
        or type(ports.estimator) ~= "table"
        or type(ports.estimator.estimate) ~= "function"
        or type(ports.clock) ~= "table"
        or type(ports.clock.now) ~= "function"
        or type(ports.model) ~= "table"
        or type(ports.model.start) ~= "function"
        or type(ports.model.cancel) ~= "function"
        or type(ports.journal) ~= "table"
    then
        return nil, failure("InvalidCompactionPorts", "compaction ports are incomplete")
    end
    for _, method in ipairs({
        "commit_intent", "commit_response", "commit_rejection",
        "publish", "commit_correction",
    }) do
        if type(ports.journal[method]) ~= "function" then
            return nil, failure("InvalidCompactionPorts", "compaction journal is incomplete", method)
        end
    end
    return ports
end

local function digest_bytes(ports, bytes)
    local called, value, digest_error = pcall(ports.safety.digest, bytes)
    if not called or not valid_text(value, 512, false) then
        return nil, failure(
            "CompactionDigestFailure",
            "compaction digest service failed",
            called and digest_error or value
        )
    end
    return value
end

local function estimate_bytes(ports, bytes, model_snapshot)
    local called, value, estimate_error = pcall(
        ports.estimator.estimate,
        bytes,
        model_snapshot
    )
    if not called or not integer_at_least(value, 0) then
        return nil, failure(
            "CompactionEstimateFailure",
            "token estimator failed",
            called and estimate_error or value
        )
    end
    return value
end

local function validate_input(input, limits)
    if not exact_fields(input, {
        mode = true, document = true, expected_context_generation = true,
        expected_manifest_digest = true, context_digest = true,
        model_snapshot = true, prompt_bundle_digest = true,
        prompt_tokens = true, tool_schema_tokens = true, control_schema_tokens = true,
        main_state = true, active_view = true, corrections = true,
    })
        or (input.mode ~= "automatic" and input.mode ~= "manual")
        or type(input.document) ~= "table"
        or not integer_at_least(input.expected_context_generation, 1)
        or input.document.generation ~= input.expected_context_generation
        or not valid_text(input.expected_manifest_digest, 512, false)
        or not valid_text(input.context_digest, 512, false)
        or not valid_text(input.prompt_bundle_digest, 512, false)
        or not integer_at_least(input.prompt_tokens, 0)
        or not integer_at_least(input.tool_schema_tokens, 0)
        or not integer_at_least(input.control_schema_tokens, 0)
        or not valid_text(input.main_state, limits.maximum_identifier_bytes, false)
        or dense_count(input.corrections) == nil
    then
        return nil, failure("InvalidCompactionInput", "compaction input is invalid")
    end
    if input.mode == "manual" and input.main_state ~= "Idle" then
        return nil, failure("ManualCompactionBusy", "manual compaction requires durable idle")
    end
    local document = input.document
    if dense_count(document.facts) == nil
        or document.event_count ~= #document.facts
        or document.event_count > limits.manifest.maximum_events
        or type(document.model_view) ~= "table"
        or type(document.model_view.active_manifest) ~= "table"
        or document.model_view.active_manifest.digest ~= input.expected_manifest_digest
    then
        return nil, failure("InvalidCompactionInput", "Context snapshot binding is invalid")
    end
    local model = input.model_snapshot
    if not exact_fields(model, {
        id = true, digest = true, window_tokens = true, maximum_output_tokens = true,
    })
        or not valid_id(model.id, limits.maximum_identifier_bytes)
        or not valid_text(model.digest, 512, false)
        or not integer_at_least(model.window_tokens, 1)
        or not integer_at_least(model.maximum_output_tokens, 1)
    then
        return nil, failure("InvalidCompactionInput", "frozen Model snapshot is invalid")
    end
    if input.active_view ~= false then
        if not exact_fields(input.active_view, {
            manifest_digest = true, estimated_tokens = true,
            builder_algorithm = true, summary_id = true, included_ranges = true,
        })
            or input.active_view.manifest_digest ~= input.expected_manifest_digest
            or not integer_at_least(input.active_view.estimated_tokens, 0)
            or input.active_view.builder_algorithm ~= limits.manifest.builder_algorithm
            or (input.active_view.summary_id ~= false
                and not valid_id(input.active_view.summary_id, limits.maximum_identifier_bytes))
            or dense_count(input.active_view.included_ranges) == nil
        then
            return nil, failure("InvalidCompactionInput", "active ModelView snapshot is invalid")
        end
        local previous_last = 0
        for _, range in ipairs(input.active_view.included_ranges) do
            if not exact_fields(range, { first = true, last = true })
                or not integer_at_least(range.first, 1)
                or not integer_at_least(range.last, range.first)
                or range.last > document.event_count
                or range.first <= previous_last
            then
                return nil, failure(
                    "InvalidCompactionInput",
                    "active ModelView range is invalid"
                )
            end
            previous_last = range.last
        end
    end
    if #input.corrections > limits.manifest.maximum_events then
        return nil, failure("InvalidCompactionInput", "too many summary corrections")
    end
    local correction_bytes, correction_ids = 0, {}
    for _, correction in ipairs(input.corrections) do
        if not exact_fields(correction, {
            correction_id = true, compaction_id = true, text = true,
        })
            or not valid_id(correction.correction_id, limits.maximum_identifier_bytes)
            or not valid_id(correction.compaction_id, limits.maximum_identifier_bytes)
            or not valid_text(correction.text, limits.manifest.maximum_summary_bytes, false)
        then
            return nil, failure("InvalidCompactionInput", "summary correction is invalid")
        end
        if correction_ids[correction.correction_id] then
            return nil, failure("InvalidCompactionInput", "summary correction is duplicated")
        end
        correction_ids[correction.correction_id] = true
        correction_bytes = correction_bytes + #correction.text
        if correction_bytes > limits.manifest.maximum_input_bytes then
            return nil, failure("CompactionInputLimit", "summary corrections exceed input cap")
        end
    end
    return true
end

local function build_groups(input, ports, limits)
    local facts = input.document.facts
    local count = #facts
    local parent, rank, encoded, tokens = {}, {}, {}, {}
    for index = 1, count do parent[index], rank[index] = index, 0 end
    local function find(index)
        local root = index
        while parent[root] ~= root do root = parent[root] end
        while parent[index] ~= index do
            local next_index = parent[index]
            parent[index] = root
            index = next_index
        end
        return root
    end
    local function union(left, right)
        left, right = find(left), find(right)
        if left == right then return end
        if rank[left] < rank[right] then left, right = right, left end
        parent[right] = left
        if rank[left] == rank[right] then rank[left] = rank[left] + 1 end
    end
    local bindings = {}
    local turn_ended, calls, results, operations, operation_results = {}, {}, {}, {}, {}
    local mandatory_event = {}
    local function bind(key, index)
        local prior = bindings[key]
        if prior then union(prior, index) else bindings[key] = index end
    end
    local link_fields = {
        requestId = true, toolCallId = true, operationId = true, queueItemId = true,
    }
    for index, item in ipairs(facts) do
        if item.seq ~= index then
            return nil, failure("InvalidCompactionInput", "Context sequence is not canonical")
        end
        local bytes, event_error = canonical_event(
            item,
            limits.maximum_identifier_bytes,
            limits.manifest.maximum_input_bytes
        )
        if not bytes then return nil, event_error end
        encoded[index] = bytes
        tokens[index], event_error = estimate_bytes(ports, bytes, input.model_snapshot)
        if tokens[index] == nil then return nil, event_error end
        if item.turn_id then bind("turn:" .. item.turn_id, index) end
        for name, value in pairs(item.fields) do
            if link_fields[name] and value ~= "" then bind(name .. ":" .. value, index) end
        end
        if item.type == "turn_ended" and item.turn_id then turn_ended[item.turn_id] = true end
        if item.type == "tool_call" then
            if not valid_text(item.fields.toolCallId, limits.maximum_identifier_bytes, false)
                or calls[item.fields.toolCallId]
            then
                return nil, failure("InvalidCompactionInput", "tool call binding is invalid")
            end
            calls[item.fields.toolCallId] = index
        end
        if item.type == "tool_result" then
            if not valid_text(item.fields.toolCallId, limits.maximum_identifier_bytes, false)
                or results[item.fields.toolCallId]
            then
                return nil, failure("InvalidCompactionInput", "tool result binding is invalid")
            end
            results[item.fields.toolCallId] = true
        end
        if item.type == "operation_intent" then
            if not valid_text(item.fields.operationId, limits.maximum_identifier_bytes, false)
                or operations[item.fields.operationId]
            then
                return nil, failure("InvalidCompactionInput", "operation binding is invalid")
            end
            operations[item.fields.operationId] = index
        end
        if item.type == "operation_result" then
            if not valid_text(item.fields.operationId, limits.maximum_identifier_bytes, false)
                or operation_results[item.fields.operationId]
            then
                return nil, failure("InvalidCompactionInput", "operation result binding is invalid")
            end
            operation_results[item.fields.operationId] = true
            if item.fields.status == "unknown" then mandatory_event[index] = true end
        elseif item.type == "unknown_side_effect" then
            mandatory_event[index] = true
        end
    end
    local grouped = {}
    for index = 1, count do
        local root = find(index)
        local group = grouped[root]
        if not group then
            group = { sequences = {}, tokens = 0, bytes = 0, mandatory = false }
            grouped[root] = group
        end
        group.sequences[#group.sequences + 1] = index
        group.tokens = group.tokens + tokens[index]
        group.bytes = group.bytes + #encoded[index]
        if mandatory_event[index] then group.mandatory = true end
        local turn_id = facts[index].turn_id
        if turn_id and not turn_ended[turn_id] then group.mandatory = true end
    end
    for id, index in pairs(calls) do
        if not results[id] then grouped[find(index)].mandatory = true end
    end
    for id, index in pairs(operations) do
        if not operation_results[id] then grouped[find(index)].mandatory = true end
    end
    local groups = {}
    for _, group in pairs(grouped) do
        table.sort(group.sequences)
        group.first = group.sequences[1]
        group.last = group.sequences[#group.sequences]
        group.ranges = ranges_from_sequences(copy_array(group.sequences))
        groups[#groups + 1] = group
    end
    table.sort(groups, function(left, right) return left.first < right.first end)
    if #groups > limits.manifest.maximum_groups then
        return nil, failure("CompactionGroupLimit", "atomic group count exceeds manifest cap")
    end
    return groups, encoded
end

local function plan_internal(input, ports, limits)
    local valid, input_error = validate_input(input, limits)
    if not valid then return nil, input_error end
    local groups, encoded_or_error = build_groups(input, ports, limits)
    if not groups then return nil, encoded_or_error end
    local encoded = encoded_or_error
    local window = math.min(
        input.model_snapshot.window_tokens,
        limits.manifest.maximum_view_tokens
    )
    local threshold = (window * limits.manifest.trigger_numerator)
        // limits.manifest.trigger_denominator
    local base_tokens = input.prompt_tokens + input.tool_schema_tokens
        + input.control_schema_tokens + input.model_snapshot.maximum_output_tokens
        + limits.manifest.reserve_tokens
    local correction_tokens, correction_byte_count, corrections = 0, 0, {}
    for index, correction in ipairs(input.corrections) do
        local estimated, estimate_error = estimate_bytes(
            ports,
            correction.text,
            input.model_snapshot
        )
        if estimated == nil then return nil, estimate_error end
        correction_tokens = correction_tokens + estimated
        correction_byte_count = correction_byte_count + #correction.text
        corrections[index] = {
            correction_id = correction.correction_id,
            compaction_id = correction.compaction_id,
            text = correction.text,
        }
    end
    base_tokens = base_tokens + correction_tokens
    if base_tokens >= threshold or base_tokens >= window then
        return {
            decision = "waiting_user",
            reason = "mandatory-view-capacity",
            error_code = "CompactionCapacityMismatch",
            threshold_tokens = threshold,
            window_tokens = window,
            base_tokens = base_tokens,
            recommendation_required = true,
        }
    end
    local all_group_tokens = 0
    for _, group in ipairs(groups) do
        all_group_tokens = all_group_tokens + group.tokens
        if group.mandatory and base_tokens + group.tokens >= window then
            return {
                decision = "waiting_user",
                reason = "oversized-atomic-group",
                error_code = "OversizedAtomicGroup",
                oversized_group = {
                    first = group.first, last = group.last,
                    ranges = group.ranges, estimated_tokens = group.tokens,
                },
                threshold_tokens = threshold,
                window_tokens = window,
                recommendation_required = true,
            }
        end
    end
    local current_estimated_tokens = input.active_view ~= false
        and input.active_view.estimated_tokens
        or base_tokens + all_group_tokens
    if input.mode == "automatic" and current_estimated_tokens < threshold then
        local all_sequences = {}
        for index = 1, #input.document.facts do all_sequences[index] = index end
        return {
            decision = "fits",
            current_estimated_tokens = current_estimated_tokens,
            threshold_tokens = threshold,
            window_tokens = window,
            included_event_ranges = ranges_from_sequences(all_sequences),
            groups = groups,
            base_tokens = base_tokens,
        }
    end
    if #groups < 2 or #input.document.facts < 2 then
        return {
            decision = input.mode == "manual" and "no_op" or "waiting_user",
            reason = "no-closed-prefix",
            error_code = "NothingToCompact",
            current_estimated_tokens = current_estimated_tokens,
            threshold_tokens = threshold,
            window_tokens = window,
        }
    end
    local earliest_mandatory = #input.document.facts + 1
    for _, group in ipairs(groups) do
        if group.mandatory then earliest_mandatory = math.min(earliest_mandatory, group.first) end
    end
    local tail_budget = threshold - base_tokens - limits.manifest.maximum_summary_tokens
    if tail_budget < 0 then tail_budget = 0 end
    local prefix_tokens, suffix_tokens = {}, {}
    local running = 0
    for index, group in ipairs(groups) do
        running = running + group.tokens
        prefix_tokens[index] = running
    end
    running = 0
    for index = #groups, 1, -1 do
        running = running + groups[index].tokens
        suffix_tokens[index] = running
    end
    local boundary, boundary_group_index
    local maximum_last = 0
    for index, group in ipairs(groups) do
        maximum_last = math.max(maximum_last, group.last)
        local next_group = groups[index + 1]
        local safe = not next_group or next_group.first > maximum_last
        if safe and maximum_last < #input.document.facts
            and maximum_last < earliest_mandatory
        then
            local tail_tokens = suffix_tokens[index + 1] or 0
            if tail_tokens <= tail_budget then
                boundary = maximum_last
                boundary_group_index = index
                break
            end
        end
    end
    if not boundary then
        return {
            decision = "waiting_user",
            reason = "no-complete-prefix-fits",
            error_code = "CompactionCapacityMismatch",
            current_estimated_tokens = current_estimated_tokens,
            threshold_tokens = threshold,
            window_tokens = window,
            recommendation_required = true,
        }
    end
    local source_parts = {}
    for index = 1, boundary do
        source_parts[#source_parts + 1] = encoded[index]
    end
    local source_tokens = prefix_tokens[boundary_group_index]
    local source_bytes = table.concat(source_parts)
    if #source_bytes + correction_byte_count > limits.manifest.maximum_input_bytes
        or source_tokens + input.prompt_tokens + correction_tokens
            + input.model_snapshot.maximum_output_tokens
            + limits.manifest.reserve_tokens > window
    then
        return {
            decision = "waiting_user",
            reason = "compaction-model-input-capacity",
            error_code = "CompactionInputTooLarge",
            source_first_seq = 1,
            source_last_seq = boundary,
            source_byte_count = #source_bytes,
            source_tokens = source_tokens,
            correction_byte_count = correction_byte_count,
            correction_tokens = correction_tokens,
            recommendation_required = true,
        }
    end
    local source_digest, digest_error = digest_bytes(ports, source_bytes)
    if not source_digest then return nil, digest_error end
    local tail_sequences, tail_tokens = {}, 0
    for _, group in ipairs(groups) do
        if group.first > boundary then
            tail_tokens = tail_tokens + group.tokens
            for _, sequence in ipairs(group.sequences) do
                tail_sequences[#tail_sequences + 1] = sequence
            end
        end
    end
    return {
        decision = "compact",
        mode = input.mode,
        expected_context_generation = input.expected_context_generation,
        expected_manifest_digest = input.expected_manifest_digest,
        context_digest = input.context_digest,
        model_snapshot = {
            id = input.model_snapshot.id,
            digest = input.model_snapshot.digest,
            window_tokens = input.model_snapshot.window_tokens,
            maximum_output_tokens = input.model_snapshot.maximum_output_tokens,
        },
        prompt_bundle_digest = input.prompt_bundle_digest,
        prompt_tokens = input.prompt_tokens,
        base_tokens = base_tokens,
        source_first_seq = 1,
        source_last_seq = boundary,
        source_digest = source_digest,
        source_bytes = source_bytes,
        source_tokens = source_tokens,
        correction_byte_count = correction_byte_count,
        correction_tokens = correction_tokens,
        tail_tokens = tail_tokens,
        tail_ranges = ranges_from_sequences(tail_sequences),
        threshold_tokens = threshold,
        window_tokens = window,
        current_estimated_tokens = current_estimated_tokens,
        event_count = #input.document.facts,
        corrections = corrections,
        groups = groups,
    }
end

local function public_plan(plan)
    local result = {}
    for key, value in pairs(plan) do
        if key ~= "source_bytes" and key ~= "model_snapshot" and key ~= "corrections" then
            result[key] = value
        end
    end
    if plan.source_bytes then result.source_byte_count = #plan.source_bytes end
    return assert(freeze(result, nil, "compaction plan"))
end

---Creates the structured prefix compaction and ModelView publication service.
function M.new(ports, options)
    local admitted_ports, ports_error = validate_ports(ports)
    if not admitted_ports then return nil, ports_error end
    local limits, options_error = validate_options(options)
    if not limits then return nil, options_error end

    local state = "Idle"
    local closed = false
    local active
    local last_result
    local serial = limits.initial_serial
    local request_serial = 0
    local correction_serial = 0
    local last_clock
    local service = {}

    local function clock_now()
        local called, value = pcall(admitted_ports.clock.now)
        if not called or not integer_at_least(value, 0)
            or (last_clock ~= nil and value < last_clock)
        then
            return nil, failure("CompactionClockFailure", "monotonic clock failed")
        end
        last_clock = value
        return value
    end

    local function commit(method, record, publishing)
        local binding = freeze(record, nil, "compaction journal binding")
        if not binding then
            return nil, failure("CompactionJournalFailure", "journal binding contains a cycle")
        end
        local called, committed, receipt = pcall(
            admitted_ports.journal[method],
            binding
        )
        if not called or committed ~= true or type(receipt) ~= "table"
            or receipt.binding ~= binding
            or not integer_at_least(
                receipt.previous_context_generation,
                record.expected_context_generation
            )
            or not integer_at_least(
                receipt.context_generation,
                receipt.previous_context_generation + 1
            )
            or (publishing and (
                receipt.previous_manifest_digest ~= record.expected_manifest_digest
                or receipt.published_manifest_digest ~= record.manifest.digest
            ))
            or (not publishing
                and receipt.active_manifest_digest ~= record.expected_manifest_digest)
        then
            state = "Unknown"
            active = nil
            return nil, failure(
                "CompactionJournalFailure",
                "compaction journal did not return an exact durable receipt",
                called and receipt or committed
            )
        end
        return receipt, binding
    end

    local function finish_waiting(reason, error_code)
        local completed = active
        active = nil
        state = "Idle"
        last_result = {
            outcome = "waiting_user",
            reason = reason,
            error_code = error_code,
            compaction_id = completed and completed.id or false,
        }
        return assert(freeze(last_result, nil, "compaction waiting outcome"))
    end

    local start_request
    local reject_attempt

    start_request = function(correction_reason)
        active.attempt = active.attempt + 1
        request_serial = request_serial + 1
        local request_id = active.id .. ":request:" .. tostring(request_serial)
        local intent = {
            kind = "compaction-request",
            purpose = "compaction",
            mode = active.plan.mode,
            compaction_id = active.id,
            request_id = request_id,
            attempt = active.attempt,
            correction_reason = correction_reason or false,
            expected_context_generation = active.context_generation,
            expected_manifest_digest = active.plan.expected_manifest_digest,
            source_first_seq = active.plan.source_first_seq,
            source_last_seq = active.plan.source_last_seq,
            source_digest = active.plan.source_digest,
            model_snapshot_digest = active.plan.model_snapshot.digest,
            manifest_snapshot_id = limits.manifest.snapshot_id,
        }
        local receipt, commit_error = commit("commit_intent", intent, false)
        if not receipt then return nil, commit_error end
        active.context_generation = receipt.context_generation
        active.request_id = request_id
        active.request_ids[request_id] = true
        active.response_committed = false
        local specification = freeze({
            request_id = request_id,
            compaction_id = active.id,
            purpose = "compaction",
            attempt = active.attempt,
            no_tools = true,
            model_snapshot = active.plan.model_snapshot,
            prompt_bundle_digest = active.plan.prompt_bundle_digest,
            source_first_seq = active.plan.source_first_seq,
            source_last_seq = active.plan.source_last_seq,
            source_digest = active.plan.source_digest,
            source_bytes = active.plan.source_bytes,
            summary_schema = limits.manifest.summary_schema,
            summary_slots = SUMMARY_SLOTS,
            corrections = active.plan.corrections,
            correction_reason = correction_reason or false,
            maximum_summary_bytes = limits.manifest.maximum_summary_bytes,
        }, nil, "compaction Model request")
        state = "Compacting"
        local called, handle, start_error = pcall(admitted_ports.model.start, specification)
        if not called or handle == nil or handle == false then
            active.handle = false
            return reject_attempt(
                "CompactionStartFailure",
                called and start_error or handle,
                false
            )
        end
        active.handle = handle
        return assert(freeze({
            state = state,
            compaction_id = active.id,
            request_id = request_id,
            attempt = active.attempt,
            status_visible = true,
            cancellable = true,
        }, nil, "compaction request admission"))
    end

    reject_attempt = function(error_code, detail, response_facts)
        local rejection = {
            kind = "compaction-rejection",
            compaction_id = active.id,
            request_id = active.request_id,
            attempt = active.attempt,
            error_code = error_code,
            detail = tostring(detail or ""),
            response_digest = response_facts and response_facts.canonical_digest or false,
            response_body = response_facts and response_facts.canonical_body or false,
            expected_context_generation = active.context_generation,
            expected_manifest_digest = active.plan.expected_manifest_digest,
            old_view_retained = true,
        }
        local receipt, commit_error = commit("commit_rejection", rejection, false)
        if not receipt then return nil, commit_error end
        active.context_generation = receipt.context_generation
        active.handle = false
        if active.attempt < limits.manifest.maximum_attempts then
            return start_request(error_code)
        end
        return finish_waiting("compaction-rejected", error_code)
    end

    local function validate_response(wrapper)
        if not exact_fields(wrapper, {
            request_id = true, canonical_body = true, canonical_digest = true,
            source_first_seq = true, source_last_seq = true, source_digest = true,
            generator_model_snapshot = true, summary = true, usage = true,
        })
            or wrapper.request_id ~= active.request_id
            or not valid_text(
                wrapper.canonical_body,
                limits.manifest.maximum_summary_bytes,
                false
            )
            or not valid_text(wrapper.canonical_digest, 512, false)
            or wrapper.source_first_seq ~= active.plan.source_first_seq
            or wrapper.source_last_seq ~= active.plan.source_last_seq
            or wrapper.source_digest ~= active.plan.source_digest
            or wrapper.generator_model_snapshot ~= active.plan.model_snapshot.digest
            or not exact_fields(wrapper.summary, {
                schema_version = true, source_first_seq = true,
                source_last_seq = true, source_digest = true,
                goals_decisions = true, constraints_permissions = true,
                files_touched = true, verification_evidence = true,
                unknown_side_effects = true, open_todos = true,
                prompt_model_transitions = true,
            })
            or not exact_fields(wrapper.usage, {
                input_tokens = true, output_tokens = true, estimated = true,
            })
            or not integer_at_least(wrapper.usage.input_tokens, 0)
            or not integer_at_least(wrapper.usage.output_tokens, 0)
            or wrapper.usage.input_tokens > active.plan.model_snapshot.window_tokens
            or wrapper.usage.output_tokens
                > active.plan.model_snapshot.maximum_output_tokens
            or type(wrapper.usage.estimated) ~= "boolean"
        then
            return nil, failure("InvalidCompactionResponse", "compaction response is invalid")
        end
        local summary = wrapper.summary
        if summary.schema_version ~= limits.manifest.summary_schema
            or summary.source_first_seq ~= active.plan.source_first_seq
            or summary.source_last_seq ~= active.plan.source_last_seq
            or summary.source_digest ~= active.plan.source_digest
        then
            return nil, failure("InvalidCompactionResponse", "summary source binding is invalid")
        end
        for _, name in ipairs(SUMMARY_SLOTS) do
            if not valid_text(summary[name], limits.manifest.maximum_summary_bytes, false) then
                return nil, failure("InvalidCompactionResponse", "summary slot is invalid", name)
            end
        end
        if encode_summary(summary) ~= wrapper.canonical_body then
            return nil, failure("InvalidCompactionResponse", "summary canonical bytes disagree")
        end
        local digest, digest_error = digest_bytes(admitted_ports, wrapper.canonical_body)
        if not digest then return nil, digest_error end
        if digest ~= wrapper.canonical_digest then
            return nil, failure("InvalidCompactionResponse", "summary digest disagrees")
        end
        return summary
    end

    function service:plan(input)
        local plan, plan_error = plan_internal(input, admitted_ports, limits)
        if not plan then return nil, plan_error end
        return public_plan(plan)
    end

    function service:begin(input)
        if closed then
            return nil, failure("CompactionClosed", "compaction service is closed")
        end
        if state ~= "Idle" then
            return nil, failure(
                type(input) == "table" and input.mode == "manual"
                    and "ManualCompactionBusy" or "CompactionBusy",
                "one compaction lifecycle is already active"
            )
        end
        local plan, plan_error = plan_internal(input, admitted_ports, limits)
        if not plan then return nil, plan_error end
        if plan.decision ~= "compact" then
            last_result = plan
            return public_plan(plan)
        end
        local now, clock_error = clock_now()
        if not now then return nil, clock_error end
        serial = serial + 1
        active = {
            id = "compaction-" .. tostring(serial),
            plan = plan,
            context_generation = plan.expected_context_generation,
            attempt = 0,
            started_at = now,
            handle = false,
            request_ids = {},
        }
        return start_request(false)
    end

    function service:accept_response(wrapper)
        if state ~= "Compacting" or not active then
            return nil, failure("NoCompactionRequest", "no compaction response is pending")
        end
        local now, clock_error = clock_now()
        if not now then return nil, clock_error end
        if now - active.started_at >= limits.manifest.active_time_ms then
            return self:cancel("compaction-active-time")
        end
        if type(wrapper) == "table"
            and valid_text(wrapper.request_id, limits.maximum_identifier_bytes, false)
            and wrapper.request_id ~= active.request_id
            and active.request_ids[wrapper.request_id]
        then
            return nil, failure(
                "StaleCompactionResponse",
                "response belongs to an earlier compaction attempt"
            )
        end
        local summary, response_error = validate_response(wrapper)
        if not summary then
            local safe_facts = type(wrapper) == "table" and {
                canonical_body = valid_text(
                    wrapper.canonical_body,
                    limits.manifest.maximum_summary_bytes,
                    true
                ) and wrapper.canonical_body or "",
                canonical_digest = valid_text(wrapper.canonical_digest, 512, true)
                    and wrapper.canonical_digest or "",
            } or false
            return reject_attempt(response_error.code, response_error.detail, safe_facts)
        end
        active.handle = false
        local response_record = {
            kind = "compaction-response",
            compaction_id = active.id,
            request_id = active.request_id,
            attempt = active.attempt,
            canonical_body = wrapper.canonical_body,
            canonical_digest = wrapper.canonical_digest,
            source_first_seq = active.plan.source_first_seq,
            source_last_seq = active.plan.source_last_seq,
            source_digest = active.plan.source_digest,
            usage = wrapper.usage,
            expected_context_generation = active.context_generation,
            expected_manifest_digest = active.plan.expected_manifest_digest,
        }
        local receipt, commit_error = commit("commit_response", response_record, false)
        if not receipt then return nil, commit_error end
        active.context_generation = receipt.context_generation
        active.response_committed = true
        local summary_tokens, estimate_error = estimate_bytes(
            admitted_ports,
            wrapper.canonical_body,
            active.plan.model_snapshot
        )
        if summary_tokens == nil then
            return reject_attempt(estimate_error.code, estimate_error.detail, wrapper)
        end
        local projected = active.plan.base_tokens + active.plan.tail_tokens + summary_tokens
        local benefit = active.plan.current_estimated_tokens - projected
        if summary_tokens > limits.manifest.maximum_summary_tokens
            or projected >= active.plan.threshold_tokens
            or projected > active.plan.window_tokens
            or benefit < limits.manifest.minimum_benefit_tokens
        then
            return reject_attempt("CompactionNoBenefit", {
                summary_tokens = summary_tokens,
                projected_tokens = projected,
                benefit_tokens = benefit,
            }, wrapper)
        end

        local summary_id = active.id .. ":summary"
        local correction_ids = {}
        for index, correction in ipairs(active.plan.corrections) do
            correction_ids[index] = correction.correction_id
        end
        local manifest = {
            schema_version = 1,
            context_generation = active.context_generation,
            context_digest = active.plan.context_digest,
            model_id = active.plan.model_snapshot.id,
            model_snapshot_digest = active.plan.model_snapshot.digest,
            window_tokens = active.plan.window_tokens,
            prompt_bundle_digest = active.plan.prompt_bundle_digest,
            summary_id = summary_id,
            summary_source_range = tostring(active.plan.source_first_seq)
                .. "-" .. tostring(active.plan.source_last_seq),
            included_event_ranges = active.plan.tail_ranges,
            excluded_prefix_reason = "summarized",
            builder_algorithm = limits.manifest.builder_algorithm,
            estimated_tokens = projected,
            correction_ids = correction_ids,
        }
        local manifest_bytes = canonical_manifest(manifest)
        if #manifest_bytes > limits.manifest.maximum_input_bytes then
            return reject_attempt(
                "CompactionManifestLimit",
                "candidate ModelView manifest exceeds its byte cap",
                wrapper
            )
        end
        local manifest_digest, manifest_error = digest_bytes(admitted_ports, manifest_bytes)
        if not manifest_digest then
            return reject_attempt(manifest_error.code, manifest_error.detail, wrapper)
        end
        manifest.digest = manifest_digest
        manifest.canonical_bytes = manifest_bytes
        local publication = {
            kind = "compaction-publication",
            compaction_id = active.id,
            summary_id = summary_id,
            request_id = active.request_id,
            expected_context_generation = active.context_generation,
            expected_manifest_digest = active.plan.expected_manifest_digest,
            canonical_facts_before = active.plan.event_count,
            canonical_facts_removed = 0,
            source_first_seq = active.plan.source_first_seq,
            source_last_seq = active.plan.source_last_seq,
            source_digest = active.plan.source_digest,
            summary = wrapper.canonical_body,
            summary_digest = wrapper.canonical_digest,
            summary_schema = limits.manifest.summary_schema,
            generator_model_snapshot = active.plan.model_snapshot.digest,
            usage = wrapper.usage,
            correction_ids = correction_ids,
            manifest = manifest,
            old_view_retained_until_publish = true,
            atomic_groups_split = 0,
        }
        state = "Publishing"
        local published, publish_error = commit("publish", publication, true)
        if not published then return nil, publish_error end
        local completed = active
        active = nil
        state = "Idle"
        last_result = {
            outcome = "completed",
            compaction_id = completed.id,
            summary_id = summary_id,
            manifest_digest = manifest_digest,
            context_generation = published.context_generation,
            estimated_tokens = projected,
            benefit_tokens = benefit,
            canonical_facts_removed = 0,
            atomic_groups_split = 0,
            status_visible = true,
        }
        return assert(freeze(last_result, nil, "compaction outcome"))
    end

    local function finish_cancel(outcome)
        local terminal = {
            kind = "compaction-cancel-result",
            compaction_id = active.id,
            request_id = active.request_id,
            reason = active.cancel_reason,
            outcome = outcome,
            expected_context_generation = active.context_generation,
            expected_manifest_digest = active.plan.expected_manifest_digest,
            old_view_retained = true,
        }
        local receipt, commit_error = commit("commit_rejection", terminal, false)
        if not receipt then return nil, commit_error end
        local completed = active
        active = nil
        state = outcome == "unknown" and "Unknown" or "Idle"
        last_result = {
            outcome = outcome,
            compaction_id = completed.id,
            context_generation = receipt.context_generation,
            old_view_retained = true,
        }
        return assert(freeze(last_result, nil, "compaction cancellation"))
    end

    function service:cancel(reason)
        if state ~= "Compacting" or not active then
            return nil, failure("NoCompactionRequest", "no compaction request can be cancelled")
        end
        if not valid_text(reason, limits.manifest.maximum_summary_bytes, false) then
            return nil, failure("InvalidCompactionCancel", "compaction cancel reason is invalid")
        end
        local record = {
            kind = "compaction-cancel-request",
            compaction_id = active.id,
            request_id = active.request_id,
            reason = reason,
            expected_context_generation = active.context_generation,
            expected_manifest_digest = active.plan.expected_manifest_digest,
            old_view_retained = true,
        }
        local receipt, commit_error = commit("commit_rejection", record, false)
        if not receipt then
            pcall(admitted_ports.model.cancel, active.handle, reason)
            return nil, commit_error
        end
        active.context_generation = receipt.context_generation
        active.cancel_reason = reason
        local called, result = pcall(admitted_ports.model.cancel, active.handle, reason)
        if not called or type(result) ~= "table"
            or (result.outcome ~= "cancelled"
                and result.outcome ~= "pending"
                and result.outcome ~= "unknown")
        then
            result = { outcome = "unknown" }
        end
        if result.outcome == "pending" then
            state = "Cancelling"
            return assert(freeze({
                state = state,
                compaction_id = active.id,
                request_id = active.request_id,
                cancel_pending = true,
            }, nil, "pending compaction cancellation"))
        end
        return finish_cancel(result.outcome)
    end

    function service:settle_cancel(settlement)
        if state ~= "Cancelling" or not active then
            return nil, failure("NoCompactionCancel", "no compaction cancellation is pending")
        end
        if not exact_fields(settlement, { request_id = true, outcome = true })
            or settlement.request_id ~= active.request_id
            or (settlement.outcome ~= "cancelled" and settlement.outcome ~= "unknown")
        then
            return nil, failure("InvalidCompactionCancel", "cancel settlement is invalid")
        end
        return finish_cancel(settlement.outcome)
    end

    function service:tick()
        local now, clock_error = clock_now()
        if not now then return nil, clock_error end
        if state == "Compacting" and active
            and now - active.started_at >= limits.manifest.active_time_ms
        then
            return self:cancel("compaction-active-time")
        end
        if state == "Cancelling" and active
            and now - active.started_at >= limits.manifest.active_time_ms
        then
            return finish_cancel("unknown")
        end
        return assert(freeze({ state = state, now = now }, nil, "compaction tick"))
    end

    function service:show_summary(document, compaction_id)
        if not valid_id(compaction_id, limits.maximum_identifier_bytes)
            or type(document) ~= "table" or type(document.model_view) ~= "table"
            or dense_count(document.model_view.compaction_records) == nil
        then
            return nil, failure("InvalidSummaryLookup", "summary lookup is invalid")
        end
        local record
        for _, candidate in ipairs(document.model_view.compaction_records) do
            if candidate.id == compaction_id then record = candidate; break end
        end
        if not record then
            return nil, failure("SummaryMissing", "compaction summary is unavailable")
        end
        if record.status ~= "ok" or not record.summary then
            return nil, failure("SummaryUnavailable", "compaction record has no accepted summary")
        end
        local summary, summary_error = decode_summary(
            record.summary,
            limits.manifest.maximum_summary_bytes
        )
        if not summary then return nil, summary_error end
        if summary.schema_version ~= limits.manifest.summary_schema then
            return nil, failure(
                "SummarySchemaMismatch",
                "compaction summary schema is not supported"
            )
        end
        if summary.source_first_seq ~= record.source_first_seq
            or summary.source_last_seq ~= record.source_last_seq
            or summary.source_digest ~= record.source_digest
        then
            return nil, failure("SummaryBindingMismatch", "summary record source binding disagrees")
        end
        return assert(freeze({
            compaction_id = compaction_id,
            source_first_seq = record.source_first_seq,
            source_last_seq = record.source_last_seq,
            source_digest = record.source_digest,
            summary = summary,
        }, nil, "structured summary"))
    end

    function service:correct_summary(command)
        if closed then
            return nil, failure("CompactionClosed", "compaction service is closed")
        end
        if state ~= "Idle" then
            return nil, failure("SummaryCorrectionBusy", "summary correction requires idle")
        end
        local document = type(command) == "table" and command.document or nil
        local model_view = type(document) == "table" and document.model_view or nil
        local active_manifest = type(model_view) == "table"
            and model_view.active_manifest or nil
        if not exact_fields(command, {
            document = true, compaction_id = true, text = true,
            expected_context_generation = true, expected_manifest_digest = true,
        })
            or type(document) ~= "table"
            or type(active_manifest) ~= "table"
            or document.generation ~= command.expected_context_generation
            or active_manifest.digest ~= command.expected_manifest_digest
            or not valid_id(command.compaction_id, limits.maximum_identifier_bytes)
            or not valid_text(command.text, limits.manifest.maximum_summary_bytes, false)
        then
            return nil, failure("InvalidSummaryCorrection", "summary correction is invalid")
        end
        local shown, show_error = self:show_summary(command.document, command.compaction_id)
        if not shown then return nil, show_error end
        correction_serial = correction_serial + 1
        local correction_id = "summary-correction-"
            .. tostring(command.expected_context_generation)
            .. "-" .. tostring(correction_serial)
        local correction_digest, digest_error = digest_bytes(admitted_ports, command.text)
        if not correction_digest then return nil, digest_error end
        local record = {
            kind = "summary-correction",
            correction_id = correction_id,
            compaction_id = command.compaction_id,
            source_first_seq = shown.source_first_seq,
            source_last_seq = shown.source_last_seq,
            source_digest = shown.source_digest,
            text = command.text,
            correction_digest = correction_digest,
            effective_at = "next-model-view-publication",
            expected_context_generation = command.expected_context_generation,
            expected_manifest_digest = command.expected_manifest_digest,
        }
        local receipt, commit_error = commit("commit_correction", record, false)
        if not receipt then return nil, commit_error end
        return assert(freeze({
            correction_id = correction_id,
            compaction_id = command.compaction_id,
            context_generation = receipt.context_generation,
            effective_at = "next-model-view-publication",
        }, nil, "summary correction"))
    end

    function service:close(reason)
        if closed then
            return assert(freeze({
                closed = true,
                state = state,
                cancel_pending = state == "Cancelling",
            }, nil, "compaction close outcome"))
        end
        local close_reason = reason or "compaction-service-close"
        if state == "Compacting" and active
            and not valid_text(
                close_reason,
                limits.manifest.maximum_summary_bytes,
                false
            )
        then
            return nil, failure("InvalidCompactionCancel", "close reason is invalid")
        end
        closed = true
        if state == "Compacting" and active then
            return self:cancel(close_reason)
        end
        return assert(freeze({
            closed = true,
            state = state,
            cancel_pending = state == "Cancelling",
        }, nil, "compaction close outcome"))
    end

    function service:status()
        return assert(freeze({
            state = state,
            closed = closed,
            active_compaction_id = active and active.id or false,
            active_request_id = active and active.request_id or false,
            attempt = active and active.attempt or 0,
            last_result = last_result or false,
            manifest_snapshot_id = limits.manifest.snapshot_id,
            builder_algorithm = limits.manifest.builder_algorithm,
            summary_schema = limits.manifest.summary_schema,
            maximum_attempts = limits.manifest.maximum_attempts,
            canonical_facts_mutable = false,
            automatic_consent_required = false,
            manual_requires_idle = true,
        }, nil, "compaction status"))
    end

    service.summary_schema = assert(freeze({
        version = limits.manifest.summary_schema,
        slots = SUMMARY_SLOTS,
        canonical_encoding = "tagged-length-v1",
    }, nil, "structured summary schema"))
    return readonly(service, "compaction service")
end

M.encode_summary = encode_summary

return M
