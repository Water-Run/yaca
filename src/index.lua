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
local VERIFIER_METHODS = { "observe" }

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
    local allowed = { path = true, scanner = true, verifier = true }
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
    local verifier
    if ports.verifier ~= nil then
        verifier, scanner_error = snapshot_methods(
            ports.verifier,
            VERIFIER_METHODS,
            "InvalidVerifierPort",
            "Context target verifier"
        )
        if not verifier then return nil, scanner_error end
    end
    return { path = path, scanner = scanner, verifier = verifier }
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

local function deep_equal(left, right, visited)
    if left == right then return true end
    if type(left) ~= type(right) or type(left) ~= "table" then return false end
    visited = visited or {}
    visited[left] = visited[left] or {}
    if visited[left][right] then return true end
    visited[left][right] = true
    for key, value in pairs(left) do
        if not deep_equal(value, right[key], visited) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
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
    local admitted = {
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
    local frozen = freeze(admitted, nil, "Context catalog candidate")
    if not frozen then return nil, "candidate-observation" end
    return frozen
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

local function selected_result(candidate, hash, tag, selections)
    local value = {
        tag = tag,
        logical_path = candidate.logical_path,
        display_path = candidate.display_path,
        hash = hash,
    }
    if candidate.physical_path ~= candidate.display_path then
        value.physical_hint = candidate.physical_path
    end
    if tag == "TargetSnapshot" then value.header_state = candidate.header_state end
    local exposed = result(value)
    selections[exposed] = assert(freeze(candidate, nil, "Context target snapshot"))
    return exposed
end

local function unique(candidate, hash, selections)
    return selected_result(candidate, hash, "Unique", selections)
end

local function decide_name(candidates, selector, path, scope, selections)
    for _, candidate in ipairs(candidates) do
        if candidate.display_name == selector or candidate.canonical_name == selector then
            if candidate.header_state ~= "valid" then
                return matched_unavailable(candidate)
            end
            local hash = hash_candidate(candidate, path)
            if not hash then return scan_incomplete(scope, "context-hash") end
            return unique(candidate, hash, selections)
        end
    end
    return nil
end

local function decide_hash(candidates, selector, path, scope, limits, selections)
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
    if #usable == 1 then
        return unique(usable[1].candidate, usable[1].hash, selections)
    end
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
    local path, scanner, verifier = admitted.path, admitted.scanner, admitted.verifier
    local service = {}
    local selections = setmetatable({}, { __mode = "k" })

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
                outcome = decide_hash(
                    candidates,
                    classified.canonical,
                    path,
                    scope,
                    limits,
                    selections
                )
            else
                outcome = decide_name(
                    candidates,
                    classified.canonical,
                    path,
                    scope,
                    selections
                )
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

    ---Captures one browser/catalog row without resolving its short name again.
    -- The snapshot remains an observation only and must pass `verify_target`
    -- immediately before open or mutation.
    function service.capture_target(candidate)
        local rank = type(candidate) == "table" and candidate.scope_rank or 0
        if not valid_integer(rank, 0) then
            return nil, failure("InvalidTargetSnapshot", "target scope rank is invalid")
        end
        local admitted_candidate, candidate_error = validate_candidate(candidate, rank, path)
        if not admitted_candidate then
            return nil, failure(
                "InvalidTargetSnapshot",
                "target snapshot is malformed",
                candidate_error
            )
        end
        local hash = hash_candidate(admitted_candidate, path)
        if not hash then
            return nil, failure("InvalidTargetSnapshot", "target hash could not be computed")
        end
        return selected_result(
            admitted_candidate,
            hash,
            "TargetSnapshot",
            selections
        )
    end

    ---Re-observes one selected target and compares its complete credential.
    -- This never resolves by name/hash a second time and never scans for a
    -- replacement when the selected path has changed.
    function service.verify_target(selection, purpose)
        purpose = purpose or "open"
        if purpose ~= "open" and purpose ~= "mutation" and purpose ~= "delete" then
            return result({ tag = "TargetUnavailable", reason = "invalid-purpose" })
        end
        local expected = selections[selection]
        if not expected then
            return result({ tag = "TargetUnavailable", reason = "invalid-selection" })
        end
        if not verifier then
            return result({ tag = "TargetUnavailable", reason = "verifier-unavailable" })
        end
        local observed_ok, observed_or_error = invoke(verifier, "observe", {
            physical_path = expected.physical_path,
            logical_path = expected.logical_path,
        })
        if not observed_ok then
            local reason = safe_reason(observed_or_error, limits, "target-unavailable")
            if reason == "TargetChanged" or reason == "IdentityChanged" then
                return result({
                    tag = "TargetChanged",
                    logical_path = expected.logical_path,
                    reason = reason,
                })
            end
            return result({
                tag = "TargetUnavailable",
                logical_path = expected.logical_path,
                reason = reason,
            })
        end
        local observed, candidate_error = validate_candidate(
            observed_or_error,
            expected.scope_rank,
            path
        )
        if not observed then
            return result({
                tag = "TargetUnavailable",
                logical_path = expected.logical_path,
                reason = candidate_error,
            })
        end
        local same = observed.logical_path == expected.logical_path
            and observed.physical_path == expected.physical_path
            and observed.display_path == expected.display_path
            and observed.display_name == expected.display_name
            and observed.canonical_name == expected.canonical_name
            and observed.created_at == expected.created_at
            and observed.updated_at == expected.updated_at
            and observed.header_state == expected.header_state
            and deep_equal(observed.observed_stat, expected.observed_stat)
        if not same then
            return result({
                tag = "TargetChanged",
                logical_path = expected.logical_path,
                reason = "observation-changed",
            })
        end
        local delete_damaged = purpose == "delete"
            and observed.header_state == "corrupt"
            and type(observed.observed_stat) == "table"
        if observed.header_state ~= "valid" and not delete_damaged then
            return result({
                tag = "TargetUnavailable",
                logical_path = expected.logical_path,
                reason = "header-" .. observed.header_state,
            })
        end
        local current_hash = hash_candidate(observed, path)
        if not current_hash or current_hash ~= selection.hash then
            return result({
                tag = "TargetChanged",
                logical_path = expected.logical_path,
                reason = "hash-changed",
            })
        end
        return result({
            tag = "Verified",
            purpose = purpose,
            header_state = observed.header_state,
            logical_path = observed.logical_path,
            display_path = observed.display_path,
            hash = current_hash,
            physical_hint = observed.physical_path,
            credential = {
                physical_path = observed.physical_path,
                logical_path = observed.logical_path,
                observed_stat = observed.observed_stat,
                canonical_name = observed.canonical_name,
                created_at = observed.created_at,
                updated_at = observed.updated_at,
                header_state = observed.header_state,
            },
        })
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
        target_verifier = verifier ~= nil,
        target_qualified = false,
    }, "Context index capabilities")

    return readonly(service, "Context index service")
