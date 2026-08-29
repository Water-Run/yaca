--[[
File: backend_linux.lua
Date: 2026-08-30
Author: WaterRun
Description: Composes Linux x86_64 narrow native services.
]]

local fs = require("fs")
local process = require("process")
local terminal = require("terminal")

local M = {}

local ABI_VERSION = "yaca-native-v0.1.0"

local function failure(code, message)
    return { code = code, message = message }
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

local function validate_identity(identity)
    return type(identity) == "table"
        and identity.os == "linux"
        and identity.arch == "x86_64"
        and identity.target == "linux-x86_64"
        and identity.supported == true
end

local function validate_native(native)
    if type(native) ~= "table" or type(native.abi_version) ~= "function" then
        return nil, failure("InvalidNativeModule", "native ABI version function is required")
    end
    local ok, version = pcall(native.abi_version)
    if not ok or version ~= ABI_VERSION then
        return nil, failure("NativeAbiMismatch", "native ABI does not match this release")
    end
    if type(native.monotonic_now) ~= "function"
        or type(native.utc_now) ~= "function"
        or type(native.secure_random) ~= "function"
        or type(native.current_process_id) ~= "function"
    then
        return nil, failure(
            "InvalidNativeModule",
            "native clock, random, and process identity functions are required"
        )
    end
    return true
end

---Composes Linux services from one validated native module and platform identity.
-- No operating-system version is accepted or inspected. Hard caps must be
-- injected from the release manifest rather than chosen by this backend.
-- @param native table Loaded yaca_native module.
-- @param identity table Immutable identity returned by platform.lua.
-- @param options table Filesystem, process, and terminal release limits.
-- @return table|nil backend Immutable Linux backend bundle.
-- @return table|nil err Structured composition failure.
function M.new(native, identity, options)
    if not validate_identity(identity) then
        return nil, failure("PlatformMismatch", "Linux backend requires linux-x86_64 identity")
    end
    local valid, native_error = validate_native(native)
    if not valid then return nil, native_error end
    options = options or {}

    local filesystem, filesystem_error = fs.new(native, options.filesystem)
    if not filesystem then return nil, filesystem_error end
    local processes, process_error = process.new(native, {
        maximum_output_bytes = options.process and options.process.maximum_output_bytes,
        maximum_poll_bytes = options.process and options.process.maximum_poll_bytes,
        shell = {
            kind = "linux",
            executable = "/bin/sh",
            fixed_arguments = { "-c" },
        },
    })
    if not processes then return nil, process_error end
    local terminal_options = options.terminal or {}

    local clock_port = readonly({
        monotonic_now = native.monotonic_now,
        utc_now = native.utc_now,
    }, "Linux clock port")
    local system_port = readonly({
        utc_now = function()
            local called, value = pcall(native.utc_now)
            if not called or type(value) ~= "string" or value == "" then
                return nil, failure("UtcClockReadFailed", "native UTC clock failed")
            end
            return value
        end,
        current_process_id = function()
            local called, value = pcall(native.current_process_id)
            if not called or math.type(value) ~= "integer" or value < 1 then
                return nil, failure(
                    "ProcessIdentityUnavailable",
                    "native process identity failed"
                )
            end
            return value
        end,
        secure_random = function(length)
            if math.type(length) ~= "integer" or length < 1 or length > 64 then
                return nil, failure("InvalidRandomLength", "secure random length is invalid")
            end
            local called, value = pcall(native.secure_random, length)
            if not called or type(value) ~= "string" or #value ~= length then
                return nil, failure(
                    "SecureRandomUnavailable",
                    "native secure random source failed"
                )
            end
            return value
        end,
    }, "Linux system port")

    ---Creates a terminal port with the backend's fixed release input cap.
    -- @param mode string|nil Requested auto, raw, or cooked mode.
    -- @return table|nil port Terminal AsyncPort.
    -- @return table|nil err Structured construction failure.
    local function new_terminal(mode)
        return terminal.new(native, {
            mode = mode or terminal_options.mode or "auto",
            maximum_input_bytes = terminal_options.maximum_input_bytes,
        })
    end

    return readonly({
        target_id = "linux-x86_64",
        filesystem = filesystem,
        processes = processes,
        clock_port = clock_port,
        system = system_port,
        new_terminal = new_terminal,
        qualification = "pending-target-evidence",
    }, "Linux backend")
end

return M
