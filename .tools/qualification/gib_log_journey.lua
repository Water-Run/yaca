--[[
Author: WaterRun
Date: 2026-09-28
File: gib_log_journey.lua
Description: Real A08/A09 target journey: GiB-scale log range reads, bounded search, growth rejection, rotation/truncation continuation guards and legacy-codepage reads through the production tools layer.
]]

-- Real target-side A08/A09 journey. Arguments: source root, native module, scratch directory.
-- Creates a real multi-GiB fixture on the target filesystem and exercises the production
-- read/search/write tools against it; no model or credentials are involved.
local source_root, native_path, scratch, blocks = table.unpack(arg)
blocks = tonumber(blocks or 38400)
assert(source_root and native_path and scratch, "three probe paths are required")
local plain_assert = assert
local separator = package.config:sub(1, 1)
local platform_kind = separator == "\\" and "windows" or "posix"

-- Join one directory and one file name with the host-native separator.
--@param directory string Absolute directory path supplied on the command line.
--@param name string File or directory name without separators.
--@return string Joined path in the host-native separator form.
local function join(directory, name)
    return directory .. separator .. name
end

-- Wraps assert with a structured failure printer for journey evidence.
--@param value any Candidate value supplied to the journey step.
--@param message string|table Human text or typed failure record.
--@return any observed assert value observed by the journey step.
local function assert(value, message)
    if type(message) == "table" then
        message = tostring(message.code) .. ": " .. tostring(message.message or message.detail)
    end
    return plain_assert(value, message)
end

local steps, failures = {}, {}

