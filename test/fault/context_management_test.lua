--[[
Author: WaterRun
Date: 2026-09-23
File: context_management_test.lua
Description: Verifies identity-bound Context lifecycle and permanent management transactions.
]]

local A = assert(loadfile(YACA_TEST_ROOT .. "/test/support/assert.lua", "t", _ENV))()

--Loads a source module into an isolated per-case environment.
--@param name string Module, Model, or resource name selected by the case.
--@param cache table Per-case module cache preserving isolated imports.
--@return any module Module export loaded in the isolated source environment.
local function load_module(name, cache)
    cache = cache or {}
    if cache[name] then return cache[name] end
    local environment = {
        --Resolves an imported Lua module through the isolated test loader.
        --@param dependency string Source module requested from the isolated loader.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        require = function(dependency)
        return load_module(dependency, cache)
    end }
    environment._G = environment
    --@metatable environment Test-owned lookup and mutation contract for the current case.
    --@field __index any Fallback table or function used for missing fixture keys.
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

--Loads a repository Lua module as a test support value.
--@param relative_path string Repository-relative Lua source path to load.
--@return any module Test support module export loaded from the repository.
local function load_table(relative_path)
    local chunk, load_error = loadfile(YACA_TEST_ROOT .. "/" .. relative_path, "t", _ENV)
    A.truthy(chunk, load_error)
    return chunk()
end

local cache = {}
local harness = load_table("test/support/context_store_harness.lua")
local sha256 = load_table("test/support/sha256_reference.lua")
local modules = {
    context = load_module("context", cache),
    index = load_module("index", cache),
    path = load_module("path", cache),
    xml = load_module("xml", cache),
    fs = load_module("fs", cache),
    fake_lxp = load_table("test/support/fake_lxp.lua"),
    sha256 = sha256,
    fake_filesystem = load_table("test/support/fake_filesystem.lua"),
}

local TARGET = "/data/Task.xml"
local RENAMED = "/data/Renamed.xml"
local REBOUND = "/other/Task.xml"
local PREVIOUS = TARGET .. ".yaca-prev"
local LOCK = TARGET .. ".yaca-lock"

