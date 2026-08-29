--[[
File: path_test.lua
Date: 2026-08-29
Author: WaterRun
Description: Verifies LogicalPath mapping, boundaries, selectors, and Context hashes.
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

local path = load_module("path")
local fixtures = load_table(".develope-docs/contracts/fixtures/path.lua")
local sha256 = load_table("test/support/sha256_reference.lua")

local function fake_native()
    local native = {
        observations = {
            starts = 0,
            updates = 0,
            closes = 0,
            maximum_chunk_bytes = 0,
        },
    }

    function native.sha256_start()
        native.observations.starts = native.observations.starts + 1
        return { parts = {}, closed = false, finished = false }
    end

    function native.sha256_update(handle, bytes)
        assert(not handle.closed and not handle.finished)
        handle.parts[#handle.parts + 1] = bytes
        native.observations.updates = native.observations.updates + 1
        if #bytes > native.observations.maximum_chunk_bytes then
            native.observations.maximum_chunk_bytes = #bytes
        end
        return true
    end

    function native.sha256_finish(handle)
        assert(not handle.closed and not handle.finished)
        handle.finished = true
        return sha256.digest(table.concat(handle.parts))
    end

    function native.sha256_close(handle)
        handle.closed = true
        native.observations.closes = native.observations.closes + 1
        return true
    end

    return native
end

local function options(overrides)
    local result = {
        maximum_path_bytes = 1024,
        maximum_segments = 64,
        maximum_segment_bytes = 255,
        maximum_hash_chunk_bytes = 3,
    }
    for key, value in pairs(overrides or {}) do result[key] = value end
    return result
end

local function codec(overrides, native)
    native = native or fake_native()
    return assert(path.new(native, options(overrides))), native
end

return {
    name = "unit/path",
    cases = {
        {
            name = "contract codec fixtures map absolute paths or fail with exact classes",
            run = function()
                local service = codec()
                for _, case in ipairs(fixtures.codec_cases) do
                    local logical, metadata_or_error = service.to_logical(case.platform_path)
                    if case.valid then
                        A.equal(logical, case.logical_path, case.id)
                        A.truthy(metadata_or_error.root_kind, case.id)
                    else
                        A.falsy(logical, case.id)
                        A.equal(metadata_or_error.code, case.error_id, case.id)
                    end
                end
            end,
        },
        {
            name = "drive UNC POSIX and extended paths round trip without case loss",
            run = function()
                local service = codec()
                local cases = {
                    { "C:\\", "/C", "windows-drive", "C:\\" },
                    { "d:/Work/我的任务.xml", "/D/Work/我的任务.xml", "windows-drive",
                        "D:\\Work\\我的任务.xml" },
                    { "\\\\Server\\Share\\Dir\\name. ",
                        "/UNC/Server/Share/Dir/name. ", "windows-unc",
                        "\\\\Server\\Share\\Dir\\name. " },
                    { "\\\\?\\c:\\Work\\..\\File.xml", "/C/File.xml", "windows-drive",
                        "C:\\File.xml" },
                    { "\\\\?\\UNC\\Server\\Share\\a.xml",
                        "/UNC/Server/Share/a.xml", "windows-unc",
                        "\\\\Server\\Share\\a.xml" },
                    { "/home/u/back\\slash.xml", "/home/u/back\\slash.xml", "posix",
                        "/home/u/back\\slash.xml" },
                    { "/", "/", "posix", "/" },
                }
                for _, case in ipairs(cases) do
                    local logical, metadata = assert(service.to_logical(case[1]))
                    A.equal(logical, case[2])
                    A.equal(metadata.root_kind, case[3])
                    local platform = case[3] == "posix" and "posix" or "windows"
                    A.equal(assert(service.from_logical(logical, platform)), case[4])
                end
                local display = "c:\\Work\\A.xml"
                A.equal(assert(service.normalize_display(display)), display)
            end,
        },
        {
            name = "navigation collapses internally but never crosses an absolute root",
            run = function()
                local service = codec()
                A.equal(assert(service.to_logical("C:\\a\\b\\..\\c")), "/C/a/c")
                A.equal(assert(service.to_logical("/a/./b//c/../d")), "/a/b/d")
                A.equal(
                    assert(service.to_logical("\\\\server\\share\\a\\b\\..")),
                    "/UNC/server/share/a"
                )
                for _, candidate in ipairs({
                    "C:\\..\\escape",
                    "\\\\server\\share\\..\\escape",
                    "/../escape",
                }) do
                    local logical, path_error = service.to_logical(candidate)
                    A.falsy(logical)
                    A.equal(path_error.code, "PathEscapesWorkspace")
                end
                A.falsy(service.to_logical("\\\\server"))
                A.falsy(service.to_logical("\\\\.\\PhysicalDrive0"))
            end,
        },
        {
            name = "canonical LogicalPath validation refuses silent rewriting",
            run = function()
                local service = codec()
                for _, valid in ipairs({
                    "/", "/C/Work/A.xml", "/UNC/server/share/a.xml", "/路径/文件.xml",
                }) do
                    A.equal(assert(service.validate_logical(valid)), valid)
                end
                for _, invalid in ipairs({
                    "relative", "/a//b", "/a/./b", "/a/../b", "/a/", "/UNC/server",
                }) do
                    local admitted, path_error = service.validate_logical(invalid)
                    A.falsy(admitted, invalid)
                    A.equal(path_error.code, "InvalidLogicalPath", invalid)
                end
                A.falsy(service.from_logical("/home/u", "windows"))
                A.falsy(service.from_logical("/C/a\\b", "windows"))
                A.falsy(service.from_logical("/C/a:b", "windows"))
            end,
        },
        {
            name = "boundary comparison uses segments and keeps hash bytes separate",
            run = function()
                local service = codec()
                A.truthy(service.is_within_root("/home/u/a", "/home/u", "posix"))
                A.truthy(service.is_within_root("/home/u", "/home/u", "posix"))
                A.falsy(service.is_within_root("/home/user", "/home/u", "posix"))
                A.truthy(service.is_within_root("/C/WORK/A", "/C/work", "windows"))
                A.falsy(service.is_within_root("/C/work2/A", "/C/work", "windows"))
                A.equal(
                    assert(service.comparison_key("/C/Work/A.xml", "windows")),
                    "/c/work/a.xml"
                )
                A.equal(
                    assert(service.comparison_key("/C/Work/A.xml", "posix")),
                    "/C/Work/A.xml"
                )
                A.falsy(service.comparison_key("/C/Work", "unknown"))
            end,
        },
        {
            name = "SHA-256 vectors use exact UTF-8 then first eight network-order bytes",
            run = function()
                A.equal(
                    sha256.hex(""),
                    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
                )
                A.equal(
                    sha256.hex("abc"),
                    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
                )
                local service, native = codec()
                for _, case in ipairs(fixtures.hash_vectors) do
                    local details = assert(service.hash(case.logical_path))
                    A.equal(details.algorithm, "SHA-256", case.id)
                    A.equal(details.full_hex, case.full_sha256, case.id)
                    A.equal(details.context_hash, case.context_hash, case.id)
                    A.equal(service.context_hash(case.logical_path), case.context_hash, case.id)
                    A.raises(function() details.context_hash = "changed" end, "cannot be modified")
                end
                A.truthy(native.observations.maximum_chunk_bytes <= 3)
                A.equal(native.observations.starts, #fixtures.hash_vectors * 2)
                A.equal(native.observations.closes, native.observations.starts)
            end,
        },
        {
            name = "selector fixtures reserve exactly sixteen hexadecimal characters",
            run = function()
                local service = codec()
                for _, case in ipairs(fixtures.selector_cases) do
                    local selector = assert(service.classify_selector(case.token))
                    A.equal(selector.kind, case.kind)
                    A.equal(selector.canonical, case.canonical)
                end
                local unicode = assert(service.classify_selector("会话"))
                A.equal(unicode.kind, "name")
                A.equal(unicode.canonical, "会话")
                A.falsy(service.classify_selector(""))
                A.falsy(service.classify_selector("bad\0name"))
            end,
        },
        {
            name = "all injected path limits fail before ambiguous allocation",
            run = function()
                local byte_service = codec({
                    maximum_path_bytes = 8,
                    maximum_segment_bytes = 8,
                    maximum_hash_chunk_bytes = 8,
                })
                local logical, byte_error = byte_service.to_logical("/12345678")
                A.falsy(logical)
                A.equal(byte_error.reason, "path-bytes")

                local segment_service = codec({ maximum_segment_bytes = 3 })
                local segment, segment_error = segment_service.to_logical("/abcd")
                A.falsy(segment)
                A.equal(segment_error.reason, "segment")

                local count_service = codec({ maximum_segments = 2 })
                local count, count_error = count_service.to_logical("/a/b/c")
                A.falsy(count)
                A.equal(count_error.reason, "segments")
            end,
        },
        {
            name = "hash port snapshots methods and rejects malformed terminal results",
            run = function()
                local native = fake_native()
                local service = codec(nil, native)
                native.sha256_finish = function() return "malicious" end
                A.equal(
                    service.context_hash("/home/u/proj/t.xml"),
                    "6317CF575885571D"
                )

                local incomplete, port_error = path.new({}, options())
                A.falsy(incomplete)
                A.equal(port_error.code, "InvalidHashPort")

                local malformed = fake_native()
                malformed.sha256_finish = function() return "short" end
                local malformed_service = codec(nil, malformed)
                local hash, hash_error = malformed_service.context_hash("/a")
                A.falsy(hash)
                A.equal(hash_error.code, "NativeHash")

                local update_failure = fake_native()
                update_failure.sha256_update = function() return false end
                local update_service = codec(nil, update_failure)
                A.falsy(update_service.context_hash("/a"))

                local close_failure = fake_native()
                close_failure.sha256_close = function() return false end
                local close_service = codec(nil, close_failure)
                A.falsy(close_service.context_hash("/a"))

                local invalid_options, options_error = path.new(fake_native(), {
                    maximum_path_bytes = 16,
                    maximum_segments = 4,
                    maximum_segment_bytes = 8,
                    maximum_hash_chunk_bytes = 4,
                    unknown = true,
                })
                A.falsy(invalid_options)
                A.equal(options_error.code, "InvalidPathOptions")
                A.raises(function() service.limits.maximum_segments = 1 end, "cannot be modified")
            end,
        },
    },
}
