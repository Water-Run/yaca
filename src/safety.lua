--[[
File: safety.lua
Date: 2026-08-29
Author: WaterRun
Description: Provides immutable snapshots, private digests, and typed secret registries.
]]

local M = {}

local function failure(code, message, reason)
    local result = { code = code, message = message }
    if reason ~= nil then result.reason = reason end
    return result
end

local function valid_integer(value, minimum)
    return math.type(value) == "integer" and value >= minimum
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

local function digest(port, value, maximum_chunk_bytes)
    if type(value) ~= "string" then
        return nil, failure("InvalidDigestInput", "digest input must be a byte string")
    end
    local started, handle = pcall(port.sha256_start)
    if not started or handle == nil or handle == false then
        return nil, failure("NativeHash", "native SHA-256 start failed")
    end
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
    return (bytes:gsub(".", function(byte)
        return string.format("%02x", byte:byte())
    end))
end

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
-- @param hash_port table Native-style streaming SHA-256 methods.
-- @param options table Hash chunk and ordinary-content scan limits.
-- @return table|nil service Immutable safety service.
-- @return table|nil err Structured construction failure.
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

    ---Copies a value graph into recursively immutable proxy tables.
    -- @param value any Acyclic value graph.
    -- @param label string|nil Mutation error label.
    -- @return any frozen Immutable copy or original scalar.
    -- @return table|nil err Cycle or key failure.
    function service.freeze(value, label)
        return freeze_value(value, {}, label or "immutable value")
    end

    ---Returns a lowercase private SHA-256 digest of exact bytes.
    -- @param value string Exact byte input.
    -- @return string|nil hex Lowercase full digest.
    -- @return table|nil err Structured native hash failure.
    function service.digest(value)
        return digest(port, value, options.maximum_hash_chunk_bytes)
    end

    ---Creates a closure-backed typed registry for one configuration generation.
    -- @param entries table Dense id/class/value/destinations entries.
    -- @return table|nil registry Immutable registry facade.
    -- @return table|nil err Structured registry failure.
    function service.secret_registry(entries)
        local by_id, ordered_or_error = validate_secret_entries(entries)
        if not by_id then return nil, ordered_or_error end
        local ordered = ordered_or_error
        local registry = {}

        ---Lists non-secret registry metadata in deterministic source order.
        -- @return table descriptors Immutable id/class/scan-eligibility records.
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
        -- @param id string Stable typed secret identity.
        -- @param destination string Exact private carrier destination.
        -- @return string|nil value Secret bytes for the admitted consumer.
        -- @return table|nil err Unknown identity or destination failure.
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
        -- @param bytes string Bounded ordinary-content bytes.
        -- @return table|nil hits Immutable non-secret match descriptors.
        -- @return table|nil err Type failure.
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
