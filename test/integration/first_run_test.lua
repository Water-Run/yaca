--[[
Author: WaterRun
Date: 2026-09-23
File: first_run_test.lua
Description: Checks first-run setup routing through the actual executable dispatcher.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

--Loads a source module into an isolated per-case environment.
--@param name string Module, Model, or resource name selected by the case.
--@param cache table Per-case module cache preserving isolated imports.
--@return any module Module export loaded in the isolated source environment.
local function load_module(name, cache)
    cache = cache or {}
    if cache[name] then return cache[name] end
    --@metatable fixture_view Test-owned lookup and mutation contract for the current case.
    --@field __index any Fallback table or function used for missing fixture keys.
    local environment = setmetatable({}, { __index = _ENV })
    --Resolves an imported Lua module through the isolated test loader.
    --@param dependency string Source module requested from the isolated loader.
    --@return any value Callback value consumed by the enclosing scenario assertion.
    environment.require = function(dependency) return load_module(dependency, cache) end
    environment._G = environment
    cache[name] = assert(loadfile(YACA_TEST_ROOT .. "/src/" .. name .. ".lua", "t", environment))()
    return cache[name]
end

--Supplies exercise behavior required by this suite.
--@param state table|string Current state observed by the fixture.
--@param setup_outcome any The setup outcome supplied to the fake service for this scenario.
--@param tty any The tty supplied to the fake service for this scenario.
--@return any observed exercise value observed by the scenario assertion.
--@return any secondary2 Recorded call count returned by the fixture.
--@return any secondary3 Additional status or structured error from the fixture operation.
local function exercise(state, setup_outcome, tty)
    local main = load_module("main")
    local calls, errors = {}, {}
    local configured = state == "ready"
    --Supplies compose runtime behavior required by this suite.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return table record Fixture record emitted by the scenario callback.
    main.compose_runtime = function()
        calls[#calls + 1] = "compose"
        return { application = { 
            --Simulates the dispatch port for this suite.
            --@param request table Request delivered to the fake component.
            --@return table|nil value Callback value consumed by the enclosing scenario assertion.
            --@return table|nil secondary2 Structured fixture record with code, message.
            dispatch = function(request)
            A.equal(request.id, "run-chat")
            A.equal(request.directory, "/work")
            calls[#calls + 1] = "dispatch"
            if not configured then return nil, { code = state, message = state } end
            return { state = "draft-ready" }
        end } }
    end
    --Supplies run model repl behavior required by this suite.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return table|nil value Callback value consumed by the enclosing scenario assertion.
    --@return table|nil secondary2 Typed error record with code StorageError.
    main.run_model_repl = function()
        calls[#calls + 1] = "setup"
        if setup_outcome == "failure" then return nil, { code = "StorageError", message = "cannot publish" } end
        configured = setup_outcome == "success"
        return { outcome = setup_outcome, state = configured and "published" or "discarded" }
    end
    --Supplies run interactive chat behavior required by this suite.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return table record Fixture record emitted by the scenario callback.
    main.run_interactive_chat = function()
        calls[#calls + 1] = "chat"
        return { outcome = "success" }
    end
    local code = main.run_cli({ [0] = "/app/yaca", "/work" }, {
        native = {
            --Supplies abi version behavior required by this suite.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return string text Text emitted by the scenario callback.
            abi_version = function() return "yaca-native-v0.1.0" end,
            --Supplies platform identity behavior required by this suite.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return table record Fixture record emitted by the scenario callback.
            platform_identity = function() return { os = "linux", arch = "x86_64" } end,
            --Supplies stdio facts behavior required by this suite.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return table record Fixture record emitted by the scenario callback.
            stdio_facts = function()
                return { stdin_is_tty = tty ~= false, stdout_is_tty = tty ~= false, stderr_is_tty = false }
            end,
        },
        --Captures stdout bytes in the the current case scenario.
        --@param none No arguments; this closure uses its captured fixture state.
        --@return boolean accepted Whether the fake callback accepts this scenario.
        stdout = function() return true end,
        --Captures stderr bytes in the the current case scenario.
        --@param bytes string Byte chunk supplied to the fake I/O port.
        --@return boolean accepted Whether the fake callback accepts this scenario.
        stderr = function(bytes) errors[#errors + 1] = bytes return true end,
    })
    return code, calls, table.concat(errors)
end

return {
    name = "integration/first-run",
    cases = {
        {
            name = "missing configuration opens offline setup then starts the selected workspace",
            --Verifies missing configuration opens offline setup then starts the selected workspace.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify missing configuration opens offline setup then starts the selected workspace.
            run = function()
                local code, calls = exercise("ConfigMissing", "success")
                A.equal(code, 0)
                A.deep_equal(calls, { "compose", "dispatch", "setup", "compose", "dispatch", "chat" })
            end,
        },
        {
            name = "cancelled or failed setup never enters chat",
            --Verifies missing configuration opens offline setup then starts the selected workspace.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify missing configuration opens offline setup then starts the selected workspace.
            run = function()
                for _, outcome in ipairs({ "cancelled", "failure" }) do
                    local code, calls = exercise("ConfigMissing", outcome)
                    A.truthy(code ~= 0)
                    A.deep_equal(calls, { "compose", "dispatch", "setup" })
                end
            end,
        },
        {
            name = "existing valid or invalid configuration is not sent through first-run setup",
            --Verifies cancelled or failed setup never enters chat.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify cancelled or failed setup never enters chat.
            run = function()
                local code, calls = exercise("ready", "success")
                A.equal(code, 0)
                A.deep_equal(calls, { "compose", "dispatch", "chat" })
                local failed, invalid_calls, errors = exercise("ConfigInvalid", "success")
                A.truthy(failed ~= 0)
                A.contains(errors, "ConfigInvalid")
                A.deep_equal(invalid_calls, { "compose", "dispatch" })
            end,
        },
        {
            name = "redirected chat input cannot trigger setup or bootstrap reads",
            --Verifies existing valid or invalid configuration is not sent through first-run setup.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify existing valid or invalid configuration is not sent through first-run setup.
            run = function()
                local code, calls, errors = exercise("ConfigMissing", "success", false)
                A.equal(code, 5)
                A.deep_equal(calls, {})
                A.contains(errors, "TtyRequired")
            end,
        },
    },
}