--Constructs an incremental SHA-256 port backed by the reference digest.
--@param none No arguments; this closure uses its captured fixture state.
--@return any port Incremental SHA-256 fixture port.
local function hash_port()
    local port = {}
    --Starts a fake incremental SHA-256 handle.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return table handle New incremental SHA-256 fixture handle.
    function port.sha256_start() return { parts = {} } end
    --Adds bytes to the fake incremental SHA-256 handle.
    --@param handle table|integer Fake resource handle whose state is inspected.
    --@param bytes string Byte chunk supplied to the fake I/O port.
    --@return boolean accepted Whether the fixture accepted the byte chunk.
    function port.sha256_update(handle, bytes)
        handle.parts[#handle.parts + 1] = bytes
        return true
    end
    --Finalizes the fake SHA-256 handle using the reference digest.
    --@param handle table|integer Fake resource handle whose state is inspected.
    --@return any digest Hexadecimal digest of the accumulated fixture bytes.
    function port.sha256_finish(handle)
        return sha256.digest(table.concat(handle.parts))
    end
    --Closes the fake SHA-256 handle and records its state.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean closed Whether the fixture handle was closed.
    function port.sha256_close() return true end
    return port
end

--Constructs the path service service used by this suite.
--@param none No arguments; this closure uses its captured fixture state.
--@return any observed path service value observed by the scenario assertion.
local function path_service()
    return assert(modules.path.new(hash_port(), {
        maximum_path_bytes = 2048,
        maximum_segments = 128,
        maximum_segment_bytes = 255,
        maximum_hash_chunk_bytes = 7,
    }))
end

--Supplies candidate for behavior required by this suite.
--@param fixture table Test fixture state shared by this helper.
--@param physical_path string Physical file path supplied to the fixture.
--@param logical_path string Logical Context path supplied to the fixture.
--@param state table|string Current state observed by the fixture.
--@param changes table Proposed changes exercised by the case.
--@return any observed Selected fixture value returned by the fixture.
local function candidate_for(fixture, physical_path, logical_path, state, changes)
    local name = assert(logical_path:match("/([^/]+)%.xml$"))
    local value = {
        physical_path = physical_path,
        logical_path = logical_path,
        display_path = "CONTEXT" .. logical_path,
        display_name = name,
        canonical_name = name,
        created_at = "2026-08-29T00:00:00Z",
        updated_at = "2026-08-29T00:00:01Z",
        observed_stat = fixture.controls.identity(physical_path),
        header_state = state or "valid",
    }
    for key, item in pairs(changes or {}) do value[key] = item end
    return value
end

--Supplies index service behavior required by this suite.
--@param observations any The observations supplied to the fake service for this scenario.
--@param rings any The rings supplied to the fake service for this scenario.
--@return any observed index service value observed by the scenario assertion.
local function index_service(observations, rings)
    local scanner = {}
    --Simulates the begin transition of a fake activity port for this suite.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether begin succeeds in the fixture.
    --@return table secondary2 Structured fixture record with index.
    function scanner.begin()
        return true, { index = 1 }
    end
    --Supplies next ring behavior required by this suite.
    --@param handle table|integer Fake resource handle whose state is inspected.
    --@return boolean accepted Whether next ring succeeds in the fixture.
    --@return any secondary2 Selected fixture value returned by the fixture.
    function scanner.next_ring(handle)
        local value = (rings or {})[handle.index]
        handle.index = handle.index + 1
        return true, value
    end
    --Simulates the close transition of a fake activity port for this suite.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return boolean accepted Whether close succeeds in the fixture.
    function scanner.close() return true end
    local verifier = {}
    --Supplies observe behavior required by this suite.
    --@param request table Request delivered to the fake component.
    --@return boolean|any observed observe value observed by the scenario assertion.
    --@return table|any|nil secondary2 Additional status or structured error from the fixture operation.
    function verifier.observe(request)
        local value = observations[request.physical_path]
        if type(value) == "function" then return value(request) end
        if value == nil then return false, { code = "NotFound" } end
        return true, value
    end
    return assert(modules.index.new({
        path = path_service(),
        scanner = scanner,
        verifier = verifier,
    }, {
        maximum_scan_candidates = 32,
        maximum_search_rings = 8,
        maximum_collision_candidates = 4,
        maximum_reason_bytes = 64,
    }))
end

--Supplies lifecycle behavior required by this suite.
--@param fixture table Test fixture state shared by this helper.
--@param base table|string Original state used to build the candidate.
--@param mutation any The mutation supplied to the fake service for this scenario.
--@return any observed Context document returned by the fixture.
local function lifecycle(fixture, base, mutation)
    local document, mutation_error = fixture.schema.lifecycle_document(base, mutation)
    A.truthy(document, mutation_error and mutation_error.code)
    fixture.register_document(document)
    return document
end

--Supplies rename document behavior required by this suite.
--@param fixture table Test fixture state shared by this helper.
--@param base table|string Original state used to build the candidate.
--@param new_name any The new name supplied to the fake service for this scenario.
--@param manual any The manual supplied to the fake service for this scenario.
--@param updated_at any The updated at supplied to the fake service for this scenario.
--@return any observed rename document value observed by the scenario assertion.
local function rename_document(fixture, base, new_name, manual, updated_at)
    return lifecycle(fixture, base, {
        kind = "rename",
        new_name = new_name,
        manual = manual,
        old_logical_path = "/C/work/Task.xml",
        new_logical_path = "/C/work/" .. new_name .. ".xml",
        updated_at = updated_at or "2026-08-29T00:00:02Z",
        view_manifest_digest = "sha256:rename-view",
    })
end

return {
    name = "fault/context-management",
    cases = {
        {
            name = "read-only inspection rejects a replaced path or late writer before returning data",
            --Verifies read-only inspection rejects a replaced path or late writer before returning data.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify read-only inspection rejects a replaced path or late writer before returning data.
            run = function()
                for _, mutation in ipairs({ "replace", "lock" }) do
                    local fixture = harness.new(modules, { [TARGET] = harness.minimal("Task") })
                    local before = fixture.controls.bytes(TARGET)
                    --Supplies fs close behavior required by the 'read-only inspection rejects a replaced path or late writer before returning data' case.
                    --@param none No arguments; this closure uses its captured fixture state.
                    --@return nil No value; assertions verify read-only inspection rejects a replaced path or late writer before returning data.
                    fixture.hooks.after.fs_close = function()
                        if mutation == "replace" then
                            fixture.controls.external_replace(TARGET, before)
                        else
                            fixture.controls.external_replace(LOCK, "a writer is present")
                        end
                    end
                    local document, document_error = fixture.store.inspect_import(TARGET)
                    A.falsy(document)
                    A.equal(document_error.code, mutation == "replace" and "TargetChanged" or "LockConflict")
                    A.equal(fixture.controls.bytes(TARGET), before)
                    A.falsy(fixture.controls.exists(PREVIOUS))
                end
            end,
        },
        {
            name = "target verifier binds the selected row and never resolves a substitute",
            --Verifies target verifier binds the selected row and never resolves a substitute.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify target verifier binds the selected row and never resolves a substitute.
            run = function()
                local fixture = harness.new(modules, { [TARGET] = harness.minimal("Task") })
                local observed = candidate_for(fixture, TARGET, "/C/work/Task.xml")
                local observations = { [TARGET] = observed }
                local service = index_service(observations)
                local selection = assert(service.capture_target(observed))
                A.equal(selection.tag, "TargetSnapshot")
                local verified = service.verify_target(selection, "mutation")
                A.equal(verified.tag, "Verified", verified.reason)
                A.equal(verified.purpose, "mutation")
                A.deep_equal(verified.credential.observed_stat, observed.observed_stat)
                --Executes the action expected to raise in the 'target verifier binds the selected row and never resolves a substitute' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify target verifier binds the selected row and never resolves a substitute.
                A.raises(function() verified.credential.observed_stat.object = "other" end,
                    "cannot be modified")

                local original_bytes = fixture.controls.bytes(TARGET)
                fixture.controls.external_replace(TARGET, original_bytes)
                local writer, stale_error = fixture.store.open_writer(
                    TARGET,
                    fixture.metadata(),
                    verified.credential
                )
                A.falsy(writer)
                A.equal(stale_error.code, "TargetChanged")
                A.falsy(fixture.controls.exists(LOCK))

                observations[TARGET].updated_at = "2026-08-29T00:00:09Z"
                A.equal(service.verify_target(selection).tag, "TargetChanged")
                observations[TARGET] = nil
                A.equal(service.verify_target(selection).tag, "TargetUnavailable")
                A.equal(service.verify_target({}).reason, "invalid-selection")

                local corrupt = candidate_for(
                    fixture,
                    TARGET,
                    "/C/work/Task.xml",
                    "corrupt",
                    { canonical_name = nil, created_at = nil, updated_at = nil }
                )
                observations[TARGET] = corrupt
                local damaged = assert(service.capture_target(corrupt))
                A.equal(service.verify_target(damaged).tag, "TargetUnavailable")
                local delete_verified = service.verify_target(damaged, "delete")
                A.equal(delete_verified.tag, "Verified")
                A.equal(delete_verified.header_state, "corrupt")
            end,
        },
        {
            name = "manual rename publishes one complete generation no-replace and invalidates hash",
            --Verifies manual rename publishes one complete generation no-replace and invalidates hash.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify manual rename publishes one complete generation no-replace and invalidates hash.
            run = function()
                local initial = harness.minimal("Task")
                local fixture = harness.new(modules, { [TARGET] = initial })
                local observed = candidate_for(fixture, TARGET, "/C/work/Task.xml")
                local service = index_service({ [TARGET] = observed })
                local verified = service.verify_target(
                    assert(service.capture_target(observed)),
                    "mutation"
                )
                local writer, base = assert(fixture.store.open_writer(
                    TARGET,
                    fixture.metadata(),
                    verified.credential
                ))
                local renamed = rename_document(fixture, base, "Renamed", true)
                A.equal(renamed.generation, 2)
                A.equal(renamed.header.name, "Renamed")
                A.equal(renamed.header.created_at, base.header.created_at)
                A.equal(renamed.header.auto_rename_disabled, true)
                A.equal(renamed.facts[3].type, "rename")
                A.equal(renamed.facts[3].fields.manual, "true")
                A.equal(renamed.facts[4].type, "model_view_published")
                local automatic = rename_document(
                    fixture,
                    base,
                    "Automatic",
                    false,
                    "2026-08-29T00:00:03Z"
                )
                A.equal(automatic.header.auto_rename_disabled, false)
                A.equal(automatic.facts[3].fields.manual, "false")

                local receipt = assert(fixture.store.move(
                    writer,
                    renamed,
                    RENAMED,
                    RENAMED .. ".yaca-tmp-rename",
                    "rename"
                ))
                A.equal(receipt.outcome, "moved")
                A.equal(receipt.old_path, TARGET)
                A.equal(receipt.path, RENAMED)
                A.falsy(fixture.controls.exists(TARGET))
                A.truthy(fixture.controls.exists(RENAMED))
                A.falsy(fixture.controls.exists(PREVIOUS))
                A.equal(fixture.store.writer_status(writer).path, RENAMED)
                A.truthy(fixture.store.close_writer(writer))
                A.falsy(fixture.controls.exists(LOCK))
                A.falsy(fixture.controls.exists(RENAMED .. ".yaca-lock"))

                local path = path_service()
                local old_hash = assert(path.context_hash("/C/work/Task.xml"))
                local new_hash = assert(path.context_hash("/C/work/Renamed.xml"))
                A.truthy(old_hash ~= new_hash)
                local new_candidate = candidate_for(
                    fixture,
                    RENAMED,
                    "/C/work/Renamed.xml",
                    "valid",
                    { updated_at = "2026-08-29T00:00:02Z" }
                )
                local catalog = index_service({ [RENAMED] = new_candidate }, {
                    {
                        scope = "/C/work",
                        complete = true,
                        candidates = { new_candidate },
                    },
                })
                A.equal(catalog.resolve(old_hash, "/C/work").tag, "NotFound")
                A.equal(catalog.resolve(new_hash, "/C/work").logical_path,
                    "/C/work/Renamed.xml")

                local collision = harness.new(modules, {
                    [TARGET] = harness.minimal("Task"),
                    [RENAMED] = harness.minimal("Renamed"),
                })
                local collision_writer, collision_base = assert(collision.store.open_writer(
                    TARGET,
                    collision.metadata()
                ))
                local collision_document = rename_document(
                    collision,
                    collision_base,
                    "Renamed",
                    true
                )
                local moved, move_error = collision.store.move(
                    collision_writer,
                    collision_document,
                    RENAMED,
                    RENAMED .. ".yaca-tmp-collision",
                    "rename"
                )
                A.falsy(moved)
                A.equal(move_error.code, "DestinationExists")
                A.truthy(collision.controls.exists(TARGET))
                A.truthy(collision.controls.exists(RENAMED))
                A.truthy(collision.store.close_writer(collision_writer))
            end,
        },
        {
            name = "rebind is a distinct cross-directory transaction and restores on publish failure",
            --Verifies rebind is a distinct cross-directory transaction and restores on publish failure.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify rebind is a distinct cross-directory transaction and restores on publish failure.
            run = function()
                local fixture = harness.new(modules, { [TARGET] = harness.minimal("Task") })
                local writer, base = assert(fixture.store.open_writer(TARGET, fixture.metadata()))
                local rebound = lifecycle(fixture, base, {
                    kind = "rebind",
                    old_logical_path = "/C/work/Task.xml",
                    new_logical_path = "/D/project/Task.xml",
                    old_root_identity = "root:C/work",
                    new_root_identity = "root:D/project",
                    updated_at = "2026-08-29T00:00:03Z",
                    view_manifest_digest = "sha256:rebind-view",
                })
                A.equal(rebound.header.name, "Task")
                A.equal(rebound.header.created_at, base.header.created_at)
                A.equal(rebound.facts[3].type, "rebind")
                local receipt = assert(fixture.store.move(
                    writer,
                    rebound,
                    REBOUND,
                    REBOUND .. ".yaca-tmp-rebind",
                    "rebind"
                ))
                A.equal(receipt.action, "rebind")
                A.falsy(fixture.controls.exists(TARGET))
                A.truthy(fixture.controls.exists(REBOUND))
                A.truthy(fixture.store.close_writer(writer))

                local failed = harness.new(modules, { [TARGET] = harness.minimal("Task") })
                local failed_writer, failed_base = assert(failed.store.open_writer(
                    TARGET,
                    failed.metadata()
                ))
                local failed_document = lifecycle(failed, failed_base, {
                    kind = "rebind",
                    old_logical_path = "/C/work/Task.xml",
                    new_logical_path = "/D/project/Task.xml",
                    old_root_identity = "root:C/work",
                    new_root_identity = "root:D/project",
                    updated_at = "2026-08-29T00:00:03Z",
                    view_manifest_digest = "sha256:rebind-failed",
                })
                local old_bytes = failed.controls.bytes(TARGET)
                --Supplies fs rename no replace behavior required by the 'rebind is a distinct cross-directory transaction and restores on publish failure' case.
                --@param _ any Unused callback argument supplied by the port.
                --@param destination string|table Publication destination selected by the case.
                --@return nil No value; assertions verify rebind is a distinct cross-directory transaction and restores on publish failure.
                failed.hooks.before.fs_rename_no_replace = function(_, destination)
                    if destination == REBOUND then failed.controls.faults.rename = true end
                end
                --Supplies fs rename no replace behavior required by the 'rebind is a distinct cross-directory transaction and restores on publish failure' case.
                --@param none No arguments; this closure uses its captured fixture state.
                --@return nil No value; assertions verify rebind is a distinct cross-directory transaction and restores on publish failure.
                failed.hooks.after.fs_rename_no_replace = function()
                    failed.controls.faults.rename = false
                end
                local value, move_error = failed.store.move(
                    failed_writer,
                    failed_document,
                    REBOUND,
                    REBOUND .. ".yaca-tmp-failure",
                    "rebind"
                )
                A.falsy(value)
                A.equal(move_error.code, "InjectedRename")
                A.equal(failed.controls.bytes(TARGET), old_bytes)
                A.falsy(failed.controls.exists(REBOUND))
                A.falsy(failed.controls.exists(PREVIOUS))
                A.truthy(failed.store.close_writer(failed_writer))
            end,
        },
        {
            name = "in-place import is read-only first and mapping cannot activate old approvals",
            --Verifies in-place import is read-only first and mapping cannot activate old approvals.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify in-place import is read-only first and mapping cannot activate old approvals.
            run = function()
                local fixture = harness.new(modules, {
                    [TARGET] = harness.unresolved("Task"),
                })
                local observed = candidate_for(fixture, TARGET, "/C/work/Task.xml")
                local verifier = index_service({ [TARGET] = observed })
                local verified = verifier.verify_target(
                    assert(verifier.capture_target(observed)),
                    "mutation"
                )
                local imported, report = assert(fixture.store.inspect_import(
                    TARGET,
                    verified.credential
                ))
                A.equal(report.outcome, "validated-readonly")
                A.equal(report.history_approvals, "audit-only")
                A.equal(report.local_mapping_required, true)
                A.equal(report.auto_replay, false)
                A.equal(report.auto_continue, false)
                A.deep_equal(report.unresolved_operation_ids, { "operation-1" })
                A.falsy(fixture.controls.exists(LOCK))

                local writer, base = assert(fixture.store.open_writer(
                    TARGET,
                    fixture.metadata(),
                    verified.credential
                ))
                A.equal(base.generation, imported.generation)
                local mapped = lifecycle(fixture, base, {
                    kind = "import",
                    source_schema = "0.1.0",
                    model_mappings = "RemoteModel->Local",
                    permission_mappings = "RemoteStd->Std",
                    decision = "approved-local-mapping",
                    notes = "history approvals remain audit-only",
                    model_name = "Local",
                    model_snapshot_digest = "sha256:local-model",
                    permission_name = "LocalStd",
                    permission_snapshot_digest = "sha256:local-permission",
                    updated_at = "2026-08-29T00:00:04Z",
                    view_manifest_digest = "sha256:import-view",
                })
                local receipt = assert(fixture.store.publish(
                    writer,
                    mapped,
                    TARGET .. ".yaca-tmp-import"
                ))
                A.equal(mapped.facts[6].type, "import_mapping")
                A.equal(mapped.session.current_model.name, "Local")
                A.equal(mapped.session.current_permission.name, "LocalStd")
                A.equal(mapped.session.current_model.snapshot_digest, "sha256:local-model")
                A.equal(mapped.facts[5].type, "operation_intent")
                A.equal(receipt.auto_continue, false)
                A.deep_equal(receipt.unresolved_operation_ids, { "operation-1" })
                A.truthy(fixture.store.close_writer(writer))
            end,
        },
        {
            name = "catalog inspection stops after Header and never reads through a writer lock",
            --Verifies catalog inspection stops after Header and never reads through a writer lock.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify catalog inspection stops after Header and never reads through a writer lock.
            run = function()
                local fixture = harness.new(modules, { [TARGET] = harness.minimal("Task") })
                local writer = assert(fixture.store.open_writer(TARGET, fixture.metadata()))
                local reads_before = fixture.hooks.counts.fs_read or 0
                local locked, lock_error = fixture.store.inspect_catalog_header(TARGET)
                A.falsy(locked)
                A.equal(lock_error.code, "LockConflict")
                A.equal(fixture.hooks.counts.fs_read or 0, reads_before)
                A.truthy(fixture.store.close_writer(writer))

                local header, report = fixture.store.inspect_catalog_header(TARGET)
                A.truthy(header, report and report.code)
                A.equal(header.name, "Task")
                A.equal(header.created_at, "2026-08-29T00:00:00Z")
                A.equal(header.updated_at, "2026-08-29T00:00:01Z")
                A.equal(report.outcome, "header-validated-readonly")
                A.equal(report.body_opened, false)
                A.truthy(report.bytes_read > 0)
                A.equal(fixture.store.capabilities.bounded_header_inspection, true)

                local mismatched = harness.new(modules, {
                    [TARGET] = harness.minimal("Different"),
                })
                local value, mismatch_error = mismatched.store.inspect_catalog_header(TARGET)
                A.falsy(value)
                A.equal(mismatch_error.code, "ContextNameMismatch")
            end,
        },
        {
            name = "permanent delete reports all four known targets and preserves changed residue",
            --Verifies permanent delete reports all four known targets and preserves changed residue.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify permanent delete reports all four known targets and preserves changed residue.
            run = function()
                local temporary = TARGET .. ".yaca-tmp-deletecase"
                local fixture = harness.new(modules, { [TARGET] = harness.minimal("Task") })
                local _, auxiliary = fixture.document(harness.minimal("Task"))
                fixture.controls.external_replace(temporary, "temporary-control")
                fixture.controls.external_replace(PREVIOUS, auxiliary)
                local credential = {
                    physical_path = TARGET,
                    logical_path = "/C/work/Task.xml",
                    observed_stat = fixture.controls.identity(TARGET),
                    canonical_name = "Task",
                    created_at = "2026-08-29T00:00:00Z",
                    updated_at = "2026-08-29T00:00:01Z",
                }
                local writer = assert(fixture.store.open_delete_writer(
                    TARGET,
                    fixture.metadata(),
                    credential
                ))
                local receipt = assert(fixture.store.delete(writer, temporary))
                A.equal(receipt.outcome, "deleted")
                A.equal(receipt.permanent, true)
                A.equal(receipt.recoverable, false)
                A.equal(receipt.secure_erase, false)
                A.equal(receipt.provider_withdrawal, false)
                A.equal(#receipt.targets, 4)
                A.deep_equal({
                    receipt.targets[1].role,
                    receipt.targets[2].role,
                    receipt.targets[3].role,
                    receipt.targets[4].role,
                }, { "official", "temporary", "previous-valid", "writer-lock" })
                for _, target in ipairs(receipt.targets) do
                    A.equal(target.outcome, "deleted", target.role)
                    A.falsy(fixture.controls.exists(target.path), target.role)
                end
                A.truthy(fixture.store.close_writer(writer))

                local raced = harness.new(modules, { [TARGET] = harness.minimal("Task") })
                raced.controls.external_replace(temporary, "temporary-control")
                raced.controls.external_replace(PREVIOUS, "old-previous")
                local raced_writer = assert(raced.store.open_delete_writer(
                    TARGET,
                    raced.metadata()
                ))
                local replaced = false
                --Supplies fs stat identity behavior required by the 'permanent delete reports all four known targets and preserves changed residue' case.
                --@param ok boolean Success status returned by the fake operation.
                --@param _ any Unused callback argument supplied by the port.
                --@param subject any The subject supplied to the fake service for this scenario.
                --@return nil No value; assertions verify permanent delete reports all four known targets and preserves changed residue.
                raced.hooks.after.fs_stat_identity = function(ok, _, subject)
                    if ok and not replaced and type(subject) == "table"
                        and subject.path == PREVIOUS
                    then
                        replaced = true
                        raced.controls.external_replace(PREVIOUS, "foreign-previous")
                    end
                end
                local partial = assert(raced.store.delete(raced_writer, temporary))
                A.equal(partial.outcome, "partial")
                A.equal(partial.targets[3].outcome, "changed")
                A.equal(raced.controls.bytes(PREVIOUS), "foreign-previous")
                A.falsy(raced.controls.exists(TARGET))
                A.falsy(raced.controls.exists(temporary))
                A.falsy(raced.controls.exists(LOCK))
                A.truthy(raced.store.close_writer(raced_writer))
                for _, operation in ipairs(raced.controls.operations) do
                    A.falsy(operation:find("trash", 1, true))
                    A.falsy(operation:find("restore", 1, true))
                    A.falsy(operation:find("tombstone", 1, true))
                end

                local damaged = harness.new(modules, {
                    [TARGET] = harness.minimal("Task"),
                })
                damaged.controls.external_replace(TARGET, "<broken>")
                local corrupt = candidate_for(
                    damaged,
                    TARGET,
                    "/C/work/Task.xml",
                    "corrupt",
                    { canonical_name = nil, created_at = nil, updated_at = nil }
                )
                local damaged_index = index_service({ [TARGET] = corrupt })
                local deletion_target = damaged_index.verify_target(
                    assert(damaged_index.capture_target(corrupt)),
                    "delete"
                )
                A.equal(deletion_target.tag, "Verified")
                local damaged_writer = assert(damaged.store.open_delete_writer(
                    TARGET,
                    damaged.metadata(),
                    deletion_target.credential
                ))
                A.equal(damaged.store.delete(damaged_writer).outcome, "deleted")
                A.falsy(damaged.controls.exists(TARGET))
                A.truthy(damaged.store.close_writer(damaged_writer))
            end,
        },
        {
            name = "typed repair plans are read-only and restore a missing or damaged official in one publication",
            --Verifies typed repair plans are read-only and restore a missing or damaged official in one publication.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify typed repair plans are read-only and restore a missing or damaged official in one publication.
            run = function()
                for _, damaged in ipairs({ false, true }) do
                    local fixture = harness.new(modules)
                    local _, old_bytes = fixture.document(harness.minimal("Task"))
                    fixture.controls.external_replace(PREVIOUS, old_bytes)
                    if damaged then fixture.controls.external_replace(TARGET, "<broken>") end
                    local credential = { physical_path = TARGET, logical_path = "/C/work/Task.xml",
                        header_state = damaged and "corrupt" or "unavailable" }
                    if damaged then credential.observed_stat = fixture.controls.identity(TARGET)
                    else credential.recovery_stat = fixture.controls.identity(PREVIOUS) end
                    local plan, base = fixture.store.plan_repair(TARGET, credential)
                    A.truthy(plan, A.render(base))
                    A.equal(plan.action, "restore-previous")
                    A.falsy(fixture.controls.exists(LOCK))
                    A.equal(fixture.controls.bytes(PREVIOUS), old_bytes)
                    A.equal(fixture.controls.bytes(TARGET), damaged and "<broken>" or nil)
                    local repaired = lifecycle(fixture, base, { kind = "repair", error_id = "PreviousValidRestored",
                        summary = "restored validated previous with an audited publication",
                        updated_at = "2026-08-29T00:00:05Z", view_manifest_digest = "sha256:repaired-view" })
                    local receipt, err = fixture.store.apply_repair(plan, repaired, TARGET .. ".yaca-tmp-repair", fixture.metadata())
                    A.truthy(receipt, A.render(err))
                    A.equal(receipt.outcome, "restored-previous")
                    A.equal(receipt.generation, 2)
                    A.falsy(receipt.auto_replay)
                    A.falsy(fixture.controls.exists(PREVIOUS))
                    A.falsy(fixture.controls.exists(LOCK))
                    A.equal(fixture.controls.bytes(TARGET), assert(fixture.schema.encode(repaired)))
                    local repeated, repeated_error = fixture.store.apply_repair(plan, repaired,
                        TARGET .. ".yaca-tmp-repeat", fixture.metadata())
                    A.falsy(repeated)
                    A.equal(repeated_error.code, "InvalidRepairPlan")
                end
            end,
        },
        {
            name = "typed repair rejects stale sources destinations and live locks before changing files",
            --Verifies typed repair rejects stale sources destinations and live locks before changing files.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify typed repair rejects stale sources destinations and live locks before changing files.
            run = function()
                for _, changed in ipairs({ "previous", "official", "lock", "under-lease" }) do
                    local fixture = harness.new(modules)
                    local _, old_bytes = fixture.document(harness.minimal("Task"))
                    fixture.controls.external_replace(PREVIOUS, old_bytes)
                    local plan, base = assert(fixture.store.plan_repair(TARGET, { physical_path = TARGET,
                        logical_path = "/C/work/Task.xml", header_state = "unavailable",
                        recovery_stat = fixture.controls.identity(PREVIOUS) }))
                    local repaired = lifecycle(fixture, base, { kind = "repair", error_id = "PreviousValidRestored",
                        summary = "restore previous", updated_at = "2026-08-29T00:00:05Z",
                        view_manifest_digest = "sha256:repaired-view" })
                    if changed == "previous" then fixture.controls.external_replace(PREVIOUS, old_bytes)
                    elseif changed == "official" then fixture.controls.external_replace(TARGET, "replacement")
                    elseif changed == "lock" then fixture.controls.external_replace(LOCK, "old-looking lock")
                    else
                        --Supplies fs create new behavior required by the 'typed repair rejects stale sources destinations and live locks before changing files' case.
                        --@param ok boolean Success status returned by the fake operation.
                        --@param _ any Unused callback argument supplied by the port.
                        --@param target table|string Target selected for the exercised operation.
                        --@return nil No value; assertions verify typed repair rejects stale sources destinations and live locks before changing files.
                        fixture.hooks.after.fs_create_new = function(ok, _, target)
                            if ok and target == LOCK then fixture.controls.external_replace(PREVIOUS, old_bytes) end
                        end
                    end
                    local result, err = fixture.store.apply_repair(plan, repaired,
                        TARGET .. ".yaca-tmp-repair", fixture.metadata())
                    A.falsy(result)
                    A.equal(err.code, "TargetChanged")
                    A.equal(fixture.controls.bytes(TARGET), changed == "official" and "replacement" or nil)
                    A.equal(fixture.controls.bytes(PREVIOUS), old_bytes)
                    A.equal(fixture.controls.exists(LOCK), changed == "lock")
                    A.falsy(fixture.controls.exists(TARGET .. ".yaca-tmp-repair"))
                end
            end,
        },
        {
            name = "typed repair retains the recovery source on publish and cleanup failures",
            --Verifies typed repair retains the recovery source on publish and cleanup failures.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify typed repair retains the recovery source on publish and cleanup failures.
            run = function()
                for _, stage in ipairs({ "write", "publish", "flush", "cleanup", "release" }) do
                    local fixture = harness.new(modules)
                    local _, old_bytes = fixture.document(harness.minimal("Task"))
                    fixture.controls.external_replace(PREVIOUS, old_bytes)
                    local plan, base = assert(fixture.store.plan_repair(TARGET, { physical_path = TARGET,
                        logical_path = "/C/work/Task.xml", header_state = "unavailable",
                        recovery_stat = fixture.controls.identity(PREVIOUS) }))
                    local repaired = lifecycle(fixture, base, { kind = "repair", error_id = "PreviousValidRestored",
                        summary = "restore previous", updated_at = "2026-08-29T00:00:05Z",
                        view_manifest_digest = "sha256:repaired-view" })
                    if stage == "write" then
                        fixture.controls.faults.write = true
                    elseif stage == "publish" then
                        --Supplies fs rename no replace verified behavior required by the 'typed repair retains the recovery source on publish and cleanup failures' case.
                        --@param none No arguments; this closure uses its captured fixture state.
                        --@return nil No value; assertions verify typed repair retains the recovery source on publish and cleanup failures.
                        fixture.hooks.before.fs_rename_no_replace_verified = function() error("synthetic publication exception") end
                    elseif stage == "flush" then
                        --Supplies fs rename no replace verified behavior required by the 'typed repair retains the recovery source on publish and cleanup failures' case.
                        --@param ok boolean Success status returned by the fake operation.
                        --@return nil No value; assertions verify typed repair retains the recovery source on publish and cleanup failures.
                        fixture.hooks.after.fs_rename_no_replace_verified = function(ok)
                            if ok then fixture.controls.faults.flush_directory = true end
                        end
                    elseif stage == "cleanup" then
                        --Supplies fs delete verified behavior required by the 'typed repair retains the recovery source on publish and cleanup failures' case.
                        --@param target table|string Target selected for the exercised operation.
                        --@return nil No value; assertions verify typed repair retains the recovery source on publish and cleanup failures.
                        fixture.hooks.before.fs_delete_verified = function(target)
                            if target == PREVIOUS then error("synthetic cleanup exception") end
                        end
                    else
                        --Supplies fs delete verified behavior required by the 'typed repair retains the recovery source on publish and cleanup failures' case.
                        --@param target table|string Target selected for the exercised operation.
                        --@return nil No value; assertions verify typed repair retains the recovery source on publish and cleanup failures.
                        fixture.hooks.before.fs_delete_verified = function(target)
                            if target == LOCK then error("synthetic lease release exception") end
                        end
                    end
                    local receipt, err = fixture.store.apply_repair(plan, repaired, TARGET .. ".yaca-tmp-repair", fixture.metadata())
                    A.falsy(receipt)
                    if stage == "write" then
                        A.equal(err.code, "InjectedWrite")
                        A.falsy(fixture.controls.exists(TARGET))
                    else A.equal(err.code, "ContextRepairUnknown") end
                    if stage ~= "release" then A.equal(fixture.controls.bytes(PREVIOUS), old_bytes) end
                    if stage == "flush" or stage == "cleanup" or stage == "release" then
                        A.equal(fixture.controls.bytes(TARGET), assert(fixture.schema.encode(repaired)))
                    end
                end
            end,
        },
        {
            name = "typed repair cleans an obsolete previous but refuses conflicting histories and active locks",
            --Verifies typed repair cleans an obsolete previous but refuses conflicting histories and active locks.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify typed repair cleans an obsolete previous but refuses conflicting histories and active locks.
            run = function()
                local fixture = harness.new(modules, { [TARGET] = harness.minimal("Task") })
                local old_bytes = fixture.controls.bytes(TARGET)
                local credential = { physical_path = TARGET, logical_path = "/C/work/Task.xml",
                    observed_stat = fixture.controls.identity(TARGET), header_state = "valid" }
                local noop, base = assert(fixture.store.plan_repair(TARGET, credential))
                A.equal(noop.action, "no-repair-needed")
                A.equal(fixture.store.apply_repair(noop).outcome, "unchanged")
                A.falsy(fixture.controls.exists(LOCK))
                fixture.controls.external_replace(PREVIOUS, old_bytes)
                local plan = assert(fixture.store.plan_repair(TARGET, credential))
                A.equal(plan.action, "clean-previous")
                local repaired = lifecycle(fixture, base, { kind = "repair", error_id = "PreviousValidCleaned",
                    summary = "clean previous", updated_at = "2026-08-29T00:00:05Z",
                    view_manifest_digest = "sha256:repaired-view" })
                A.equal(assert(fixture.store.apply_repair(plan, repaired,
                    TARGET .. ".yaca-tmp-repair", fixture.metadata())).outcome, "cleaned-previous")
                A.falsy(fixture.controls.exists(PREVIOUS))
                credential.observed_stat = fixture.controls.identity(TARGET)
                fixture.controls.external_replace(PREVIOUS, "<invalid>")
                local unsafe, unsafe_error = fixture.store.plan_repair(TARGET, credential)
                A.falsy(unsafe)
                A.equal(unsafe_error.code, "NoSafeRepair")
                fixture.controls.external_replace(LOCK, "old-looking-lock")
                local blocked, blocked_error = fixture.store.plan_repair(TARGET, credential)
                A.falsy(blocked)
                A.equal(blocked_error.code, "LockConflict")
                A.equal(fixture.controls.bytes(PREVIOUS), "<invalid>")
                A.equal(fixture.controls.bytes(LOCK), "old-looking-lock")
            end,
        },
        {
            name = "repair uses only previous-valid evidence and never breaks a stale lock",
            --Verifies repair uses only previous-valid evidence and never breaks a stale lock.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify repair uses only previous-valid evidence and never breaks a stale lock.
            run = function()
                local fixture = harness.new(modules)
                local first = harness.minimal("Task")
                local _, old_bytes = fixture.document(first)
                fixture.controls.external_replace(PREVIOUS, old_bytes)
                local writer, restored, receipt = fixture.store.repair(
                    TARGET,
                    fixture.metadata()
                )
                A.truthy(writer)
                A.equal(receipt.outcome, "restored-previous")
                A.equal(receipt.requires_repair_generation, true)
                A.equal(receipt.auto_replay, false)
                A.equal(restored.generation, 1)
                local repaired = lifecycle(fixture, restored, {
                    kind = "repair",
                    error_id = "PreviousValidRestored",
                    summary = "restored the validated previous generation",
                    updated_at = "2026-08-29T00:00:05Z",
                    view_manifest_digest = "sha256:repair-view",
                })
                A.equal(repaired.facts[3].type, "warning")
                A.truthy(fixture.store.publish(
                    writer,
                    repaired,
                    TARGET .. ".yaca-tmp-repair"
                ))
                A.truthy(fixture.store.close_writer(writer))

                local stale = harness.new(modules, { [TARGET] = harness.minimal("Task") })
                stale.controls.external_replace(LOCK, table.concat({
                    "version=1",
                    "pid=1",
                    "startedAt=2001-01-01T00:00:00Z",
                    "",
                }, "\n"))
                local repaired_writer, repair_error = stale.store.repair(
                    TARGET,
                    stale.metadata()
                )
                A.falsy(repaired_writer)
                A.equal(repair_error.code, "LockConflict")
                A.truthy(stale.controls.exists(LOCK))

                local unresolved_fixture = harness.new(modules)
                local unresolved = fixture.schema.build(harness.unresolved("Task"))
                local resolved, resolve_error = unresolved_fixture.schema.lifecycle_document(
                    unresolved,
                    {
                        kind = "resolve_operation",
                        operation_id = "operation-1",
                        status = "unknown",
                        evidence = "user confirmed that outcome remains unknown",
                        updated_at = "2026-08-29T00:00:06Z",
                        view_manifest_digest = "sha256:resolution-view",
                    }
                )
                A.truthy(resolved, resolve_error and resolve_error.code)
                A.deep_equal(resolved.recovery.unresolved_operation_ids, {})
                A.deep_equal(resolved.recovery.unknown_operation_ids, { "operation-1" })
                A.equal(resolved.recovery.auto_continue, false)
            end,
        },
        {
            name = "active writer blocks external rename rebind delete import and repair",
            --Verifies active writer blocks external rename rebind delete import and repair.
            --@param none No arguments; this closure uses its captured fixture state.
            --@return nil No value; assertions verify active writer blocks external rename rebind delete import and repair.
            run = function()
                local fixture = harness.new(modules, { [TARGET] = harness.minimal("Task") })
                local writer = assert(fixture.store.open_writer(TARGET, fixture.metadata(10)))
                local other = fixture.new_store()
                local blocked, lock_error = other.open_writer(TARGET, fixture.metadata(20))
                A.falsy(blocked)
                A.equal(lock_error.code, "LockConflict")
                blocked, lock_error = other.open_delete_writer(TARGET, fixture.metadata(20))
                A.falsy(blocked)
                A.equal(lock_error.code, "LockConflict")
                blocked, lock_error = other.inspect_import(TARGET)
                A.falsy(blocked)
                A.equal(lock_error.code, "LockConflict")
                blocked, lock_error = other.repair(TARGET, fixture.metadata(20))
                A.falsy(blocked)
                A.equal(lock_error.code, "LockConflict")
                A.truthy(fixture.store.close_writer(writer))
                local admitted = assert(other.open_writer(TARGET, fixture.metadata(20)))
                A.truthy(other.close_writer(admitted))
            end,
        },
    },
}
