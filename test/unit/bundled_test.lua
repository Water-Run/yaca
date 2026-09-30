--[[
Author: WaterRun
Date: 2026-09-30
File: bundled_test.lua
Description: Verifies the bundled-software index parser, renderer, context projection and question composition.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

local cases = {}

--Appends one case to the suite list.
--@param case table Case record with name and run fields.
--@return void No value; mutates the shared cases list.
local function add(case)
    cases[#cases + 1] = case
end

--Loads the bundled module into an isolated environment.
--@param name string Module name to load.
--@return table Loaded module instance.
local function load_module(name)
    local chunk = assert(loadfile(YACA_TEST_ROOT .. "/src/" .. name .. ".lua", "t", _ENV))
    return chunk()
end

--Builds one valid index fixture with an optional line transform.
--@param transform function|nil Callback receiving the entry line before assembly.
--@return string Complete INDEX.txt fixture bytes.
local function fixture(transform)
    local lines = {
        "# yaca bundled software index",
        "# name | summary | manual URL | notes",
        "python2|Python 2 interpreter, no pip|https://docs.python.org/2/|run via exec",
        "curl|HTTP and HTTPS client with its own CA bundle|https://curl.se/docs/|",
    }
    if transform then lines[#lines + 1] = transform() end
    return table.concat(lines, "\n") .. "\n"
end

-- Supplies finite stream responses and tracks ownership for index read regressions.
--@param chunks table Ordered chunk records or a typed failure with code and message.
--@return table Filesystem port that refuses reads beyond the supplied responses.
--@return table Observed read and close counts for the single fake handle.
local function index_filesystem(chunks)
    local handle, observed = {}, { reads = 0, closes = 0 }
    local filesystem = {
        -- Opens the index handle whose lifecycle is observed by this fixture.
        --@param path string Absolute index path supplied by the caller.
        --@return boolean Always true for the supplied fixture.
        --@return table The single fake read handle.
        open_read = function(path) return true, handle end,
        -- Returns the next response, preserving typed failures and bounding stalled tests.
        --@param opened table Handle returned by this fixture's open_read.
        --@param maximum_bytes integer Requested byte ceiling, checked against fixture chunks.
        --@return boolean Whether a chunk is available rather than a typed failure.
        --@return table Chunk record or the exact supplied failure.
        stream_read = function(opened, maximum_bytes)
            A.equal(opened, handle)
            observed.reads = observed.reads + 1
            local chunk = chunks[observed.reads]
            if not chunk then return false, { code = "UnexpectedRead" } end
            if chunk.code then return false, chunk end
            A.truthy(#chunk.bytes <= maximum_bytes)
            return true, chunk
        end,
        -- Counts each release of the fixture's single index handle.
        --@param opened table Handle returned by this fixture's open_read.
        --@return boolean Always true after observing the release.
        close = function(opened)
            A.equal(opened, handle)
            observed.closes = observed.closes + 1
            return true
        end,
    }
    return filesystem, observed
end

cases[#cases + 1] = {
    name = "index parsing accepts a leading UTF-8 BOM from legacy Windows editors",
    -- Verifies that an editor's UTF-8 signature does not become part of an index name or header.
    --@param none No arguments; supplies the same valid index with an explicit leading signature.
    --@return nil Assertions verify parsed entries preserve their original names and notes.
    run = function()
        local bundled = load_module("bundled")
        local entries = assert(bundled.parse("\239\187\191" .. fixture()))
        A.equal(entries[1].name, "python2")
        A.equal(entries[1].notes, "run via exec")
    end,
}

cases[#cases + 1] = {
    name = "index parsing rejects malformed UTF-8 before projecting optional metadata",
    -- Verifies malformed notes cannot reach the model-facing runtime environment.
    --@param none No arguments; supplies invalid and truncated scalar bytes in an otherwise valid line.
    --@return nil Assertions verify a typed BundledIndex failure for both malformed forms.
    run = function()
        local bundled = load_module("bundled")
        for _, malformed in ipairs({ "\255", "\226\130" }) do
            local entries, err = bundled.parse("name|summary||notes" .. malformed .. "\n")
            A.falsy(entries)
            A.equal(err.code, "BundledIndex")
        end
    end,
}

cases[#cases + 1] = {
    name = "index byte limit also applies to the final EOF chunk",
    -- Verifies exact-limit success and limit-plus-one refusal with bytes in the EOF chunk.
    --@param none No arguments; builds independent finite stream fixtures.
    --@return nil Assertions check byte admission and exactly one close per read.
    run = function()
        local bundled = load_module("bundled")
        for _, extra in ipairs({ 0, 1 }) do
            local chunks = {}
            for index = 1, 4 do
                chunks[index] = { bytes = string.rep("a", 4096), eof = false }
            end
            chunks[5] = { bytes = string.rep("b", extra), eof = true }
            local filesystem, observed = index_filesystem(chunks)
            local bytes, err = bundled.read_file(filesystem, "/x/INDEX.txt")
            if extra == 0 then
                A.equal(bytes, string.rep("a", 16384))
                A.falsy(err)
            else
                A.falsy(bytes)
                A.equal(err.code, "BundledIndex")
            end
            A.equal(observed.reads, 5)
            A.equal(observed.closes, 1)
        end
    end,
}

cases[#cases + 1] = {
    name = "index read refuses a stalled stream and closes its handle",
    -- Verifies that an empty non-EOF chunk fails before a second read can occur.
    --@param none No arguments; supplies one stalled chunk and an unexpected-read guard.
    --@return nil Assertions check the typed failure, read count and handle release.
    run = function()
        local bundled = load_module("bundled")
        local filesystem, observed = index_filesystem({ { bytes = "", eof = false } })
        local bytes, err = bundled.read_file(filesystem, "/x/INDEX.txt")
        A.falsy(bytes)
        A.equal(err.code, "BundledIndex")
        A.equal(observed.reads, 1)
        A.equal(observed.closes, 1)
    end,
}

cases[#cases + 1] = {
    name = "index read retains filesystem failures instead of returning a valid prefix",
    -- Verifies that a failure after a parseable prefix discards bytes and releases ownership.
    --@param none No arguments; supplies a valid prefix followed by a typed read error.
    --@return nil Assertions check error identity and exactly one handle close.
    run = function()
        local bundled = load_module("bundled")
        local expected = { code = "ReadFailure", message = "index device became unavailable" }
        local filesystem, observed = index_filesystem({
            { bytes = fixture(), eof = false }, expected,
        })
        local bytes, err = bundled.read_file(filesystem, "/x/INDEX.txt")
        A.falsy(bytes)
        A.equal(err, expected)
        A.equal(observed.reads, 2)
        A.equal(observed.closes, 1)
    end,
}

cases[#cases + 1] = {
    name = "index parsing accepts bounded entries and preserves optional fields",
    --Verifies index parsing accepts bounded entries and preserves optional fields.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return nil No value; assertions verify index parsing accepts bounded entries and preserves optional fields.
    run = function()
        local bundled = load_module("bundled")
        local entries = assert(bundled.parse(fixture()))
        A.equal(#entries, 2)
        A.equal(entries[1].name, "python2")
        A.equal(entries[1].url, "https://docs.python.org/2/")
        A.equal(entries[1].notes, "run via exec")
        A.equal(entries[2].notes, false)
        A.equal(entries[2].url, "https://curl.se/docs/")
    end,
}

cases[#cases + 1] = {
    name = "index parsing rejects malformed lines and duplicates",
    --Verifies index parsing rejects malformed lines and duplicates.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return nil No value; assertions verify index parsing rejects malformed lines and duplicates.
    run = function()
        local bundled = load_module("bundled")
        local bad, bad_error = bundled.parse("onefield\n")
        A.truthy(bad == nil and bad_error.code == "BundledIndex")
        --Supplies the duplicate line used by the rejection case.
        --@param none No arguments; this closure returns a fixed duplicate entry line.
        --@return string Duplicate index line for the fixture.
        local duplicate_line = function()
            return "python2|duplicate|url|notes"
        end
        bad, bad_error = bundled.parse(fixture(duplicate_line))
        A.truthy(bad == nil and bad_error.code == "BundledIndex")
        bad, bad_error = bundled.parse("# only comments\n")
        A.truthy(bad == nil and bad_error.code == "BundledIndex")
    end,
}

--Supplies the CRLF fixture used by the tolerance case.
--@param none No arguments; this closure returns a fixed CRLF index.
--@return string Index bytes whose lines end with CRLF.
local crlf_bytes = "n|s|u|notes\r\n"

cases[#cases + 1] = {
    name = "index parsing tolerates CRLF line endings without leaking CR",
    --Verifies index parsing tolerates CRLF line endings without leaking CR.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return nil No value; assertions verify index parsing tolerates CRLF line endings without leaking CR.
    run = function()
        local bundled = load_module("bundled")
        local entries = assert(bundled.parse(crlf_bytes))
        A.equal(entries[1].notes, "notes")
        A.falsy(entries[1].notes:find("\r"))
    end,
}

cases[#cases + 1] = {
    name = "index parsing rejects an over-limit summary field",
    --Verifies index parsing rejects an over-limit summary field.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return nil No value; assertions verify index parsing rejects an over-limit summary field.
    run = function()
        local bundled = load_module("bundled")
        --Supplies the oversize summary used by the rejection case.
        --@param none No arguments; this closure returns a fixed over-limit entry line.
        --@return string Oversize index line for the fixture.
        local oversize_line = function()
            return "x|" .. string.rep("y", 300) .. "||"
        end
        local bad, bad_error = bundled.parse(fixture(oversize_line))
        A.truthy(bad == nil and bad_error.code == "BundledIndex")
    end,
}

cases[#cases + 1] = {
    name = "render round-trips parse and render_context separates tool calls",
    --Verifies render round-trips parse and render_context separates tool calls.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return nil No value; assertions verify render round-trips parse and render_context separates tool calls.
    run = function()
        local bundled = load_module("bundled")
        local entries = assert(bundled.parse(fixture()))
        local bytes = assert(bundled.render(entries))
        local reparsed = assert(bundled.parse(bytes))
        A.equal(#reparsed, #entries)
        A.equal(reparsed[1].summary, entries[1].summary)
        local context = assert(bundled.render_context(entries))
        A.truthy(context:find("not tool calls", 1, true))
        A.truthy(context:find("python2", 1, true))
        A.truthy(context:find("manual: https://docs.python.org/2/", 1, true))
        A.truthy(context:find("run via exec", 1, true))
    end,
}

cases[#cases + 1] = {
    name = "render_question embeds the index and constrains the answer shape",
    --Verifies render_question embeds the index and constrains the answer shape.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return nil No value; assertions verify render_question embeds the index and constrains the answer shape.
    run = function()
        local bundled = load_module("bundled")
        local entries = assert(bundled.parse(fixture()))
        local message = assert(bundled.render_question(entries, "which program downloads a file"))
        A.truthy(message:find("User question: which program downloads a file", 1, true))
        A.truthy(message:find("exec or lua", 1, true))
        A.truthy(message:find("curl", 1, true))
        local bad, bad_error = bundled.render_question(entries, "")
        A.truthy(bad_error.code == "BundledIndex")
        bad, bad_error = bundled.render_question(entries, string.rep("q", 5000))
        A.truthy(bad_error.code == "BundledIndex")
    end,
}

cases[#cases + 1] = {
    name = "merge_directory preserves fields and adds placeholders",
    --Verifies merge_directory preserves fields and adds placeholders.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return nil No value; assertions verify merge_directory preserves fields and adds placeholders.
    run = function()
        local bundled = load_module("bundled")
        local entries = assert(bundled.parse(fixture()))
        local merged = assert(bundled.merge_directory(entries, { "curl", "git", "python2" }))
        A.equal(merged[1].name, "curl")
        A.equal(merged[2].summary, "bundled program; description pending")
        A.equal(#merged, 3)
        local rendered = assert(bundled.render(merged))
        assert(bundled.parse(rendered))
    end,
}

cases[#cases + 1] = {
    name = "read_file streams through the filesystem port and caps oversize indexes",
    --Verifies read_file streams through the filesystem port and caps oversize indexes.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return nil No value; assertions verify read_file streams through the filesystem port and caps oversize indexes.
    run = function()
        local bundled = load_module("bundled")
        local bytes = fixture()
        local chunks, position, opened_paths = {}, 1, {}
        local fs = {
            --Supplies the open observation used by the 'read_file streams through the filesystem port and caps oversize indexes' case.
            --@param path string File or Context path exercised by the case.
            --@return boolean accepted Whether the fake port opened the index.
            --@return any secondary2 Opaque fake handle for this scenario.
            open_read = function(path)
                opened_paths[#opened_paths + 1] = path
                return true, {}
            end,
            --Supplies chunked bytes used by the 'read_file streams through the filesystem port and caps oversize indexes' case.
            --@param handle any Unused fake handle for this scenario.
            --@param maximum_bytes integer Chunk byte bound supplied by the service.
            --@return boolean accepted Whether the fake port produced a chunk.
            --@return table secondary2 Chunk record with bytes and eof fields.
            stream_read = function(handle, maximum_bytes)
                local chunk = bytes:sub(position, position + maximum_bytes - 1)
                position = position + #chunk
                chunks[#chunks + 1] = #chunk
                return true, { bytes = chunk, eof = #chunk == 0 }
            end,
            --Supplies the close observation used by the 'read_file streams through the filesystem port and caps oversize indexes' case.
            --@param handle any Unused fake handle for this scenario.
            --@return boolean accepted Always true for this scenario.
            close = function(handle) return true end,
        }
        local observed = assert(bundled.read_file(fs, "/x/INDEX.txt"))
        A.equal(observed, bytes)
        A.equal(opened_paths[1], "/x/INDEX.txt")
        A.truthy(#chunks >= 2)
        local calls = 0
        --Supplies the endless chunk used by the cap case.
        --@param handle any Unused fake handle for this scenario.
        --@param maximum_bytes integer Chunk byte bound supplied by the caller.
        --@return boolean accepted Always true for this scenario.
        --@return table secondary2 Chunk record that never signals EOF.
        fs.stream_read = function(handle, maximum_bytes)
            calls = calls + 1
            return true, { bytes = string.rep("a", maximum_bytes), eof = false }
        end
        local capped, capped_error = bundled.read_file(fs, "/x/INDEX.txt")
        A.truthy(capped == nil and capped_error.code == "BundledIndex")
    end,
}

return {
    name = "unit/bundled",
    cases = cases,
}