end

local FILESYSTEM_SCANNER_METHODS = {
    "direct_inspect",
    "direct_reverify",
    "direct_walk",
}

local CATALOG_STORE_METHODS = {
    "inspect_writer",
    "inspect_catalog_header",
}

local CATALOG_PATH_METHODS = {
    "validate_logical",
    "parent",
    "context_file",
}

local function valid_absolute_path(value)
    if not valid_text(value, false) then return false end
    local normalized = value:gsub("\\", "/")
    return normalized:sub(1, 1) == "/"
        or normalized:match("^[A-Za-z]:/") ~= nil
        or normalized:match("^//[^/]+/[^/]+") ~= nil
end

local function valid_platform_root(value, platform_kind)
    if not valid_absolute_path(value) then return false end
    local normalized = value:gsub("\\", "/")
    if platform_kind == "windows" then
        return normalized:match("^[A-Za-z]:/") ~= nil
            or normalized:match("^//[^/]+/[^/]+") ~= nil
    end
    return platform_kind == "posix" and normalized:sub(1, 1) == "/"
        and normalized:match("^[A-Za-z]:/") == nil
end

local function validate_filesystem_scanner_options(options)
    if type(options) ~= "table" then
        return nil, failure(
            "InvalidCatalogOptions",
            "Context catalog filesystem options are required"
        )
    end
    local allowed = {
        context_root = true,
        platform_kind = true,
        maximum_walk_depth = true,
        maximum_walk_entries = true,
    }
    for key in pairs(options) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure(
                "InvalidCatalogOptions",
                "Context catalog options contain an unknown field"
            )
        end
    end
    if not valid_platform_root(options.context_root, options.platform_kind)
        or (options.platform_kind ~= "posix" and options.platform_kind ~= "windows")
        or not valid_integer(options.maximum_walk_depth, 1)
        or not valid_integer(options.maximum_walk_entries, 1)
    then
        return nil, failure(
            "InvalidCatalogOptions",
            "Context catalog filesystem options are incomplete"
        )
    end
    return {
        context_root = options.context_root,
        platform_kind = options.platform_kind,
        maximum_walk_depth = options.maximum_walk_depth,
        maximum_walk_entries = options.maximum_walk_entries,
    }
