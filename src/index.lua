--[[
File: index.lua
Date: 2026-08-29
Author: WaterRun
Description: Resolves Context selectors over bounded real-time catalog rings.
]]

local M = {}

local PATH_METHODS = {
    "validate_logical",
    "validate_context_name",
    "classify_selector",
    "context_file",
    "compare_logical",
    "context_hash",
}

local SCANNER_METHODS = { "begin", "next_ring", "close" }

local HEADER_STATES = {
    valid = true,
    corrupt = true,
    unavailable = true,
    changed = true,
}

local CANDIDATE_FIELDS = {
    physical_path = true,
    logical_path = true,
    display_path = true,
    display_name = true,
    canonical_name = true,
    created_at = true,
    updated_at = true,
    scope_rank = true,
    hash16 = true,
    observed_stat = true,
    header_state = true,
}

local RING_FIELDS = {
    scope = true,
    rank = true,
    complete = true,
    reason = true,
    candidates = true,
}

local function failure(code, message, reason)
    local result = { code = code, message = message }
    if reason ~= nil then result.reason = reason end
    return result
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
        __len = function()
            return #values
        end,
        __metatable = "locked",
    })
end

local function freeze(value, visiting, label)
    if type(value) ~= "table" then return value end
    visiting = visiting or {}
    if visiting[value] then return nil end
    visiting[value] = true
    local copy = {}
    for key, item in pairs(value) do
        local frozen = freeze(item, visiting, label)
        if frozen == nil and type(item) == "table" then
            visiting[value] = nil
            return nil
        end
        copy[key] = frozen
    end
    visiting[value] = nil
    return readonly(copy, label)
end

local function valid_integer(value, minimum)
    return math.type(value) == "integer" and value >= minimum
end

local function validate_options(options)
    if type(options) ~= "table" then
        return nil, failure("InvalidIndexOptions", "Context index hard limits are required")
    end
    local allowed = {
        maximum_scan_candidates = true,
        maximum_search_rings = true,
        maximum_collision_candidates = true,
        maximum_reason_bytes = true,
    }
    local limits = {}
    for name in pairs(allowed) do
        if not valid_integer(options[name], 1) then
            return nil, failure("InvalidIndexOptions", name .. " must be a positive integer")
        end
        limits[name] = options[name]
    end
    for key in pairs(options) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure(
                "InvalidIndexOptions",
                "Context index options have an unknown field"
            )
        end
    end
    if limits.maximum_collision_candidates < 2
        or limits.maximum_collision_candidates > limits.maximum_scan_candidates
    then
        return nil, failure(
            "InvalidIndexOptions",
            "collision limit must be between two and the scan candidate limit"
        )
    end
    return limits
end

local function snapshot_methods(value, names, code, label)
    if type(value) ~= "table" then
        return nil, failure(code, label .. " is required")
    end
    local snapshot = {}
    for _, name in ipairs(names) do
        if type(value[name]) ~= "function" then
            return nil, failure(code, label .. " omits " .. name)
        end
        snapshot[name] = value[name]
    end
    return snapshot
end

local function validate_ports(ports)
    if type(ports) ~= "table" then
        return nil, failure("InvalidIndexPorts", "Context index ports are required")
    end
    local allowed = { path = true, scanner = true }
    for key in pairs(ports) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure("InvalidIndexPorts", "Context index ports have an unknown field")
        end
    end
    local path, path_error = snapshot_methods(
        ports.path,
        PATH_METHODS,
        "InvalidPathPort",
        "LogicalPath service"
    )
    if not path then return nil, path_error end
    local scanner, scanner_error = snapshot_methods(
        ports.scanner,
        SCANNER_METHODS,
        "InvalidScannerPort",
        "Context catalog scanner"
    )
    if not scanner then return nil, scanner_error end
    return { path = path, scanner = scanner }
end

local function safe_reason(value, limits, fallback)
    if type(value) == "table" then value = value.reason or value.code end
    if type(value) ~= "string"
        or value == ""
        or #value > limits.maximum_reason_bytes
        or value:match("^[A-Za-z][A-Za-z0-9_-]*$") == nil
    then
        return fallback
    end
    return value
