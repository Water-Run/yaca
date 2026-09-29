--[[
Author: WaterRun
Date: 2026-09-29
File: bundled.lua
Description: Bundled-software index service: reads, validates, renders and rewrites tools/INDEX.txt and separates bundled programs from tool calls.
]]

local M = {}

-- Maximum admitted index file bytes; larger files are a typed failure.
local MAXIMUM_INDEX_BYTES = 16384
-- Maximum admitted entries in one index.
local MAXIMUM_ENTRIES = 64
-- Per-field byte ceilings applied on parse and write.
local FIELD_LIMITS = { name = 64, summary = 240, url = 320, notes = 320 }
-- Stable native error code shared by every failure in this module.
local FAILURE_CODE = "BundledIndex"

-- Builds a structured failure record for this module.
--@param message string Human-readable diagnostic text.
--@param detail string|nil Extra bounded context for the failure.
--@return table Frozen failure with code, message and optional detail.
local function failure(message, detail)
    local record = { code = FAILURE_CODE, message = message }
    if detail ~= nil then record.detail = detail end
    return record
end

-- Reports whether a value is a bounded NUL-free UTF-8-looking string.
-- Bundled index text must survive byte-oriented transports unchanged.
--@param value any Candidate field value.
--@param limit integer Positive byte ceiling.
--@return boolean True for a nonempty string within the ceiling without NUL or newline bytes.
local function bounded_field(value, limit)
    return type(value) == "string" and #value >= 1 and #value <= limit
        and not value:find("[\0\r\n|]")
end

-- Splits one index line into its four pipe-delimited fields.
--@param line string Single newline-free index line.
--@return table|nil Entry with name, summary, url and notes fields.
--@return table|nil Failure for a malformed or over-limit line.
local function parse_entry(line)
    local name, summary, url, notes = line:match("^([^|]+)|([^|]+)|([^|]*)|(.*)$")
    if not name or not bounded_field(name, FIELD_LIMITS.name)
        or not bounded_field(summary, FIELD_LIMITS.summary)
        or #url > FIELD_LIMITS.url or url:find("[\0\r\n|]")
        or #notes > FIELD_LIMITS.notes
    then
        return nil, failure("index line is malformed or exceeds field limits", line:sub(1, 120))
    end
    return {
        name = name, summary = summary,
        url = url ~= "" and url or false,
        notes = notes ~= "" and notes or false,
    }
end