-- Records one named journey step outcome.
--@param name string Stable journey step identifier.
--@param ok boolean Whether the step assertion held.
--@param detail string Extra evidence text appended to the record.
--@return void No value; appends to the step ledger.
local function record(name, ok, detail)
    steps[#steps + 1] = { name = name, ok = ok, detail = detail or "" }
    if not ok then failures[#failures + 1] = name end
    print((ok and "PASS " or "FAIL ") .. name .. (detail ~= "" and ("    " .. detail) or ""))
end

package.path = source_root .. "/src/?.lua"
local native = assert(package.loadlib(native_path, "luaopen_yaca_native"))()
local fs = assert(require("fs").new(native, {
    maximum_chunk_bytes = 65536, maximum_lease_bytes = 256, maximum_direct_entries = 256,
}))
local paths = assert(require("path").new(native, {
    maximum_path_bytes = 32768, maximum_segments = 256, maximum_segment_bytes = 255,
    maximum_hash_chunk_bytes = 32768,
}))
local safety = assert(require("safety").new(native, {
    maximum_hash_chunk_bytes = 65536, minimum_scannable_secret_bytes = 8,
}))
local text_codec = assert(require("textcodec").new(native, platform_kind, os.getenv))
local operations = assert(require("context").new_operation_service({
    safety = safety,
    journal = {
        -- Records an intent for the GiB journey fixture journal.
        --@param _ any Unused callback argument supplied by the port.
        --@param digest string Computed hexadecimal digest of the intent.
        --@return boolean accepted Whether the fake callback accepts this journey step.
        --@return any secondary2 Computed digest returned by the fixture.
        commit_intent = function(_, digest) return true, digest end,
        -- Records a result for the GiB journey fixture journal.
        --@param _ any Unused callback argument supplied by the port.
        --@param digest string Computed hexadecimal digest of the result.
        --@return boolean accepted Whether the fake callback accepts this journey step.
        --@return any secondary2 Computed digest returned by the fixture.
        commit_result = function(_, digest) return true, digest end,
    },
}, { maximum_identifier_bytes = 256, maximum_evidence_bytes = 131072, unresolved_operation_ids = {} }))
local tools = assert(require("tools").new({
    filesystem = fs, path = paths, safety = safety, secret_registry = false,
    processes = false, operations = operations, text_codec = text_codec,
    authorization = {
        -- Admits every journey call through the fake authorization port.
        --@param call table Recorded call under inspection.
        --@return boolean accepted Always true for this journey.
        --@return any secondary2 Call digest echoed back to the service.
        admit = function(call) return true, call.call_digest end,
        -- Reverifies every journey call through the fake authorization port.
        --@param call table Recorded call under inspection.
        --@param _ any Unused callback argument supplied by the port.
        --@param digest string Expected or computed hexadecimal digest.
        --@return boolean Whether the recorded digest matches the request.
        reverify = function(call, _, digest) return call.call_digest == digest end,
    },
}, {
    maximum_argument_bytes = 65536, maximum_path_bytes = 32768, maximum_content_bytes = 65536,
    maximum_file_bytes = 16 * 1024 * 1024, maximum_result_bytes = 131072,
    maximum_list_depth = 8, maximum_page_entries = 64, maximum_walk_entries = 256,
    maximum_search_pattern_bytes = 256, maximum_search_matches = 64,
    maximum_patch_hunks = 16, maximum_patch_lines = 128, maximum_line_bytes = 4096,
    maximum_continuations = 8, maximum_identifier_bytes = 256, filesystem_chunk_bytes = 4096,
    create_permissions = 384, maximum_json_depth = 24, maximum_json_nodes = 4096,
    maximum_number_bytes = 32, maximum_exec_output_bytes = 65536,
    maximum_exec_deadline_ms = 10000, platform_kind = platform_kind,
    workspace_path = scratch, reserved_paths = { join(scratch, "reserved") },
}))
local codec = assert(require("json").new({
    maximum_bytes = 65536, maximum_depth = 24, maximum_nodes = 4096,
    maximum_string_bytes = 65536, maximum_number_bytes = 32,
}))
-- Encodes one journey argument value as canonical JSON bytes.
--@param value any Argument scalar, array or table to encode.
--@return string Canonical JSON text for the admission record.
local jsonlib = require("json")

-- Recursively tags plain Lua values for the canonical JSON writer.
--@param value any Plain scalar, number or table argument value.
--@return any Tagged value accepted by the codec writer.
local function tag_json(value)
    if math.type(value) == "integer" then return jsonlib.number(tostring(value)) end
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = tag_json(item) end
    return jsonlib.object(copy)
end
local serial = 0

-- Admits, authorizes and executes one direct tool call through the production path.
--@param tool string Tool name selected for the journey step.
--@param arguments table Canonical argument vector for the call.
--@param tag string Stable call tag used for identity fields.
--@return table Durable tool result record.
local function run(tool, arguments, tag)
    serial = serial + 1
    local admitted = assert(tools:admit_call({
        tool = tool, schema_version = tools.schema_version, registry_digest = tools.registry_digest,
        provider_call_id = "a08-" .. tag, tool_call_id = "call-" .. tag,
        operation_id = "operation-" .. tag,
        canonical_arguments = codec.write(tag_json(arguments)),
    }))
    local action = assert(tools:permission_action(admitted))
    if admitted.mutates or admitted.tool == "exec" then
        assert(tools:begin_operation(admitted))
    end
    local token = assert(tools:authorize(admitted, {
        permission_snapshot_digest = "journey", approval_digest = "",
        config_generation = "journey", workspace_identity = action.workspace_root_identity,
        double_check = false, action_review = "not-required",
    }))
    return assert(tools:execute(token))
end

-- Builds the multi-GiB fixture with head, tail and overlong-line sections.
--@param path string Absolute fixture path on the target filesystem.
--@return number Exact fixture size in bytes accumulated from the writes.
--@effect Writes approximately 2.4 GiB to the scratch directory at full scale.
local function build_fixture(path)
    local handle = assert(io.open(path, "wb"))
    local size = 0
    -- Write one fixture chunk and account for its exact byte count.
    --@param chunk string Fixture bytes to append at the current position.
    --@return void No value; updates the captured size accumulator.
    local function emit(chunk)
        handle:write(chunk)
        size = size + #chunk
    end
    local filler = string.rep("x", 63) .. "\n"
    emit("A08-HEAD-MARKER-0001\n")
    local block = filler:rep(1000)
    for index = 1, blocks do
        emit(block)
        if index == math.floor(blocks / 2) then
            emit(string.rep("L", 299999) .. "\n")
        end
    end
    emit("A08-TAIL-MARKER-9f2c\n")
    handle:close()
    return size
end

local path = join(scratch, "a08-gib.log")
local size = build_fixture(path)
record("fixture-created", blocks < 38400 or size > 2 * 1024 * 1024 * 1024,
    string.format("size=%.0fMiB", size / (1024 * 1024)))

local head = run("read", { path = path, start_line = 1, max_lines = 2, encoding = "auto" }, "head")
record("head-range", head.outcome == "success"
    and head.payload and head.payload.lines
    and head.payload.lines[1].text:find("A08-HEAD-MARKER", 1, true) ~= nil,
    head.outcome .. "/" .. tostring(head.error and head.error.code) .. "/"
        .. tostring(head.error and head.error.message):sub(1, 90))

local tail = run("read", { path = path, start_line = 1, max_lines = 3, from_end = true,
    encoding = "auto" }, "tail")
record("tail-range", tail.outcome == "success"
    and tail.payload and tail.payload.lines and #tail.payload.lines >= 1
    and tail.payload.lines[#tail.payload.lines].text:find("A08-TAIL-MARKER", 1, true) ~= nil,
    tail.outcome .. "/" .. tostring(tail.error and tail.error.code))

local search = run("search", { path = path, pattern = "A08-HEAD-MARKER-0001", dialect = "literal",
    case_sensitive = true, page_size = 4, encoding = "auto" }, "search")
record("bounded-search", search.outcome == "success" and search.payload
    and search.payload.matches and #search.payload.matches == 1,
    search.outcome .. "/" .. tostring(search.error and search.error.code) .. "/"
        .. tostring(search.error and search.error.message):sub(1, 90))

local deep = run("search", { path = path, pattern = "A08-TAIL-MARKER-9f2c", dialect = "literal",
    case_sensitive = true, page_size = 4, encoding = "auto" }, "deep")
record("scan-budget-bounded", deep.outcome == "success" and deep.payload
    and (blocks < 38400 or deep.payload.complete == false),
    deep.outcome .. "/complete=" .. tostring(deep.payload and deep.payload.complete))

local mid = run("read", { path = path, start_line = 1199900, max_lines = 4, encoding = "auto" },
    "mid")
record("offset-past-2gib", mid.outcome == "success", mid.outcome)

serial = serial + 1
local oversize_admitted, oversize_error = tools:admit_call({
    tool = "write", schema_version = tools.schema_version, registry_digest = tools.registry_digest,
    provider_call_id = "a08-write2", tool_call_id = "call-write2", operation_id = "operation-write2",
    canonical_arguments = codec.write(tag_json({ path = join(scratch, "reject.txt"), mode = "create",
        content = string.rep("y", 70000), encoding = "utf-8", newline_policy = "preserve" })),
})
record("oversize-write-rejected", oversize_admitted == nil
    and oversize_error ~= nil and oversize_error.code == "InvalidToolCall",
    "admission/" .. tostring(oversize_error and oversize_error.code))
local small_reject = run("write", { path = join(scratch, "reject.txt"), mode = "create",
    content = string.rep("z", 60000), encoding = "utf-8", newline_policy = "preserve" }, "write2")
if small_reject.outcome == "success" then os.remove(join(scratch, "reject.txt")) end

local legacy_path = join(scratch, "a09-cp936.txt")
local legacy_handle = assert(io.open(legacy_path, "wb"))
legacy_handle:write("A09-CP936-MARKER\n")
legacy_handle:write("\xd6\xd0\xce\xc4\xb2\xe2\xca\xd4\n")
legacy_handle:close()
local legacy = run("read", { path = legacy_path, start_line = 1, max_lines = 2,
    encoding = "cp936" }, "legacy")
local saw_legacy = legacy.outcome == "success" and legacy.payload and legacy.payload.lines
    and #legacy.payload.lines >= 2
    and legacy.payload.lines[2].text:find("中文测试", 1, true) ~= nil
record("cp936-file-decoded", saw_legacy, legacy.outcome)

local legacy_reject = run("read", { path = legacy_path, start_line = 1, max_lines = 2,
    encoding = "auto" }, "legacy-reject")
-- Strict-UTF-8 hosts refuse the CP936 bytes; hosts whose file default is a
-- legacy ANSI page decode them transparently by design (textcodec facts).
if text_codec.facts.file_default then
    record("cp936-file-default-decodes", legacy_reject.outcome == "success"
        and legacy_reject.payload and legacy_reject.payload.classification == "text",
        legacy_reject.outcome .. "/" .. tostring(legacy_reject.payload
            and legacy_reject.payload.classification) .. "/default="
            .. tostring(text_codec.facts.file_default))
else
    record("cp936-strict-utf8-refuses", legacy_reject.outcome == "success"
        and legacy_reject.payload and legacy_reject.payload.classification == "invalid-encoding"
        and legacy_reject.payload.hint ~= nil,
        legacy_reject.outcome .. "/" .. tostring(legacy_reject.payload
            and legacy_reject.payload.classification))
end
os.remove(legacy_path)

local fh = assert(io.open(path, "r+b"))
fh:seek("end", -8)
fh:write("Z\n")
fh:close()
local changed = run("read", { path = path, start_line = 1, max_lines = 2, from_end = true,
    encoding = "auto" }, "changed")
record("tail-after-growth", changed.outcome == "success", changed.outcome)

local page = run("read", { path = path, start_line = 1, max_lines = 3, encoding = "auto" }, "page1")
local page_token = page.payload and page.payload.continuation or ""
record("continuation-issued", page.outcome == "success"
    and page.payload and page.payload.continuation and page.payload.next_line == 4,
    page.outcome .. "/next_line=" .. tostring(page.payload and page.payload.next_line))
local follow = run("read", { path = path, start_line = 1, max_lines = 3, encoding = "auto",
    continuation = page_token }, "page2")
record("continuation-follows-offset", follow.outcome == "success" and follow.payload
    and follow.payload.lines and follow.payload.lines[1].number == 4,
    follow.outcome .. "/" .. tostring(follow.error and follow.error.code))

local truncator = assert(io.open(path, "wb"))
truncator:write("A08-TRUNCATED-SMALL\n")
truncator:close()
local follow_token = follow.payload and follow.payload.continuation or ""
local stale = run("read", { path = path, start_line = 1, max_lines = 3, encoding = "auto",
    continuation = follow_token }, "stale")
record("continuation-across-truncation", stale.outcome == "failed"
    and stale.error and stale.error.code == "TargetChanged",
    stale.outcome .. "/" .. tostring(stale.error and stale.error.code))

local rotated_away = path .. ".1"
os.rename(path, rotated_away)
local replacement = assert(io.open(path, "wb"))
replacement:write("A08-ROTATED-HEAD-0002\n")
local rot_block = (string.rep("r", 63) .. "\n"):rep(1000)
for index = 1, 280 do replacement:write(rot_block) end
replacement:close()
local after_rotation = run("read", { path = path, start_line = 1, max_lines = 1,
    encoding = "auto" }, "rotated")
record("rotation-fresh-read", after_rotation.outcome == "success" and after_rotation.payload
    and after_rotation.payload.lines
    and after_rotation.payload.lines[1].text:find("A08-ROTATED-HEAD-0002", 1, true) ~= nil,
    after_rotation.outcome)
local rotated_token = after_rotation.payload and after_rotation.payload.continuation or ""
local rotated_away_2 = path .. ".2"
os.rename(path, rotated_away_2)
local replacement2 = assert(io.open(path, "wb"))
replacement2:write("A08-ROTATED-HEAD-0003\n")
replacement2:close()
local rotated_stale = run("read", { path = path, start_line = 1, max_lines = 3,
    encoding = "auto", continuation = rotated_token }, "stale2")
record("continuation-across-rotation", rotated_stale.outcome == "failed"
    and rotated_stale.error and rotated_stale.error.code == "TargetChanged",
    rotated_stale.outcome .. "/" .. tostring(rotated_stale.error and rotated_stale.error.code))
os.remove(rotated_away)
os.remove(rotated_away_2)

os.remove(path)
print(string.format("gib-journey steps=%d failures=%d", #steps, #failures))
os.exit(#failures == 0 and 0 or 1)