end

local function invoke(scanner, method, ...)
    local called, ok, value = pcall(scanner[method], ...)
    if not called then return false, "scanner-exception" end
    if ok == true then return true, value end
    if ok == false then return false, value end
    return false, "scanner-contract"
end

local function result(value)
    return assert(freeze(value, nil, "Context resolver result"))
end

local function invalid_selector(reason)
    return result({ tag = "InvalidSelector", reason = reason })
end

local function scan_incomplete(scope, reason)
    return result({ tag = "ScanIncomplete", scope = scope, reason = reason })
end

local function matched_unavailable(candidate)
    return result({
        tag = "MatchedUnavailable",
        logical_path = candidate.logical_path,
        reason = "header-" .. candidate.header_state,
    })
end

local function not_found()
    return result({ tag = "NotFound" })
end

local function valid_array(values)
    if type(values) ~= "table" then return false end
    local count = 0
    for key in pairs(values) do
        if not valid_integer(key, 1) then return false end
        if key > count then count = key end
    end
    if count ~= #values then return false end
    for index = 1, count do
        if values[index] == nil then return false end
    end
    return true
end

local function valid_text(value, allow_empty)
    return type(value) == "string"
        and (allow_empty or value ~= "")
        and value:find("\0", 1, true) == nil
end

local function validate_candidate(candidate, rank, path)
    if type(candidate) ~= "table" then return nil, "candidate-contract" end
    for key in pairs(candidate) do
        if type(key) ~= "string" or not CANDIDATE_FIELDS[key] then
            return nil, "candidate-contract"
        end
    end
    if not valid_text(candidate.physical_path, false)
        or (candidate.display_path ~= nil and not valid_text(candidate.display_path, false))
        or type(candidate.header_state) ~= "string"
        or not HEADER_STATES[candidate.header_state]
    then
        return nil, "candidate-contract"
    end
    local details = path.context_file(candidate.logical_path)
    if not details then return nil, "candidate-path" end
    if candidate.display_name ~= nil and candidate.display_name ~= details.display_name then
        return nil, "candidate-name"
    end
    if candidate.scope_rank ~= nil
        and (not valid_integer(candidate.scope_rank, 0) or candidate.scope_rank ~= rank)
    then
        return nil, "candidate-rank"
    end
    if candidate.hash16 ~= nil
        and (type(candidate.hash16) ~= "string"
            or candidate.hash16:match("^[0-9A-F][0-9A-F]+$") == nil
            or #candidate.hash16 ~= 16)
    then
        return nil, "candidate-hash"
    end
    if candidate.canonical_name ~= nil and not valid_text(candidate.canonical_name, false) then
        return nil, "candidate-header"
    end
    if candidate.created_at ~= nil and not valid_text(candidate.created_at, false) then
        return nil, "candidate-header"
    end
    if candidate.updated_at ~= nil and not valid_text(candidate.updated_at, false) then
        return nil, "candidate-header"
    end
    if candidate.observed_stat ~= nil and type(candidate.observed_stat) ~= "table" then
        return nil, "candidate-observation"
    end
    if candidate.header_state == "valid" then
        if candidate.canonical_name ~= details.display_name
            or not valid_text(candidate.created_at, false)
            or not valid_text(candidate.updated_at, false)
            or type(candidate.observed_stat) ~= "table"
        then
            return nil, "candidate-header"
        end
    end
    return {
        physical_path = candidate.physical_path,
        logical_path = candidate.logical_path,
        display_path = candidate.display_path or candidate.physical_path,
        display_name = details.display_name,
        canonical_name = candidate.canonical_name,
        created_at = candidate.created_at,
        updated_at = candidate.updated_at,
        observed_stat = candidate.observed_stat,
        header_state = candidate.header_state,
        scope_rank = rank,
    }
end

local function validate_ring(ring, expected_rank, path, limits)
    if type(ring) ~= "table" then return nil, nil, "ring-contract" end
    for key in pairs(ring) do
        if type(key) ~= "string" or not RING_FIELDS[key] then
            return nil, nil, "ring-contract"
        end
    end
    local scope = path.validate_logical(ring.scope)
    if not scope
        or type(ring.complete) ~= "boolean"
        or not valid_array(ring.candidates)
        or (ring.rank ~= nil and ring.rank ~= expected_rank)
    then
        return nil, nil, "ring-contract"
    end
    if #ring.candidates > limits.maximum_scan_candidates then
        return nil, scope, "scan-limit"
    end
    if not ring.complete then
        return nil, scope, safe_reason(ring.reason, limits, "scope-unavailable")
    end
    if ring.reason ~= nil then return nil, scope, "ring-contract" end
    local candidates = {}
    for index, candidate in ipairs(ring.candidates) do
        local admitted, candidate_error = validate_candidate(candidate, expected_rank, path)
        if not admitted then return nil, scope, candidate_error end
        candidates[index] = admitted
    end
    local compare_failed = false
    local sorted = pcall(table.sort, candidates, function(left, right)
        local order = path.compare_logical(left.logical_path, right.logical_path)
        if type(order) ~= "number" then
            compare_failed = true
            return false
        end
        return order < 0
    end)
    if not sorted or compare_failed then return nil, scope, "candidate-order" end
    return candidates, scope
end

local function hash_candidate(candidate, path)
    local hash = path.context_hash(candidate.logical_path)
    if type(hash) ~= "string"
        or #hash ~= 16
        or hash:match("^[0-9A-F][0-9A-F]+$") == nil
    then
        return nil
    end
    return hash
end

local function unique(candidate, hash)
    local value = {
        tag = "Unique",
        logical_path = candidate.logical_path,
        display_path = candidate.display_path,
        hash = hash,
    }
    if candidate.physical_path ~= candidate.display_path then
        value.physical_hint = candidate.physical_path
    end
    return result(value)
end

local function decide_name(candidates, selector, path, scope)
    for _, candidate in ipairs(candidates) do
        if candidate.display_name == selector or candidate.canonical_name == selector then
            if candidate.header_state ~= "valid" then
                return matched_unavailable(candidate)
            end
            local hash = hash_candidate(candidate, path)
            if not hash then return scan_incomplete(scope, "context-hash") end
            return unique(candidate, hash)
        end
    end
    return nil
end

local function decide_hash(candidates, selector, path, scope, limits)
    local usable, unavailable = {}, {}
    for _, candidate in ipairs(candidates) do
        local hash = hash_candidate(candidate, path)
        if not hash then return scan_incomplete(scope, "context-hash") end
        if hash == selector then
            if candidate.header_state == "valid" then
                usable[#usable + 1] = { candidate = candidate, hash = hash }
            else
                unavailable[#unavailable + 1] = candidate
            end
        end
    end
    if #usable > 1 then
        local collisions = {}
        local count = math.min(#usable, limits.maximum_collision_candidates)
        for index = 1, count do
            collisions[index] = {
                logical_path = usable[index].candidate.logical_path,
                hash = usable[index].hash,
            }
        end
        return result({ tag = "HashCollision", candidates = collisions })
    end
    if #usable == 1 then return unique(usable[1].candidate, usable[1].hash) end
    if #unavailable > 0 then return matched_unavailable(unavailable[1]) end
    return nil
end

---Creates the deterministic Context resolver around an ephemeral ring scanner.
-- The scanner is a narrow platform adapter. Each resolve call opens a fresh
-- scan, then `next_ring` returns one complete bounded ring at a time or nil at
-- end-of-catalog. No candidate or outcome is cached between calls.
-- @param ports table Contains path and scanner services.
-- @param options table Mandatory release hard limits.
-- @return table|nil service Immutable resolver service.
-- @return table|nil err Structured dependency or limit failure.
function M.new(ports, options)
    local admitted, ports_error = validate_ports(ports)
    if not admitted then return nil, ports_error end
    local limits, limits_error = validate_options(options)
    if not limits then return nil, limits_error end
    local path, scanner = admitted.path, admitted.scanner
    local service = {}

    ---Resolves one exact Context name or canonical 16-hex path hash.
    -- @param selector string Exact display name or hash token.
    -- @param origin_logical string Current workspace mirror directory.
    -- @return table ResolveResult immutable discriminated union.
    function service.resolve(selector, origin_logical)
        local classified, selector_error = path.classify_selector(selector)
        if not classified then
            return invalid_selector(safe_reason(selector_error, limits, "invalid-token"))
        end
        if classified.kind == "name" then
            local name, name_error = path.validate_context_name(classified.canonical)
            if not name then
                return invalid_selector(safe_reason(name_error, limits, "unsafe-name"))
            end
        end
        local origin = path.validate_logical(origin_logical)
        if not origin then return scan_incomplete("/", "invalid-origin") end

        local began, handle_or_error = invoke(scanner, "begin", origin, {
            maximum_scan_candidates = limits.maximum_scan_candidates,
            maximum_search_rings = limits.maximum_search_rings,
        })
        if not began then
            return scan_incomplete(
                origin,
                safe_reason(handle_or_error, limits, "scanner-begin")
            )
        end
        if handle_or_error == nil then
            return scan_incomplete(origin, "scanner-begin-contract")
        end
        local handle = handle_or_error
        local closed = false
        local function finish(outcome)
            if closed then return outcome end
            closed = true
            local close_ok, close_error = invoke(scanner, "close", handle)
            if not close_ok and outcome.tag ~= "ScanIncomplete" then
                return scan_incomplete(
                    origin,
                    safe_reason(close_error, limits, "scanner-close")
                )
            end
            return outcome
        end

        local seen_paths = {}
        local candidate_count = 0
        for ring_number = 1, limits.maximum_search_rings do
            local next_ok, ring_or_error = invoke(scanner, "next_ring", handle)
            if not next_ok then
                return finish(scan_incomplete(
                    origin,
                    safe_reason(ring_or_error, limits, "scanner-next")
                ))
            end
            if ring_or_error == nil then return finish(not_found()) end
            local rank = ring_number - 1
            local candidates, scope, ring_error = validate_ring(
                ring_or_error,
                rank,
                path,
                limits
            )
            if not candidates then
                return finish(scan_incomplete(scope or origin, ring_error))
            end
            if candidate_count + #candidates > limits.maximum_scan_candidates then
                return finish(scan_incomplete(scope, "scan-limit"))
            end
            candidate_count = candidate_count + #candidates
            for _, candidate in ipairs(candidates) do
                if seen_paths[candidate.logical_path] then
                    return finish(scan_incomplete(scope, "duplicate-candidate"))
                end
                seen_paths[candidate.logical_path] = true
            end

            local outcome
            if classified.kind == "hash" then
                outcome = decide_hash(candidates, classified.canonical, path, scope, limits)
            else
                outcome = decide_name(candidates, classified.canonical, path, scope)
            end
            if outcome then return finish(outcome) end
        end
        return finish(scan_incomplete(origin, "ring-limit"))
    end

    ---Computes `.status` hash from the current handle path without scanning.
    -- @param logical_path string Current Context LogicalPath.
    -- @return string|nil hash Canonical 16-uppercase-hex address.
    -- @return table|nil err Structured path/hash failure.
    function service.current_hash(logical_path)
        local details, path_error = path.context_file(logical_path)
        if not details then return nil, path_error end
        return path.context_hash(details.logical_path)
    end

    service.limits = readonly({
        maximum_scan_candidates = limits.maximum_scan_candidates,
        maximum_search_rings = limits.maximum_search_rings,
        maximum_collision_candidates = limits.maximum_collision_candidates,
        maximum_reason_bytes = limits.maximum_reason_bytes,
    }, "Context index limits")
    service.capabilities = readonly({
        persistent_index = false,
        real_time_scan = true,
        incremental_rings = true,
        stable_logical_order = true,
        target_qualified = false,
    }, "Context index capabilities")

    return readonly(service, "Context index service")
end

return M