-- Parses complete index bytes into validated entries.
--@param bytes string Exact INDEX.txt contents.
--@return table|nil Ordered array of parsed entries.
--@return table|nil Failure for invalid bytes, size or duplicates.
function M.parse(bytes)
    if type(bytes) ~= "string" or #bytes == 0 then
        return nil, failure("index bytes are required")
    end
    if #bytes > MAXIMUM_INDEX_BYTES then
        return nil, failure("index exceeds its byte limit")
    end
    if bytes:find("\0") then
        return nil, failure("index contains NUL bytes")
    end
    local entries, seen = {}, {}
    for line in bytes:gmatch("([^\n]+)") do
        if line:sub(1, 1) ~= "#" then
            local entry, entry_error = parse_entry(line)
            if not entry then return nil, entry_error end
            if seen[entry.name] then
                return nil, failure("index repeats a name", entry.name)
            end
            seen[entry.name] = true
            entries[#entries + 1] = entry
            if #entries > MAXIMUM_ENTRIES then
                return nil, failure("index exceeds its entry limit")
            end
        end
    end
    if #entries == 0 then
        return nil, failure("index contains no entries")
    end
    return entries
end

-- Renders validated entries back into canonical INDEX.txt bytes.
--@param entries table Array of entries shaped by parse.
--@return string|nil Canonical index text ending in one newline.
--@return table|nil Failure when an entry no longer validates.
function M.render(entries)
    if type(entries) ~= "table" or #entries == 0 or #entries > MAXIMUM_ENTRIES then
        return nil, failure("entries array is empty or exceeds its limit")
    end
    local lines = {
        "# yaca bundled software index",
        "# name | summary | manual URL | notes",
        "# Bundled programs are not tool calls; invoke them through exec or the lua tool.",
    }
    for index, entry in ipairs(entries) do
        if type(entry) ~= "table"
            or not bounded_field(entry.name, FIELD_LIMITS.name)
            or not bounded_field(entry.summary, FIELD_LIMITS.summary)
        then
            return nil, failure("entry fails validation on render", tostring(index))
        end
        local url = entry.url or ""
        local notes = entry.notes or ""
        if #url > FIELD_LIMITS.url or #notes > FIELD_LIMITS.notes
            or url:find("[\0\r\n|]") or notes:find("[\0\r\n|]")
        then
            return nil, failure("entry field exceeds limits on render", entry.name)
        end
        lines[#lines + 1] = entry.name .. "|" .. entry.summary .. "|" .. url .. "|" .. notes
    end
    return table.concat(lines, "\n") .. "\n"
end

-- Builds the model-facing context rendering for admitted entries.
-- The rendering states the exec/lua boundary explicitly so bundled
-- programs are never mistaken for native tool calls.
--@param entries table Array of entries shaped by parse.
--@return string|nil Bounded context block.
--@return table|nil Failure for an invalid entries array.
function M.render_context(entries)
    if type(entries) ~= "table" or #entries == 0 or #entries > MAXIMUM_ENTRIES then
        return nil, failure("entries array is empty or exceeds its limit")
    end
    local lines = {
        "Bundled software shipped beside this yaca (not tool calls; use them through exec or the lua tool):",
    }
    for _, entry in ipairs(entries) do
        local line = "- " .. entry.name .. ": " .. entry.summary
        if entry.url then line = line .. " (manual: " .. entry.url .. ")" end
        if entry.notes then line = line .. " — " .. entry.notes end
        lines[#lines + 1] = line
    end
    return table.concat(lines, "\n")
end

-- Builds the advisory ask message for one bundled-software question.
-- The message embeds the context rendering and constrains the reply to
-- matching plus an exec/lua invocation shape.
--@param entries table Array of entries shaped by parse.
--@param question string Bounded user question text.
--@return string|nil Composed ask message.
--@return table|nil Failure for an invalid array or question.
function M.render_question(entries, question)
    if type(question) ~= "string" or #question == 0 or #question > 4000
        or question:find("\0")
    then
        return nil, failure("question must be bounded text")
    end
    local context, context_error = M.render_context(entries)
    if not context then return nil, context_error end
    return "Bundled software matching request. Bundled software are portable programs, "
        .. "not tool calls; they run through the exec or lua tools.\n\n"
        .. context .. "\n\nUser question: " .. question .. "\n\n"
        .. "Reply with: the matching bundled software (or none), the reason, "
        .. "and one concrete exec or lua invocation shape. State uncertainty explicitly.",
        nil
end

-- Merges a directory listing into existing entries for index regeneration.
-- Unknown directories gain a placeholder entry; known fields are preserved.
--@param entries table Array of existing entries shaped by parse.
--@param names table Array of subdirectory name strings.
--@return table|nil Merged entry array ordered by directory order then existing order.
--@return table|nil Failure when a name cannot be represented.
function M.merge_directory(entries, names)
    if type(entries) ~= "table" or type(names) ~= "table" then
        return nil, failure("entries and names arrays are required")
    end
    local by_name = {}
    for _, entry in ipairs(entries) do by_name[entry.name] = entry end
    local merged, used = {}, {}
    for _, name in ipairs(names) do
        if type(name) ~= "string" or not bounded_field(name, FIELD_LIMITS.name) then
            return nil, failure("directory name cannot be represented", tostring(name))
        end
        local entry = by_name[name]
        if not entry then
            entry = {
                name = name,
                summary = "bundled program; description pending",
                url = false,
                notes = "edit tools/INDEX.txt to document it",
            }
        end
        merged[#merged + 1] = entry
        used[name] = true
    end
    for _, entry in ipairs(entries) do
        if not used[entry.name] then merged[#merged + 1] = entry end
    end
    if #merged == 0 or #merged > MAXIMUM_ENTRIES then
        return nil, failure("merged index is empty or exceeds its limit")
    end
    return merged
end

-- Reads INDEX.txt bytes through the production filesystem service.
--@param filesystem table Filesystem service with open_read, stream_read and close.
--@param path string Absolute INDEX.txt path.
--@return string|nil Complete bounded file bytes.
--@return table|nil Typed filesystem failure.
function M.read_file(filesystem, path)
    local opened, handle = filesystem.open_read(path)
    if not opened then return nil, handle end
    local parts = {}
    while true do
        local chunk, chunk_error
        local ok, value = filesystem.stream_read(handle, 4096)
        if not ok then
            chunk_error = value
            filesystem.close(handle)
            return nil, chunk_error
        end
        parts[#parts + 1] = value.bytes
        if value.eof then break end
        if #table.concat(parts) > MAXIMUM_INDEX_BYTES then
            filesystem.close(handle)
            return nil, failure("index exceeds its byte limit")
        end
    end
    filesystem.close(handle)
    return table.concat(parts)
end

return M
