--[[
File: repl_input_surface_test.lua
Date: 2026-09-14
Author: WaterRun
Description: Verifies each interactive surface reports its own cancellation code.
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

local main = load_module("main")
local cli = load_module("cli")
local config = load_module("config")
local sha256 = load_table("test/support/sha256_reference.lua")
local fake_filesystem = load_table("test/support/fake_filesystem.lua")

local CONFIG_PATH = "/data/config.ini"

local function hash_port()
    local port = {}
    function port.sha256_start() return { parts = {}, finished = false, closed = false } end
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

local function options()
    return {
        schema_version = "0.1.0",
        release_ca_path = "/opt/yaca/cacert.pem",
        ini_limits = {
            maximum_bytes = 65536,
            maximum_lines = 512,
            maximum_line_bytes = 4096,
            maximum_value_bytes = 16384,
        },
        hard_limits = {
            queue_items = 64,
            turn_model_requests = 64,
            turn_tool_calls = 256,
            connect_timeout_ms = 120000,
            response_bytes = 16777216,
            exec_timeout_ms = 3600000,
            exec_output_kb = 8192,
            auto_name_turns = 100000,
            recent_contexts = 10000,
            model_context_tokens = 2000000,
            model_output_tokens = 131072,
            request_timeout_ms = 3600000,
            retry_count = 10,
            retry_base_delay_ms = 60000,
        },
        runtime_defaults = { retry_count = 2 },
        maximum_text_bytes = 16384,
        maximum_name_bytes = 128,
        maximum_adapter_options_bytes = 4096,
        maximum_hash_chunk_bytes = 11,
        minimum_scannable_secret_bytes = 8,
    }
end

local function source()
    return table.concat({
        "[General]",
        "SchemaVersion = 0.1.0",
        "LogLevel = info",
        "",
        "[Agent]",
        "QueueMaxItems = 9",
        "",
        "[Permission.Std]",
        "Read = allow",
        "Write = confirm",
        "Delete = confirm",
        "Shell = confirm",
        "OutsideWorkspace = confirm",
        "",
        "[Model.Primary]",
        "Enabled = true",
        "Protocol = openai-chat",
        'Endpoint = "https://api.example/v1/chat"',
        'RemoteModel = "remote-main"',
        'Key = "example-secret-value"',
        "",
    }, "\n")
end

---Terminal double emitting one scripted event batch per poll.
-- The contract mirrors the production port: start/poll/cancel/close, with
-- `user_action` and `io_terminal` events.
local function scripted_terminal(batches, cursor)
    local terminal = { started = false, closed = false, cancelled = false }
    function terminal.start(self, now)
        A.equal(math.type(now), "integer")
        A.falsy(self.started)
        self.started = true
        return true
    end
    function terminal.poll(self, now, budget)
        A.truthy(self.started)
        A.equal(math.type(now), "integer")
        A.truthy(budget > 0)
        cursor.index = cursor.index + 1
        return batches[cursor.index] or { { kind = "io_terminal" } }
    end
    function terminal.cancel(self, now)
        A.equal(math.type(now), "integer")
        self.cancelled = true
        return true
    end
    function terminal.join(self, now)
        A.equal(math.type(now), "integer")
        self.joined = true
        return {}
    end
    function terminal.close(self)
        self.closed = true
        return true
    end
    return terminal
end

local function harness(batches)
    local filesystem, controls = fake_filesystem.new({ [CONFIG_PATH] = source() })
    local service = assert(config.new({
        sha256 = hash_port(),
        filesystem = filesystem,
    }, options()))
    local terminals, ticks, written = {}, 0, {}
    local cursor = { index = 0 }
    local composed = {
        config = service,
        layout = { config_path = CONFIG_PATH },
        backend = {
            new_terminal = function(mode)
                local terminal = scripted_terminal(batches, cursor)
                terminal.mode = mode
                terminals[#terminals + 1] = terminal
                return terminal
            end,
            clock_port = {
                monotonic_now = function()
                    ticks = ticks + 1
                    return ticks
                end,
                sleep_ms = function() return true end,
            },
            system = { secure_random = function(count) return string.rep("\0", count) end },
        },
    }
    local runtime = {
        cli = assert(cli.new({ platform = "linux" })),
        stdout = function(bytes)
            written[#written + 1] = bytes
            return true
        end,
    }
    return composed, runtime, terminals, written, controls
end

local function context_harness(commands, settings)
    settings = settings or {}
    local batches = {}
    for _, command in ipairs(commands) do
        batches[#batches + 1] = type(command) == "table" and { command } or {
            { kind = "user_action", action = "text", text = command },
            { kind = "user_action", action = "submit-or-queue" },
        }
    end
    local composed, runtime, terminals, written, controls = harness(batches)
    local path = assert(load_module("path").new(hash_port(), {
        maximum_path_bytes = 2048, maximum_segments = 128,
        maximum_segment_bytes = 255, maximum_hash_chunk_bytes = 64,
    }))
    local rows, calls = {}, { scans = 0, closes = 0, verifies = 0, mutations = {} }
    for i = 1, settings.count or 2 do
        local name = string.format("Task%03d", i)
        local logical = "/" .. name .. ".xml"
        rows[i] = {
            logical_path = logical, physical_path = "/data/CONTEXT" .. logical,
            display_path = "CONTEXT" .. logical, display_name = name, canonical_name = name,
            created_at = "2026-09-14T00:00:00Z", updated_at = "2026-09-14T00:00:01Z",
            observed_stat = { object = logical, size = 100 }, header_state = "valid",
        }
    end
    if settings.corrupt then rows[1].header_state = "corrupt" end
    if settings.previous_only then
        rows[1].header_state = "unavailable"
        rows[1].observed_stat = nil
        rows[1].canonical_name, rows[1].created_at, rows[1].updated_at = nil, nil, nil
        rows[1].recovery_stat = { kind = "file", object = "previous-file", size = 100 }
    end
    if settings.busy then
        rows[1].header_state = "unavailable"
        rows[1].canonical_name, rows[1].created_at, rows[1].updated_at = nil, nil, nil
    end
    local scanner = {
        begin = function()
            calls.scans = calls.scans + 1
            if settings.scan_failure then return false, { code = "ScanDenied", message = "scan denied" } end
            return true, { next = 0 }
        end,
        next_ring = function(handle)
            handle.next = handle.next + 1
            if handle.next == 1 then return true, { scope = "/", complete = true, candidates = rows } end
            if settings.partial and handle.next == 2 then
                return false, { code = "ScanInterrupted" }
            end
            return true, nil
        end,
        close = function() calls.closes = calls.closes + 1 return true end,
        status = function() return { complete = not settings.partial, partial_reason = "ScanInterrupted" } end,
    }
    local verifier = { observe = function(target)
            calls.verifies = calls.verifies + 1
            for _, row in ipairs(rows) do
                if row.logical_path == target.logical_path then
                    local copy = {}; for key, value in pairs(row) do copy[key] = value end
                    if settings.changed or (settings.changed_after_confirm and calls.verifies > 1)
                        or (settings.changed_after_verify and calls.verifies > settings.changed_after_verify)
                    then
                        if settings.previous_only then
                            copy.recovery_stat = { kind = "file", object = "replacement", size = 100 }
                        else copy.observed_stat = { object = "replacement", size = 100 } end
                    end
                    return true, copy
                end
            end
            return false, { code = "NotFound" }
        end }
    local catalog = assert(load_module("index").new({ path = path, scanner = scanner,
        verifier = verifier }, { maximum_scan_candidates = 1024, maximum_search_rings = 8,
        maximum_collision_candidates = 4, maximum_reason_bytes = 64 }))
    composed.contexts = { catalog = catalog, catalog_scanner = scanner, path = path,
        catalog_verifier = verifier, context_root = "/data/CONTEXT", store = {
            inspect_import = function(target, credential)
                calls.import_reads = (calls.import_reads or 0) + 1
                A.equal(target, credential.physical_path)
                if settings.body_error then return nil, { code = "InvalidContext", message = "invalid body" } end
                return { header = { auto_rename_disabled = false }, session = {
                    current_model = { name = settings.reference_model or "Foreign" },
                    current_permission = { name = "ForeignStd" },
                    double_check_override = false, double_check_goal_override = { mode = "inherit" },
                    context_prompt = "preserved imported context",
                } }, { outcome = "validated-readonly" }
            end,
        } }
    composed.config_generation = { context = { recent_list_limit = 1 } }
    if settings.manage then
        composed.publication = { manage_context = function(specification)
            calls.mutations[#calls.mutations + 1] = specification
            A.equal(specification.context_path, specification.expected_credential.physical_path)
            A.equal(specification.logical_path, specification.expected_credential.logical_path)
            if settings.mutation_error then return nil, settings.mutation_error end
            if specification.action == "import" then
                if specification.generation ~= calls.import_generation then
                    return nil, { code = "ConfigGenerationChanged", message = "configuration changed" }
                end
                return { outcome = "success", context_hash = "0123456789ABCDEF",
                    model = specification.generation.current_model, permission = specification.generation.current_permission }
            end
            if specification.action == "delete" then
                return { outcome = settings.partial_delete and "partial" or "deleted",
                    targets = { { role = "official", outcome = "deleted", path = specification.context_path } } }
            end
            return { outcome = "success", context_hash = "0123456789ABCDEF",
                logical_path = "/Managed.xml", auto_rename_disabled = specification.action == "rename" }
        end, plan_rebind = function(specification)
            calls.plans = (calls.plans or 0) + 1
            A.equal(specification.context_path, specification.expected_credential.physical_path)
            if settings.plan_error then return nil, settings.plan_error end
            local plan = { target_root = specification.target_root,
                target_logical_path = "/new-work/Task001.xml", target_hash = "FEDCBA9876543210" }
            calls.proposal = plan
            return plan
        end, plan_repair = function(specification)
            calls.repair_plans = (calls.repair_plans or 0) + 1
            if settings.plan_error then return nil, settings.plan_error end
            return { action = settings.repair_action or "restore-previous", source_path = specification.context_path .. ".yaca-prev",
                previous_path = specification.context_path .. ".yaca-prev" }
        end, plan_import = function(specification)
            calls.import_plans = (calls.import_plans or 0) + 1
            calls.import_generation = specification.generation
            if settings.plan_error then return nil, settings.plan_error end
            A.equal(specification.generation.context_prompt, "preserved imported context")
            A.equal(specification.generation.effective_double_check, false)
            return { workspace = "/", previous_model = "Foreign", previous_permission = "ForeignStd",
                model = specification.generation.current_model, permission = specification.generation.current_permission,
                unresolved_operations = 1, unresolved_tools = 1, unknown_operations = 0 }
        end }
    end
    if settings.controllers then
        composed.application = {
            dispatch = function(action)
                calls.exports = (calls.exports or 0) + 1
                calls.export_selector = action.selector
                A.equal(action.id, "export-context")
                if not action.selector then return nil, { code = "NoActiveContext", message = "provide a selector" } end
                if settings.export_error then return nil, settings.export_error end
                return { kind = "context-export", format = "markdown", markdown = "# yaca Context export v1\n\nfixture body\n" }
            end,
            preview_continue = function(selector)
                calls.continue_selectors = calls.continue_selectors or {}
                calls.continue_selectors[#calls.continue_selectors + 1] = selector
                if settings.continue_error then return nil, settings.continue_error end
                calls.continue_preview = { kind = "continue-preview", context_hash = "0123456789ABCDEF",
                    logical_path = "/work/Task001.xml", recorded_workspace = "/work", origin_workspace = "/",
                    requires_workspace_confirmation = settings.cross_workspace == true }
                return calls.continue_preview
            end,
            continue_preview = function() error("manager must close its terminal before opening a writer") end,
        }
    end
    if settings.change_import_config then
        local write = runtime.stdout
        runtime.stdout = function(bytes)
            if bytes:find("Type IMPORT", 1, true) then
                controls.external_write(CONFIG_PATH, source():gsub("LogLevel = info", "LogLevel = debug"))
            end
            return write(bytes)
        end
    end
    if settings.stdout_failure then
        runtime.stdout = function(bytes)
            written[#written + 1] = bytes
            return not bytes:find("context>", 1, true)
        end
    end
    local result, err
    if settings.model_manager then result, err = main.run_model_manager(composed, runtime)
    else result, err = main.run_context_repl(composed, runtime, { view = settings.view or "recent" }) end
    for _, terminal in ipairs(terminals) do A.truthy(terminal.closed, "terminal must be restored") end
    A.equal(calls.scans, calls.closes + (settings.scan_failure and 1 or 0))
    return result, err, table.concat(written), calls, controls
end

local context_cases = {
    {
        name = "Model rename lists referenced Contexts and saves without rewriting their history",
        run = function()
            local result, err, output, calls, controls = context_harness({
                "rename model-edit-1:1 Renamed", "preview", "save model-edit-2",
            }, { model_manager = true, reference_model = "Primary" })
            A.truthy(result, A.render(err))
            A.equal(result.state, "published")
            A.contains(output, "Affected Contexts: 2")
            A.contains(output, "/Task001.xml references Primary")
            A.contains(output, "explicit mapping on continuation")
            A.contains(controls.bytes(CONFIG_PATH), "[Model.Renamed]")
            A.equal(calls.import_reads, 6)
            A.equal(#calls.mutations, 0)
        end,
    },
    {
        name = "Model reference preview rejects busy corrupt partial and invalid-body Contexts",
        run = function()
            for _, key in ipairs({ "busy", "corrupt", "partial", "body_error" }) do
                local settings = { model_manager = true, reference_model = "Primary", [key] = true }
                local result, err, output, calls, controls = context_harness({
                    "rename model-edit-1:1 Renamed", "preview", "save model-edit-2", "quit",
                }, settings)
                A.truthy(result, A.render(err))
                A.contains(output, "ModelPreviewRequired")
                A.equal(controls.bytes(CONFIG_PATH), source())
                A.falsy(table.concat(controls.operations, "|"):find("create:", 1, true))
                A.equal(#calls.mutations, 0)
            end
        end,
    },
    {
        name = "Model reference identity is checked again after confirmation before creating configuration temporary",
        run = function()
            local result, err, output, calls, controls = context_harness({
                "rename model-edit-1:1 Renamed", "preview", "save model-edit-2", "quit",
            }, { model_manager = true, reference_model = "Primary", changed_after_verify = 6 })
            A.truthy(result, A.render(err))
            A.contains(output, "Affected Contexts: 2")
            A.contains(output, "ModelImpactStale")
            A.equal(controls.bytes(CONFIG_PATH), source())
            A.falsy(table.concat(controls.operations, "|"):find("create:", 1, true))
            A.equal(#calls.mutations, 0)
        end,
    },
    {
        name = "Context manager exports Markdown through the read-only application owner",
        run = function()
            local result, err, output, calls = context_harness({ "export Task001", "export", "quit" }, { controllers = true })
            A.truthy(result, A.render(err))
            A.contains(output, "# yaca Context export v1\n\nfixture body\n")
            A.contains(output, "NoActiveContext")
            A.equal(calls.exports, 2)
            A.equal(#calls.mutations, 0)
            result, err, output = context_harness({ "export Task001", "quit" }, {
                controllers = true, export_error = { code = "RegisteredSecret", message = "export rejected" },
            })
            A.truthy(result, A.render(err))
            A.contains(output, "RegisteredSecret")
            A.falsy(output:find("fixture body", 1, true))
        end,
    },
    {
        name = "Context manager restores input before transferring an exact continuation preview",
        run = function()
            for _, cross in ipairs({ false, true }) do
                local commands = { "select Task001" }
                if cross then commands[2] = "CONTINUE 0123456789ABCDEF" end
                local result, err, output, calls = context_harness(commands, { controllers = true, cross_workspace = cross })
                A.truthy(result, A.render(err))
                A.equal(result.state, "continue-selected")
                A.equal(result.preview, calls.continue_preview)
                A.equal(result.confirmation, cross and "CONTINUE 0123456789ABCDEF" or nil)
                A.equal(#calls.mutations, 0)
                A.equal(#calls.continue_selectors, 1)
                if cross then A.contains(output, "Context workspace: /work") end
            end
        end,
    },
    {
        name = "Context manager cancels workspace choices without leaving management or opening a writer",
        run = function()
            local result, err, output, calls = context_harness({ "select Task001", "no", "list", "quit" }, {
                controllers = true, cross_workspace = true,
            })
            A.truthy(result, A.render(err))
            A.falsy(result.preview)
            A.contains(output, "Context continuation cancelled")
            A.equal(#calls.mutations, 0)
            result, err, output = context_harness({ "select Task001", "quit" }, {
                controllers = true, continue_error = { code = "LockConflict", message = "busy" },
            })
            A.truthy(result, A.render(err))
            A.contains(output, "LockConflict")
            result, err = context_harness({ "select Task001", { kind = "user_action", action = "eof" } }, {
                controllers = true, cross_workspace = true,
            })
            A.truthy(result, A.render(err))
            A.equal(result.outcome, "cancelled")
        end,
    },

    {
        name = "Context repair confirms a previous-only target and refuses changed confirmations",
        run = function()
            local path = assert(load_module("path").new(hash_port(), {
                maximum_path_bytes = 2048, maximum_segments = 128,
                maximum_segment_bytes = 255, maximum_hash_chunk_bytes = 64,
            }))
            local hash = assert(path.context_hash("/Task001.xml"))
            local commands = { "repair " .. hash, "REPAIR " .. hash, "quit" }
            local result, err, output, calls = context_harness(commands, { manage = true, previous_only = true })
            A.truthy(result, A.render(err))
            A.contains(output, "Action: restore-previous")
            A.contains(output, "Task001.xml.yaca-prev")
            A.equal(#calls.mutations, 1)
            A.equal(calls.mutations[1].action, "repair")
            A.equal(calls.mutations[1].expected_credential.recovery_stat.object, "previous-file")
            A.falsy(calls.mutations[1].expected_credential.observed_stat)
            result, err, output, calls = context_harness(commands,
                { manage = true, previous_only = true, changed_after_confirm = true })
            A.truthy(result, A.render(err))
            A.contains(output, "ContextTargetChanged")
            A.equal(#calls.mutations, 0)
        end,
    },
    {
        name = "Context repair cancellation no-op and unsafe repair never start an unconfirmed mutation",
        run = function()
            local result, err, output, calls = context_harness({ "repair Task001", "no", "quit" },
                { manage = true, corrupt = true })
            A.truthy(result, A.render(err))
            A.contains(output, "Context repair cancelled")
            A.equal(#calls.mutations, 0)
            result, err, output, calls = context_harness({ "repair Task001", "quit" },
                { manage = true, repair_action = "no-repair-needed" })
            A.truthy(result, A.render(err))
            A.contains(output, "No previous-file repair is needed")
            A.falsy(output:find("Type REPAIR", 1, true))
            A.equal(#calls.mutations, 1)
            result, err, output, calls = context_harness({ "repair Task001", "quit" },
                { manage = true, plan_error = { code = "NoSafeRepair" } })
            A.truthy(result, A.render(err))
            A.contains(output, "NoSafeRepair")
            A.equal(#calls.mutations, 0)
        end,
    },
    {
        name = "Context import captures an exact in-place file and confirms effective local mappings",
        run = function()
            local path = assert(load_module("path").new(hash_port(), {
                maximum_path_bytes = 2048, maximum_segments = 128,
                maximum_segment_bytes = 255, maximum_hash_chunk_bytes = 64,
            }))
            local hash = assert(path.context_hash("/Task001.xml"))
            local commands = { "import /data/CONTEXT/Task001.xml", "Primary", "Std", "IMPORT " .. hash, "quit" }
            local result, err, output, calls = context_harness(commands, { manage = true })
            A.truthy(result, A.render(err))
            A.contains(output, "VALIDATED READ-ONLY")
            A.contains(output, "Model: Foreign -> Primary")
            A.contains(output, "Permission: ForeignStd -> Std")
            A.contains(output, "Unresolved operations/tools: 1/1")
            A.contains(output, "Context mapped:")
            A.equal(calls.verifies, 4)
            A.equal(#calls.mutations, 1)
            A.equal(calls.mutations[1].action, "import")
            A.equal(calls.mutations[1].generation.current_model, "Primary")
            result, err, output, calls = context_harness(commands, { manage = true, changed_after_verify = 3 })
            A.truthy(result, A.render(err))
            A.contains(output, "ContextTargetChanged")
            A.equal(#calls.mutations, 0)
            result, err, output, calls = context_harness(commands, { manage = true, change_import_config = true })
            A.truthy(result, A.render(err))
            A.contains(output, "ConfigGenerationChanged")
            A.falsy(output:find("Context mapped:", 1, true))
        end,
    },
    {
        name = "Context import rejects outside paths busy files invalid mappings and cancelled consent",
        run = function()
            for _, scenario in ipairs({
                { commands = { "import /elsewhere/Task001.xml", "quit" }, error = "InvalidImportPath", reads = 0 },
                { commands = { "import /data/CONTEXT/Task001.xml", "quit" }, busy = true,
                    error = "ContextTargetUnavailable", reads = 0 },
                { commands = { "import /data/CONTEXT/Task001.xml", "Missing", "quit" },
                    error = "ModelUnavailable", reads = 1 },
                { commands = { "import /data/CONTEXT/Task001.xml", "Primary", "Std", "no", "quit" },
                    error = "Context import cancelled", reads = 1 },
            }) do
                local result, err, output, calls = context_harness(scenario.commands,
                    { manage = true, busy = scenario.busy })
                A.truthy(result, A.render(err))
                A.contains(output, scenario.error)
                A.equal(calls.import_reads or 0, scenario.reads)
                A.equal(#calls.mutations, 0)
            end
        end,
    },
    {
        name = "Context rebind confirms the inspected destination and reverifies the original selection",
        run = function()
            local path = assert(load_module("path").new(hash_port(), {
                maximum_path_bytes = 2048, maximum_segments = 128,
                maximum_segment_bytes = 255, maximum_hash_chunk_bytes = 64,
            }))
            local hash = assert(path.context_hash("/Task001.xml"))
            local commands = { "rebind Task001 /new-work", "REBIND " .. hash, "quit" }
            local result, err, output, calls = context_harness(commands, { manage = true })
            A.truthy(result, A.render(err))
            A.contains(output, "New workspace: /new-work")
            A.contains(output, "FEDCBA9876543210 /new-work/Task001.xml")
            A.equal(calls.verifies, 2)
            A.equal(#calls.mutations, 1)
            A.equal(calls.mutations[1].action, "rebind")
            A.equal(calls.mutations[1].rebind_plan, calls.proposal)
            result, err, output, calls = context_harness(commands,
                { manage = true, changed_after_confirm = true })
            A.truthy(result, A.render(err))
            A.contains(output, "ContextTargetChanged")
            A.equal(#calls.mutations, 0)
        end,
    },
    {
        name = "Context rebind cancellation and planning failures make no mutations",
        run = function()
            local result, err, output, calls = context_harness({
                "rebind Task001 /new-work", "no", "quit",
            }, { manage = true })
            A.truthy(result, A.render(err))
            A.contains(output, "Context rebind cancelled")
            A.equal(calls.verifies, 1)
            A.equal(#calls.mutations, 0)
            result, err, output, calls = context_harness({ "rebind Task001 /missing", "quit" },
                { manage = true, plan_error = { code = "InvalidWorkspace" } })
            A.truthy(result, A.render(err))
            A.contains(output, "InvalidWorkspace")
            A.equal(#calls.mutations, 0)
            A.falsy(output:find("Type REBIND", 1, true))
        end,
    },
    {
        name = "Context read-only loop lists searches verifies refreshes and closes without body access",
        run = function()
            local result, err, output, calls = context_harness({
                "list full", "search Task002", "inspect Task001", "refresh", "help", "quit",
            })
            A.truthy(result, A.render(err)); A.equal(result.outcome, "success")
            A.equal(result.online_requests, 0); A.equal(result.total, 2)
            A.contains(output, "CONTEXT CATALOG view=recent")
            A.contains(output, "CONTEXT CATALOG view=full")
            A.contains(output, "CONTEXT SEARCH Task002")
            A.contains(output, "verified: reverified for open")
            A.contains(output, "Catalog rescanned; 2 Context(s)")
            A.falsy(output:find("ERROR", 1, true)); A.equal(calls.verifies, 1); A.equal(calls.scans, 3)
        end,
    },
    {
        name = "Context inspection refuses replaced and busy targets without selecting replacements",
        run = function()
            local result, err, output, calls = context_harness({ "inspect Task001", "quit" }, { changed = true })
            A.truthy(result, A.render(err)); A.contains(output, "ContextTargetChanged")
            A.falsy(output:find("verified: reverified", 1, true)); A.equal(calls.scans, 2); A.equal(calls.verifies, 1)
            result, err, output, calls = context_harness({ "inspect Task001", "quit" }, { busy = true })
            A.truthy(result, A.render(err)); A.contains(output, "UNAVAILABLE-METADATA-ONLY")
            A.equal(calls.verifies, 0); A.falsy(output:find("verified: reverified", 1, true))
        end,
    },
    {
        name = "Context loop rejects mutations and malformed commands then accepts subsequent input",
        run = function()
            local result, err, output = context_harness({ "rename Task001 NewName", "nonsense", "list", "quit" })
            A.truthy(result, A.render(err)); A.contains(output, "ContextActionUnavailable")
            A.contains(output, "context-rename"); A.contains(output, "CONTEXT CATALOG")
        end,
    },
    {
        name = "Context mutations use exact credentials and explicit permanent delete consent",
        run = function()
            local result, err, output, calls = context_harness({
                "rename Task001 Managed", "set-auto-rename-disabled Task001 false",
                "delete Task001", "not-confirmed", "delete Task001 --yes", "quit",
            }, { manage = true })
            A.truthy(result, A.render(err))
            A.equal(#calls.mutations, 3)
            A.equal(calls.mutations[1].action, "rename")
            A.equal(calls.mutations[1].new_name, "Managed")
            A.equal(calls.mutations[2].action, "set_auto_rename_disabled")
            A.equal(calls.mutations[2].value, false)
            A.equal(calls.mutations[3].action, "delete")
            A.contains(output, "Context deletion cancelled")
            A.contains(output, "Context deletion: deleted")
            A.equal(calls.verifies, 5)
        end,
    },
    {
        name = "Context delete confirms an exact hash and reverifies before mutation",
        run = function()
            local path = assert(load_module("path").new(hash_port(), {
                maximum_path_bytes = 2048, maximum_segments = 128,
                maximum_segment_bytes = 255, maximum_hash_chunk_bytes = 64,
            }))
            local confirm = "DELETE " .. assert(path.context_hash("/Task001.xml"))
            local result, err, output, calls = context_harness({ "delete Task001", confirm, "quit" },
                { manage = true })
            A.truthy(result, A.render(err))
            A.equal(#calls.mutations, 1)
            A.equal(calls.verifies, 2)
            A.contains(output, "PERMANENT DELETE")
            result, err, output, calls = context_harness({ "delete Task001", confirm, "quit" },
                { manage = true, changed_after_confirm = true })
            A.truthy(result, A.render(err))
            A.equal(#calls.mutations, 0)
            A.contains(output, "ContextTargetChanged")
        end,
    },
    {
        name = "Context delete cancellation and uncertain mutation restore and stop the manager",
        run = function()
            local result, err, output, calls = context_harness({ "delete Task001",
                { kind = "user_action", action = "cancel" } }, { manage = true })
            A.truthy(result, A.render(err))
            A.equal(result.outcome, "cancelled")
            A.equal(#calls.mutations, 0)
            for _, settings in ipairs({
                { manage = true, mutation_error = { code = "ContextMutationUnknown" } },
                { manage = true, partial_delete = true },
            }) do
                result, err, output, calls = context_harness({ "delete Task001 --yes",
                    "rename Task002 NotAllowed", "quit" }, settings)
                A.falsy(result)
                A.equal(err.code, "ContextMutationUnknown")
                A.equal(#calls.mutations, 1)
            end
        end,
    },
    {
        name = "Context deletion admits corrupt headers but rejects busy targets and names containing secrets",
        run = function()
            local result, err, output, calls = context_harness({ "delete Task001 --yes", "quit" },
                { manage = true, corrupt = true })
            A.truthy(result, A.render(err))
            A.equal(#calls.mutations, 1)
            A.equal(calls.mutations[1].expected_credential.header_state, "corrupt")
            result, err, output, calls = context_harness({ "delete Task001 --yes", "quit" },
                { manage = true, busy = true })
            A.truthy(result, A.render(err))
            A.equal(#calls.mutations, 0)
            result, err, output, calls = context_harness({ "rename Task001 example-secret-value", "quit" },
                { manage = true })
            A.truthy(result, A.render(err))
            A.equal(#calls.mutations, 0)
            A.contains(output, "RegisteredSecret")
        end,
    },
    {
        name = "Context full initial view bounds rows and reports true search totals",
        run = function()
            local result, err, output = context_harness({ "search Task", "quit" }, { count = 300, view = "full" })
            A.truthy(result, A.render(err)); A.contains(output, "CONTEXT CATALOG view=full")
            A.contains(output, "Total: 300"); A.contains(output, "Results were truncated")
            A.truthy(#output < 100000)
            result, err, output = context_harness({ "search Task", "quit" }, { count = 100, view = "full" })
            A.truthy(result, A.render(err)); A.contains(output, "Total: 100")
            A.falsy(output:find("truncated", 1, true), "an exact page is not truncated")
        end,
    },
    {
        name = "Context partial scans remain explicit and refreshable and scan failures propagate",
        run = function()
            local result, err, output = context_harness({ "refresh", "list", "quit" }, { partial = true })
            A.truthy(result, A.render(err)); A.contains(output, "scan incomplete")
            result, err = context_harness({}, { scan_failure = true })
            A.falsy(result); A.equal(err.code, "ScanDenied")
        end,
    },
    {
        name = "Context cancellation EOF and broken stdout always close the terminal",
        run = function()
            for _, event in ipairs({ { kind = "user_action", action = "cancel" },
                { kind = "user_action", action = "eof" }, { kind = "io_terminal" } }) do
                local result, err = context_harness({ event })
                A.truthy(result, A.render(err)); A.equal(result.outcome, "cancelled")
            end
            local result, err = context_harness({ "quit" }, { stdout_failure = true })
            A.falsy(result); A.equal(err.code, "BrokenStdout")
        end,
    },
}

local suite = {
    name = "integration/repl-input-surface",
    cases = {
        {
            name = "configuration editor reports its own cancellation code and restores the terminal",
            run = function()
                local composed, runtime, terminals = harness({
                    { { kind = "user_action", action = "cancel" } },
                })
                local result, editor_error = main.run_config_repl(composed, runtime)
                A.truthy(result, A.render(editor_error))
                A.equal(result.action, "config-repl")
                A.equal(result.outcome, "cancelled")
                A.equal(result.state, "cancelled")
                A.truthy(#terminals > 0)
                for _, terminal in ipairs(terminals) do A.truthy(terminal.closed) end
            end,
        },
    },
}

for _, case in ipairs(context_cases) do suite.cases[#suite.cases + 1] = case end
return suite
