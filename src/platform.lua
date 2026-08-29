--[[
File: platform.lua
Date: 2026-08-29
Author: WaterRun
Description: Produces the immutable normalized platform identity.
]]

local M = {}

local TARGET_BY_IDENTITY = {
    ["windows\0x86"] = "win32-x86",
    ["windows\0x86_64"] = "win64-x86_64",
    ["linux\0x86_64"] = "linux-x86_64",
}

local RELEASE_TARGETS = {
    ["win32-x86"] = true,
    ["win64-x86_64"] = true,
    ["linux-x86_64"] = true,
}

local function failure(code, detail)
    return { code = code, detail = detail }
end

local function readonly(values, label)
    return setmetatable({}, {
        __index = values,
        __newindex = function(_, key)
            error((label or "readonly value") .. " cannot be modified: " .. tostring(key), 2)
        end,
        __pairs = function() return next, values, nil end,
        __metatable = "locked",
        __tostring = function() return label or "readonly value" end,
    })
end

local function validate_observation(observation)
    if type(observation) ~= "table" then
        return nil, failure("InvalidPlatformIdentity", "native platform_identity must return a table")
    end
    local allowed = { os = true, arch = true }
    for key in pairs(observation) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure("UnexpectedPlatformField", tostring(key))
        end
    end
    if type(observation.os) ~= "string" or type(observation.arch) ~= "string" then
        return nil, failure("InvalidPlatformIdentity", "os and arch must be canonical strings")
    end
    local target = TARGET_BY_IDENTITY[observation.os .. "\0" .. observation.arch]
    if not target then
        return nil, failure("UnsupportedPlatform", observation.os .. "/" .. observation.arch)
    end
    return {
        os = observation.os,
        arch = observation.arch,
        target = target,
    }
end

---Creates a lazy platform service for one declared release target.
-- @param native table Native port exposing platform_identity().
-- @param release_target string One of the release manifest target names.
-- @return table|nil service Immutable service exposing identity().
-- @return table|nil err Structured validation or probe failure.
function M.new(native, release_target)
    if type(native) ~= "table" or type(native.platform_identity) ~= "function" then
        return nil, failure("InvalidPlatformPort", "platform_identity function is required")
    end
    if type(release_target) ~= "string" or not RELEASE_TARGETS[release_target] then
        return nil, failure("UnknownReleaseTarget", tostring(release_target))
    end

    local attempted = false
    local cached_identity, cached_error

    local function identity()
        if attempted then return cached_identity, cached_error end
        attempted = true

        local ok, observation, probe_error = pcall(native.platform_identity)
        if not ok then
            cached_error = failure("PlatformProbeFailed", tostring(observation))
            return nil, cached_error
        end
        if observation == nil then
            cached_error = failure("PlatformProbeFailed", tostring(probe_error or "native probe returned no identity"))
            return nil, cached_error
        end

        local normalized, validation_error = validate_observation(observation)
        if not normalized then
            cached_error = validation_error
            return nil, cached_error
        end
        normalized.supported = normalized.target == release_target
        cached_identity = readonly(normalized, "platform identity")
        return cached_identity
    end

    return readonly({ identity = identity }, "platform service")
end

return M
