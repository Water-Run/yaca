--[[
Author: WaterRun
Date: 2026-09-23
File: run.lua
Description: Discovers and executes isolated yaca Lua test suites.
]]

local M = {}

local is_windows = package.config:sub(1, 1) == "\\"

--Supplies normalize behavior required by this suite.
--@param path string File or Context path exercised by the case.
--@return any observed normalize value observed by the scenario assertion.
local function normalize(path)
    path = tostring(path or ""):gsub("\\", "/")
    local unc = path:sub(1, 2) == "//"
    path = path:gsub("/%./", "/"):gsub("//+", "/")
    if unc then path = "/" .. path end
    if #path > 1 and not path:match("^[A-Za-z]:/$") then path = path:gsub("/$", "") end
    return path
end

--Checks is absolute for this test scenario.
--@param path string File or Context path exercised by the case.
--@return number matches Whether is absolute satisfies the tested condition.
local function is_absolute(path)
    path = normalize(path)
    return path:sub(1, 1) == "/" or path:match("^[A-Za-z]:/") ~= nil or path:match("^//[^/]+/[^/]+") ~= nil
end

--Supplies current directory behavior required by this suite.
--@param none No arguments; this closure uses its captured fixture state.
--@return any observed current directory value observed by the scenario assertion.
local function current_directory()
    local command = is_windows and "cd" or "pwd"
    local pipe = io.popen(command, "r")
    if pipe then
        local value = pipe:read("l")
        pipe:close()
        if value and value ~= "" then return normalize(value) end
    end
    local fallback = os.getenv("PWD")
    if fallback and fallback ~= "" then return normalize(fallback) end
    error("cannot determine test working directory")
end

--Supplies absolute behavior required by this suite.
--@param path string File or Context path exercised by the case.
--@return any observed absolute value observed by the scenario assertion.
local function absolute(path)
    path = normalize(path)
    if is_absolute(path) then return path end
    return normalize(current_directory() .. "/" .. path)
end

--Supplies shell quote behavior required by this suite.
--@param path string File or Context path exercised by the case.
--@return string quoted Argument quoted for the selected command shell.
local function shell_quote(path)
    if is_windows then return '"' .. path:gsub('"', '""') .. '"' end
    return "'" .. path:gsub("'", "'\\''") .. "'"
end

--Supplies root from script behavior required by this suite.
--@param script any The script supplied to the fake service for this scenario.
--@return any observed root from script value observed by the scenario assertion.
local function root_from_script(script)
    local path = absolute(script or "test/run.lua")
    local root = path:match("^(.*)/test/run%.lua$")
    if not root or root == "" then error("test runner must be located at <root>/test/run.lua") end
    return root
end

