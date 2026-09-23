--[[
Author: WaterRun
Date: 2026-09-23
File: written_identity_test.lua
Description: Verifies post-close write identities without admitting replaced or corrupted files.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()
local fs = assert(loadfile(YACA_TEST_ROOT .. "/src/fs.lua", "t", _ENV))()
local fake = assert(loadfile(YACA_TEST_ROOT .. "/test/support/fake_filesystem.lua", "t", _ENV))()
local PATH = "/data/owned.tmp"
local BYTES = "known public bytes"
local LEASE_PATH = "/data/writer.lock"

-- Create a flushed file whose modification timestamp is finalized on close.
--@param none No arguments.
--@return table Fixture filesystem.
--@return table Fixture observations and external mutation controls.
--@return table Identity captured before the write handle closes.
--@effect Writes only to a fresh in-memory filesystem.
local function written()
    local filesystem, controls = fake.new(nil, 4)
    controls.close_updates_modified = true
    local handle = select(2, assert(filesystem.create_new(PATH, 384)))
    assert(filesystem.stream_write(handle, BYTES))
    assert(filesystem.flush_file(handle))
    local before = select(2, assert(filesystem.stat_identity(handle)))
    assert(filesystem.close(handle))
    return filesystem, controls, before
end

-- Adapt the in-memory filesystem operations to the exact native names used by fs.new.
--@param none No arguments; creates a fresh five-byte-chunk fixture.
--@return table Validated filesystem service with lease operations.
--@return table Fixture observations and external mutation controls.
--@return table Mutable fake-native mapping for fault injection before each lease call.
--@effect Creates only an in-memory filesystem and service.
local function lease_fixture()
    local fixture, controls = fake.new(nil, 5)
    local mapping = {
        fs_open_read = "open_read",
        fs_create_new = "create_new",
        fs_stat_identity = "stat_identity",
        fs_read = "stream_read",
        fs_write = "stream_write",
        fs_flush_file = "flush_file",
        fs_flush_directory = "flush_directory",
        fs_replace = "replace",
        fs_rename_no_replace = "rename_no_replace",
        fs_delete_verified = "delete_verified",
        fs_close = "close",
    }
    local native = {}
    for name, implementation in pairs(mapping) do native[name] = fixture[implementation] end
    local service = assert(fs.new(native, {
        maximum_chunk_bytes = 5,
        maximum_lease_bytes = 64,
    }))
    return service, controls, native
end

return {
    name = "integration/written-identity",
    cases = {
        {
            name = "only the write-close timestamp may advance before exact readback",
            -- Accept the original object and payload using its finalized timestamp.
            --@param none No arguments.
            --@return nil Assertions complete without returning a value.
            run = function()
                local filesystem, controls, before = written()
                local after = assert(fs.observe_closed_write(filesystem, PATH, before, BYTES))
                A.equal(after.object, before.object)
                A.truthy(after.modified ~= before.modified)
                A.equal(after.modified, controls.identity(PATH).modified)
                A.equal(controls.bytes(PATH), BYTES)
            end,
        },
        {
            name = "replacement with identical payload remains foreign",
            -- Refuse a different object even when its size and bytes match.
            --@param none No arguments.
            --@return nil Assertions complete without returning a value.
            run = function()
                local filesystem, controls, before = written()
                controls.external_replace(PATH, BYTES)
                local identity, problem = fs.observe_closed_write(filesystem, PATH, before, BYTES)
                A.falsy(identity)
                A.equal(problem.code, "TargetChanged")
                A.equal(controls.bytes(PATH), BYTES)
            end,
        },
        {
            name = "same-object same-length corruption fails exact readback",
            -- Ensure accepting close-time metadata cannot authorize altered content.
            --@param none No arguments.
            --@return nil Assertions complete without returning a value.
            run = function()
                local filesystem, controls, before = written()
                local corrupt = string.rep("x", #BYTES)
                assert(controls.external_write(PATH, corrupt))
                local identity, problem = fs.observe_closed_write(filesystem, PATH, before, BYTES)
                A.falsy(identity)
                A.equal(problem.code, "WrittenContentChanged")
                A.equal(controls.bytes(PATH), corrupt)
            end,
        },
        {
            name = "changed size is refused even when the caller will validate bytes separately",
            -- Preserve the pre-close length bound for streamed Context writers.
            --@param none No arguments.
            --@return nil Assertions complete without returning a value.
            run = function()
                local filesystem, controls, before = written()
                assert(controls.external_write(PATH, BYTES .. "!"))
                local identity, problem = fs.observe_closed_write(filesystem, PATH, before)
                A.falsy(identity)
                A.equal(problem.code, "TargetChanged")
            end,
        },
        {
            name = "lease write failure preserves a foreign replacement at the lock path",
            -- Bind the original lease through its create handle, then swap the path before cleanup.
            --@param none No arguments.
            --@return nil Assertions complete without returning a value.
            --@effect Mutates only an isolated in-memory lease path and its injected write port.
            run = function()
                local service, controls, native = lease_fixture()
                -- Simulate a different writer replacing the original file as the write fails.
                --@param handle table Original lease write handle, retained by the fake port.
                --@param bytes string Bounded metadata chunk rejected by this injected fault.
                --@return boolean False because this fixture rejects the write.
                --@return table InjectedWrite diagnostic; the replacement has separate object identity.
                --@effect Replaces the lease path with a foreign fixture file.
                native.fs_write = function(handle, bytes)
                    A.truthy(handle)
                    A.truthy(bytes)
                    controls.external_replace(LEASE_PATH, "foreign lease")
                    return false, { code = "InjectedWrite", message = "fixture write failure" }
                end
                local acquired, problem = service.acquire_lease(LEASE_PATH, "version=1\n", 384)
                A.falsy(acquired)
                A.equal(problem.code, "InjectedWrite")
                A.equal(controls.bytes(LEASE_PATH), "foreign lease")
            end,
        },
        {
            name = "lease durability failure preserves a foreign replacement after write close",
            -- Verify that a later cleanup still uses the object bound at create time.
            --@param none No arguments.
            --@return nil Assertions complete without returning a value.
            --@effect Mutates only an isolated in-memory lease path and its directory-flush port.
            run = function()
                local service, controls, native = lease_fixture()
                -- Swap the flushed lease pathname before reporting directory durability failure.
                --@param path string Parent directory selected by the lease service.
                --@return boolean False because the injected directory flush fails.
                --@return table InjectedDirectoryFlush diagnostic for this fixture.
                --@effect Replaces only the fixture lease pathname with a foreign object.
                native.fs_flush_directory = function(path)
                    A.equal(path, "/data")
                    controls.external_replace(LEASE_PATH, "foreign lease")
                    return false, { code = "InjectedDirectoryFlush", message = "fixture durability failure" }
                end
                local acquired, problem = service.acquire_lease(LEASE_PATH, "version=1\n", 384)
                A.falsy(acquired)
                A.equal(problem.code, "LeaseAcquireUnknown")
                A.equal(controls.bytes(LEASE_PATH), "foreign lease")
            end,
        },
    },
}
