--[[
File: main.lua
Date: 2026-08-29
Author: WaterRun
Description: Routes the offline bootstrap lifecycle from the unique composition root.
]]

local MODULE_NAME = ...
local session = require("session")

local M = {}
local default_runtime_dispatch

local BOOTSTRAP_ACTIONS = {
    ["config-repl"] = true,
    ["model-repl"] = true,
    ["context-repl"] = true,
}

local function failure(code, message, next_action)
    local result = { code = code, message = message }
    if next_action ~= nil then result.next_action = next_action end
    return result
end

local function readonly(values, label)
    return setmetatable({}, {
        __index = values,
        __newindex = function(_, key)
            error((label or "readonly value") .. " cannot be modified: " .. tostring(key), 2)
        end,
        __pairs = function()
            return next, values, nil
        end,
        __len = function()
            return #values
        end,
        __metatable = "locked",
    })
end

local function freeze(value, visiting, label)
    if type(value) ~= "table" then return value end
    visiting = visiting or {}
    if visiting[value] then return nil end
    visiting[value] = true
    local copy = {}
    for key, item in pairs(value) do
        local frozen = freeze(item, visiting, label)
        if frozen == nil and type(item) == "table" then
            visiting[value] = nil
            return nil
        end
        copy[key] = frozen
    end
    visiting[value] = nil
    return readonly(copy, label)
end

local function valid_integer(value, minimum)
    return math.type(value) == "integer" and value >= minimum
end

local function dense_string_array(values)
    if type(values) ~= "table" then return false end
    local count = 0
    for key in pairs(values) do
        if math.type(key) ~= "integer" or key < 1 then return false end
        count = count + 1
    end
    for index = 1, count do
        local value = values[index]
        if type(value) ~= "string" or value == "" or value:find("\0", 1, true) then
            return false
        end
    end
    return true
end

local function copy_plain(value, visiting)
    local value_type = type(value)
    if value_type == "nil" or value_type == "string" or value_type == "boolean" then
        return value, true
    end
    if value_type == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return nil, false end
        return value, true
    end
    if value_type ~= "table" then return nil, false end
    visiting = visiting or {}
    if visiting[value] then return nil, false end
    visiting[value] = true
    local copy = {}
    for key, item in pairs(value) do
        if type(key) ~= "string" and math.type(key) ~= "integer" then
            visiting[value] = nil
            return nil, false
        end
        local copied, copied_ok = copy_plain(item, visiting)
        if not copied_ok then
            visiting[value] = nil
            return nil, false
        end
        copy[key] = copied
    end
    visiting[value] = nil
    return copy, true
end

local function valid_absolute_path(value)
    if type(value) ~= "string" or value == "" or value:find("\0", 1, true) then return false end
    local normalized = value:gsub("\\", "/")
    return normalized:sub(1, 1) == "/"
        or normalized:match("^[A-Za-z]:/") ~= nil
        or normalized:match("^//[^/]+/[^/]+") ~= nil
end

local RUNTIME_TARGETS = {
    ["win32-x86"] = "windows",
    ["win64-x86_64"] = "windows",
    ["linux-x86_64"] = "linux",
}

local function normalize_executable_path(value, style)
    if type(value) ~= "string" or value == "" or value:find("\0", 1, true) then
        return nil
    end
    if style == "linux" then
        if value:sub(1, 1) ~= "/" or value:find("\\", 1, true) then return nil end
        if value:find("//", 1, true)
            or value:find("/./", 1, true)
            or value:find("/../", 1, true)
            or value:sub(-2) == "/."
            or value:sub(-3) == "/.."
            or value:sub(-1) == "/"
        then
            return nil
        end
        return value
    end

    local normalized = value:gsub("/", "\\")
    local drive = normalized:match("^[A-Za-z]:\\") ~= nil
    local unc = normalized:match("^\\\\[^\\]+\\[^\\]+\\") ~= nil
    if not drive and not unc then return nil end
    if normalized:find("\\%.\\")
        or normalized:find("\\%.%.\\")
        or normalized:sub(-2) == "\\."
        or normalized:sub(-3) == "\\.."
        or normalized:sub(-1) == "\\"
    then
        return nil
    end
    return normalized
end

local function executable_directory(path, style)
    local separator = style == "windows" and "\\" or "/"
    local last
    for index = #path, 1, -1 do
        if path:sub(index, index) == separator then
            last = index
            break
        end
    end
    if not last or last == #path then return nil end
    if style == "linux" and last == 1 then return "/" end
    if style == "windows" and last == 3 and path:sub(2, 3) == ":\\" then
        return path:sub(1, 3)
    end
    return path:sub(1, last - 1)
end

local function join_path(root, leaf, style)
    local separator = style == "windows" and "\\" or "/"
    if root:sub(-1) == separator then return root .. leaf end
    return root .. separator .. leaf
end

---Resolves durable and ephemeral roots from observed executable identities.
-- The outer onefile executable owns adjacent user data. The inner extracted
-- executable owns immutable bundled components; neither root is derived from
-- cwd, PATH text, or a caller-provided resource directory.
-- @param native table Native port exposing executable_paths(argv0).
-- @param argv0 string Original process argv[0] preserved by the onefile launcher.
-- @param target_id string One exact release target id.
-- @return table|nil Immutable runtime layout.
-- @return table|nil Structured layout failure.
function M.resolve_runtime_layout(native, argv0, target_id)
    local style = RUNTIME_TARGETS[target_id]
    if type(native) ~= "table"
        or type(native.executable_paths) ~= "function"
        or type(argv0) ~= "string"
        or argv0 == ""
        or argv0:find("\0", 1, true)
        or not style
    then
        return nil, failure(
            "InvalidExecutableLayout",
            "runtime executable identity inputs are invalid"
        )
    end

    local called, observed = pcall(native.executable_paths, argv0)
    if not called or type(observed) ~= "table" then
        return nil, failure(
            "InvalidExecutableLayout",
            "runtime executable identities could not be observed"
        )
    end
    for key in pairs(observed) do
        if key ~= "application" and key ~= "runtime" then
            return nil, failure(
                "InvalidExecutableLayout",
                "runtime executable identity contains an unknown field"
            )
        end
    end

    local application = normalize_executable_path(observed.application, style)
    local runtime = normalize_executable_path(observed.runtime, style)
    if not application or not runtime then
        return nil, failure(
            "InvalidExecutableLayout",
            "runtime executable paths are not canonical target paths"
        )
    end
    local comparable_application = style == "windows" and application:lower() or application
    local comparable_runtime = style == "windows" and runtime:lower() or runtime
    if comparable_application == comparable_runtime then
        return nil, failure(
            "InvalidExecutableLayout",
            "outer application and inner runtime executables must be distinct"
        )
    end

    local application_root = executable_directory(application, style)
    local runtime_root = executable_directory(runtime, style)
    if not application_root or not runtime_root then
        return nil, failure(
            "InvalidExecutableLayout",
            "runtime executable directories could not be derived"
        )
    end
    local data_root = join_path(application_root, "__yaca__", style)
    local components_root = join_path(runtime_root, ".luai", style)
    components_root = join_path(components_root, "components", style)
    local curl_name = style == "windows" and "curl.exe" or "curl"
    return readonly({
        target_id = target_id,
        application_executable = application,
        runtime_executable = runtime,
        application_root = application_root,
        runtime_root = runtime_root,
        data_root = data_root,
        config_path = join_path(data_root, "config.ini", style),
        curl_executable = join_path(components_root, curl_name, style),
        ca_bundle_path = join_path(components_root, "cacert.pem", style),
    }, "runtime layout")