end

local function validate_filesystem_scanner_ports(ports)
    if type(ports) ~= "table" then
        return nil, failure(
            "InvalidCatalogPorts",
            "Context catalog filesystem ports are required"
        )
    end
    local allowed = { filesystem = true, store = true, path = true }
    for key in pairs(ports) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure(
                "InvalidCatalogPorts",
                "Context catalog filesystem ports contain an unknown field"
            )
        end
    end
    local filesystem, port_error = snapshot_methods(
        ports.filesystem,
        FILESYSTEM_SCANNER_METHODS,
        "InvalidCatalogFilesystem",
        "Context catalog filesystem"
    )
    if not filesystem then return nil, port_error end
    local store
    store, port_error = snapshot_methods(
        ports.store,
        CATALOG_STORE_METHODS,
        "InvalidCatalogStore",
        "Context catalog store"
    )
    if not store then return nil, port_error end
    local path
    path, port_error = snapshot_methods(
        ports.path,
        CATALOG_PATH_METHODS,
        "InvalidCatalogPath",
        "Context catalog LogicalPath service"
    )
    if not path then return nil, port_error end
    return { filesystem = filesystem, store = store, path = path }
end

local function join_catalog_path(root, relative, platform_kind)
    if relative == "" then return root end
    local separator = platform_kind == "windows" and "\\" or "/"
    local suffix = platform_kind == "windows" and relative:gsub("/", "\\") or relative
    if root:sub(-1) == "/" or root:sub(-1) == "\\" then return root .. suffix end
    return root .. separator .. suffix
end

local function physical_key(value, platform_kind)
    local normalized = value:gsub("\\", "/")
    if platform_kind == "windows" then return normalized:lower() end
    return normalized
end

local CATALOG_UNAVAILABLE_ERRORS = {
    AccessDenied = true,
    Busy = true,
    ContextFilesystemContract = true,
    ContextUnavailable = true,
    DirectFilesystemUnavailable = true,
    InvalidTargetType = true,
    LockConflict = true,
    NativeContract = true,
    NativeFailure = true,
    NotFound = true,
    PermissionDenied = true,
    Storage = true,
    Unsupported = true,
}

local CATALOG_CHANGED_ERRORS = {
    ContextChanged = true,
    ContextTemporaryMismatch = true,
    IdentityChanged = true,
    TargetChanged = true,
}

local function catalog_error_state(error_value)
    local code = type(error_value) == "table" and error_value.code or nil
    if code and CATALOG_CHANGED_ERRORS[code] then return "changed" end
    if code and CATALOG_UNAVAILABLE_ERRORS[code] then return "unavailable" end
    return "corrupt"
end

local function call_value(port, method, ...)
    local called, value, value_error = pcall(port[method], ...)
    if not called then
        return nil, failure(
            "CatalogDependencyFailure",
            "Context catalog dependency raised an exception",
            method
        )
    end
    return value, value_error
end

local function call_status(port, method, ...)
    local ok, value = invoke(port, method, ...)
    if not ok then return nil, value end
    return value
end

local function increment(values, name, amount)
    values[name] = values[name] + (amount or 1)
end

