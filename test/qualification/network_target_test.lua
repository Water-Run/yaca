--[[
File: network_target_test.lua
Date: 2026-08-29
Author: WaterRun
Description: Keeps curl carrier evidence separate from target release qualification.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()
local fake_filesystem = assert(loadfile(
    YACA_TEST_ROOT .. "/test/support/fake_filesystem.lua",
    "t",
    _ENV
))()

local function load_module(name, cache)
    cache = cache or {}
    if cache[name] then return cache[name] end
    local environment = {}
    for key, value in pairs(_ENV) do environment[key] = value end
    environment.require = function(dependency)
        return load_module(dependency, cache)
    end
    environment._G = environment
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

local function ports()
    local filesystem = fake_filesystem.new(nil, 128)
    return {
        filesystem = filesystem,
        processes = {
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
                A.contains(service.capabilities.qualification, "target-curl-tls-proxy-ca-pending")
                A.raises(function()
                    service.capabilities.fixed_arguments[1] = "--config"
                end, "cannot be modified")
            end,
        },
        {
            name = "relative or caller-qualified curl component is rejected",
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
            name = "release manifest keeps every old-system target and curl lock pending",
            run = function()
                local manifest = assert(loadfile(
                    YACA_TEST_ROOT .. "/release/manifest.lua",
                    "t",
                    _ENV
                ))()
                A.equal(manifest.release_state, "unqualified")
                A.falsy(manifest.release_authorized)
                A.equal(manifest.dependencies.curl.status, "target-lock-pending")
                A.equal(manifest.dependencies.ca_bundle.status, "target-lock-pending")
                A.deep_equal(manifest.targets, {
                    {
                        id = "win32-x86",
                        os = "windows",
                        arch = "x86",
                        qualification = "pending",
                    },
                    {
                        id = "win64-x86_64",
                        os = "windows",
                        arch = "x86_64",
                        qualification = "pending",
                    },
                    {
                        id = "linux-x86_64",
                        os = "linux",
                        arch = "x86_64",
                        qualification = "pending",
                    },
                })
            end,
        },
    },
}