end

local TARGET_BY_NATIVE_IDENTITY = {
    ["windows\0x86"] = "win32-x86",
    ["windows\0x86_64"] = "win64-x86_64",
    ["linux\0x86_64"] = "linux-x86_64",
}

local function safe_diagnostic(value, maximum_bytes)
    value = type(value) == "string" and value or "internal failure"
    value = value:gsub("[%z\1-\31\127]", "?")
    if #value > maximum_bytes then value = value:sub(1, maximum_bytes) .. "..." end
    return value
end

local function write_direct(writer, bytes)
    local called, result
    if type(writer) == "function" then
        called, result = pcall(writer, bytes)
    elseif type(writer) == "table" and type(writer.write) == "function" then
        called, result = pcall(writer.write, writer, bytes)
    else
        return false
    end
    return called and result ~= nil and result ~= false
end

local function diagnostic(writer, err)
    local code = type(err) == "table" and err.code or "InternalError"
    if type(code) ~= "string" or not code:match("^[A-Za-z][A-Za-z0-9]+$") then
        code = "InternalError"
    end
    local message = type(err) == "table" and err.message or nil
    local line = "yaca: " .. code .. ": " .. safe_diagnostic(message, 1024)
    if type(err) == "table" and type(err.suggestion) == "string" then
        line = line .. " (did you mean " .. safe_diagnostic(err.suggestion, 128) .. "?)"
    end
    return write_direct(writer, line .. "\n")
end

local function copy_arguments(arguments)
    if type(arguments) ~= "table"
        or type(arguments[0]) ~= "string"
        or arguments[0] == ""
        or arguments[0]:find("\0", 1, true)
    then
        return nil, failure("UsageError", "argv[0] and a dense argument array are required")
    end
    local maximum, count = 0, 0
    for key, value in pairs(arguments) do
        if math.type(key) ~= "integer" or key < 0
            or type(value) ~= "string"
            or value:find("\0", 1, true)
        then
            return nil, failure("UsageError", "command arguments must be NUL-free strings")
        end
        if key > 0 then
            count = count + 1
            if key > maximum then maximum = key end
        end
    end
    if maximum ~= count then
        return nil, failure("UsageError", "command arguments must be dense")
    end
    local values = {}
    for index = 1, maximum do values[index] = arguments[index] end
    return { argv0 = arguments[0], values = values }
end

