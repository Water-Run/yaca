--[[
Author: WaterRun
Date: 2026-08-29
File: safety.lua
Description: Provides immutable snapshots, private digests, and typed secret registries.
]]

local M = {}

-- Construct a structured diagnostic without throwing or formatting its optional fields.
--@param code string Stable diagnostic code used by callers to choose recovery behavior.
--@param message string Human-readable summary supplied by the failing operation.
--@param reason string|nil Optional machine-readable cause or validation rule.
--@return table New diagnostic record; optional non-nil fields are retained without deep copying.
local function failure(code, message, reason)
    local result = { code = code, message = message }
    if reason ~= nil then result.reason = reason end
    return result
end

-- Check the Lua integer subtype and the caller's inclusive lower bound.
--@param value any Candidate value; floats and non-numeric values are rejected.
--@param minimum integer Inclusive minimum accepted by this check.
--@return boolean True only for an integer at least minimum.
local function valid_integer(value, minimum)
    return math.type(value) == "integer" and value >= minimum
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
    --@field __len function Reports the backing table sequence length.
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
        -- Forward sequence-length queries to the backing table.
        --@param none The proxy operand supplied by Lua is ignored.
        --@return integer Length of the backing sequence under the Lua length operator.
        __len = function()
            return #values
        end,
        __metatable = "locked",
    })
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

-- Copy table values recursively behind read-only proxies, rejecting cycles and unsupported keys.
--@param value any Acyclic value graph; non-table values are returned unchanged.
--@param visiting table Tables on the current recursion path, used to detect cycles.
--@param label string|nil Diagnostic label applied to every proxy created by this traversal.
--@return any Copied table proxy or original non-table value; nil when validation fails.
--@return table|nil InvalidImmutableValue diagnostic for cycles or unsupported key types.
--@effect Temporarily marks visiting entries and removes them on all explicit return paths.
--@ownership Table contents are copied; non-table objects retain their original identity and ownership.
local function freeze_value(value, visiting, label)
    if type(value) ~= "table" then return value end
    if visiting[value] then
        return nil, failure("InvalidImmutableValue", "immutable values must not contain cycles")
    end
    visiting[value] = true
    local copied = {}
    for key, item in pairs(value) do
        local key_type = type(key)
        if key_type ~= "string" and key_type ~= "number" and key_type ~= "boolean" then
            visiting[value] = nil
            return nil, failure(
                "InvalidImmutableValue",
                "immutable table keys must be strings, numbers, or booleans"
            )
        end
        local frozen, freeze_error = freeze_value(item, visiting, label)
        if frozen == nil and freeze_error then
            visiting[value] = nil
            return nil, freeze_error
        end
        copied[key] = frozen
    end
    visiting[value] = nil
    return readonly(copied, label)
end

-- Capture the four required streaming SHA-256 functions from an injected port.
--@param port any Candidate native-style hash port.
--@return table|nil Fresh table of function references, or nil when a required function is missing.
--@return table|nil InvalidHashPort diagnostic on failure.
local function validate_hash_port(port)
    if type(port) ~= "table" then
        return nil, failure("InvalidHashPort", "a streaming SHA-256 port is required")
    end
    local result = {}
    for _, name in ipairs({
        "sha256_start", "sha256_update", "sha256_finish", "sha256_close",
    }) do
        if type(port[name]) ~= "function" then
            return nil, failure("InvalidHashPort", "streaming SHA-256 port is incomplete")
        end
        result[name] = port[name]
    end
    return result
end

-- Hash exact bytes in bounded updates and close the native digest handle before returning.
--@param port table Validated streaming SHA-256 function references.
--@param value any Candidate byte string; non-string inputs return InvalidDigestInput.
--@param maximum_chunk_bytes integer Positive maximum byte count passed to each update call.
--@return string|nil Lowercase 64-character SHA-256 digest, or nil on input/native failure.
--@return table|nil Structured input or NativeHash diagnostic without secret input bytes.
--@ownership Acquires one native digest handle and attempts to close it on each post-acquisition exit path.
local function digest(port, value, maximum_chunk_bytes)
    if type(value) ~= "string" then
        return nil, failure("InvalidDigestInput", "digest input must be a byte string")
    end
    local started, handle = pcall(port.sha256_start)
    if not started or handle == nil or handle == false then
        return nil, failure("NativeHash", "native SHA-256 start failed")
    end
    -- Release the captured digest handle while converting native exceptions into pcall results.
    --@param none No arguments; closes the handle acquired by this digest call.
    --@return boolean Whether the native close function returned without raising.
    --@return any... Native return values on success, or the raised error value on failure.
    --@ownership Attempts to release the captured native hash handle.
    local function close()
        return pcall(port.sha256_close, handle)
    end
    for index = 1, #value, maximum_chunk_bytes do
        local called, updated = pcall(
            port.sha256_update,
            handle,
            value:sub(index, index + maximum_chunk_bytes - 1)
        )
        if not called or updated ~= true then
            close()
            return nil, failure("NativeHash", "native SHA-256 update failed")
        end
    end
    local finished, bytes = pcall(port.sha256_finish, handle)
    local closed, close_result = close()
    if not finished or type(bytes) ~= "string" or #bytes ~= 32 then
        return nil, failure("NativeHash", "native SHA-256 returned a malformed digest")
    end
    if not closed or close_result ~= true then
        return nil, failure("NativeHash", "native SHA-256 close failed")
    end
    -- Render one raw digest byte as two lowercase hexadecimal digits.
    --@param byte string One-byte match supplied by string.gsub.
    --@return string Exactly two hexadecimal digits preserving that byte's value.
    return (bytes:gsub(".", function(byte)
        return string.format("%02x", byte:byte())
    end))
