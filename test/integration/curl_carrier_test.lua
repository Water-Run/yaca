--[[
Author: WaterRun
Date: 2026-09-23
File: curl_carrier_test.lua
Description: Verifies curl secret carriers, private files, isolation, and cleanup.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()
local fake_filesystem = assert(loadfile(
    YACA_TEST_ROOT .. "/test/support/fake_filesystem.lua",
    "t",
    _ENV
))()

--Loads a source module into an isolated per-case environment.
--@param name string Module, Model, or resource name selected by the case.
--@param cache table Per-case module cache preserving isolated imports.
--@return any module Module export loaded in the isolated source environment.
local function load_module(name, cache)
    cache = cache or {}
    if cache[name] then return cache[name] end
    local environment = {}
    for key, value in pairs(_ENV) do environment[key] = value end
    --Resolves an imported Lua module through the isolated test loader.
    --@param dependency string Source module requested from the isolated loader.
    --@return any value Callback value consumed by the enclosing scenario assertion.
    environment.require = function(dependency)
        return load_module(dependency, cache)
    end
    environment._G = environment
    --@metatable environment Test-owned lookup and mutation contract for the current case.
    --@field __index any Fallback table or function used for missing fixture keys.
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

local TEMP = "/private/network"
local CURL = "/release/components/curl"
local CA = "/release/ca/cacert.pem"
local SECRET = "yaca-config-key-0001"

--Supplies secret source behavior required by this suite.
--@param secret string Secret value used only inside the fixture.
--@param eligible any The eligible supplied to the fake service for this scenario.
--@return table observed Typed error record with code SecretDestinationDenied.
local function secret_source(secret, eligible)
    return {
        --Supplies secret descriptors behavior required by this suite.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return table record Fixture record emitted by the scenario callback.
        secret_descriptors = function()
            return {
                {
                    id = "Model.Main.Key",
                    class = "model-key",
                    scan_eligible = eligible ~= false,
                },
            }
        end,
        --Simulates the reveal secret boundary for this suite.
        --@param id string|integer Identity selected for the fake operation.
        --@param destination string|table Publication destination selected by the case.
        --@return any|nil value Callback value consumed by the enclosing scenario assertion.
        --@return table|nil secondary2 Typed error record with code SecretDestinationDenied.
        reveal_secret = function(id, destination)
            if id ~= "Model.Main.Key" or destination ~= "model-auth:Main" then
                return nil, { code = "SecretDestinationDenied", message = "denied" }
            end
            return secret
        end,
        --Simulates the scan registered secrets boundary for this suite.
        --@param bytes string Byte chunk supplied to the fake I/O port.
        --@return table record Fixture record emitted by the scenario callback.
        scan_registered_secrets = function(bytes)
            local first = bytes:find(secret, 1, true)
            if not first or eligible == false then return {} end
            return {
                {
                    id = "Model.Main.Key",
                    class = "model-key",
                    offset = first,
                    length = #secret,
                },
            }
        end,
    }
end

--Supplies attempt behavior required by this suite.
--@param overrides table|nil Per-case overrides of default fixture behavior.
--@return any observed attempt value observed by the scenario assertion.
local function attempt(overrides)
    local result = {
        attempt_id = "attemptA",
        url = "https://api.example.invalid/v1/messages",
        method = "POST",
        public_headers = {
            { name = "Content-Type", value = "application/json" },
            { name = "X-Protocol-Version", value = "2026-08-29" },
        },
        secret_headers = {
            {
                name = "Authorization",
                prefix = "Bearer ",
                secret_id = "Model.Main.Key",
                destination = "model-auth:Main",
            },
        },
        body = '{"messages":[{"role":"user","content":"hello"}]}',
        secret_source = secret_source(SECRET),
        proxy = { mode = "off" },
        connect_timeout_ms = 2000,
        total_timeout_ms = 10000,
    }
    for key, value in pairs(overrides or {}) do result[key] = value end
    return result
end

--Supplies network options behavior required by the 'Authorization' case.
--@param overrides table|nil Per-case overrides of default fixture behavior.
--@return any observed network options value observed by the scenario assertion.
local function network_options(overrides)
    local result = {
        curl_executable = CURL,
        bundled_ca_path = CA,
        temporary_directory = TEMP,
        private_permissions = 384,
        maximum_body_bytes = 2048,
        maximum_header_bytes = 1024,
        maximum_config_bytes = 4096,
        maximum_output_bytes = 2048,
        maximum_io_chunk_bytes = 128,
        maximum_attempt_id_bytes = 32,
        maximum_connect_timeout_ms = 10000,
        maximum_total_timeout_ms = 60000,
        component_environment = {
            PATH = "/release/components",
            HOME = "/host/home",
            LC_ALL = "C",
            HTTP_PROXY = SECRET,
            https_proxy = SECRET,
            CURL_HOME = SECRET,
            CURL_CA_BUNDLE = SECRET,
            SSL_CERT_FILE = SECRET,
            NETRC = SECRET,
            LUA_PATH = SECRET,
            CUSTOM = SECRET,
        },
    }
    for key, value in pairs(overrides or {}) do result[key] = value end
    return result
end

--Constructs make fixture for the Authorization scenario.
--@param initial any The initial supplied to the fake service for this scenario.
--@param native_options any The native options supplied to the fake service for this scenario.
--@param option_overrides table|nil Per-case overrides of default options.
--@return table created Constructed make fixture fixture value.
local function make_fixture(initial, native_options, option_overrides)
    local process = load_module("process")
    local network = load_module("network")
    local filesystem, controls = fake_filesystem.new(initial, 128)
    local native = {
        calls = {},
        batches = {},
        result = {
            outcome = "completed",
            exit_kind = "exit-code",
            exit_code = 0,
            duration_ms = 12,
            descendants_proven_stopped = true,
        },
    }
    native_options = native_options or {}

    --Simulates process start in the Authorization fixture.
    --@param request table Request delivered to the fake component.
    --@return boolean accepted Whether process start succeeds in the fixture.
    --@return table secondary2 Structured fixture record selected by the exercised branch.
    function native.process_start(request)
        native.calls.start = request
        if native_options.fail_start then
            return false, {
                code = "SpawnFailed",
                message = "curl rejected " .. SECRET,
            }
        end
        if native_options.replace_body then
            controls.external_replace(
                TEMP .. "/yaca-curl-attemptA.body.tmp",
                "foreign-body"
            )
        end
        if native_options.write_headers ~= false then
            A.truthy(controls.external_write(
                TEMP .. "/yaca-curl-attemptA.headers.tmp",
                "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n\r\n"
            ))
        end
        return true, { process = "curl" }
    end

    --Simulates process poll in the Authorization fixture.
    --@param _ any Unused callback argument supplied by the port.
    --@param _ any Unused callback argument supplied by the port.
    --@param budget integer|table Resource budget applied by the scenario.
    --@return boolean accepted Whether process poll succeeds in the fixture.
    --@return any secondary2 Event batch returned by the fixture.
    function native.process_poll(_, _, budget)
        local batch = table.remove(native.batches, 1) or {}
        A.truthy(#batch <= budget)
        return true, batch
    end

    --Simulates process cancel in the Authorization fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether process cancel succeeds in the fixture.
    --@return boolean secondary2 True acknowledgment from the fake port.
    function native.process_cancel()
        native.calls.cancel = (native.calls.cancel or 0) + 1
        return true, true
    end

    --Simulates process join in the Authorization fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether process join succeeds in the fixture.
    --@return any secondary2 Additional status or structured error from the fixture operation.
    function native.process_join()
        return true, native.result
    end

    --Simulates process close in the Authorization fixture.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether process close succeeds in the fixture.
    --@return boolean secondary2 True acknowledgment from the fake port.
    function native.process_close()
        native.calls.close = true
        return true, true
    end

    local processes = assert(process.new(native, {
        maximum_output_bytes = 4096,
        maximum_poll_bytes = 512,
        maximum_stdin_bytes = 8192,
        maximum_arguments = 16,
        maximum_argument_bytes = 1024,
        shell = {
            kind = "linux",
            executable = "/bin/sh",
            fixed_arguments = { "-c" },
        },
    }))
    local service = assert(network.new({
        filesystem = filesystem,
        processes = processes,
    }, network_options(option_overrides)))
    return {
        service = service,
        controls = controls,
        native = native,
    }
end

--Supplies secret locations behavior required by the 'Authorization' case.
--@param value any Candidate whose acceptance or transformation the test checks.
--@param secret string Secret value used only inside the fixture.
--@param path string File or Context path exercised by the case.
--@param hits any The hits supplied to the fake service for this scenario.
--@param visited any The visited supplied to the fake service for this scenario.
--@return any observed secret locations value observed by the scenario assertion.
local function secret_locations(value, secret, path, hits, visited)
    hits, visited = hits or {}, visited or {}
    if type(value) == "string" then
        if value:find(secret, 1, true) then hits[#hits + 1] = path end
        return hits
    end
    if type(value) ~= "table" or visited[value] then return hits end
    visited[value] = true
    for key, item in pairs(value) do
        secret_locations(key, secret, path .. ".<key>", hits, visited)
        secret_locations(item, secret, path .. "." .. tostring(key), hits, visited)
    end
    return hits
end

return {
    name = "integration/curl-carrier",
    cases = {
        {
            name = "curl carriers use finalized close timestamps through cleanup",
            -- Complete a curl attempt when each created carrier changes timestamp at close.
            --@param none No arguments.
            --@return nil Assertions complete without returning a value.
            --@effect Runs the fake process port and removes only its fixture carriers.
            run = function()
                local fixture = make_fixture()
                fixture.controls.close_updates_modified = true
                local port = assert(fixture.service.new_attempt(attempt()))
                assert(port:start(100))
                local result = port:join(1000)
                A.equal(result.outcome, "completed")
                assert(port:close())
                A.falsy(fixture.controls.exists(TEMP .. "/yaca-curl-attemptA.body.tmp"))
                A.falsy(fixture.controls.exists(TEMP .. "/yaca-curl-attemptA.headers.tmp"))
            end,
        },
        {
            name = "secret exists only in anonymous config stdin and curl invocation is fixed",
            --Verifies secret exists only in anonymous config stdin and curl invocation is fixed.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify secret exists only in anonymous config stdin and curl invocation is fixed.
            run = function()
                local fixture = make_fixture()
                fixture.native.batches = {
                    {
                        { kind = "stdout", bytes = "data: ok\n\n" },
                        { kind = "stderr", bytes = "diagnostic " .. SECRET },
                        { kind = "terminal", outcome = "completed" },
                    },
                }
                local port = assert(fixture.service.new_attempt(attempt()))
                A.truthy(port:start(100))

                local request = fixture.native.calls.start
                A.equal(request.mode, "argv")
                A.equal(request.executable, CURL)
                A.deep_equal(request.arguments, {
                    "--disable", "--silent", "--show-error", "--no-buffer", "--config", "-",
                })
                A.equal(request.arguments[1], "--disable")
                A.falsy(request.shell)
                A.falsy(request.command)
                A.equal(request.environment_mode, "clean")
                A.equal(request.stdin.kind, "bytes")
                A.equal(request.stdin.carrier, "anonymous-pipe")
                A.deep_equal(secret_locations(request, SECRET, "request"), {
                    "request.stdin.bytes",
                })
                A.equal(request.environment.LC_ALL, "C")
                A.equal(request.environment.PATH, "/release/components")
                A.equal(request.environment.HOME, "/host/home")
                A.falsy(request.environment.HTTP_PROXY)
                A.falsy(request.environment.https_proxy)
                A.falsy(request.environment.CURL_HOME)
                A.falsy(request.environment.CURL_CA_BUNDLE)
                A.falsy(request.environment.SSL_CERT_FILE)
                A.falsy(request.environment.NETRC)
                A.falsy(request.environment.LUA_PATH)
                A.falsy(request.environment.CUSTOM)

                local config = request.stdin.bytes
                A.contains(config, 'header = "Authorization: Bearer ' .. SECRET .. '"')
                A.contains(config, 'data-binary = "@' .. TEMP .. '/yaca-curl-attemptA.body.tmp"')
                A.contains(config, 'dump-header = "' .. TEMP .. '/yaca-curl-attemptA.headers.tmp"')
                A.contains(config, 'retry = "0"')
                A.contains(config, "no-retry-all-errors\n")
                A.contains(config, "no-location\n")
                A.contains(config, 'max-redirs = "0"')
                A.contains(config, 'proto = "=http,https"')
                A.contains(config, "http1.1\n")
                A.contains(config, "tlsv1.2\n")
                A.contains(config, "proxy-tlsv1\n")
                A.contains(config, "no-insecure\n")
                A.contains(config, "no-proxy-insecure\n")
                A.contains(config, "no-compressed\n")
                A.contains(config, "no-netrc\n")
                A.falsy(config:find(" = true", 1, true))
                A.falsy(config:find(" = false", 1, true))
                A.contains(config, 'proxy = ""')
                A.contains(config, 'noproxy = "*"')
                A.contains(config, 'cacert = "' .. CA .. '"')
                A.contains(config, 'proxy-cacert = "' .. CA .. '"')

                local body_path = TEMP .. "/yaca-curl-attemptA.body.tmp"
                local header_path = TEMP .. "/yaca-curl-attemptA.headers.tmp"
                A.equal(fixture.controls.permissions(body_path), 384)
                A.equal(fixture.controls.permissions(header_path), 384)
                A.equal(fixture.controls.bytes(body_path), attempt().body)
                A.falsy(fixture.controls.bytes(body_path):find(SECRET, 1, true))
                A.falsy(fixture.controls.bytes(header_path):find(SECRET, 1, true))

                local collision = assert(fixture.service.new_attempt(attempt()))
                --Executes the action expected to raise in the 'secret exists only in anonymous config stdin and curl invocation is fixed' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify secret exists only in anonymous config stdin and curl invocation is fixed.
                local collision_error = A.raises(function() collision:start(101) end, "DestinationExists")
                A.falsy(collision_error:find(SECRET, 1, true))
                A.equal(fixture.controls.bytes(body_path), attempt().body)

                local events = port:poll(102, 3)
                A.deep_equal(events[1], { kind = "body_chunk", bytes = "data: ok\n\n" })
                A.deep_equal(events[2], { kind = "diagnostic_progress" })
                A.equal(events[3].kind, "transport_terminal")
                local result = port:join(110)
                A.equal(result.response_body, "data: ok\n\n")
                A.contains(result.response_headers, "HTTP/1.1 200 OK")
                A.contains(result.diagnostic, "[registered-secret]")
                A.falsy(result.diagnostic:find(SECRET, 1, true))
                A.falsy(fixture.controls.exists(body_path))
                A.falsy(fixture.controls.exists(header_path))
                A.truthy(port:close())
                A.truthy(fixture.native.calls.close)
            end,
        },
        {
            name = "header collision preserves foreign file and rolls back request body",
            --Verifies header collision preserves foreign file and rolls back request body.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify header collision preserves foreign file and rolls back request body.
            run = function()
                local header_path = TEMP .. "/yaca-curl-collision.headers.tmp"
                local fixture = make_fixture({ [header_path] = "foreign-header" })
                local port = assert(fixture.service.new_attempt(attempt({
                    attempt_id = "collision",
                })))
                --Executes the action expected to raise in the 'header collision preserves foreign file and rolls back request body' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify header collision preserves foreign file and rolls back request body.
                local raised = A.raises(function() port:start(1) end, "DestinationExists")
                A.falsy(raised:find(SECRET, 1, true))
                A.equal(fixture.controls.bytes(header_path), "foreign-header")
                A.falsy(fixture.controls.exists(TEMP .. "/yaca-curl-collision.body.tmp"))
                A.falsy(fixture.native.calls.start)
            end,
        },
        {
            name = "ordinary body cannot smuggle a registered config secret to disk",
            --Verifies header collision preserves foreign file and rolls back request body.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify header collision preserves foreign file and rolls back request body.
            run = function()
                local fixture = make_fixture()
                local port = assert(fixture.service.new_attempt(attempt({
                    attempt_id = "bodysecret",
                    body = '{"message":"' .. SECRET .. '"}',
                })))
                --Executes the action expected to raise in the 'ordinary body cannot smuggle a registered config secret to disk' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify header collision preserves foreign file and rolls back request body.
                local raised = A.raises(function() port:start(1) end, "RegisteredSecretInRequest")
                A.falsy(raised:find(SECRET, 1, true))
                A.falsy(fixture.controls.exists(TEMP .. "/yaca-curl-bodysecret.body.tmp"))
                A.falsy(fixture.native.calls.start)
            end,
        },
        {
            name = "short or unknown secret is consumer-ineligible before carrier creation",
            --Verifies ordinary body cannot smuggle a registered config secret to disk.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify ordinary body cannot smuggle a registered config secret to disk.
            run = function()
                local short = "short"
                local fixture = make_fixture()
                local port = assert(fixture.service.new_attempt(attempt({
                    attempt_id = "shortkey",
                    secret_source = secret_source(short, false),
                })))
                --Executes the action expected to raise in the 'short or unknown secret is consumer-ineligible before carrier creation' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify ordinary body cannot smuggle a registered config secret to disk.
                local raised = A.raises(function() port:start(1) end, "SecretConsumerIneligible")
                A.falsy(raised:find(short, 1, true))
                A.falsy(fixture.controls.exists(TEMP .. "/yaca-curl-shortkey.body.tmp"))
                A.falsy(fixture.native.calls.start)
            end,
        },
        {
            name = "spawn error is redacted and both private carriers are removed",
            --Verifies short or unknown secret is consumer-ineligible before carrier creation.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify short or unknown secret is consumer-ineligible before carrier creation.
            run = function()
                local fixture = make_fixture(nil, { fail_start = true })
                local port = assert(fixture.service.new_attempt(attempt({
                    attempt_id = "spawnfail",
                })))
                --Executes the action expected to raise in the 'spawn error is redacted and both private carriers are removed' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify short or unknown secret is consumer-ineligible before carrier creation.
                local raised = A.raises(function() port:start(1) end, "SpawnFailed")
                A.falsy(raised:find(SECRET, 1, true))
                A.contains(raised, "[registered-secret]")
                A.falsy(fixture.controls.exists(TEMP .. "/yaca-curl-spawnfail.body.tmp"))
                A.falsy(fixture.controls.exists(TEMP .. "/yaca-curl-spawnfail.headers.tmp"))
            end,
        },
        {
            name = "identity race is detected without deleting a foreign replacement",
            --Verifies spawn error is redacted and both private carriers are removed.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify spawn error is redacted and both private carriers are removed.
            run = function()
                local fixture = make_fixture(nil, { replace_body = true })
                fixture.native.batches = {
                    { { kind = "terminal", outcome = "completed" } },
                }
                local port = assert(fixture.service.new_attempt(attempt()))
                port:start(1)
                port:poll(2, 1)
                --Executes the action expected to raise in the 'identity race is detected without deleting a foreign replacement' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify spawn error is redacted and both private carriers are removed.
                local raised = A.raises(function() port:join(3) end, "CarrierChanged")
                A.falsy(raised:find(SECRET, 1, true))
                A.equal(
                    fixture.controls.bytes(TEMP .. "/yaca-curl-attemptA.body.tmp"),
                    "foreign-body"
                )
                A.falsy(fixture.controls.exists(TEMP .. "/yaca-curl-attemptA.headers.tmp"))
            end,
        },
    },
}
