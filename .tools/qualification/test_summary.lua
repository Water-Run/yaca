--[[
File: test_summary.lua
Date: 2026-09-07
Author: WaterRun
Description: Validates complete Lua suite evidence for the qualification builder.
]]

local M = {}

local function count_value(value)
    if value ~= "0" and not value:match("^[1-9][0-9]*$") then return nil end
    local number = tonumber(value)
    if math.type(number) ~= "integer" or number < 0 then return nil end
    return number
end

---Parses exactly one successful, nonempty full-suite summary from a build log.
-- Counts are derived from the tested checkout; malformed or repeated SUMMARY
-- lines cannot be accepted as complete qualification evidence.
-- @param source string Captured test runner stdout/stderr bytes.
-- @return table|nil summary Validated total, passed, and failed counts.
-- @return string|nil err Reason the log cannot establish complete test evidence.
function M.parse(source)
    if type(source) ~= "string" then return nil, "test log must be bytes" end
    local summary
    for raw_line in source:gmatch("[^\n]+") do
        local line = raw_line:gsub("\r$", "")
        if line:match("^SUMMARY") then
            if summary then return nil, "test log has multiple summaries" end
            local total, passed, failed = line:match(
                "^SUMMARY total=(%d+) passed=(%d+) failed=(%d+)$"
            )
            if not total then return nil, "test summary is malformed" end
            total, passed, failed = count_value(total), count_value(passed), count_value(failed)
            if not total or not passed or not failed
                or total < 1 or passed ~= total or failed ~= 0
            then
                return nil, "test summary does not prove a nonempty successful suite"
            end
            summary = { total = total, passed = passed, failed = failed }
        end
    end
    if not summary then return nil, "test log has no summary" end
    return summary
end

local invoked_path = type(arg) == "table" and type(arg[0]) == "string"
    and arg[0]:gsub("\\", "/") or ""
local invoked = invoked_path == "test_summary.lua"
    or invoked_path:match("/test_summary%.lua$") ~= nil
if invoked then
    if #arg ~= 1 then
        io.stderr:write("usage: lua test_summary.lua FULL_TEST_LOG\n")
        os.exit(64)
    end
    local file, open_error = io.open(arg[1], "rb")
    if not file then
        io.stderr:write("test evidence: ", tostring(open_error), "\n")
        os.exit(1)
    end
    local source, read_error = file:read("a")
    local closed, close_error = file:close()
    local summary, parse_error = M.parse(source)
    if not source or not closed or not summary then
        io.stderr:write("test evidence: ",
            tostring(read_error or close_error or parse_error), "\n")
        os.exit(1)
    end
    io.stdout:write(tostring(summary.passed), "/", tostring(summary.total), "\n")
    os.exit(0)
end

return M
