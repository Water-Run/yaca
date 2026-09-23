--[[
Author: WaterRun
Date: 2026-08-29
File: platform.lua
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

-- Construct a structured diagnostic without throwing or formatting its optional fields.
--@param code string Stable diagnostic code used by callers to choose recovery behavior.
--@param detail any|nil Optional underlying cause or contextual diagnostic data; retained as supplied.
--@return table New diagnostic record; optional non-nil fields are retained without deep copying.
local function failure(code, detail)
    return { code = code, detail = detail }
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
    --@field __metatable string Hides this metatable behind the fixed "locked" marker.
    --@field __tostring function Displays the supplied diagnostic label.
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
        __metatable = "locked",
        -- Display the stable proxy label without exposing backing fields.
        --@param none The proxy operand supplied by tostring is ignored.
        --@return string Supplied label, or "readonly value" when it is absent.
        __tostring = function()
            return label or "readonly value"
        end,
    })
end

-- Normalize an exact native OS/architecture pair to a declared package target.
--@param observation any Native probe result containing only canonical os and arch fields.
--@return table|nil Normalized os, arch and target fields; nil on invalid or unsupported input.
--@return table|nil Structured shape, unexpected-field or unsupported-platform error.
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
--@param native table Native port exposing platform_identity().
--@param release_target string One of the release manifest target names.
--@return table|nil service Immutable service exposing identity().
--@return table|nil err Structured validation or probe failure.
function M.new(native, release_target)
    if type(native) ~= "table" or type(native.platform_identity) ~= "function" then
        return nil, failure("InvalidPlatformPort", "platform_identity function is required")
    end
    if type(release_target) ~= "string" or not RELEASE_TARGETS[release_target] then
        return nil, failure("UnknownReleaseTarget", tostring(release_target))
    end

    local attempted = false
    local cached_identity, cached_error

    -- Probe the package identity once and retain either its normalized facts or its failure.
    --@param none No arguments; uses the native probe and release target captured at construction.
    --@return table|nil Read-only platform facts with supported indicating a package-target match.
    --@return table|nil Cached probe or validation failure; nil after a successful observation.
    --@effect Invokes native.platform_identity at most once, including when that invocation fails.
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
