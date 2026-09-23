--[[
Author: WaterRun
Date: 2026-09-23
File: network_target_test.lua
Description: Keeps curl carrier evidence separate from target release qualification.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()
local fake_filesystem = assert(loadfile(
    YACA_TEST_ROOT .. "/test/support/fake_filesystem.lua",
    "t",
    _ENV
))()

-- Load one source module under an isolated dependency cache for qualification tests.
--@param name string Source module basename.
--@param cache table|nil Shared cache for this load graph.
--@return any Module value returned by the source chunk.
local function load_module(name, cache)
    cache = cache or {}
    if cache[name] then return cache[name] end
    local environment = {}
    for key, value in pairs(_ENV) do environment[key] = value end
    -- Resolve a source dependency through the same isolated module cache.
    --@param dependency string Required module basename.
    --@return any Loaded dependency value.
    environment.require = function(dependency)
        return load_module(dependency, cache)
    end
    environment._G = environment
    --@metatable isolated_test_environment Falls back to suite globals for read access;
    -- explicit fields remain mutable only within this test loader.
    --@field __index table Parent test environment used for absent keys.
    setmetatable(environment, { __index = _ENV })
    local chunk, load_error = loadfile(
        YACA_TEST_ROOT .. "/src/" .. name .. ".lua",
        "t",
        environment
    )
    A.truthy(chunk, load_error)
    local value = chunk()
    cache[name] = value
    return value
end

-- Build bounded carrier options for a supplied curl executable path.
--@param curl_path string Candidate absolute or relative executable path.
--@return table Network factory options with test-local paths.
local function options(curl_path)
    return {
        curl_executable = curl_path,
        bundled_ca_path = YACA_TEST_ROOT .. "/bin/cacert.pem",
        temporary_directory = YACA_TEST_ROOT .. "/.qualification-private-temp",
        private_permissions = 384,
        maximum_body_bytes = 1024,
        maximum_header_bytes = 1024,
        maximum_config_bytes = 4096,
        maximum_output_bytes = 4096,
        maximum_io_chunk_bytes = 128,
        maximum_attempt_id_bytes = 32,
        maximum_connect_timeout_ms = 10000,
        maximum_total_timeout_ms = 60000,
        component_environment = { LC_ALL = "C" },
    }
end

-- Provide inert filesystem/process dependencies for metadata-only checks.
--@param none No parameters.
--@return table Network factory port map.
local function ports()
    local filesystem = fake_filesystem.new(nil, 128)
    return {
        filesystem = filesystem,
        processes = {
            -- Reject any unexpected child-process creation in metadata tests.
            --@param none No parameters.
            --@return nil Does not return normally.
            --@error Always raises when network I/O is attempted.
            new_component_port = function()
                error("qualification metadata test must not start curl")
            end,
        },
    }
end

return {
    name = "qualification/network-target",
    cases = {
        {
            name = "carrier candidate never self-declares target qualification",
            -- Check fixed curl arguments and an honest pending target-qualification flag.
            --@param none No parameters.
            --@return nil Assertions raise on failure.
            run = function()
                local network = load_module("network")
                local service = assert(network.new(
                    ports(),
                    options(YACA_TEST_ROOT .. "/bin/curl")
                ))
                A.equal(service.capabilities.first_option, "--disable")
                A.equal(service.capabilities.fixed_arguments[1], "--disable")
                A.equal(service.capabilities.config_carrier, "anonymous-stdin-pipe")
                A.falsy(service.capabilities.secret_in_argv)
                A.falsy(service.capabilities.secret_in_environment)
                A.falsy(service.capabilities.target_qualified)
                A.contains(service.capabilities.qualification, "three-edition-target-qualification-pending")
                -- Attempt to mutate the published fixed curl argv snapshot.
                --@param none No parameters.
                --@return nil Does not return normally when proxy is locked.
                --@error Raises the read-only proxy assignment error.
                A.raises(function()
                    service.capabilities.fixed_arguments[1] = "--config"
                end, "cannot be modified")
            end,
        },
        {
            name = "relative or caller-qualified curl component is rejected",
            -- Reject relative paths and caller-supplied qualification claims.
            --@param none No parameters.
            --@return nil Assertions raise on failure.
            run = function()
                local network = load_module("network")
                local rejected, path_error = network.new(ports(), options("bin/curl"))
                A.falsy(rejected)
                A.equal(path_error.code, "InvalidNetworkPath")

                local self_qualified = options(YACA_TEST_ROOT .. "/bin/curl")
                self_qualified.target_qualified = true
                local second, option_error = network.new(ports(), self_qualified)
                A.falsy(second)
                A.equal(option_error.code, "InvalidNetworkOptions")
            end,
        },
        {
            name = "release manifest locks sources while every target artifact stays pending",
            -- Keep source pins separate from still-pending target artifacts.
            --@param none No parameters.
            --@return nil Assertions raise on failure.
            run = function()
                local manifest = assert(loadfile(
                    YACA_TEST_ROOT .. "/release/manifest.lua",
                    "t",
                    _ENV
                ))()
                A.equal(manifest.release_state, "unqualified")
                A.falsy(manifest.release_authorized)
                A.falsy(manifest.target_qualification_complete)
                A.equal(manifest.dependencies.curl.version, "8.21.0")
                A.equal(manifest.dependencies.mbedtls.version, "3.6.7")
                A.equal(manifest.dependencies.ca_bundle.version, "2026-08-13")
                local expected_status = {
                    curl = "source-and-patch-pinned-target-artifact-pending",
                    mbedtls = "source-and-patch-pinned-target-artifact-pending",
                    ca_bundle = "source-pinned-target-artifact-pending",
                }
                for _, dependency in ipairs({ "curl", "mbedtls", "ca_bundle" }) do
                    A.equal(
                        manifest.dependencies[dependency].status,
                        expected_status[dependency]
                    )
                    A.matches(manifest.dependencies[dependency].sha256, "^[0-9a-f]+$")
                    A.equal(#manifest.dependencies[dependency].sha256, 64)
                end
                local expected = {
                    { "win32-x86", "windows", "x86", "Windows XP SP3" },
                    { "win64-x86_64", "windows", "x86_64", "Windows 7 SP1" },
                    { "linux-x86_64", "linux", "x86_64", "CentOS 7 x86_64" },
                }
                for index, values in ipairs(expected) do
                    local target = manifest.targets[index]
                    A.equal(target.id, values[1])
                    A.equal(target.os, values[2])
                    A.equal(target.arch, values[3])
                    A.equal(target.minimum, values[4])
                    A.equal(target.qualification, "pending")
                end
            end,
        },
    },
}
