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

-- These methods are deliberately a separate capability set.  The basic
-- filesystem port is sufficient for Runtime-owned configuration and Context
-- publication, while model-visible direct tools additionally require
-- no-follow inspection and identity-bound mutation primitives.  A target that
-- does not provide the complete set remains usable for management, but direct
-- tools fail closed before admission.
local DIRECT_METHODS = {
    "fs_inspect_direct",
    "fs_walk_direct",
    "fs_open_read_verified",
    "fs_create_new_verified",
    "fs_replace_verified",
    "fs_rename_no_replace_verified",
    "fs_delete_direct_verified",
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

local function copy_identity(identity)
    return {
        kind = identity.kind,
        volume = identity.volume,
        object = identity.object,
        size = identity.size,
        modified = identity.modified,
    }
end

local function same_identity(left, right)
    return type(left) == "table" and type(right) == "table"
        and left.kind == right.kind
        and left.volume == right.volume
        and left.object == right.object
        and left.size == right.size
        and left.modified == right.modified
end

local function same_object_identity(left, right)
    return type(left) == "table" and type(right) == "table"
        and left.kind == right.kind
        and left.volume == right.volume
        and left.object == right.object
end

local function exact_fields(value, allowed)
    if type(value) ~= "table" then return false end
    for key in pairs(value) do
        if type(key) ~= "string" or not allowed[key] then return false end
    end
    return true
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

local function valid_relative_path(value)
    if type(value) ~= "string" or value == ""
        or value:find("\0", 1, true)
        or value:sub(1, 1) == "/"
        or value:find("\\", 1, true)
    then
        return false
    end
    for segment in value:gmatch("[^/]+") do
        if segment == "." or segment == ".." then return false end
    end
    return value:sub(-1) ~= "/" and not value:find("//", 1, true)
end

local function join_direct_path(root, relative)
    local separator = root:find("\\", 1, true) and "\\" or "/"
    local suffix = relative:gsub("/", separator)
    if root:sub(-1) == "/" or root:sub(-1) == "\\" then return root .. suffix end
    return root .. separator .. suffix
end

local function validate_direct_metadata(metadata)
    if not exact_fields(metadata, {
        link_count = true,
        behavior_digest = true,
        preservation = true,
        link_target = true,
    })
        or not valid_integer(metadata.link_count, 1)
        or type(metadata.behavior_digest) ~= "string"
        or metadata.behavior_digest == ""
        or (metadata.preservation ~= "proven" and metadata.preservation ~= "unsupported")
        or (metadata.link_target ~= false and not valid_absolute_path(metadata.link_target))
    then
        return nil, failure("NativeContract", "direct filesystem metadata is invalid")
    end
    return readonly({
        link_count = metadata.link_count,
        behavior_digest = metadata.behavior_digest,
        preservation = metadata.preservation,
        link_target = metadata.link_target,
    }, "direct filesystem metadata")
end

local function validate_ancestor(ancestor)
    if not exact_fields(ancestor, { path = true, identity = true })
        or not valid_absolute_path(ancestor.path)
    then
        return nil, failure("NativeContract", "direct filesystem ancestor is invalid")
    end
    local identity, identity_error = validate_identity(ancestor.identity)
    if not identity then return nil, identity_error end
    return readonly({ path = ancestor.path, identity = identity }, "filesystem ancestor")
end

local function validate_direct_snapshot(value)
    if not exact_fields(value, {
        requested_path = true,
        canonical_path = true,
        exists = true,
        identity = true,
        parent_identity = true,
        metadata = true,
        ancestors = true,
        ancestry_complete = true,
    })
        or not valid_absolute_path(value.requested_path)
        or not valid_absolute_path(value.canonical_path)
        or type(value.exists) ~= "boolean"
        or type(value.ancestry_complete) ~= "boolean"
    then
        return nil, failure("NativeContract", "direct filesystem snapshot is invalid")
    end
    local parent, parent_error = validate_identity(value.parent_identity)
    if not parent then return nil, parent_error end
    local identity = false
    local metadata = false
    if value.exists then
        identity, parent_error = validate_identity(value.identity)
        if not identity then return nil, parent_error end
        metadata, parent_error = validate_direct_metadata(value.metadata)
        if not metadata then return nil, parent_error end
    elseif value.identity ~= false or value.metadata ~= false then
        return nil, failure(
            "NativeContract",
            "missing direct target must not carry identity or metadata"
        )
    end
    local ancestor_count = dense_count(value.ancestors)
    if ancestor_count == nil or ancestor_count == 0 then
        return nil, failure("NativeContract", "direct ancestry must be a non-empty dense array")
    end
    local ancestors = {}
    for index, ancestor in ipairs(value.ancestors) do
        local admitted, ancestor_error = validate_ancestor(ancestor)
        if not admitted then return nil, ancestor_error end
        ancestors[index] = admitted
    end
    return readonly({
        requested_path = value.requested_path,
        canonical_path = value.canonical_path,
        exists = value.exists,
        identity = identity,
        parent_identity = parent,
        metadata = metadata,
        ancestors = readonly(ancestors, "filesystem ancestors"),
        ancestry_complete = value.ancestry_complete,
    }, "direct filesystem snapshot")
end

local function direct_snapshot_equal(left, right)
    if left.requested_path ~= right.requested_path
        or left.canonical_path ~= right.canonical_path
        or left.exists ~= right.exists
        or left.ancestry_complete ~= right.ancestry_complete
        or not same_object_identity(left.parent_identity, right.parent_identity)
        or #left.ancestors ~= #right.ancestors
    then
        return false
    end
    if left.exists then
        if not same_identity(left.identity, right.identity)
            or left.metadata.link_count ~= right.metadata.link_count
            or left.metadata.behavior_digest ~= right.metadata.behavior_digest
            or left.metadata.preservation ~= right.metadata.preservation
            or left.metadata.link_target ~= right.metadata.link_target
        then
            return false
        end
    end
    for index = 1, #left.ancestors do
        local left_ancestor, right_ancestor = left.ancestors[index], right.ancestors[index]
        if left_ancestor.path ~= right_ancestor.path
            or not same_object_identity(left_ancestor.identity, right_ancestor.identity)
        then
            return false
        end
    end
    return true
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

    local maximum_direct_entries = options.maximum_direct_entries or maximum_chunk_bytes
    if not valid_integer(maximum_direct_entries, 1) then
        return nil, failure("InvalidFilesystemLimit", "maximum_direct_entries is invalid")
    end

    local direct_available = true
    for _, method in ipairs(DIRECT_METHODS) do
        if type(native[method]) ~= "function" then
            direct_available = false
            break
        end
    end

    local service = {}
    local lease_states = setmetatable({}, { __mode = "k" })
    local direct_snapshot_states = setmetatable({}, { __mode = "k" })

    local function mark_direct_snapshot(snapshot)
        direct_snapshot_states[snapshot] = true
        return snapshot
    end

    local function require_direct_snapshot(snapshot, label)
        if not direct_snapshot_states[snapshot] then
            return nil, failure(
                "InvalidDirectSnapshot",
                (label or "direct operation") .. " requires a snapshot from this service"
            )
        end
        return snapshot
    end

    local function direct_unavailable()
        return false, failure(
            "DirectFilesystemUnavailable",
            "the complete no-follow direct filesystem port is unavailable"
        )
    end

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

    ---Inspects one direct-tool path without following the final link.
    -- The native result binds canonical physical ancestry, final identity, and
    -- behavior/security metadata.  Incomplete ancestry is returned as data so
    -- callers can fail closed at the reserved-tree boundary.
    -- @param path string Absolute target path.
    -- @return boolean ok Whether inspection completed.
    -- @return table snapshot_or_err Immutable marked snapshot or failure.
    function service.direct_inspect(path)
        if not direct_available then return direct_unavailable() end
        if not valid_absolute_path(path) then
            return false, failure("InvalidPath", "direct_inspect requires an absolute path")
        end
        local ok, value = invoke(native, "fs_inspect_direct", path)
        if not ok then return false, value end
        local snapshot, snapshot_error = validate_direct_snapshot(value)
        if not snapshot then return false, snapshot_error end
        if snapshot.requested_path ~= path then
            return false, failure("NativeContract", "direct snapshot changed the requested path")
        end
        return true, mark_direct_snapshot(snapshot)
    end

    ---Re-inspects and compares every safety-relevant direct path fact.
    -- @param snapshot table Marked snapshot returned by direct_inspect/walk.
    -- @return boolean ok True only when the exact snapshot is still current.
    -- @return table current_or_err Current marked snapshot or typed stale error.
    function service.direct_reverify(snapshot)
        local admitted, snapshot_error = require_direct_snapshot(snapshot, "direct_reverify")
        if not admitted then return false, snapshot_error end
        local ok, current = service.direct_inspect(snapshot.requested_path)
        if not ok then return false, current end
        if not direct_snapshot_equal(snapshot, current) then
            return false, failure("TargetChanged", "direct filesystem snapshot is stale")
        end
        return true, current
    end

    ---Performs one bounded no-follow walk with a fixed ignore grammar.
    -- @param root_snapshot table Existing directory snapshot.
    -- @param depth integer Maximum recursive depth, where zero is the root.
    -- @param maximum_entries integer Maximum candidate records to return.
    -- @return boolean ok Whether a bounded result was obtained.
    -- @return table result_or_err Immutable walk result.
    function service.direct_walk(root_snapshot, depth, maximum_entries)
        if not direct_available then return direct_unavailable() end
        local admitted, snapshot_error = require_direct_snapshot(root_snapshot, "direct_walk")
        if not admitted then return false, snapshot_error end
        if not root_snapshot.exists or root_snapshot.identity.kind ~= "directory" then
            return false, failure("InvalidTargetType", "direct walk root must be a directory")
        end
        if not valid_integer(depth, 0)
            or not valid_integer(maximum_entries, 1)
            or maximum_entries > maximum_direct_entries
        then
            return false, failure("Limit", "direct walk bounds are invalid")
        end
        local current_ok, current = service.direct_reverify(root_snapshot)
        if not current_ok then return false, current end
        local ok, value = invoke(
            native,
            "fs_walk_direct",
            current.canonical_path,
            depth,
            maximum_entries,
            "git-compatible-v1"
        )
        if not ok then return false, value end
        if not exact_fields(value, {
            generation = true,
            entries = true,
            complete = true,
            partial_reason = true,
        })
            or type(value.generation) ~= "string"
            or value.generation == ""
            or type(value.complete) ~= "boolean"
            or (value.partial_reason ~= false and type(value.partial_reason) ~= "string")
        then
            return false, failure("NativeContract", "direct walk result is invalid")
        end
        local count = dense_count(value.entries)
        if count == nil or count > maximum_entries then
            return false, failure("NativeContract", "direct walk entries violate the bound")
        end
        if value.complete and value.partial_reason ~= false then
            return false, failure("NativeContract", "complete direct walk has a partial reason")
        end
        if not value.complete and value.partial_reason == false then
            return false, failure("NativeContract", "partial direct walk omits its reason")
        end
        local entries, seen = {}, {}
        for index, entry in ipairs(value.entries) do
            if not exact_fields(entry, { relative_path = true, snapshot = true })
                or not valid_relative_path(entry.relative_path)
                or seen[entry.relative_path]
            then
                return false, failure("NativeContract", "direct walk entry path is invalid")
            end
            seen[entry.relative_path] = true
            local snapshot, entry_error = validate_direct_snapshot(entry.snapshot)
            if not snapshot then return false, entry_error end
            if snapshot.requested_path ~= join_direct_path(
                current.canonical_path,
                entry.relative_path
            ) then
                return false, failure(
                    "NativeContract",
                    "direct walk entry is not rooted below the requested directory"
                )
            end
            entries[index] = readonly({
                relative_path = entry.relative_path,
                snapshot = mark_direct_snapshot(snapshot),
            }, "direct walk entry")
        end
        return true, readonly({
            generation = value.generation,
            entries = readonly(entries, "direct walk entries"),
            complete = value.complete,
            partial_reason = value.partial_reason,
        }, "direct walk result")
    end

    ---Opens only the exact previously inspected ordinary file.
    function service.direct_open_read(snapshot)
        if not direct_available then return direct_unavailable() end
        local admitted, snapshot_error = require_direct_snapshot(snapshot, "direct_open_read")
        if not admitted then return false, snapshot_error end
        if not snapshot.exists or snapshot.identity.kind ~= "file" then
            return false, failure("InvalidTargetType", "direct read requires an ordinary file")
        end
        local current_ok, current = service.direct_reverify(snapshot)
        if not current_ok then return false, current end
        local ok, handle_or_error = invoke(
            native,
            "fs_open_read_verified",
            current.canonical_path,
            copy_identity(current.identity)
        )
        if not ok then return false, handle_or_error end
        local stated, identity_or_error = service.stat_identity(handle_or_error)
        if not stated or not same_identity(identity_or_error, current.identity) then
            service.close(handle_or_error)
            return false, stated and failure("TargetChanged", "opened direct file identity changed")
                or identity_or_error
        end
        return true, handle_or_error
    end

    ---Creates a final or temporary ordinary file against an exact parent.
    function service.direct_create_new(missing_snapshot, permissions)
        if not direct_available then return direct_unavailable() end
        local admitted, snapshot_error = require_direct_snapshot(
            missing_snapshot,
            "direct_create_new"
        )
        if not admitted then return false, snapshot_error end
        if missing_snapshot.exists then
            return false, failure("DestinationExists", "direct create target already exists")
        end
        if not valid_integer(permissions, 0) or permissions > 511 then
            return false, failure("InvalidPermissions", "direct create permissions are invalid")
        end
        local current_ok, current = service.direct_reverify(missing_snapshot)
        if not current_ok then return false, current end
        return invoke(
            native,
            "fs_create_new_verified",
            current.canonical_path,
            copy_identity(current.parent_identity),
            permissions
        )
    end

    ---Replaces an exact target with an exact same-directory temporary.
    function service.direct_replace(temporary_snapshot, target_snapshot)
        if not direct_available then return direct_unavailable() end
        local temporary, temporary_error = require_direct_snapshot(
            temporary_snapshot,
            "direct_replace temporary"
        )
        if not temporary then return false, temporary_error end
        local target, target_error = require_direct_snapshot(target_snapshot, "direct_replace target")
        if not target then return false, target_error end
        if not temporary.exists or temporary.identity.kind ~= "file"
            or not target.exists or target.identity.kind ~= "file"
            or not same_object_identity(temporary.parent_identity, target.parent_identity)
        then
            return false, failure(
                "InvalidTargetType",
                "direct replace requires ordinary files in one exact directory"
            )
        end
        local temporary_ok, current_temporary = service.direct_reverify(temporary)
        if not temporary_ok then return false, current_temporary end
        local target_ok, current_target = service.direct_reverify(target)
        if not target_ok then return false, current_target end
        return invoke(
            native,
            "fs_replace_verified",
            current_temporary.canonical_path,
            current_target.canonical_path,
            copy_identity(current_temporary.identity),
            copy_identity(current_target.identity),
            copy_identity(current_target.parent_identity)
        )
    end

    ---Renames one exact source to an exact absent target without replacement.
    function service.direct_rename(source_snapshot, target_snapshot)
        if not direct_available then return direct_unavailable() end
        local source, source_error = require_direct_snapshot(source_snapshot, "direct_rename source")
        if not source then return false, source_error end
        local target, target_error = require_direct_snapshot(target_snapshot, "direct_rename target")
        if not target then return false, target_error end
        if not source.exists or (source.identity.kind ~= "file" and source.identity.kind ~= "directory")
            or target.exists
        then
            return false, failure(
                "InvalidTargetType",
                "direct rename requires an ordinary source and absent target"
            )
        end
        local source_ok, current_source = service.direct_reverify(source)
        if not source_ok then return false, current_source end
        local target_ok, current_target = service.direct_reverify(target)
        if not target_ok then return false, current_target end
        return invoke(
            native,
            "fs_rename_no_replace_verified",
            current_source.canonical_path,
            current_target.canonical_path,
            copy_identity(current_source.identity),
            copy_identity(current_source.parent_identity),
            copy_identity(current_target.parent_identity)
        )
    end

    ---Permanently deletes one exact ordinary file or empty directory.
    function service.direct_delete(snapshot)
        if not direct_available then return direct_unavailable() end
        local admitted, snapshot_error = require_direct_snapshot(snapshot, "direct_delete")
        if not admitted then return false, snapshot_error end
        if not snapshot.exists
            or (snapshot.identity.kind ~= "file" and snapshot.identity.kind ~= "directory")
        then
            return false, failure(
                "InvalidTargetType",
                "direct delete requires an ordinary file or empty directory"
            )
        end
        local current_ok, current = service.direct_reverify(snapshot)
        if not current_ok then return false, current end
        return invoke(
            native,
            "fs_delete_direct_verified",
            current.canonical_path,
            copy_identity(current.identity),
            copy_identity(current.parent_identity)
        )
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
        verified_direct_candidate = direct_available,
        maximum_direct_entries = maximum_direct_entries,
    }, "filesystem capabilities")

    return readonly(service, "filesystem service")
end

return M