--Supplies discover one behavior required by this suite.
--@param path string File or Context path exercised by the case.
--@return table|any|nil observed discover one value observed by the scenario assertion.
--@return string|nil secondary2 Additional status or structured error from the fixture operation.
local function discover_one(path)
    path = absolute(path)
    if path:match("_test%.lua$") then return { path } end
    local command
    if is_windows then
        local windows_path = path:gsub("/", "\\")
        command = "dir /b /s " .. shell_quote(windows_path .. "\\*_test.lua") .. " 2>NUL"
    else
        command = "find " .. shell_quote(path) .. " -type f -name '*_test.lua' -print 2>/dev/null"
    end
    local pipe = io.popen(command, "r")
    if not pipe then return nil, "cannot start test discovery" end
    local files = {}
    for line in pipe:lines() do
        local normalized_line = normalize(line)
        if normalized_line:match("_test%.lua$") then files[#files + 1] = normalized_line end
    end
    local ok, why, code = pipe:close()
    if ok == nil and code ~= 0 then return nil, "test discovery failed: " .. tostring(why) .. "/" .. tostring(code) end
    table.sort(files)
    return files
end

--- Discovers unique test files beneath files or directories.
--@param paths table Paths to search.
--@return table|nil Sorted absolute test file paths.
--@return string|nil Discovery error.
function M.discover(paths)
    local found, seen = {}, {}
    for _, path in ipairs(paths or {}) do
        local files, discovery_error = discover_one(path)
        if not files then return nil, discovery_error end
        for _, file in ipairs(files) do
            if not seen[file] then
                seen[file] = true
                found[#found + 1] = file
            end
        end
    end
    table.sort(found)
    return found
end

--Supplies validate spec behavior required by this suite.
--@param spec table Test specification or request under evaluation.
--@param file table|string Fixture file or its path.
--@return any|nil observed validate spec value observed by the scenario assertion.
--@return string|nil secondary2 Additional status or structured error from the fixture operation.
local function validate_spec(spec, file)
    if type(spec) ~= "table" then return nil, file .. " must return a test suite table" end
    if type(spec.name) ~= "string" or spec.name == "" then return nil, file .. " has no suite name" end
    if type(spec.cases) ~= "table" or #spec.cases == 0 then return nil, file .. " has no test cases" end
    local names = {}
    for index, case in ipairs(spec.cases) do
        if type(case) ~= "table" then return nil, file .. " case " .. index .. " is not a table" end
        if type(case.name) ~= "string" or case.name == "" then return nil, file .. " case " .. index .. " has no name" end
        if names[case.name] then return nil, file .. " repeats case " .. case.name end
        if type(case.run) ~= "function" then return nil, file .. " case " .. case.name .. " has no run function" end
        names[case.name] = true
    end
    return spec
end

M.validate_spec = validate_spec

--Supplies traceback behavior required by this suite.
--@param message string|table Message or diagnostic passed through this test port.
--@return any observed traceback value observed by the scenario assertion.
local function traceback(message)
    return debug.traceback(tostring(message), 2)
end

--- Loads a suite in an isolated global environment.
--@param file string Absolute test file path.
--@param root string Absolute repository root.
--@return table|nil Validated suite.
--@return string|nil Load or validation error.
--@return table Captured log lines.
function M.load_spec(file, root)
    local logs = {}
    local test_os = {}
    for key, value in pairs(os) do test_os[key] = value end
    --Supplies exit behavior required by this suite.
    --@param code string|integer Expected error or exit code.
    --@return nil No value; the fake port or test assertion observes this callback's effects.
    test_os.exit = function(code) error("test attempted os.exit(" .. tostring(code) .. ")", 2) end
    local environment = {
        arg = false,
        os = test_os,
        YACA_TEST_ROOT = root,
        YACA_TEST_RUNNER = M,
        --Supplies print behavior required by this suite.
        --@param ... any Additional values forwarded by the fake port.
        --@return nil No value; the fake port or test assertion observes this callback's effects.
        print = function(...)
            local values = {}
            for index = 1, select("#", ...) do values[index] = tostring(select(index, ...)) end
            logs[#logs + 1] = table.concat(values, "\t")
        end,
    }
    environment._G = environment
    --@metatable environment Test-owned lookup and mutation contract for the current case.
    --@field __index any Fallback table or function used for missing fixture keys.
    setmetatable(environment, { __index = _G })
    local chunk, load_error = loadfile(file, "t", environment)
    if not chunk then return nil, load_error, logs end
    local ok, spec = xpcall(chunk, traceback)
    if not ok then return nil, spec, logs end
    local valid, validation_error = validate_spec(spec, file)
    if not valid then return nil, validation_error, logs end
    return valid, nil, logs
end

--Supplies snapshot loaded behavior required by this suite.
--@param none No arguments; this closure uses its captured fixture state.
--@return any observed Captured snapshot returned by the fixture.
local function snapshot_loaded()
    local snapshot = {}
    for key, value in pairs(package.loaded) do snapshot[key] = value end
    return snapshot
end

--Supplies restore loaded behavior required by this suite.
--@param snapshot table Captured immutable state under inspection.
--@return nil No value; the fake port or test assertion observes this callback's effects.
local function restore_loaded(snapshot)
    for key in pairs(package.loaded) do if snapshot[key] == nil then package.loaded[key] = nil end end
    for key, value in pairs(snapshot) do package.loaded[key] = value end
end

--- Executes every case despite individual failures.
--@param entries table Normalized case entries.
--@param writer function|nil Line output callback.
--@return table Summary counts.
function M.run_cases(entries, writer)
    --Supplies an assertion callback for this test scenario.
    --@param line string|integer Input line or physical line position.
    --@return nil No value; the fake port or test assertion observes this callback's effects.
    writer = writer or function(line) io.stdout:write(line, "\n") end
    local summary = { total = 0, passed = 0, failed = 0 }
    for _, entry in ipairs(entries) do
        summary.total = summary.total + 1
        local old_path, old_cpath = package.path, package.cpath
        local old_loaded = snapshot_loaded()
        local ok, failure = xpcall(entry.run, traceback)
        package.path, package.cpath = old_path, old_cpath
        restore_loaded(old_loaded)
        local label = entry.suite .. " :: " .. entry.name
        if ok then
            summary.passed = summary.passed + 1
            writer("PASS " .. label)
        else
            summary.failed = summary.failed + 1
            writer("FAIL " .. label)
            writer("  " .. tostring(failure):gsub("\n", "\n  "))
            for _, log_line in ipairs(entry.logs or {}) do writer("  LOG " .. log_line) end
        end
    end
    writer(string.format("SUMMARY total=%d passed=%d failed=%d", summary.total, summary.passed, summary.failed))
    return summary
end

--Supplies usage behavior required by this suite.
--@param writer table|function Writer receiving generated test output.
--@return nil No value; the fake port or test assertion observes this callback's effects.
local function usage(writer)
    writer("usage: lua test/run.lua [--list] [test-file-or-directory ...]")
end

--- Runs the command-line test runner.
--@param arguments table Lua argument array.
--@return integer Stable process exit code.
function M.main(arguments)
    local root = root_from_script(arguments[0])
    local paths, list_only = {}, false
    for index = 1, #arguments do
        local value = arguments[index]
        if value == "--list" then
            list_only = true
        elseif value == "--help" or value == "-h" then
            --Supplies usage behavior required by this suite.
            --@param line string|integer Input line or physical line position.
            --@return nil No value; the fake port or test assertion observes this callback's effects.
            usage(function(line) io.stdout:write(line, "\n") end)
            return 0
        elseif value:sub(1, 1) == "-" then
            io.stderr:write("unknown test option: ", value, "\n")
            --Supplies usage behavior required by this suite.
            --@param line string|integer Input line or physical line position.
            --@return nil No value; the fake port or test assertion observes this callback's effects.
            usage(function(line) io.stderr:write(line, "\n") end)
            return 2
        else
            paths[#paths + 1] = value
        end
    end
    if #paths == 0 then paths[1] = root .. "/test" end

    local files, discovery_error = M.discover(paths)
    if not files then
        io.stderr:write("test discovery error: ", tostring(discovery_error), "\n")
        return 2
    end
    if #files == 0 then
        io.stderr:write("test discovery error: no *_test.lua files found\n")
        return 2
    end
    if list_only then
        for _, file in ipairs(files) do io.stdout:write(file, "\n") end
        return 0
    end

    local entries = {}
    for _, file in ipairs(files) do
        local spec, load_error, logs = M.load_spec(file, root)
        if not spec then
            entries[#entries + 1] = {
                suite = file,
                name = "<load>",
                --Verifies <load>.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify <load>.
                run = function() error(load_error, 0) end,
                logs = logs,
            }
        else
            for _, case in ipairs(spec.cases) do
                entries[#entries + 1] = { suite = spec.name, name = case.name, run = case.run, logs = logs }
            end
        end
    end

    local summary = M.run_cases(entries)
    return summary.failed == 0 and 0 or 1
end

local invoked_path = type(arg) == "table" and type(arg[0]) == "string" and normalize(arg[0]) or ""
local invoked_as_runner = invoked_path == "test/run.lua" or invoked_path:sub(-13) == "/test/run.lua"

if invoked_as_runner then os.exit(M.main(arg), true) end
return M
