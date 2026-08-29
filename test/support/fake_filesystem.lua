--[[
File: fake_filesystem.lua
Date: 2026-08-29
Author: WaterRun
Description: Provides an identity-aware in-memory filesystem service for transaction tests.
]]

local M = {}

local function error_value(code, message)
    return { code = code, message = message or code }
end

local function same_identity(file, identity)
    return type(identity) == "table"
        and identity.kind == "file"
        and identity.volume == file.volume
        and identity.object == file.object
        and identity.size == #file.bytes
        and identity.modified == file.modified
end

---Creates an in-memory filesystem with explicit external-change and fault controls.
-- @param initial table|nil Absolute path to byte-string map.
-- @param maximum_chunk_bytes integer|nil Stream cap.
-- @return table service Narrow filesystem facade.
-- @return table controls Test-only observations and mutation controls.
function M.new(initial, maximum_chunk_bytes)
    local files = {}
    local next_object = 0
    local next_modified = 0
    local controls = {
        operations = {},
        faults = {},
        created_permissions = {},
    }

    local function make_file(bytes, permissions)
        next_object = next_object + 1
        next_modified = next_modified + 1
        return {
            bytes = bytes,
            permissions = permissions or 384,
            volume = "fake-volume",
            object = tostring(next_object),
            modified = tostring(next_modified),
        }
    end

    local function touch(file)
        next_modified = next_modified + 1
        file.modified = tostring(next_modified)
    end

    local function identity(file)
        return {
            kind = "file",
            volume = file.volume,
            object = file.object,
            size = #file.bytes,
            modified = file.modified,
        }
    end

    for path, bytes in pairs(initial or {}) do files[path] = make_file(bytes) end

    local service = {}

    function service.open_read(path)
        controls.operations[#controls.operations + 1] = "open:" .. path
        local file = files[path]
        if not file then return false, error_value("NotFound") end
        return true, { mode = "read", file = file, path = path, offset = 1, closed = false }
    end

    function service.create_new(path, permissions)
        controls.operations[#controls.operations + 1] = "create:" .. path
        if files[path] then return false, error_value("DestinationExists") end
        local file = make_file("", permissions)
        files[path] = file
        controls.created_permissions[path] = permissions
        return true, { mode = "write", file = file, path = path, closed = false }
    end

    function service.stat_identity(handle_or_path)
        controls.operations[#controls.operations + 1] = "stat"
        local file = type(handle_or_path) == "string"
            and files[handle_or_path]
            or type(handle_or_path) == "table" and handle_or_path.file
        if not file then return false, error_value("NotFound") end
        return true, identity(file)
    end

    function service.stream_read(handle, maximum_bytes)
        controls.operations[#controls.operations + 1] = "read"
        if type(handle) ~= "table" or handle.closed or handle.mode ~= "read" then
            return false, error_value("InvalidHandle")
        end
        local bytes = handle.file.bytes:sub(handle.offset, handle.offset + maximum_bytes - 1)
        handle.offset = handle.offset + #bytes
        return true, { bytes = bytes, eof = handle.offset > #handle.file.bytes }
    end

    function service.stream_write(handle, bytes)
        controls.operations[#controls.operations + 1] = "write"
        if controls.faults.write then return false, error_value("InjectedWrite") end
        if type(handle) ~= "table" or handle.closed or handle.mode ~= "write" then
            return false, error_value("InvalidHandle")
        end
        handle.file.bytes = handle.file.bytes .. bytes
        touch(handle.file)
        return true, #bytes
    end

    function service.flush_file(handle)
        controls.operations[#controls.operations + 1] = "flush-file"
        if controls.faults.flush_file then return false, error_value("InjectedFlush") end
        if type(handle) ~= "table" or handle.closed then
            return false, error_value("InvalidHandle")
        end
        return true, true
    end

    function service.flush_directory(path)
        controls.operations[#controls.operations + 1] = "flush-directory:" .. path
        if controls.faults.flush_directory then
            return false, error_value("InjectedDirectoryFlush")
        end
        return true, true
    end

    function service.replace(temporary_path, target_path)
        controls.operations[#controls.operations + 1] = "replace"
        if controls.faults.replace then return false, error_value("InjectedReplace") end
        if not files[temporary_path] then return false, error_value("NotFound") end
        if not files[target_path] then return false, error_value("NotFound") end
        files[target_path] = files[temporary_path]
        files[temporary_path] = nil
        return true, true
    end

    function service.rename_no_replace(source_path, target_path)
        controls.operations[#controls.operations + 1] = "rename-no-replace"
        if controls.faults.rename then return false, error_value("InjectedRename") end
        if not files[source_path] then return false, error_value("NotFound") end
        if files[target_path] then return false, error_value("DestinationExists") end
        files[target_path] = files[source_path]
        files[source_path] = nil
        return true, true
    end

    function service.delete_verified(path, expected)
        controls.operations[#controls.operations + 1] = "delete:" .. path
        local file = files[path]
        if not file then return false, error_value("NotFound") end
        if not same_identity(file, expected) then
            return false, error_value("IdentityChanged")
        end
        files[path] = nil
        return true, true
    end

    function service.close(handle)
        controls.operations[#controls.operations + 1] = "close"
        if type(handle) ~= "table" or handle.closed then
            return false, error_value("InvalidHandle")
        end
        handle.closed = true
        if handle.mode == "write" and controls.faults.corrupt_after_write_close then
            handle.file.bytes = handle.file.bytes .. "!"
            touch(handle.file)
            controls.faults.corrupt_after_write_close = false
        end
        return true, true
    end

    service.capabilities = {
        maximum_chunk_bytes = maximum_chunk_bytes or 17,
        target_qualified = false,
    }

    function controls.bytes(path)
        return files[path] and files[path].bytes or nil
    end

    function controls.permissions(path)
        return files[path] and files[path].permissions or nil
    end

    function controls.external_replace(path, bytes)
        files[path] = make_file(bytes)
    end

    function controls.exists(path)
        return files[path] ~= nil
    end

    return service, controls
end

return M
