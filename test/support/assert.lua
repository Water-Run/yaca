--[[
File: assert.lua
Date: 2026-08-29
Author: WaterRun
Description: Provides deterministic assertion helpers for the yaca test runner.
]]

local M = {}

local function render(value, seen)
    local value_type = type(value)
    if value_type == "string" then return string.format("%q", value) end
    if value_type ~= "table" then return tostring(value) end

    seen = seen or {}
    if seen[value] then return "<cycle>" end
    seen[value] = true

    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right)
        local left_type, right_type = type(left), type(right)
        if left_type ~= right_type then return left_type < right_type end
        return tostring(left) < tostring(right)
    end)

    local parts = {}
    for _, key in ipairs(keys) do
        parts[#parts + 1] = "[" .. render(key, seen) .. "]=" .. render(value[key], seen)
    end
    seen[value] = nil
    return "{" .. table.concat(parts, ",") .. "}"
end

local function fail(message, level)
    error(message or "assertion failed", (level or 1) + 1)
end

--- Fails the current test immediately.
-- @param message string Failure description.
function M.fail(message)
    fail(message, 1)
end

--- Requires a truthy value.
-- @param value any Value under test.
-- @param message string|nil Optional failure description.
-- @return any The original value.
function M.truthy(value, message)
    if not value then fail(message or ("expected truthy value, got " .. render(value)), 1) end
    return value
end

--- Requires a false or nil value.
-- @param value any Value under test.
-- @param message string|nil Optional failure description.
-- @return any The original value.
function M.falsy(value, message)
    if value then fail(message or ("expected falsy value, got " .. render(value)), 1) end
    return value
end

--- Requires scalar or identity equality.
-- @param actual any Observed value.
-- @param expected any Required value.
-- @param message string|nil Optional failure description.
-- @return any The observed value.
function M.equal(actual, expected, message)
    if actual ~= expected then
        fail(message or ("expected " .. render(expected) .. ", got " .. render(actual)), 1)
    end
    return actual
end

local function deep_equal(left, right, visited)
    if left == right then return true end
    if type(left) ~= type(right) or type(left) ~= "table" then return false end
    visited = visited or {}
    visited[left] = visited[left] or {}
    if visited[left][right] then return true end
    visited[left][right] = true
    for key, value in pairs(left) do
        if not deep_equal(value, right[key], visited) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

--- Requires recursive table equality.
-- @param actual any Observed value.
-- @param expected any Required value.
-- @param message string|nil Optional failure description.
-- @return any The observed value.
function M.deep_equal(actual, expected, message)
    if not deep_equal(actual, expected) then
        fail(message or ("expected deep equality\nexpected: " .. render(expected) .. "\nactual:   " .. render(actual)), 1)
    end
    return actual
end

--- Requires a Lua value type.
-- @param actual any Observed value.
-- @param expected string Required Lua type name.
-- @param message string|nil Optional failure description.
-- @return any The observed value.
function M.type(actual, expected, message)
    if type(actual) ~= expected then
        fail(message or ("expected type " .. tostring(expected) .. ", got " .. type(actual)), 1)
    end
    return actual
end

--- Requires a string to match a Lua pattern.
-- @param actual any Observed value.
-- @param pattern string Required Lua pattern.
-- @param message string|nil Optional failure description.
-- @return string The observed string.
function M.matches(actual, pattern, message)
    if type(actual) ~= "string" or not actual:match(pattern) then
        fail(message or ("expected " .. render(actual) .. " to match " .. render(pattern)), 1)
    end
    return actual
end

--- Requires a string to contain exact bytes.
-- @param actual any Observed value.
-- @param needle string Required byte sequence.
-- @param message string|nil Optional failure description.
-- @return string The observed string.
function M.contains(actual, needle, message)
    if type(actual) ~= "string" or type(needle) ~= "string" or not actual:find(needle, 1, true) then
        fail(message or ("expected " .. render(actual) .. " to contain " .. render(needle)), 1)
    end
    return actual
end

--- Requires a callback to raise an error.
-- @param callback function Callback under test.
-- @param expected string|nil Exact error substring when supplied.
-- @param message string|nil Optional failure description.
-- @return any The raised error value.
function M.raises(callback, expected, message)
    if type(callback) ~= "function" then fail("raises callback must be a function", 1) end
    local ok, raised = pcall(callback)
    if ok then fail(message or "expected callback to raise", 1) end
    local raised_text = tostring(raised)
    if expected and not raised_text:find(expected, 1, true) then
        fail(message or ("expected error containing " .. render(expected) .. ", got " .. render(raised_text)), 1)
    end
    return raised
end

--- Requires two arrays to contain the same value counts.
-- @param actual table Observed array.
-- @param expected table Required array.
-- @param message string|nil Optional failure description.
-- @return table The observed array.
function M.same_items(actual, expected, message)
    M.type(actual, "table", message)
    M.type(expected, "table", message)
    local function counts(values)
        local result = {}
        for _, value in ipairs(values) do result[value] = (result[value] or 0) + 1 end
        return result
    end
    return M.deep_equal(counts(actual), counts(expected), message)
end

--- Renders a value for deterministic assertion diagnostics.
-- @param value any Value to render.
-- @return string Diagnostic representation.
function M.render(value)
    return render(value)
end

return M