---Creates the no-follow, bounded production scanner and target verifier.
-- Search rings are materialized only one at a time. Each complete ring is
-- enumerated twice around Header inspection so directory changes fail closed.
-- @return table|nil scanner Ephemeral ring scanner.
-- @return table|nil verifier Exact selected-target observer.
-- @return table|nil err Structured construction failure.
function M.new_filesystem_scanner(ports, options)
    local admitted_ports, ports_error = validate_filesystem_scanner_ports(ports)
    if not admitted_ports then return nil, nil, ports_error end
    local admitted, options_error = validate_filesystem_scanner_options(options)
    if not admitted then return nil, nil, options_error end
    local filesystem = admitted_ports.filesystem
    local store = admitted_ports.store
    local path = admitted_ports.path
    local handles = setmetatable({}, { __mode = "k" })
    local scanner = {}
    local verifier = {}

    local function physical_for_logical(root, logical)
        if admitted.platform_kind == "windows" and logical:find("\\", 1, true) then
            return nil
        end
        local relative = logical == "/" and "" or logical:sub(2)
        return join_catalog_path(root, relative, admitted.platform_kind)
    end

    local function unavailable_candidate(snapshot, logical, details, rank)
        local candidate = {
            physical_path = snapshot.requested_path,
            logical_path = logical,
            display_path = "CONTEXT" .. logical,
            display_name = details.display_name,
            observed_stat = snapshot.identity ~= false and snapshot.identity or nil,
            header_state = "unavailable",
        }
        if rank ~= nil then candidate.scope_rank = rank end
        return candidate
    end

    local function inspect_candidate(snapshot, logical, details, rank, statistics)
        local candidate = unavailable_candidate(snapshot, logical, details, rank)
        if snapshot.exists ~= true
            or type(snapshot.identity) ~= "table"
            or snapshot.identity.kind ~= "file"
            or snapshot.ancestry_complete ~= true
            or type(snapshot.metadata) ~= "table"
            or snapshot.metadata.link_target ~= false
        then
            increment(statistics, "unavailable")
            return candidate
        end
        local writer, writer_error = call_value(store, "inspect_writer", snapshot.requested_path)
        if not writer
            or type(writer.busy) ~= "boolean"
            or (writer.busy == false and writer.metadata_state ~= "absent")
            or (writer.busy == true
                and writer.metadata_state ~= "valid"
                and writer.metadata_state ~= "invalid"
                and writer.metadata_state ~= "unavailable")
        then
            increment(statistics, "unavailable")
            increment(statistics, "lock_unavailable")
            return candidate, writer_error
        end
        if writer.busy == true then
            increment(statistics, "busy")
            increment(statistics, "unavailable")
            if writer.metadata_state == "invalid" then
                increment(statistics, "lock_invalid")
            elseif writer.metadata_state == "unavailable" then
                increment(statistics, "lock_unavailable")
            end
            return candidate
        end
        local credential = {
            physical_path = snapshot.requested_path,
            logical_path = logical,
            observed_stat = snapshot.identity,
        }
        local header, report_or_error = call_value(
            store,
            "inspect_catalog_header",
            snapshot.requested_path,
            credential
        )
        if not header then
            local state = catalog_error_state(report_or_error)
            candidate.header_state = state
            increment(statistics, state)
            return candidate, report_or_error
        end
        if type(report_or_error) ~= "table"
            or report_or_error.body_opened ~= false
            or not valid_integer(report_or_error.bytes_read, 0)
            or type(header.name) ~= "string"
            or type(header.created_at) ~= "string"
            or type(header.updated_at) ~= "string"
        then
            candidate.header_state = "unavailable"
            increment(statistics, "unavailable")
            return candidate, failure(
                "CatalogDependencyContract",
                "Context catalog Header inspection returned an invalid result"
            )
        end
        increment(statistics, "header_bytes", report_or_error.bytes_read)
        local current, reverify_error = call_status(
            filesystem,
            "direct_reverify",
            snapshot
        )
        if not current then
            local state = catalog_error_state(reverify_error)
            candidate.header_state = state
            increment(statistics, state)
            return candidate, reverify_error
        end
        candidate.observed_stat = current.identity
        candidate.canonical_name = header.name
        candidate.created_at = header.created_at
        candidate.updated_at = header.updated_at
        candidate.header_state = "valid"
        increment(statistics, "valid")
        return candidate
    end

    local function mark_partial(state, reason)
        state.statistics.complete = false
        state.statistics.partial_reason = reason
    end

    local function incomplete_ring(state, scope, rank, reason)
        mark_partial(state, reason)
        return {
            scope = scope,
            rank = rank,
            complete = false,
            reason = reason,
            candidates = {},
        }
    end

    local function safe_directory(snapshot)
        return snapshot.exists == true
            and type(snapshot.identity) == "table"
            and snapshot.identity.kind == "directory"
            and snapshot.ancestry_complete == true
            and type(snapshot.metadata) == "table"
            and snapshot.metadata.link_target == false
    end

    local function observation_reason(error_value, fallback)
        return type(error_value) == "table" and error_value.code or fallback
    end

    local function confirm_observations(observations)
        local logical_paths = {}
        for logical in pairs(observations) do logical_paths[#logical_paths + 1] = logical end
        table.sort(logical_paths)
        for _, logical in ipairs(logical_paths) do
            local observation = observations[logical]
            local confirmed, confirm_error = call_status(
                filesystem,
                "direct_walk",
                observation.snapshot,
                0,
                observation.maximum_entries
            )
            if not confirmed then
                return nil, observation_reason(confirm_error, "EnumerationChanged")
            end
            if confirmed.complete ~= true
                or confirmed.generation ~= observation.generation
            then
                return nil, "EnumerationChanged"
            end
        end
        return true
    end

    local function complete_empty_ring(state, scope, rank)
        state.statistics.rings = state.statistics.rings + 1
        return { scope = scope, rank = rank, complete = true, candidates = {} }
    end

    local function scan_ring(state, scope, rank)
        local prior_stable, prior_error = confirm_observations(state.observations)
        if not prior_stable then
            return incomplete_ring(state, scope, rank, prior_error)
        end
        local physical_scope = physical_for_logical(admitted.context_root, scope)
        if not physical_scope then
            return incomplete_ring(state, scope, rank, "invalid-origin")
        end
        local snapshot, inspect_error = call_status(
            filesystem,
            "direct_inspect",
            physical_scope
        )
        if not snapshot then
            local code = type(inspect_error) == "table" and inspect_error.code or nil
            if code == "NotFound" then
                return complete_empty_ring(state, scope, rank)
            end
            return incomplete_ring(state, scope, rank, code or "scope-unavailable")
        end
        if snapshot.exists == false then
            local current, reverify_error = call_status(
                filesystem,
                "direct_reverify",
                snapshot
            )
            if not current then
                local reason = type(reverify_error) == "table" and reverify_error.code
                    or "EnumerationChanged"
                return incomplete_ring(state, scope, rank, reason)
            end
            return complete_empty_ring(state, scope, rank)
        end
        if not safe_directory(snapshot) then
            return incomplete_ring(state, scope, rank, "scope-unavailable")
        end
        local recursive = rank ~= 0 or scope == "/"
        local candidates = {}
        local new_paths = {}
        local current_observations = {}
        local pending = { { logical = scope, snapshot = snapshot, depth = 0 } }
        local ring_entries = 0
        local ring_statistics = {
            valid = 0,
            corrupt = 0,
            unavailable = 0,
            changed = 0,
            busy = 0,
            lock_invalid = 0,
            lock_unavailable = 0,
            header_bytes = 0,
        }
        while #pending > 0 do
            if ring_entries >= admitted.maximum_walk_entries then
                return incomplete_ring(state, scope, rank, "entry-limit")
            end
            local directory = pending[#pending]
            pending[#pending] = nil
            local remaining = admitted.maximum_walk_entries - ring_entries
            local walked, walk_error = call_status(
                filesystem,
                "direct_walk",
                directory.snapshot,
                0,
                remaining
            )
            if not walked then
                return incomplete_ring(
                    state,
                    scope,
                    rank,
                    observation_reason(walk_error, "enumeration-failed")
                )
            end
            state.statistics.entries = state.statistics.entries + #walked.entries
            ring_entries = ring_entries + #walked.entries
            if walked.complete ~= true then
                return incomplete_ring(
                    state,
                    scope,
                    rank,
                    type(walked.partial_reason) == "string"
                        and walked.partial_reason or "enumeration-incomplete"
                )
            end
            current_observations[directory.logical] = {
                snapshot = directory.snapshot,
                generation = walked.generation,
                maximum_entries = remaining,
            }
            local child_directories = {}
            for _, entry in ipairs(walked.entries) do
                local logical = directory.logical == "/"
                    and "/" .. entry.relative_path
                    or directory.logical .. "/" .. entry.relative_path
                local entry_kind = type(entry.snapshot.identity) == "table"
                    and entry.snapshot.identity.kind or false
                if entry_kind == "directory" then
                    if recursive and not state.completed_subtrees[logical] then
                        if not path.validate_logical(logical)
                            or not safe_directory(entry.snapshot)
                        then
                            return incomplete_ring(
                                state,
                                scope,
                                rank,
                                "scope-unavailable"
                            )
                        end
                        if directory.depth >= admitted.maximum_walk_depth then
                            return incomplete_ring(state, scope, rank, "depth-limit")
                        end
                        child_directories[#child_directories + 1] = {
                            logical = logical,
                            snapshot = entry.snapshot,
                            depth = directory.depth + 1,
                        }
                    end
                elseif logical:sub(-4) == ".xml" and not state.seen[logical] then
                    local details = path.context_file(logical)
                    if not details then
                        return incomplete_ring(state, scope, rank, "candidate-path")
                    end
                    if state.statistics.candidates + #candidates
                        >= state.maximum_scan_candidates
                    then
                        return incomplete_ring(state, scope, rank, "scan-limit")
                    end
                    local candidate = inspect_candidate(
                        entry.snapshot,
                        logical,
                        details,
                        rank,
                        ring_statistics
                    )
                    candidates[#candidates + 1] = candidate
                    new_paths[#new_paths + 1] = logical
                end
            end
            for index = #child_directories, 1, -1 do
                pending[#pending + 1] = child_directories[index]
            end
        end
        local combined_observations = {}
        for logical, observation in pairs(state.observations) do
            combined_observations[logical] = observation
        end
        for logical, observation in pairs(current_observations) do
            combined_observations[logical] = observation
        end
        local confirmed, confirm_error = confirm_observations(combined_observations)
        if not confirmed then
            return incomplete_ring(state, scope, rank, confirm_error)
        end
        state.observations = combined_observations
        if recursive then state.completed_subtrees[scope] = true end
        for _, logical in ipairs(new_paths) do state.seen[logical] = true end
        state.statistics.candidates = state.statistics.candidates + #candidates
        for name, value in pairs(ring_statistics) do
            state.statistics[name] = state.statistics[name] + value
        end
        state.statistics.rings = state.statistics.rings + 1
        return {
            scope = scope,
            rank = rank,
            complete = true,
            candidates = candidates,
        }
    end

    function scanner.begin(origin, limits)
        local logical = path.validate_logical(origin)
        if not logical
            or type(limits) ~= "table"
            or not valid_integer(limits.maximum_scan_candidates, 1)
            or not valid_integer(limits.maximum_search_rings, 1)
        then
            return false, failure("InvalidCatalogScan", "Context catalog scan is invalid")
        end
        for key in pairs(limits) do
            if key ~= "maximum_scan_candidates" and key ~= "maximum_search_rings" then
                return false, failure(
                    "InvalidCatalogScan",
                    "Context catalog scan limits contain an unknown field"
                )
            end
        end
        local scopes = {}
        local current = logical
        for _ = 1, limits.maximum_search_rings do
            scopes[#scopes + 1] = current
            if current == "/" then break end
            local parent_scope = path.parent(current)
            if not parent_scope or parent_scope == current then
                return false, failure(
                    "InvalidCatalogScan",
                    "Context catalog scope ancestry is invalid"
                )
            end
            current = parent_scope
        end
        local handle = readonly({}, "Context catalog scan handle")
        handles[handle] = {
            scopes = scopes,
            next_scope = 1,
            maximum_scan_candidates = limits.maximum_scan_candidates,
            seen = {},
            observations = {},
            completed_subtrees = {},
            closed = false,
            statistics = {
                complete = true,
                partial_reason = false,
                rings = 0,
                entries = 0,
                candidates = 0,
                valid = 0,
                corrupt = 0,
                unavailable = 0,
                changed = 0,
                busy = 0,
                lock_invalid = 0,
                lock_unavailable = 0,
                header_bytes = 0,
            },
        }
        return true, handle
    end

    function scanner.next_ring(handle)
        local state = handles[handle]
        if not state then
            return false, failure("InvalidCatalogScan", "Context catalog handle is foreign")
        end
        if state.closed then
            return false, failure("CatalogScanClosed", "Context catalog scan is closed")
        end
        local scope = state.scopes[state.next_scope]
        if not scope then return true, nil end
        local rank = state.next_scope - 1
        state.next_scope = state.next_scope + 1
        return true, scan_ring(state, scope, rank)
    end

    function scanner.close(handle)
        local state = handles[handle]
        if not state then
            return false, failure("InvalidCatalogScan", "Context catalog handle is foreign")
        end
        if state.closed then
            return false, failure("CatalogScanClosed", "Context catalog scan is closed")
        end
        state.closed = true
        return true
    end

    function scanner.status(handle)
        local state = handles[handle]
        if not state then
            return nil, failure("InvalidCatalogScan", "Context catalog handle is foreign")
        end
        local values = {}
        for key, value in pairs(state.statistics) do values[key] = value end
        values.closed = state.closed
        return result(values)
    end

    function verifier.observe(request)
        if type(request) ~= "table"
            or type(request.physical_path) ~= "string"
            or not path.validate_logical(request.logical_path)
        then
            return false, failure("InvalidTargetSnapshot", "Context target request is invalid")
        end
        for key in pairs(request) do
            if key ~= "physical_path" and key ~= "logical_path" then
                return false, failure(
                    "InvalidTargetSnapshot",
                    "Context target request contains an unknown field"
                )
            end
        end
        local root_snapshot, root_error = call_status(
            filesystem,
            "direct_inspect",
            admitted.context_root
        )
        if not root_snapshot then return false, root_error end
        if root_snapshot.exists ~= true
            or type(root_snapshot.identity) ~= "table"
            or root_snapshot.identity.kind ~= "directory"
            or root_snapshot.ancestry_complete ~= true
            or type(root_snapshot.metadata) ~= "table"
            or root_snapshot.metadata.link_target ~= false
        then
            return false, failure("TargetChanged", "Context catalog root changed")
        end
        local expected = physical_for_logical(
            root_snapshot.canonical_path,
            request.logical_path
        )
        if not expected
            or physical_key(expected, admitted.platform_kind)
                ~= physical_key(request.physical_path, admitted.platform_kind)
        then
            return false, failure("TargetChanged", "Context target left its catalog mapping")
        end
        local snapshot, inspect_error = call_status(
            filesystem,
            "direct_inspect",
            request.physical_path
        )
        if not snapshot then return false, inspect_error end
        if snapshot.exists ~= true then
            return false, failure("NotFound", "Context target is unavailable")
        end
        local details, details_error = path.context_file(request.logical_path)
        if not details then return false, details_error end
        local statistics = {
            valid = 0,
            corrupt = 0,
            unavailable = 0,
            changed = 0,
            busy = 0,
            lock_invalid = 0,
            lock_unavailable = 0,
            header_bytes = 0,
        }
        return true, inspect_candidate(
            snapshot,
            request.logical_path,
            details,
            nil,
            statistics
        )
    end

    scanner.capabilities = readonly({
        no_follow = true,
        bounded_header_only = true,
        stable_double_enumeration = true,
        persistent_index = false,
        target_qualified = false,
    }, "Context catalog scanner capabilities")
    verifier.capabilities = readonly({
        exact_selected_path = true,
        catalog_boundary_rechecked = true,
        target_qualified = false,
    }, "Context catalog verifier capabilities")
    return readonly(scanner, "Context catalog filesystem scanner"),
        readonly(verifier, "Context catalog target verifier")
end

return M
