--[[
File: index_test.lua
Date: 2026-08-29
Author: WaterRun
Description: Verifies bounded real-time Context ring resolution and stable outcomes.
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

local function read_file(relative_path)
    local handle, open_error = io.open(YACA_TEST_ROOT .. "/" .. relative_path, "rb")
    A.truthy(handle, open_error)
    local bytes = handle:read("a")
    handle:close()
    return bytes
end

local cache = {}
local index = load_module("index", cache)
local path = load_module("path", cache)
local sha256 = load_table("test/support/sha256_reference.lua")

local PATH_METHODS = {
    "validate_logical",
    "validate_context_name",
    "classify_selector",
    "context_file",
    "compare_logical",
    "context_hash",
}

local function hash_port()
    local port = {}
    function port.sha256_start()
        return { parts = {}, finished = false, closed = false }
    end
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

local function path_service(hash_override)
    local base = assert(path.new(hash_port(), {
        maximum_path_bytes = 2048,
        maximum_segments = 128,
        maximum_segment_bytes = 255,
        maximum_hash_chunk_bytes = 7,
    }))
    local calls = { hashes = 0, paths = {} }
    local wrapped = {}
    for _, method in ipairs(PATH_METHODS) do
        if method == "context_hash" then
            function wrapped.context_hash(logical)
                calls.hashes = calls.hashes + 1
                calls.paths[#calls.paths + 1] = logical
                if hash_override then
                    local replacement = hash_override(logical)
                    if replacement ~= nil then return replacement end
                end
                return base.context_hash(logical)
            end
        else
            wrapped[method] = base[method]
        end
    end
    return wrapped, calls, base
end

local function candidate(logical_path, state, changes)
    local name = assert(logical_path:match("/([^/]+)%.xml$"))
    local value = {
        physical_path = "/release/__yaca__/CONTEXT" .. logical_path,
        logical_path = logical_path,
        display_path = "CONTEXT" .. logical_path,
        display_name = name,
        canonical_name = name,
        created_at = "2026-08-29T00:00:00Z",
        updated_at = "2026-08-29T00:00:01Z",
        observed_stat = { object = logical_path, size = 100 },
        header_state = state or "valid",
    }
    for key, item in pairs(changes or {}) do value[key] = item end
    return value
end

local function ring(scope, candidates, changes)
    local value = { scope = scope, complete = true, candidates = candidates or {} }
    for key, item in pairs(changes or {}) do value[key] = item end
    return value
end

local function scanner(initial_rings)
    local controls = {
        rings = initial_rings or {},
        begins = 0,
        nexts = 0,
        closes = 0,
        yielded = {},
        fail_begin = false,
        fail_next = false,
        fail_close = false,
    }
    local port = {}
    function port.begin(origin, limits)
        controls.begins = controls.begins + 1
        controls.last_origin = origin
        controls.last_limits = limits
        if controls.fail_begin then return false, { code = "OpenDenied" } end
        return true, { rings = controls.rings, next = 1, closed = false }
    end
    function port.next_ring(handle)
        assert(not handle.closed)
        controls.nexts = controls.nexts + 1
        if controls.fail_next then return false, { code = "EnumerationChanged" } end
        local current = handle.rings[handle.next]
        handle.next = handle.next + 1
        if current then
            for _, item in ipairs(current.candidates or {}) do
                local logical = item.logical_path or "<malformed>"
                controls.yielded[logical] = (controls.yielded[logical] or 0) + 1
            end
        end
        return true, current
    end
    function port.close(handle)
        assert(not handle.closed)
        handle.closed = true
        controls.closes = controls.closes + 1
        if controls.fail_close then return false, { code = "CloseFailed" } end
        return true
    end
    return port, controls
end

local function options(changes)
    local value = {
        maximum_scan_candidates = 32,
        maximum_search_rings = 8,
        maximum_collision_candidates = 4,
        maximum_reason_bytes = 64,
    }
    for key, item in pairs(changes or {}) do value[key] = item end
    return value
end

local function resolver(rings, settings)
    settings = settings or {}
    local path_port, hash_calls, base = path_service(settings.hash_override)
    local scanner_port, scanner_calls = scanner(rings)
    local service = assert(index.new({ path = path_port, scanner = scanner_port },
        options(settings.options)))
    return service, scanner_calls, hash_calls, base
end

local function catalog_snapshot(physical_path, kind, object)
    return {
        requested_path = physical_path,
        canonical_path = physical_path,
        exists = true,
        identity = {
            kind = kind,
            volume = "catalog-volume",
            object = object or physical_path,
            size = kind == "file" and 128 or 0,
            modified = "1",
        },
        parent_identity = {
            kind = "directory",
            volume = "catalog-volume",
            object = "parent:" .. physical_path,
            size = 0,
            modified = "1",
        },
        metadata = {
            link_count = 1,
            behavior_digest = "behavior:" .. physical_path,
            preservation = "proven",
            link_target = false,
        },
        ancestors = {
            {
                path = "/",
                identity = {
                    kind = "directory",
                    volume = "catalog-volume",
                    object = "root",
                    size = 0,
                    modified = "1",
                },
            },
        },
        ancestry_complete = true,
    }
end

local function filesystem_catalog(settings)
    settings = settings or {}
    local root = "/release/__yaca__/CONTEXT"
    local paths = {
        root .. "/C",
        root .. "/C/sibling",
        root .. "/C/work",
        root .. "/C/work/deep",
        root .. "/D",
        root .. "/C/work/Task.xml",
        root .. "/C/work/Busy.xml",
        root .. "/C/work/Broken.xml",
        root .. "/C/work/folder.xml",
        root .. "/C/work/Task.xml.yaca-prev",
        root .. "/C/work/deep/Deep.xml",
        root .. "/C/sibling/Task.xml",
        root .. "/D/Far.xml",
    }
    local directories = {
        [root] = true,
        [root .. "/C"] = true,
        [root .. "/C/sibling"] = true,
        [root .. "/C/work"] = true,
        [root .. "/C/work/deep"] = true,
        [root .. "/D"] = true,
        [root .. "/C/work/folder.xml"] = true,
    }
    local controls = {
        root = root,
        walks = 0,
        header_paths = {},
        generations = {},
        unstable = settings.unstable,
    }
    local filesystem = {}
    function filesystem.direct_inspect(physical_path)
        if directories[physical_path] then
            return true, catalog_snapshot(physical_path, "directory")
        end
        for _, candidate_path in ipairs(paths) do
            if candidate_path == physical_path then
                return true, catalog_snapshot(physical_path, "file")
            end
        end
        return false, { code = "NotFound" }
    end
    function filesystem.direct_reverify(snapshot)
        return true, snapshot
    end
    function filesystem.direct_walk(snapshot, depth, maximum)
        controls.walks = controls.walks + 1
        local entries = {}
        local prefix = snapshot.requested_path .. "/"
        for _, physical_path in ipairs(paths) do
            if physical_path:sub(1, #prefix) == prefix then
                local relative = physical_path:sub(#prefix + 1)
                local levels = 1
                for _ in relative:gmatch("/") do levels = levels + 1 end
                if levels <= depth + 1 then
                    entries[#entries + 1] = {
                        relative_path = relative,
                        snapshot = catalog_snapshot(
                            physical_path,
                            directories[physical_path] and "directory" or "file"
                        ),
                    }
                end
            end
        end
        table.sort(entries, function(left, right)
            return left.relative_path < right.relative_path
        end)
        while #entries > maximum do entries[#entries] = nil end
        local generation = snapshot.requested_path .. ":"
            .. (controls.generations[snapshot.requested_path] or "stable")
        if controls.unstable and controls.walks % 2 == 0 then
            generation = snapshot.requested_path .. ":changed"
        end
        return true, {
            generation = generation,
            entries = entries,
            complete = true,
            partial_reason = false,
        }
    end
    local store = {}
    function store.inspect_writer(physical_path)
        if physical_path:sub(-9) == "/Busy.xml" then
            return {
                busy = true,
                pid = 42,
                metadata_state = "valid",
            }
        end
        return { busy = false, pid = "unknown", metadata_state = "absent" }
    end
    function store.inspect_catalog_header(physical_path)
        controls.header_paths[#controls.header_paths + 1] = physical_path
        if physical_path:sub(-11) == "/Broken.xml" then
            return nil, { code = "ContextSchema" }
        end
        local name = assert(physical_path:match("/([^/]+)%.xml$"))
        return {
            name = name,
            created_at = "2026-08-29T00:00:00Z",
            updated_at = "2026-08-29T00:00:01Z",
        }, {
            bytes_read = 256,
            body_opened = false,
        }
    end
    local _, _, path_port = path_service()
    local scanner_port, verifier_port, scanner_error = index.new_filesystem_scanner({
        filesystem = filesystem,
        store = store,
        path = path_port,
    }, {
        context_root = root,
        platform_kind = "posix",
        maximum_walk_depth = 16,
        maximum_walk_entries = 32,
    })
    A.truthy(scanner_port, scanner_error and scanner_error.code)
    return scanner_port, verifier_port, path_port, controls
end

local function outcome_line(id, outcome)
    if outcome.tag == "Unique" then
        return table.concat({ id, outcome.tag, outcome.logical_path, outcome.hash }, "\t")
    end
    if outcome.tag == "HashCollision" then
        local candidates = {}
        for _, item in ipairs(outcome.candidates) do
            candidates[#candidates + 1] = item.logical_path .. "@" .. item.hash
        end
        return table.concat({ id, outcome.tag, table.concat(candidates, ",") }, "\t")
    end
    if outcome.tag == "MatchedUnavailable" then
        return table.concat({
            id,
            outcome.tag,
            outcome.logical_path or "-",
            outcome.reason,
        }, "\t")
    end
    if outcome.tag == "ScanIncomplete" then
        return table.concat({ id, outcome.tag, outcome.scope, outcome.reason }, "\t")
    end
    return table.concat({ id, outcome.tag }, "\t")
end

return {
    name = "unit/index",
    cases = {
        {
            name = "construction snapshots narrow ports and mandatory hard limits",
            run = function()
                local path_port = path_service()
                local scanner_port = scanner({})
                local service = assert(index.new({ path = path_port, scanner = scanner_port },
                    options()))
                A.equal(service.capabilities.persistent_index, false)
                A.equal(service.capabilities.real_time_scan, true)
                A.equal(service.limits.maximum_scan_candidates, 32)
                A.raises(function() service.limits.maximum_scan_candidates = 100 end,
                    "cannot be modified")
                A.falsy(index.new({}, options()))
                A.falsy(index.new({ path = path_port, scanner = {} }, options()))
                A.falsy(index.new({ path = path_port, scanner = scanner_port }, {}))
                A.falsy(index.new({ path = path_port, scanner = scanner_port },
                    options({ extra = 1 })))
                A.falsy(index.new({ path = path_port, scanner = scanner_port },
                    options({ maximum_collision_candidates = 1 })))
            end,
        },
        {
            name = "path service admits official XML only and compares exact bytes",
            run = function()
                local _, _, base = path_service()
                local details = assert(base.context_file("/C/工作/任务.xml"))
                A.equal(details.parent, "/C/工作")
                A.equal(details.leaf, "任务.xml")
                A.equal(details.display_name, "任务")
                A.falsy(base.context_file("/C/工作/任务.xml.yaca-prev"))
                A.falsy(base.context_file("/C/工作/任务.xml.yaca-lock"))
                A.falsy(base.context_file("/C/工作/.xml"))
                A.equal(assert(base.compare_logical("/C/A.xml", "/C/a.xml")), -1)
                A.equal(assert(base.parent("/C/工作/任务.xml")), "/C/工作")
                A.equal(assert(base.parent("/")), "/")
                A.falsy(base.validate_context_name("../任务"))
                A.falsy(base.validate_context_name("bad\nname"))
            end,
        },
        {
            name = "invalid selector and origin fail before any catalog enumeration",
            run = function()
                local service, scan = resolver({})
                local empty = service.resolve("", "/C/work")
                local separator = service.resolve("../Task", "/C/work")
                local origin = service.resolve("Task", "relative")
                A.equal(empty.tag, "InvalidSelector")
                A.equal(empty.reason, "type")
                A.equal(separator.tag, "InvalidSelector")
                A.equal(separator.reason, "separator")
                A.equal(origin.tag, "ScanIncomplete")
                A.equal(origin.reason, "invalid-origin")
                A.equal(scan.begins, 0)
            end,
        },
        {
            name = "name resolution uses nearest ring then byte-stable logical order",
            run = function()
                local rings = {
                    ring("/C/work", {}),
                    ring("/C", {
                        candidate("/C/z/Task.xml"),
                        candidate("/C/a/Task.xml"),
                        candidate("/C/m/Other.xml"),
                    }),
                    ring("/", { candidate("/D/Task.xml") }),
                }
                local service, scan, hashes = resolver(rings)
                local outcome = service.resolve("Task", "/C/work")
                A.equal(outcome.tag, "Unique")
                A.equal(outcome.logical_path, "/C/a/Task.xml")
                A.equal(outcome.hash, "AC491D360D0835D4")
                A.equal(scan.nexts, 2)
                A.equal(scan.closes, 1)
                A.equal(hashes.hashes, 1)
                A.deep_equal(hashes.paths, { "/C/a/Task.xml" })
                for logical, count in pairs(scan.yielded) do
                    A.equal(count, 1, logical)
                end
                A.raises(function() outcome.logical_path = "/changed.xml" end,
                    "cannot be modified")
            end,
        },
        {
            name = "first damaged name is fail-stop and incomplete ring has precedence",
            run = function()
                local service, scan, hashes = resolver({
                    ring("/C/work", {}),
                    ring("/C", {
                        candidate("/C/z/Task.xml"),
                        candidate("/C/a/Task.xml", "corrupt"),
                    }),
                    ring("/", { candidate("/D/Task.xml") }),
                })
                local damaged = service.resolve("Task", "/C/work")
                A.equal(damaged.tag, "MatchedUnavailable")
                A.equal(damaged.logical_path, "/C/a/Task.xml")
                A.equal(damaged.reason, "header-corrupt")
                A.equal(scan.nexts, 2)
                A.equal(hashes.hashes, 0)

                local partial_service, partial_scan = resolver({
                    ring("/C/work", { candidate("/C/work/Task.xml") }, {
                        complete = false,
                        reason = "PermissionDenied",
                    }),
                    ring("/", { candidate("/D/Task.xml") }),
                })
                local partial = partial_service.resolve("Task", "/C/work")
                A.equal(partial.tag, "ScanIncomplete")
                A.equal(partial.scope, "/C/work")
                A.equal(partial.reason, "PermissionDenied")
                A.equal(partial_scan.nexts, 1)
            end,
        },
        {
            name = "hash scans the complete nearest ring and farther rings cannot overturn it",
            run = function()
                local target_hash = "1111111111111111"
                local service, scan, hashes = resolver({
                    ring("/C/work", {
                        candidate("/C/work/z.xml"),
                        candidate("/C/work/target.xml"),
                        candidate("/C/work/a.xml"),
                    }),
                    ring("/", {
                        candidate("/D/one.xml"),
                        candidate("/D/two.xml"),
                    }),
                }, {
                    hash_override = function(logical)
                        if logical == "/C/work/target.xml"
                            or logical == "/D/one.xml"
                            or logical == "/D/two.xml"
                        then return target_hash end
                    end,
                })
                local outcome = service.resolve(target_hash:lower(), "/C/work")
                A.equal(outcome.tag, "Unique")
                A.equal(outcome.logical_path, "/C/work/target.xml")
                A.equal(outcome.hash, target_hash)
                A.equal(scan.nexts, 1)
                A.equal(hashes.hashes, 3)
                A.deep_equal(hashes.paths, {
                    "/C/work/a.xml",
                    "/C/work/target.xml",
                    "/C/work/z.xml",
                })
            end,
        },
        {
            name = "hash collision is bounded and emitted in stable logical order",
            run = function()
                local collision = "AAAAAAAAAAAAAAAA"
                local service = resolver({
                    ring("/C/work", {
                        candidate("/C/work/z.xml"),
                        candidate("/C/work/a.xml"),
                        candidate("/C/work/m.xml"),
                    }),
                }, {
                    hash_override = function() return collision end,
                    options = { maximum_collision_candidates = 2 },
                })
                local outcome = service.resolve(collision, "/C/work")
                A.equal(outcome.tag, "HashCollision")
                A.equal(#outcome.candidates, 2)
                A.deep_equal({
                    outcome.candidates[1].logical_path,
                    outcome.candidates[2].logical_path,
                }, { "/C/work/a.xml", "/C/work/m.xml" })
                A.raises(function() outcome.candidates[1].hash = "changed" end,
                    "cannot be modified")
            end,
        },
        {
            name = "hash unavailable mixtures follow usable-count rules",
            run = function()
                local target_hash = "BBBBBBBBBBBBBBBB"
                local function collision_path() return target_hash end
                local unavailable_service = resolver({
                    ring("/C/work", {
                        candidate("/C/work/z.xml", "unavailable"),
                        candidate("/C/work/a.xml", "corrupt"),
                    }),
                }, { hash_override = collision_path })
                local unavailable = unavailable_service.resolve(target_hash, "/C/work")
                A.equal(unavailable.tag, "MatchedUnavailable")
                A.equal(unavailable.logical_path, "/C/work/a.xml")

                local usable_service = resolver({
                    ring("/C/work", {
                        candidate("/C/work/bad.xml", "changed"),
                        candidate("/C/work/good.xml"),
                    }),
                }, { hash_override = collision_path })
                local usable = usable_service.resolve(target_hash, "/C/work")
                A.equal(usable.tag, "Unique")
                A.equal(usable.logical_path, "/C/work/good.xml")
            end,
        },
        {
            name = "not found performs no name hashes and fresh scans observe live changes",
            run = function()
                local service, scan, hashes = resolver({
                    ring("/C/work", { candidate("/C/work/Other.xml") }),
                    ring("/", { candidate("/D/Else.xml") }),
                })
                local missing = service.resolve("Task", "/C/work")
                A.equal(missing.tag, "NotFound")
                A.equal(hashes.hashes, 0)
                A.equal(scan.begins, 1)
                A.equal(scan.closes, 1)

                scan.rings = { ring("/C/work", { candidate("/C/work/Task.xml") }) }
                local found = service.resolve("Task", "/C/work")
                A.equal(found.tag, "Unique")
                A.equal(found.logical_path, "/C/work/Task.xml")
                A.equal(scan.begins, 2)
                A.equal(scan.closes, 2)
            end,
        },
        {
            name = "caps duplicates malformed candidates and scanner faults fail closed",
            run = function()
                local capped = resolver({
                    ring("/C/work", {
                        candidate("/C/work/a.xml"),
                        candidate("/C/work/b.xml"),
                        candidate("/C/work/c.xml"),
                    }),
                }, { options = {
                    maximum_scan_candidates = 2,
                    maximum_collision_candidates = 2,
                } })
                A.equal(capped.resolve("missing", "/C/work").reason, "scan-limit")

                local duplicate = resolver({
                    ring("/C/work", { candidate("/C/work/a.xml") }),
                    ring("/", { candidate("/C/work/a.xml") }),
                })
                A.equal(duplicate.resolve("missing", "/C/work").reason,
                    "duplicate-candidate")

                local malformed_candidate = candidate("/C/work/a.xml")
                malformed_candidate.extra = true
                local malformed = resolver({ ring("/C/work", { malformed_candidate }) })
                A.equal(malformed.resolve("missing", "/C/work").reason,
                    "candidate-contract")

                local faulted, fault_scan = resolver({})
                fault_scan.fail_next = true
                local fault = faulted.resolve("missing", "/C/work")
                A.equal(fault.tag, "ScanIncomplete")
                A.equal(fault.reason, "EnumerationChanged")
                A.equal(fault_scan.closes, 1)
            end,
        },
        {
            name = "status hashes the bound logical path without opening a scanner",
            run = function()
                local service, scan, hashes = resolver({
                    ring("/", { candidate("/C/work/Alpha.xml") }),
                })
                A.equal(service.current_hash("/C/work/Alpha.xml"), "170613A156579BA8")
                A.equal(scan.begins, 0)
                A.equal(hashes.hashes, 1)
                A.falsy(service.current_hash("/C/work/not-context.txt"))
                A.equal(scan.begins, 0)
            end,
        },
        {
            name = "filesystem scanner yields stable incremental rings without reading locks",
            run = function()
                local scanner_port, verifier_port, path_port, controls = filesystem_catalog()
                local began, handle = scanner_port.begin("/C/work", {
                    maximum_scan_candidates = 32,
                    maximum_search_rings = 8,
                })
                A.truthy(began)
                local ok, near = scanner_port.next_ring(handle)
                A.truthy(ok)
                A.equal(near.scope, "/C/work")
                A.equal(#near.candidates, 3)
                A.deep_equal({
                    near.candidates[1].display_name,
                    near.candidates[2].display_name,
                    near.candidates[3].display_name,
                }, { "Broken", "Busy", "Task" })
                A.equal(near.candidates[1].header_state, "corrupt")
                A.equal(near.candidates[2].header_state, "unavailable")
                A.equal(near.candidates[3].header_state, "valid")

                local _, parent_ring = scanner_port.next_ring(handle)
                A.equal(parent_ring.scope, "/C")
                A.equal(#parent_ring.candidates, 2)
                A.deep_equal({
                    parent_ring.candidates[1].logical_path,
                    parent_ring.candidates[2].logical_path,
                }, { "/C/sibling/Task.xml", "/C/work/deep/Deep.xml" })

                local _, root_ring = scanner_port.next_ring(handle)
                A.equal(root_ring.scope, "/")
                A.equal(#root_ring.candidates, 1)
                A.equal(root_ring.candidates[1].logical_path, "/D/Far.xml")
                local _, finished = scanner_port.next_ring(handle)
                A.equal(finished, nil)
                A.truthy(scanner_port.close(handle))
                local status = assert(scanner_port.status(handle))
                A.equal(status.candidates, 6)
                A.equal(status.valid, 4)
                A.equal(status.corrupt, 1)
                A.equal(status.unavailable, 1)
                A.equal(status.busy, 1)
                A.equal(#controls.header_paths, 5)
                for _, physical_path in ipairs(controls.header_paths) do
                    A.falsy(physical_path:sub(-9) == "/Busy.xml")
                    A.falsy(physical_path:find(".yaca-prev", 1, true))
                end

                local catalog = assert(index.new({
                    path = path_port,
                    scanner = scanner_port,
                    verifier = verifier_port,
                }, options()))
                local selected = catalog.resolve("Task", "/C/work")
                A.equal(selected.logical_path, "/C/work/Task.xml")
                local verified = catalog.verify_target(selected, "open")
                A.equal(verified.tag, "Verified")
                A.equal(verified.logical_path, "/C/work/Task.xml")
            end,
        },
        {
            name = "filesystem scanner rejects a directory generation change",
            run = function()
                local scanner_port = filesystem_catalog({ unstable = true })
                local _, handle = scanner_port.begin("/C/work", {
                    maximum_scan_candidates = 32,
                    maximum_search_rings = 8,
                })
                local _, ring_value = scanner_port.next_ring(handle)
                A.falsy(ring_value.complete)
                A.equal(ring_value.reason, "EnumerationChanged")
                A.equal(#ring_value.candidates, 0)
                local status = assert(scanner_port.status(handle))
                A.falsy(status.complete)
                A.equal(status.partial_reason, "EnumerationChanged")
                A.truthy(scanner_port.close(handle))
            end,
        },
        {
            name = "farther ring fails when an already-scanned nearer ring changes",
            run = function()
                local scanner_port, _, _, controls = filesystem_catalog()
                local _, handle = scanner_port.begin("/C/work", {
                    maximum_scan_candidates = 32,
                    maximum_search_rings = 8,
                })
                local _, near = scanner_port.next_ring(handle)
                A.truthy(near.complete)
                controls.generations[controls.root .. "/C/work"] = "changed"
                local _, parent_ring = scanner_port.next_ring(handle)
                A.falsy(parent_ring.complete)
                A.equal(parent_ring.reason, "EnumerationChanged")
                A.equal(#parent_ring.candidates, 0)
                A.truthy(scanner_port.close(handle))
            end,
        },
        {
            name = "catalog-root origin covers every nested Context in one ring",
            run = function()
                local scanner_port = filesystem_catalog()
                local _, handle = scanner_port.begin("/", {
                    maximum_scan_candidates = 32,
                    maximum_search_rings = 8,
                })
                local _, root_ring = scanner_port.next_ring(handle)
                A.equal(root_ring.scope, "/")
                A.truthy(root_ring.complete)
                A.equal(#root_ring.candidates, 6)
                A.deep_equal({
                    root_ring.candidates[1].logical_path,
                    root_ring.candidates[6].logical_path,
                }, { "/C/sibling/Task.xml", "/D/Far.xml" })
                local _, finished = scanner_port.next_ring(handle)
                A.equal(finished, nil)
                A.truthy(scanner_port.close(handle))
            end,
        },
        {
            name = "resolver outcome corpus matches the deterministic golden file",
            run = function()
                local lines = {}
                local name_service = resolver({
                    ring("/C/work", { candidate("/C/work/Alpha.xml") }),
                })
                lines[#lines + 1] = outcome_line(
                    "near-name",
                    name_service.resolve("Alpha", "/C/work")
                )

                local damaged_service = resolver({
                    ring("/C/work", { candidate("/C/work/Alpha.xml", "corrupt") }),
                })
                lines[#lines + 1] = outcome_line(
                    "damaged-name",
                    damaged_service.resolve("Alpha", "/C/work")
                )

                local collision = "AAAAAAAAAAAAAAAA"
                local collision_service = resolver({
                    ring("/C/work", {
                        candidate("/C/work/z.xml"),
                        candidate("/C/work/a.xml"),
                    }),
                }, { hash_override = function() return collision end })
                lines[#lines + 1] = outcome_line(
                    "hash-collision",
                    collision_service.resolve(collision, "/C/work")
                )

                local partial_service = resolver({
                    ring("/C/work", {}, { complete = false, reason = "DirectoryUnreadable" }),
                })
                lines[#lines + 1] = outcome_line(
                    "partial",
                    partial_service.resolve("Alpha", "/C/work")
                )

                local missing_service = resolver({ ring("/C/work", {}) })
                lines[#lines + 1] = outcome_line(
                    "missing",
                    missing_service.resolve("Alpha", "/C/work")
                )
                A.equal(table.concat(lines, "\n") .. "\n", read_file("test/golden/resolver"))
            end,
        },
    },
}
