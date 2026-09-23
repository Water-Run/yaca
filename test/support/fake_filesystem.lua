--[[
Author: WaterRun
Date: 2026-09-23
File: fake_filesystem.lua
Description: Provides an identity-aware in-memory filesystem service for transaction tests.
]]

local M = {}

--Supplies error value behavior required by this suite.
--@param code string|integer Expected error or exit code.
--@param message string|table Message or diagnostic passed through this test port.
--@return table observed Structured fixture record with code, message.
local function error_value(code, message)
    return { code = code, message = message or code }
end

--Supplies the same identity observation used by this suite.
--@param file table|string Fixture file or its path.
--@param identity table File or process identity under inspection.
--@return any matches Whether same identity satisfies the tested condition.
local function same_identity(file, identity)
    return type(identity) == "table"
        and identity.kind == "file"
        and identity.volume == file.volume
        and identity.object == file.object
        and identity.size == #file.bytes
        and identity.modified == file.modified
end

---Creates an in-memory filesystem with explicit external-change and fault controls.
--@param initial table|nil Absolute path to byte-string map.
--@param maximum_chunk_bytes integer|nil Stream cap.
--@return table service Narrow filesystem facade.
--@return table controls Test-only observations and mutation controls.
function M.new(initial, maximum_chunk_bytes)
    local files = {}
    local next_object = 0
    local next_modified = 0
    local controls = {
        operations = {},
        faults = {},
        created_permissions = {},
    }

    --Constructs make file for this test scenario.
    --@param bytes string Byte chunk supplied to the fake I/O port.
    --@param permissions table Permission profile exercised by the case.
    --@return table created Constructed make file fixture value.
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

    --Supplies touch behavior required by this suite.
    --@param file table|string Fixture file or its path.
    --@return nil No value; the fake port or test assertion observes this callback's effects.
    local function touch(file)
        next_modified = next_modified + 1
        file.modified = tostring(next_modified)
    end

    --Supplies the identity observation used by this suite.
    --@param file table|string Fixture file or its path.
    --@return table observed Structured fixture record selected by the exercised branch.
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

    --Supplies open read behavior required by this suite.
    --@param path string File or Context path exercised by the case.
    --@return boolean accepted Whether open read succeeds in the fixture.
    --@return table|any secondary2 Additional status or structured error from the fixture operation.
    function service.open_read(path)
        controls.operations[#controls.operations + 1] = "open:" .. path
        local file = files[path]
        if not file then return false, error_value("NotFound") end
        return true, { mode = "read", file = file, path = path, offset = 1, closed = false }
    end

    --Constructs create new for this test scenario.
    --@param path string File or Context path exercised by the case.
    --@param permissions table Permission profile exercised by the case.
    --@return boolean accepted Whether create new succeeds in the fixture.
    --@return table|any secondary2 Additional status or structured error from the fixture operation.
    function service.create_new(path, permissions)
        controls.operations[#controls.operations + 1] = "create:" .. path
        if files[path] then return false, error_value("DestinationExists") end
        local file = make_file("", permissions)
        files[path] = file
        controls.created_permissions[path] = permissions
        return true, { mode = "write", file = file, path = path, closed = false }
    end

    --Supplies the stat identity observation used by this suite.
    --@param handle_or_path table|string Fake handle or path accepted by this port.
    --@return boolean accepted Whether stat identity succeeds in the fixture.
    --@return any secondary2 Additional status or structured error from the fixture operation.
    function service.stat_identity(handle_or_path)
        controls.operations[#controls.operations + 1] = "stat"
        local file = type(handle_or_path) == "string"
            and files[handle_or_path]
            or type(handle_or_path) == "table" and handle_or_path.file
        if not file then return false, error_value("NotFound") end
        return true, identity(file)
    end

    --Supplies stream read behavior required by this suite.
    --@param handle table|integer Fake resource handle whose state is inspected.
    --@param maximum_bytes integer Maximum allowed byte length.
    --@return boolean accepted Whether stream read succeeds in the fixture.
    --@return table|any secondary2 Additional status or structured error from the fixture operation.
    function service.stream_read(handle, maximum_bytes)
        controls.operations[#controls.operations + 1] = "read"
        if type(handle) ~= "table" or handle.closed or handle.mode ~= "read" then
            return false, error_value("InvalidHandle")
        end
        local bytes = handle.file.bytes:sub(handle.offset, handle.offset + maximum_bytes - 1)
        handle.offset = handle.offset + #bytes
        return true, { bytes = bytes, eof = handle.offset > #handle.file.bytes }
    end

    --Supplies stream write behavior required by this suite.
    --@param handle table|integer Fake resource handle whose state is inspected.
    --@param bytes string Byte chunk supplied to the fake I/O port.
    --@return boolean accepted Whether stream write succeeds in the fixture.
    --@return any secondary2 Additional status or structured error from the fixture operation.
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

    --Supplies flush file behavior required by this suite.
    --@param handle table|integer Fake resource handle whose state is inspected.
    --@return boolean accepted Whether flush file succeeds in the fixture.
    --@return boolean|any secondary2 Additional status or structured error from the fixture operation.
    function service.flush_file(handle)
        controls.operations[#controls.operations + 1] = "flush-file"
        if controls.faults.flush_file then return false, error_value("InjectedFlush") end
        if type(handle) ~= "table" or handle.closed then
            return false, error_value("InvalidHandle")
        end
        return true, true
    end

    --Supplies flush directory behavior required by this suite.
    --@param path string File or Context path exercised by the case.
    --@return boolean accepted Whether flush directory succeeds in the fixture.
    --@return boolean|any secondary2 Additional status or structured error from the fixture operation.
    function service.flush_directory(path)
        controls.operations[#controls.operations + 1] = "flush-directory:" .. path
        if controls.faults.flush_directory then
            return false, error_value("InjectedDirectoryFlush")
        end
        return true, true
    end

    --Records the replace effect observed by this suite.
    --@param temporary_path string Temporary publication path used by the fixture.
    --@param target_path string Destination path targeted by the operation.
    --@return boolean accepted Whether replace succeeds in the fixture.
    --@return boolean|any secondary2 Additional status or structured error from the fixture operation.
    function service.replace(temporary_path, target_path)
        controls.operations[#controls.operations + 1] = "replace"
        if controls.faults.replace then return false, error_value("InjectedReplace") end
        if not files[temporary_path] then return false, error_value("NotFound") end
        if not files[target_path] then return false, error_value("NotFound") end
        files[target_path] = files[temporary_path]
        files[temporary_path] = nil
        return true, true
    end

    --Supplies rename no replace behavior required by this suite.
    --@param source_path string Source file path read by the fixture.
    --@param target_path string Destination path targeted by the operation.
    --@return boolean accepted Whether rename no replace succeeds in the fixture.
    --@return boolean|any secondary2 Additional status or structured error from the fixture operation.
    function service.rename_no_replace(source_path, target_path)
        controls.operations[#controls.operations + 1] = "rename-no-replace"
        if controls.faults.rename then return false, error_value("InjectedRename") end
        if not files[source_path] then return false, error_value("NotFound") end
        if files[target_path] then return false, error_value("DestinationExists") end
        files[target_path] = files[source_path]
        files[source_path] = nil
        return true, true
    end

    --Supplies delete verified behavior required by this suite.
    --@param path string File or Context path exercised by the case.
    --@param expected any Expected value used by the assertion.
    --@return boolean accepted Whether delete verified succeeds in the fixture.
    --@return boolean|any secondary2 Additional status or structured error from the fixture operation.
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

    -- Close a fixture handle, optionally finalizing write time or injecting corruption.
    --@param handle table Open fixture read or write handle.
    --@return boolean Whether this handle was open and is now closed.
    --@return boolean|table True on success, or an InvalidHandle error.
    --@effect Updates write time when close_updates_modified is enabled; may apply the configured corruption fault.
    function service.close(handle)
        controls.operations[#controls.operations + 1] = "close"
        if type(handle) ~= "table" or handle.closed then
            return false, error_value("InvalidHandle")
        end
        handle.closed = true
        if handle.mode == "write" and controls.close_updates_modified then
            touch(handle.file)
        end
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

    --Supplies bytes behavior required by this suite.
    --@param path string File or Context path exercised by the case.
    --@return any observed bytes value observed by the scenario assertion.
    function controls.bytes(path)
        return files[path] and files[path].bytes or nil
    end

    --Supplies permissions behavior required by this suite.
    --@param path string File or Context path exercised by the case.
    --@return any observed permissions value observed by the scenario assertion.
    function controls.permissions(path)
        return files[path] and files[path].permissions or nil
    end

    --Supplies the identity observation used by this suite.
    --@param path string File or Context path exercised by the case.
    --@return any observed identity value observed by the scenario assertion.
    function controls.identity(path)
        return files[path] and identity(files[path]) or nil
    end

    --Records the external replace effect observed by this suite.
    --@param path string File or Context path exercised by the case.
    --@param bytes string Byte chunk supplied to the fake I/O port.
    --@return nil No value; the fake port or test assertion observes this callback's effects.
    function controls.external_replace(path, bytes)
        files[path] = make_file(bytes)
    end

    --Records the external write effect observed by this suite.
    --@param path string File or Context path exercised by the case.
    --@param bytes string Byte chunk supplied to the fake I/O port.
    --@return boolean accepted Whether external write succeeds in the fixture.
    function controls.external_write(path, bytes)
        local file = files[path]
        if not file then return false end
        file.bytes = bytes
        touch(file)
        return true
    end

    --Supplies external delete behavior required by this suite.
    --@param path string File or Context path exercised by the case.
    --@return nil No value; the fake port or test assertion observes this callback's effects.
    function controls.external_delete(path)
        files[path] = nil
    end

    --Supplies exists behavior required by this suite.
    --@param path string File or Context path exercised by the case.
    --@return any observed exists value observed by the scenario assertion.
    function controls.exists(path)
        return files[path] ~= nil
    end

    return service, controls
end

return M
