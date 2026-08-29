--[[
File: lxp_corpus_test.lua
Date: 2026-08-29
Author: WaterRun
Description: Locks the pinned parser build and Context reference-reader corpus.
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

local function read_all(relative_path)
    local handle, open_error = io.open(YACA_TEST_ROOT .. "/" .. relative_path, "rb")
    A.truthy(handle, open_error)
    local value = assert(handle:read("a"))
    assert(handle:close())
    return value
end

local xml = load_module("xml")
local fake_lxp = load_table("test/support/fake_lxp.lua")
local build = load_table("native/lxp_build.lua")
local release = load_table("release/manifest.lua")
local proof = load_table(".develope-docs/proofs/modern-2026-08-29/manifest.lua")
local fixture = read_all(".develope-docs/contracts/fixtures/context-minimal.xml")
local rng = read_all(".develope-docs/contracts/context.rng")

local function emit_leaf(callbacks, name, value, attributes)
    callbacks.StartElement(nil, name, attributes or {})
    if value ~= nil and value ~= "" then callbacks.CharacterData(nil, value) end
    callbacks.EndElement(nil, name)
end

local function emit_field(callbacks, name, value)
    emit_leaf(callbacks, "Field", value, { name = name })
end

local function emit_fixture(callbacks)
    callbacks.XmlDecl(nil, "1.0", "UTF-8")
    callbacks.StartElement(nil, "YacaContext", {
        schemaVersion = "0.1.0",
        generation = "1",
    })
    callbacks.StartElement(nil, "Header", {})
    emit_leaf(callbacks, "Name", "Untitled Conversation [0A1B]")
    emit_leaf(callbacks, "CreatedAt", "2026-08-29T00:00:00Z")
    emit_leaf(callbacks, "UpdatedAt", "2026-08-29T00:00:01Z")
    emit_leaf(callbacks, "AutoRenameDisabled", "false")
    emit_leaf(callbacks, "NamingWaterline", "0")
    emit_leaf(callbacks, "AutoNameBaseline", "0")
    callbacks.EndElement(nil, "Header")

    callbacks.StartElement(nil, "Session", {})
    emit_leaf(callbacks, "CurrentModel", nil, {
        name = "Local",
        snapshotDigest = "sha256:model-snapshot",
    })
    emit_leaf(callbacks, "CurrentPermission", nil, {
        name = "Std",
        snapshotDigest = "sha256:permission-snapshot",
    })
    emit_leaf(callbacks, "DoubleCheckOverride", "inherit")
    emit_leaf(callbacks, "DoubleCheckGoalOverride", nil, { mode = "inherit" })
    emit_leaf(callbacks, "ContextPrompt", "")
    callbacks.EndElement(nil, "Session")

    callbacks.StartElement(nil, "Facts", {})
    callbacks.StartElement(nil, "Event", {
        seq = "1",
        type = "turn_started",
        at = "2026-08-29T00:00:00Z",
        turnId = "turn-1",
    })
    emit_field(callbacks, "kind", "main")
    emit_field(callbacks, "configGeneration", "sha256:config-generation")
    emit_field(callbacks, "modelSnapshot", "sha256:model-snapshot")
    emit_field(callbacks, "permissionSnapshot", "sha256:permission-snapshot")
    emit_field(callbacks, "promptSnapshot", "sha256:prompt-snapshot")
    emit_field(callbacks, "toolRegistrySnapshot", "sha256:tool-registry")
    callbacks.EndElement(nil, "Event")
    callbacks.StartElement(nil, "Event", {
        seq = "2",
        type = "user_message",
        at = "2026-08-29T00:00:01Z",
        turnId = "turn-1",
    })
    emit_field(callbacks, "messageId", "message-1")
    emit_field(callbacks, "text", "hello")
    emit_field(callbacks, "source", "main")
    callbacks.EndElement(nil, "Event")
    callbacks.EndElement(nil, "Facts")

    callbacks.StartElement(nil, "ModelView", {})
    emit_leaf(callbacks, "ActiveManifest", nil, {
        digest = "sha256:view-manifest",
        firstEventSeq = "1",
        lastEventSeq = "2",
    })
    callbacks.EndElement(nil, "ModelView")
    callbacks.EndElement(nil, "YacaContext")
end

local function reference_dispatch(document, callbacks)
    if document == fixture then
        emit_fixture(callbacks)
        return true
    end
    if document == "unknown-element" then
        callbacks.StartElement(nil, "YacaContext", {})
        callbacks.StartElement(nil, "Unknown", {})
        callbacks.EndElement(nil, "Unknown")
        callbacks.EndElement(nil, "YacaContext")
        return true
    end
    return false, "reference fixture mismatch", 1, 1, 1
end

local function reference_codec()
    local lxp = fake_lxp(reference_dispatch)
    local service = assert(xml.new({
        lxp = lxp,
        maximum_bytes = 4096,
        maximum_depth = 32,
        maximum_elements = 128,
        maximum_attributes_per_element = 8,
        maximum_text_node_bytes = 512,
        maximum_total_text_bytes = 2048,
        maximum_sax_events = 256,
        maximum_context_events = 16,
        maximum_carrier_bytes = 1024,
        maximum_chunk_bytes = 17,
    }))
    return service, lxp
end

local function allowed_rng_elements()
    local allowed = {}
    for name in rng:gmatch('<element name="([^"]+)">') do allowed[name] = true end
    return allowed
end

return {
    name = "reference/lxp-corpus",
    cases = {
        {
            name = "build recipe and runtime identity match every pinned manifest",
            run = function()
                for _, name in ipairs({ "lua", "expat", "luaexpat" }) do
                    A.equal(build.lock[name].version, release.dependencies[name].version)
                    A.equal(build.lock[name].sha256, release.dependencies[name].sha256)
                    A.equal(build.lock[name].sha256, proof.source_pins[name].sha256)
                end
                A.contains(build.lock.expat.url, "R_2_8_2")
                A.contains(build.lock.luaexpat.url, "1.5.2")
                A.same_items(build.expat_cmake_arguments, {
                    "-DCMAKE_BUILD_TYPE=Release",
                    "-DCMAKE_POSITION_INDEPENDENT_CODE=ON",
                    "-DEXPAT_SHARED_LIBS=OFF",
                    "-DEXPAT_BUILD_DOCS=OFF",
                    "-DEXPAT_BUILD_EXAMPLES=OFF",
                    "-DEXPAT_BUILD_TESTS=OFF",
                    "-DEXPAT_BUILD_TOOLS=OFF",
                })
                A.equal(build.luaexpat_compile.entry_point, "luaopen_lxp")
                A.equal(build.luaexpat_compile.expat_linkage, "verified-static-archive")
                A.same_items(build.luaexpat_compile.forbidden_linkage, {
                    "host-libexpat", "rpath", "runpath",
                })
                local formats = {
                    ["win32-x86"] = "PE32-i386",
                    ["win64-x86_64"] = "PE32+-x86-64",
                    ["linux-x86_64"] = "ELF64-x86-64",
                }
                for target, object_format in pairs(formats) do
                    local plan = assert(build.plan(target))
                    A.equal(plan.object_format, object_format)
                    A.equal(plan.lua_abi, "5.5")
                    A.equal(plan.expat_linkage, "verified-static-archive")
                end
                A.falsy(build.plan("unknown"))
                local lxp = fake_lxp(reference_dispatch)
                A.truthy(build.validate_runtime(lxp))
                lxp._VERSION = "LuaExpat 1.5.1"
                A.falsy(build.validate_runtime(lxp))
            end,
        },
        {
            name = "reference reader admits the RNG vocabulary and ordered root children",
            run = function()
                local service = reference_codec()
                local allowed = allowed_rng_elements()
                local counts = {}
                local root_children = {}
                local root_attributes
                local stats = assert(service.parse(fixture, {
                    start_element = function(name, attributes, path)
                        if not allowed[name] then return false, "RNG unknown element: " .. name end
                        counts[name] = (counts[name] or 0) + 1
                        if path == "/YacaContext" then root_attributes = attributes end
                        if path:match("^/YacaContext/[^/]+$") then
                            root_children[#root_children + 1] = name
                        end
                    end,
                }))
                A.deep_equal(root_children, { "Header", "Session", "Facts", "ModelView" })
                A.equal(root_attributes.schemaVersion, "0.1.0")
                A.equal(root_attributes.generation, "1")
                A.equal(counts.YacaContext, 1)
                A.equal(counts.Event, 2)
                A.equal(counts.Field, 9)
                A.equal(stats.elements, 28)
                A.equal(stats.context_events, 2)
                A.equal(stats.external_entity_opens, 0)

                local rejected, reference_error = service.parse("unknown-element", {
                    start_element = function(name)
                        if not allowed[name] then return false, "RNG unknown element" end
                    end,
                })
                A.falsy(rejected)
                A.equal(reference_error.code, "XmlConsumer")
            end,
        },
        {
            name = "every fixture split position preserves the same bounded parse",
            run = function()
                local service, lxp = reference_codec()
                for position = 0, #fixture do
                    local stats, parse_error = service.parse({
                        fixture:sub(1, position),
                        fixture:sub(position + 1),
                    })
                    A.truthy(stats, "split " .. position .. ": " .. A.render(parse_error))
                    A.equal(stats.elements, 28)
                    A.equal(stats.context_events, 2)
                end
                A.truthy(lxp.observations.maximum_chunk_bytes <= 17)
                A.equal(lxp.observations.parser_count, #fixture + 1)
            end,
        },
        {
            name = "modern native corpus evidence stays explicit about target gaps",
            run = function()
                local selected
                for _, candidate in ipairs(proof.proofs) do
                    if candidate.id == "TP-010" then selected = candidate end
                end
                A.truthy(selected)
                A.equal(selected.status, "proven-modern")
                A.truthy(selected.assertions > 5500000)
                A.contains(selected.scope, "pinned-source-build")
                A.same_items(selected.target_pending, {
                    "Win32 x86 build/load",
                    "Win64 build/load",
                    "CentOS 7 runtime",
                    "target resource limits",
                })
                A.falsy(proof.conclusions.target_qualification_complete)
                A.falsy(proof.conclusions.release_gate_open)
            end,
        },
    },
}