end

-- Validate secret identifiers and destination sets while copying registry structure.
--@param entries any Dense id/class/value/destinations records; ids and per-entry destinations must be unique.
--@return table|nil Private records indexed by id, or nil when an entry is invalid.
--@return table Records in source order on success, or an InvalidSecretRegistry diagnostic on failure.
--@ownership Copies entry and destination tables; immutable secret byte strings are retained in private records.
local function validate_secret_entries(entries)
    local count = dense_count(entries)
    if count == nil then
        return nil, failure("InvalidSecretRegistry", "secret entries must be a dense array")
    end
    local by_id = {}
    local ordered = {}
    for index, entry in ipairs(entries) do
        if type(entry) ~= "table" then
            return nil, failure("InvalidSecretRegistry", "secret entries must be tables")
        end
        local allowed = {
            id = true,
            class = true,
            value = true,
            destinations = true,
        }
        for key in pairs(entry) do
            if type(key) ~= "string" or not allowed[key] then
                return nil, failure("InvalidSecretRegistry", "secret entry has an unknown field")
            end
        end
        if type(entry.id) ~= "string" or entry.id == "" or by_id[entry.id]
            or type(entry.class) ~= "string" or entry.class == ""
            or type(entry.value) ~= "string" or entry.value == ""
        then
            return nil, failure("InvalidSecretRegistry", "secret entry identity is invalid")
        end
        local destination_count = dense_count(entry.destinations)
        if not destination_count or destination_count == 0 then
            return nil, failure("InvalidSecretRegistry", "secret destinations are required")
        end
        local destinations = {}
        for _, destination in ipairs(entry.destinations) do
            if type(destination) ~= "string" or destination == "" or destinations[destination] then
                return nil, failure("InvalidSecretRegistry", "secret destination is invalid")
            end
            destinations[destination] = true
        end
        local admitted = {
            id = entry.id,
            class = entry.class,
            value = entry.value,
            destinations = destinations,
            order = index,
        }
        by_id[entry.id] = admitted
        ordered[index] = admitted
    end
    return by_id, ordered
end

