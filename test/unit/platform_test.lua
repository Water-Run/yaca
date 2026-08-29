--[[
File: platform_test.lua
Date: 2026-08-29
Author: WaterRun
Description: Verifies normalized immutable platform identities and failures.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()
local fake_native = assert(loadfile(YACA_TEST_ROOT .. "/test/support/fake_native.lua", "t", _ENV))()
local manifest = assert(loadfile(YACA_TEST_ROOT .. "/release/manifest.lua", "t", _ENV))()
local loader_module = assert(loadfile(YACA_TEST_ROOT .. "/.tools/check_loader.lua", "t", _ENV))()
local secure_loader = assert(loader_module.new(manifest, YACA_TEST_ROOT))
local platform = secure_loader:require_lua("platform")

local function identity_fields(identity)
    local fields = {}
    for key in pairs(identity) do fields[#fields + 1] = key end
    table.sort(fields)
    return fields
end

return {
    name = "unit/platform",
    cases = {
        {
            name = "identity is canonical immutable and probed once",
            run = function()
                local native = fake_native.platform({ os = "windows", arch = "x86" })
                local service = assert(platform.new(native, "win32-x86"))
                local first = assert(service.identity())
                local second = assert(service.identity())
                A.equal(first, second)
                A.equal(native.call_count(), 1)
                A.deep_equal(identity_fields(first), { "arch", "os", "supported", "target" })
                A.equal(first.os, "windows")
                A.equal(first.arch, "x86")
                A.equal(first.target, "win32-x86")
                A.truthy(first.supported)
                A.raises(function() first.os = "linux" end, "cannot be modified")
                A.raises(function() service.identity = false end, "cannot be modified")
            end,
        },
        {
            name = "all release identities map exactly",
            run = function()
                local vectors = {
                    { "windows", "x86", "win32-x86" },
                    { "windows", "x86_64", "win64-x86_64" },
                    { "linux", "x86_64", "linux-x86_64" },
                }
                for _, vector in ipairs(vectors) do
                    local service = assert(platform.new(fake_native.platform({ os = vector[1], arch = vector[2] }), vector[3]))
                    local identity = assert(service.identity())
                    A.equal(identity.target, vector[3])
                    A.truthy(identity.supported)
                end
            end,
        },
        {
            name = "recognized runtime mismatch is explicit and unsupported",
            run = function()
                local service = assert(platform.new(fake_native.platform({ os = "linux", arch = "x86_64" }), "win64-x86_64"))
                local identity = assert(service.identity())
                A.equal(identity.target, "linux-x86_64")
                A.falsy(identity.supported)
            end,
        },
        {
            name = "unknown release target is rejected before probing",
            run = function()
                local native = fake_native.platform({ os = "linux", arch = "x86_64" })
                local service, platform_error = platform.new(native, "linux-arm64")
                A.falsy(service)
                A.equal(platform_error.code, "UnknownReleaseTarget")
                A.equal(native.call_count(), 0)
            end,
        },
        {
            name = "unknown observation fields including OS version are rejected",
            run = function()
                local native = fake_native.platform({ os = "windows", arch = "x86", version = "5.1" })
                local service = assert(platform.new(native, "win32-x86"))
                local identity, platform_error = service.identity()
                A.falsy(identity)
                A.equal(platform_error.code, "UnexpectedPlatformField")
                A.equal(platform_error.detail, "version")
                local again, same_error = service.identity()
                A.falsy(again)
                A.equal(same_error, platform_error)
                A.equal(native.call_count(), 1)
            end,
        },
        {
            name = "unknown OS or architecture fails closed",
            run = function()
                for _, observation in ipairs({
                    { os = "macos", arch = "x86_64" },
                    { os = "linux", arch = "arm64" },
                    { os = "Windows", arch = "x86" },
                }) do
                    local service = assert(platform.new(fake_native.platform(observation), "linux-x86_64"))
                    local identity, platform_error = service.identity()
                    A.falsy(identity)
                    A.equal(platform_error.code, "UnsupportedPlatform")
                end
            end,
        },
        {
            name = "native absence exceptions and malformed results are typed",
            run = function()
                local service, port_error = platform.new({}, "linux-x86_64")
                A.falsy(service)
                A.equal(port_error.code, "InvalidPlatformPort")

                local missing = assert(platform.new(fake_native.platform(nil, "no platform API"), "linux-x86_64"))
                local missing_identity, missing_error = missing.identity()
                A.falsy(missing_identity)
                A.equal(missing_error.code, "PlatformProbeFailed")
                A.contains(missing_error.detail, "no platform API")

                local throwing_native = fake_native.platform(function() error("probe exploded") end)
                local throwing = assert(platform.new(throwing_native, "linux-x86_64"))
                local throwing_identity, throwing_error = throwing.identity()
                A.falsy(throwing_identity)
                A.equal(throwing_error.code, "PlatformProbeFailed")
                A.contains(throwing_error.detail, "probe exploded")

                local malformed = assert(platform.new(fake_native.platform("linux/x64"), "linux-x86_64"))
                local malformed_identity, malformed_error = malformed.identity()
                A.falsy(malformed_identity)
                A.equal(malformed_error.code, "InvalidPlatformIdentity")
            end,
        },
    },
}