local function default_native_module()
    if type(package) ~= "table"
        or type(package.cpath) ~= "string"
        or type(package.loadlib) ~= "function"
    then
        return nil, failure("NativeLoadFailed", "the bundled native loader is unavailable")
    end
    local template = package.cpath:match("^([^;]+)")
    local path, replacements
    if template then path, replacements = template:gsub("%?", "yaca_native") end
    local normalized = path and path:gsub("\\", "/") or ""
    local expected_suffix = normalized:match("%.dll$")
        and "/.luai/native/yaca_native.dll"
        or "/.luai/native/yaca_native.so"
    if replacements ~= 1
        or not valid_absolute_path(path)
        or normalized:sub(-#expected_suffix) ~= expected_suffix
    then
        return nil, failure(
            "NativeLoadFailed",
            "the first native loader path is not the bundled absolute allowlisted path"
        )
    end
    local loader, load_error = package.loadlib(path, "luaopen_yaca_native")
    if type(loader) ~= "function" then
        return nil, failure("NativeLoadFailed", safe_diagnostic(load_error, 512))
    end
    local called, native = pcall(loader)
    if not called or type(native) ~= "table" then
        return nil, failure("NativeLoadFailed", "the bundled native module could not be opened")
    end
    return native, nil, path
end

local function admit_native(native)
    if type(native) ~= "table"
        or type(native.abi_version) ~= "function"
        or type(native.platform_identity) ~= "function"
        or type(native.stdio_facts) ~= "function"
    then
        return nil, failure("InvalidNativeModule", "native startup functions are incomplete")
    end
    local abi_called, abi = pcall(native.abi_version)
    if not abi_called or abi ~= "yaca-native-v0.1.0" then
        return nil, failure("NativeAbiMismatch", "native ABI does not match this release")
    end
    local identity_called, observed = pcall(native.platform_identity)
    if not identity_called or type(observed) ~= "table" then
        return nil, failure("PlatformProbeFailed", "native platform identity is unavailable")
    end
    for key in pairs(observed) do
        if key ~= "os" and key ~= "arch" then
            return nil, failure("InvalidPlatformIdentity", "native identity has an unknown field")
        end
    end
    local target = TARGET_BY_NATIVE_IDENTITY[
        tostring(observed.os) .. "\0" .. tostring(observed.arch)
    ]
    if not target then
        return nil, failure("UnsupportedPlatform", "native platform is not a release target")
    end
    return {
        os = observed.os,
        arch = observed.arch,
        target = target,
        supported = true,
    }
end

local function new_cli(platform_name)
    local json = require("json")
    local cli = require("cli")
    local codec, codec_error = json.new({
        maximum_bytes = 65536,
        maximum_depth = 16,
        maximum_nodes = 2048,
        maximum_string_bytes = 16384,
        maximum_number_bytes = 64,
    })
    if not codec then return nil, codec_error end
    return cli.new({
        platform = platform_name,
        product_name = "yaca",
        machine_schema_version = "yaca-cli-v0.1.0",
        json_codec = codec,
    })
end

---Runs one complete top-level argv projection and returns its stable exit code.
-- Production loads the native module only from luainstaller's first absolute
-- bundled path. Tests may inject the same narrow native contract and writers.
-- @param arguments table Process arguments including string argv[0].
-- @param ports table|nil Test/runtime injection for native and output writers.
-- @return integer Stable CLI exit code.
function M.run_cli(arguments, ports)
    ports = ports or {}
    local stdout = ports.stdout or function(bytes)
        local result = io.stdout:write(bytes)
        return result ~= nil
    end
    local stderr = ports.stderr or function(bytes)
        local result = io.stderr:write(bytes)
        return result ~= nil
    end
    local invocation, argument_error = copy_arguments(arguments)
    if not invocation then
        diagnostic(stderr, argument_error)
        return 2
    end

    local native, native_error, native_path
    if ports.native ~= nil then
        native = ports.native
        native_path = ports.native_path
    else
        native, native_error, native_path = default_native_module()
    end
    if not native then
        diagnostic(stderr, native_error)
        return 1
    end
    local identity, identity_error = admit_native(native)
    if not identity then
        diagnostic(stderr, identity_error)
        return 1
    end
    if ports.release_target ~= nil and ports.release_target ~= identity.target then
        diagnostic(stderr, failure(
            "PlatformMismatch",
            "the executable does not match its declared release target"
        ))
        return 1
    end

    local cli_service, cli_error = new_cli(identity.os)
    if not cli_service then
        diagnostic(stderr, cli_error)
        return 1
    end
    local facts_called, facts = pcall(native.stdio_facts)
    if not facts_called then
        diagnostic(stderr, failure("PlatformProbeFailed", "stdio facts are unavailable"))
        return 1
    end
    local request, parse_error = cli_service.parse_argv(invocation.values, facts)
    if not request then
        diagnostic(stderr, parse_error)
        return cli_service.exit_code(parse_error)
    end

    local rendered, render_error
    if request.id == "help" then
        local help
        help, render_error = cli_service.render_help(request.topic)
        if help and request.machine == true then
            rendered, render_error = cli_service.machine_result("help", "success", {
                product = "yaca",
                topic = request.topic or "top",
                text = help,
            })
        else
            rendered = help
        end
    elseif request.id == "version" then
        if request.machine == true then
            rendered, render_error = cli_service.machine_result("version", "success", {
                product = "yaca",
                version = "0.1.0",
                release_target = identity.target,
            })
        else
            rendered = "yaca 0.1.0 (" .. identity.target .. ")\n"
        end
    else
        local dispatch = ports.dispatch or default_runtime_dispatch
        if type(dispatch) ~= "function" then
            render_error = failure(
                "RuntimeCompositionUnavailable",
                "the selected action has no composed runtime adapter"
            )
        else
            local called, payload, dispatch_error = pcall(dispatch, request, {
                argv0 = invocation.argv0,
                native = native,
                native_path = native_path or false,
                identity = identity,
                cli = cli_service,
                stdio_facts = facts,
                stdout = stdout,
                stderr = stderr,
            })
            if not called then
                render_error = failure("InternalError", "runtime dispatch raised an exception")
            elseif not payload then
                render_error = dispatch_error or failure(
                    "InternalError",
                    "runtime dispatch returned no result"
                )
            elseif type(payload) == "string" then
                rendered = payload
            elseif type(payload) == "table" and type(payload.output) == "string" then
                rendered = payload.output
                if payload.exit_value ~= nil then render_error = payload.exit_value end
            else
                render_error = failure("InternalError", "runtime dispatch returned invalid output")
            end
        end
    end

    if not rendered then
        diagnostic(stderr, render_error)
        return cli_service.exit_code(render_error)
    end
    local emitted, emit_error = cli_service.emit(stdout, rendered)
    if not emitted then
        diagnostic(stderr, emit_error)
        return cli_service.exit_code(emit_error)
    end
    if render_error ~= nil then return cli_service.exit_code(render_error) end
    return 0
end

local function validate_components(components)
    if type(components) ~= "table" then
        return nil, failure("InvalidBootstrapComponents", "bootstrap components are required")
    end
    local allowed = {
        platform = true,
        config = true,
        workspace = true,
        self_test = true,
        management = true,
        network = true,
        context_catalog = true,
        agent = true,
    }
    for key in pairs(components) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure(
                "InvalidBootstrapComponents",
                "bootstrap components contain an unknown field"
            )
        end
    end
    if type(components.platform) ~= "table"
        or type(components.platform.identity) ~= "function"
        or type(components.config) ~= "table"
        or type(components.config.reload_file) ~= "function"
        or type(components.workspace) ~= "table"
        or type(components.workspace.inspect) ~= "function"
    then
        return nil, failure(
            "InvalidBootstrapComponents",
            "platform, config, and workspace services are incomplete"
        )
    end
    if type(components.self_test) ~= "table"
        or components.self_test.online ~= "explicit-current-invocation-only"
        or components.self_test.auto_fix ~= false
        or type(components.self_test.run) ~= "function"
    then
        return nil, failure(
            "InvalidBootstrapComponents",
            "self-test must declare explicit-consent online and no-auto-fix semantics"
        )
    end
    if type(components.management) ~= "table"
        or components.management.online ~= false
        or type(components.management.run) ~= "function"
    then
        return nil, failure(
            "InvalidBootstrapComponents",
            "management must declare an offline run method"
        )
    end
    return components
end

local function validate_options(options)
    if type(options) ~= "table" then
        return nil, failure("InvalidBootstrapOptions", "bootstrap options are required")
    end
    local allowed = {
        product_name = true,
        product_version = true,
        release_target = true,
        config_path = true,
        maximum_draft_bytes = true,
    }
    for key in pairs(options) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure(
                "InvalidBootstrapOptions",
                "bootstrap options contain an unknown field"
            )
        end
    end
    if type(options.product_name) ~= "string" or options.product_name == ""
        or type(options.product_version) ~= "string" or options.product_version == ""
        or type(options.release_target) ~= "string" or options.release_target == ""
        or not valid_absolute_path(options.config_path)
        or not valid_integer(options.maximum_draft_bytes, 1)
    then
        return nil, failure("InvalidBootstrapOptions", "bootstrap options are incomplete")
    end
    return options
end

local function validate_request(request)
    if type(request) ~= "table" or type(request.id) ~= "string" or request.id == "" then
        return nil, failure("UsageError", "a semantic action id is required")
    end
    local fields = {
        help = { id = true, topic = true, machine = true },
        version = { id = true, machine = true },
        ["self-test"] = {
            id = true,
            through_stage = true,
            list_checks = true,
            excluded_models = true,
            excluded_checks = true,
            selected_checks = true,
            online_consent = true,
            machine = true,
        },
        ["config-repl"] = { id = true },
        ["model-repl"] = { id = true },
        ["context-repl"] = { id = true, view = true },
        ["run-chat"] = { id = true, directory = true },
    }
    local allowed = fields[request.id]
    if not allowed then return nil, failure("UsageError", "semantic action is unsupported") end
    for key in pairs(request) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure("UsageError", "semantic action contains an unknown field")
        end
    end
    if request.machine ~= nil and type(request.machine) ~= "boolean" then
        return nil, failure("UsageError", "machine modifier must be boolean")
    end
    if request.id == "help" and request.topic ~= nil and type(request.topic) ~= "string" then
        return nil, failure("UsageError", "help topic must be a string")
    end
    if request.id == "self-test" then
        local stage = request.through_stage or 1
        if not valid_integer(stage, 1) or stage > 3 then
            return nil, failure("UsageError", "self-test stage must be 1, 2, or 3")
        end
        if request.online_consent ~= nil and type(request.online_consent) ~= "boolean" then
            return nil, failure("UsageError", "online consent must be boolean")
        end
        if request.list_checks ~= nil and type(request.list_checks) ~= "boolean" then
            return nil, failure("UsageError", "self-test list flag must be boolean")
        end
        for _, name in ipairs({
            "excluded_models", "excluded_checks", "selected_checks",
        }) do
            if request[name] ~= nil and not dense_string_array(request[name]) then
                return nil, failure("UsageError", "self-test filters must be string arrays")
            end
        end
    end
    if request.id == "run-chat"
        and request.directory ~= nil
        and type(request.directory) ~= "string"
    then
        return nil, failure("UsageError", "chat directory must be a string")
    end
    return request
end

local function normalize_config_error(config_error)
    if type(config_error) ~= "table" then
        return failure("ConfigInvalid", "the main configuration could not be loaded")
    end
    if config_error.code == "NotFound" then
        return failure(
            "ConfigMissing",
            "the main configuration is missing",
            "Run config-repl or model-repl."
        )
    end
    if config_error.code == "ConfigInvalid" then return config_error end
    return failure(
        "ConfigInvalid",
        "the main configuration could not be loaded",
        "Run config-repl or Stage 1 self-test."
    )
end

---Creates the side-effect-free application composition root.
-- No component method is called until dispatch receives an explicit semantic
-- action. Bootstrap-safe routes never receive the optional network/agent ports.
-- @param components table Injected platform/config/workspace/offline handlers.
-- @param options table Product identity, config path, target, and draft cap.
-- @return table|nil application Immutable application facade.
-- @return table|nil err Structured construction failure.
function M.new(components, options)
    local admitted_components, components_error = validate_components(components)
    if not admitted_components then return nil, components_error end
    local admitted, options_error = validate_options(options)
    if not admitted then return nil, options_error end

    local platform_attempted = false
    local platform_identity
    local platform_error
    local active_draft
    local lifecycle = "constructed"
    local application = {}

    local function check_platform()
        if platform_attempted then return platform_identity, platform_error end
        platform_attempted = true
        local called, identity, identity_error = pcall(admitted_components.platform.identity)
        if not called or not identity then
            platform_error = failure(
                "PlatformMismatch",
                "release platform identity could not be validated"
            )
            return nil, platform_error
        end
        if identity.supported ~= true or identity.target ~= admitted.release_target then
            platform_error = failure(
                "PlatformMismatch",
                "the executable does not match the observed release target"
            )
            return nil, platform_error
        end
        platform_identity = identity
        return identity
    end

    local function load_config()
        local called, generation, config_error = pcall(
            admitted_components.config.reload_file,
            admitted.config_path
        )
        if not called then
            return nil, failure("ConfigInvalid", "configuration loading raised an exception")
        end
        if not generation then return nil, normalize_config_error(config_error) end
        return generation
    end

    local function self_test_snapshot(identity, generation, config_error)
        local config_snapshot
        local models = {}
        local snapshot_id = "self-test-config-unavailable"
        if generation then
            if type(generation.id) ~= "string"
                or type(generation.model_order) ~= "table"
                or type(generation.models) ~= "table"
            then
                return nil, failure(
                    "SelfTestSnapshotInvalid",
                    "configuration generation cannot be projected for self-test"
                )
            end
            snapshot_id = generation.id
            config_snapshot = {
                available = true,
                generation = {
                    id = generation.id,
                    schema_version = generation.schema_version,
                    general = generation.general,
                    tui = generation.tui,
                    agent = generation.agent,
                    network = generation.network,
                    exec = generation.exec,
                    context = generation.context,
                    permissions = generation.permissions,
                    permission_order = generation.permission_order,
                    models = generation.models,
                    model_order = generation.model_order,
                    current_model = generation.current_model,
                    current_permission = generation.current_permission,
                    default_model = generation.default_model,
                    default_permission = generation.default_permission,
                    effective_double_check = generation.effective_double_check,
                    effective_double_check_goal = generation.effective_double_check_goal,
                    context_prompt = generation.context_prompt,
                    auto_rename_disabled = generation.auto_rename_disabled,
                    agent_ready = generation.agent_ready,
                    agent_block_reason = generation.agent_block_reason or false,
                    warnings = generation.warnings,
                },
            }
            local count = 0
            for index, name in ipairs(generation.model_order) do
                count = count + 1
                if index ~= count or type(name) ~= "string" or name == "" then
                    return nil, failure(
                        "SelfTestSnapshotInvalid",
                        "configuration Model order is invalid"
                    )
                end
                local model = generation.models[name]
                if type(model) ~= "table" then
                    return nil, failure(
                        "SelfTestSnapshotInvalid",
                        "configuration Model snapshot is missing"
                    )
                end
                if model.enabled == true then
                    if type(model.endpoint) ~= "string" or model.endpoint == "" then
                        return nil, failure(
                            "SelfTestSnapshotInvalid",
                            "enabled Model endpoint is unavailable"
                        )
                    end
                    models[#models + 1] = {
                        id = name,
                        endpoint = model.endpoint,
                        snapshot_id = generation.id .. ":model:" .. tostring(index),
                    }
                end
            end
            for key in pairs(generation.model_order) do
                if math.type(key) ~= "integer" or key < 1 or key > count then
                    return nil, failure(
                        "SelfTestSnapshotInvalid",
                        "configuration Model order is not dense"
                    )
                end
            end
        else
            config_snapshot = {
                available = false,
                error = {
                    code = config_error and config_error.code or "ConfigInvalid",
                    message = config_error and config_error.message
                        or "configuration is unavailable",
                },
            }
        end
        local raw_snapshot = {
            product = {
                name = admitted.product_name,
                version = admitted.product_version,
                release_target = admitted.release_target,
            },
            platform = {
                os = identity.os,
                arch = identity.arch,
                target = identity.target,
                supported = identity.supported,
            },
            config_path = admitted.config_path,
            config = config_snapshot,
        }
        local copied_snapshot, copied_ok = copy_plain(raw_snapshot, {})
        local copied_models, models_ok = copy_plain(models, {})
        if not copied_ok or not models_ok then
            return nil, failure(
                "SelfTestSnapshotInvalid",
                "self-test snapshot contains a non-data value or cycle"
            )
        end
        local snapshot = freeze(copied_snapshot, {}, "self-test configuration snapshot")
        local frozen_models = freeze(copied_models, {}, "self-test Model snapshots")
        if not snapshot or not frozen_models then
            return nil, failure("SelfTestSnapshotInvalid", "self-test snapshot cannot be frozen")
        end
        return {
            snapshot_id = snapshot_id,
            snapshot = snapshot,
            models = frozen_models,
        }
    end

    local function run_self_test(mode, request, identity, generation, config_error)
        local projection, projection_error = self_test_snapshot(
            identity,
            generation,
            config_error
        )
        if not projection then return nil, projection_error end
        local specification = freeze({
            mode = mode,
            through_stage = request.through_stage or 1,
            list_checks = request.list_checks == true,
            online_consent = request.online_consent == true,
            excluded_models = request.excluded_models or {},
            excluded_checks = request.excluded_checks or {},
            selected_checks = request.selected_checks or {},
            snapshot_id = projection.snapshot_id,
            snapshot = projection.snapshot,
            models = projection.models,
        }, {}, "self-test run specification")
        if not specification then
            return nil, failure("SelfTestSnapshotInvalid", "self-test request contains a cycle")
        end
        local called, result, run_error = pcall(
            admitted_components.self_test.run,
            admitted_components.self_test,
            specification
        )
        if not called then
            return nil, failure("SelfTestFailed", "self-test runner raised an exception")
        end
        if result == nil then
            if type(run_error) == "table" and type(run_error.code) == "string" then
                return nil, run_error
            end
            return nil, failure("SelfTestFailed", "self-test runner returned no result")
        end
        local outcomes = { passed = true, partial = true, cancelled = true, error = true }
        local through_stage = request.through_stage or 1
        if type(result) ~= "table"
            or result.kind ~= "self-test"
            or not outcomes[result.outcome]
            or not valid_integer(result.online_requests, 0)
            or result.auto_fixes ~= 0
            or not valid_integer(result.completed_stage, 0)
            or result.completed_stage > through_stage
            or (through_stage == 1 and result.online_requests ~= 0)
        then
            return nil, failure("SelfTestContract", "self-test runner violated its result contract")
        end
        local frozen = freeze(result, {}, "self-test result")
        if not frozen then
            return nil, failure("SelfTestContract", "self-test result contains a cycle")
        end
        return frozen
    end

    local function dispatch_self_test(request)
        local identity, identity_error = check_platform()
        if not identity then return nil, identity_error end
        local through_stage = request.through_stage or 1
        if through_stage >= 2 and request.list_checks ~= true
            and request.online_consent ~= true
        then
            return nil, failure(
                "OnlineConsentRequired",
                "online self-test requires explicit current-invocation consent"
            )
        end
        local generation, config_error = load_config()
        return run_self_test("explicit", request, identity, generation, config_error)
    end

    local function dispatch_management(request)
        local identity, identity_error = check_platform()
        if not identity then return nil, identity_error end
        local generation, config_error = load_config()
        local context = readonly({
            action = request.id,
            request = request,
            release_target = admitted.release_target,
            config_path = admitted.config_path,
            config_service = admitted_components.config,
            config_generation = generation or false,
            config_error = config_error or false,
            online = false,
        }, "bootstrap management request")
        local called, result = pcall(admitted_components.management.run, context)
        if not called or type(result) ~= "table" or type(result.outcome) ~= "string" then
            return nil, failure(
                "ManagementFailed",
                "bootstrap management returned an invalid result"
            )
        end
        local frozen = freeze(result, {}, "bootstrap management result")
        if not frozen then
            return nil, failure("ManagementFailed", "management result contains a cycle")
        end
        return frozen
    end

    local function run_startup_self_test(generation)
        local requested = generation.general.startup_self_test
        if requested == "off" then return true end
        local stage_by_name = { stage1 = 1, stage2 = 2, stage3 = 3 }
        local through_stage = stage_by_name[requested]
        if not through_stage then
            return nil, failure("StartupSelfTestFailed", "startup self-test setting is invalid")
        end
        if through_stage >= 2 then
            return nil, failure(
                "OnlineConsentRequired",
                "startup online self-test requires visible current-invocation consent"
            )
        end
        local identity, identity_error = check_platform()
        if not identity then return nil, identity_error end
        local result, stage_error = run_self_test("startup", {
            through_stage = through_stage,
            list_checks = false,
            online_consent = false,
            excluded_models = {},
            excluded_checks = {},
            selected_checks = {},
        }, identity, generation)
        if not result then return nil, stage_error end
        if result.outcome ~= "passed" then
            return nil, failure(
                "StartupSelfTestFailed",
                "required startup self-test did not pass"
            )
        end
        return true
    end

    local function dispatch_chat(request)
        if active_draft then
            return nil, failure("SessionActive", "this process already owns an active chat")
        end
        local identity, identity_error = check_platform()
        if not identity then return nil, identity_error end
        local called, workspace, workspace_error = pcall(
            admitted_components.workspace.inspect,
            request.directory or "."
        )
        if not called or not workspace then
            return nil, workspace_error or failure(
                "InvalidWorkspace",
                "the requested workspace could not be inspected"
            )
        end
        local generation, config_error = load_config()
        if not generation then return nil, config_error end
        if generation.agent_ready ~= true then
            return nil, failure(
                "ModelUnavailable",
                "the selected Model cannot start the coding Agent"
            )
        end
        local self_test_ok, self_test_error = run_startup_self_test(generation)
        if not self_test_ok then return nil, self_test_error end
        local draft, draft_error = session.new_draft(generation, workspace, {
            maximum_draft_bytes = admitted.maximum_draft_bytes,
        })
        if not draft then return nil, draft_error end
        active_draft = draft
        lifecycle = "draft-ready"
        return readonly({
            kind = "run-chat",
            outcome = "ready",
            draft = draft,
            status = draft.status(),
        }, "chat bootstrap result")
    end

    ---Dispatches one already-normalized semantic action.
    -- Parsing argv and rendering human/machine output are later adapters.
    function application.dispatch(request)
        if lifecycle == "closed" then
            return nil, failure("ApplicationClosed", "the application lifecycle is closed")
        end
        local admitted_request, request_error = validate_request(request)
        if not admitted_request then return nil, request_error end
        if request.id == "help" then
            return readonly({
                kind = "help",
                outcome = "success",
                topic = request.topic or false,
                product = admitted.product_name,
                bootstrap_actions = readonly({
                    "help", "version", "self-test", "config-repl", "model-repl",
                    "context-repl", "run-chat",
                }, "bootstrap action names"),
            }, "help bootstrap result")
        end
        if request.id == "version" then
            return readonly({
                kind = "version",
                outcome = "success",
                product = admitted.product_name,
                version = admitted.product_version,
                release_target = admitted.release_target,
            }, "version bootstrap result")
        end
        if request.id == "self-test" then return dispatch_self_test(request) end
        if BOOTSTRAP_ACTIONS[request.id] then return dispatch_management(request) end
        return dispatch_chat(request)
    end

    ---Returns lifecycle facts without loading config or scanning Contexts.
    function application.status()
        return readonly({
            lifecycle = lifecycle,
            active_draft = active_draft and active_draft.status() or false,
            platform_checked = platform_attempted,
        }, "application status")
    end

    ---Closes the current in-memory draft and prevents further dispatch.
    function application.close()
        if lifecycle == "closed" then return false end
        if active_draft then active_draft.close() end
        active_draft = nil
        lifecycle = "closed"
        return true
    end

    application.product_name = admitted.product_name
    application.product_version = admitted.product_version
    application.release_target = admitted.release_target
    return readonly(application, "application composition root")
end

local BACKEND_OPTIONS = {
    filesystem = {
        maximum_chunk_bytes = 65536,
        maximum_lease_bytes = 65536,
        maximum_direct_entries = 10000,
    },
    process = {
        maximum_output_bytes = 8 * 1024 * 1024,
        maximum_poll_bytes = 65536,
    },
    terminal = { maximum_input_bytes = 65536 },
}

local SELF_TEST_OPTIONS = {
    maximum_models = 8,
    maximum_filters = 32,
    maximum_results = 128,
    maximum_summary_bytes = 256,
    maximum_evidence_items = 8,
    maximum_evidence_bytes = 256,
    maximum_online_requests = 128,
    maximum_snapshot_nodes = 2048,
    maximum_snapshot_bytes = 65536,
    maximum_identifier_bytes = 128,
}

local CONFIG_REPAIR_TEMPLATE = table.concat({
    "; yaca bootstrap repair template",
    "; This file is intentionally not Agent-ready until Model.Primary is configured",
    "; and explicitly enabled. Run yaca --config-repl after editing to validate it.",
    "",
    "[General]",
    "SchemaVersion = 0.1.0",
    "StartupSelfTest = off",
    "",
    "[Permission.Std]",
    "Read = allow",
    "Write = confirm",
    "Delete = confirm",
    "Shell = confirm",
    "OutsideWorkspace = confirm",
    "",
    "[Permission.Readonly]",
    "Read = allow",
    "Write = deny",
    "Delete = deny",
    "Shell = deny",
    "OutsideWorkspace = deny",
    "",
    "[Model.Primary]",
    "Enabled = false",
    "Protocol = openai-chat",
    "",
}, "\n")

local function config_options(ca_bundle_path)
    return {
        schema_version = "0.1.0",
        release_ca_path = ca_bundle_path,
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
        maximum_hash_chunk_bytes = 65536,
        minimum_scannable_secret_bytes = 8,
        adapter_option_schemas = {},
    }
end

local function exact_identity(value, expected_kind)
    if type(value) ~= "table" then return false end
    local allowed = {
        kind = true,
        volume = true,
        object = true,
        size = true,
        modified = true,
    }
    for key in pairs(value) do
        if type(key) ~= "string" or not allowed[key] then return false end
    end
    return (expected_kind == nil or value.kind == expected_kind)
        and type(value.kind) == "string"
        and type(value.volume) == "string" and value.volume ~= ""
        and type(value.object) == "string" and value.object ~= ""
        and valid_integer(value.size, 0)
        and type(value.modified) == "string" and value.modified ~= ""
end

local function workspace_port(native)
    return readonly({
        inspect = function(requested)
            if type(requested) ~= "string" or requested == ""
                or requested:find("\0", 1, true)
            then
                return nil, failure("InvalidWorkspace", "workspace path is invalid")
            end
            if type(native.workspace_inspect) ~= "function" then
                return nil, failure(
                    "InvalidWorkspace",
                    "native workspace inspection is unavailable"
                )
            end
            local called, observed = pcall(native.workspace_inspect, requested)
            if not called or type(observed) ~= "table" then
                return nil, failure(
                    "InvalidWorkspace",
                    "the requested workspace is not an enterable directory"
                )
            end
            for key in pairs(observed) do
                if key ~= "path" and key ~= "enterable" and key ~= "identity" then
                    return nil, failure(
                        "InvalidWorkspace",
                        "native workspace inspection returned an unknown field"
                    )
                end
            end
            if not valid_absolute_path(observed.path)
                or observed.enterable ~= true
                or not exact_identity(observed.identity, "directory")
            then
                return nil, failure(
                    "InvalidWorkspace",
                    "native workspace inspection returned invalid facts"
                )
            end
            return readonly({
                path = observed.path,
                enterable = true,
                identity = readonly({
                    kind = observed.identity.kind,
                    volume = observed.identity.volume,
                    object = observed.identity.object,
                    size = observed.identity.size,
                    modified = observed.identity.modified,
                }, "workspace identity"),
            }, "workspace observation")
        end,
    }, "workspace service")
end

local function build_context_services(native, filesystem)
    local safety = require("safety")
    local xml = require("xml")
    local context = require("context")
    local safety_service, safety_error = safety.new(native, {
        maximum_hash_chunk_bytes = 65536,
        minimum_scannable_secret_bytes = 8,
    })
    if not safety_service then return nil, safety_error end
    local loaded, lxp = pcall(require, "lxp")
    if not loaded then
        return nil, failure("XmlDependencyFailure", "the bundled LuaExpat module did not load")
    end
    local codec, codec_error = xml.new({
        lxp = lxp,
        maximum_bytes = 1024 * 1024,
        maximum_depth = 32,
        maximum_elements = 4096,
        maximum_attributes_per_element = 8,
        maximum_text_node_bytes = 131072,
        maximum_total_text_bytes = 512 * 1024,
        maximum_sax_events = 16384,
        maximum_context_events = 256,
        maximum_carrier_bytes = 65536,
        maximum_chunk_bytes = 65536,
    })
    if not codec then return nil, codec_error end
    local schema, schema_error = context.new({
        xml = codec,
        safety = safety_service,
        maximum_name_bytes = 256,
        maximum_identifier_bytes = 256,
        maximum_field_name_bytes = 64,
        maximum_field_bytes = 65536,
        maximum_events = 256,
        maximum_compaction_records = 64,
        maximum_export_bytes = 1024 * 1024,
    })
    if not schema then return nil, schema_error end
    local store, store_error = context.new_store(schema, { filesystem = filesystem }, {
        maximum_context_bytes = 1024 * 1024,
        maximum_lock_hostname_bytes = 64,
        maximum_temp_nonce_bytes = 32,
        context_permissions = 384,
        lock_permissions = 384,
    })
    if not store then return nil, store_error end
    return readonly({
        safety = safety_service,
        xml = codec,
        schema = schema,
        store = store,
    }, "Context runtime services")
end

local function read_file_bytes(filesystem, path, maximum_bytes)
    local opened, handle_or_error = filesystem.open_read(path)
    if not opened then return nil, handle_or_error end
    local handle = handle_or_error
    local stated, identity_or_error = filesystem.stat_identity(handle)
    if not stated then
        filesystem.close(handle)
        return nil, identity_or_error
    end
    if identity_or_error.kind ~= "file" or identity_or_error.size > maximum_bytes then
        filesystem.close(handle)
        return nil, failure("FileTooLarge", "file is not an admitted bounded ordinary file")
    end
    local chunks, total = {}, 0
    while true do
        local read, chunk_or_error = filesystem.stream_read(
            handle,
            filesystem.capabilities.maximum_chunk_bytes
        )
        if not read then
            filesystem.close(handle)
            return nil, chunk_or_error
        end
        total = total + #chunk_or_error.bytes
        if total > maximum_bytes then
            filesystem.close(handle)
            return nil, failure("FileTooLarge", "file changed beyond its admitted bound")
        end
        chunks[#chunks + 1] = chunk_or_error.bytes
        if chunk_or_error.eof then break end
    end
    local closed, close_error = filesystem.close(handle)
    if not closed then return nil, close_error end
    return table.concat(chunks), identity_or_error
end

local function file_digest(filesystem, safety_service, path, maximum_bytes)
    local bytes, read_error = read_file_bytes(filesystem, path, maximum_bytes)
    if not bytes then return nil, read_error end
    return safety_service.digest(bytes)
end

local function check_result(outcome, summary, evidence)
    return {
        outcome = outcome,
        summary = summary,
        evidence = evidence or {},
        online_requests = 0,
        auto_fixes = 0,
    }
end

local function build_offline_self_test(runtime)
    local filesystem = runtime.backend.filesystem
    local layout = runtime.layout
    local context_services = runtime.context_services
    local context_error = runtime.context_error
    local native = runtime.native
    local facts = runtime.stdio_facts

    local function stat_file(path)
        local stated, value = filesystem.stat_identity(path)
        return stated and value.kind == "file", value
    end

    return function(specification)
        local id = specification.check.id
        if id == "ST1-PLATFORM" then
            if runtime.identity.target == layout.target_id then
                return check_result("passed", "release platform identity matches", {
                    "target=" .. runtime.identity.target,
                })
            end
            return check_result("failed", "release platform identity does not match")
        end
        if id == "ST1-PACKAGE" then
            local application_ok = stat_file(layout.application_executable)
            local runtime_ok = stat_file(layout.runtime_executable)
            local curl_ok = stat_file(layout.curl_executable)
            if application_ok and runtime_ok and curl_ok then
                return check_result("passed", "minimal package files are present", {
                    "outer-executable=present",
                    "inner-runtime=present",
                    "curl=present",
                })
            end
            return check_result("failed", "one or more required package files are unavailable")
        end
        if id == "ST1-SAFE-LOAD" then
            local native_path = runtime.native_path
            local normalized = type(native_path) == "string" and native_path:gsub("\\", "/") or ""
            local native_ok = normalized:match("/%.luai/native/yaca_native%.[a-z]+$") ~= nil
                and stat_file(native_path)
            if native_ok then
                return check_result("passed", "native module came from the bundled allowlist", {
                    "native-loader=absolute-bundled",
                })
            end
            return check_result("failed", "native module load identity is unavailable")
        end
        if id == "ST1-DATA-ROOT" then
            local stated, value = filesystem.stat_identity(layout.data_root)
            if stated and value.kind == "directory" then
                return check_result("passed", "adjacent data root is available", {
                    "data-root=directory",
                })
            end
            return check_result("failed", "adjacent data root is missing or inaccessible")
        end
        if id == "ST1-CONFIG-SCHEMA" then
            local config = specification.snapshot.config
            if config.available == true
                and config.generation.schema_version == "0.1.0"
            then
                return check_result("passed", "configuration schema is current", {
                    "schema=0.1.0",
                })
            end
            return check_result("failed", "configuration schema is unavailable or invalid")
        end
        if id == "ST1-CONFIG-SOURCE" then
            local config = specification.snapshot.config
            if config.available == true then
                local ok = stat_file(layout.config_path)
                if ok then
                    return check_result("passed", "configuration source is a bounded file", {
                        "config-source=present",
                    })
                end
            end
            return check_result("failed", "configuration source cannot be verified")
        end
        if id == "ST1-ATOMIC-WRITE" then
            local capabilities = filesystem.capabilities
            if capabilities.atomic_replace_candidate
                and capabilities.rename_no_replace_candidate
                and capabilities.verified_delete_candidate
            then
                return check_result(
                    "unknown",
                    "publication primitives still require target qualification",
                    { "qualification=pending-target-evidence" }
                )
            end
            return check_result("failed", "required publication primitives are unavailable")
        end
        if id == "ST1-CONTEXT-CODEC" then
            if context_services then
                return check_result("passed", "pinned Context XML codec loaded", {
                    "luaexpat=1.5.2",
                    "expat=2.8.2",
                })
            end
            return check_result("failed", "pinned Context XML codec is unavailable", {
                "reason=" .. safe_diagnostic(context_error and context_error.code, 96),
            })
        end
        if id == "ST1-CONTEXT-SCHEMA" then
            if context_services then
                return check_result("passed", "Context schema service constructed", {
                    "context-schema=0.1.0",
                })
            end
            return check_result("failed", "Context schema service is unavailable")
        end
        if id == "ST1-CONTEXT-CATALOG" then
            return check_result(
                "unknown",
                "Context catalog scanner is not yet attached to the runtime",
                { "catalog=unavailable" }
            )
        end
        if id == "ST1-CONTEXT-LOCK" then
            return check_result(
                "unknown",
                "Context lock probe requires the composed catalog",
                { "lock-probe=not-run" }
            )
        end
        if id == "ST1-TOOLS" then
            if filesystem.capabilities.verified_direct_candidate == true then
                return check_result("passed", "verified direct filesystem tools are available", {
                    "direct-filesystem=complete",
                })
            end
            return check_result("failed", "verified direct filesystem tools are unavailable", {
                "direct-filesystem=incomplete",
            })
        end
        if id == "ST1-CA-BUNDLE" then
            if not context_services then
                return check_result("failed", "CA bundle digest service is unavailable")
            end
            local digest = file_digest(
                filesystem,
                context_services.safety,
                layout.ca_bundle_path,
                4 * 1024 * 1024
            )
            if digest == "f66dff1bdf8f96060b8177976f8b7d9254bc89bc4db933d769f7384d28480bc9" then
                return check_result("passed", "bundled CA certificate set matches the lock", {
                    "ca-bundle=2026-08-13",
                })
            end
            return check_result("failed", "bundled CA certificate set does not match the lock")
        end
        if id == "ST1-TTY-INPUT" then
            if type(facts) == "table" and facts.stdin_is_tty == true then
                return check_result("passed", "interactive terminal input is available", {
                    "stdin-tty=true",
                })
            end
            return check_result("warning", "interactive terminal input is unavailable", {
                "stdin-tty=false",
            })
        end
        if id == "ST1-ZERO-SURFACE" then
            local forbidden = {
                "web", "audio", "image", "remote", "plugin", "mcp", "telemetry", "update",
            }
            for _, descriptor in ipairs(runtime.cli.registry()) do
                local lowered = descriptor.id:lower()
                for _, token in ipairs(forbidden) do
                    if lowered:find(token, 1, true) then
                        return check_result("failed", "excluded product surface is present")
                    end
                end
            end
            return check_result("passed", "excluded product surfaces are absent", {
                "public-actions=39",
            })
        end
        return check_result("failed", "offline check has no composed implementation")
    end
end

local function cleanup_created_file(filesystem, path)
    local stated, identity = filesystem.stat_identity(path)
    if not stated then
        return type(identity) == "table" and identity.code == "NotFound"
    end
    return filesystem.delete_verified(path, identity)
end

local function ensure_data_root(filesystem, path, parent_path)
    local stated, identity_or_error = filesystem.stat_identity(path)
    if stated then
        if identity_or_error.kind ~= "directory" then
            return nil, failure("DataRootConflict", "the adjacent data root is not a directory")
        end
        return false
    end
    if type(identity_or_error) ~= "table" or identity_or_error.code ~= "NotFound" then
        return nil, identity_or_error
    end
    local created, create_error = filesystem.make_directory(path, 448)
    if not created then return nil, create_error end
    local flushed, flush_error = filesystem.flush_directory(parent_path)
    if not flushed then
        return nil, failure(
            "PublicationUnknown",
            "data root creation durability is unknown",
            flush_error.code
        )
    end
    return true
end

local function publish_repair_template(filesystem, layout)
    local created_root, root_error = ensure_data_root(
        filesystem,
        layout.data_root,
        layout.application_root
    )
    if created_root == nil then return nil, root_error end
    local temporary_path = layout.config_path .. ".yaca-new.tmp"
    local created, handle_or_error = filesystem.create_new(temporary_path, 384)
    if not created then
        return nil, failure(
            "TemporaryConflict",
            "the fixed configuration publication temporary is occupied",
            handle_or_error and handle_or_error.code
        )
    end
    local handle = handle_or_error
    local function abort(original)
        filesystem.close(handle)
        local cleaned = cleanup_created_file(filesystem, temporary_path)
        if not cleaned then
            return nil, failure(
                "PublicationUnknown",
                "configuration template cleanup could not be proven",
                original and original.code
            )
        end
        return nil, original
    end
    local offset = 1
    while offset <= #CONFIG_REPAIR_TEMPLATE do
        local bytes = CONFIG_REPAIR_TEMPLATE:sub(
            offset,
            offset + filesystem.capabilities.maximum_chunk_bytes - 1
        )
        local written, write_error = filesystem.stream_write(handle, bytes)
        if not written then return abort(write_error) end
        offset = offset + #bytes
    end
    local flushed, flush_error = filesystem.flush_file(handle)
    if not flushed then return abort(flush_error) end
    local stated, identity_or_error = filesystem.stat_identity(handle)
    if not stated or identity_or_error.kind ~= "file"
        or identity_or_error.size ~= #CONFIG_REPAIR_TEMPLATE
    then
        return abort(stated and failure(
            "PublicationValidation",
            "configuration template size is invalid"
        ) or identity_or_error)
    end
    local closed, close_error = filesystem.close(handle)
    if not closed then
        local cleaned = cleanup_created_file(filesystem, temporary_path)
        if not cleaned then
            return nil, failure(
                "PublicationUnknown",
                "configuration template close and cleanup are unknown"
            )
        end
        return nil, close_error
    end
    handle = false
    local observed, observed_identity = read_file_bytes(
        filesystem,
        temporary_path,
        #CONFIG_REPAIR_TEMPLATE
    )
    if observed == nil then
        cleanup_created_file(filesystem, temporary_path)
        return nil, observed_identity
    end
    if observed ~= CONFIG_REPAIR_TEMPLATE then
        cleanup_created_file(filesystem, temporary_path)
        return nil, failure(
            "PublicationValidation",
            "configuration template bytes changed before publication"
        )
    end
    local published, publish_error = filesystem.rename_no_replace(
        temporary_path,
        layout.config_path
    )
    if not published then
        cleanup_created_file(filesystem, temporary_path)
        return nil, publish_error
    end
    local directory_flushed, directory_error = filesystem.flush_directory(layout.data_root)
    if not directory_flushed then
        return nil, failure(
            "PublicationUnknown",
            "configuration template publication durability is unknown",
            directory_error.code
        )
    end
    return readonly({ created_data_root = created_root }, "template publication result")
end

local function management_service(filesystem, layout)
    local service = { online = false }
    function service.run(context)
        if context.action == "config-repl" then
            if context.config_generation then
                return {
                    outcome = "success",
                    action = context.action,
                    state = "valid",
                    config_path = layout.config_path,
                }
            end
            if context.config_error and context.config_error.code == "ConfigMissing" then
                local published, publish_error = publish_repair_template(filesystem, layout)
                if not published then
                    return {
                        outcome = "error",
                        action = context.action,
                        state = "publication-failed",
                        error_code = publish_error.code,
                        config_path = layout.config_path,
                    }
                end
                return {
                    outcome = "success",
                    action = context.action,
                    state = "repair-template-created",
                    config_path = layout.config_path,
                    created_data_root = published.created_data_root,
                }
            end
            return {
                outcome = "action-required",
                action = context.action,
                state = "invalid",
                error_code = context.config_error and context.config_error.code or "ConfigInvalid",
                config_path = layout.config_path,
            }
        end
        if context.action == "model-repl" then
            return {
                outcome = "action-required",
                action = context.action,
                state = context.config_generation and "edit-required" or "config-repair-required",
                config_path = layout.config_path,
            }
        end
        return {
            outcome = "error",
            action = context.action,
            state = "catalog-unavailable",
            error_code = "ContextCatalogUnavailable",
        }
    end
    return service
end

---Composes production adapters for one already-admitted packaged invocation.
-- Construction resolves all mutable and immutable roots from native executable
-- identities; it never derives them from cwd or ambient environment variables.
function M.compose_runtime(runtime)
    if type(runtime) ~= "table"
        or type(runtime.native) ~= "table"
        or type(runtime.identity) ~= "table"
        or type(runtime.argv0) ~= "string"
        or type(runtime.cli) ~= "table"
    then
        return nil, failure("InvalidRuntimeComposition", "runtime composition inputs are incomplete")
    end
    local layout, layout_error = M.resolve_runtime_layout(
        runtime.native,
        runtime.argv0,
        runtime.identity.target
    )
    if not layout then return nil, layout_error end
    local backend_module = runtime.identity.os == "windows"
        and require("backend_windows") or require("backend_linux")
    local backend, backend_error = backend_module.new(
        runtime.native,
        runtime.identity,
        BACKEND_OPTIONS
    )
    if not backend then return nil, backend_error end
    local config = require("config")
    local config_service, config_error = config.new({
        sha256 = runtime.native,
        filesystem = backend.filesystem,
    }, config_options(layout.ca_bundle_path))
    if not config_service then return nil, config_error end
    local contexts, contexts_error = build_context_services(
        runtime.native,
        backend.filesystem
    )
    local composed = {
        native = runtime.native,
        native_path = runtime.native_path,
        stdio_facts = runtime.stdio_facts,
        identity = runtime.identity,
        cli = runtime.cli,
        layout = layout,
        backend = backend,
        context_services = contexts,
        context_error = contexts_error,
    }
    local diagnostics = require("diagnostics")
    local self_test, self_test_error = diagnostics.new_self_test({
        offline = {
            online = false,
            run = build_offline_self_test(composed),
        },
        model = {
            online = true,
            run = function()
                return check_result(
                    "failed",
                    "online Model qualification adapter is not yet composed"
                )
            end,
        },
        advisory = {
            online = true,
            auto_fix = false,
            run = function()
                return check_result(
                    "failed",
                    "online advisory adapter is not yet composed"
                )
            end,
        },
    }, SELF_TEST_OPTIONS)
    if not self_test then return nil, self_test_error end
    local application, application_error = M.new({
        platform = { identity = function() return runtime.identity end },
        config = config_service,
        workspace = workspace_port(runtime.native),
        self_test = self_test,
        management = management_service(backend.filesystem, layout),
    }, {
        product_name = "yaca",
        product_version = "0.1.0",
        release_target = runtime.identity.target,
        config_path = layout.config_path,
        maximum_draft_bytes = 16384,
    })
    if not application then return nil, application_error end
    return readonly({
        application = application,
        layout = layout,
        backend = backend,
        config = config_service,
        contexts = contexts or false,
        context_error = contexts_error or false,
    }, "production runtime composition")
end

local function render_self_test(cli_service, request, result)
    if request.machine == true then
        local records = {}
        if result.listed then
            for _, item in ipairs(result.checks) do
                records[#records + 1] = {
                    check_id = item.id,
                    stage = item.stage,
                    required = item.required,
                    online = item.online,
                    owner = item.owner,
                }
            end
        else
            for _, item in ipairs(result.results) do
                records[#records + 1] = {
                    check_id = item.check_id,
                    stage = item.stage,
                    required = item.required,
                    online = item.online,
                    owner = item.owner,
                    model_id = item.model_id,
                    state = item.outcome,
                    summary = item.summary,
                    evidence = item.evidence,
                    excluded = item.excluded,
                    advisory = item.advisory,
                }
            end
        end
        records[#records + 1] = {
            outcome = result.outcome,
            completed_stage = result.completed_stage,
            online_requests = result.online_requests,
            auto_fixes = result.auto_fixes,
            listed = result.listed,
        }
        return cli_service.machine_stream("self-test", records)
    end
    local lines = {}
    if result.listed then
        for _, item in ipairs(result.checks) do
            lines[#lines + 1] = string.format(
                "%s stage=%d required=%s online=%s owner=%s",
                item.id,
                item.stage,
                tostring(item.required),
                tostring(item.online),
                item.owner
            )
        end
    else
        for _, item in ipairs(result.results) do
            lines[#lines + 1] = string.format(
                "%s %-9s %s",
                item.check_id,
                item.outcome:upper(),
                item.summary
            )
        end
    end
    lines[#lines + 1] = string.format(
        "self-test outcome=%s completed-stage=%d online-requests=%d auto-fixes=%d",
        result.outcome,
        result.completed_stage,
        result.online_requests,
        result.auto_fixes
    )
    return table.concat(lines, "\n") .. "\n"
end

local function render_management(request, result)
    if result.action == "config-repl" then
        if result.state == "repair-template-created" then
            return "Created an offline repair template at "
                .. safe_diagnostic(result.config_path, 1024)
                .. ". Edit Model.Primary, set Enabled=true, then run config-repl again.\n"
        end
        if result.state == "valid" then
            return "Configuration is valid: "
                .. safe_diagnostic(result.config_path, 1024) .. "\n"
        end
        return "Configuration requires repair: "
            .. safe_diagnostic(result.config_path or "unknown", 1024)
            .. " (" .. safe_diagnostic(result.error_code or result.state, 128) .. ")\n"
    end
    if result.action == "model-repl" then
        return "Model configuration requires an explicit edit of "
            .. safe_diagnostic(result.config_path, 1024)
            .. "; the interactive secret editor is not yet available.\n"
    end
    return "Context management is unavailable until the runtime catalog is composed.\n"
end

local function render_runtime_result(cli_service, request, result)
    if request.id == "self-test" then return render_self_test(cli_service, request, result) end
    if BOOTSTRAP_ACTIONS[request.id] then return render_management(request, result) end
    local status = result.status
    return table.concat({
        "New chat draft is ready (not saved).",
        "Workspace: " .. safe_diagnostic(status.workspace, 1024),
        "Model: " .. safe_diagnostic(status.model, 256),
        "Permission: " .. safe_diagnostic(status.permission, 256),
        "The interactive Agent loop is not yet attached; no message was accepted.",
        "",
    }, "\n")
end

default_runtime_dispatch = function(request, runtime)
    local composed, composition_error = M.compose_runtime(runtime)
    if not composed then return nil, composition_error end
    local result, dispatch_error = composed.application.dispatch(request)
    if not result then return nil, dispatch_error end
    local output, render_error = render_runtime_result(runtime.cli, request, result)
    if not output then return nil, render_error end
    local successful = result.outcome == "success"
        or result.outcome == "ready"
        or result.outcome == "passed"
    return { output = output, exit_value = successful and nil or result }
end

if MODULE_NAME == nil and _G.YACA_TEST_ROOT == nil then
    os.exit(M.run_cli(arg), true)
end

return M
