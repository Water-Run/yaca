--[[
File: fs.lua
Date: 2026-08-29
Author: WaterRun
Description: Validates and exposes narrow filesystem native primitives.
]]

local M = {}

local REQUIRED_METHODS = {
    "fs_open_read",
    "fs_create_new",
    "fs_stat_identity",
    "fs_read",
    "fs_write",
    "fs_flush_file",
    "fs_flush_directory",
    "fs_replace",
    "fs_rename_no_replace",
    "fs_delete_verified",
    "fs_close",
}

local function failure(code, message, detail)
    local result = { code = code, message = message }
    if detail ~= nil then result.detail = detail end
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

local function directory_of(path)
    if type(path) ~= "string" then return nil end
    local separator
    for index = #path, 1, -1 do
        local byte = path:byte(index)
        if byte == 0x2F or byte == 0x5C then
            separator = index
            break
        end
    end
    if not separator then return nil end
    if separator == 1 then return path:sub(1, 1) end
    if separator == 3 and path:sub(2, 2) == ":" then return path:sub(1, 3) end
    return path:sub(1, separator - 1)
end

local function normalize_native_error(value)
    if type(value) ~= "table"
        or type(value.code) ~= "string"
        or value.code == ""
        or type(value.message) ~= "string"
        or value.message == ""
    then
        return failure("NativeContract", "native filesystem returned an invalid error")
    end
    if value.retryable ~= nil and type(value.retryable) ~= "boolean" then
        return failure("NativeContract", "native filesystem returned an invalid retryable flag")
    end
    return value
end

local function invoke(native, method, ...)
    local ok, success, value = pcall(native[method], ...)
    if not ok then
        return false, failure("NativeFailure", "native filesystem call raised an exception")
    end
    if success == true then return true, value end
    if success == false then return false, normalize_native_error(value) end
    return false, failure("NativeContract", "native filesystem returned an invalid status")
end

local function validate_identity(identity)
    if type(identity) ~= "table" then
        return nil, failure("NativeContract", "filesystem identity must be a table")
    end
    local allowed = {
        kind = true,
        volume = true,
        object = true,
        size = true,
        modified = true,
    }
    for key in pairs(identity) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure("NativeContract", "filesystem identity has an unknown field")
        end
    end
    if type(identity.kind) ~= "string"
        or type(identity.volume) ~= "string"
        or type(identity.object) ~= "string"
        or not valid_integer(identity.size, 0)
        or type(identity.modified) ~= "string"
    then
        return nil, failure("NativeContract", "filesystem identity fields are invalid")
    end
    return readonly({
        kind = identity.kind,
        volume = identity.volume,
        object = identity.object,
        size = identity.size,
        modified = identity.modified,
    }, "filesystem identity")
end