---Creates safety primitives around an injected streaming SHA-256 implementation.
-- Secret values remain in closure-owned state and are revealed only to their
-- exact registered destination. Descriptors and scan results never carry bytes.
--@param hash_port table Native-style streaming SHA-256 methods.
--@param options table Hash chunk and ordinary-content scan limits.
--@return table|nil service Immutable safety service.
--@return table|nil err Structured construction failure.
function M.new(hash_port, options)
    local port, port_error = validate_hash_port(hash_port)
    if not port then return nil, port_error end
    if type(options) ~= "table" then
        return nil, failure("InvalidSafetyOptions", "safety limits are required")
    end
    local allowed = {
        maximum_hash_chunk_bytes = true,
        minimum_scannable_secret_bytes = true,
    }
    for key in pairs(options) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure("InvalidSafetyOptions", "safety options contain an unknown field")
        end
    end
    if not valid_integer(options.maximum_hash_chunk_bytes, 1)
        or not valid_integer(options.minimum_scannable_secret_bytes, 1)
    then
        return nil, failure("InvalidSafetyOptions", "safety limits must be positive integers")
    end

    local service = {}

    ---Copies an acyclic table graph into read-only proxies, retaining non-table values unchanged.
    --@param value any Acyclic value graph.
    --@param label string|nil Mutation error label.
    --@return any frozen Immutable copy or original scalar.
    --@return table|nil err Cycle or key failure.
    function service.freeze(value, label)
        return freeze_value(value, {}, label or "immutable value")
    end

    ---Returns a lowercase private SHA-256 digest of exact bytes.
    --@param value string Exact byte input.
    --@return string|nil hex Lowercase full digest.
    --@return table|nil err Structured native hash failure.
    function service.digest(value)
        return digest(port, value, options.maximum_hash_chunk_bytes)
    end

    ---Hashes an ordered, typed public binding without ambiguous concatenation.
    -- Field order is part of the contract. Values are exact strings, booleans,
    -- or integers; secrets must never be supplied by callers.
    --@param domain string Stable ASCII/UTF-8 binding domain.
    --@param fields table Dense ordered { name, value } records.
    --@return string|nil hex Lowercase SHA-256 binding digest.
    --@return table|nil err Structured shape or native hash failure.
    function service.binding_digest(domain, fields)
        if type(domain) ~= "string" or domain == "" or domain:find("\0", 1, true) then
            return nil, failure("InvalidBinding", "binding domain is invalid")
        end
        local count = dense_count(fields)
        if count == nil then
            return nil, failure("InvalidBinding", "binding fields must be a dense array")
        end
        local parts = {
            "yaca-public-binding-v1\0",
            tostring(#domain), ":", domain,
            "\0", tostring(count), "\0",
        }
        local names = {}
        for _, field in ipairs(fields) do
            if type(field) ~= "table" then
                return nil, failure("InvalidBinding", "binding field must be a table")
            end
            for key in pairs(field) do
                if key ~= "name" and key ~= "value" then
                    return nil, failure("InvalidBinding", "binding field has an unknown key")
                end
            end
            if type(field.name) ~= "string" or field.name == ""
                or field.name:find("\0", 1, true) or names[field.name]
            then
                return nil, failure("InvalidBinding", "binding field identity is invalid")
            end
            names[field.name] = true
            local value_type = type(field.value)
            local tag, encoded
            if value_type == "string" then
                tag, encoded = "s", field.value
            elseif value_type == "boolean" then
                tag, encoded = "b", field.value and "1" or "0"
            elseif math.type(field.value) == "integer" then
                tag, encoded = "i", tostring(field.value)
            else
                return nil, failure("InvalidBinding", "binding value type is unsupported")
            end
            parts[#parts + 1] = tostring(#field.name)
            parts[#parts + 1] = ":"
            parts[#parts + 1] = field.name
            parts[#parts + 1] = ":"
            parts[#parts + 1] = tag
            parts[#parts + 1] = ":"
            parts[#parts + 1] = tostring(#encoded)
            parts[#parts + 1] = ":"
            parts[#parts + 1] = encoded
            parts[#parts + 1] = "\0"
        end
        return digest(port, table.concat(parts), options.maximum_hash_chunk_bytes)
    end

    service.binding_version = "yaca-public-binding-v1"

    ---Creates a closure-backed typed registry for one configuration generation.
    --@param entries table Dense id/class/value/destinations entries.
    --@return table|nil registry Immutable registry facade.
    --@return table|nil err Structured registry failure.
    function service.secret_registry(entries)
        local by_id, ordered_or_error = validate_secret_entries(entries)
        if not by_id then return nil, ordered_or_error end
        local ordered = ordered_or_error
        local maximum_scannable_bytes = 0
        for _, entry in ipairs(ordered) do
            if #entry.value >= options.minimum_scannable_secret_bytes then
                maximum_scannable_bytes = math.max(maximum_scannable_bytes, #entry.value)
            end
        end
        local registry = {}

        ---Lists non-secret registry metadata in deterministic source order.
        --@param none No arguments; enumerates this registry's captured entries.
        --@return table descriptors Immutable id/class/scan-eligibility records.
        function registry.descriptors()
            local descriptors = {}
            for index, entry in ipairs(ordered) do
                descriptors[index] = {
                    id = entry.id,
                    class = entry.class,
                    scan_eligible = #entry.value >= options.minimum_scannable_secret_bytes,
                }
            end
            return assert(freeze_value(descriptors, {}, "secret descriptors"))
        end

        ---Reveals a secret only to the exact consumer registered at construction.
        --@param id string Stable typed secret identity.
        --@param destination string Exact private carrier destination.
        --@return string|nil value Secret bytes for the admitted consumer.
        --@return table|nil err Unknown identity or destination failure.
        function registry.reveal(id, destination)
            local entry = type(id) == "string" and by_id[id] or nil
            if not entry then
                return nil, failure("UnknownSecret", "registered secret identity is unknown")
            end
            if type(destination) ~= "string" or not entry.destinations[destination] then
                return nil, failure(
                    "SecretDestinationDenied",
                    "secret destination is not registered"
                )
            end
            return entry.value
        end

        ---Scans exact ordinary bytes for eligible registered values.
        -- Short values are deliberately excluded by the release guarantee.
        --@param bytes string Bounded ordinary-content bytes.
        --@return table|nil hits Immutable non-secret match descriptors.
        --@return table|nil err Type failure.
        function registry.scan(bytes)
            if type(bytes) ~= "string" then
                return nil, failure("InvalidSecretScan", "secret scan input must be bytes")
            end
            local hits = {}
            for _, entry in ipairs(ordered) do
                if #entry.value >= options.minimum_scannable_secret_bytes then
                    local start_index = bytes:find(entry.value, 1, true)
                    if start_index then
                        hits[#hits + 1] = {
                            id = entry.id,
                            class = entry.class,
                            offset = start_index,
                            length = #entry.value,
                        }
                    end
                end
            end
            return assert(freeze_value(hits, {}, "secret scan results"))
        end

        ---Creates a cross-chunk exact scanner for an unbounded byte stream.
        -- Only the longest-pattern overlap is retained.  Match values and the
        -- overlap length stay closure-private so public diagnostics cannot use
        -- the scanner as a secret-length oracle.
        --@param none No arguments; uses this registry's eligible patterns and scan threshold.
        --@return table Read-only scanner facade exposing push and finish over private stream state.
        --@ownership Each scanner owns its overlap buffer until finish clears it or the scanner is collected.
        function registry.new_stream_scanner()
            local tail = ""
            local observed = 0
            local hit_count = 0
            local finished = false
            local scanner = {}

            -- Find newly completed matches, including overlapping and cross-chunk occurrences.
            --@param bytes string Next exact stream chunk; empty chunks are allowed before finish.
            --@return table|nil Read-only match descriptors with one-based absolute offsets; nil for invalid or closed input.
            --@return table|nil InvalidSecretScan or SecretScannerClosed diagnostic on failure.
            --@effect Advances the observed byte count, bounded overlap buffer and cumulative match count.
            function scanner.push(bytes)
                if finished then
                    return nil, failure("SecretScannerClosed", "secret stream scanner is closed")
                end
                if type(bytes) ~= "string" then
                    return nil, failure("InvalidSecretScan", "secret stream chunk must be bytes")
                end
                local combined = tail .. bytes
                local combined_start = observed - #tail
                local hits = {}
                for _, entry in ipairs(ordered) do
                    if #entry.value >= options.minimum_scannable_secret_bytes then
                        local from = 1
                        while true do
                            local first = combined:find(entry.value, from, true)
                            if not first then break end
                            local absolute = combined_start + first
                            local last = absolute + #entry.value - 1
                            -- A match whose final byte was already observed was
                            -- reported by an earlier push. This boundary rule
                            -- avoids an unbounded de-duplication set while the
                            -- overlap still catches every cross-chunk match.
                            if last > observed then
                                if hit_count < math.maxinteger then
                                    hit_count = hit_count + 1
                                end
                                hits[#hits + 1] = {
                                    id = entry.id,
                                    class = entry.class,
                                    offset = absolute,
                                    length = #entry.value,
                                }
                            end
                            from = first + 1
                        end
                    end
                end
                observed = observed + #bytes
                local overlap = math.max(maximum_scannable_bytes - 1, 0)
                tail = overlap == 0 and "" or combined:sub(-overlap)
                return assert(freeze_value(hits, {}, "secret stream scan results"))
            end

            -- Close the scanner and discard its retained overlap bytes.
            --@param none No arguments; may be called once per scanner.
            --@return table|nil Read-only observed-byte, match-count and redacted receipt; nil after an earlier finish.
            --@return table|nil SecretScannerClosed diagnostic when finish was already called.
            --@effect Clears the private tail and rejects all future push and finish calls.
            function scanner.finish()
                if finished then
                    return nil, failure("SecretScannerClosed", "secret stream scanner is closed")
                end
                finished = true
                tail = ""
                return readonly({
                    observed_bytes = observed,
                    hit_count = hit_count,
                    redacted = hit_count > 0,
                }, "secret stream scan receipt")
            end

            return readonly(scanner, "secret stream scanner")
        end

        registry.minimum_scannable_secret_bytes = options.minimum_scannable_secret_bytes
        return readonly(registry, "secret registry")
    end

    service.limits = readonly({
        maximum_hash_chunk_bytes = options.maximum_hash_chunk_bytes,
        minimum_scannable_secret_bytes = options.minimum_scannable_secret_bytes,
    }, "safety limits")
    return readonly(service, "safety service")
end

return M
