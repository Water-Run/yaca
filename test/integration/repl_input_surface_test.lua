--[[
File: repl_input_surface_test.lua
Date: 2026-09-14
Author: WaterRun
Description: Verifies each interactive surface reports its own cancellation code.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

local function load_module(name, cache)
    cache = cache or {}
    if cache[name] then return cache[name] end
    local environment = { require = function(dependency)
        return load_module(dependency, cache)
    end }
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

local function load_table(relative_path)
    local chunk, load_error = loadfile(YACA_TEST_ROOT .. "/" .. relative_path, "t", _ENV)
    A.truthy(chunk, load_error)
    return chunk()
end

local main = load_module("main")
local cli = load_module("cli")
local config = load_module("config")
local sha256 = load_table("test/support/sha256_reference.lua")
local fake_filesystem = load_table("test/support/fake_filesystem.lua")

local CONFIG_PATH = "/data/config.ini"

local function hash_port()
    local port = {}
    function port.sha256_start() return { parts = {}, finished = false, closed = false } end
    function port.sha256_update(handle, bytes)
        assert(not handle.finished and not handle.closed)
        handle.parts[#handle.parts + 1] = bytes
        return true
    end
    function port.sha256_finish(handle)
        assert(not handle.finished and not handle.closed)
        handle.finished = true
        return sha256.digest(table.concat(handle.parts))
    end
    function port.sha256_close(handle)
        assert(not handle.closed)
        handle.closed = true
        return true
    end
    return port
end

local function options()
    return {
        schema_version = "0.1.0",
        release_ca_path = "/opt/yaca/cacert.pem",
        ini_limits = {
            maximum_bytes = 65536,
            maximum_lines = 512,
            maximum_line_bytes = 4096,
            maximum_value_bytes = 16384,
        },
        hard_limits = {
            queue_items = 64,
            turn_model_requests = 64,
            turn_tool_calls = 256,
            connect_timeout_ms = 120000,
            response_bytes = 16777216,
            exec_timeout_ms = 3600000,
            exec_output_kb = 8192,
            auto_name_turns = 100000,
            recent_contexts = 10000,
            model_context_tokens = 2000000,
            model_output_tokens = 131072,
            request_timeout_ms = 3600000,
            retry_count = 10,
            retry_base_delay_ms = 60000,
        },
        runtime_defaults = { retry_count = 2 },
        maximum_text_bytes = 16384,
        maximum_name_bytes = 128,
        maximum_adapter_options_bytes = 4096,
        maximum_hash_chunk_bytes = 11,
        minimum_scannable_secret_bytes = 8,
    }
end

local function source()
    return table.concat({
        "[General]",
        "SchemaVersion = 0.1.0",
        "LogLevel = info",
        "",
        "[Agent]",
        "QueueMaxItems = 9",
        "",
        "[Permission.Std]",
        "Read = allow",
        "Write = confirm",
        "Delete = confirm",
        "Shell = confirm",
        "OutsideWorkspace = confirm",
        "",
        "[Model.Primary]",
        "Enabled = true",
        "Protocol = openai-chat",
        'Endpoint = "https://api.example/v1/chat"',
        'RemoteModel = "remote-main"',
        'Key = "example-secret-value"',
        "",
    }, "\n")
end

---Terminal double emitting one scripted event batch per poll.
-- The contract mirrors the production port: start/poll/cancel/close, with
-- `user_action` and `io_terminal` events.
local function scripted_terminal(batches)
    local index = 0
    local terminal = { started = false, closed = false, cancelled = false }
    function terminal.start(self, now)
        A.equal(math.type(now), "integer")
        A.falsy(self.started)
        self.started = true
        return true
    end
    function terminal.poll(self, now, budget)
        A.truthy(self.started)
        A.equal(math.type(now), "integer")
        A.truthy(budget > 0)
        index = index + 1
        return batches[index] or { { kind = "io_terminal" } }
    end
    function terminal.cancel(self, now)
        A.equal(math.type(now), "integer")
        self.cancelled = true
        return true
    end
    function terminal.join(self, now)
        A.equal(math.type(now), "integer")
        self.joined = true
        return {}
    end
    function terminal.close(self)
        self.closed = true
        return true
    end
    return terminal
end

local function harness(batches)
    local filesystem = fake_filesystem.new({ [CONFIG_PATH] = source() })
    local service = assert(config.new({
        sha256 = hash_port(),
        filesystem = filesystem,
    }, options()))
    local terminals, ticks, written = {}, 0, {}
    local composed = {
        config = service,
        layout = { config_path = CONFIG_PATH },
        backend = {
            new_terminal = function(mode)
                local terminal = scripted_terminal(batches)
                terminal.mode = mode
                terminals[#terminals + 1] = terminal
                return terminal
            end,
            clock_port = {
                monotonic_now = function()
                    ticks = ticks + 1
                    return ticks
                end,
                sleep_ms = function() return true end,
            },
            system = { secure_random = function(count) return string.rep("\0", count) end },
        },
    }
    local runtime = {
        cli = assert(cli.new({ platform = "linux" })),
        stdout = function(bytes)
            written[#written + 1] = bytes
            return true
        end,
    }
    return composed, runtime, terminals, written
end

return {
    name = "integration/repl-input-surface",
    cases = {
        {
            name = "configuration editor reports its own cancellation code and restores the terminal",
            run = function()
                local composed, runtime, terminals = harness({
                    { { kind = "user_action", action = "cancel" } },
                })
                local result, editor_error = main.run_config_repl(composed, runtime)
                A.truthy(result, A.render(editor_error))
                A.equal(result.action, "config-repl")
                A.equal(result.outcome, "cancelled")
                A.equal(result.state, "cancelled")
                A.truthy(#terminals > 0)
                for _, terminal in ipairs(terminals) do A.truthy(terminal.closed) end
            end,
        },
    },
}