---Creates a filesystem service around an injected native module.
-- Every path is required to be absolute and NUL-free. Write sizes are bounded
-- by the release-manifest value supplied by the composition root.
-- @param native table Native filesystem implementation.
-- @param options table Contains maximum_chunk_bytes.
-- @return table|nil service Immutable filesystem service.
-- @return table|nil err Structured construction failure.
function M.new(native, options)
    if type(native) ~= "table" then
        return nil, failure("InvalidFilesystemPort", "native filesystem port is required")
    end
    for _, method in ipairs(REQUIRED_METHODS) do
        if type(native[method]) ~= "function" then
            return nil, failure("InvalidFilesystemPort", "native filesystem omits " .. method)
        end
    end
    options = options or {}
    local maximum_chunk_bytes = options.maximum_chunk_bytes
    if not valid_integer(maximum_chunk_bytes, 1) then
        return nil, failure("InvalidFilesystemLimit", "maximum_chunk_bytes is required")
    end

    local maximum_lease_bytes = options.maximum_lease_bytes or maximum_chunk_bytes
    if not valid_integer(maximum_lease_bytes, 1) then
        return nil, failure("InvalidFilesystemLimit", "maximum_lease_bytes is invalid")
    end

    local service = {}
    local lease_states = setmetatable({}, { __mode = "k" })

    ---Opens an existing absolute path for binary reading.
    -- @param path string Absolute operating-system path.
    -- @return boolean ok Whether the file was opened.
    -- @return any handle_or_err Opaque handle or structured error.
    function service.open_read(path)
        if not valid_absolute_path(path) then
            return false, failure("InvalidPath", "open_read requires an absolute NUL-free path")
        end
        return invoke(native, "fs_open_read", path)
    end

    ---Creates a new file without replacing an existing directory entry.
    -- @param path string Absolute operating-system path.
    -- @param permissions integer Owner-oriented permission mask.
    -- @return boolean ok Whether the file was created.
    -- @return any handle_or_err Opaque handle or structured error.
    function service.create_new(path, permissions)
        if not valid_absolute_path(path) then
            return false, failure("InvalidPath", "create_new requires an absolute NUL-free path")
        end
        if not valid_integer(permissions, 0) or permissions > 511 then
            return false, failure(
                "InvalidPermissions",
                "permissions must be an integer from 0 to 511"
            )
        end
        return invoke(native, "fs_create_new", path, permissions)
    end

    ---Reads a stable identity from an open handle or absolute path.
    -- @param handle_or_path any Opaque native handle or absolute path.
    -- @return boolean ok Whether identity was read.
    -- @return table identity_or_err Immutable identity or structured error.
    function service.stat_identity(handle_or_path)
        if type(handle_or_path) == "string" and not valid_absolute_path(handle_or_path) then
            return false, failure("InvalidPath", "stat_identity received an invalid path")
        end
        local handle_type = type(handle_or_path)
        if handle_type ~= "string" and handle_type ~= "table" and handle_type ~= "userdata" then
            return false, failure("InvalidHandle", "stat_identity requires a path or native handle")
        end
        local ok, value = invoke(native, "fs_stat_identity", handle_or_path)
        if not ok then return false, value end
        local identity, identity_error = validate_identity(value)
        if not identity then return false, identity_error end
        return true, identity
    end

    ---Reads at most the requested number of binary bytes.
    -- @param handle any Opaque native read handle.
    -- @param maximum_bytes integer Positive bounded read size.
    -- @return boolean ok Whether bytes were read.
    -- @return table chunk_or_err Table with bytes and eof, or structured error.
    function service.stream_read(handle, maximum_bytes)
        if not valid_integer(maximum_bytes, 1) or maximum_bytes > maximum_chunk_bytes then
            return false, failure("Limit", "read size exceeds maximum_chunk_bytes")
        end
        local ok, value = invoke(native, "fs_read", handle, maximum_bytes)
        if not ok then return false, value end
        if type(value) ~= "table"
            or type(value.bytes) ~= "string"
            or type(value.eof) ~= "boolean"
            or #value.bytes > maximum_bytes
        then
            return false, failure("NativeContract", "native filesystem returned an invalid read")
        end
        return true, { bytes = value.bytes, eof = value.eof }
    end

    ---Writes one bounded binary chunk completely or returns an error.
    -- @param handle any Opaque native write handle.
    -- @param bytes string Exact bytes to write.
    -- @return boolean ok Whether all bytes were written.
    -- @return any result_or_err Byte count or structured error.
    function service.stream_write(handle, bytes)
        if type(bytes) ~= "string" then
            return false, failure("InvalidBytes", "stream_write requires a byte string")
        end
        if #bytes > maximum_chunk_bytes then
            return false, failure("Limit", "write size exceeds maximum_chunk_bytes")
        end
        local ok, value = invoke(native, "fs_write", handle, bytes)
        if not ok then return false, value end
        if value ~= #bytes then
            return false, failure(
                "NativeContract",
                "native filesystem did not report a complete write"
            )
        end
        return true, value
    end

    ---Flushes one open file handle to the strongest available storage barrier.
    -- @param handle any Opaque native file handle.
    -- @return boolean ok Whether the flush succeeded.
    -- @return any result_or_err Native result or structured error.
    function service.flush_file(handle)
        return invoke(native, "fs_flush_file", handle)
    end

    ---Flushes the directory containing publication metadata.
    -- @param path string Absolute directory path.
    -- @return boolean ok Whether the flush succeeded.
    -- @return any result_or_err Native result or structured error.
    function service.flush_directory(path)
        if not valid_absolute_path(path) then
            return false, failure("InvalidPath", "flush_directory requires an absolute path")
        end
        return invoke(native, "fs_flush_directory", path)
    end

    ---Atomically replaces one existing target with a flushed temporary file.
    -- @param temporary_path string Absolute temporary path.
    -- @param target_path string Absolute existing target path.
    -- @return boolean ok Whether replacement succeeded.
    -- @return any result_or_err Native result or structured error.
    function service.replace(temporary_path, target_path)
        if not valid_absolute_path(temporary_path) or not valid_absolute_path(target_path) then
            return false, failure("InvalidPath", "replace requires two absolute paths")
        end
        return invoke(native, "fs_replace", temporary_path, target_path)
    end

    ---Moves a source without ever replacing an existing destination.
    -- @param source_path string Absolute source path.
    -- @param target_path string Absolute target path.
    -- @return boolean ok Whether the move succeeded.
    -- @return any result_or_err Native result or structured error.
    function service.rename_no_replace(source_path, target_path)
        if not valid_absolute_path(source_path) or not valid_absolute_path(target_path) then
            return false, failure("InvalidPath", "rename_no_replace requires two absolute paths")
        end
        return invoke(native, "fs_rename_no_replace", source_path, target_path)
    end

    ---Deletes only when the native layer revalidates the expected identity.
    -- @param path string Absolute target path.
    -- @param identity table Previously observed filesystem identity.
    -- @return boolean ok Whether the verified target was deleted.
    -- @return any result_or_err Native result or structured error.
    function service.delete_verified(path, identity)
        if not valid_absolute_path(path) then
            return false, failure("InvalidPath", "delete_verified requires an absolute path")
        end
        local validated, identity_error = validate_identity(identity)
        if not validated then return false, identity_error end
        return invoke(native, "fs_delete_verified", path, {
            kind = validated.kind,
            volume = validated.volume,
            object = validated.object,
            size = validated.size,
            modified = validated.modified,
        })
    end

    ---Closes an opaque native file handle.
    -- @param handle any Opaque native file handle.
    -- @return boolean ok Whether close succeeded.
    -- @return any result_or_err Native result or structured error.
    function service.close(handle)
        return invoke(native, "fs_close", handle)
    end

    local function cleanup_created(path, identity)
        local stated, observed = service.stat_identity(path)
        if stated then identity = observed end
        if identity then service.delete_verified(path, identity) end
        local directory = directory_of(path)
        if directory then service.flush_directory(directory) end
    end

    ---Acquires an existence-backed exclusive lease with durable public metadata.
    -- Exclusive create is the mutex. A process crash intentionally leaves a
    -- stale file that only evidence-based self-fix may remove; age is never
    -- treated as proof that another writer is gone.
    -- @param path string Absolute stable lease path.
    -- @param metadata string Bounded public lock metadata bytes.
    -- @param permissions integer Permission mask for the lease file.
    -- @return boolean ok Whether this process acquired the lease.
    -- @return table lease_or_err Opaque lease or structured failure.
    function service.acquire_lease(path, metadata, permissions)
        if not valid_absolute_path(path) then
            return false, failure("InvalidPath", "lease path must be absolute")
        end
        if type(metadata) ~= "string" or #metadata > maximum_lease_bytes then
            return false, failure("LeaseLimit", "lease metadata exceeds its byte limit")
        end
        if not valid_integer(permissions, 0) or permissions > 511 then
            return false, failure("InvalidPermissions", "lease permissions are invalid")
        end
        local created, handle_or_error = service.create_new(path, permissions)
        if not created then
            if type(handle_or_error) == "table" and handle_or_error.code == "DestinationExists" then
                return false, failure("LockConflict", "exclusive lease already exists")
            end
            return false, handle_or_error
        end
        local handle = handle_or_error
        local offset = 1
        while offset <= #metadata do
            local chunk = metadata:sub(offset, offset + maximum_chunk_bytes - 1)
            local written, write_error = service.stream_write(handle, chunk)
            if not written then
                service.close(handle)
                cleanup_created(path)
                return false, write_error
            end
            offset = offset + #chunk
        end
        local flushed, flush_error = service.flush_file(handle)
        if not flushed then
            service.close(handle)
            cleanup_created(path)
            return false, flush_error
        end
        local stated, identity_or_error = service.stat_identity(handle)
        if not stated then
            service.close(handle)
            cleanup_created(path)
            return false, identity_or_error
        end
        local closed, close_error = service.close(handle)
        if not closed then
            cleanup_created(path, identity_or_error)
            return false, close_error
        end
        local directory = directory_of(path)
        local directory_flushed, directory_error = service.flush_directory(directory)
        if not directory_flushed then
            cleanup_created(path, identity_or_error)
            return false, failure(
                "LeaseAcquireUnknown",
                "lease publication durability is unknown",
                directory_error.code
            )
        end
        local lease = readonly({}, "filesystem lease")
        lease_states[lease] = {
            path = path,
            identity = identity_or_error,
            active = true,
        }
        return true, lease
    end

    ---Releases only the exact lease file identity acquired by this service.
    -- @param lease table Opaque lease returned by acquire_lease.
    -- @return boolean ok Whether removal and directory durability are proven.
    -- @return any result_or_err True or structured release failure.
    function service.release_lease(lease)
        local state = lease_states[lease]
        if not state or not state.active then
            return false, failure("InvalidLease", "filesystem lease is stale or foreign")
        end
        local deleted, delete_error = service.delete_verified(state.path, state.identity)
        if not deleted then return false, delete_error end
        state.active = false
        local flushed, flush_error = service.flush_directory(assert(directory_of(state.path)))
        if not flushed then
            return false, failure(
                "LeaseReleaseUnknown",
                "lease removal durability is unknown",
                flush_error.code
            )
        end
        return true, true
    end

    service.capabilities = readonly({
        atomic_replace_candidate = true,
        rename_no_replace_candidate = true,
        verified_delete_candidate = true,
        exclusive_create_lease_candidate = true,
        target_qualified = false,
        maximum_chunk_bytes = maximum_chunk_bytes,
        maximum_lease_bytes = maximum_lease_bytes,
    }, "filesystem capabilities")

    return readonly(service, "filesystem service")
end

return M
