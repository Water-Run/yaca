--[[
Author: WaterRun
Date: 2026-09-23
File: fs.lua
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

-- Construct a structured diagnostic without throwing or formatting its optional fields.
--@param code string Stable diagnostic code used by callers to choose recovery behavior.
--@param message string Human-readable summary supplied by the failing operation.
--@param detail any|nil Optional underlying cause or contextual diagnostic data; retained as supplied.
--@return table New diagnostic record; optional non-nil fields are retained without deep copying.
local function failure(code, message, detail)
    local result = { code = code, message = message }
    if detail ~= nil then result.detail = detail end
    return result
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

-- Check the Lua integer subtype and the caller's inclusive lower bound.
--@param value any Candidate value; floats and non-numeric values are rejected.
--@param minimum integer Inclusive minimum accepted by this check.
--@return boolean True only for an integer at least minimum.
local function valid_integer(value, minimum)
    return math.type(value) == "integer" and value >= minimum
end

-- Recognize a nonempty NUL-free POSIX, drive-rooted or UNC path spelling.
--@param path any Candidate native path; slash variants are inspected without changing the supplied bytes.
--@return boolean True for a path with an absolute prefix; this check does not resolve dot segments.
local function valid_absolute_path(path)
    if type(path) ~= "string" or path == "" or path:find("\0", 1, true) then
        return false
    end
    local normalized = path:gsub("\\", "/")
    return normalized:sub(1, 1) == "/"
        or normalized:match("^[A-Za-z]:/") ~= nil
        or normalized:match("^//[^/]+/[^/]+") ~= nil
end

-- Find the lexical parent while retaining POSIX and drive roots.
--@param path any Candidate native path containing slash or backslash separators.
--@return string|nil Parent spelling, or nil for a non-string path with no separator.
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

-- Keep a well-shaped native error or replace a malformed one with NativeContract.
--@param value any Error returned by a failed native filesystem call.
--@return table Original structured error when valid; a new NativeContract error otherwise.
--@ownership Valid native error tables are returned by reference, not copied.
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

-- Call one validated native entry while containing Lua exceptions and malformed status values.
--@param native table Injected native filesystem module.
--@param method string Exact native entry name selected by the service.
--@param ... any Ordered native arguments passed unchanged to the entry.
--@return boolean True only when the native entry explicitly reports success.
--@return any Native value on success or a normalized structured error on failure.
--@effect Runs the native operation selected by method; its filesystem effects depend on that entry.
local function invoke(native, method, ...)
    local ok, success, value = pcall(native[method], ...)
    if not ok then
        return false, failure("NativeFailure", "native filesystem call raised an exception")
    end
    if success == true then return true, value end
    if success == false then return false, normalize_native_error(value) end
    return false, failure("NativeContract", "native filesystem returned an invalid status")
end

-- Admit an exact five-field filesystem identity and freeze its scalar values.
--@param identity any Native identity candidate with kind, volume, object, size and modified fields.
--@return table|nil Read-only copy of the identity, or nil for an unexpected field or type.
--@return table|nil NativeContract diagnostic when validation fails.
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

-- Recreate a native-call-safe identity record from an already validated service identity.
--@param identity table Read-only identity previously returned by this filesystem service.
--@return table Fresh mutable five-field record passed to a native verified operation.
local function copy_identity(identity)
    return {
        kind = identity.kind,
        volume = identity.volume,
        object = identity.object,
        size = identity.size,
        modified = identity.modified,
    }
end

-- Validate a post-publication native identity without changing native failures.
--@param ok boolean Status returned by the verified rename or replace operation.
--@param value any Native identity on success, or structured native error on failure.
--@return boolean True only for a successful native call with a valid post-publication identity.
--@return table Frozen identity on success, original native error on failure, or Unknown for an invalid receipt.
local function publication_identity(ok, value)
    if not ok then return false, value end
    local identity, identity_error = validate_identity(value)
    if not identity then
        return false, failure("Unknown", "native publication receipt is invalid", identity_error.code)
    end
    return true, identity
end

-- Compare all five observed identity fields without performing a filesystem read.
--@param left any First previously validated identity record.
--@param right any Second previously validated identity record.
--@return boolean True when both are tables and kind, volume, object, size and modified are equal.
local function same_identity(left, right)
    return type(left) == "table" and type(right) == "table"
        and left.kind == right.kind
        and left.volume == right.volume
        and left.object == right.object
        and left.size == right.size
        and left.modified == right.modified
end

-- Compare persistent object keys while allowing size and modification time to change.
--@param left any First previously validated identity record.
--@param right any Second previously validated identity record.
--@return boolean True when both are tables with equal kind, volume and object fields.
local function same_object_identity(left, right)
    return type(left) == "table" and type(right) == "table"
        and left.kind == right.kind
        and left.volume == right.volume
        and left.object == right.object
end

-- Re-observe a newly written file after its write handle has closed. FAT may
-- finalize LastWriteTime at close even after FlushFileBuffers. Object and size
-- must remain exact; the returned timestamp becomes the stable readback bound.
--@param filesystem table Filesystem port with bounded reads and identity checks.
--@param path string Absolute path of the file just created by this caller.
--@param before table Identity observed through the flushed write handle.
--@param expected_bytes string|nil Exact payload to read back; nil delegates byte validation to the caller.
--@return table|nil Immutable post-close identity, or nil when validation fails.
--@return table|nil Structured identity, content, read or close failure.
--@effect Opens and closes a read handle when expected_bytes is supplied; never writes or deletes.
function M.observe_closed_write(filesystem, path, before, expected_bytes)
    local stated, observed = filesystem.stat_identity(path)
    if not stated then return nil, observed end
    local identity, identity_error = validate_identity(observed)
    if not identity then return nil, identity_error end
    if not same_object_identity(before, identity) or before.size ~= identity.size then
        return nil, failure("TargetChanged", "written file changed across handle close")
    end
    if expected_bytes == nil then return identity end
    if identity.size ~= #expected_bytes then
        return nil, failure("WrittenContentChanged", "written file size differs from its payload")
    end
    local opened, handle = filesystem.open_read(path)
    if not opened then return nil, handle end
    -- Release the owned read handle before returning the first validation error.
    --@param problem table Error that prevented exact readback.
    --@return nil No identity is admitted after a readback failure.
    --@return table Original structured error.
    --@ownership Closes handle exactly once on this failure path.
    local function reject(problem)
        filesystem.close(handle)
        return nil, problem
    end
    local bound, current = filesystem.stat_identity(handle)
    if not bound then return reject(current) end
    if not same_identity(identity, current) then
        return reject(failure("TargetChanged", "written file changed before readback"))
    end
    local offset = 1
    while true do
        local read, chunk = filesystem.stream_read(handle, filesystem.capabilities.maximum_chunk_bytes)
        if not read then return reject(chunk) end
        if chunk.bytes ~= expected_bytes:sub(offset, offset + #chunk.bytes - 1)
            or (#chunk.bytes == 0 and not chunk.eof)
        then
            return reject(failure("WrittenContentChanged", "written file differs from its payload"))
        end
        offset = offset + #chunk.bytes
        if chunk.eof then break end
    end
    local restated, final = filesystem.stat_identity(handle)
    local closed, close_error = filesystem.close(handle)
    if not restated then return nil, final end
    if not closed then return nil, close_error end
    if not same_identity(identity, final) or offset ~= #expected_bytes + 1 then
        return nil, failure("TargetChanged", "written file changed during readback")
    end
    return identity
end

-- Reject table keys outside an explicit string-key set without requiring every allowed key.
--@param value any Candidate record.
--@param allowed table Set of field names admitted by the caller's record contract.
--@return boolean True only for a table whose present keys are strings in allowed.
local function exact_fields(value, allowed)
    if type(value) ~= "table" then return false end
    for key in pairs(value) do
        if type(key) ~= "string" or not allowed[key] then return false end
    end
    return true
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

-- Admit a slash-delimited relative path without empty, dot, parent or backslash segments.
--@param value any Candidate native walk entry path.
--@return boolean True when a nonempty NUL-free relative spelling satisfies the walk grammar.
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

-- Join an already admitted native root and relative entry using the root's separator style.
--@param root string Absolute canonical directory path returned by native inspection.
--@param relative string Previously validated slash-delimited relative walk entry.
--@return string Native requested path for the direct entry beneath root.
local function join_direct_path(root, relative)
    local separator = root:find("\\", 1, true) and "\\" or "/"
    local suffix = relative:gsub("/", separator)
    if root:sub(-1) == "/" or root:sub(-1) == "\\" then return root .. suffix end
    return root .. separator .. suffix
end

-- Check every declared direct-file behavior and security metadata field.
--@param metadata any Native metadata candidate with link count, behavior digest, preservation and link target.
--@return table|nil Read-only admitted metadata, or nil for an incomplete or malformed record.
--@return table|nil NativeContract diagnostic on failure.
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

-- Admit one absolute ancestor path with a validated filesystem identity.
--@param ancestor any Native path/identity pair from a direct snapshot's ancestry array.
--@return table|nil Read-only admitted ancestor record, or nil for a malformed pair.
--@return table|nil NativeContract diagnostic on failure.
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

-- Freeze a complete direct-inspection record with explicit presence and ancestry facts.
--@param value any Native direct snapshot candidate including path, target, parent and ancestry fields.
--@return table|nil Read-only snapshot with nested admitted records, or nil on contract failure.
--@return table|nil NativeContract diagnostic naming the malformed native boundary.
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

-- Compare every safety-relevant direct path fact while ignoring ancestor modification times.
--@param left table Previously marked direct snapshot.
--@param right table Newly marked snapshot of the same requested path.
--@return boolean True when paths, presence, target identity/metadata and ancestor objects agree.
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
--@param native table Native filesystem implementation.
--@param options table Contains maximum_chunk_bytes.
--@return table|nil service Immutable filesystem service.
--@return table|nil err Structured construction failure.
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
    --@metatable lease_states Associates lease proxies with acquired path identities and active flags; collection does not remove lease files.
    --@field __mode string Fixed k mode: keys are weak; entries remain mutable within their owning module.
    local lease_states = setmetatable({}, { __mode = "k" })
    --@metatable direct_snapshot_states Marks direct filesystem snapshots admitted by this exact service instance.
    --@field __mode string Fixed k mode: keys are weak; entries remain mutable within their owning module.
    local direct_snapshot_states = setmetatable({}, { __mode = "k" })

    -- Bind a validated snapshot to this service instance's private weak-key registry.
    --@param snapshot table Read-only direct snapshot validated by this service.
    --@return table The same snapshot, now admitted for subsequent direct operations.
    --@effect Adds one service-local weak-key marker without changing the snapshot.
    local function mark_direct_snapshot(snapshot)
        direct_snapshot_states[snapshot] = true
        return snapshot
    end

    -- Reject unmarked or foreign snapshots before an identity-sensitive direct operation.
    --@param snapshot any Candidate snapshot value.
    --@param label string|nil Operation name included in an invalid-snapshot error.
    --@return table|nil Original marked snapshot, or nil when it was not issued by this service.
    --@return table|nil InvalidDirectSnapshot diagnostic for an unmarked value.
    local function require_direct_snapshot(snapshot, label)
        if not direct_snapshot_states[snapshot] then
            return nil, failure(
                "InvalidDirectSnapshot",
                (label or "direct operation") .. " requires a snapshot from this service"
            )
        end
        return snapshot
    end

    -- Report that one or more required no-follow native functions are absent.
    --@param none No arguments; reads the capability captured at service construction.
    --@return boolean False because direct operation admission is unavailable.
    --@return table DirectFilesystemUnavailable diagnostic.
    local function direct_unavailable()
        return false, failure(
            "DirectFilesystemUnavailable",
            "the complete no-follow direct filesystem port is unavailable"
        )
    end

    ---Opens an existing absolute path for binary reading.
    --@param path string Absolute operating-system path.
    --@return boolean ok Whether the file was opened.
    --@return any handle_or_err Opaque handle or structured error.
    --@effect Opens a native read handle when the path passes lexical validation.
    --@ownership The caller must close a successful handle with service.close.
    function service.open_read(path)
        if not valid_absolute_path(path) then
            return false, failure("InvalidPath", "open_read requires an absolute NUL-free path")
        end
        return invoke(native, "fs_open_read", path)
    end

    ---Creates a new file without replacing an existing directory entry.
    --@param path string Absolute operating-system path.
    --@param permissions integer Owner-oriented permission mask.
    --@return boolean ok Whether the file was created.
    --@return any handle_or_err Opaque handle or structured error.
    --@effect Creates exactly the named file when absent; does not create parent directories.
    --@ownership The caller must close a successful write handle with service.close.
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
    --@param handle_or_path any Opaque native handle or absolute path.
    --@return boolean ok Whether identity was read.
    --@return table identity_or_err Immutable identity or structured error.
    --@effect Reads native file metadata without modifying the file or handle position.
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
    --@param handle any Opaque native read handle.
    --@param maximum_bytes integer Positive bounded read size.
    --@return boolean ok Whether bytes were read.
    --@return table chunk_or_err Table with bytes and eof, or structured error.
    --@effect Advances the native read handle by the reported number of bytes.
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
    --@param handle any Opaque native write handle.
    --@param bytes string Exact bytes to write.
    --@return boolean ok Whether all bytes were written.
    --@return any result_or_err Byte count or structured error.
    --@effect Writes to the already opened native handle without publishing a pathname.
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
    --@param handle any Opaque native file handle.
    --@return boolean ok Whether the flush succeeded.
    --@return any result_or_err Native result or structured error.
    --@effect Requests the native file durability barrier for this handle.
    function service.flush_file(handle)
        return invoke(native, "fs_flush_file", handle)
    end

    ---Flushes the directory containing publication metadata.
    --@param path string Absolute directory path.
    --@return boolean ok Whether the flush succeeded.
    --@return any result_or_err Native result or structured error.
    --@effect Requests the native directory metadata durability barrier.
    function service.flush_directory(path)
        if not valid_absolute_path(path) then
            return false, failure("InvalidPath", "flush_directory requires an absolute path")
        end
        return invoke(native, "fs_flush_directory", path)
    end

    ---Atomically replaces one existing target with a flushed temporary file.
    --@param temporary_path string Absolute temporary path.
    --@param target_path string Absolute existing target path.
    --@return boolean ok Whether replacement succeeded.
    --@return any result_or_err Native result or structured error.
    --@effect Replaces the target entry when the native operation succeeds; caller must flush the directory.
    function service.replace(temporary_path, target_path)
        if not valid_absolute_path(temporary_path) or not valid_absolute_path(target_path) then
            return false, failure("InvalidPath", "replace requires two absolute paths")
        end
        return invoke(native, "fs_replace", temporary_path, target_path)
    end

    ---Moves a source without ever replacing an existing destination.
    --@param source_path string Absolute source path.
    --@param target_path string Absolute target path.
    --@return boolean ok Whether the move succeeded.
    --@return any result_or_err Native result or structured error.
    --@effect Moves the source without replacing a destination entry; caller must flush affected directories.
    function service.rename_no_replace(source_path, target_path)
        if not valid_absolute_path(source_path) or not valid_absolute_path(target_path) then
            return false, failure("InvalidPath", "rename_no_replace requires two absolute paths")
        end
        return invoke(native, "fs_rename_no_replace", source_path, target_path)
    end

    ---Deletes only when the native layer revalidates the expected identity.
    --@param path string Absolute target path.
    --@param identity table Previously observed filesystem identity.
    --@return boolean ok Whether the verified target was deleted.
    --@return any result_or_err Native result or structured error.
    --@effect Permanently removes only the matching identity; caller must flush the directory for durability.
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
    --@param handle any Opaque native file handle.
    --@return boolean ok Whether close succeeded.
    --@return any result_or_err Native result or structured error.
    --@ownership Attempts to release the native handle; a failed close leaves its actual state uncertain.
    function service.close(handle)
        return invoke(native, "fs_close", handle)
    end

    ---Creates one exact absolute directory without creating parent segments.
    -- Runtime composition uses this only for its fixed adjacent data tree.
    --@param path string Absolute directory path whose parent must already exist.
    --@param permissions integer Owner-oriented mode from zero through 511.
    --@return boolean True only when the native port reports successful creation.
    --@return any Native result or structured validation/port error.
    --@effect Creates one native directory entry without traversing and creating missing parents.
    function service.make_directory(path, permissions)
        if type(native.fs_make_directory) ~= "function" then
            return false, failure(
                "DirectoryCreationUnavailable",
                "the native directory creation port is unavailable"
            )
        end
        if not valid_absolute_path(path) then
            return false, failure("InvalidPath", "make_directory requires an absolute path")
        end
        if not valid_integer(permissions, 0) or permissions > 511 then
            return false, failure("InvalidPermissions", "directory permissions are invalid")
        end
        return invoke(native, "fs_make_directory", path, permissions)
    end

    ---Inspects one direct-tool path without following the final link.
    -- The native result binds canonical physical ancestry, final identity, and
    -- behavior/security metadata.  Incomplete ancestry is returned as data so
    -- callers can fail closed at the reserved-tree boundary.
    --@param path string Absolute target path.
    --@return boolean ok Whether inspection completed.
    --@return table snapshot_or_err Immutable marked snapshot or failure.
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
    --@param snapshot table Marked snapshot returned by direct_inspect/walk.
    --@return boolean ok True only when the exact snapshot is still current.
    --@return table current_or_err Current marked snapshot or typed stale error.
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
    --@param root_snapshot table Existing directory snapshot.
    --@param depth integer Maximum recursive depth, where zero is the root.
    --@param maximum_entries integer Maximum candidate records to return.
    --@return boolean ok Whether a bounded result was obtained.
    --@return table result_or_err Immutable walk result.
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
    --@param snapshot table Marked direct file snapshot issued by this service.
    --@return boolean True only when the opened handle still names that exact file identity.
    --@return any Open read handle on success, or a structured stale/port error.
    --@ownership The caller must close a successful handle with service.close.
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
    --@param missing_snapshot table Marked direct snapshot proving the target is absent.
    --@param permissions integer Owner-oriented mode from zero through 511.
    --@return boolean True only when creation against the reverified parent succeeds.
    --@return any Open write handle on success, or a structured collision/stale/port error.
    --@effect Creates one native ordinary file without replacing an existing entry.
    --@ownership The caller must close a successful handle with service.close.
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

    ---Replaces an exact target and returns its verified post-publication identity.
    --@param temporary_snapshot table Marked ordinary-file snapshot of the flushed temporary.
    --@param target_snapshot table Marked ordinary-file snapshot of the existing target in the same parent.
    --@return boolean True only when the verified native replacement returns a valid final identity.
    --@return table Immutable published identity on success, or a structured stale/native/unknown error.
    --@effect Publishes the temporary over the target; caller must flush the containing directory.
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
        return publication_identity(invoke(
            native,
            "fs_replace_verified",
            current_temporary.canonical_path,
            current_target.canonical_path,
            copy_identity(current_temporary.identity),
            copy_identity(current_target.identity),
            copy_identity(current_target.parent_identity),
            current_target.metadata.behavior_digest
        ))
    end

    ---Renames without replacement and returns the verified destination identity.
    --@param source_snapshot table Marked ordinary-file or directory source snapshot.
    --@param target_snapshot table Marked absent destination snapshot.
    --@return boolean True only when the verified native rename returns a valid final identity.
    --@return table Immutable destination identity on success, or a structured stale/native/unknown error.
    --@effect Moves the source without replacing the target; caller must flush affected directories.
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
        return publication_identity(invoke(
            native,
            "fs_rename_no_replace_verified",
            current_source.canonical_path,
            current_target.canonical_path,
            copy_identity(current_source.identity),
            copy_identity(current_source.parent_identity),
            copy_identity(current_target.parent_identity)
        ))
    end

    ---Permanently deletes one exact ordinary file or empty directory.
    --@param snapshot table Marked direct snapshot of the existing target to delete.
    --@return boolean True only when native verified deletion of the rechecked target succeeds.
    --@return any Native result or structured stale/type/port error.
    --@effect Removes one bound file or empty directory; caller must flush its parent directory.
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

    -- Remove only the lease object observed through this acquisition's creation handle.
    --@param path string Absolute lease path originally created by this service.
    --@param identity table|nil Identity captured from that creation handle; nil prevents deletion.
    --@return nil Cleanup is best effort; the caller preserves the original acquisition error.
    --@effect May delete the original lease object and flush its directory; never adopts a replacement object.
    local function cleanup_created(path, identity)
        if not identity then return end
        local stated, observed = service.stat_identity(path)
        if stated and same_object_identity(identity, observed) then
            service.delete_verified(path, observed)
        end
        local directory = directory_of(path)
        if directory then service.flush_directory(directory) end
    end

    ---Acquires an existence-backed exclusive lease with durable public metadata.
    -- Exclusive create is the mutex. A process crash intentionally leaves a
    -- stale file that only evidence-based self-fix may remove; age is never
    -- treated as proof that another writer is gone.
    --@param path string Absolute stable lease path.
    --@param metadata string Bounded public lock metadata bytes.
    --@param permissions integer Permission mask for the lease file.
    --@return boolean ok Whether this process acquired the lease.
    --@return table lease_or_err Opaque lease or structured failure.
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
        local bound, created_identity = service.stat_identity(handle)
        if not bound or created_identity.kind ~= "file" then
            service.close(handle)
            return false, failure(
                "LeaseAcquireUnknown",
                "created lease identity could not be bound",
                bound and "invalid-type" or created_identity.code
            )
        end
        local offset = 1
        while offset <= #metadata do
            local chunk = metadata:sub(offset, offset + maximum_chunk_bytes - 1)
            local written, write_error = service.stream_write(handle, chunk)
            if not written then
                service.close(handle)
                cleanup_created(path, created_identity)
                return false, write_error
            end
            offset = offset + #chunk
        end
        local flushed, flush_error = service.flush_file(handle)
        if not flushed then
            service.close(handle)
            cleanup_created(path, created_identity)
            return false, flush_error
        end
        local stated, identity_or_error = service.stat_identity(handle)
        if not stated then
            service.close(handle)
            cleanup_created(path, created_identity)
            return false, identity_or_error
        end
        local closed, close_error = service.close(handle)
        if not closed then
            cleanup_created(path, created_identity)
            return false, close_error
        end
        local final_identity, final_error = M.observe_closed_write(service, path, identity_or_error, metadata)
        if not final_identity then
            cleanup_created(path, created_identity)
            return false, final_error
        end
        identity_or_error = final_identity
        local directory = directory_of(path)
        local directory_flushed, directory_error = service.flush_directory(directory)
        if not directory_flushed then
            cleanup_created(path, created_identity)
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
    --@param lease table Opaque lease returned by acquire_lease.
    --@return boolean ok Whether removal and directory durability are proven.
    --@return any result_or_err True or structured release failure.
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
        directory_create_candidate = type(native.fs_make_directory) == "function",
        verified_direct_candidate = direct_available,
        maximum_direct_entries = maximum_direct_entries,
    }, "filesystem capabilities")

    return readonly(service, "filesystem service")
end

return M
